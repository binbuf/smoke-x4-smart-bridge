#!/usr/bin/env python3
"""Fail the firmware build if the image carries forbidden components.

The MVP is BLE-only and updates over USB: the image must not contain Wi-Fi, an
IP stack, HTTP, or OTA support (ADR 0001, ADR 0006). The ESP-IDF build writes
the linked component set to build/project_description.json; this script checks
that set plus the partition table and target.

Run by main/CMakeLists.txt after the .elf is linked, and usable by hand:

    python firmware/tools/check_image.py --build-dir firmware/build \
        --partitions firmware/partitions.csv
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Component names in ESP-IDF 6.0 build_components. Anything in this list is a
# hard failure: HTTP/TLS/MQTT/WebSocket and OTA update code have no place in the
# BLE-only image (ADR 0001, ADR 0006). Wi-Fi/IP/ethernet components are checked
# separately because ESP-IDF 6's bt component requires esp_wifi at build time;
# T27 overrides esp_wifi with an empty local component and the linked-object
# check below proves no Wi-Fi, lwip or esp_netif code reached the image.
FORBIDDEN_COMPONENTS = {
    "esp_http_client",
    "esp_http_server",
    "esp_https_ota",
    "esp_https_server",
    "esp_websocket_client",
    "http_parser",
    "mqtt",
    "esp-tls",
    "tcp_transport",
}

# Object files from these archives must never be linked. The build_components
# list may still contain the component names while they are inert build deps.
FORBIDDEN_LINKED_ARCHIVES = (
    "liblwip.a:",
    "libesp_netif.a:",
    "libesp_netif_stack.a:",
    "libwpa_supplicant.a:",
    "libesp_wifi.a:",
)

TARGET = "esp32s3"


def fail(message: str) -> None:
    print(f"image guard: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def check_description(build_dir: Path) -> list[str]:
    description = build_dir / "project_description.json"
    if not description.is_file():
        fail(f"missing {description} (build first)")
    data = json.loads(description.read_text(encoding="utf-8"))

    target = data.get("target")
    if target != TARGET:
        fail(f"target is {target!r}, expected {TARGET!r}")

    build_components = set(data.get("build_components", []))
    if not build_components:
        fail("project_description.json lists no build_components")

    found = sorted(build_components & FORBIDDEN_COMPONENTS)
    if found:
        fail("forbidden components linked: " + ", ".join(found))
    return sorted(build_components)


def check_linked_network(build_dir: Path) -> None:
    """Reject linked Wi-Fi/lwIP/netif objects in the ELF map.

    `build_components` is not enough: ESP-IDF 6 lists esp_wifi/lwip because bt
    requires esp_wifi, but the local esp_wifi override and disabled lwip leave
    them unlinked. The map's archive-member notation (`*libfoo.a:bar.*`) only
    appears for objects that actually reached the image, so this is the proof
    that the binary has no network stack.
    """
    maps = sorted(build_dir.glob("*.map"))
    if not maps:
        fail(f"missing linker map in {build_dir} (build first)")
    text = maps[0].read_text(encoding="utf-8", errors="replace")
    found = [pattern for pattern in FORBIDDEN_LINKED_ARCHIVES if pattern in text]
    if found:
        fail("network objects linked: " + ", ".join(found))


def check_partitions(partitions: Path) -> None:
    if not partitions.is_file():
        fail(f"missing partition table {partitions}")
    for lineno, raw in enumerate(
        partitions.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        fields = [field.strip() for field in line.split(",")]
        if len(fields) < 3:
            fail(f"{partitions}:{lineno}: malformed partition row")
        ptype, subtype = fields[1].lower(), fields[2].lower()
        if ptype == "ota" or subtype.startswith("ota"):
            fail(f"{partitions}:{lineno}: OTA slot {fields[0]!r} is not allowed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=Path("build"))
    parser.add_argument(
        "--partitions", type=Path, default=Path(__file__).resolve().parents[1] / "partitions.csv"
    )
    args = parser.parse_args()

    components = check_description(args.build_dir)
    check_linked_network(args.build_dir)
    check_partitions(args.partitions)
    print(
        f"image guard: ok ({TARGET}, {len(components)} components, no linked "
        f"Wi-Fi/lwIP/netif stack, no HTTP/OTA, no-OTA partition table)"
    )


if __name__ == "__main__":
    main()
