# -*- coding: UTF-8 -*-
import os
import sys
import json
import yaml
import tempfile
import unittest
from unittest.mock import patch, MagicMock
from PySide6.QtCore import QCoreApplication

# Add scripts/py to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from gui.backend import DevOpsBackend, USER_SETTINGS_PATH
from azure.azure_db import AzureDevOpsCache


class TestSettingsAndProjectSwitch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not QCoreApplication.instance():
            cls.app = QCoreApplication([])
        else:
            cls.app = QCoreApplication.instance()

    def setUp(self):
        # Backup original user settings if file exists
        self.original_settings = None
        if os.path.exists(USER_SETTINGS_PATH):
            try:
                with open(USER_SETTINGS_PATH, "r", encoding="utf-8") as f:
                    self.original_settings = f.read()
            except Exception:
                pass

        self.backend = DevOpsBackend()
        self.app.processEvents()

    def tearDown(self):
        # Restore original user settings
        if self.original_settings is not None:
            os.makedirs(os.path.dirname(USER_SETTINGS_PATH), exist_ok=True)
            with open(USER_SETTINGS_PATH, "w", encoding="utf-8") as f:
                f.write(self.original_settings)
        elif os.path.exists(USER_SETTINGS_PATH):
            try:
                os.remove(USER_SETTINGS_PATH)
            except Exception:
                pass

    def test_get_available_databases(self):
        dbs = self.backend.get_available_databases()
        self.assertIsInstance(dbs, list)
        self.assertGreater(len(dbs), 0)
        
        # Verify structure of database items
        first_db = dbs[0]
        self.assertIn("path", first_db)
        self.assertIn("name", first_db)
        self.assertIn("project", first_db)
        self.assertIn("size_mb", first_db)
        self.assertIn("is_active", first_db)

    def test_test_tfs_connection_mock_success(self):
        fake_response_data = {
            "value": [
                {"id": "proj-1", "name": "Project Beta", "description": "Second project"},
                {"id": "proj-0", "name": "Project Alpha", "description": "First project"}
            ]
        }
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps(fake_response_data).encode("utf-8")
        mock_response.__enter__.return_value = mock_response

        with patch("urllib.request.urlopen", return_value=mock_response):
            result = self.backend.test_tfs_connection(
                url="http://tfs.example.local:8080/tfs",
                collection="DefaultCollection",
                pat="dummy_pat_123"
            )
            self.assertTrue(result["success"])
            self.assertEqual(len(result["projects"]), 2)
            # Projects should be sorted alphabetically by name
            self.assertEqual(result["projects"][0]["name"], "Project Alpha")
            self.assertEqual(result["projects"][1]["name"], "Project Beta")

    def test_test_tfs_connection_failure(self):
        result = self.backend.test_tfs_connection(
            url="http://invalid-nonexistent-host-99999.xyz/tfs",
            collection="DefaultCollection",
            pat=""
        )
        self.assertFalse(result["success"])
        self.assertIn("error", result)

    def test_switch_database(self):
        # Create a temp sqlite database using AzureDevOpsCache schema
        temp_fd, temp_db = tempfile.mkstemp(suffix=".db")
        os.close(temp_fd)
        try:
            cache = AzureDevOpsCache(temp_db)
            with cache._connection() as conn:
                conn.execute("INSERT INTO projects (id, name, last_synced_at) VALUES ('p-test', 'Temp Project', '2026-09-06T12:00:00')")

            success = self.backend.switch_database(temp_db)
            self.assertTrue(success)
            self.assertEqual(self.backend.projectName, "Temp Project")
            self.assertEqual(os.path.abspath(self.backend.dbPath), os.path.abspath(temp_db))

            # Verify persisted in user_settings.yaml
            self.assertTrue(os.path.exists(USER_SETTINGS_PATH))
            with open(USER_SETTINGS_PATH, "r", encoding="utf-8") as f:
                settings = yaml.safe_load(f)
            self.assertEqual(os.path.abspath(settings["db_path"]), os.path.abspath(temp_db))
            self.assertEqual(settings["project_name"], "Temp Project")
        finally:
            if os.path.exists(temp_db):
                try:
                    os.remove(temp_db)
                except Exception:
                    pass

    def test_create_project_and_database(self):
        temp_dir = tempfile.mkdtemp()
        new_db_file = os.path.join(temp_dir, "tfs_new_test.db")
        try:
            res = self.backend.create_project_and_database(
                url="http://tfs.test.local:8080/tfs",
                collection="CustomCollection",
                pat="secret-pat-token",
                project_id="guid-12345",
                project_name="Newly Created Project",
                db_path=new_db_file,
                start_sync=False,
                store_pat=True
            )
            self.assertTrue(res["success"])
            self.assertTrue(os.path.exists(new_db_file))

            # Verify project entry in sqlite
            cache = AzureDevOpsCache(new_db_file)
            with cache._connection() as conn:
                row = conn.execute("SELECT id, name FROM projects WHERE id='guid-12345'").fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["name"], "Newly Created Project")

            # Check backend active properties
            self.assertEqual(self.backend.projectName, "Newly Created Project")
            self.assertEqual(os.path.abspath(self.backend.dbPath), os.path.abspath(new_db_file))
            self.assertEqual(self.backend.tfsCollection, "CustomCollection")
            self.assertEqual(self.backend.tfsPat, "secret-pat-token")

            # Check user_settings.yaml
            with open(USER_SETTINGS_PATH, "r", encoding="utf-8") as f:
                settings = yaml.safe_load(f)
            self.assertEqual(settings["project_name"], "Newly Created Project")
            self.assertEqual(settings["pat"], "secret-pat-token")
        finally:
            if os.path.exists(new_db_file):
                try:
                    os.remove(new_db_file)
                except Exception:
                    pass
            try:
                os.rmdir(temp_dir)
            except Exception:
                pass


if __name__ == "__main__":
    unittest.main()
