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

    def test_reports_right_sidebar_collapse_in_all_reports_and_reactivate_button(self):
        qml_dir = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "gui",
            "qml",
            "views",
        )
        with open(os.path.join(qml_dir, "ReportsView.qml"), "r", encoding="utf-8") as f:
            reports_view_qml = f.read()
        with open(os.path.join(qml_dir, "reports", "ReportsTagDayExplorerTab.qml"), "r", encoding="utf-8") as f:
            explorer_tab_qml = f.read()
        with open(os.path.join(qml_dir, "reports", "ReportsTagDaySidebar.qml"), "r", encoding="utf-8") as f:
            td_sidebar_qml = f.read()
        with open(os.path.join(qml_dir, "reports", "ReportPreviewPane.qml"), "r", encoding="utf-8") as f:
            preview_pane_qml = f.read()

        # 1. External toggle button removed from Tag Day Explorer header
        self.assertNotIn("Sidebar ◨", explorer_tab_qml)
        self.assertNotIn("Sidebar ◧", explorer_tab_qml)

        # 2. Tab switching in ReportsView does not force-reopen the collapsed sidebar
        active_tab_block = reports_view_qml.split("onActiveReportTabChanged:")[1].split("Connections")[0]
        self.assertNotIn("root.isTdSidebarOpen = true", active_tab_block)

        # 3. Collapse button exists inside both ReportPreviewPane (Tabs 0, 2..6) and ReportsTagDaySidebar (Tab 1)
        self.assertIn("previewPaneRoot.root.isTdSidebarOpen = false", preview_pane_qml)
        self.assertIn("root.isTdSidebarOpen = false", td_sidebar_qml)

        # 4. Minimal collapsed strip with reactivate button remains visible when collapsed
        self.assertIn("visible: !(root && root.isTdSidebarOpen)", td_sidebar_qml)
        self.assertIn("if (root) root.isTdSidebarOpen = true;", td_sidebar_qml)


if __name__ == "__main__":
    unittest.main()
