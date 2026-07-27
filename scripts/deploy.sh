#!/usr/bin/env bash
# Turnkey deploy — the bridge and the phone, from one script.
#
#   ./scripts/deploy.sh doctor          what's installed, what's missing
#   ./scripts/deploy.sh bridge          flash the ESP32-S3 over USB
#   ./scripts/deploy.sh app             build + install the Android app
#
# WHY THIS EXISTS ALONGSIDE `make flash`. `make flash` is the developer path:
# it needs ESP-IDF (a ~2 GB toolchain) because it *builds* first. This script
# is the deploy path: it writes an already-built merged image with nothing but
# `esptool`, so somebody who just wants the bridge running does not install a
# compiler. Both write the same bytes to the same board.
#
# It writes over USB, never over the air — §12.6 rule 8. A board that a USB
# cable can always recover is a board you cannot brick.
#
# Windows: run from Git Bash (the same shell the Makefile assumes). Serial
# ports are COM3, COM7, … and pass through unmangled.

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

CHIP=esp32s3
BAUD=460800
FW_BUILD=firmware/build/heltec-v3
DIST=dist

bold=$(printf '\033[1m'); dim=$(printf '\033[2m'); red=$(printf '\033[31m')
green=$(printf '\033[32m'); yellow=$(printf '\033[33m'); off=$(printf '\033[0m')
[ -t 1 ] || { bold=; dim=; red=; green=; yellow=; off=; }

say()  { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$bold" "$off" "$*"; }
warn() { printf '%s!%s   %s\n' "$yellow" "$off" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$red" "$off" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# The project version, read from the firmware config rather than typed here —
# release.yml already fails a build where the tag, the firmware and the app
# disagree, so there is exactly one place this number lives.
project_version() {
  sed -n 's/^CONFIG_APP_PROJECT_VER="\(.*\)"$/\1/p' firmware/sdkconfig.defaults
}

confirm() {
  [ "${ASSUME_YES:-0}" = 1 ] && return 0
  printf '%s [y/N] ' "$1"
  read -r reply </dev/tty || return 1
  case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ── esptool ──────────────────────────────────────────────────────────────
#
# Three spellings in the wild and all three are fine. Resolved once into
# ESPTOOL[@] so the call sites stay readable.
ESPTOOL=()
find_esptool() {
  if have esptool.py; then ESPTOOL=(esptool.py)
  elif have esptool; then ESPTOOL=(esptool)
  elif have python3 && python3 -c 'import esptool' 2>/dev/null; then ESPTOOL=(python3 -m esptool)
  elif have python && python -c 'import esptool' 2>/dev/null; then ESPTOOL=(python -m esptool)
  else return 1
  fi
}

# esptool v5 renamed every subcommand to kebab-case and warns loudly on the
# legacy spelling; v4 only knows the legacy one. Pick by version so neither
# generation prints noise the user then has to evaluate.
esptool_cmd() {
  local want=$1 major
  major=$("${ESPTOOL[@]}" version 2>/dev/null | sed -n 's/^v\{0,1\}\([0-9]\{1,\}\)\..*/\1/p' | head -n 1)
  if [ "${major:-4}" -ge 5 ] 2>/dev/null; then
    printf '%s' "${want//_/-}"
  else
    printf '%s' "$want"
  fi
}

# ── serial port ──────────────────────────────────────────────────────────
#
# esptool auto-detects when handed no port, which is the right default. We
# only look ourselves so the script can SAY which board it found — "flashing
# COM7" is a sentence somebody can check before saying yes.
detect_ports() {
  case "$(uname -s)" in
    Linux*)  ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true ;;
    Darwin*) ls /dev/cu.usbserial* /dev/cu.usbmodem* /dev/cu.SLAB* /dev/cu.wchusbserial* 2>/dev/null || true ;;
    *)       # Git Bash / MSYS: ask Windows, which is the only thing that knows.
             powershell.exe -NoProfile -Command \
               '(Get-CimInstance Win32_SerialPort).DeviceID' 2>/dev/null | tr -d '\r' || true ;;
  esac
}

# ── the merged image ─────────────────────────────────────────────────────
#
# One file at offset 0: bootloader + partition table + otadata + app, already
# assembled by `dart run flash` from the build's own flasher_args.json. A
# single part cannot be written to the wrong offset, which is most of why the
# release ships this shape rather than four loose binaries.
newest_image() {
  ls -t "$DIST"/smoke-bridge-heltec-v3-*.bin 2>/dev/null | head -n 1
}

build_image() {
  step "Building firmware (needs ESP-IDF)"
  make build
  step "Packing the merged image"
  dart run flash --build "$FW_BUILD" --version "$(project_version)" --out "$DIST"
}

# ── doctor ───────────────────────────────────────────────────────────────

cmd_doctor() {
  local ok=0
  row() { # name, present?, why-you-need-it
    if [ "$2" = 1 ]; then printf '  %sok%s   %-10s %s\n' "$green" "$off" "$1" "$3"
    else printf '  %s--%s   %-10s %s\n' "$dim" "$off" "$1" "$3"; ok=1; fi
  }
  say "${bold}Deploy the bridge${off} (./scripts/deploy.sh bridge)"
  find_esptool && row esptool 1 "flashes the board" || row esptool 0 "flashes the board — pip install esptool"
  [ -n "$(newest_image)" ] && row image 1 "$(newest_image)" || row image 0 "no merged image in $DIST/ — pass --build, or download a release"
  [ -n "$(detect_ports)" ] && row port 1 "$(detect_ports | tr '\n' ' ')" || row port 0 "no serial port seen — plug the board in"
  say ""
  say "${bold}Deploy the app${off} (./scripts/deploy.sh app)"
  have flutter && row flutter 1 "builds the APK" || row flutter 0 "builds the APK — https://docs.flutter.dev/get-started/install"
  have adb && row adb 1 "installs it on the phone" || row adb 0 "installs it on the phone — part of Android platform-tools"
  if have adb; then
    local n; n=$(adb devices | tail -n +2 | grep -c '\bdevice$' || true)
    [ "${n:-0}" -gt 0 ] && row device 1 "$n connected" || row device 0 "no device — enable USB debugging and accept the prompt"
  fi
  say ""
  say "${bold}Build from source${off} (make build · make test-host)"
  have dart && row dart 1 "tools, codegen, simulator" || row dart 0 "tools, codegen, simulator"
  have cmake && row cmake 1 "host unit tests" || row cmake 0 "host unit tests"
  { [ -f "${IDF_PATH:-$HOME/esp/esp-idf}/export.sh" ] && row esp-idf 1 "${IDF_PATH:-$HOME/esp/esp-idf}"; } \
    || row esp-idf 0 "only needed to BUILD firmware, not to flash it"
  return $ok
}

# ── bridge ───────────────────────────────────────────────────────────────

cmd_bridge() {
  local port="" image="" do_build=0 do_erase=0 do_monitor=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --port)    port=${2:?--port needs a value}; shift 2 ;;
      --image)   image=${2:?--image needs a value}; shift 2 ;;
      --build)   do_build=1; shift ;;
      --erase)   do_erase=1; shift ;;
      --monitor) do_monitor=1; shift ;;
      --yes|-y)  ASSUME_YES=1; shift ;;
      *) die "unknown option for 'bridge': $1" ;;
    esac
  done

  find_esptool || die "esptool not found.

  Install it:            pip install esptool
  Or flash from Chrome:  open tools/installer/index.html from a release
                         (esp-web-tools — no Python, no toolchain)"

  if [ -z "$image" ]; then
    image=$(newest_image)
    if [ -z "$image" ] && [ "$do_build" = 1 ]; then
      build_image
      image=$(newest_image)
    fi
  fi
  [ -n "$image" ] && [ -f "$image" ] || die "no merged image to flash.

  Build one:      ./scripts/deploy.sh bridge --build     (needs ESP-IDF)
  Or download:    smoke-bridge-heltec-v3-<version>.bin from a GitHub release,
                  then:  ./scripts/deploy.sh bridge --image <file>"

  if [ -z "$port" ]; then
    local found; found=$(detect_ports)
    case $(printf '%s' "$found" | grep -c . || true) in
      0) warn "no serial port detected — letting esptool find one" ;;
      1) port=$found ;;
      *) die "several serial ports are present; name the board's one:
$(printf '%s\n' "$found" | sed 's/^/    /')
    ./scripts/deploy.sh bridge --port <PORT>" ;;
    esac
  fi

  say ""
  say "  image   $image ($(wc -c <"$image" | tr -d ' ') bytes)"
  say "  board   $CHIP @ ${port:-auto-detect}"
  if [ "$do_erase" = 1 ]; then
    say "  writes  offset 0x0, after erasing the whole flash"
  else
    say "  writes  offset 0x0"
  fi
  say ""
  warn "Never power this board with the LoRa antenna disconnected (01 §1.5) —"
  warn "transmitting into an open port can destroy the SX1262."
  say ""
  if [ "$do_erase" = 1 ]; then
    warn "--erase wipes every cook stored on the bridge. There is no undo."
  fi
  confirm "Flash it?" || { say "Nothing written."; exit 0; }

  local port_arg=(); [ -n "$port" ] && port_arg=(-p "$port")

  if [ "$do_erase" = 1 ]; then
    step "Erasing flash"
    "${ESPTOOL[@]}" --chip "$CHIP" "${port_arg[@]}" "$(esptool_cmd erase_flash)"
  fi

  step "Writing $image"
  "${ESPTOOL[@]}" --chip "$CHIP" "${port_arg[@]}" -b "$BAUD" \
    "$(esptool_cmd write_flash)" 0x0 "$image"

  say ""
  say "${green}Flashed.${off} The bridge boots into pairing mode with the OLED showing"
  say "a passkey. Next: install the app and follow the three-hop setup —"
  say "  ./scripts/deploy.sh app"
  say ""

  if [ "$do_monitor" = 1 ]; then
    step "Serial monitor (ctrl-] to quit)"
    if have python3 && python3 -c 'import serial.tools.miniterm' 2>/dev/null; then
      python3 -m serial.tools.miniterm "${port:-$(detect_ports | head -n 1)}" 115200
    elif have idf.py; then
      idf.py -p "${port:-$(detect_ports | head -n 1)}" monitor
    else
      warn "no monitor available (pip install pyserial), skipping"
    fi
  fi
}

# ── app ──────────────────────────────────────────────────────────────────

cmd_app() {
  local apk="" device="" do_run=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apk)    apk=${2:?--apk needs a value}; shift 2 ;;
      --device) device=${2:?--device needs a value}; shift 2 ;;
      --run)    do_run=1; shift ;;
      --yes|-y) ASSUME_YES=1; shift ;;
      *) die "unknown option for 'app': $1" ;;
    esac
  done

  have adb || die "adb not found — install Android platform-tools.
  It ships with Android Studio, or:  https://developer.android.com/tools/releases/platform-tools"

  # `adb devices` lists one header line then TAB-separated rows. Anything not
  # in state `device` (unauthorized, offline) is not installable, and saying
  # so beats an install that fails four steps later.
  local devices; devices=$(adb devices | tail -n +2 | grep -c '\bdevice$' || true)
  if [ "${devices:-0}" = 0 ]; then
    adb devices | tail -n +2 | grep -q 'unauthorized' \
      && die "the phone is connected but unauthorized — accept the 'Allow USB debugging' prompt on its screen." \
      || die "no Android device connected.

  1. Enable Developer options (tap Build number 7×), then USB debugging.
  2. Plug the phone in and accept the prompt.
  3. Re-run this."
  fi
  if [ "$devices" -gt 1 ] && [ -z "$device" ]; then
    die "several devices connected; name one with --device <serial>:
$(adb devices | tail -n +2 | sed 's/^/    /')"
  fi
  local dev_arg=(); [ -n "$device" ] && dev_arg=(-s "$device")

  if [ "$do_run" = 1 ]; then
    have flutter || die "flutter not found — https://docs.flutter.dev/get-started/install"
    step "flutter run (hot reload; ctrl-c to stop)"
    ( cd app && flutter run ${device:+-d "$device"} )
    return
  fi

  if [ -z "$apk" ]; then
    have flutter || die "flutter not found, and no --apk given.
  Either install Flutter, or pass a release APK:
    ./scripts/deploy.sh app --apk smoke-bridge-<version>.apk"
    step "Building the release APK"
    ( cd app && flutter pub get && flutter build apk --release )
    apk=app/build/app/outputs/flutter-apk/app-release.apk
  fi
  [ -f "$apk" ] || die "no such APK: $apk"

  step "Installing on $(adb "${dev_arg[@]}" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
  # -r reinstalls over an existing copy and KEEPS its data, so a redeploy does
  # not throw away the bridge pairing or a running cook.
  adb "${dev_arg[@]}" install -r "$apk"

  say ""
  say "${green}Installed.${off} Open Smoke Bridge on the phone. It scans for the"
  say "bridge over Bluetooth, so no Wi-Fi setup is required to see temperatures."
}

# ── entry ────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Smoke X4 Smart Bridge — deploy

  ./scripts/deploy.sh doctor
      What's installed, what's missing, and what each thing is for.

  ./scripts/deploy.sh bridge [options]      flash the ESP32-S3 over USB
      --image FILE   merged image to write (default: newest in dist/)
      --build        build it first (needs ESP-IDF)
      --port PORT    serial port (default: auto-detect)
      --erase        wipe the flash first — DELETES STORED COOKS
      --monitor      open a serial monitor afterwards
      -y, --yes      don't ask for confirmation

  ./scripts/deploy.sh app [options]         install the Android app
      --apk FILE     install this APK instead of building one
      --device SN    target device, when more than one is connected
      --run          flutter run instead (hot reload, for development)
      -y, --yes      don't ask for confirmation

Developers building firmware from source want `make` instead:
  make build · make flash-monitor · make test-host · make sim
EOF
}

case "${1:-}" in
  bridge) shift; cmd_bridge "$@" ;;
  app)    shift; cmd_app "$@" ;;
  doctor) shift; cmd_doctor ;;
  ""|-h|--help|help) usage ;;
  *) usage >&2; die "unknown command: $1" ;;
esac
