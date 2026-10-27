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

# Component names in ESP-IDF 6.0 build_components. This list is the network,
# HTTP and OTA-update surface, not the stock partition layer: `app_update` is a
# hard private requirement of esp_partition and is always in the baseline. It
# is harmless here because the partition table has no OTA slot and none of the
# update components above it are present (see the ADR/progress note in T04).
FORBIDDEN_COMPONENTS = {
    "esp_http_client",
    "esp_http_server",
    "esp_https_ota",
    "esp_https_server",
    "esp_netif",
    "esp_netif_stack",
    "esp_websocket_client",
    "esp_wifi",
    "http_parser",
    "lwip",
    "mqtt",
    "esp-tls",
    "tcp_transport",
}


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
    check_partitions(args.partitions)
    print(
        f"image guard: ok ({TARGET}, {len(components)} components, no "
        f"Wi-Fi/HTTP/OTA, no-OTA partition table)"
    )


if __name__ == "__main__":
    main()
