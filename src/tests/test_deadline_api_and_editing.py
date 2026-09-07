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


if __name__ == "__main__":
    unittest.main()
