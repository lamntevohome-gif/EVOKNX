// The settings (from the Editor, boxSettingsWire) and the timers (from the phone, boxTimersWire). Parsed and checked here.
#pragma once
#include <ArduinoJson.h>
#include <string>
#include <vector>
#include "payload.h"

namespace evo {

constexpr size_t kMaxTimers = 64;
constexpr uint32_t kMaxSecs = 86400;

struct Timer {
  std::string id, name, gname, wname;  // wname: name of the watched address (countdown)
  char kind = 's';                     // 's' schedule, 'c' countdown
  uint16_t minute = 0;                 // schedule: minute of the day (local time)
  uint8_t days = 0;                    // schedule: bit 0 = Monday … bit 6 = Sunday
  uint16_t watch = 0;                  // countdown: the address that starts it
  Payload trig;                        // countdown: the value that starts it
  uint32_t secs = 0;                   // countdown: how long to wait
  bool restart = true;                 // countdown: start again when the value comes again
  uint16_t ga = 0;                     // the address that is written
  Payload act;                         // the value that is written
};

struct BusCfg {
  bool tunnel = false;
  std::string host;
  uint16_t port = 3671;
};

struct BoxCfg {
  std::string name = "EvoKNX Box", rev;
  int tzMin = 0;  // local time = UTC + tzMin
  BusCfg bus;
  std::vector<Timer> timers;
};

inline std::string str(JsonVariantConst v, size_t max = 40) {
  const char* s = v.is<const char*>() ? v.as<const char*>() : "";
  std::string t = s ? s : "";
  if (t.size() > max) t.resize(max);
  return t;
}

// Reads the settings (name, time zone, how the box reaches the bus) into [out]; the timers of [out] are not touched.
// On a problem returns false and says what in [err]; [out] is then unchanged.
inline bool parseSettings(const std::string& json, BoxCfg& out, std::string& err) {
  JsonDocument doc;
  if (deserializeJson(doc, json) != DeserializationError::Ok) {
    err = "not valid JSON";
    return false;
  }
  if ((doc["v"] | 0) != 1) {
    err = "unknown format version";
    return false;
  }
  BoxCfg c = out;
  c.name = str(doc["name"]);
  if (c.name.empty()) c.name = "EvoKNX Box";
  int tz = doc["tz"] | 0;
  if (tz < -720 || tz > 840) {
    err = "time zone out of range";
    return false;
  }
  c.tzMin = tz;
  JsonObjectConst bus = doc["bus"];
  c.bus = BusCfg();
  c.bus.tunnel = str(bus["mode"], 10) == "tunnel";
  if (c.bus.tunnel) {
    c.bus.host = str(bus["host"], 64);
    int port = bus["port"] | 3671;
    if (c.bus.host.empty() || port < 1 || port > 65535) {
      err = "tunneling needs the address of the interface";
      return false;
    }
    c.bus.port = (uint16_t)port;
  }
  out = c;
  return true;
}

// Reads the timers (and their fingerprint "rev") into [out]; the settings of [out] are not touched. The "ui" part (how the phone shows
// the timers) is only stored by the caller, never read here. On a problem returns false and says what in [err]; [out] is then unchanged.
inline bool parseTimers(const std::string& json, BoxCfg& out, std::string& err) {
  JsonDocument doc;
  if (deserializeJson(doc, json) != DeserializationError::Ok) {
    err = "not valid JSON";
    return false;
  }
  if ((doc["v"] | 0) != 1) {
    err = "unknown format version";
    return false;
  }
  BoxCfg c = out;
  c.timers.clear();
  c.rev = str(doc["rev"], 24);
  JsonArrayConst arr = doc["timers"];
  if (arr.size() > kMaxTimers) {
    err = "too many timers";
    return false;
  }
  for (JsonObjectConst o : arr) {
    Timer t;
    t.id = str(o["id"], 24);
    t.name = str(o["n"]);
    t.gname = str(o["gn"]);
    t.wname = str(o["wn"]);
    if (t.id.empty()) {
      err = "a timer has no id";
      return false;
    }
    std::string k = str(o["k"], 2);
    if (k != "s" && k != "c") {
      err = "unknown timer kind";
      return false;
    }
    t.kind = k[0];
    int g = o["g"] | -1;
    if (g < 0 || g > 0xFFFF || !parseHexPayload(str(o["a"], 32).c_str(), (o["as"] | 0) == 1, t.act)) {
      err = "timer " + t.id + ": bad address or value";
      return false;
    }
    t.ga = (uint16_t)g;
    if (t.kind == 's') {
      int m = o["m"] | -1, d = o["d"] | 0;
      if (m < 0 || m > 1439 || d < 1 || d > 127) {
        err = "timer " + t.id + ": bad time or days";
        return false;
      }
      t.minute = (uint16_t)m;
      t.days = (uint8_t)d;
    } else {
      int w = o["w"] | -1;
      long s = o["s"] | 0L;
      if (w < 0 || w > 0xFFFF || s < 1 || s > (long)kMaxSecs || !parseHexPayload(str(o["v"], 32).c_str(), (o["vs"] | 0) == 1, t.trig)) {
        err = "timer " + t.id + ": bad watch address, value or time";
        return false;
      }
      t.watch = (uint16_t)w;
      t.secs = (uint32_t)s;
      t.restart = (o["r"] | 1) != 0;
    }
    c.timers.push_back(t);
  }
  out = c;
  return true;
}

}  // namespace evo
