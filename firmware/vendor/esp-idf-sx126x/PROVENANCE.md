# Provenance — esp-idf-sx126x / ra01s

Vendored source, not a build-time dependency. Copied from the legacy reference
tree at `legacy/firmware/vendor/esp-idf-sx126x/`, which is a snapshot of:

- Upstream: <https://github.com/nopnop2002/esp-idf-sx126x>
- Driver: `components/ra01s`
- Licence: MIT, Copyright (c) 2022 nopnop2002 (see `LICENSE`)
- Snapshot date: 2026-10-26
- Upstream commit: **not recorded in the legacy snapshot** (the legacy tree has
  a `.gitmodules` entry but no submodule commit metadata). Treat this as a
  known-good source snapshot, not a reproducible commit pin. If the exact
  upstream commit is recovered, add it here and re-vendor rather than editing
  the driver in place.

The vendored files are unchanged from the legacy snapshot apart from this note
and the component wiring. Do not fork the driver behaviour here; later radio
work belongs in `firmware/components/sx_radio/`.

Heltec V3 pins are set in `firmware/sdkconfig.defaults.heltec-v3` via the
driver's own Kconfig options: SCK 9, MOSI 10, MISO 11, NSS 8, RST 12, BUSY 13,
no TXEN/RXEN, SPI2.
