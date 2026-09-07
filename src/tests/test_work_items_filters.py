import unittest
import os
import sys
import tempfile

py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from azure.azure_db import AzureDevOpsCache
from gui.backend import DevOpsBackend


class TestWorkItemsFilters(unittest.TestCase):
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

    def test_azure_db_work_item_iteration_fields(self):
        wi_id = 1001
        raw = {
            "id": wi_id,
            "fields": {
                "System.Title": "Implement feature X",
                "System.WorkItemType": "Feature",
                "System.State": "Active",
                "System.AssignedTo": {"displayName": "Alice Smith"},
                "System.ChangedDate": "2026-09-01T10:00:00Z",
                "System.IterationPath": "MyProject\\TeamA\\week-2630",
                "System.IterationId": 555,
                "System.AreaPath": "MyProject\\Area1",
            }
        }
        self.cache.save_work_item(
            wi_id,
            raw["fields"]["System.Title"],
            raw["fields"]["System.WorkItemType"],
            raw["fields"]["System.State"],
            "Alice Smith",
            raw["fields"]["System.ChangedDate"],
            raw,
            deleted=0
        )

        item = self.cache.get_work_item(wi_id)
        self.assertIsNotNone(item)
        self.assertEqual(item["iteration_path"], "MyProject\\TeamA\\week-2630")
        self.assertEqual(item["iteration_id"], 555)
        self.assertEqual(item["area_path"], "MyProject\\Area1")

        all_items = self.cache.get_all_work_items()
        self.assertEqual(len(all_items), 1)
        self.assertEqual(all_items[0]["iteration_path"], "MyProject\\TeamA\\week-2630")
        self.assertEqual(all_items[0]["iteration_id"], 555)
        self.assertEqual(all_items[0]["area_path"], "MyProject\\Area1")

    def test_backend_iteration_classification(self):
        # Create work items with different iteration hierarchies:
        # 1. Project root -> Unplanned
        # 2. Team area parent container -> Unplanned
        # 3. Dev Backlog -> Unplanned (contains backlog)
        # 4. Sprint week-2630 -> Planned
        # 5. Sprint week-2633 -> Planned
        items = [
            (2001, "Root item", "Task", "Active", "Dev 1", "2026-09-05T12:00:00Z", "ProjX"),
            (2002, "Team backlog item", "Task", "Active", "Dev 2", "2026-09-04T12:00:00Z", "ProjX\\TeamA"),
            (2003, "Dev backlog item", "Task", "Active", "Dev 1", "2026-09-03T12:00:00Z", "ProjX\\TeamA\\Dev Backlog"),
            (2004, "Planned sprint 1", "Bug", "Resolved", "Dev 3", "2026-09-02T12:00:00Z", "ProjX\\TeamA\\week-2630"),
            (2005, "Planned sprint 2", "Feature", "In Progress", "Dev 2", "2026-08-20T12:00:00Z", "ProjX\\TeamA\\week-2633"),
        ]

        for wi_id, title, type_str, state, user, date_str, iter_path in items:
            raw = {
                "id": wi_id,
                "fields": {
                    "System.Title": title,
                    "System.WorkItemType": type_str,
                    "System.State": state,
                    "System.AssignedTo": {"displayName": user},
                    "System.ChangedDate": date_str,
                    "System.IterationPath": iter_path,
                }
            }
            self.cache.save_work_item(wi_id, title, type_str, state, user, date_str, raw, deleted=0)

        # Setup backend with this cache database
        backend = DevOpsBackend()
        backend._cache_db = self.cache
        backend._db_path = self.tmp_db.name
        backend.refresh_all_data()

        work_items = backend.workItems
        self.assertEqual(len(work_items), 5)

        by_id = {wi["id"]: wi for wi in work_items}

        # Item 2001: Root path -> Unplanned
        self.assertFalse(by_id[2001]["is_iteration_planned"])

        # Item 2002: Team parent container -> Unplanned
        self.assertFalse(by_id[2002]["is_iteration_planned"])

        # Item 2003: Backlog leaf -> Unplanned
        self.assertFalse(by_id[2003]["is_iteration_planned"])

        # Item 2004: week-2630 -> Planned
        self.assertTrue(by_id[2004]["is_iteration_planned"])
        self.assertEqual(by_id[2004]["iteration_name"], "week-2630")

        # Item 2005: week-2633 -> Planned
        self.assertTrue(by_id[2005]["is_iteration_planned"])
        self.assertEqual(by_id[2005]["iteration_name"], "week-2633")

        # Test backend properties
        iterations = backend.workItemIterations
        self.assertEqual(iterations, ["week-2630", "week-2633"])

        assignees = backend.workItemAssignees
        self.assertEqual(assignees, ["Dev 1", "Dev 2", "Dev 3"])


if __name__ == "__main__":
    unittest.main()
