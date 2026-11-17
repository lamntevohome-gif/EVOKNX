// The two ways the box reaches the KNX bus: routing (KNX IP Router) and tunneling (KNX IP Interface).
#pragma once
#include <Arduino.h>
#include <WiFiUdp.h>
#include <WiFi.h>
#include <functional>
#include <string>
#include <vector>
#include "board.h"
#include "core/box_config.h"
#include "core/knx_frames.h"

class KnxBus {
 public:
  virtual ~KnxBus() {}
  virtual void begin(const evo::BusCfg& cfg, IPAddress local) = 0;
  virtual void loop() = 0;
  virtual bool up() const = 0;
  virtual bool send(uint16_t ga, const evo::Payload& p) = 0;  // writes a group value; false when it could not
  virtual const char* mode() const = 0;

  std::function<void(const evo::Group&)> onGroup;     // a group telegram was seen on the bus
  std::function<void(bool up, const char* why)> onUp;  // the connection came up or went down
  uint32_t lastRxMs = 0, lastTxMs = 0;
  bool everRx = false, everTx = false;
  std::string error;

 protected:
  void setUp(bool up, const char* why) {
    if (up == reported_) return;
    reported_ = up;
    if (onUp) onUp(up, why);
  }
  bool reported_ = false;
};

// ------------------------------------------------------------------------------------------------------------------------
// Routing: the box listens to the KNX multicast group and writes to it. It takes no tunnel channel.
class RoutingBus : public KnxBus {
 public:
  void begin(const evo::BusCfg&, IPAddress) override {
    udp_.stop();
    ready_ = udp_.beginMulticast(IPAddress(224, 0, 23, 12), 3671);
    error = ready_ ? "" : "could not join the KNX multicast group";
    setUp(ready_, ready_ ? "KNX routing ready" : "KNX routing failed");
  }

  void loop() override {
    if (!ready_) return;
    int n = udp_.parsePacket();
    for (int guard = 0; n > 0 && guard < 16; guard++) {
      uint8_t buf[128];
      int len = udp_.read(buf, sizeof(buf));
      uint16_t svc;
      size_t off, blen;
      if (len > 0 && evo::parseHeader(buf, (size_t)len, svc, off, blen) && svc == evo::SVC_ROUTING_IND) {
        uint8_t code;
        evo::Group g;
        if (evo::parseCemi(buf + off, blen, code, g) && code == evo::CEMI_L_DATA_IND && g.src != KNX_SOURCE_ADDRESS) {
          lastRxMs = millis();
          everRx = true;
          if (onGroup) onGroup(g);
        }
      }
      n = udp_.parsePacket();
    }
  }

  bool up() const override { return ready_; }
  const char* mode() const override { return "routing"; }

  bool send(uint16_t ga, const evo::Payload& p) override {
    if (!ready_) return false;
    // KNX allows about 50 telegrams a second at most: keep 25 ms between two.
    uint32_t since = millis() - lastSend_;
    if (since < 25) delay(25 - since);
    uint8_t buf[64];
    size_t n = evo::buildRouting(buf, KNX_SOURCE_ADDRESS, ga, p);
    if (!udp_.beginPacket(IPAddress(224, 0, 23, 12), 3671)) return false;
    udp_.write(buf, n);
    bool ok = udp_.endPacket() == 1;
    lastSend_ = millis();
    if (ok) {
      lastTxMs = lastSend_;
      everTx = true;
    }
    return ok;
  }

 private:
  WiFiUDP udp_;
  bool ready_ = false;
  uint32_t lastSend_ = 0;
};

// ------------------------------------------------------------------------------------------------------------------------
// Tunneling: the box connects to a KNX IP Interface like the App does (it takes one tunnel channel).
class TunnelBus : public KnxBus {
 public:
  void begin(const evo::BusCfg& cfg, IPAddress local) override {
    cfg_ = cfg;
    local_ = local;
    udp_.stop();
    udp_.begin(kLocalPort);
    remote_ = IPAddress();
    if (!remote_.fromString(cfg.host.c_str())) {
      if (!WiFi.hostByName(cfg.host.c_str(), remote_)) remote_ = IPAddress();
    }
    state_ = ST_IDLE;
    error = remote_ == IPAddress() ? "the address of the interface cannot be found" : "";
    retryAt_ = 0;
    queue_.clear();
    setUp(false, "KNX tunnel closed");
  }

  void loop() override {
    uint32_t now = millis();
    poll(false);
    while (!queue_.empty()) {  // telegrams that came while a write waited for its acknowledge
      evo::Group g = queue_.front();
      queue_.erase(queue_.begin());
      if (onGroup) onGroup(g);
    }
    if (remote_ == IPAddress()) {
      if (now - retryAt_ > 10000 || retryAt_ == 0) {
        retryAt_ = now;
        if (!WiFi.hostByName(cfg_.host.c_str(), remote_)) {
          remote_ = IPAddress();
          error = "the address of the interface cannot be found";
        }
      }
      return;
    }
    switch (state_) {
      case ST_IDLE:
        if (retryAt_ == 0 || now - retryAt_ >= 5000) connect();
        break;
      case ST_CONNECTING:
        if (now - connectAt_ > 3000) {
          error = "the interface does not answer";
          toIdle("KNX tunnel: no answer from the interface");
        }
        break;
      case ST_CONNECTED:
        if (!hbWait_ && now - hbAt_ >= 60000) {
          sendState();
        } else if (hbWait_ && now - hbAt_ >= 10000) {
          if (++hbTries_ >= 3) {
            error = "the interface stopped answering";
            toIdle("KNX tunnel lost (no heartbeat answer)");
          } else {
            sendState();
          }
        }
        break;
    }
  }

  bool up() const override { return state_ == ST_CONNECTED; }
  const char* mode() const override { return "tunnel"; }

  bool send(uint16_t ga, const evo::Payload& p) override {
    if (state_ != ST_CONNECTED) return false;
    uint8_t buf[80];
    size_t n = evo::buildTunnelReq(buf, channel_, seqTx_, ga, p);
    for (int attempt = 0; attempt < 2; attempt++) {
      awaitAck_ = true;
      ackStatus_ = 0xFF;
      raw(buf, n);
      uint32_t t = millis();
      while (awaitAck_ && millis() - t < 1000) {
        poll(true);
        delay(1);
      }
      if (!awaitAck_) break;
    }
    if (awaitAck_) {  // no acknowledge twice: the connection is broken
      awaitAck_ = false;
      error = "the interface did not acknowledge a telegram";
      toIdle("KNX tunnel lost (no acknowledge)");
      return false;
    }
    seqTx_++;
    if (ackStatus_ != 0) return false;
    lastTxMs = millis();
    everTx = true;
    return true;
  }

 private:
  enum State { ST_IDLE, ST_CONNECTING, ST_CONNECTED };
  static constexpr uint16_t kLocalPort = 3672;

  void ipBytes(uint8_t ip[4]) const {
    for (int i = 0; i < 4; i++) ip[i] = local_[i];
  }

  void raw(const uint8_t* d, size_t n) {
    udp_.beginPacket(dataIp_ == IPAddress() ? remote_ : dataIp_, dataIp_ == IPAddress() ? cfg_.port : dataPort_);
    udp_.write(d, n);
    udp_.endPacket();
  }

  void connect() {
    uint8_t ip[4], buf[40];
    ipBytes(ip);
    dataIp_ = IPAddress();
    size_t n = evo::buildConnectReq(buf, ip, kLocalPort);
    raw(buf, n);
    state_ = ST_CONNECTING;
    connectAt_ = millis();
    retryAt_ = connectAt_;
  }

  void sendState() {
    uint8_t ip[4], buf[24];
    ipBytes(ip);
    size_t n = evo::buildStateReq(buf, channel_, ip, kLocalPort);
    raw(buf, n);
    hbWait_ = true;
    hbAt_ = millis();
  }

  void toIdle(const char* why) {
    state_ = ST_IDLE;
    retryAt_ = millis();
    hbWait_ = false;
    setUp(false, why);
  }

  // Reads what has arrived. With [defer] the telegrams of the bus are kept for the main loop (used while a write waits for its acknowledge).
  void poll(bool defer) {
    int n = udp_.parsePacket();
    for (int guard = 0; n > 0 && guard < 16; guard++) {
      uint8_t buf[128];
      int len = udp_.read(buf, sizeof(buf));
      if (len > 0) handle(buf, (size_t)len, defer);
      n = udp_.parsePacket();
    }
  }

  void handle(const uint8_t* d, size_t len, bool defer) {
    uint16_t svc;
    size_t off, blen;
    if (!evo::parseHeader(d, len, svc, off, blen)) return;
    const uint8_t* b = d + off;
    switch (svc) {
      case evo::SVC_CONNECT_RES:
        if (state_ != ST_CONNECTING || blen < 2) return;
        if (b[1] != 0) {
          error = b[1] == 0x24 ? "the interface has no free tunnel channel left" : "the interface refused the connection (code " + std::to_string(b[1]) + ")";
          toIdle("KNX tunnel refused");
          return;
        }
        channel_ = b[0];
        dataIp_ = IPAddress();
        if (blen >= 10 && (b[4] | b[5] | b[6] | b[7]) != 0) {
          dataIp_ = IPAddress(b[4], b[5], b[6], b[7]);
          dataPort_ = (uint16_t)((b[8] << 8) | b[9]);
        }
        seqTx_ = 0;
        seqRx_ = 0;
        hbAt_ = millis();
        hbWait_ = false;
        hbTries_ = 0;
        state_ = ST_CONNECTED;
        error = "";
        setUp(true, "KNX tunnel connected");
        break;
      case evo::SVC_STATE_RES:
        if (blen >= 2 && b[0] == channel_) {
          if (b[1] == 0) {
            hbWait_ = false;
            hbTries_ = 0;
            hbAt_ = millis();
          } else {
            error = "the interface closed the tunnel";
            toIdle("KNX tunnel closed by the interface");
          }
        }
        break;
      case evo::SVC_DISCONNECT_REQ:
        if (blen >= 1 && b[0] == channel_ && state_ != ST_IDLE) {
          uint8_t out[8];
          size_t n = evo::buildDisconnectRes(out, channel_, 0);
          raw(out, n);
          error = "the interface closed the tunnel";
          toIdle("KNX tunnel closed by the interface");
        }
        break;
      case evo::SVC_TUNNEL_ACK:
        if (awaitAck_ && blen >= 4 && b[1] == channel_ && b[2] == seqTx_) {
          ackStatus_ = b[3];
          awaitAck_ = false;
        }
        break;
      case evo::SVC_TUNNEL_REQ: {
        if (state_ != ST_CONNECTED || blen < 4 || b[1] != channel_) return;
        uint8_t seq = b[2];
        uint8_t out[12];
        size_t n = evo::buildTunnelAck(out, channel_, seq, 0);
        raw(out, n);
        if (seq != seqRx_) return;  // a repeat of one we already have
        seqRx_++;
        uint8_t code;
        evo::Group g;
        if (evo::parseCemi(b + 4, blen - 4, code, g) && code == evo::CEMI_L_DATA_IND) {
          lastRxMs = millis();
          everRx = true;
          if (defer) {
            if (queue_.size() < 16) queue_.push_back(g);
          } else if (onGroup) {
            onGroup(g);
          }
        }
        break;
      }
      default:
        break;
    }
  }

  WiFiUDP udp_;
  evo::BusCfg cfg_;
  IPAddress local_, remote_, dataIp_;
  uint16_t dataPort_ = 3671;
  State state_ = ST_IDLE;
  uint8_t channel_ = 0, seqTx_ = 0, seqRx_ = 0, hbTries_ = 0;
  bool awaitAck_ = false, hbWait_ = false;
  uint8_t ackStatus_ = 0;
  uint32_t connectAt_ = 0, retryAt_ = 0, hbAt_ = 0;
  std::vector<evo::Group> queue_;
};
