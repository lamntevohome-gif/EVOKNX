// Tests of the logic of the box on a PC (no ESP32 needed):
//   g++ -std=c++17 -I../src/core -I<ArduinoJson>/src host_test.cpp -o host_test && ./host_test
#include <stdio.h>
#include <string.h>
#include <string>
#include <vector>
#include "box_config.h"
#include "access.h"
#include "event_log.h"
#include "knx_frames.h"
#include "scheduler.h"
#include "vectors.h"

using namespace evo;

static int pass = 0, failn = 0;
#define CHECK(c, name)                                  \
  do {                                                  \
    if (c) {                                            \
      pass++;                                           \
    } else {                                            \
      failn++;                                          \
      printf("FAIL: %s (line %d)\n", name, __LINE__);   \
    }                                                   \
  } while (0)

static std::string hex(const uint8_t* d, size_t n) {
  static const char* h = "0123456789abcdef";
  std::string s;
  for (size_t i = 0; i < n; i++) {
    s += h[d[i] >> 4];
    s += h[d[i] & 15];
  }
  return s;
}

static Payload P(const char* h, bool shortv) {
  Payload p;
  parseHexPayload(h, shortv, p);
  return p;
}

static std::vector<std::string> logs;
static std::vector<std::pair<uint16_t, std::string>> sent;
static bool busOk = true;

static LogFn LOG = [](char k, const std::string& x) { logs.push_back(std::string(1, k) + ":" + x); };
static SendFn SEND = [](uint16_t ga, const Payload& p) {
  if (!busOk) return false;
  sent.push_back({ga, hex(p.b, p.len)});
  return true;
};

// seconds since 1970 of a UTC date and time
static uint32_t utc(int y, int mo, int d, int h, int mi, int s = 0) {
  static const int cum[] = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334};
  long days = 0;
  for (int yy = 1970; yy < y; yy++) days += (yy % 4 == 0 && (yy % 100 != 0 || yy % 400 == 0)) ? 366 : 365;
  days += cum[mo - 1] + (d - 1);
  if (mo > 2 && (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0))) days += 1;
  return (uint32_t)(days * 86400L + h * 3600L + mi * 60L + s);
}

static Group G(uint16_t dst, const char* h, bool shortv, uint16_t apci = APCI_WRITE) {
  Group g;
  g.dst = dst;
  g.apci = apci;
  g.p = P(h, shortv);
  return g;
}

int main() {
  // ---- frames, compared with the ones knx_core (Dart) builds
  uint8_t o[80];
  size_t n = buildCemi(o, CEMI_L_DATA_REQ, 0, (1 << 11) | (1 << 8) | 5, APCI_WRITE, P("01", true));
  CHECK(hex(o, n) == V_CEMI_REQ_SHORT, "cemi short");
  n = buildCemi(o, CEMI_L_DATA_REQ, 0, (2 << 11) | 1, APCI_WRITE, P("80", false));
  CHECK(hex(o, n) == V_CEMI_REQ_1BYTE, "cemi 1 byte");
  n = buildCemi(o, CEMI_L_DATA_REQ, 0, (3 << 11) | (4 << 8) | 200, APCI_WRITE, P("0c33", false));
  CHECK(hex(o, n) == V_CEMI_REQ_FLOAT, "cemi float");
  n = buildCemi(o, CEMI_L_DATA_REQ, 0, (3 << 11) | (4 << 8) | 200, APCI_WRITE, P("48656c6c6f000000000000000000", false));
  CHECK(hex(o, n) == V_CEMI_REQ_TEXT, "cemi 14 bytes");
  n = buildRouting(o, 0xFFFA, (1 << 11) | (1 << 8) | 5, P("00", true));
  CHECK(hex(o, n) == V_ROUTING, "routing indication");
  const uint8_t ip[4] = {192, 168, 1, 77};
  n = buildConnectReq(o, ip, 3671);
  CHECK(hex(o, n) == V_CONNECT, "connect request");
  n = buildStateReq(o, 7, ip, 3671);
  CHECK(hex(o, n) == V_STATE, "connection state request");
  n = buildDisconnectReq(o, 7, ip, 3671);
  CHECK(hex(o, n) == V_DISCONNECT, "disconnect request");
  n = buildTunnelReq(o, 7, 3, (1 << 11) | (1 << 8) | 5, P("01", true));
  CHECK(hex(o, n) == V_TUNNEL, "tunnelling request");
  n = buildTunnelAck(o, 7, 3, 0);
  CHECK(hex(o, n) == V_ACK, "tunnelling ack");

  // ---- parsing what the bus sends
  auto fromHex = [](const char* h, uint8_t* out) {
    size_t k = strlen(h) / 2;
    for (size_t i = 0; i < k; i++) {
      unsigned v;
      sscanf(h + 2 * i, "%2x", &v);
      out[i] = (uint8_t)v;
    }
    return k;
  };
  uint8_t buf[80];
  uint8_t code;
  Group g;
  n = fromHex(V_CEMI_IND_SHORT, buf);
  CHECK(parseCemi(buf, n, code, g) && code == CEMI_L_DATA_IND && g.src == 0x1101 && g.dst == 0x0905 && g.apci == APCI_WRITE && g.p.shortv && g.p.b[0] == 1, "parse short write");
  n = fromHex(V_CEMI_IND_RESP, buf);
  CHECK(parseCemi(buf, n, code, g) && g.apci == APCI_RESPONSE && !g.p.shortv && g.p.len == 1 && g.p.b[0] == 0x80 && g.dst == 0x1001, "parse response with a byte");
  n = fromHex(V_CEMI_REQ_TEXT, buf);
  CHECK(parseCemi(buf, n, code, g) && g.p.len == 14 && g.p.b[0] == 'H', "parse 14 bytes");
  n = fromHex(V_ROUTING, buf);
  uint16_t svc;
  size_t off, blen;
  CHECK(parseHeader(buf, n, svc, off, blen) && svc == SVC_ROUTING_IND && parseCemi(buf + off, blen, code, g) && g.src == 0xFFFA && g.p.shortv && g.p.b[0] == 0, "parse routing frame");
  buf[0] = 0x07;
  CHECK(!parseHeader(buf, n, svc, off, blen), "bad header refused");
  uint8_t bad[12] = {0x29, 0, 0xBC, 0x60, 0, 0, 0, 0, 1, 0, 0x81, 0};  // individual destination
  CHECK(!parseCemi(bad, 11, code, g), "individual destination refused");

  // ---- the settings from the Editor
  BoxCfg cfg;
  std::string err;
  CHECK(parseSettings(V_SETTINGS, cfg, err), ("parse settings: " + err).c_str());
  CHECK(cfg.timers.empty(), "settings do not touch the timers");
  CHECK(parseTimers(V_WIRE, cfg, err), ("parse wire: " + err).c_str());
  CHECK(cfg.name == "Villa box" && cfg.tzMin == 420 && cfg.bus.tunnel, "timers do not touch the settings");
  CHECK(cfg.name == "Villa box" && cfg.tzMin == 420 && cfg.bus.tunnel && cfg.bus.host == "192.168.1.50" && cfg.bus.port == 3671 && cfg.rev == V_WIRE_REV, "settings");
  CHECK(cfg.timers.size() == 3, "three timers");
  CHECK(cfg.timers[0].kind == 's' && cfg.timers[0].minute == 1350 && cfg.timers[0].days == 31 && cfg.timers[0].ga == 2309 && cfg.timers[0].act.shortv && cfg.timers[0].act.b[0] == 0 && cfg.timers[0].name == "Night off", "schedule fields");
  CHECK(cfg.timers[2].kind == 'c' && cfg.timers[2].watch == 2309 && cfg.timers[2].secs == 600 && cfg.timers[2].trig.shortv && cfg.timers[2].trig.b[0] == 1 && cfg.timers[2].restart, "countdown fields");
  BoxCfg tmp;
  CHECK(!parseTimers("{", tmp, err), "bad json refused");
  CHECK(!parseTimers("{\"v\":2}", tmp, err), "unknown version refused");
  CHECK(!parseTimers("{\"v\":1,\"timers\":[{\"id\":\"x\",\"k\":\"s\",\"m\":1500,\"d\":1,\"g\":1,\"a\":\"00\",\"as\":1}]}", tmp, err), "bad minute refused");
  CHECK(!parseTimers("{\"v\":1,\"timers\":[{\"id\":\"x\",\"k\":\"c\",\"w\":1,\"v\":\"01\",\"vs\":1,\"s\":0,\"g\":1,\"a\":\"00\",\"as\":1}]}", tmp, err), "zero seconds refused");
  CHECK(!parseSettings("{\"v\":1,\"bus\":{\"mode\":\"tunnel\"}}", tmp, err), "tunnel without host refused");
  CHECK(parseTimers("{\"v\":1,\"timers\":[],\"ui\":[{\"x\":1}]}", tmp, err) && tmp.timers.empty(), "empty list is fine, ui is ignored");

  // ---- who may do what
  CHECK(isPrivateV4(192, 168) && isPrivateV4(10, 1) && isPrivateV4(172, 16) && isPrivateV4(172, 31) && isPrivateV4(127, 0) && isPrivateV4(169, 254), "private addresses");
  CHECK(!isPrivateV4(172, 15) && !isPrivateV4(172, 32) && !isPrivateV4(8, 8) && !isPrivateV4(192, 169) && !isPrivateV4(100, 64), "public addresses");
  CHECK(validKey("0123456789ABCDEF0123456789ABCDEF") && !validKey("0123456789abcdef0123456789abcdef") && !validKey("ABC") && !validKey(nullptr), "key form");
  CHECK(accessFor(false, true, true) == Need::Open && accessFor(false, false, true) == Need::Open, "reading from the home network is open");
  CHECK(accessFor(false, true, false) == Need::Signature && accessFor(false, false, false) == Need::Deny, "reading from outside needs the key");
  CHECK(accessFor(true, true, true) == Need::Signature && accessFor(true, true, false) == Need::Signature && accessFor(true, false, true) == Need::Deny, "changing needs the key");

  // ---- the local time
  int wd, mod;
  int64_t day;
  localParts(utc(2026, 11, 17, 1, 50), 420, wd, mod, day);  // 08:50 in Vietnam, Tuesday
  CHECK(wd == 2 && mod == 8 * 60 + 50, "2026-11-17 08:50 local is Tuesday");
  localParts(utc(2026, 11, 17, 20, 0), 420, wd, mod, day);  // 03:00 on Wednesday
  CHECK(wd == 3 && mod == 180, "crosses midnight with the offset");
  localParts(utc(2026, 11, 15, 12, 0), 0, wd, mod, day);
  CHECK(wd == 7, "2026-11-15 is Sunday");

  // ---- schedules
  Scheduler s;
  s.setConfig(cfg);
  logs.clear();
  sent.clear();
  // Tuesday 22:30 local = 15:30 UTC: the first schedule (Mon-Fri 22:30) fires once.
  uint32_t t0 = utc(2026, 11, 17, 15, 30, 5);
  s.tick(t0, true, 1000, SEND, LOG);
  s.tick(t0 + 10, true, 11000, SEND, LOG);
  s.tick(t0 + 54, true, 55000, SEND, LOG);
  CHECK(sent.size() == 1 && sent[0].first == 2309 && sent[0].second == "00", "22:30 fires once");
  CHECK(logs.size() == 1 && logs[0][0] == 'S', "logged");
  s.tick(t0 + 60, true, 61000, SEND, LOG);
  CHECK(sent.size() == 1, "not again in the next minute");
  s.tick(utc(2026, 11, 18, 15, 30, 1), true, 86400000, SEND, LOG);
  CHECK(sent.size() == 2, "fires again the next day");
  // Saturday 22:30: the Mon-Fri schedule is silent; the weekend one is at 06:05.
  sent.clear();
  s.tick(utc(2026, 11, 21, 15, 30, 1), true, 5, SEND, LOG);
  CHECK(sent.empty(), "silent on Saturday");
  s.tick(utc(2026, 11, 20, 23, 5, 1), true, 9, SEND, LOG);  // 06:05 Saturday local
  CHECK(sent.size() == 1 && sent[0].first == 4097 && sent[0].second == "01", "weekend schedule 06:05");
  // No valid time: nothing runs.
  sent.clear();
  s.tick(5, false, 10, SEND, LOG);
  CHECK(sent.empty(), "no schedule without a valid clock");
  // The bus is down at 22:30: an error is logged, not repeated.
  s.setConfig(cfg);
  logs.clear();
  busOk = false;
  s.tick(t0, true, 1, SEND, LOG);
  s.tick(t0 + 3, true, 3000, SEND, LOG);
  CHECK(logs.size() == 1 && logs[0][0] == 'E', "error logged once when the bus is down");
  busOk = true;

  // ---- countdown (timer 3: watch 1/1/5 becomes 1, after 600 s write 0 to 1/1/5)
  s.setConfig(cfg);
  logs.clear();
  sent.clear();
  uint64_t ms = 1000000;
  uint32_t clock = utc(2026, 11, 17, 3, 0, 0);  // 10:00 local: no schedule is due
  s.onTelegram(G(2309, "01", true), ms, LOG);
  CHECK(s.runningCount() == 1 && s.isRunning(2) && s.secondsLeft(2, ms) == 600, "countdown started");
  s.tick(clock, true, ms + 599000, SEND, LOG);
  CHECK(sent.empty(), "not yet after 599 s");
  s.tick(clock, true, ms + 600000, SEND, LOG);
  CHECK(sent.size() == 1 && sent[0].first == 2309 && sent[0].second == "00" && s.runningCount() == 0, "writes after 600 s");
  CHECK(logs.back()[0] == 'R', "logged as ran");
  // Cancelled by another value.
  sent.clear();
  s.onTelegram(G(2309, "01", true), ms, LOG);
  s.onTelegram(G(2309, "00", true), ms + 1000, LOG);
  CHECK(s.runningCount() == 0 && logs.back()[0] == 'X', "cancelled when it becomes 0");
  s.tick(clock, true, ms + 700000, SEND, LOG);
  CHECK(sent.empty(), "a cancelled countdown does not write");
  // Restart.
  s.onTelegram(G(2309, "01", true), ms, LOG);
  s.onTelegram(G(2309, "01", true), ms + 300000, LOG);
  CHECK(s.secondsLeft(2, ms + 300000) == 600, "started again from the beginning");
  s.tick(clock, true, ms + 600000, SEND, LOG);
  CHECK(sent.empty(), "the old end time does not count after a restart");
  s.tick(clock, true, ms + 900000, SEND, LOG);
  CHECK(sent.size() == 1, "writes 600 s after the restart");
  // Without restart.
  BoxCfg nr = cfg;
  nr.timers[2].restart = false;
  s.setConfig(nr);
  s.onTelegram(G(2309, "01", true), ms, LOG);
  s.onTelegram(G(2309, "01", true), ms + 300000, LOG);
  CHECK(s.secondsLeft(2, ms + 300000) == 300, "keeps the first end time");
  // A read and other addresses are ignored.
  s.setConfig(cfg);
  s.onTelegram(G(2309, "01", true, APCI_READ), ms, LOG);
  s.onTelegram(G(2310, "01", true), ms, LOG);
  CHECK(s.runningCount() == 0, "read and other addresses are ignored");
  // A response (the state read from the bus) starts it too.
  s.onTelegram(G(2309, "01", true, APCI_RESPONSE), ms, LOG);
  CHECK(s.runningCount() == 1, "a response starts it");
  // The bus is not ready at the end: tries again every 5 s, then gives up.
  sent.clear();
  logs.clear();
  busOk = false;
  s.tick(clock, true, ms + 600000, SEND, LOG);
  CHECK(sent.empty() && s.runningCount() == 1, "waits when the bus is down");
  busOk = true;
  s.tick(clock, true, ms + 604999, SEND, LOG);
  CHECK(sent.empty(), "tries again only after 5 s");
  s.tick(clock, true, ms + 605000, SEND, LOG);
  CHECK(sent.size() == 1 && s.runningCount() == 0, "writes when the bus is back");
  s.onTelegram(G(2309, "01", true), ms, LOG);
  busOk = false;
  logs.clear();
  for (int i = 0; i < 14; i++) s.tick(clock, true, ms + 600000 + (uint64_t)i * 5000, SEND, LOG);
  CHECK(s.runningCount() == 0 && !logs.empty() && logs.back()[0] == 'E', "gives up after 12 tries");
  busOk = true;
  // Run by hand.
  sent.clear();
  CHECK(s.runNow("tm_a", SEND, LOG) && sent.size() == 1 && !s.runNow("nope", SEND, LOG), "run now");

  // ---- the log
  EventLog lg;
  uint32_t now = utc(2026, 11, 17, 3, 0, 0);
  lg.add(now - 8 * 86400, 'S', "old");
  lg.add(now - 6 * 86400, 'S', "recent");
  lg.add(0, 'B', "boot without time");
  lg.add(now, 'R', "bad|text\nhere");
  CHECK(lg.prune(now) && lg.events().size() == 3, "older than 7 days is dropped");
  CHECK(!lg.prune(100), "nothing dropped when the clock is not valid");
  std::string line = eventLine(lg.events().back());
  Event e;
  CHECK(parseEventLine(line, e) && e.t == now && e.k == 'R' && e.x == "bad text here", "log line round trip");
  CHECK(!parseEventLine("garbage", e) && !parseEventLine("12|", e), "bad line refused");
  for (size_t i = 0; i < kLogMax + 50; i++) lg.add(now, 'S', "x");
  CHECK(lg.events().size() == kLogMax, "log is limited");

  printf("%d passed, %d failed\n", pass, failn);
  return failn ? 1 : 0;
}
