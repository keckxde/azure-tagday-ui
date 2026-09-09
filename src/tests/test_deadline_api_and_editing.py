# -*- coding: UTF-8 -*-
import os
import sys
import json
import unittest
from unittest.mock import patch, MagicMock
import tempfile
import shutil

py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import utils
from azure.azure_base_client import AzureBaseClient
from azure.azure_db import AzureDevOpsCache


class TestDeadlineApiAndEditing(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "test_cache.db")
        self.cache = AzureDevOpsCache(self.db_path)
        self.client = AzureBaseClient("https://dev.azure.com/testorg/DefaultCollection", "testpat")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_extract_work_item_deadline_priorities(self):
        # 1. Custom field priority
        fields = {
            "Custom.MilestoneDeadline": "2026-09-01T12:00:00Z",
            "Microsoft.VSTS.Scheduling.TargetDate": "2026-08-14T00:00:00Z",
            "Microsoft.VSTS.Scheduling.DueDate": "2026-08-10T00:00:00Z"
        }
        val, matched = utils.extract_work_item_deadline(fields, custom_field="Custom.MilestoneDeadline")
        self.assertEqual(val, "2026-09-01T12:00:00Z")
        self.assertEqual(matched, "Custom.MilestoneDeadline")

        # 2. Standard TargetDate fallback
        fields_std = {
            "Microsoft.VSTS.Scheduling.TargetDate": "2026-08-14T00:00:00Z",
            "Microsoft.VSTS.Scheduling.DueDate": "2026-08-10T00:00:00Z"
        }
        val2, matched2 = utils.extract_work_item_deadline(fields_std)
        self.assertEqual(val2, "2026-08-14T00:00:00Z")
        self.assertEqual(matched2, "Microsoft.VSTS.Scheduling.TargetDate")

        # 3. DueDate fallback
        fields_due = {
            "Microsoft.VSTS.Scheduling.DueDate": "2026-08-10T00:00:00Z"
        }
        val3, matched3 = utils.extract_work_item_deadline(fields_due)
        self.assertEqual(val3, "2026-08-10T00:00:00Z")
        self.assertEqual(matched3, "Microsoft.VSTS.Scheduling.DueDate")

    def test_azure_base_client_update_work_item_field(self):
        with patch.object(self.client, "_request") as mock_req:
            mock_req.return_value = ({"id": 12345, "fields": {"Custom.Milestone": "2026-08-14"}}, 200)

            # Set value
            res = self.client.update_work_item_field(12345, "Custom.Milestone", "2026-08-14", project_id="PROJ")
            self.assertEqual(res["id"], 12345)
            mock_req.assert_called_with(
                "PATCH",
                "PROJ/_apis/wit/workitems/12345",
                params={"api-version": "6.0"},
                data=[{"op": "add", "path": "/fields/Custom.Milestone", "value": "2026-08-14"}],
                content_type="application/json-patch+json"
            )

            # Clear value (remove op)
            self.client.update_work_item_field(12345, "Custom.Milestone", "", project_id="PROJ")
            mock_req.assert_called_with(
                "PATCH",
                "PROJ/_apis/wit/workitems/12345",
                params={"api-version": "6.0"},
                data=[{"op": "remove", "path": "/fields/Custom.Milestone"}],
                content_type="application/json-patch+json"
            )

    def test_cache_db_update_work_item_deadline(self):
        # Save work item first
        raw_wi = {
            "id": 999,
            "fields": {
                "System.Title": "Story with deadline",
                "System.WorkItemType": "User Story",
                "System.State": "Active"
            }
        }
        self.cache.save_work_item(999, "Story with deadline", "User Story", "Active", "Alice", "2026-08-01", raw_wi)

        # Update deadline in DB
        ok = self.cache.update_work_item_deadline(999, "2026-08-14", field_name="Custom.Milestone")
        self.assertTrue(ok)

        wi = self.cache.get_work_item(999)
        raw_loaded = json.loads(wi["raw_json"])
        self.assertEqual(raw_loaded["fields"].get("Custom.Milestone"), "2026-08-14")

        # Clear deadline
        ok_clear = self.cache.update_work_item_deadline(999, "")
        self.assertTrue(ok_clear)

        wi_cleared = self.cache.get_work_item(999)
        raw_cleared = json.loads(wi_cleared["raw_json"])
        self.assertNotIn("Custom.Milestone", raw_cleared["fields"])

    def test_backend_update_work_item_deadline_async(self):
        from gui.backend import DevOpsBackend
        import time

        backend = DevOpsBackend()
        backend._cache_db = self.cache

        raw_wi = {
            "id": 1001,
            "fields": {
                "System.Title": "Item for async deadline update",
                "System.WorkItemType": "User Story",
                "System.State": "Active",
                "Microsoft.VSTS.Scheduling.TargetDate": "2026-07-01"
            }
        }
        self.cache.save_work_item(1001, "Item for async deadline update", "User Story", "Active", "Bob", "2026-07-01", raw_wi)
        backend.refresh_all_data()

        mock_handler = MagicMock()
        with patch("devops_helper._getHandler", return_value=mock_handler):
            res = backend.update_work_item_deadline(1001, "2026-09-15")

            # Check immediate return value (optimistic UI update)
            self.assertTrue(res["success"])
            self.assertEqual(res["deadline"], "2026-09-15")
            self.assertTrue(res["syncing"])

            # Check SQLite DB was updated immediately
            wi_db = self.cache.get_work_item(1001)
            raw_db = json.loads(wi_db["raw_json"])
            self.assertEqual(raw_db["fields"]["Microsoft.VSTS.Scheduling.TargetDate"], "2026-09-15")

            # Wait briefly for daemon thread to complete
            time.sleep(0.1)
            mock_handler.update_work_item_field.assert_called_once()
            call_args = mock_handler.update_work_item_field.call_args
            self.assertEqual(call_args[0][0], 1001)
            self.assertEqual(call_args[0][1], "Microsoft.VSTS.Scheduling.TargetDate")
            self.assertEqual(call_args[0][2], "2026-09-15T17:00:00Z")

    def test_backend_update_work_item_iteration_async(self):
        from gui.backend import DevOpsBackend
        import time

        backend = DevOpsBackend()
        backend._cache_db = self.cache

        raw_wi = {
            "id": 1002,
            "fields": {
                "System.Title": "Item for async iteration update",
                "System.WorkItemType": "Task",
                "System.State": "Active",
                "System.IterationPath": "Project\\week-2630"
            }
        }
        self.cache.save_work_item(1002, "Item for async iteration update", "Task", "Active", "Charlie", "2026-07-01", raw_wi)
        backend.refresh_all_data()

        mock_handler = MagicMock()
        with patch("devops_helper._getHandler", return_value=mock_handler), \
             patch("devops_helper.AZURE_PROJECT_ID", "MyProject"):
            res = backend.update_work_item_iteration(1002, "week-2635")

            # Check immediate return value (optimistic UI update)
            self.assertTrue(res["success"])
            self.assertEqual(res["iteration"], "week-2635")
            self.assertEqual(res["full_path"], "MyProject\\week-2635")
            self.assertTrue(res["syncing"])

            # Check SQLite DB was updated immediately
            wi_db = self.cache.get_work_item(1002)
            raw_db = json.loads(wi_db["raw_json"])
            self.assertEqual(raw_db["fields"]["System.IterationPath"], "MyProject\\week-2635")

            # Wait briefly for daemon thread to complete
            time.sleep(0.1)
            mock_handler.update_work_item_field.assert_called_once()
            call_args = mock_handler.update_work_item_field.call_args
            self.assertEqual(call_args[0][0], 1002)
            self.assertEqual(call_args[0][1], "System.IterationPath")
            self.assertEqual(call_args[0][2], "MyProject\\week-2635")


if __name__ == "__main__":
    unittest.main()

