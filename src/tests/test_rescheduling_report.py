import unittest
import tempfile
import os
import shutil
import csv
from src.azure.azure_db import AzureDevOpsCache
from src.generate_rescheduling_report import (
    get_rescheduled_items_data,
    render_rescheduling_markdown,
    generate_rescheduling_report
)


class TestReschedulingReport(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_report_shifts.db")
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

    def test_backlog_to_sprint_ignored_in_report(self):
        # 1. Item 5001 moved from Backlog to Sprint week-2630 (initial scheduling)
        self._save_wi(5001, "Backlog Initial Item", "User Story", "Active", "Dave", "Project\\Backlog")
        self.db.update_work_item_iteration(5001, "Project\\week-2630", source="user_gui")

        # 2. Item 5002 was already in week-2630, moved to week-2632 (sprint-to-sprint reschedule)
        self._save_wi(5002, "Scheduled Rescheduled Item", "User Story", "Active", "Eve", "Project\\week-2630")
        self.db.update_work_item_iteration(5002, "Project\\week-2632", source="user_gui")

        # Get report data
        data = get_rescheduled_items_data(self.db)
        
        # Item 5001 should be ignored (was in Backlog), only 5002 should be in moved items
        moved_ids = [it["id"] for it in data["work_items"]]
        self.assertNotIn(5001, moved_ids)
        self.assertIn(5002, moved_ids)
        self.assertEqual(data["total_moved_items"], 1)
        self.assertEqual(data["total_shifts"], 1)
        self.assertEqual(data["net_delay_weeks"], 2)

    def test_generate_report_files(self):
        # Create sprint-to-sprint shifts
        self._save_wi(6001, "Refactor Core Architecture", "User Story", "Active", "Alice", "Proj\\week-2630")
        self.db.update_work_item_iteration(6001, "Proj\\week-2633", source="user_gui") # +3w
        self._save_wi(6002, "Fix Memory Leak", "Bug", "Active", "Bob", "Proj\\week-2631")
        self.db.update_work_item_iteration(6002, "Proj\\week-2632", source="tfs_sync") # +1w

        # Mark 6002 as accepted
        self.db.update_work_item_shifts_review_status(6002, status="accepted")

        md_path = os.path.join(self.test_dir, "test_rescheduling.md")
        csv_path = os.path.join(self.test_dir, "test_rescheduling.csv")

        res = generate_rescheduling_report(
            cache_db=self.db,
            output_md=md_path,
            output_csv=csv_path
        )

        self.assertTrue(res["success"])
        self.assertTrue(os.path.exists(md_path))
        self.assertTrue(os.path.exists(csv_path))
        self.assertEqual(res["total_moved_items"], 2)
        self.assertEqual(res["total_shifts"], 2)
        self.assertEqual(res["net_delay_weeks"], 4)
        self.assertEqual(res["pending_shifts_count"], 1)
        self.assertEqual(res["accepted_shifts_count"], 1)

        # Verify Markdown Content
        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()
            self.assertIn("# 🔄 Sprint Rescheduling & Postponement Impact Report", content)
            self.assertIn("Refactor Core Architecture", content)
            self.assertIn("Fix Memory Leak", content)
            self.assertIn("+3w", content)
            self.assertIn("+1w", content)
            self.assertIn("✅ Accepted", content)
            self.assertIn("⏳ Pending", content)

        # Verify CSV Content
        with open(csv_path, "r", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            self.assertEqual(len(rows), 2)
            row_map = {r["WorkItemID"]: r for r in rows}
            self.assertIn("6001", row_map)
            self.assertIn("6002", row_map)
            self.assertEqual(row_map["6001"]["ReviewStatus"], "pending")
            self.assertEqual(row_map["6002"]["ReviewStatus"], "accepted")


if __name__ == "__main__":
    unittest.main()
