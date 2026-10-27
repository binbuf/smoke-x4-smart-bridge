"""Unit tests for the CI dependency guard.

Run from the repository root:

    python -m unittest discover -s tools/ci -p "test_*.py" -v

Each test writes a synthetic repository so the guard's failure paths are proven
without touching the real tree.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_forbidden_deps as guard  # noqa: E402


class DependencyGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "app" / "android" / "app" / "src" / "main").mkdir(parents=True)
        (self.root / "firmware" / "main").mkdir(parents=True)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write(self, relative: str, text: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_clean_tree_passes(self) -> None:
        self.write(
            "app/pubspec.yaml",
            "dependencies:\n"
            "  flutter:\n"
            "    sdk: flutter\n"
            "  sqflite: ^2.4.2\n"
            "dev_dependencies:\n"
            "  flutter_test:\n"
            "    sdk: flutter\n",
        )
        self.write(
            "app/pubspec.lock",
            "packages:\n  sqflite:\n    dependency: direct main\n",
        )
        self.write(
            "app/android/app/src/main/AndroidManifest.xml",
            "<manifest><application/></manifest>\n",
        )
        self.write(
            "firmware/main/CMakeLists.txt",
            "idf_component_register(\n"
            "  SRCS \"main.c\"\n"
            "  REQUIRES board nvs_flash\n"
            "  PRIV_REQUIRES log\n"
            ")\n",
        )
        self.write(
            "firmware/sdkconfig.defaults",
            "# CONFIG_ESP_WIFI_ENABLED is not set\n",
        )
        self.assertEqual(guard.find_violations(self.root), [])

    def test_http_direct_dependency_fails(self) -> None:
        self.write("app/pubspec.yaml", "dependencies:\n  http: ^1.0.0\n")
        violations = guard.find_violations(self.root)
        self.assertTrue(any("http" in item for item in violations))

    def test_forbidden_transitive_package_fails(self) -> None:
        self.write(
            "app/pubspec.lock",
            "packages:\n  web_socket_channel:\n    dependency: transitive\n",
        )
        violations = guard.find_violations(self.root)
        self.assertTrue(any("web_socket_channel" in item for item in violations))

    def test_mqtt_and_ota_packages_fail(self) -> None:
        self.write(
            "app/pubspec.yaml",
            "dependencies:\n  mqtt_client: ^10.0.0\n  ota_update: ^6.0.0\n",
        )
        violations = guard.find_violations(self.root)
        self.assertTrue(any("mqtt_client" in item for item in violations))
        self.assertTrue(any("ota_update" in item for item in violations))

    def test_firmware_component_manifest_fails(self) -> None:
        self.write(
            "firmware/components/net/idf_component.yml",
            "dependencies:\n  espressif/esp_http_client: ^1.0.0\n",
        )
        violations = guard.find_violations(self.root)
        self.assertTrue(any("esp_http_client" in item for item in violations))

    def test_firmware_cmake_requires_fails(self) -> None:
        self.write(
            "firmware/main/CMakeLists.txt",
            "idf_component_register(\n"
            "  SRCS \"main.c\"\n"
            "  REQUIRES esp_wifi\n"
            ")\n",
        )
        violations = guard.find_violations(self.root)
        self.assertTrue(any("esp_wifi" in item for item in violations))

    def test_comments_do_not_false_positive(self) -> None:
        self.write(
            "firmware/main/CMakeLists.txt",
            "# esp_wifi is deliberately absent\n"
            "idf_component_register(SRCS \"main.c\")\n",
        )
        self.assertEqual(guard.find_violations(self.root), [])

    def test_release_manifest_network_permission_fails(self) -> None:
        self.write(
            "app/android/app/src/main/AndroidManifest.xml",
            "<manifest>\n"
            '  <uses-permission android:name="android.permission.INTERNET"/>\n'
            "</manifest>\n",
        )
        violations = guard.find_violations(self.root)
        self.assertTrue(any("INTERNET" in item for item in violations))

    def test_enabled_wifi_kconfig_fails(self) -> None:
        self.write("firmware/sdkconfig.defaults", "CONFIG_ESP_WIFI_ENABLED=y\n")
        violations = guard.find_violations(self.root)
        self.assertTrue(any("CONFIG_ESP_WIFI_ENABLED" in item for item in violations))


if __name__ == "__main__":
    unittest.main()
