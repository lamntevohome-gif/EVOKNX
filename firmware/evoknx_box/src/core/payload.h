// The data of a KNX group telegram, as the bus carries it. No data types here: the Editor already turned the values into bytes.
#pragma once
#include <stdint.h>
#include <string.h>
#include <string>

namespace evo {

struct Payload {
  uint8_t len = 0;       // number of bytes in b (a short value is one byte)
  uint8_t b[16] = {0};
  bool shortv = false;   // true: the value sits in the 6 low bits of the APCI byte (1-bit … 6-bit values)

  bool operator==(const Payload& o) const { return shortv == o.shortv && len == o.len && memcmp(b, o.b, len) == 0; }
  bool operator!=(const Payload& o) const { return !(*this == o); }
};

// "01", "80" or "0a1b…" (lowercase or uppercase) to bytes. False when it is not hex or has more than 14 bytes.
inline bool parseHexPayload(const char* hex, bool shortv, Payload& out) {
  size_t n = hex ? strlen(hex) : 0;
  if (n == 0 || (n % 2) != 0 || n / 2 > 14) return false;
  auto nib = [](char c) -> int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  };
  out = Payload();
  for (size_t i = 0; i < n / 2; i++) {
    int h = nib(hex[2 * i]), l = nib(hex[2 * i + 1]);
    if (h < 0 || l < 0) return false;
    out.b[i] = (uint8_t)(h * 16 + l);
  }
  out.len = (uint8_t)(n / 2);
  out.shortv = shortv;
  if (shortv) {
    if (out.len != 1) return false;
    out.b[0] &= 0x3F;
  }
  return true;
}

inline std::string gaText(uint16_t ga) {
  return std::to_string((ga >> 11) & 0x1F) + "/" + std::to_string((ga >> 8) & 0x07) + "/" + std::to_string(ga & 0xFF);
}

}  // namespace evo
