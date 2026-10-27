# ESP-IDF project root. Build from this directory after activating ESP-IDF:
#   idf.py -B build \
#     -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
#
# The target (esp32s3), no-OTA partition table and the no-Wi-Fi/no-HTTP/no-OTA
# component guard are set by sdkconfig.defaults and this file.
cmake_minimum_required(VERSION 3.16)

set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/vendor/esp-idf-sx126x/components")

# ESP-IDF 6's disabled esp_wifi fallback still exposes esp_mesh.h, which
# includes lwip/ip_addr.h although Wi-Fi/lwip are not built. A header-only shim
# keeps the BLE-only image free of the network stack (ADR 0034).
include_directories("${CMAKE_CURRENT_LIST_DIR}/compat/include")

# Build only main and its transitive requirements. ESP-IDF would otherwise build
# every component in the IDF tree, including Wi-Fi, HTTP and OTA, even though
# nothing links them. This list is the image-content boundary; the post-build
# guard proves the linked set stays clean.
#
# `bt` is listed for T27's NimBLE GATT server. ESP-IDF 6's bt component pulls
# esp_wifi as a build requirement even for a NimBLE-only image; the image guard
# is updated in ADR 0034 to distinguish that inert controller dependency from
# an initialised network stack. `espcoredump` is listed so panic dumps actually
# land in the coredump partition; it is registered as a whole-archive panic
# handler.
set(COMPONENTS main espcoredump bt)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(sx4_bridge)

# The image must not contain Wi-Fi, IP/HTTP or OTA components (ADR 0001/0006).
# This runs in the top-level directory because add_custom_command can only
# attach a POST_BUILD step to a target created in the same directory.
idf_build_get_property(sx4_python PYTHON)
add_custom_command(TARGET ${CMAKE_PROJECT_NAME}.elf POST_BUILD
    COMMAND "${sx4_python}"
            "${CMAKE_CURRENT_LIST_DIR}/tools/check_image.py"
            --build-dir "${CMAKE_BINARY_DIR}"
            --partitions "${CMAKE_CURRENT_LIST_DIR}/partitions.csv"
    COMMENT "Checking image for Wi-Fi/HTTP/OTA components"
    VERBATIM
)
