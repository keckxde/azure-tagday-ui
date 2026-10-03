# -*- coding: UTF-8 -*-
"""
Unit tests for the Right Sidebar backend support methods:
- get_file_content
- get_report_content
- parse_csv_to_table
- get_member_workload_details
"""
import os
import sys
import unittest
import tempfile
import json
from unittest.mock import MagicMock, patch

# Ensure src/ is on sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from gui.backend import DevOpsBackend


class TestRightSidebarBackend(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.backend = DevOpsBackend()
        self.backend._reports_dir = self.temp_dir.name

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_get_file_content_existing_file(self):
        test_file = os.path.join(self.temp_dir.name, "SAMPLE.md")
        content = "# Sample Title\n\nThis is a test document with several words.\nLine 3."
        with open(test_file, "w", encoding="utf-8") as f:
            f.write(content)

        res = self.backend.get_file_content(test_file)
        self.assertTrue(res["success"])
        self.assertEqual(res["file_name"], "SAMPLE.md")
        self.assertEqual(res["content"], content)
        self.assertEqual(res["line_count"], 4)
        self.assertGreater(res["word_count"], 5)
        self.assertGreater(res["size_bytes"], 10)
        self.assertTrue(res["modified_at"])

    def test_get_file_content_relative_resolution(self):
        test_file = os.path.join(self.temp_dir.name, "TAGDAY.md")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write("# Tag Day Report")

        res = self.backend.get_file_content("TAGDAY.md")
        self.assertTrue(res["success"])
        self.assertEqual(res["file_name"], "TAGDAY.md")
        self.assertIn("# Tag Day Report", res["content"])

    def test_get_file_content_missing_file(self):
        res = self.backend.get_file_content("non_existent_file.xyz")
        self.assertFalse(res["success"])
        self.assertIn("File not found", res["error"])
        self.assertEqual(res["content"], "")

    def test_parse_csv_to_table(self):
        csv_text = "ID,Name,Role,Status\n1,Alice,Dev,Active\n2,Bob,QA,Closed\n3,Charlie,Lead,Active"
        table = self.backend.parse_csv_to_table(csv_text)
        self.assertEqual(table["headers"], ["ID", "Name", "Role", "Status"])
        self.assertEqual(len(table["rows"]), 3)
        self.assertEqual(table["rows"][0], ["1", "Alice", "Dev", "Active"])
        self.assertEqual(table["total_rows"], 3)
        self.assertEqual(table["total_cols"], 4)

    def test_parse_csv_to_table_empty(self):
        table = self.backend.parse_csv_to_table("")
        self.assertEqual(table["headers"], [])
        self.assertEqual(table["rows"], [])
        self.assertEqual(table["total_rows"], 0)

    def test_get_report_content_tagday(self):
        test_file = os.path.join(self.temp_dir.name, "TAGDAY.md")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write("# Tag Day Release Notes\n\nRepository changes.")

        res = self.backend.get_report_content("tagday")
        self.assertTrue(res["success"])
        self.assertEqual(res["title"], "Tag Day Release Report")
        self.assertEqual(res["format"], "markdown")
        self.assertIn("Tag Day Release Notes", res["content"])

    def test_get_report_content_sprint(self):
        self.backend._work_items = [
            {
                "id": 101,
                "title": "Story A",
                "type": "User Story",
                "state": "Active",
                "assigned_to": "Alice",
                "sprint_week_name": "week-2640",
                "iteration_path": "Project\\week-2640",
                "target_date": "2026-10-04"
            },
            {
                "id": 102,
                "title": "Bug B",
                "type": "Bug",
                "state": "Closed",
                "assigned_to": "Bob",
                "sprint_week_name": "week-2640",
                "iteration_path": "Project\\week-2640",
                "target_date": "2026-10-04"
            }
        ]
        res = self.backend.get_report_content("sprint", "week-2640")
        self.assertTrue(res["success"])
        self.assertEqual(res["title"], "Sprint Report - week-2640")
        self.assertEqual(res["format"], "markdown")
        self.assertIn("#101", res["content"])
        self.assertIn("Story A", res["content"])

    def test_get_report_content_team_motivation(self):
        self.backend.get_team_motivation_markdown_summary = MagicMock(return_value="# Sprint Retro Summary\n- Team XP: 1200")
        res = self.backend.get_report_content("team_motivation")
        self.assertTrue(res["success"])
        self.assertEqual(res["format"], "markdown")
        self.assertIn("Sprint Retro Summary", res["content"])

    def test_get_member_workload_details(self):
        self.backend._work_items = [
            {
                "id": 101,
                "title": "Feature 1",
                "type": "User Story",
                "state": "Active",
                "assigned_to": "Jane Doe",
                "sprint_week_name": "week-2640",
                "iteration_path": "Project\\week-2640",
                "target_date": "2026-10-05",
                "urgency_status": "none"
            },
            {
                "id": 102,
                "title": "Fix Critical Bug",
                "type": "Bug",
                "state": "Closed",
                "assigned_to": "Jane Doe",
                "sprint_week_name": "week-2640",
                "iteration_path": "Project\\week-2640",
                "target_date": "2026-10-02",
                "urgency_status": "none"
            },
            {
                "id": 103,
                "title": "Late Task",
                "type": "Task",
                "state": "Active",
                "assigned_to": "Jane Doe",
                "sprint_week_name": "week-2639",
                "iteration_path": "Project\\week-2639",
                "target_date": "2026-09-25",
                "urgency_status": "overdue"
            },
            {
                "id": 104,
                "title": "Other Member Task",
                "type": "Task",
                "state": "Active",
                "assigned_to": "John Smith",
                "sprint_week_name": "week-2640",
                "iteration_path": "Project\\week-2640"
            }
        ]

        details = self.backend.get_member_workload_details("Jane Doe")
        self.assertEqual(details["assignee"], "Jane Doe")
        self.assertEqual(details["initials"], "JD")
        self.assertEqual(details["total_items"], 3)
        self.assertEqual(details["active_items"], 2)
        self.assertEqual(details["closed_items"], 1)
        self.assertEqual(details["overdue_items"], 1)
        self.assertEqual(details["completion_rate"], 33)

        # Check sprints list
        sprint_names = [s["sprint"] for s in details["sprints"]]
        self.assertIn("week-2640", sprint_names)
        self.assertIn("week-2639", sprint_names)

        # Check items list
        item_ids = [w["id"] for w in details["work_items"]]
        self.assertEqual(len(item_ids), 3)
        self.assertIn(101, item_ids)
        self.assertIn(102, item_ids)
        self.assertIn(103, item_ids)
        self.assertNotIn(104, item_ids)


if __name__ == "__main__":
    unittest.main()
