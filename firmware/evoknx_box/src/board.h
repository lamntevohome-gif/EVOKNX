// Settings of the board. Fill in the pins of YOUR board from its schematic before you build.
#pragma once

// ---- Network ------------------------------------------------------------------------------------------------------------
// The box uses a cable (Ethernet) because it is more stable than Wi-Fi. Boards like the KinCony AG8 have a W5500 Ethernet chip on SPI.
// Put its pins here (the numbers are the GPIO numbers in the schematic).
#define ETH_W5500_CS -1
#define ETH_W5500_INT -1
#define ETH_W5500_RST -1
#define ETH_SPI_SCK -1
#define ETH_SPI_MISO -1
#define ETH_SPI_MOSI -1

// For a first try on a bare ESP32 board without Ethernet: remove the two slashes and fill in your Wi-Fi.
// #define USE_WIFI
#define WIFI_SSID ""
#define WIFI_PASS ""

// ---- Other ---------------------------------------------------------------------------------------------------------------
#define BOOT_BUTTON_PIN 0                // hold it for 3 seconds while powering up to make a new pairing code
#define KNX_SOURCE_ADDRESS 0xFFFA        // 15.15.250: the address the box writes from in routing mode
#define FW_VERSION "0.1.0"

#if !defined(USE_WIFI) && (ETH_W5500_CS < 0 || ETH_SPI_SCK < 0 || ETH_SPI_MISO < 0 || ETH_SPI_MOSI < 0)
#error "Fill in the Ethernet pins in src/board.h (from the schematic of your board), or define USE_WIFI for a test."
#endif
