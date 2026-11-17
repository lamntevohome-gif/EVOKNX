// EvoKNX Box: runs the timers (schedules and countdowns) that the EvoKNX Editor sends, when the App is closed.
//   - reaches the KNX bus by routing (KNX IP Router) or tunneling (KNX IP Interface)
//   - keeps the timers and a log of the last 7 days in its own flash (no SD card)
//   - the Editor gives the box a hidden key once (claim, home network only); after that every change needs a signature made with
//     that key (HMAC-SHA256; the key itself never travels). Reading is open from the home network (the read-only web page).
//   - the phone makes the timers and sends them; the Editor sends the settings (name, time zone, how to reach the bus)
#include <Arduino.h>
#include <ArduinoJson.h>
#include <ArduinoOTA.h>
#include <ETH.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <SPI.h>
#include <WebServer.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <esp_random.h>
#include <esp_sntp.h>
#include <esp_task_wdt.h>
#include <esp_timer.h>
#include <mbedtls/md.h>
#include <sys/time.h>
#include <time.h>
#include <string>

#include "board.h"
#include "bus.h"
#include "core/access.h"
#include "core/box_config.h"
#include "core/event_log.h"
#include "core/scheduler.h"
#include "web_page.h"

using namespace evo;

static const uint16_t kDiscoveryPort = 47803;

static WebServer server(80);
static WiFiUDP disc;
static Preferences prefs;

static BoxCfg cfg;
static std::string rawConfig = "{\"v\":1,\"timers\":[],\"ui\":[]}";  // the timers as received (with "ui")
static Scheduler sched;
static EventLog elog;
static KnxBus* bus = nullptr;

static String boxKey;  // 32 capital hex digits; empty = nobody has claimed the box yet
static String ntpServer = "pool.ntp.org";
static String chipId;
static bool ntpSynced = false, syncFlag = false, bootPending = true, servicesStarted = false, netUp = false, otaStarted = false;
static IPAddress lastIp;

// ------------------------------------------------------------------------------------------------------------ time

static uint64_t monoMs() { return (uint64_t)(esp_timer_get_time() / 1000); }
static uint32_t nowUtc() { return (uint32_t)time(nullptr); }
static bool timeValid() { return nowUtc() > kMinValidEpoch; }

static IPAddress localIp() {
#ifdef USE_WIFI
  return WiFi.status() == WL_CONNECTED ? WiFi.localIP() : IPAddress();
#else
  return ETH.linkUp() ? ETH.localIP() : IPAddress();
#endif
}

static String localTimeString() {
  time_t t = (time_t)nowUtc() + (time_t)cfg.tzMin * 60;
  struct tm tmv;
  gmtime_r(&t, &tmv);
  char b[24];
  strftime(b, sizeof(b), "%Y-%m-%d %H:%M:%S", &tmv);
  return String(b);
}

static void onSynced(struct timeval*) { syncFlag = true; }

static void applyNtp() {
  sntp_set_time_sync_notification_cb(onSynced);
  configTime(0, 0, ntpServer.c_str(), "pool.ntp.org", "time.google.com");  // the offset is added by the box itself (cfg.tzMin)
}

// ------------------------------------------------------------------------------------------------------------ log

static void appendLogLine(const std::string& line) {
  File f = LittleFS.open("/log.txt", "a");
  if (!f) return;
  f.print(line.c_str());
  f.close();
}

static void logEvent(char k, const std::string& x) {
  uint32_t t = timeValid() ? nowUtc() : 0;
  elog.add(t, k, x);
  Event e;
  e.t = t;
  e.k = k;
  e.x = x;
  appendLogLine(eventLine(e));
  Serial.printf("[%c] %s\n", k, x.c_str());
}

static void loadLog() {
  File f = LittleFS.open("/log.txt", "r");
  if (!f) return;
  while (f.available()) {
    String l = f.readStringUntil('\n');
    Event e;
    if (parseEventLine(std::string(l.c_str()), e)) elog.add(e.t, e.k, e.x);
  }
  f.close();
}

// Rewrites the file with what is left after the events older than 7 days were dropped (about once a day).
static void compactLog() {
  File f = LittleFS.open("/log.tmp", "w");
  if (!f) return;
  for (const Event& e : elog.events()) f.print(eventLine(e).c_str());
  f.close();
  LittleFS.remove("/log.txt");
  LittleFS.rename("/log.tmp", "/log.txt");
}

// ------------------------------------------------------------------------------------------------------------ settings

// Writes a file so that a power cut in the middle never leaves a broken file: first a temporary file, checked, then renamed; the old
// one stays as .bak.
static bool saveFile(const char* path, const char* bak, const std::string& json) {
  File f = LittleFS.open("/save.tmp", "w");
  if (!f) return false;
  size_t n = f.write((const uint8_t*)json.data(), json.size());
  f.close();
  File r = LittleFS.open("/save.tmp", "r");
  size_t back = r ? r.size() : 0;
  if (r) r.close();
  if (n != json.size() || back != json.size()) {
    LittleFS.remove("/save.tmp");
    return false;
  }
  LittleFS.remove(bak);
  if (LittleFS.exists(path)) LittleFS.rename(path, bak);
  return LittleFS.rename("/save.tmp", path);
}

static bool readFile(const char* path, std::string& out) {
  File f = LittleFS.open(path, "r");
  if (!f) return false;
  String s = f.readString();
  f.close();
  out = s.c_str();
  return !out.empty();
}

static void startBus() {
  IPAddress ip = localIp();
  if (ip == IPAddress()) return;
  delete bus;
  if (cfg.bus.tunnel) {
    bus = new TunnelBus();
  } else {
    bus = new RoutingBus();
  }
  bus->onGroup = [](const Group& g) { sched.onTelegram(g, monoMs(), [](char k, const std::string& x) { logEvent(k, x); }); };
  bus->onUp = [](bool up, const char* why) { logEvent(up ? 'U' : 'D', why); };
  bus->begin(cfg.bus, ip);
}

static void applyConfig(const BoxCfg& nc) {
  bool busChanged = bus == nullptr || nc.bus.tunnel != cfg.bus.tunnel || nc.bus.host != cfg.bus.host || nc.bus.port != cfg.bus.port;
  cfg = nc;
  sched.setConfig(cfg);
  if (busChanged) startBus();
}

static void loadConfig() {
  for (const char* path : {"/settings.json", "/settings.bak"}) {
    std::string json, err;
    BoxCfg c = cfg;
    if (readFile(path, json) && parseSettings(json, c, err)) {
      cfg = c;
      break;
    }
  }
  for (const char* path : {"/config.json", "/config.bak"}) {
    std::string json, err;
    BoxCfg c = cfg;
    if (readFile(path, json) && parseTimers(json, c, err)) {
      rawConfig = json;
      cfg = c;
      break;
    }
  }
  sched.setConfig(cfg);
}

// ------------------------------------------------------------------------------------------------------------ key and signing

static bool claimed() { return boxKey.length() == 32; }

static String hmacHex(const String& key, const String& msg) {
  uint8_t out[32];
  const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  mbedtls_md_hmac(info, (const uint8_t*)key.c_str(), key.length(), (const uint8_t*)msg.c_str(), msg.length(), out);
  static const char* h = "0123456789abcdef";
  String s;
  for (int i = 0; i < 32; i++) {
    s += h[out[i] >> 4];
    s += h[out[i] & 15];
  }
  return s;
}

static bool sameText(const String& a, const String& b) {
  if (a.length() != b.length()) return false;
  uint8_t d = 0;
  for (size_t i = 0; i < a.length(); i++) d |= (uint8_t)(a[i] ^ b[i]);
  return d == 0;
}

struct Nonce {
  char v[33] = {0};
  uint32_t exp = 0;
};
static Nonce nonces[4];

static String newNonce() {
  uint8_t r[16];
  esp_fill_random(r, sizeof(r));
  static const char* h = "0123456789abcdef";
  char s[33];
  for (int i = 0; i < 16; i++) {
    s[2 * i] = h[r[i] >> 4];
    s[2 * i + 1] = h[r[i] & 15];
  }
  s[32] = 0;
  int slot = 0;
  for (int i = 0; i < 4; i++) {
    if (nonces[i].v[0] == 0 || (int32_t)(nonces[i].exp - millis()) <= 0) {
      slot = i;
      break;
    }
    if ((int32_t)(nonces[i].exp - nonces[slot].exp) < 0) slot = i;
  }
  memcpy(nonces[slot].v, s, 33);
  nonces[slot].exp = millis() + 30000;
  return String(s);
}

static bool takeNonce(const String& n) {
  for (auto& s : nonces) {
    if (s.v[0] && n.equals(s.v) && (int32_t)(s.exp - millis()) > 0) {
      s.v[0] = 0;
      return true;
    }
  }
  return false;
}

static uint8_t failCount = 0;
static uint32_t failSince = 0;

static void sendJson(int code, const String& body) {
  server.sendHeader("Cache-Control", "no-store");
  server.send(code, "application/json", body);
}

static void sendError(int code, const String& msg) {
  JsonDocument d;
  d["error"] = msg;
  String o;
  serializeJson(d, o);
  sendJson(code, o);
}

static bool fromLan() {
  IPAddress r = server.client().remoteIP();
  return isPrivateV4(r[0], r[1]);
}

// Checks that the call is allowed: reading is open from the home network; everything else needs the signature made with the key.
// Sends the error itself when it is not allowed.
static bool authOk() {
  bool post = server.method() != HTTP_GET;
  Need need = accessFor(post, claimed(), fromLan());
  if (need == Need::Open) return true;
  if (need == Need::Deny) {
    sendError(403, post ? "The box has no key yet. Press Connect in the Editor (Connections > EvoKNX Box) from the home network." : "Open this from the home network.");
    return false;
  }
  if (failCount >= 8 && millis() - failSince < 60000) {
    sendError(429, "Too many wrong attempts. Wait a minute.");
    return false;
  }
  if (millis() - failSince >= 60000) failCount = 0;
  String nonce = server.header("X-Nonce"), sig = server.header("X-Sig");
  String body;
  if (post) body = server.arg("plain");
  bool ok = nonce.length() == 32 && takeNonce(nonce) && sameText(hmacHex(boxKey, nonce + "\n" + (post ? "POST" : "GET") + "\n" + server.uri() + "\n" + body), sig);
  if (!ok) {
    if (failCount == 0) failSince = millis();
    failCount++;
    sendError(401, "The key is not correct.");
    return false;
  }
  failCount = 0;
  return true;
}

// ------------------------------------------------------------------------------------------------------------ the web API

static bool sendEvent(uint16_t ga, const Payload& p) { return bus && bus->send(ga, p); }
static void logFn(char k, const std::string& x) { logEvent(k, x); }

static void handleInfo() {
  JsonDocument d;
  d["app"] = "evoknx-box";
  d["name"] = cfg.name;
  d["fw"] = FW_VERSION;
  d["id"] = chipId;
  d["claimed"] = claimed();
  String o;
  serializeJson(d, o);
  sendJson(200, o);
}

static void handleChallenge() {
  JsonDocument d;
  d["nonce"] = newNonce();
  String o;
  serializeJson(d, o);
  sendJson(200, o);
}

static void handleStatus() {
  if (!authOk()) return;
  JsonDocument d;
  d["fw"] = FW_VERSION;
  d["name"] = cfg.name;
  d["id"] = chipId;
  d["mode"] = bus ? bus->mode() : (cfg.bus.tunnel ? "tunnel" : "routing");
  d["busUp"] = bus && bus->up();
  d["busErr"] = bus ? bus->error.c_str() : "waiting for the network";
  d["rxAgo"] = (bus && bus->everRx) ? (long)((millis() - bus->lastRxMs) / 1000) : -1L;
  d["txAgo"] = (bus && bus->everTx) ? (long)((millis() - bus->lastTxMs) / 1000) : -1L;
  d["timeOk"] = timeValid();
  d["time"] = localTimeString();
  d["utc"] = nowUtc();
  d["tz"] = cfg.tzMin;
  d["claimed"] = claimed();
  d["ntp"] = ntpServer;
  d["ntpSynced"] = ntpSynced;
  d["rev"] = cfg.rev;
  d["count"] = (int)cfg.timers.size();
  d["ip"] = localIp().toString();
  d["uptime"] = (uint32_t)(esp_timer_get_time() / 1000000);
  JsonArray run = d["running"].to<JsonArray>();
  for (size_t i = 0; i < cfg.timers.size(); i++) {
    if (!sched.isRunning(i)) continue;
    JsonObject o = run.add<JsonObject>();
    o["id"] = cfg.timers[i].id;
    o["left"] = sched.secondsLeft(i, monoMs());
  }
  String o;
  serializeJson(d, o);
  sendJson(200, o);
}

static void handleConfigGet() {
  if (!authOk()) return;
  sendJson(200, String(rawConfig.c_str()));
}

static void handleConfigPost() {
  if (!authOk()) return;
  std::string body = server.arg("plain").c_str(), err;
  BoxCfg nc = cfg;
  if (!parseTimers(body, nc, err)) {
    sendError(400, String("The timers are not valid: ") + err.c_str());
    return;
  }
  if (!saveFile("/config.json", "/config.bak", body)) {
    sendError(500, "The box could not save the timers.");
    return;
  }
  rawConfig = body;
  applyConfig(nc);
  logEvent('P', "timers received: " + std::to_string(nc.timers.size()) + " running");
  JsonDocument d;
  d["ok"] = true;
  d["rev"] = cfg.rev;
  d["count"] = (int)cfg.timers.size();
  String o;
  serializeJson(d, o);
  sendJson(200, o);
}

static void handleSettingsPost() {
  if (!authOk()) return;
  std::string body = server.arg("plain").c_str(), err;
  BoxCfg nc = cfg;
  if (!parseSettings(body, nc, err)) {
    sendError(400, String("The settings are not valid: ") + err.c_str());
    return;
  }
  if (!saveFile("/settings.json", "/settings.bak", body)) {
    sendError(500, "The box could not save the settings.");
    return;
  }
  applyConfig(nc);
  logEvent('P', "settings received");
  sendJson(200, "{\"ok\":true}");
}

// The Editor gives the box its key. Only from the home network, only once (until the BOOT button clears it).
static void handleClaim() {
  if (!fromLan()) {
    sendError(403, "The box can only be set up from the home network.");
    return;
  }
  if (claimed()) {
    sendError(409, "This box already belongs to a project. Hold the BOOT button for 3 seconds while powering it on to release it.");
    return;
  }
  JsonDocument d;
  if (deserializeJson(d, server.arg("plain")) != DeserializationError::Ok || !validKey(d["key"] | "")) {
    sendError(400, "The key is not valid.");
    return;
  }
  boxKey = d["key"].as<const char*>();
  prefs.putString("key", boxKey);
  failCount = 0;
  logEvent('P', "box claimed");
  sendJson(200, "{\"ok\":true}");
}

static String jsonEsc(const std::string& s) {
  String o;
  for (char c : s) {
    if (c == '"' || c == '\\') o += '\\';
    o += c;
  }
  return o;
}

static void handleLog() {
  if (!authOk()) return;
  server.sendHeader("Cache-Control", "no-store");
  server.setContentLength(CONTENT_LENGTH_UNKNOWN);
  server.send(200, "application/json", "");
  server.sendContent("{\"events\":[");
  String chunk;
  bool first = true;
  for (const Event& e : elog.events()) {
    if (!first) chunk += ',';
    first = false;
    chunk += "{\"t\":" + String(e.t) + ",\"k\":\"" + String(e.k) + "\",\"x\":\"" + jsonEsc(e.x) + "\"}";
    if (chunk.length() > 1000) {
      server.sendContent(chunk);
      chunk = "";
    }
  }
  chunk += "]}";
  server.sendContent(chunk);
  server.sendContent("");
}

static void handleRun() {
  if (!authOk()) return;
  JsonDocument d;
  if (deserializeJson(d, server.arg("plain")) != DeserializationError::Ok || !d["id"].is<const char*>()) {
    sendError(400, "Send the id of the timer.");
    return;
  }
  if (!sched.runNow(d["id"].as<const char*>(), sendEvent, logFn)) {
    sendError(404, "The box does not have this timer. Send the timers to the box first.");
    return;
  }
  sendJson(200, "{\"ok\":true}");
}

static void handleTime() {
  if (!authOk()) return;
  JsonDocument d;
  if (deserializeJson(d, server.arg("plain")) != DeserializationError::Ok) {
    sendError(400, "Not valid JSON.");
    return;
  }
  if (d["ntp"].is<const char*>()) {
    String n = d["ntp"].as<const char*>();
    n.trim();
    bool good = n.length() > 0 && n.length() <= 60;
    for (size_t i = 0; good && i < n.length(); i++) good = isalnum((unsigned char)n[i]) || n[i] == '.' || n[i] == '-';
    if (!good) {
      sendError(400, "The time server must be a name like pool.ntp.org.");
      return;
    }
    ntpServer = n;
    prefs.putString("ntp", ntpServer);
    applyNtp();
  }
  if (d["sync"] == true) applyNtp();
  if (d["set"].is<double>()) {
    double v = d["set"].as<double>();
    if (v > kMinValidEpoch && v < 4102444800.0) {
      struct timeval tv;
      tv.tv_sec = (time_t)v;
      tv.tv_usec = 0;
      settimeofday(&tv, nullptr);
      logEvent('T', "time set by hand");
    }
  }
  sendJson(200, "{\"ok\":true}");
}

static void startServices() {
  static const char* hdrs[] = {"X-Nonce", "X-Sig"};
  server.collectHeaders(hdrs, 2);
  server.on("/", HTTP_GET, []() { server.send_P(200, "text/html", kPage); });
  server.on("/api/info", HTTP_GET, handleInfo);
  server.on("/api/challenge", HTTP_GET, handleChallenge);
  server.on("/api/status", HTTP_GET, handleStatus);
  server.on("/api/config", HTTP_GET, handleConfigGet);
  server.on("/api/config", HTTP_POST, handleConfigPost);
  server.on("/api/settings", HTTP_POST, handleSettingsPost);
  server.on("/api/claim", HTTP_POST, handleClaim);
  server.on("/api/log", HTTP_GET, handleLog);
  server.on("/api/run", HTTP_POST, handleRun);
  server.on("/api/time", HTTP_POST, handleTime);
  server.onNotFound([]() { sendError(404, "Not found."); });
  server.begin();
  disc.begin(kDiscoveryPort);
}

// Updating over the network is only possible once the box has a key (the key is the password).
static void startOta() {
  if (otaStarted || !claimed()) return;
  ArduinoOTA.setHostname((String("evoknx-box-") + chipId).c_str());
  ArduinoOTA.setPassword(boxKey.c_str());
  ArduinoOTA.begin();
  otaStarted = true;
}

// The Editor looks for boxes with a UDP broadcast "EVOKNX-BOX?".
static void pollDiscovery() {
  if (disc.parsePacket() <= 0) return;
  char buf[32];
  int len = disc.read(buf, sizeof(buf) - 1);
  if (len <= 0) return;
  buf[len] = 0;
  if (strncmp(buf, "EVOKNX-BOX?", 11) != 0) return;
  JsonDocument d;
  d["t"] = "EVOKNX-BOX";
  d["name"] = cfg.name;
  d["port"] = 80;
  d["id"] = chipId;
  d["fw"] = FW_VERSION;
  d["claimed"] = claimed();
  String o;
  serializeJson(d, o);
  disc.beginPacket(disc.remoteIP(), disc.remotePort());
  disc.print(o);
  disc.endPacket();
}

// ------------------------------------------------------------------------------------------------------------ setup and loop

static void startNetwork() {
#ifdef USE_WIFI
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
#else
  ETH.begin(ETH_PHY_W5500, 1, ETH_W5500_CS, ETH_W5500_INT, ETH_W5500_RST, SPI3_HOST, ETH_SPI_SCK, ETH_SPI_MISO, ETH_SPI_MOSI);
#endif
}

void setup() {
  Serial.begin(115200);
  delay(200);
  uint64_t mac = ESP.getEfuseMac();
  char id[13];
  snprintf(id, sizeof(id), "%012llX", (unsigned long long)mac);
  chipId = id;

  // Watchdog: if the program ever hangs, the box restarts itself.
  esp_task_wdt_config_t twdt;
  twdt.timeout_ms = 30000;
  twdt.idle_core_mask = 0;
  twdt.trigger_panic = true;
  if (esp_task_wdt_reconfigure(&twdt) != ESP_OK) esp_task_wdt_init(&twdt);
  esp_task_wdt_add(NULL);

  if (!LittleFS.begin(true)) Serial.println("LittleFS could not start");
  prefs.begin("evoknx", false);
  boxKey = prefs.getString("key", "");
  if (!validKey(boxKey.c_str())) boxKey = "";
  ntpServer = prefs.getString("ntp", "pool.ntp.org");
  // BOOT button held for 3 seconds while powering on: the box forgets its key (the timers stay) and can be claimed again.
  pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);
  uint32_t t0 = millis();
  while (digitalRead(BOOT_BUTTON_PIN) == LOW && millis() - t0 < 3000) delay(10);
  if (digitalRead(BOOT_BUTTON_PIN) == LOW && millis() - t0 >= 3000) {
    boxKey = "";
    prefs.remove("key");
    Serial.println("Key cleared (button held). The box can be claimed again.");
  }
  Serial.printf("\nEvoKNX Box %s  %s\n", FW_VERSION, claimed() ? "(claimed)" : "(not claimed yet: press Connect in the Editor)");

  loadConfig();
  loadLog();
  {
    // The file only grows between two clean-ups; if the clock never got set it could grow for a long time.
    File f = LittleFS.open("/log.txt", "r");
    size_t size = f ? f.size() : 0;
    if (f) f.close();
    if (size > 64 * 1024) compactLog();
  }
  startNetwork();
}

void loop() {
  esp_task_wdt_reset();

  IPAddress ip = localIp();
  bool up = ip != IPAddress();
  if (up && !netUp) {
    netUp = true;
    if (!servicesStarted) {
      startServices();
      servicesStarted = true;
    }
    applyNtp();
  }
  if (!up && netUp) netUp = false;
  if (up && ip != lastIp) {
    lastIp = ip;
    startBus();
  }

  if (servicesStarted) {
    server.handleClient();
    startOta();
    if (otaStarted) ArduinoOTA.handle();
    pollDiscovery();
  }
  if (bus) bus->loop();

  if (syncFlag) {
    syncFlag = false;
    ntpSynced = true;
    logEvent('T', "time synchronised");
    if (elog.prune(nowUtc())) compactLog();
  }
  if (bootPending && (timeValid() || millis() > 60000)) {
    bootPending = false;
    logEvent('B', std::string("box started, firmware ") + FW_VERSION);
  }

  static uint32_t lastTick = 0;
  if (millis() - lastTick >= 250) {
    lastTick = millis();
    sched.tick(nowUtc(), timeValid(), monoMs(), sendEvent, logFn);
  }

  // A new day: drop what is older than 7 days.
  static uint32_t lastPrune = 0;
  if (millis() - lastPrune > 6UL * 3600 * 1000) {
    lastPrune = millis();
    if (elog.prune(nowUtc())) compactLog();
  }

  delay(2);
}
