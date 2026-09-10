# -*- coding: UTF-8 -*-
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

# Ensure src is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from PySide6.QtWidgets import QApplication
from gui.backend import DevOpsBackend, _load_user_settings, _save_user_settings


# Ensure single QApplication instance for Qt Quick tests
_app = QApplication.instance() or QApplication(sys.argv)


class TestScheduledSync(unittest.TestCase):
    def setUp(self):
        self.backend = DevOpsBackend()

    def tearDown(self):
        if hasattr(self.backend, "_auto_sync_timer") and self.backend._auto_sync_timer.isActive():
            self.backend._auto_sync_timer.stop()

    def test_default_auto_sync_properties(self):
        """Test default auto-sync state and property values."""
        self.assertIsInstance(self.backend.autoSyncEnabled, bool)
        self.assertGreaterEqual(self.backend.autoSyncIntervalMinutes, 1)
        self.assertIn(self.backend.autoSyncScope, ["all", "work_items", "pull_requests"])
        self.assertIsInstance(self.backend.nextAutoSyncSeconds, int)
        self.assertIsInstance(self.backend.nextAutoSyncText, str)
        self.assertIsInstance(self.backend.autoSyncStatusText, str)

    def test_enable_and_disable_auto_sync(self):
        """Test enabling and disabling auto-sync updates properties and timer countdown."""
        self.backend.setAutoSyncEnabled(True)
        self.assertTrue(self.backend.autoSyncEnabled)
        self.assertNotEqual(self.backend.nextAutoSyncText, "Off")
        self.assertIn("Auto-sync", self.backend.autoSyncStatusText)

        self.backend.setAutoSyncEnabled(False)
        self.assertFalse(self.backend.autoSyncEnabled)
        self.assertEqual(self.backend.nextAutoSyncText, "Off")
        self.assertEqual(self.backend.autoSyncStatusText, "Auto-sync: Off")

    def test_set_auto_sync_interval(self):
        """Test setting auto-sync interval updates minutes and countdown."""
        self.backend.setAutoSyncInterval(10)
        self.assertEqual(self.backend.autoSyncIntervalMinutes, 10)
        self.assertEqual(self.backend.nextAutoSyncSeconds, 600)

        # Invalid/0 should fallback to 5 min
        self.backend.setAutoSyncInterval(0)
        self.assertEqual(self.backend.autoSyncIntervalMinutes, 5)
        self.assertEqual(self.backend.nextAutoSyncSeconds, 300)

    def test_set_auto_sync_scope(self):
        """Test setting auto-sync scope."""
        self.backend.setAutoSyncScope("work_items")
        self.assertEqual(self.backend.autoSyncScope, "work_items")

        self.backend.setAutoSyncScope("pull_requests")
        self.assertEqual(self.backend.autoSyncScope, "pull_requests")

        self.backend.setAutoSyncScope("all")
        self.assertEqual(self.backend.autoSyncScope, "all")

        # Invalid scope fallback
        self.backend.setAutoSyncScope("unknown_scope")
        self.assertEqual(self.backend.autoSyncScope, "all")

    def test_timer_tick_countdown_and_trigger(self):
        """Test timer tick decrementing countdown and triggering sync at 0."""
        self.backend.setAutoSyncEnabled(True)
        self.backend.setAutoSyncInterval(5)
        self.backend._seconds_until_next_sync = 3

        # 1st tick -> 2
        self.backend._on_auto_sync_timer_tick()
        self.assertEqual(self.backend.nextAutoSyncSeconds, 2)
        self.assertEqual(self.backend.nextAutoSyncText, "00:02")

        # 2nd tick -> 1
        self.backend._on_auto_sync_timer_tick()
        self.assertEqual(self.backend.nextAutoSyncSeconds, 1)
        self.assertEqual(self.backend.nextAutoSyncText, "00:01")

        # 3rd tick -> hits 0 -> triggers sync and resets countdown
        with patch.object(self.backend, "sync_all_async") as mock_sync:
            self.backend._on_auto_sync_timer_tick()
            mock_sync.assert_called_once()
            self.assertEqual(self.backend.nextAutoSyncSeconds, 300)

    def test_timer_tick_deferred_when_busy(self):
        """Test timer tick defers triggering if backend is busy with another task."""
        self.backend.setAutoSyncEnabled(True)
        self.backend.setAutoSyncInterval(5)
        self.backend._seconds_until_next_sync = 0
        self.backend._is_busy = True

        with patch.object(self.backend, "sync_all_async") as mock_sync:
            self.backend._on_auto_sync_timer_tick()
            mock_sync.assert_not_called()
            self.assertEqual(self.backend.nextAutoSyncSeconds, 30)

    def test_manual_sync_resets_auto_sync_timer(self):
        """Test that triggering manual sync resets the auto-sync countdown."""
        self.backend.setAutoSyncEnabled(True)
        self.backend.setAutoSyncInterval(5)
        self.backend._seconds_until_next_sync = 45

        self.backend.reset_auto_sync_timer()
        self.assertEqual(self.backend.nextAutoSyncSeconds, 300)

    def test_main_qml_no_top_right_floating_indicator(self):
        """Verify that Main.qml does not contain the obsolete top-right floating background pill."""
        qml_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "gui", "qml", "Main.qml"
        )
        with open(qml_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertNotIn("Floating Background Task Pill", content)
        self.assertNotIn("pillLogBtnText", content)
        self.assertIn("Auto: ", content)


if __name__ == "__main__":
    unittest.main()
