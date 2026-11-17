// Runs the timers. Pure logic: the time and the bus are given to it, so it can be tested on a PC.
#pragma once
#include <stdint.h>
#include <functional>
#include <string>
#include <vector>
#include "box_config.h"
#include "knx_frames.h"

namespace evo {

// Writes [p] to the group address [ga] on the bus. False when it could not be sent.
using SendFn = std::function<bool(uint16_t ga, const Payload& p)>;
// Tells what happened: a letter and a short text (they go to the log of the last 7 days).
//   S schedule ran   C countdown started   X countdown cancelled   R countdown ran   E error   M run by hand
using LogFn = std::function<void(char type, const std::string& text)>;

constexpr uint32_t kMinValidEpoch = 1704067200;  // 2024-01-01: earlier means the clock was never set

// The local weekday (1 = Monday … 7 = Sunday) and the minute of the day of [utc] with the offset [tzMin].
inline void localParts(uint32_t utc, int tzMin, int& weekday, int& minuteOfDay, int64_t& dayNo) {
  int64_t local = (int64_t)utc + (int64_t)tzMin * 60;
  dayNo = local / 86400;
  if (local < 0 && local % 86400 != 0) dayNo -= 1;
  int64_t sec = local - dayNo * 86400;
  minuteOfDay = (int)(sec / 60);
  weekday = (int)(((dayNo % 7) + 7 + 3) % 7) + 1;  // 1970-01-01 was a Thursday
}

class Scheduler {
 public:
  struct Running {
    std::string id;
    uint64_t dueMs;
    uint8_t tries;
  };

  void setConfig(const BoxCfg& c) {
    cfg_ = c;
    lastKey_.assign(c.timers.size(), -1);
    running_.assign(c.timers.size(), Running{"", 0, 0});
    active_.assign(c.timers.size(), false);
  }

  const BoxCfg& config() const { return cfg_; }

  // Call about every 250 ms. [utc] is the clock time (valid only when [timeValid]); [monoMs] counts from power-up.
  void tick(uint32_t utc, bool timeValid, uint64_t monoMs, const SendFn& send, const LogFn& log) {
    if (timeValid) {
      int wd, mod;
      int64_t day;
      localParts(utc, cfg_.tzMin, wd, mod, day);
      int64_t key = day * 1440 + mod;
      for (size_t i = 0; i < cfg_.timers.size(); i++) {
        const Timer& t = cfg_.timers[i];
        if (t.kind != 's' || t.minute != mod || !(t.days & (1 << (wd - 1))) || lastKey_[i] == key) continue;
        lastKey_[i] = key;
        fire(t, send, log, 'S', "schedule");
      }
    }
    for (size_t i = 0; i < cfg_.timers.size(); i++) {
      if (!active_[i] || monoMs < running_[i].dueMs) continue;
      const Timer& t = cfg_.timers[i];
      if (send(t.ga, t.act)) {
        active_[i] = false;
        log('R', label(t) + " wrote " + gaText(t.ga));
      } else if (++running_[i].tries >= 12) {
        active_[i] = false;
        log('E', label(t) + ": could not write " + gaText(t.ga) + " (bus not available), giving up");
      } else {
        running_[i].dueMs = monoMs + 5000;  // the bus is not ready: try again in 5 s
      }
    }
  }

  // A telegram seen on the bus: starts, restarts or cancels the countdowns that watch this address.
  void onTelegram(const Group& g, uint64_t monoMs, const LogFn& log) {
    if (g.apci == APCI_READ) return;
    for (size_t i = 0; i < cfg_.timers.size(); i++) {
      const Timer& t = cfg_.timers[i];
      if (t.kind != 'c' || t.watch != g.dst) continue;
      if (g.p == t.trig) {
        if (active_[i] && !t.restart) continue;
        bool again = active_[i];
        active_[i] = true;
        running_[i] = Running{t.id, monoMs + (uint64_t)t.secs * 1000ULL, 0};
        log('C', label(t) + (again ? " started again, " : " started, ") + std::to_string(t.secs) + " s");
      } else if (active_[i]) {
        active_[i] = false;
        log('X', label(t) + " cancelled (" + gaText(t.watch) + " changed)");
      }
    }
  }

  // Runs the timer [id] now (to test it); a countdown writes its value at once. False when there is no such timer.
  bool runNow(const std::string& id, const SendFn& send, const LogFn& log) {
    for (const Timer& t : cfg_.timers) {
      if (t.id == id) {
        fire(t, send, log, 'M', "run by hand");
        return true;
      }
    }
    return false;
  }

  size_t runningCount() const {
    size_t n = 0;
    for (bool a : active_) n += a ? 1 : 0;
    return n;
  }

  // Seconds left of the countdown [i] (0 when it is not running).
  uint32_t secondsLeft(size_t i, uint64_t monoMs) const {
    if (i >= active_.size() || !active_[i] || running_[i].dueMs <= monoMs) return 0;
    return (uint32_t)((running_[i].dueMs - monoMs + 999) / 1000);
  }

  bool isRunning(size_t i) const { return i < active_.size() && active_[i]; }

 private:
  static std::string label(const Timer& t) {
    std::string n = t.name.empty() ? (t.kind == 'c' ? "countdown " + t.id : "schedule " + t.id) : t.name;
    return n;
  }

  void fire(const Timer& t, const SendFn& send, const LogFn& log, char type, const char* how) {
    if (send(t.ga, t.act)) {
      log(type, label(t) + " wrote " + gaText(t.ga) + (type == 'M' ? " (run by hand)" : ""));
    } else {
      log('E', label(t) + ": could not write " + gaText(t.ga) + " (" + how + ", bus not available)");
    }
  }

  BoxCfg cfg_;
  std::vector<int64_t> lastKey_;
  std::vector<Running> running_;
  std::vector<bool> active_;
};

}  // namespace evo
