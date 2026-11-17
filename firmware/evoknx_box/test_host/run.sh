#!/bin/sh
# Builds and runs the PC tests. Usage: ARDUINOJSON=/path/to/ArduinoJson/src ./run.sh
set -e
cd "$(dirname "$0")"
g++ -std=c++17 -Wall -Wextra -I../src/core -I"${ARDUINOJSON:?set ARDUINOJSON to the src folder of ArduinoJson 7}" host_test.cpp -o /tmp/evoknx_host_test
/tmp/evoknx_host_test
