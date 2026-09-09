# -*- coding: UTF-8 -*-
"""
Unit tests for weekly iteration advance preparation, ISO week schematic continuation,
classification node synchronization, and SQLite caching.
"""

import os
import sys
import unittest
import tempfile
import json
from datetime import date, datetime
from unittest.mock import MagicMock, patch

# Ensure src is in sys.path
SRC_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

import utils
from azure.azure_db import AzureDevOpsCache
from azure.azure_base_client import AzureBaseClient
from azure.azure_info_handler import AzureInfoHandler
from gui.backend import DevOpsBackend


class TestWeeklyIterationsAdvance(unittest.TestCase):

    def setUp(self):
        self.tmp_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        self.tmp_db.close()
        self.cache = AzureDevOpsCache(self.tmp_db.name)

    def tearDown(self):
        if os.path.exists(self.tmp_db.name):
            try:
                os.remove(self.tmp_db.name)
            except Exception:
                pass

    def test_generate_weekly_iterations_advance_single_year(self):
        """Test generating iterations across weeks within the same year."""
        # Start at 2026 week 33, deadline 2026 week 36 (or date in week 36: 2026-09-04)
        iters = utils.generate_weekly_iterations_advance(
            start_date_or_week="week-2633",
            deadline="2026-09-04"
        )
        self.assertEqual(len(iters), 4)
        names = [it["sprint_name"] for it in iters]
        self.assertEqual(names, ["week-2633", "week-2634", "week-2635", "week-2636"])

        # Check fields of the first iteration (2026 week 33)
        it0 = iters[0]
        self.assertEqual(it0["year"], 2026)
        self.assertEqual(it0["week"], 33)
        self.assertEqual(it0["start_date"], "2026-08-10") # Monday
        self.assertEqual(it0["end_date"], "2026-08-14")   # Friday
        self.assertIn("week-2633", it0["label"])
        self.assertEqual(it0["short_label"], "W33")

    def test_generate_weekly_iterations_advance_year_rollover(self):
        """Test generating iterations across a calendar year boundary (e.g. 2026 to 2027)."""
        # Start from week-2651 up to week-2703
        iters = utils.generate_weekly_iterations_advance(
            start_date_or_week="week-2651",
            deadline="week-2703"
        )
        names = [it["sprint_name"] for it in iters]
        self.assertIn("week-2651", names)
        self.assertIn("week-2652", names)
        self.assertIn("week-2701", names)
        self.assertIn("week-2702", names)
        self.assertIn("week-2703", names)

        # Check year fields on the rollover
        idx_2701 = names.index("week-2701")
        self.assertEqual(iters[idx_2701]["year"], 2027)
        self.assertEqual(iters[idx_2701]["week"], 1)

    def test_generate_weekly_iterations_advance_with_weeks_count(self):
        """Test generating a specific count of weekly iterations."""
        iters = utils.generate_weekly_iterations_advance(
            start_date_or_week=(2026, 40),
            weeks_count=6
        )
        self.assertEqual(len(iters), 6)
        expected = ["week-2640", "week-2641", "week-2642", "week-2643", "week-2644", "week-2645"]
        self.assertEqual([it["sprint_name"] for it in iters], expected)

    def test_get_iterations_up_to_deadline(self):
        """Test get_iterations_up_to_deadline helper."""
        iters = utils.get_iterations_up_to_deadline(
            current_or_latest_iter="week-2610",
            deadline_date_or_str="2026-03-27" # week 13
        )
        self.assertTrue(len(iters) >= 4)
        self.assertEqual(iters[0]["sprint_name"], "week-2610")
        self.assertEqual(iters[-1]["sprint_name"], "week-2613")

    def test_cached_iterations_db_crud(self):
        """Test saving, retrieving, and deleting cached iterations in SQLite."""
        self.cache.save_cached_iteration(
            project="ProjX",
            name="week-2640",
            path="ProjX\\week-2640",
            start_date="2026-09-28",
            end_date="2026-10-02",
            year=2026,
            week=40,
            is_synced=1
        )
        self.cache.save_cached_iteration(
            project="ProjX",
            name="week-2641",
            path="ProjX\\week-2641",
            start_date="2026-10-05",
            end_date="2026-10-09",
            year=2026,
            week=41,
            is_synced=0
        )

        rows = self.cache.get_cached_iterations(project="ProjX")
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["iteration_name"], "week-2640")
        self.assertEqual(rows[0]["is_server_synced"], 1)
        self.assertEqual(rows[1]["iteration_name"], "week-2641")
        self.assertEqual(rows[1]["is_server_synced"], 0)

        # Test upsert on duplicate
        self.cache.save_cached_iteration(
            project="ProjX",
            name="week-2641",
            path="ProjX\\week-2641",
            start_date="2026-10-05",
            end_date="2026-10-09",
            year=2026,
            week=41,
            is_synced=1 # updated
        )
        rows_after = self.cache.get_cached_iterations(project="ProjX")
        self.assertEqual(len(rows_after), 2)
        self.assertEqual(rows_after[1]["is_server_synced"], 1)

        # Test delete
        self.cache.delete_cached_iteration("week-2640", project="ProjX")
        rows_del = self.cache.get_cached_iterations(project="ProjX")
        self.assertEqual(len(rows_del), 1)
        self.assertEqual(rows_del[0]["iteration_name"], "week-2641")

        # Test clear
        self.cache.clear_cached_iterations(project="ProjX")
        self.assertEqual(len(self.cache.get_cached_iterations(project="ProjX")), 0)

    @patch.object(AzureBaseClient, "_request")
    def test_azure_base_client_classification_nodes(self, mock_request):
        """Test AzureBaseClient get_classification_nodes and create_classification_node."""
        mock_request.return_value = ({"name": "Iterations", "children": [{"name": "week-2630"}]}, 200)

        client = AzureBaseClient("https://tfs.example.com/tfs", "pat_token")
        tree = client.get_classification_nodes("ProjX", structure_group="iterations")
        self.assertIn("name", tree)
        self.assertEqual(tree["name"], "Iterations")

        # Test create_classification_node
        mock_request.return_value = ({"id": 999, "name": "week-2635", "attributes": {"startDate": "2026-08-24T00:00:00Z"}}, 200)
        res = client.create_classification_node("ProjX", "week-2635", start_date="2026-08-24", finish_date="2026-08-28")
        self.assertEqual(res["name"], "week-2635")
        mock_request.assert_called()

    @patch.object(AzureInfoHandler, "_request")
    def test_azure_info_handler_prepare_weekly_iterations(self, mock_request):
        """Test AzureInfoHandler.prepare_weekly_iterations with mocked TFS server."""
        # Mock tree response indicating week-2633 already exists
        def mock_req(method, path, params=None, data=None, **kwargs):
            if method == "GET" and "classificationnodes/iterations" in path:
                return ({"name": "Iterations", "children": [{"name": "week-2633"}]}, 200)
            elif method == "POST" and "classificationnodes/iterations" in path:
                return ({"id": 1000, "name": data.get("name")}, 200)
            return ({}, 200)

        mock_request.side_effect = mock_req

        handler = AzureInfoHandler("https://tfs.example.com/tfs", "pat_token")
        summary = handler.prepare_weekly_iterations(
            project_id="ProjX",
            start_from="week-2633",
            deadline="week-2635",
            sync_to_tfs=True,
            cache_db=self.cache
        )

        self.assertEqual(summary["total_generated"], 3) # 2633, 2634, 2635
        # 2633 already existed, so 2634 and 2635 should have been created on server
        self.assertEqual(summary["created_on_server"], 2)

        # Check that iterations were saved in SQLite cache
        cached = self.cache.get_cached_iterations(project="ProjX")
        self.assertEqual(len(cached), 3)

    def test_backend_available_sprint_list_and_workload_matrix(self):
        """Test DevOpsBackend incorporates prepared advance iterations into availableSprintList and getWorkloadMatrix."""
        # 1. Setup backend with cache
        backend = DevOpsBackend()
        backend._cache_db = self.cache
        backend._db_path = self.tmp_db.name
        backend.selectedProject = "ProjX"

        # 2. Add an advance prepared sprint in DB
        self.cache.save_cached_iteration(
            project="ProjX",
            name="week-2650",
            path="ProjX\\week-2650",
            start_date="2026-12-07",
            end_date="2026-12-11",
            year=2026,
            week=50,
            is_synced=1
        )

        backend.refresh_all_data()
        sprints = backend.availableSprintList
        self.assertIn("week-2650", sprints)

        # 3. Test prepareWeeklyIterations slot
        res = backend.prepareWeeklyIterations(deadline="week-2652", start_from="week-2650", sync_to_tfs=False)
        self.assertTrue(res["total_generated"] >= 3)
        self.assertIn("week-2651", backend.availableSprintList)
        self.assertIn("week-2652", backend.availableSprintList)

        # 4. Test getWorkloadMatrix includes forward sprints
        matrix = backend.getWorkloadMatrix(horizon_weeks=4)
        cols = matrix.get("sprint_columns", [])
        self.assertTrue(len(cols) >= 1)


if __name__ == "__main__":
    unittest.main()
