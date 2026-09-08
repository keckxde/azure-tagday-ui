# -*- coding: UTF-8 -*-
"""
Unit tests for Weekly Sprint date math, deadline countdown calculations,
workload capacity matrix generation, and sprint report generation.
"""

import os
import sys
import tempfile
import unittest
from datetime import datetime, date, timedelta

py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import utils
import generate_sprint_report
from azure import AzureDevOpsCache


class TestSprintWorkloadAndDeadlines(unittest.TestCase):

    def test_parse_sprint_week_valid(self):
        # Format week-YYWW
        y, w, base = utils.parse_sprint_week("week-2633")
        self.assertEqual(y, 2026)
        self.assertEqual(w, 33)
        self.assertEqual(base, "week-2633")

        # Nested iteration path with uppercase
        y, w, base = utils.parse_sprint_week("ProjectRoot\\Sprints\\Week-2615")
        self.assertEqual(y, 2026)
        self.assertEqual(w, 15)
        self.assertEqual(base, "week-2615")

        # 4-digit year format: Sprint-2026-W30
        y, w, base = utils.parse_sprint_week("Sprint-2026-W30")
        self.assertEqual(y, 2026)
        self.assertEqual(w, 30)
        self.assertEqual(base, "week-2630")

    def test_parse_sprint_week_invalid(self):
        y, w, base = utils.parse_sprint_week("ProjectRoot\\Backlog")
        self.assertIsNone(y)
        self.assertIsNone(w)
        self.assertIsNone(base)

        y, w, base = utils.parse_sprint_week("")
        self.assertIsNone(y)
        self.assertIsNone(w)
        self.assertIsNone(base)

    def test_get_sprint_date_range(self):
        # Week 33 of 2026: Monday 2026-08-10 to Friday 2026-08-14
        start_d, end_d, start_str, end_str = utils.get_sprint_date_range(2026, 33)
        self.assertEqual(start_d, date(2026, 8, 10))
        self.assertEqual(end_d, date(2026, 8, 14))
        self.assertEqual(start_str, "2026-08-10")
        self.assertEqual(end_str, "2026-08-14")

        # Range label
        lbl = utils.format_sprint_range_label(2026, 33)
        self.assertIn("week-2633", lbl)
        self.assertIn("Aug 10", lbl)
        self.assertIn("Aug 14", lbl)

    def test_calculate_deadline_urgency_completed(self):
        urg = utils.calculate_deadline_urgency("2026-08-14", is_completed=True)
        self.assertEqual(urg["status"], "completed")
        self.assertEqual(urg["badge_text"], "✓ Closed")
        self.assertEqual(urg["badge_color"], "#3fb950")

    def test_calculate_deadline_urgency_overdue(self):
        # Anchor current time at 2026-08-20
        now_dt = datetime(2026, 8, 20, 10, 0, 0)
        urg = utils.calculate_deadline_urgency("2026-08-14", is_completed=False, now_dt=now_dt)
        self.assertEqual(urg["status"], "overdue")
        self.assertEqual(urg["days_diff"], -6)
        self.assertIn("6d Overdue", urg["badge_text"])
        self.assertEqual(urg["badge_color"], "#f85149")

    def test_calculate_deadline_urgency_due_this_week(self):
        # Target date 2026-08-14, current date 2026-08-11 -> 3 days left
        now_dt = datetime(2026, 8, 11, 10, 0, 0)
        urg = utils.calculate_deadline_urgency("2026-08-14", is_completed=False, now_dt=now_dt)
        self.assertEqual(urg["status"], "due_this_week")
        self.assertEqual(urg["days_diff"], 3)
        self.assertIn("3d left", urg["badge_text"])
        self.assertEqual(urg["badge_color"], "#d29922")

    def test_calculate_deadline_urgency_due_today(self):
        now_dt = datetime(2026, 8, 14, 10, 0, 0)
        urg = utils.calculate_deadline_urgency("2026-08-14", is_completed=False, now_dt=now_dt)
        self.assertEqual(urg["status"], "due_this_week")
        self.assertEqual(urg["days_diff"], 0)
        self.assertIn("Due Today", urg["badge_text"])

    def test_calculate_deadline_urgency_due_next_week(self):
        now_dt = datetime(2026, 8, 4, 10, 0, 0) # 10 days before Aug 14
        urg = utils.calculate_deadline_urgency("2026-08-14", is_completed=False, now_dt=now_dt)
        self.assertEqual(urg["status"], "due_next_week")
        self.assertEqual(urg["days_diff"], 10)
        self.assertIn("Next Wk", urg["badge_text"])

    def test_calculate_deadline_urgency_future(self):
        now_dt = datetime(2026, 7, 1, 10, 0, 0)
        urg = utils.calculate_deadline_urgency("2026-08-14", is_completed=False, now_dt=now_dt)
        self.assertEqual(urg["status"], "future")
        self.assertGreater(urg["days_diff"], 14)

    def test_sprint_report_generation(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = os.path.join(tmpdir, "test_sprint.db")
            cache = AzureDevOpsCache(db_path)

            # Insert test work items for week-2633
            wis = [
                {
                    "id": 1001,
                    "title": "Implement User Authentication",
                    "type": "User Story",
                    "state": "Active",
                    "assigned_to": "Alice",
                    "iteration_path": "Project\\week-2633",
                    "target_date": "2026-08-14",
                    "changed_date": "2026-08-11T12:00:00Z",
                    "fields": {
                        "System.IterationPath": "Project\\week-2633",
                        "Microsoft.VSTS.Scheduling.TargetDate": "2026-08-14"
                    }
                },
                {
                    "id": 1002,
                    "title": "Fix token expiration crash",
                    "type": "Bug",
                    "state": "Closed",
                    "assigned_to": "Bob",
                    "iteration_path": "Project\\week-2633",
                    "target_date": "2026-08-13",
                    "changed_date": "2026-08-12T14:00:00Z",
                    "fields": {
                        "System.IterationPath": "Project\\week-2633",
                        "Microsoft.VSTS.Scheduling.TargetDate": "2026-08-13"
                    }
                },
                {
                    "id": 1003,
                    "title": "Write unit tests for login",
                    "type": "Task",
                    "state": "Active",
                    "assigned_to": "Alice",
                    "iteration_path": "Project\\week-2633",
                    "target_date": "2026-08-14",
                    "changed_date": "2026-08-11T16:00:00Z",
                    "fields": {
                        "System.IterationPath": "Project\\week-2633",
                        "Microsoft.VSTS.Scheduling.TargetDate": "2026-08-14"
                    }
                }
            ]

            for w in wis:
                cache.save_work_item(
                    wi_id=w["id"],
                    title=w["title"],
                    type_str=w["type"],
                    state=w["state"],
                    assigned_to=w["assigned_to"],
                    changed_date=w["changed_date"],
                    raw_json_obj=w
                )

            md_out = os.path.join(tmpdir, "sprint_report.md")
            csv_out = os.path.join(tmpdir, "sprint_report.csv")

            now_dt = datetime(2026, 8, 12, 10, 0, 0)
            data, md_text = generate_sprint_report.generate_sprint_report(
                cache,
                sprint_name="week-2633",
                output_md=md_out,
                output_csv=csv_out,
                now_dt=now_dt
            )

            self.assertEqual(data["total_items"], 3)
            self.assertEqual(len(data["stories"]), 1)
            self.assertEqual(len(data["bugs"]), 1)
            self.assertEqual(len(data["tasks"]), 1)
            self.assertEqual(data["closed_items"], 1)
            self.assertEqual(data["active_items"], 2)

            self.assertTrue(os.path.exists(md_out))
            self.assertTrue(os.path.exists(csv_out))

            with open(md_out, "r", encoding="utf-8") as f:
                content = f.read()
                self.assertIn("Implement User Authentication", content)
                self.assertIn("Fix token expiration crash", content)
                self.assertIn("Alice", content)
                self.assertIn("Bob", content)

    def test_workload_matrix_overdue_only_filter(self):
        from src.gui.backend import DevOpsBackend
        backend = DevOpsBackend()
        backend._work_items = [
            {
                "id": 1001,
                "title": "Overdue Feature",
                "type": "Requirement",
                "state": "Active",
                "assigned_to": "Alice",
                "iteration_path": "Project\\week-2633",
                "iteration_name": "week-2633",
                "deadline_str": "2026-08-01",
                "urgency_status": "overdue",
            },
            {
                "id": 1002,
                "title": "On-Time Task",
                "type": "Task",
                "state": "Active",
                "assigned_to": "Bob",
                "iteration_path": "Project\\week-2633",
                "iteration_name": "week-2633",
                "deadline_str": "2026-09-30",
                "urgency_status": "future",
            }
        ]

        # 1. Normal (overdue_only=False) -> both Alice and Bob included
        matrix_all = backend.getWorkloadMatrix(overdue_only=False)
        assignees_all = [r["assignee"] for r in matrix_all.get("assignee_rows", [])]
        self.assertIn("Alice", assignees_all)
        self.assertIn("Bob", assignees_all)

        # 2. Filtered (overdue_only=True) -> only Alice included
        matrix_overdue = backend.getWorkloadMatrix(overdue_only=True)
        assignees_overdue = [r["assignee"] for r in matrix_overdue.get("assignee_rows", [])]
        self.assertIn("Alice", assignees_overdue)
        self.assertNotIn("Bob", assignees_overdue)

    def test_get_sprint_taskboard_url_and_open_sprint(self):
        from src.gui.backend import DevOpsBackend
        from unittest.mock import MagicMock, patch
        import devops_helper

        backend = DevOpsBackend()
        devops_helper.AZURE_BASE_URL = "https://tfs.mycompany.com/tfs"
        devops_helper.AZURE_COLLECTION = "DefaultCollection"
        devops_helper.AZURE_PROJECT_ID = "MyProject"

        # 1. URL from sprint name
        url_sprint = backend.get_sprint_taskboard_url("week-2634")
        self.assertEqual(url_sprint, "https://tfs.mycompany.com/tfs/DefaultCollection/MyProject/_sprints/taskboard/week-2634")

        # 2. URL with spaces in sprint name
        url_space = backend.get_sprint_taskboard_url("Sprint 2026.1")
        self.assertEqual(url_space, "https://tfs.mycompany.com/tfs/DefaultCollection/MyProject/_sprints/taskboard/Sprint%202026.1")

        # 3. URL from work item in cache DB
        mock_db = MagicMock()
        mock_db.get_work_item.return_value = {
            "id": 999,
            "title": "Test Task",
            "iteration_path": "MyProject\\Sprint-33",
        }
        backend._cache_db = mock_db
        url_wi = backend.get_sprint_taskboard_url(999)
        self.assertEqual(url_wi, "https://tfs.mycompany.com/tfs/DefaultCollection/MyProject/_sprints/taskboard/Sprint-33")

        # 4. open_sprint_in_browser calls open_url
        with patch.object(backend, "open_url") as mock_open:
            backend.open_sprint_in_browser("week-2634")
            mock_open.assert_called_once_with("https://tfs.mycompany.com/tfs/DefaultCollection/MyProject/_sprints/taskboard/week-2634")


if __name__ == "__main__":
    unittest.main()

