// KNXnet/IP frames and cEMI group telegrams (routing and tunneling). Pure functions, no network code, so they can be tested on a PC.
#pragma once
#include <stddef.h>
#include <stdint.h>
#include "payload.h"

namespace evo {

enum : uint16_t {
  SVC_CONNECT_REQ = 0x0205,
  SVC_CONNECT_RES = 0x0206,
  SVC_STATE_REQ = 0x0207,
  SVC_STATE_RES = 0x0208,
  SVC_DISCONNECT_REQ = 0x0209,
  SVC_DISCONNECT_RES = 0x020A,
  SVC_TUNNEL_REQ = 0x0420,
  SVC_TUNNEL_ACK = 0x0421,
  SVC_ROUTING_IND = 0x0530,
};

enum : uint8_t { CEMI_L_DATA_REQ = 0x11, CEMI_L_DATA_CON = 0x2E, CEMI_L_DATA_IND = 0x29 };
enum : uint16_t { APCI_READ = 0x000, APCI_RESPONSE = 0x040, APCI_WRITE = 0x080 };

// A group telegram seen on the bus.
struct Group {
  uint16_t src = 0, dst = 0;
  uint16_t apci = 0;  // APCI_READ, APCI_RESPONSE or APCI_WRITE
  Payload p;
};

// cEMI L_Data frame for a group write/response. Returns the length.
inline size_t buildCemi(uint8_t* o, uint8_t code, uint16_t src, uint16_t ga, uint16_t apci, const Payload& p) {
  size_t i = 0;
  o[i++] = code;
  o[i++] = 0x00;  // no additional information
  o[i++] = 0xBC;
  o[i++] = 0xE0;
  o[i++] = (uint8_t)(src >> 8);
  o[i++] = (uint8_t)src;
  o[i++] = (uint8_t)(ga >> 8);
  o[i++] = (uint8_t)ga;
  if (p.shortv) {
    o[i++] = 1;
    o[i++] = (uint8_t)((apci >> 8) & 0x03);
    o[i++] = (uint8_t)((apci & 0xC0) | (p.len ? (p.b[0] & 0x3F) : 0));
  } else {
    o[i++] = (uint8_t)(1 + p.len);
    o[i++] = (uint8_t)((apci >> 8) & 0x03);
    o[i++] = (uint8_t)(apci & 0xC0);
    for (uint8_t k = 0; k < p.len; k++) o[i++] = p.b[k];
  }
  return i;
}

// Parses a cEMI L_Data frame. Only group telegrams (read, response, write) are accepted; [code] is the message code.
inline bool parseCemi(const uint8_t* d, size_t n, uint8_t& code, Group& g) {
  if (n < 10) return false;
  code = d[0];
  size_t i = 2 + d[1];
  if (n < i + 9) return false;
  uint8_t c2 = d[i + 1];
  g.src = (uint16_t)((d[i + 2] << 8) | d[i + 3]);
  g.dst = (uint16_t)((d[i + 4] << 8) | d[i + 5]);
  uint8_t len = d[i + 6];
  uint8_t tpci = d[i + 7];
  uint8_t lo = d[i + 8];
  if ((c2 & 0x80) == 0) return false;  // not a group address
  if ((tpci & 0xFC) != 0) return false; // a control or numbered telegram, not group data
  uint16_t apci = (uint16_t)((((tpci & 0x03) << 8) | (lo & 0xC0)) & 0x3C0);
  if (apci != APCI_READ && apci != APCI_RESPONSE && apci != APCI_WRITE) return false;
  g.apci = apci;
  g.p = Payload();
  if (apci == APCI_READ) return true;
  if (len <= 1) {
    g.p.shortv = true;
    g.p.len = 1;
    g.p.b[0] = lo & 0x3F;
  } else {
    size_t start = i + 9, cnt = (size_t)len - 1;
    if (cnt > 14 || start + cnt > n) return false;
    g.p.len = (uint8_t)cnt;
    for (size_t k = 0; k < cnt; k++) g.p.b[k] = d[start + k];
  }
  return true;
}

// KNXnet/IP header + body.
inline size_t buildFrame(uint8_t* o, uint16_t service, const uint8_t* body, size_t bodyLen) {
  size_t total = 6 + bodyLen;
  o[0] = 0x06;
  o[1] = 0x10;
  o[2] = (uint8_t)(service >> 8);
  o[3] = (uint8_t)service;
  o[4] = (uint8_t)(total >> 8);
  o[5] = (uint8_t)total;
  for (size_t i = 0; i < bodyLen; i++) o[6 + i] = body[i];
  return total;
}

// Routing indication carrying one group write.
inline size_t buildRouting(uint8_t* o, uint16_t src, uint16_t ga, const Payload& p) {
  uint8_t cemi[40];
  size_t n = buildCemi(cemi, CEMI_L_DATA_IND, src, ga, APCI_WRITE, p);
  return buildFrame(o, SVC_ROUTING_IND, cemi, n);
}

inline void putHpai(uint8_t* o, const uint8_t ip[4], uint16_t port) {
  o[0] = 0x08;
  o[1] = 0x01;
  for (int i = 0; i < 4; i++) o[2 + i] = ip[i];
  o[6] = (uint8_t)(port >> 8);
  o[7] = (uint8_t)port;
}

// CONNECT_REQUEST for a tunnel (the control and the data endpoint are the same: our address and port).
inline size_t buildConnectReq(uint8_t* o, const uint8_t ip[4], uint16_t port) {
  uint8_t body[20];
  putHpai(body, ip, port);
  putHpai(body + 8, ip, port);
  body[16] = 0x04;
  body[17] = 0x04;
  body[18] = 0x02;
  body[19] = 0x00;
  return buildFrame(o, SVC_CONNECT_REQ, body, 20);
}

inline size_t buildStateReq(uint8_t* o, uint8_t channel, const uint8_t ip[4], uint16_t port) {
  uint8_t body[10] = {channel, 0};
  putHpai(body + 2, ip, port);
  return buildFrame(o, SVC_STATE_REQ, body, 10);
}

inline size_t buildDisconnectReq(uint8_t* o, uint8_t channel, const uint8_t ip[4], uint16_t port) {
  uint8_t body[10] = {channel, 0};
  putHpai(body + 2, ip, port);
  return buildFrame(o, SVC_DISCONNECT_REQ, body, 10);
}

inline size_t buildDisconnectRes(uint8_t* o, uint8_t channel, uint8_t status) {
  uint8_t body[2] = {channel, status};
  return buildFrame(o, SVC_DISCONNECT_RES, body, 2);
}

// TUNNELING_REQUEST with a cEMI frame (L_Data.req for a group write).
inline size_t buildTunnelReq(uint8_t* o, uint8_t channel, uint8_t seq, uint16_t ga, const Payload& p) {
  uint8_t body[60] = {0x04, channel, seq, 0x00};
  size_t n = buildCemi(body + 4, CEMI_L_DATA_REQ, 0, ga, APCI_WRITE, p);
  return buildFrame(o, SVC_TUNNEL_REQ, body, 4 + n);
}

inline size_t buildTunnelAck(uint8_t* o, uint8_t channel, uint8_t seq, uint8_t status) {
  uint8_t body[4] = {0x04, channel, seq, status};
  return buildFrame(o, SVC_TUNNEL_ACK, body, 4);
}

// The header of a received frame: service and where the body is. False when it is not a KNXnet/IP frame.
inline bool parseHeader(const uint8_t* d, size_t n, uint16_t& service, size_t& bodyOff, size_t& bodyLen) {
  if (n < 6 || d[0] != 0x06 || d[1] != 0x10) return false;
  service = (uint16_t)((d[2] << 8) | d[3]);
  size_t total = (size_t)((d[4] << 8) | d[5]);
  if (total < 6 || total > n) return false;
  bodyOff = 6;
  bodyLen = total - 6;
  return true;
}

}  // namespace evo
