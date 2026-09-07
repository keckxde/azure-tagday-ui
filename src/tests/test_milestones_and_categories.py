"""
Unit tests for Major Milestones and Categories Management & Workload Explorer Visualization
"""

import os
import shutil
import tempfile
import unittest

from src.azure.azure_db import AzureDevOpsCache
from src.gui.backend import DevOpsBackend


class TestMilestonesAndCategories(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_milestones_cache.db")
        self.cache = AzureDevOpsCache(db_path=self.db_path)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_default_categories_initialized(self):
        categories = self.cache.get_milestone_categories()
        cat_ids = [c["id"] for c in categories]
        self.assertIn("ddqs", cat_ids)
        self.assertIn("qiav", cat_ids)
        self.assertIn("scenario", cat_ids)
        self.assertIn("release", cat_ids)
        self.assertIn("general", cat_ids)

        ddqs = next(c for c in categories if c["id"] == "ddqs")
        self.assertEqual(ddqs["name"], "Internal Process (DDQS)")
        self.assertEqual(ddqs["icon"], "⚙️")

    def test_category_appearance_customization(self):
        # Update appearance of ddqs category
        res = self.cache.save_milestone_category(
            cat_id="ddqs",
            name="DDQS Quality Gate",
            color="#ff5500",
            bg_color="#331100",
            icon="🛡️",
            sort_order=1
        )
        self.assertEqual(res, "ddqs")

        categories = self.cache.get_milestone_categories()
        ddqs = next(c for c in categories if c["id"] == "ddqs")
        self.assertEqual(ddqs["name"], "DDQS Quality Gate")
        self.assertEqual(ddqs["color"], "#ff5500")
        self.assertEqual(ddqs["bg_color"], "#331100")
        self.assertEqual(ddqs["icon"], "🛡️")

    def test_milestone_crud(self):
        # Create a new milestone
        milestone_id = self.cache.save_milestone(
            name="QIAV-01 Audit",
            target_date="2026-08-14",
            category_id="qiav",
            description="External QIAV process compliance signoff"
        )
        self.assertGreater(milestone_id, 0)

        # Retrieve milestones
        milestones = self.cache.get_milestones()
        self.assertEqual(len(milestones), 1)
        m = milestones[0]
        self.assertEqual(m["name"], "QIAV-01 Audit")
        self.assertEqual(m["target_date"], "2026-08-14")
        self.assertEqual(m["category_id"], "qiav")
        self.assertEqual(m["category_name"], "External Process (QIAV)")
        self.assertEqual(m["category_icon"], "🔷")

        # Update milestone
        update_id = self.cache.save_milestone(
            milestone_id=milestone_id,
            name="QIAV-01 Audit Final",
            target_date="2026-08-21",
            category_id="qiav",
            description="Updated date"
        )
        self.assertEqual(update_id, milestone_id)

        milestones_updated = self.cache.get_milestones()
        self.assertEqual(milestones_updated[0]["name"], "QIAV-01 Audit Final")
        self.assertEqual(milestones_updated[0]["target_date"], "2026-08-21")

        # Delete milestone
        del_success = self.cache.delete_milestone(milestone_id)
        self.assertTrue(del_success)
        self.assertEqual(len(self.cache.get_milestones()), 0)

    def test_workload_matrix_milestone_matching(self):
        # Create sample milestones across different sprint weeks
        self.cache.save_milestone(
            name="DDQS Gate 1",
            target_date="2026-08-14",
            category_id="ddqs",
            description="DDQS internal review"
        )
        self.cache.save_milestone(
            name="Scenario Bravo",
            target_date="2026-08-21",
            category_id="scenario",
            description="External scenario demo"
        )

        backend = DevOpsBackend()
        backend._cache_db = self.cache
        backend._work_items = [
            {
                "id": 101,
                "title": "[123] [OI_01] Implement Sensor Driver",
                "type": "Task",
                "state": "Active",
                "assigned_to": "Alice",
                "iteration_path": "Project\\week-2633",
                "iteration_name": "week-2633",
                "target_date": "2026-08-14",
                "remaining_work": 4.0,
                "completed_work": 4.0,
            },
            {
                "id": 102,
                "title": "[123] [SCEN_02] Scenario Integration",
                "type": "Task",
                "state": "Active",
                "assigned_to": "Bob",
                "iteration_path": "Project\\week-2634",
                "iteration_name": "week-2634",
                "target_date": "2026-08-21",
                "remaining_work": 8.0,
                "completed_work": 2.0,
            }
        ]

        matrix = backend.getWorkloadMatrix()

        sprint_cols = matrix.get("sprint_columns", [])
        self.assertGreater(len(sprint_cols), 0)

        # Verify sprint columns have milestones attached
        milestone_sprints = [c for c in sprint_cols if c.get("milestones") and len(c["milestones"]) > 0]
        self.assertGreaterEqual(len(milestone_sprints), 1)

        # Check container items in assignee rows for Alice
        assignee_rows = matrix.get("assignee_rows", [])
        alice_row = next((r for r in assignee_rows if r["assignee"] == "Alice"), None)
        self.assertIsNotNone(alice_row)

        alice_items = []
        for cell in alice_row.get("cells", []):
            alice_items.extend(cell.get("items", []))
            for container in cell.get("containers", []):
                if container.get("milestone_name"):
                    alice_items.append(container)

        matched_ms = [it for it in alice_items if it.get("milestone_name") == "DDQS Gate 1"]
        self.assertTrue(len(matched_ms) > 0)
        self.assertEqual(matched_ms[0]["milestone_category"], "Internal Process (DDQS)")


if __name__ == "__main__":
    unittest.main()
