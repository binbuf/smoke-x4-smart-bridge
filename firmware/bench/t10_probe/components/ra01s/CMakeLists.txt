set(component_srcs "ra01s.c")

idf_component_register(
    SRCS "${component_srcs}"
    REQUIRES driver esp_driver_spi
    PRIV_REQUIRES esp_driver_gpio
    INCLUDE_DIRS "."
)

# Bench-only pin map for the Heltec V3. This is the vendored ra01s driver
# copied from legacy/ for the T10 capture probe; T12 vendors the product driver.
target_compile_definitions(${COMPONENT_LIB} PRIVATE
    CONFIG_SPI2_HOST=1
    CONFIG_MISO_GPIO=11
    CONFIG_MOSI_GPIO=10
    CONFIG_SCLK_GPIO=9
    CONFIG_NSS_GPIO=8
    CONFIG_RST_GPIO=12
    CONFIG_BUSY_GPIO=13
    CONFIG_TXEN_GPIO=-1
    CONFIG_RXEN_GPIO=-1
)
