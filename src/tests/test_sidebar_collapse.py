import unittest
import tempfile
import os
import shutil
from unittest.mock import patch

from src.gui.backend import DevOpsBackend, _load_user_settings, _save_user_settings


class TestSidebarCollapse(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.settings_file = os.path.join(self.test_dir, "user_settings.yaml")

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_sidebar_collapse_toggle_and_persistence(self):
        with patch("src.gui.backend.USER_SETTINGS_PATH", self.settings_file):
            backend = DevOpsBackend()

            # Default is expanded (False)
            self.assertFalse(backend.sidebarCollapsed)

            # Signal tracking
            emitted_states = []
            backend.sidebarCollapsedChanged.connect(lambda state: emitted_states.append(state))

            # Collapse sidebar
            backend.setSidebarCollapsed(True)
            self.assertTrue(backend.sidebarCollapsed)
            self.assertEqual(emitted_states, [True])

            # Persistence in YAML
            saved_cfg = _load_user_settings()
            self.assertTrue(saved_cfg.get("sidebar_collapsed"))

            # Toggle sidebar back to expanded
            backend.toggleSidebar()
            self.assertFalse(backend.sidebarCollapsed)
            self.assertEqual(emitted_states, [True, False])

            # Toggle sidebar to collapsed
            backend.toggleSidebar()
            self.assertTrue(backend.sidebarCollapsed)
            self.assertEqual(emitted_states, [True, False, True])

    def test_sidebar_initializes_from_saved_settings(self):
        with patch("src.gui.backend.USER_SETTINGS_PATH", self.settings_file):
            _save_user_settings({"sidebar_collapsed": True})
            backend = DevOpsBackend()
            self.assertTrue(backend.sidebarCollapsed)


if __name__ == "__main__":
    unittest.main()
