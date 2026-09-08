# -*- coding: UTF-8 -*-
import unittest
from unittest.mock import MagicMock, patch
import urllib.error
import tempfile
import os
import shutil

import sys
test_dir = os.path.dirname(os.path.realpath(__file__))
py_dir = os.path.dirname(test_dir)
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from azure import AzureDevOpsCache, AzureInfoHandler
import devops_helper


class TestSyncWorkItems(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_cache.db")
        self.cache = AzureDevOpsCache(self.db_path)
        self.handler = AzureInfoHandler("https://tfs.example.com/tfs", "fake-token")

    def tearDown(self):
        try:
            shutil.rmtree(self.test_dir)
        except Exception:
            pass

    def test_sync_work_items_success_and_deleted(self):
        # Seed 2 work items in database
        self.cache.save_work_item(1001, "Active Task", "Task", "Active", "Dev A", "2025-01-01", {"id": 1001})
        self.cache.save_work_item(1002, "Obsolete Task", "Task", "Active", "Dev B", "2025-01-01", {"id": 1002})

        # Mock get_work_item: 1001 exists, 1002 returns 404 HTTPError
        def mock_get_wi(task_id):
            if int(task_id) == 1001:
                return {
                    "id": 1001,
                    "fields": {
                        "System.Title": "Active Task Updated",
                        "System.WorkItemType": "Task",
                        "System.State": "Resolved",
                        "System.AssignedTo": {"displayName": "Dev A"},
                        "System.ChangedDate": "2025-02-01",
                    }
                }
            elif int(task_id) == 1002:
                raise urllib.error.HTTPError(None, 404, "Work item does not exist", None, None)
            raise ValueError(f"Unexpected task id: {task_id}")

        self.handler.get_work_item = MagicMock(side_effect=mock_get_wi)

        summary = self.handler.sync_work_items(self.cache)

        self.assertEqual(summary["synced"], 1)
        self.assertEqual(summary["deleted"], 1)
        self.assertEqual(summary["errors"], 0)

        # Verify 1001 is updated and active
        wi_1001 = self.cache.get_work_item(1001)
        self.assertEqual(wi_1001["Title"], "Active Task Updated")
        self.assertEqual(wi_1001["State"], "Resolved")
        self.assertFalse(wi_1001["deleted"])

        # Verify 1002 is marked deleted while retaining original title
        wi_1002 = self.cache.get_work_item(1002)
        self.assertEqual(wi_1002["Title"], "Obsolete Task")
        self.assertTrue(wi_1002["deleted"])
        self.assertEqual(wi_1002["is_deleted"], 1)

    def test_sync_work_items_server_error_not_marked_deleted(self):
        # Work item in DB
        self.cache.save_work_item(1003, "Important Task", "Task", "Active", "Dev C", "2025-01-01", {"id": 1003})

        # Server error 500 should NOT mark work item deleted
        self.handler.get_work_item = MagicMock(
            side_effect=urllib.error.HTTPError(None, 500, "Internal Server Error", None, None)
        )

        summary = self.handler.sync_work_items(self.cache)

        self.assertEqual(summary["synced"], 0)
        self.assertEqual(summary["deleted"], 0)
        self.assertEqual(summary["errors"], 1)

        wi_1003 = self.cache.get_work_item(1003)
        self.assertFalse(wi_1003["deleted"])

    @patch("devops_helper.ParseMarkdown")
    @patch("devops_helper._getHandler")
    @patch("devops_helper._getDBCacheHandler")
    def test_devops_helper_sync_replaces_parse_markdown(self, mock_get_db, mock_get_handler, mock_parse_md):
        mock_handler = MagicMock()
        mock_handler.GetTFSRepositories.return_value = {"repo1": {}}
        mock_handler.sync_work_items.return_value = {"synced": 2, "deleted": 1, "errors": 0}
        mock_get_handler.return_value = mock_handler

        mock_db = MagicMock()
        mock_db.get_project_last_synced.return_value = None
        mock_db.get_all_work_item_ids.return_value = [101, 102, 103]
        mock_get_db.return_value = (self.db_path, mock_db)

        # Run devops_helper.sync
        devops_helper.sync(force_sync=True)

        # Verify ParseMarkdown was NOT called
        mock_parse_md.assert_not_called()

        # Verify sync_work_items was called with project_id
        mock_handler.sync_work_items.assert_called_once_with(mock_db, project_id=devops_helper.AZURE_PROJECT_ID)

    @patch("devops_helper._getHandler", return_value=None)
    def test_devops_helper_sync_missing_handler_raises_runtime_error(self, mock_get_handler):
        with self.assertRaises(RuntimeError) as ctx:
            devops_helper.sync(force_sync=True)
        self.assertIn("Azure/TFS client could not be initialized", str(ctx.exception))

    def test_query_work_item_ids_wiql(self):
        mock_response = {
            "workItems": [
                {"id": 501, "url": "https://.../501"},
                {"id": 502, "url": "https://.../502"}
            ]
        }
        self.handler._request = MagicMock(return_value=(mock_response, 200))

        ids = self.handler.query_work_item_ids_wiql("TEST_PROJECT")
        self.assertEqual(ids, [501, 502])
        self.handler._request.assert_called_with(
            "POST", "TEST_PROJECT/_apis/wit/wiql", params={"api-version": "6.0"},
            data={"query": "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = 'TEST_PROJECT' ORDER BY [System.Id]"}
        )

    def test_sync_work_items_wiql_discovery(self):
        # Database already has 401 (active) and 402 (will be deleted because not returned by WIQL/batch)
        self.cache.save_work_item(401, "Task 401", "Task", "Active", "Dev A", "2025-01-01", {"id": 401})
        self.cache.save_work_item(402, "Task 402", "Task", "Active", "Dev B", "2025-01-01", {"id": 402})

        # WIQL discovers 401 and 403 (brand new task never seen before)
        self.handler.query_work_item_ids_wiql = MagicMock(return_value=[401, 403])

        # Batch API returns 401 and 403
        self.handler.get_work_items_batch = MagicMock(return_value=[
            {"id": 401, "fields": {"System.Title": "Task 401 Updated", "System.WorkItemType": "Task", "System.State": "Resolved"}},
            {"id": 403, "fields": {"System.Title": "Brand New Task 403", "System.WorkItemType": "Bug", "System.State": "New"}},
        ])

        # Sync without knowing task IDs in advance!
        summary = self.handler.sync_work_items(self.cache, project_id="TEST_PROJECT")

        self.assertEqual(summary["synced"], 2)   # 401 and 403
        self.assertEqual(summary["deleted"], 1)  # 402 was in db, but not returned by API -> marked deleted

        # 401 updated
        wi_401 = self.cache.get_work_item(401)
        self.assertEqual(wi_401["Title"], "Task 401 Updated")
        self.assertFalse(wi_401["deleted"])

        # 403 newly created
        wi_403 = self.cache.get_work_item(403)
        self.assertIsNotNone(wi_403)
        self.assertEqual(wi_403["Title"], "Brand New Task 403")
        self.assertFalse(wi_403["deleted"])

        # 402 marked deleted
        wi_402 = self.cache.get_work_item(402)
        self.assertTrue(wi_402["deleted"])
        self.assertEqual(wi_402["Title"], "Task 402")

    def test_get_work_items_batch(self):
        # Mock _request
        mock_response = {
            "count": 2,
            "value": [
                {"id": 201, "fields": {"System.Title": "Task 201"}},
                {"id": 202, "fields": {"System.Title": "Task 202"}}
            ]
        }
        self.handler._request = MagicMock(return_value=(mock_response, 200))

        items = self.handler.get_work_items_batch([201, 202, 203], chunk_size=2)
        self.assertEqual(len(items), 4)  # 2 calls * 2 items returned
        # Verify endpoint and method
        self.handler._request.assert_called_with(
            "POST", "_apis/wit/workitemsbatch", params={"api-version": "6.0"}, data={"ids": [203]}
        )

    def test_sync_work_items_batch_mode(self):
        self.cache.save_work_item(301, "Old Title 301", "Task", "Active", "Dev A", "2025-01-01", {"id": 301})
        self.cache.save_work_item(302, "Old Title 302", "Task", "Active", "Dev B", "2025-01-01", {"id": 302})

        # Batch returns only 301 (302 is deleted/omitted)
        self.handler.get_work_items_batch = MagicMock(return_value=[
            {
                "id": 301,
                "fields": {
                    "System.Title": "New Title 301",
                    "System.WorkItemType": "Task",
                    "System.State": "Closed",
                    "System.AssignedTo": {"displayName": "Dev A"},
                    "System.ChangedDate": "2025-03-01",
                }
            }
        ])

        # WIQL returns 301 from remote
        self.handler.query_work_item_ids_wiql = MagicMock(return_value=[301])
        summary = self.handler.sync_work_items(self.cache)

        self.assertEqual(summary["synced"], 1)
        self.assertEqual(summary["deleted"], 1)
        self.assertEqual(summary["errors"], 0)

        wi_301 = self.cache.get_work_item(301)
        self.assertEqual(wi_301["Title"], "New Title 301")
        self.assertEqual(wi_301["State"], "Closed")
        self.assertFalse(wi_301["deleted"])

        wi_302 = self.cache.get_work_item(302)
        self.assertTrue(wi_302["deleted"])
        self.assertEqual(wi_302["Title"], "Old Title 302")

    def test_query_work_item_ids_wiql_tree_links(self):
        mock_tree_response = {
            "queryType": "tree",
            "queryResultType": "workItemLink",
            "workItemRelations": [
                {"rel": None, "source": None, "target": {"id": 100, "url": "https://.../100"}},
                {"rel": "System.LinkTypes.Hierarchy-Forward", "source": {"id": 100, "url": "https://.../100"}, "target": {"id": 200, "url": "https://.../200"}},
                {"rel": "System.LinkTypes.Hierarchy-Forward", "source": {"id": 200, "url": "https://.../200"}, "target": {"id": 300, "url": "https://.../300"}},
            ]
        }
        self.handler._request = MagicMock(return_value=(mock_tree_response, 200))

        ids = self.handler.query_work_item_ids_wiql("TEST_PROJECT", query="SELECT [System.Id] FROM WorkItemLinks")
        self.assertEqual(sorted(ids), [100, 200, 300])

    def test_query_work_item_hierarchy_wiql(self):
        mock_tree_response = {
            "queryType": "tree",
            "queryResultType": "workItemLink",
            "workItemRelations": [
                {"rel": "System.LinkTypes.Hierarchy-Forward", "source": {"id": 10, "url": "https://.../10"}, "target": {"id": 20, "url": "https://.../20"}},
            ]
        }
        self.handler._request = MagicMock(return_value=(mock_tree_response, 200))

        relations = self.handler.query_work_item_hierarchy_wiql("TEST_PROJECT")
        self.assertEqual(len(relations), 1)
        self.assertEqual(relations[0]["source"]["id"], 10)
        self.assertEqual(relations[0]["target"]["id"], 20)

    def test_sync_work_items_auto_fetches_missing_parents(self):
        # Child Task 600 references Parent Story 500 via System.Parent
        # Story 500 references Epic 400 via Hierarchy-Reverse relation
        # Initial query only returns Child Task 600
        self.handler.query_work_item_ids_wiql = MagicMock(return_value=[600])

        def batch_side_effect(chunk, expand=None, chunk_size=200):
            res = []
            for cid in chunk:
                if cid == 600:
                    res.append({
                        "id": 600,
                        "fields": {"System.Title": "Child Task 600", "System.WorkItemType": "Task", "System.State": "Active", "System.Parent": 500},
                        "relations": [{"rel": "System.LinkTypes.Hierarchy-Reverse", "url": "https://.../500"}]
                    })
                elif cid == 500:
                    res.append({
                        "id": 500,
                        "fields": {"System.Title": "Parent Story 500", "System.WorkItemType": "User Story", "System.State": "Active"},
                        "relations": [{"rel": "System.LinkTypes.Hierarchy-Reverse", "url": "https://.../400"}]
                    })
                elif cid == 400:
                    res.append({
                        "id": 400,
                        "fields": {"System.Title": "Grandparent Epic 400", "System.WorkItemType": "Epic", "System.State": "Active"},
                        "relations": []
                    })
            return res

        self.handler.get_work_items_batch = MagicMock(side_effect=batch_side_effect)

        summary = self.handler.sync_work_items(self.cache, project_id="TEST_PROJECT")

        # All 3 (600, 500, 400) should be synced
        self.assertEqual(summary["synced"], 3)
        self.assertIsNotNone(self.cache.get_work_item(600))
        self.assertIsNotNone(self.cache.get_work_item(500))
        self.assertIsNotNone(self.cache.get_work_item(400))
        self.assertEqual(self.cache.get_work_item(500)["Title"], "Parent Story 500")
        self.assertEqual(self.cache.get_work_item(400)["Title"], "Grandparent Epic 400")

    def test_sync_work_items_progress_callback(self):
        """Tests that sync_work_items invokes progress_callback with informative progress messages."""
        self.handler.query_work_item_ids_wiql = MagicMock(return_value=[1001, 1002, 1003])
        all_mock_items = {
            1001: {"id": 1001, "fields": {"System.Title": "Item 1", "System.WorkItemType": "Task", "System.State": "Active"}},
            1002: {"id": 1002, "fields": {"System.Title": "Item 2", "System.WorkItemType": "Task", "System.State": "Active"}},
            1003: {"id": 1003, "fields": {"System.Title": "Item 3", "System.WorkItemType": "Task", "System.State": "Active"}},
        }
        self.handler.get_work_items_batch = MagicMock(side_effect=lambda ids, **kwargs: [all_mock_items[i] for i in ids if i in all_mock_items])

        messages = []
        def on_progress(msg, current=0, total=0):
            messages.append((msg, current, total))

        summary = self.handler.sync_work_items(self.cache, project_id="TEST_PROJECT", chunk_size=2, progress_callback=on_progress)

        self.assertEqual(summary["synced"], 3)
        self.assertGreaterEqual(len(messages), 4, "Progress callback should be called multiple times across sync stages")
        
        # Check that messages contain WIQL start, discovery count, batch progress, and completion
        msg_texts = [m[0] for m in messages]
        self.assertTrue(any("WIQL" in m for m in msg_texts))
        self.assertTrue(any("batch" in m.lower() for m in msg_texts))
        self.assertTrue(any("completed" in m.lower() for m in msg_texts))

    def test_get_max_work_item_changed_date(self):
        self.assertIsNone(self.cache.get_max_work_item_changed_date())
        self.cache.save_work_item(1, "Task 1", "Task", "Active", "Dev", "2026-01-01T10:00:00Z", {"id": 1})
        self.cache.save_work_item(2, "Task 2", "Task", "Active", "Dev", "2026-03-01T12:00:00Z", {"id": 2})
        self.cache.save_work_item(3, "Task 3 (deleted)", "Task", "Active", "Dev", "2026-05-01T12:00:00Z", {"id": 3}, deleted=1)

        max_date = self.cache.get_max_work_item_changed_date()
        self.assertEqual(max_date, "2026-03-01T12:00:00Z")

    def test_query_work_item_ids_wiql_with_changed_since(self):
        self.handler._request = MagicMock(return_value=({"workItems": [{"id": 10}, {"id": 20}]}, 200))

        ids = self.handler.query_work_item_ids_wiql("MY_PROJ", changed_since="2026-03-01T10:00:00Z")
        self.assertEqual(ids, [10, 20])

        self.handler._request.assert_called_once_with(
            "POST", "MY_PROJ/_apis/wit/wiql", params={"api-version": "6.0"},
            data={"query": "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = 'MY_PROJ' AND [System.ChangedDate] >= '2026-03-01 10:00:00' ORDER BY [System.Id]"}
        )

    def test_incremental_sync_skips_unchanged_work_items(self):
        """Tests that only modified items are fetched when existing cached items have not changed."""
        # Seed 5 items in cache with ChangedDate
        for i in range(1, 6):
            self.cache.save_work_item(
                i, f"Task {i}", "Task", "Active", "Dev", "2026-03-01T10:00:00Z",
                {"id": i, "fields": {"System.ChangedDate": "2026-03-01T10:00:00Z"}}
            )

        # Mock query_work_item_ids_wiql:
        # Full query returns all 5 items [1, 2, 3, 4, 5]
        # Changed query (with changed_since) returns ONLY item 3 (modified)
        def mock_wiql(project_id=None, query=None, changed_since=None):
            if changed_since:
                return [3]
            return [1, 2, 3, 4, 5]

        self.handler.query_work_item_ids_wiql = MagicMock(side_effect=mock_wiql)

        # Mock batch fetch: should only be called for [3]
        mock_batch = MagicMock(return_value=[
            {
                "id": 3,
                "fields": {
                    "System.Title": "Task 3 Modified",
                    "System.WorkItemType": "Task",
                    "System.State": "Closed",
                    "System.AssignedTo": {"displayName": "Dev"},
                    "System.ChangedDate": "2026-03-02T15:00:00Z"
                }
            }
        ])
        self.handler.get_work_items_batch = mock_batch

        summary = self.handler.sync_work_items(self.cache, project_id="MY_PROJ")

        # Verify only item 3 was fetched in batch
        mock_batch.assert_called_once_with([3], expand="all", chunk_size=200)
        self.assertEqual(summary["synced"], 1)
        self.assertEqual(summary["unchanged"], 4)
        self.assertEqual(summary["deleted"], 0)

        # Verify item 3 is updated in cache
        wi3 = self.cache.get_work_item(3)
        self.assertEqual(wi3["Title"], "Task 3 Modified")
        self.assertEqual(wi3["State"], "Closed")

    def test_incremental_sync_fetches_new_items_and_reconciles_deletions(self):
        """Tests that new items and deleted items are reconciled alongside unchanged items."""
        # Database has items 10 and 20
        self.cache.save_work_item(10, "Task 10", "Task", "Active", "Dev", "2026-03-01T10:00:00Z", {"id": 10})
        self.cache.save_work_item(20, "Task 20 (will be deleted)", "Task", "Active", "Dev", "2026-03-01T10:00:00Z", {"id": 20})

        # Remote has items 10 (unchanged) and 30 (brand new item). Item 20 is gone from remote.
        def mock_wiql(project_id=None, query=None, changed_since=None):
            if changed_since:
                return []  # No existing items modified
            return [10, 30]

        self.handler.query_work_item_ids_wiql = MagicMock(side_effect=mock_wiql)

        mock_batch = MagicMock(return_value=[
            {
                "id": 30,
                "fields": {
                    "System.Title": "Task 30 New",
                    "System.WorkItemType": "Bug",
                    "System.State": "New",
                    "System.AssignedTo": {"displayName": "Tester"},
                    "System.ChangedDate": "2026-03-05T10:00:00Z"
                }
            }
        ])
        self.handler.get_work_items_batch = mock_batch

        summary = self.handler.sync_work_items(self.cache, project_id="MY_PROJ")

        # Batch was called ONLY for new item [30]
        mock_batch.assert_called_once_with([30], expand="all", chunk_size=200)
        self.assertEqual(summary["synced"], 1)   # Item 30
        self.assertEqual(summary["deleted"], 1)  # Item 20 marked deleted
        self.assertEqual(summary["unchanged"], 1) # Item 10 was skipped

        wi20 = self.cache.get_work_item(20)
        self.assertTrue(wi20["deleted"])

        wi30 = self.cache.get_work_item(30)
        self.assertIsNotNone(wi30)
        self.assertEqual(wi30["Title"], "Task 30 New")


if __name__ == "__main__":
    unittest.main()

