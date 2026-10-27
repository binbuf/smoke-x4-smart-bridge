#!/usr/bin/env python3
"""Fail if the app or firmware gains a network, MQTT or OTA dependency.

The MVP is BLE-only and updates over USB (ADR 0001 and ADR 0006). CI job 6 is a
hard guard, separate from the firmware image guard: it fails at the dependency
manifest before anyone can build a Wi-Fi/HTTP/MQTT/OTA path.

Checked surfaces:

- ``app/pubspec.yaml`` direct dependencies (including dev dependencies);
- ``app/pubspec.lock`` resolved packages, so a forbidden transitive package
  cannot slip in;
- the release Android manifest, for INTERNET/network/notification/foreground
  permissions (the debug/profile manifests need INTERNET for the Flutter tool);
- every tracked ``firmware/**/idf_component.yml``;
- ``firmware/**/CMakeLists.txt`` component lists (``set(COMPONENTS ...)``,
  ``REQUIRES`` and ``PRIV_REQUIRES``);
- ``firmware/sdkconfig.defaults*`` for enabled Wi-Fi/IP/HTTP/MQTT/OTA symbols.

Run from the repository root:

    python tools/ci/check_forbidden_deps.py

The companion unittest, ``tools/ci/test_check_forbidden_deps.py``, proves the
guard catches each class of violation on a synthetic tree.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

# Package names are compared case-insensitively after normalisation. Keep the
# list to the anti-tasks: network clients, WebSocket, MQTT and OTA. BLE packages
# (for example flutter_blue_plus) are intentionally allowed.
FORBIDDEN_APP_PACKAGES = {
    "http",
    "http_client",
    "dio",
    "chopper",
    "retrofit",
    "graphql",
    "grpc",
    "web_socket",
    "web_socket_channel",
    "websocket",
    "websocket_client",
    "mqtt",
    "mqtt_client",
    "mqtt5",
    "flutter_mqtt",
    "ota",
    "ota_update",
    "flutter_ota",
    "shorebird_code_push",
}

# ESP-IDF component names, matching firmware/tools/check_image.py's linked-image
# boundary. app_update is deliberate: esp_partition privately requires it, and
# the no-OTA guarantee comes from the partition table plus the absence of the
# update components above it.
FORBIDDEN_FIRMWARE_COMPONENTS = {
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

FORBIDDEN_PERMISSIONS = {
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
}

# Enabled Kconfig symbols are checked only in uncommented lines. The current
# defaults document these symbols as deliberately absent; turning one on here
# is the signal we care about.
FORBIDDEN_KCONFIG = (
    "CONFIG_ESP_WIFI_ENABLED",
    "CONFIG_ESP_WIFI_REMOTE_ENABLED",
    "CONFIG_ESP_WIFI_NAN_ENABLED",
    "CONFIG_LWIP_ENABLE",
    "CONFIG_ESP_NETIF_ENABLE",
    "CONFIG_ESP_HTTP_CLIENT_ENABLED",
    "CONFIG_ESP_HTTP_SERVER_ENABLED",
    "CONFIG_ESP_HTTPS_OTA",
    "CONFIG_ESP_WEBSOCKET_CLIENT_ENABLED",
    "CONFIG_MQTT_PROTOCOL_311",
    "CONFIG_MQTT_TASK",
)

SKIP_DIRS = {"build", "managed_components", "legacy", ".git", ".dart_tool"}


def normalise_package(name: object) -> str:
    text = str(name).strip().strip("'\"").lower()
    # A dependency may be written as `espressif/esp_http_client`.
    return text.rsplit("/", 1)[-1]


def find_violations(root: Path) -> list[str]:
    """Return human-readable violations under *root*; empty means clean."""
    root = Path(root)
    violations: list[str] = []
    violations += _check_app_manifests(root)
    violations += _check_android_manifest(root)
    violations += _check_firmware_manifests(root)
    violations += _check_kconfig(root)
    return violations


def _load_yaml(path: Path) -> object:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as exc:  # pragma: no cover - defensive
        raise SystemExit(f"dependency guard: cannot parse {path}: {exc}")


def _check_app_manifests(root: Path) -> list[str]:
    violations: list[str] = []
    pubspec = root / "app" / "pubspec.yaml"
    if pubspec.is_file():
        data = _load_yaml(pubspec)
        for section in ("dependencies", "dev_dependencies"):
            deps = data.get(section) or {}
            if not isinstance(deps, dict):
                continue
            for name in deps:
                if normalise_package(name) in FORBIDDEN_APP_PACKAGES:
                    violations.append(
                        f"{pubspec}:{section} contains forbidden package {name!r}"
                    )

    lock = root / "app" / "pubspec.lock"
    if lock.is_file():
        data = _load_yaml(lock)
        packages = data.get("packages") or {}
        if isinstance(packages, dict):
            for name in packages:
                if normalise_package(name) in FORBIDDEN_APP_PACKAGES:
                    violations.append(
                        f"{lock}: resolved package {name!r} is forbidden "
                        "(direct or transitive)"
                    )
    return violations


def _check_android_manifest(root: Path) -> list[str]:
    manifest = root / "app" / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.is_file():
        return []
    text = manifest.read_text(encoding="utf-8")
    violations: list[str] = []
    for permission in FORBIDDEN_PERMISSIONS:
        if re.search(
            r"<uses-permission[^>]*android:name\s*=\s*['\"]"
            + re.escape(permission)
            + r"['\"]",
            text,
        ):
            violations.append(
                f"{manifest}: release manifest requests forbidden permission "
                f"{permission}"
            )
    return violations


def _check_firmware_manifests(root: Path) -> list[str]:
    firmware = root / "firmware"
    if not firmware.is_dir():
        return []
    violations: list[str] = []

    for path in _walk(firmware, "idf_component.yml"):
        data = _load_yaml(path)
        deps = data.get("dependencies") or {}
        names = deps.keys() if isinstance(deps, dict) else deps
        if not isinstance(names, (list, tuple, set)) and not hasattr(names, "__iter__"):
            continue
        for name in names:
            if normalise_package(name) in FORBIDDEN_FIRMWARE_COMPONENTS:
                violations.append(
                    f"{path}: idf_component dependency {name!r} is forbidden"
                )

    for path in _walk(firmware, "CMakeLists.txt"):
        original = path.read_text(encoding="utf-8").splitlines()
        for lineno, line in enumerate(original, start=1):
            if line.lstrip().startswith("#"):
                continue
            line = line.split("#", 1)[0]
            for component in FORBIDDEN_FIRMWARE_COMPONENTS:
                if re.search(rf"(?<![\w-]){re.escape(component)}(?![\w-])", line):
                    violations.append(
                        f"{path}:{lineno}: component {component!r} is forbidden"
                    )
    return violations


def _check_kconfig(root: Path) -> list[str]:
    violations: list[str] = []
    for path in sorted(root.glob("firmware/sdkconfig.defaults*")):
        for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            for symbol in FORBIDDEN_KCONFIG:
                if re.match(rf"{re.escape(symbol)}=y\b", line):
                    violations.append(
                        f"{path}:{lineno}: {symbol}=y enables a forbidden stack"
                    )
    return violations


def _walk(base: Path, filename: str):
    for path in sorted(base.rglob(filename)):
        if any(part in SKIP_DIRS for part in path.relative_to(base).parts):
            continue
        yield path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (default: the checkout containing this script)",
    )
    args = parser.parse_args(argv)

    violations = find_violations(args.root)
    if violations:
        for violation in violations:
            print(f"dependency guard: FAIL: {violation}", file=sys.stderr)
        print(
            "dependency guard: the MVP has no network, MQTT or OTA dependencies "
            "(ADR 0001/0006)",
            file=sys.stderr,
        )
        return 1
    print(
        "dependency guard: ok (app pubspec/lock, release manifest, firmware "
        "manifests and sdkconfig contain no network/MQTT/OTA dependency)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
