// Who may do what: the box trusts the home network for reading, and always wants a signature for anything that changes it.
#pragma once
#include <stdint.h>

namespace evo {

// True for addresses that cannot come from the Internet: 10.x, 172.16–31.x, 192.168.x, 169.254.x and 127.x.
inline bool isPrivateV4(uint8_t a, uint8_t b) {
  return a == 10 || a == 127 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
}

// A key is 32 capital hex digits.
inline bool validKey(const char* k) {
  if (!k) return false;
  int n = 0;
  for (; k[n]; n++) {
    char c = k[n];
    if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) return false;
  }
  return n == 32;
}

enum class Need { Open, Signature, Deny };

// What a call needs. [post]: it changes something. [claimed]: the box has a key. [lan]: the call comes from a private address.
inline Need accessFor(bool post, bool claimed, bool lan) {
  if (!post && lan) return Need::Open;  // reading from the home network
  if (!claimed) return Need::Deny;      // no key: nothing can be signed, and nothing is read from outside
  return Need::Signature;
}

}  // namespace evo
