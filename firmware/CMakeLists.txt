cmake_minimum_required(VERSION 3.16)

# ESP-IDF v5.4+ (builds on v6.0.2), target esp32s3 (Heltec WiFi LoRa 32 V3).
# See design 03.
#
# Trim the build to main + transitive dependencies: IDF otherwise compiles
# every bundled component (esp_lcd, perfmon, …) we never link. This keeps
# builds fast and keeps unrelated IDF code out of our -Werror surface.
set(COMPONENTS main)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(smoke_bridge)
