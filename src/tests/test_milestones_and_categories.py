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

    def test_extract_target_milestone_tags(self):
        from src import utils
        tags_str = "Backend; Target:DDQS-01; Prio1; target: QIAV-02 ; Target:Release_1.0"
        extracted = utils.extract_target_milestone_tags(tags_str)
        self.assertEqual(extracted, ["DDQS-01", "QIAV-02", "Release_1.0"])

        # Test list format
        tags_list = ["Feature", "Target:Scenario_Alpha", "bug"]
        self.assertEqual(utils.extract_target_milestone_tags(tags_list), ["Scenario_Alpha"])

        # Test empty
        self.assertEqual(utils.extract_target_milestone_tags(""), [])
        self.assertEqual(utils.extract_target_milestone_tags(None), [])

    def test_match_work_item_to_milestone_tag_precedence(self):
        from src import utils
        milestones = [
            {"id": 1, "name": "DDQS-01", "target_date": "2026-08-14", "category_name": "DDQS"},
            {"id": 2, "name": "QIAV-02", "target_date": "2026-08-21", "category_name": "QIAV"},
        ]

        # Work item with Target:QIAV-02 tag, even if target_date is 2026-08-14 (matching DDQS-01 date)
        wi_with_tag = {
            "id": 201,
            "target_date": "2026-08-14",
            "tags": "Prio1; Target:QIAV-02",
        }
        matched = utils.match_work_item_to_milestone(wi_with_tag, milestones)
        self.assertIsNotNone(matched)
        self.assertEqual(matched["id"], 2)
        self.assertEqual(matched["name"], "QIAV-02")

        # Work item without tag, should fallback to date
        wi_no_tag = {
            "id": 202,
            "target_date": "2026-08-14",
            "tags": "Prio1; Backend",
        }
        matched_date = utils.match_work_item_to_milestone(wi_no_tag, milestones)
        self.assertIsNotNone(matched_date)
        self.assertEqual(matched_date["id"], 1)

    def test_discover_and_prefill_milestones_from_work_items(self):
        import json

        # Save work items in DB with Target tags
        wi1 = {
            "id": 501,
            "title": "Setup Pipeline",
            "type": "Task",
            "fields": {
                "System.Tags": "Target:DDQS-01; Infra",
                "Microsoft.VSTS.Scheduling.TargetDate": "2026-08-14T00:00:00Z"
            }
        }
        wi2 = {
            "id": 502,
            "title": "QIAV Audit Prep",
            "type": "Task",
            "fields": {
                "System.Tags": "Target:QIAV-GateA",
                "Microsoft.VSTS.Scheduling.TargetDate": "2026-08-28T00:00:00Z"
            }
        }
        wi3 = {
            "id": 503,
            "title": "Release Candidate",
            "type": "Task",
            "fields": {
                "System.Tags": "Target:v2.0_Release",
                "System.TargetDate": "2026-09-04"
            }
        }
        self.cache.save_work_item(501, wi1["title"], wi1["type"], "Active", "Alice", "2026-08-01", wi1)
        self.cache.save_work_item(502, wi2["title"], wi2["type"], "Active", "Bob", "2026-08-01", wi2)
        self.cache.save_work_item(503, wi3["title"], wi3["type"], "Active", "Charlie", "2026-08-01", wi3)

        # Pre-fill
        new_ms = self.cache.discover_and_prefill_milestones_from_work_items()
        self.assertEqual(len(new_ms), 3)

        all_ms = self.cache.get_milestones()
        ms_names = [m["name"] for m in all_ms]
        self.assertIn("DDQS-01", ms_names)
        self.assertIn("QIAV-GateA", ms_names)
        self.assertIn("v2.0_Release", ms_names)

        ddqs_m = next(m for m in all_ms if m["name"] == "DDQS-01")
        self.assertEqual(ddqs_m["category_id"], "ddqs")
        self.assertEqual(ddqs_m["target_date"], "2026-08-14")

        qiav_m = next(m for m in all_ms if m["name"] == "QIAV-GateA")
        self.assertEqual(qiav_m["category_id"], "qiav")
        self.assertEqual(qiav_m["target_date"], "2026-08-28")

        rel_m = next(m for m in all_ms if m["name"] == "v2.0_Release")
        self.assertEqual(rel_m["category_id"], "release")
        self.assertEqual(rel_m["target_date"], "2026-09-04")

        # Running again should not create duplicates
        again_ms = self.cache.discover_and_prefill_milestones_from_work_items()
        self.assertEqual(len(again_ms), 0)

    def test_backend_prefill_and_matrix_tag_matching(self):
        wi = {
            "id": 601,
            "title": "Camera Calibration Task",
            "type": "Task",
            "fields": {
                "System.Tags": "Target:DDQS-02; Camera",
                "Microsoft.VSTS.Scheduling.TargetDate": "2026-08-14"
            }
        }
        self.cache.save_work_item(601, wi["title"], wi["type"], "Active", "David", "2026-08-01", wi)

        backend = DevOpsBackend()
        backend._cache_db = self.cache

        added = backend.prefillMilestonesFromWorkItems()
        self.assertEqual(added, 1)

        milestones = backend.get_milestones()
        self.assertEqual(len(milestones), 1)
        self.assertEqual(milestones[0]["name"], "DDQS-02")


if __name__ == "__main__":
    unittest.main()
