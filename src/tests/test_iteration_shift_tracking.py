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

    def test_is_scheduled_sprint(self):
        from src.azure.azure_db import _is_scheduled_sprint
        self.assertTrue(_is_scheduled_sprint("Project\\week-2631"))
        self.assertTrue(_is_scheduled_sprint("Sprint 2026-31"))
        self.assertTrue(_is_scheduled_sprint("Iteration 4"))
        self.assertTrue(_is_scheduled_sprint("week-2633"))
        self.assertFalse(_is_scheduled_sprint("Project\\Backlog"))
        self.assertFalse(_is_scheduled_sprint("Backlog"))
        self.assertFalse(_is_scheduled_sprint("Unassigned"))
        self.assertFalse(_is_scheduled_sprint(""))
        self.assertFalse(_is_scheduled_sprint(None))

    def test_review_status_lifecycle_and_filters(self):
        self._save_wi(3001, "Story X", "User Story", "Active", "Carol", "P\\week-2630")
        self.db.update_work_item_iteration(3001, "P\\week-2632", source="user_gui")
        self.db.update_work_item_iteration(3001, "P\\week-2634", source="user_gui")

        shifts = self.db.get_iteration_shifts(work_item_id=3001)
        self.assertEqual(len(shifts), 2)
        # Default status is pending
        self.assertEqual(shifts[0]["review_status"], "pending")
        self.assertEqual(shifts[1]["review_status"], "pending")

        # Accept first shift by ID
        shift_id = shifts[0]["id"]
        ok = self.db.update_shift_review_status(shift_id, status="accepted", reviewed_by="Lead")
        self.assertTrue(ok)

        # Query filtered by accepted
        acc_shifts = self.db.get_iteration_shifts(work_item_id=3001, review_status="accepted")
        self.assertEqual(len(acc_shifts), 1)
        self.assertEqual(acc_shifts[0]["id"], shift_id)
        self.assertEqual(acc_shifts[0]["reviewed_by"], "Lead")

        # Query filtered by pending
        pend_shifts = self.db.get_iteration_shifts(work_item_id=3001, review_status="pending")
        self.assertEqual(len(pend_shifts), 1)

        # Accept all shifts for work item 3001
        self.db.update_work_item_shifts_review_status(3001, status="accepted")
        acc_all = self.db.get_iteration_shifts(work_item_id=3001, review_status="accepted")
        self.assertEqual(len(acc_all), 2)

        # Metrics reflects pending/accepted
        m = self.db.get_shift_metrics()
        self.assertEqual(m["accepted_shifts_count"], 2)
        self.assertEqual(m["pending_shifts_count"], 0)


if __name__ == "__main__":
    unittest.main()
