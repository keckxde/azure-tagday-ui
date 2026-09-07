import unittest
import tempfile
import os
import shutil
from unittest.mock import patch

from src.gui.backend import DevOpsBackend, _load_user_settings, _save_user_settings


class TestFontSizeAndScaling(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.settings_file = os.path.join(self.test_dir, "user_settings.yaml")

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_font_scaling_modes_and_persistence(self):
        with patch("src.gui.backend.USER_SETTINGS_PATH", self.settings_file):
            backend = DevOpsBackend()

            # Default mode is medium (1.0 scale)
            self.assertEqual(backend.fontSizeMode, "medium")
            self.assertAlmostEqual(backend.uiScale, 1.0)

            # Test Small mode
            signal_emitted = []
            backend.fontSizeModeChanged.connect(lambda mode, scale: signal_emitted.append((mode, scale)))

            backend.setFontSizeMode("small")
            self.assertEqual(backend.fontSizeMode, "small")
            self.assertAlmostEqual(backend.uiScale, 0.90)
            self.assertEqual(signal_emitted[-1], ("small", 0.90))

            # Test Large mode
            backend.setFontSizeMode("large")
            self.assertEqual(backend.fontSizeMode, "large")
            self.assertAlmostEqual(backend.uiScale, 1.15)
            self.assertEqual(signal_emitted[-1], ("large", 1.15))

            # Test X-Large mode
            backend.setFontSizeMode("xlarge")
            self.assertEqual(backend.fontSizeMode, "xlarge")
            self.assertAlmostEqual(backend.uiScale, 1.30)
            self.assertEqual(signal_emitted[-1], ("xlarge", 1.30))

            # Test Invalid mode defaults to medium
            backend.setFontSizeMode("invalid_mode")
            self.assertEqual(backend.fontSizeMode, "medium")
            self.assertAlmostEqual(backend.uiScale, 1.0)

            # Check that settings were saved to YAML
            saved_cfg = _load_user_settings()
            self.assertEqual(saved_cfg.get("font_size_mode"), "medium")
            self.assertAlmostEqual(saved_cfg.get("ui_scale"), 1.0)


if __name__ == "__main__":
    unittest.main()
