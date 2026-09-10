import unittest
from datetime import date
from src.gui.backend import DevOpsBackend
from src.utils import parse_sprint_week, format_sprint_range_label


class TestWorkloadCurrentDateTimeline(unittest.TestCase):
    def setUp(self):
        self.backend = DevOpsBackend()
        self.today = date.today()
        self.curr_y, self.curr_w, self.curr_wd = self.today.isocalendar()
        self.curr_sprint_name = f"week-{str(self.curr_y)[-2:]}{self.curr_w:02d}"

    def test_get_current_date_info(self):
        info = self.backend.getCurrentDateInfo()
        self.assertIsNotNone(info)
        self.assertEqual(info["current_year"], self.curr_y)
        self.assertEqual(info["current_week"], self.curr_w)
        self.assertEqual(info["current_weekday"], self.curr_wd)
        self.assertEqual(info["current_sprint_name"], self.curr_sprint_name)
        self.assertEqual(info["current_date"], self.today.strftime("%Y-%m-%d"))
        self.assertTrue(len(info["current_date_label"]) > 0)
        self.assertTrue(len(info["current_sprint_label"]) > 0)

    def test_get_workload_matrix_current_date_metadata(self):
        matrix = self.backend.getWorkloadMatrix(horizon_weeks=4)
        self.assertIsNotNone(matrix)
        self.assertIn("current_date", matrix)
        self.assertIn("current_date_label", matrix)
        self.assertIn("current_year", matrix)
        self.assertIn("current_week", matrix)
        self.assertIn("current_sprint_name", matrix)
        self.assertIn("has_current_sprint_in_view", matrix)
        self.assertIn("current_sprint_index", matrix)

        self.assertEqual(matrix["current_year"], self.curr_y)
        self.assertEqual(matrix["current_week"], self.curr_w)
        self.assertEqual(matrix["current_sprint_name"], self.curr_sprint_name)

        # Check sprint_columns
        sprint_cols = matrix["sprint_columns"]
        self.assertTrue(len(sprint_cols) > 0)
        found_current = False
        for idx, col in enumerate(sprint_cols):
            self.assertIn("is_current", col)
            self.assertIn("is_past", col)
            self.assertIn("is_future", col)
            self.assertIn("day_progress", col)

            if col["year"] == self.curr_y and col["week"] == self.curr_w:
                self.assertTrue(col["is_current"])
                self.assertFalse(col["is_past"])
                self.assertFalse(col["is_future"])
                self.assertGreaterEqual(col["day_progress"], 0.0)
                self.assertLessEqual(col["day_progress"], 1.0)
                found_current = True
                self.assertEqual(matrix["current_sprint_index"], idx)
                self.assertTrue(matrix["has_current_sprint_in_view"])
            elif (col["year"], col["week"]) < (self.curr_y, self.curr_w):
                self.assertFalse(col["is_current"])
                self.assertTrue(col["is_past"])
                self.assertFalse(col["is_future"])
            else:
                self.assertFalse(col["is_current"])
                self.assertFalse(col["is_past"])
                self.assertTrue(col["is_future"])

        # Check column totals
        col_totals = matrix["column_totals"]
        self.assertEqual(len(col_totals), len(sprint_cols))
        for col_tot in col_totals:
            self.assertIn("is_current", col_tot)
            self.assertIn("is_past", col_tot)
            self.assertIn("is_future", col_tot)

    def test_assignee_row_cells_current_flag(self):
        # Inject sample work items across past, current, and future sprints
        curr_yy = str(self.curr_y)[-2:]
        curr_sprint = f"week-{curr_yy}{self.curr_w:02d}"
        prev_sprint = f"week-{curr_yy}{(self.curr_w - 1):02d}" if self.curr_w > 1 else f"week-{int(curr_yy)-1:02d}52"

        self.backend._work_items = [
            {
                "id": 101,
                "title": "Current Sprint Task",
                "assigned_to": "Alice",
                "type": "Task",
                "state": "Active",
                "iteration_name": curr_sprint,
                "sprint_week_name": curr_sprint,
                "is_task": True,
                "is_story": False,
                "is_bug": False,
                "is_done": False,
                "urgency_status": "normal",
                "_search_text": "alice current sprint task",
            },
            {
                "id": 102,
                "title": "Past Sprint Story",
                "assigned_to": "Alice",
                "type": "User Story",
                "state": "Closed",
                "iteration_name": prev_sprint,
                "sprint_week_name": prev_sprint,
                "is_task": False,
                "is_story": True,
                "is_bug": False,
                "is_done": True,
                "urgency_status": "normal",
                "_search_text": "alice past sprint story",
            }
        ]

        matrix = self.backend.getWorkloadMatrix(horizon_weeks=4)
        rows = matrix["assignee_rows"]
        self.assertTrue(len(rows) > 0)
        alice_row = next((r for r in rows if r["assignee"] == "Alice"), None)
        self.assertIsNotNone(alice_row)

        for cell in alice_row["cells"]:
            self.assertIn("is_current", cell)
            self.assertIn("is_past", cell)
            self.assertIn("is_future", cell)
            if cell["sprint_name"] == curr_sprint:
                self.assertTrue(cell["is_current"])
            elif cell["sprint_name"] == prev_sprint:
                self.assertTrue(cell["is_past"])
                self.assertFalse(cell["is_current"])


if __name__ == "__main__":
    unittest.main()
