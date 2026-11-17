// The log of the last 7 days: what the box did (not every telegram). Pure logic; the file is written by the caller.
#pragma once
#include <stdint.h>
#include <stdlib.h>
#include <deque>
#include <string>

namespace evo {

constexpr uint32_t kLogDays = 7;
constexpr size_t kLogMax = 600;

struct Event {
  uint32_t t = 0;  // seconds since 1970 (UTC), 0 when the clock was not set
  char k = '?';
  std::string x;
};

inline std::string cleanText(const std::string& s) {
  std::string o;
  for (char c : s) o += (c == '\n' || c == '\r' || c == '|') ? ' ' : c;
  if (o.size() > 90) o.resize(90);
  return o;
}

// One line of the file: "t|k|text".
inline std::string eventLine(const Event& e) { return std::to_string(e.t) + "|" + e.k + "|" + cleanText(e.x) + "\n"; }

inline bool parseEventLine(const std::string& line, Event& e) {
  size_t a = line.find('|');
  if (a == std::string::npos || a == 0 || a + 2 >= line.size() || line[a + 2] != '|') return false;
  for (size_t i = 0; i < a; i++) {
    if (line[i] < '0' || line[i] > '9') return false;
  }
  e.t = (uint32_t)strtoul(line.substr(0, a).c_str(), nullptr, 10);
  e.k = line[a + 1];
  e.x = line.substr(a + 3);
  while (!e.x.empty() && (e.x.back() == '\n' || e.x.back() == '\r')) e.x.pop_back();
  return true;
}

class EventLog {
 public:
  void add(uint32_t t, char k, const std::string& x) {
    Event e;
    e.t = t;
    e.k = k;
    e.x = cleanText(x);
    ev_.push_back(e);
    while (ev_.size() > kLogMax) ev_.pop_front();
  }

  // Drops what is older than 7 days. Returns true when something was dropped (the file can then be rewritten).
  bool prune(uint32_t nowUtc) {
    bool any = false;
    if (nowUtc < 1704067200) return false;
    while (!ev_.empty() && ev_.front().t != 0 && ev_.front().t + kLogDays * 86400 < nowUtc) {
      ev_.pop_front();
      any = true;
    }
    return any;
  }

  const std::deque<Event>& events() const { return ev_; }
  void clear() { ev_.clear(); }

 private:
  std::deque<Event> ev_;
};

}  // namespace evo
