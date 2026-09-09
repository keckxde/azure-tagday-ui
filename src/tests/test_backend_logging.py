# -*- coding: UTF-8 -*-
import os
import sys
import unittest
import logging
from PySide6.QtCore import QCoreApplication

# Add scripts/py to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from gui.backend import DevOpsBackend


class TestBackendLogging(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not QCoreApplication.instance():
            cls.app = QCoreApplication([])
        else:
            cls.app = QCoreApplication.instance()

    def setUp(self):
        self.backend = DevOpsBackend()
        self.app.processEvents()
        self.backend.clear_logs()
        self.app.processEvents()

    def test_log_capture_and_severity_counts(self):
        test_logger = logging.getLogger("test_module_sync")
        test_logger.info("Test sync info line")
        test_logger.warning("Test sync warning line")
        test_logger.error("Test sync error line")

        # Process Qt events so queued signals are delivered
        self.app.processEvents()

        counts = self.backend.logCounts
        self.assertGreaterEqual(counts["info"], 1)
        self.assertGreaterEqual(counts["warning"], 1)
        self.assertGreaterEqual(counts["error"], 1)

        logs = self.backend.syncLogs
        severities = [l["level"] for l in logs]
        self.assertIn("INFO", severities)
        self.assertIn("WARNING", severities)
        self.assertIn("ERROR", severities)

    def test_clear_logs(self):
        test_logger = logging.getLogger("test_module_clear")
        test_logger.info("Some message to clear")
        self.app.processEvents()

        self.assertGreater(self.backend.logCounts["all"], 0)
        self.backend.clear_logs()
        self.app.processEvents()

        # After clear, only the 'Log cleared' notice may exist
        self.assertLessEqual(self.backend.logCounts["all"], 1)
        self.assertEqual(self.backend.logCounts["warning"], 0)
        self.assertEqual(self.backend.logCounts["error"], 0)

    def test_get_all_logs_text(self):
        test_logger = logging.getLogger("test_module_text")
        test_logger.info("UniqueSearchableLogString12345")
        self.app.processEvents()

        all_text = self.backend.get_all_logs_text()
        self.assertIn("UniqueSearchableLogString12345", all_text)
        self.assertIn("[INFO]", all_text)

    def test_progress_property_and_signal(self):
        emitted = []
        self.backend.progressChanged.connect(lambda: emitted.append(True))
        self.assertEqual(self.backend.progress, 0)
        
        self.backend._progress = 42
        self.backend.progressChanged.emit()
        self.app.processEvents()
        
        self.assertEqual(len(emitted), 1)
        self.assertEqual(self.backend.progress, 42)


if __name__ == "__main__":
    unittest.main()

