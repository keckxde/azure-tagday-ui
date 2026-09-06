# -*- coding: UTF-8 -*-
import os
import sys
import unittest
from datetime import datetime

# Add py directory to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import generate_revision


class TestGenerateRevision(unittest.TestCase):

    def test_parse_revision_date(self):
        # 2-digit year >= 80 -> 1900s
        dt_old = generate_revision.parse_revision_date("31.12.95")
        self.assertEqual(dt_old, datetime(1995, 12, 31))

        # 2-digit year < 80 -> 2000s
        dt_new = generate_revision.parse_revision_date("06.09.26")
        self.assertEqual(dt_new, datetime(2026, 9, 6))

        # 4-digit year
        dt_full = generate_revision.parse_revision_date("15.05.2025")
        self.assertEqual(dt_full, datetime(2025, 5, 15))

        # Invalid formats
        self.assertIsNone(generate_revision.parse_revision_date(""))
        self.assertIsNone(generate_revision.parse_revision_date(None))
        self.assertIsNone(generate_revision.parse_revision_date("2025-05-15"))
        self.assertIsNone(generate_revision.parse_revision_date("invalid"))

    def test_safe_iso_parse(self):
        # Standard ISO
        dt_iso = generate_revision.safe_iso_parse("2026-09-06T10:30:00")
        self.assertEqual(dt_iso, datetime(2026, 9, 6, 10, 30, 0))

        # Space-separated
        dt_space = generate_revision.safe_iso_parse("2026-09-06 10:30:00")
        self.assertEqual(dt_space, datetime(2026, 9, 6, 10, 30, 0))

        # Invalid
        self.assertIsNone(generate_revision.safe_iso_parse(""))
        self.assertIsNone(generate_revision.safe_iso_parse(None))
        self.assertIsNone(generate_revision.safe_iso_parse("not-a-valid-date"))

    def test_format_date_rev(self):
        dt = datetime(2026, 9, 6)
        self.assertEqual(generate_revision.format_date_rev(dt), "06.09.26")
        self.assertEqual(generate_revision.format_date_rev(None), "")

    def test_get_last_change(self):
        # Version ending in digits
        val = generate_revision.get_last_change("v1.0.42", "v1.0.10", "fallback")
        self.assertEqual(val, "42")

        # Stable greater than unstable
        val_stable = generate_revision.get_last_change("v1.0.10", "v1.0.99", "fallback")
        self.assertEqual(val_stable, "99")

        # Fallback when version ends in 0
        val_fallback = generate_revision.get_last_change("v1.0.0", "v1.0.0", "fallback")
        self.assertEqual(val_fallback, "fallback")

        # Empty strings return ""
        val_empty = generate_revision.get_last_change("", "", "fallback")
        self.assertEqual(val_empty, "")


if __name__ == "__main__":
    unittest.main()
