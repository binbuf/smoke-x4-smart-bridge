"""Tests for the T37 cadence report extractor.

Run from the repository root:

    python -m unittest discover -s tools/bench -p "test_*.py" -v

The T10 capture is real probe evidence; the product fixture is synthetic and
models the T21/T25 serial lines, including a >90 s gap, a missing sequence
number and a restart.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import cadence_report as cadence  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
T10_CAPTURE = ROOT / "artifacts" / "bench" / "T10" / "serial-20261026T214626.log"
PRODUCT_FIXTURE = ROOT / "tools" / "bench" / "fixtures" / "product-cadence.log"
TEMPLATE = ROOT / "artifacts" / "bench" / "T37" / "CADENCE-REPORT-TEMPLATE.md"


class T10CaptureTest(unittest.TestCase):
    def setUp(self) -> None:
        self.capture = cadence.parse_capture(T10_CAPTURE)
        self.analysis = cadence.analyze(self.capture)

    def test_counts_state_frames_not_sync_or_ack(self) -> None:
        self.assertEqual(self.capture.radio_packets, 43)
        self.assertEqual(self.analysis["sample_count"], 41)
        self.assertEqual(self.analysis["radio_packet_count"], 43)

    def test_observed_intervals_and_the_known_gap(self) -> None:
        self.assertAlmostEqual(self.analysis["interval_min"], 30.22, places=2)
        self.assertAlmostEqual(self.analysis["interval_max"], 166.34, places=2)
        self.assertAlmostEqual(self.analysis["interval_mean"], 33.6355, places=3)
        self.assertEqual(self.analysis["interval_count"], 40)
        self.assertEqual(self.analysis["gap_count"], 1)
        self.assertEqual(self.analysis["restart_count"], 0)
        gap = self.analysis["gaps"][0]
        self.assertEqual(gap["kind"], "radio")
        self.assertAlmostEqual(gap["seconds"], 166.34, places=2)

    def test_rssi_range(self) -> None:
        self.assertEqual(self.analysis["rssi_min"], -52)
        self.assertEqual(self.analysis["rssi_max"], -28)
        self.assertAlmostEqual(self.analysis["rssi_mean"], -34.1951, places=3)

    def test_expected_count_uses_span_without_capture_markers(self) -> None:
        self.assertIsNotNone(self.analysis["opened"])
        self.assertIsNone(self.analysis["closed"])
        self.assertAlmostEqual(self.analysis["span_seconds"], 1345.42, places=2)
        self.assertEqual(self.analysis["expected_count"], 45)
        self.assertEqual(self.analysis["missed_count"], 4)
        self.assertTrue(
            any("no usable # opened/# closed" in item
                for item in self.analysis["warnings"])
        )

    def test_t10_has_no_sequences(self) -> None:
        self.assertIsNone(self.analysis["first_seq"])
        self.assertIsNone(self.analysis["last_seq"])
        self.assertEqual(self.analysis["missing_seq"], [])


class ProductCaptureTest(unittest.TestCase):
    def setUp(self) -> None:
        self.capture = cadence.parse_capture(PRODUCT_FIXTURE)
        self.analysis = cadence.analyze(self.capture)

    def test_product_counts_expectation_and_intervals(self) -> None:
        self.assertEqual(self.analysis["sample_count"], 5)
        self.assertEqual(self.analysis["expected_count"], 6)
        self.assertEqual(self.analysis["missed_count"], 1)
        self.assertAlmostEqual(self.analysis["wall_seconds"], 190.0, places=1)
        self.assertAlmostEqual(self.analysis["span_seconds"], 181.0, places=1)
        self.assertAlmostEqual(self.analysis["interval_min"], 30.0, places=2)
        self.assertAlmostEqual(self.analysis["interval_mean"], 45.25, places=2)
        self.assertAlmostEqual(self.analysis["interval_max"], 91.0, places=2)

    def test_gap_and_sequence_hole_are_reported(self) -> None:
        self.assertEqual(self.analysis["gap_count"], 1)
        self.assertEqual(self.analysis["gaps"][0]["kind"], "radio")
        self.assertEqual(self.analysis["first_seq"], 0)
        self.assertEqual(self.analysis["last_seq"], 5)
        self.assertEqual(self.analysis["missing_seq"], [3])

    def test_rssi_comes_from_the_rx_line_before_each_record(self) -> None:
        self.assertEqual(self.analysis["rssi_min"], -50)
        self.assertEqual(self.analysis["rssi_max"], -40)
        self.assertAlmostEqual(self.analysis["rssi_mean"], -44.4, places=3)


class RestartTest(unittest.TestCase):
    def test_restart_is_a_gap_and_not_an_interval(self) -> None:
        text = (
            "# opened 2026-10-26T22:00:00 port=COM5 baud=115200\n"
            "ESP-ROM:esp32s3-20210327\n"
            "rst:0x1 (POWERON),boot:0x8 (SPI_FAST_FLASH_BOOT)\n"
            "I (1000) sx4.radio: rx len=77 rssi=-40 snr=9\n"
            "I (1001) sx4.sample: stored seq=0 t=1,2,3,4 flags=0x0f\n"
            "I (31000) sx4.radio: rx len=77 rssi=-41 snr=9\n"
            "I (31001) sx4.sample: stored seq=1 t=1,2,3,4 flags=0x0f\n"
            "ESP-ROM:esp32s3-20210327\n"
            "rst:0x5 (DSLEEP),boot:0x8 (SPI_FAST_FLASH_BOOT)\n"
            "I (1000) sx4.radio: rx len=77 rssi=-35 snr=9\n"
            "I (1001) sx4.sample: stored seq=2 t=1,2,3,4 flags=0x0f\n"
            "# closed 2026-10-26T22:00:40 port=COM5 baud=115200\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            capture_path = Path(tmp) / "restart.log"
            capture_path.write_text(text, encoding="utf-8")
            capture = cadence.parse_capture(capture_path)
            analysis = cadence.analyze(capture)

        self.assertEqual(analysis["sample_count"], 3)
        self.assertEqual(analysis["boot_count"], 2)
        self.assertEqual(analysis["restart_count"], 1)
        self.assertEqual(analysis["interval_count"], 1)  # no cross-boot interval
        self.assertAlmostEqual(analysis["interval_min"], 30.0, places=2)
        self.assertEqual(analysis["gap_count"], 0)
        self.assertEqual(analysis["gaps"][0]["kind"], "restart")
        self.assertIn("bridge restart", analysis["gaps"][0]["cause"])


class ReportTest(unittest.TestCase):
    def test_template_renders_with_every_measured_field(self) -> None:
        analysis = cadence.analyze(cadence.parse_capture(PRODUCT_FIXTURE))
        report = cadence.render_markdown(
            analysis, TEMPLATE.read_text(encoding="utf-8")
        )
        self.assertNotIn("{{", report)
        self.assertIn("5", report)
        self.assertIn("91.0 s", report)
        self.assertIn("_unrecorded — fill at T37_", report)
        self.assertIn("T37 manual checks", report)
        self.assertIn("⏳", report)

    def test_empty_capture_is_reported_and_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            capture_path = Path(tmp) / "empty.log"
            capture_path.write_text("# opened 2026-10-26T22:00:00\n", encoding="utf-8")
            capture = cadence.parse_capture(capture_path)
            analysis = cadence.analyze(capture)
            self.assertEqual(analysis["sample_count"], 0)
            self.assertEqual(analysis["expected_count"], 0)
            self.assertTrue(
                any("no stored product samples" in item
                    for item in analysis["warnings"])
            )


if __name__ == "__main__":
    unittest.main()
