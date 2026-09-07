import unittest
import tempfile
import os
import shutil
from src.azure.azure_db import AzureDevOpsCache, _calculate_sprint_delta_weeks


class TestIterationShiftTracking(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_shifts.db")
        self.db = AzureDevOpsCache(self.db_path)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _save_wi(self, wi_id, title, type_str, state, assigned_to, iteration_path):
        raw_obj = {
            "id": wi_id,
            "fields": {
                "System.Title": title,
                "System.WorkItemType": type_str,
                "System.State": state,
                "System.AssignedTo": {"displayName": assigned_to} if isinstance(assigned_to, str) else assigned_to,
                "System.IterationPath": iteration_path
            }
        }
        self.db.save_work_item(
            wi_id=wi_id,
            title=title,
            type_str=type_str,
            state=state,
            assigned_to=assigned_to,
            changed_date="2026-08-01T10:00:00Z",
            raw_json_obj=raw_obj
        )

    def test_calculate_sprint_delta_weeks(self):
        # 2-digit year format: week-YYWW
        self.assertEqual(_calculate_sprint_delta_weeks("Project\\week-2631", "Project\\week-2633"), 2)
        self.assertEqual(_calculate_sprint_delta_weeks("week-2633", "week-2631"), -2)
        self.assertEqual(_calculate_sprint_delta_weeks("week-2631", "week-2631"), 0)

        # 4-digit year format: Sprint 2026-31 to Sprint 2026-35
        self.assertEqual(_calculate_sprint_delta_weeks("Sprint 2026-31", "Sprint 2026-35"), 4)

        # Non-matching or None format defaults to 0
        self.assertEqual(_calculate_sprint_delta_weeks("Backlog", "week-2631"), 0)
        self.assertEqual(_calculate_sprint_delta_weeks(None, "week-2631"), 0)

    def test_sync_records_iteration_shift(self):
        # Initial save of work item in week-2631
        self._save_wi(1001, "Initial User Story", "User Story", "Active", "Alice", "MyProj\\week-2631")

        # Verify no shifts recorded yet
        shifts = self.db.get_iteration_shifts(work_item_id=1001)
        self.assertEqual(len(shifts), 0)

        # Sync updates work item to week-2634 (+3 weeks delay)
        self._save_wi(1001, "Initial User Story", "User Story", "Active", "Alice", "MyProj\\week-2634")

        shifts = self.db.get_iteration_shifts(work_item_id=1001)
        self.assertEqual(len(shifts), 1)
        self.assertEqual(shifts[0]["work_item_id"], 1001)
        self.assertEqual(shifts[0]["old_sprint"], "week-2631")
        self.assertEqual(shifts[0]["new_sprint"], "week-2634")
        self.assertEqual(shifts[0]["delta_weeks"], 3)
        self.assertEqual(shifts[0]["source"], "tfs_sync")

    def test_manual_update_work_item_iteration(self):
        self._save_wi(1002, "Critical Bug", "Bug", "Active", "Bob", "MyProj\\week-2630")

        # Manual move via GUI to week-2632
        res = self.db.update_work_item_iteration(1002, "MyProj\\week-2632", source="user_gui")
        self.assertTrue(res)

        # Check shifts table
        shifts = self.db.get_iteration_shifts(work_item_id=1002)
        self.assertEqual(len(shifts), 1)
        self.assertEqual(shifts[0]["source"], "user_gui")
        self.assertEqual(shifts[0]["delta_weeks"], 2)

        # Check raw json iteration was updated
        item = self.db.get_work_item(1002)
        self.assertEqual(item["iteration_path"], "MyProj\\week-2632")

    def test_shift_metrics_calculation(self):
        # Insert 3 work items
        self._save_wi(2001, "Story A", "User Story", "Active", "Alice", "P\\week-2630")
        self._save_wi(2002, "Bug B", "Bug", "Active", "Bob", "P\\week-2630")
        self._save_wi(2003, "Story C", "User Story", "Active", "Alice", "P\\week-2630")

        # Reschedule Story A by +2 weeks
        self.db.update_work_item_iteration(2001, "P\\week-2632", source="user_gui")
        # Reschedule Story A again by +1 week (Total +3w, 2 moves)
        self.db.update_work_item_iteration(2001, "P\\week-2633", source="user_gui")
        # Reschedule Bug B by +1 week (Total +1w, 1 move)
        self.db.update_work_item_iteration(2002, "P\\week-2631", source="tfs_sync")

        metrics = self.db.get_shift_metrics()
        self.assertEqual(metrics["total_shifts"], 3)
        self.assertEqual(metrics["total_shifted_items"], 2)
        self.assertEqual(metrics["net_delay_weeks"], 4)  # 3 + 1
        self.assertIsNotNone(metrics["most_delayed_item"])
        self.assertEqual(metrics["most_delayed_item"]["id"], 2001)
        self.assertEqual(metrics["most_delayed_item"]["total_delayed_weeks"], 3)
        self.assertEqual(metrics["most_delayed_item"]["shift_count"], 2)
        self.assertEqual(len(metrics["top_delayed_items"]), 2)


if __name__ == "__main__":
    unittest.main()
