# EvoKNX Box (ESP32 firmware)

A small box that runs **timers** (schedules and countdowns) when the App is closed.

* The timers are **made on the phone** (EvoKNX App, Settings, Schedulers) and sent with *Save*. The box keeps them in its own flash and runs them. They can be switched on/off, edited, run by hand and read back from any phone.
* The Editor only declares the box (Connections, *EvoKNX Box*) and chooses which **1-bit group addresses** the timers may switch (tab *Schedulers*, On/Off only). It also sends the box its settings (name, time zone, how it reaches the bus).
* **Schedule**: writes On or Off to an address at a time of day, on chosen days.
* **Countdown**: starts when an address gets a value and writes On/Off after a time you set. Any other value on that address cancels it.
* Reaches the KNX bus by **routing** (KNX IP Router, no tunnel channel used) or **tunneling** (KNX IP Interface, one tunnel channel).
* Keeps the timers and a log of the last 7 days in its own flash. No SD card.
* The web page of the box (`http://<box address>/`) is read-only and opens without a login from the home network: connection, timers, log of 7 days. The time is set from the App.

## Build and upload

1. Install PlatformIO (VS Code extension).
2. Open `src/board.h` and fill in the Ethernet pins from the **schematic of your board** (W5500: CS, INT, RST, SCK, MISO, MOSI). The build stops with a message until this is done. For a first try on a bare ESP32 with Wi-Fi, define `USE_WIFI` and your Wi-Fi.
3. Connect the board by USB and run `pio run -t upload`.
4. Put the box on the network. In the Editor: Connections, *Add connection*, *EvoKNX Box*, *Find box*, *Connect*. The Editor makes a hidden key and gives it to the box once. Nobody types or reads a code.
5. Send the configuration to the phones as usual: the key and the address of the box travel inside it.

To give the box to another project: hold the BOOT button for 3 seconds while powering it on. The key is forgotten (the timers stay) and the box can be claimed again.

Updates later can be done over the network (ArduinoOTA, the password is the key), once the box has a key.

> I could not build or run this firmware where it was written (no ESP32 and no Arduino toolchain there). The logic (timers, frames, settings, log) is tested on a PC (`test_host`), and the signing is tested against the Editor. The parts that touch the board (Ethernet pins, the Arduino libraries, the real KNX bus) need a first test on the real board. If the build shows an error, send the log.

## What the box does and does not do

* A schedule that is due while the box is off or has no valid time is **not** run later.
* Without Internet the box has no time. Set it from the App (Schedulers, *Set time from phone*). Schedules do not run while the time is not set.
* A countdown that is running is lost when the box restarts.
* If the bus is not available when a countdown ends, the box tries again every 5 seconds, up to 12 times, then writes an error in the log.
* The time zone comes from the Editor (no daylight saving).

## Security

* **Claim**: a box without a key accepts `POST /api/claim {"key"}` once, and only from a private network address (192.168.x, 10.x, 172.16–31.x). After that it answers 409 until the BOOT button clears the key.
* **Reading** (`/api/status`, `/api/config`, `/api/log`) is open from a private address. From any other address it needs a signature.
* **Changing** (`/api/config`, `/api/settings`, `/api/run`, `/api/time`) always needs a signature: `HMAC-SHA256(key, nonce \n METHOD \n path \n body)`. The nonce is given by the box, valid 30 seconds, used once. The key never travels on the network.
* After 8 wrong signatures in a minute the box answers 429 for the rest of the minute.
* If you open a port of the router to the box (to use the App away from home), the timers can be read by anyone who finds the port only with a valid signature, and changed only with the key. The traffic is plain HTTP: it is not encrypted. A VPN is better.
* KNX itself has no security here: anybody who can reach the bus can send telegrams.

## API

| Call | What |
|---|---|
| `GET /api/info` | name, firmware, id, `claimed` (always open) |
| `GET /api/challenge` | a one-time number to sign |
| `POST /api/claim` | gives the box its key (home network, once) |
| `GET /api/status` | bus, time, number of timers, countdowns running, version of the timers |
| `GET /api/config`, `POST /api/config` | the timers (`timers` run by the box, `ui` kept for the phones) |
| `POST /api/settings` | name, time zone, bus (from the Editor) |
| `GET /api/log` | events of the last 7 days |
| `POST /api/run` `{"id"}` | runs a timer now (test) |
| `POST /api/time` `{"ntp"}` `{"sync":true}` `{"set":epoch}` | time server, synchronise, set by hand |

UDP discovery: send `EVOKNX-BOX?` to port 47803 (broadcast); the box answers with a JSON line.

## Tests on a PC

```
cd test_host
g++ -std=c++17 -I../src/core -I<ArduinoJson>/src host_test.cpp -o host_test && ./host_test
```

`vectors.h` is made by `dart run tool/box_vectors.dart` in `packages/knx_config`: the frames are built by the same code the App uses, so the firmware and the App agree.
