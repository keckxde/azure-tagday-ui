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

    def test_backend_work_item_milestone_enrichment_and_inheritance(self):
        self.cache.save_milestone("DDQS-01", "2026-08-14", "ddqs", "Demonstration 1")

        parent_wi = {
            "id": 701,
            "title": "[1.0] Camera Driver Story",
            "type": "User Story",
            "state": "Active",
            "assigned_to": "Alice",
            "tags": "Target:DDQS-01; Camera",
            "raw_tags": "Target:DDQS-01; Camera",
            "parent_id": None,
            "is_iteration_planned": False,
            "iteration_name": "Backlog",
        }

        child_task = {
            "id": 702,
            "title": "Implement USB capture",
            "type": "Task",
            "state": "Active",
            "assigned_to": "Bob",
            "tags": "Dev",
            "raw_tags": "Dev",
            "parent_id": 701,
            "is_iteration_planned": False,
            "iteration_name": "Backlog",
        }

        unrelated_wi = {
            "id": 703,
            "title": "General Docs",
            "type": "Task",
            "state": "Active",
            "assigned_to": "Carol",
            "tags": "Doc",
            "raw_tags": "Doc",
            "parent_id": None,
            "is_iteration_planned": False,
            "iteration_name": "Backlog",
        }

        backend = DevOpsBackend()
        backend._cache_db = self.cache
        backend._work_items = [parent_wi, child_task, unrelated_wi]

        backend._enrich_work_items_with_milestones()

        # Check direct milestone on parent
        self.assertTrue(parent_wi["has_direct_milestone"])
        self.assertTrue(parent_wi["has_milestone"])
        self.assertFalse(parent_wi["is_milestone_inherited"])
        self.assertEqual(parent_wi["effective_milestone_name"], "DDQS-01")
        self.assertEqual(parent_wi["milestone_category"], "Internal Process (DDQS)")
        self.assertFalse(parent_wi["is_iteration_planned"])

        # Check inherited milestone on child
        self.assertFalse(child_task["has_direct_milestone"])
        self.assertTrue(child_task["has_milestone"])
        self.assertTrue(child_task["is_milestone_inherited"])
        self.assertEqual(child_task["effective_milestone_name"], "DDQS-01")
        self.assertEqual(child_task["milestone_category"], "Internal Process (DDQS)")

        # Check unrelated item
        self.assertFalse(unrelated_wi["has_milestone"])
        self.assertEqual(unrelated_wi["effective_milestone_name"], "")

        # Check workItemMilestones property
        ms_list = backend.workItemMilestones
        self.assertIn("DDQS-01", ms_list)

    def test_multi_day_milestone_crud_and_properties(self):
        # Save a multi-day milestone
        m_id = self.cache.save_milestone(
            name="QIAV Audit Workshop",
            target_date="2026-08-10",
            category_id="qiav",
            description="2-week onsite audit and test execution",
            end_date="2026-08-21"
        )
        self.assertGreater(m_id, 0)

        milestones = self.cache.get_milestones()
        self.assertEqual(len(milestones), 1)
        m = milestones[0]
        self.assertEqual(m["name"], "QIAV Audit Workshop")
        self.assertEqual(m["target_date"], "2026-08-10")
        self.assertEqual(m["start_date"], "2026-08-10")
        self.assertEqual(m["end_date"], "2026-08-21")
        self.assertTrue(m["is_multi_day"])
        self.assertEqual(m["duration_days"], 12)
        self.assertEqual(m["date_display"], "2026-08-10 – 2026-08-21")

        # Test inverted dates auto-swapping
        m2_id = self.cache.save_milestone(
            name="Swapped Milestone",
            target_date="2026-09-10",
            category_id="ddqs",
            end_date="2026-09-01"
        )
        milestones = self.cache.get_milestones()
        m2 = next(item for item in milestones if item["id"] == m2_id)
        self.assertEqual(m2["target_date"], "2026-09-01")
        self.assertEqual(m2["end_date"], "2026-09-10")
        self.assertTrue(m2["is_multi_day"])
        self.assertEqual(m2["duration_days"], 10)

        # Test single-day milestone
        m3_id = self.cache.save_milestone(
            name="Single Day Gate",
            target_date="2026-09-15",
            category_id="ddqs",
            end_date=""
        )
        milestones = self.cache.get_milestones()
        m3 = next(item for item in milestones if item["id"] == m3_id)
        self.assertFalse(m3["is_multi_day"])
        self.assertEqual(m3["duration_days"], 1)
        self.assertEqual(m3["date_display"], "2026-09-15")

    def test_multi_day_milestone_range_matching_and_matrix_overlap(self):
        from src import utils

        # Multi-day milestone spanning from Aug 10 to Aug 21 (covers sprint week 33 and 34)
        m_id = self.cache.save_milestone(
            name="Integration Event",
            target_date="2026-08-10",
            category_id="scenario",
            description="System cross-component integration",
            end_date="2026-08-21"
        )

        milestones = self.cache.get_milestones()
        m = milestones[0]

        # Test date range utility
        self.assertTrue(utils.is_date_in_milestone_range("2026-08-10", m))
        self.assertTrue(utils.is_date_in_milestone_range("2026-08-15", m))
        self.assertTrue(utils.is_date_in_milestone_range("2026-08-21", m))
        self.assertFalse(utils.is_date_in_milestone_range("2026-08-09", m))
        self.assertFalse(utils.is_date_in_milestone_range("2026-08-22", m))

        # Test work item matching to multi-day range
        wi_in_range = {
            "id": 801,
            "title": "Middle of event task",
            "target_date": "2026-08-15",
            "tags": "Integration",
        }
        matched = utils.match_work_item_to_milestone(wi_in_range, milestones)
        self.assertIsNotNone(matched)
        self.assertEqual(matched["name"], "Integration Event")

        # Test workload matrix multi-sprint column overlap
        backend = DevOpsBackend()
        backend._cache_db = self.cache
        backend._work_items = [
            {
                "id": 801,
                "title": "Task Week 33",
                "type": "Task",
                "state": "Active",
                "assigned_to": "Alice",
                "iteration_path": "Project\\week-2633",
                "iteration_name": "week-2633",
                "target_date": "2026-08-14",
                "remaining_work": 4.0,
            },
            {
                "id": 802,
                "title": "Task Week 34",
                "type": "Task",
                "state": "Active",
                "assigned_to": "Alice",
                "iteration_path": "Project\\week-2634",
                "iteration_name": "week-2634",
                "target_date": "2026-08-19",
                "remaining_work": 4.0,
            }
        ]

        matrix = backend.getWorkloadMatrix()
        sprint_cols = matrix.get("sprint_columns", [])

        # Find columns for week 33 and week 34
        w33_col = next((c for c in sprint_cols if "2633" in c.get("name", "") or "week-2633" in c.get("name", "") or "33" in c.get("name", "")), None)
        w34_col = next((c for c in sprint_cols if "2634" in c.get("name", "") or "week-2634" in c.get("name", "") or "34" in c.get("name", "")), None)

        if w33_col:
            col_ms_names = [ms["name"] for ms in w33_col.get("milestones", [])]
            self.assertIn("Integration Event", col_ms_names)

        if w34_col:
            col_ms_names = [ms["name"] for ms in w34_col.get("milestones", [])]
            self.assertIn("Integration Event", col_ms_names)

    def test_workload_matrix_filter_by_milestone(self):
        self.cache.save_milestone(
            name="Milestone Alpha",
            target_date="2026-08-14",
            category_id="ddqs",
            description="Alpha milestone"
        )
        self.cache.save_milestone(
            name="Milestone Beta",
            target_date="2026-08-21",
            category_id="scenario",
            description="Beta milestone"
        )

        backend = DevOpsBackend()
        backend._cache_db = self.cache
        backend._work_items = [
            {
                "id": 901,
                "title": "Task Alpha",
                "type": "Task",
                "state": "Active",
                "assigned_to": "Alice",
                "iteration_path": "Project\\week-2633",
                "iteration_name": "week-2633",
                "target_date": "2026-08-14",
                "tags": "Target:Milestone Alpha",
                "remaining_work": 4.0,
            },
            {
                "id": 902,
                "title": "Task Beta",
                "type": "Task",
                "state": "Active",
                "assigned_to": "Bob",
                "iteration_path": "Project\\week-2634",
                "iteration_name": "week-2634",
                "target_date": "2026-08-21",
                "tags": "Target:Milestone Beta",
                "remaining_work": 8.0,
            },
            {
                "id": 903,
                "title": "Task Unplanned",
                "type": "Task",
                "state": "Active",
                "assigned_to": "Charlie",
                "iteration_path": "Project\\week-2635",
                "iteration_name": "week-2635",
                "target_date": "2026-08-28",
                "tags": "General",
                "remaining_work": 2.0,
            }
        ]

        # 1. Filter ALL -> returns all 3 assignees/items
        matrix_all = backend.getWorkloadMatrix(filter_milestone="ALL")
        all_assignees = [r["assignee"] for r in matrix_all.get("assignee_rows", [])]
        self.assertIn("Alice", all_assignees)
        self.assertIn("Bob", all_assignees)
        self.assertIn("Charlie", all_assignees)

        # 2. Filter specific milestone "Milestone Alpha" -> only Alice / Task 901
        matrix_alpha = backend.getWorkloadMatrix(filter_milestone="Milestone Alpha")
        alpha_assignees = [r["assignee"] for r in matrix_alpha.get("assignee_rows", [])]
        self.assertIn("Alice", alpha_assignees)
        self.assertNotIn("Bob", alpha_assignees)
        self.assertNotIn("Charlie", alpha_assignees)

        # 3. Filter PLANNED -> Alice and Bob (both have milestones), Charlie excluded
        matrix_planned = backend.getWorkloadMatrix(filter_milestone="PLANNED")
        planned_assignees = [r["assignee"] for r in matrix_planned.get("assignee_rows", [])]
        self.assertIn("Alice", planned_assignees)
        self.assertIn("Bob", planned_assignees)
        self.assertNotIn("Charlie", planned_assignees)

        # 4. Filter UNPLANNED -> Charlie only
        matrix_unplanned = backend.getWorkloadMatrix(filter_milestone="UNPLANNED")
        unplanned_assignees = [r["assignee"] for r in matrix_unplanned.get("assignee_rows", [])]
        self.assertNotIn("Alice", unplanned_assignees)
        self.assertNotIn("Bob", unplanned_assignees)
        self.assertIn("Charlie", unplanned_assignees)

    def test_milestone_team_and_week_range(self):
        # 1. Create milestone with team and multi-day range
        m_id = self.cache.save_milestone(
            name="DDQS Release Gate",
            target_date="2026-07-20",
            end_date="2026-08-14",
            category_id="ddqs",
            description="Team-wide quality gate",
            team="Chassis Team"
        )
        self.assertGreater(m_id, 0)

        milestones = self.cache.get_milestones()
        self.assertEqual(len(milestones), 1)
        m = milestones[0]
        self.assertEqual(m["name"], "DDQS Release Gate")
        self.assertEqual(m["team"], "Chassis Team")
        self.assertEqual(m["start_date"], "2026-07-20")
        self.assertEqual(m["end_date"], "2026-08-14")
        self.assertTrue(m["is_multi_day"])
        self.assertEqual(m["start_week"], "week-2630")
        self.assertEqual(m["end_week"], "week-2633")
        self.assertEqual(m["week_range"], "week-2630 – week-2633")

    def test_milestones_excel_export_and_import(self):
        # Setup sample milestones
        self.cache.save_milestone(
            name="M1 Gate",
            target_date="2026-07-20",
            end_date="2026-07-24",
            category_id="ddqs",
            description="Phase 1 signoff",
            team="Alpha Team"
        )
        self.cache.save_milestone(
            name="M2 Scenario Demo",
            target_date="2026-08-10",
            end_date="2026-08-21",
            category_id="scenario",
            description="Scenario integration",
            team="Beta Team"
        )

        backend = DevOpsBackend()
        backend._cache_db = self.cache

        export_path = os.path.join(self.test_dir, "milestones_export_test.xlsx")
        res_export = backend.exportMilestonesToExcel(export_path)
        self.assertTrue(res_export["success"])
        self.assertTrue(os.path.exists(export_path))
        self.assertEqual(res_export["count"], 2)

        # Verify Excel content with openpyxl
        import openpyxl
        wb = openpyxl.load_workbook(export_path)
        ws = wb.active
        self.assertEqual(ws.title, "Milestones")
        rows = list(ws.iter_rows(values_only=True))
        self.assertEqual(len(rows), 3)  # Header + 2 rows
        header = rows[0]
        self.assertIn("Milestone Name", header)
        self.assertIn("Team", header)
        self.assertIn("Category", header)
        self.assertIn("Start Date", header)
        self.assertIn("End Date", header)
        self.assertIn("Week Range", header)

        # Import into fresh database
        new_db_path = os.path.join(self.test_dir, "new_import_cache.db")
        new_cache = AzureDevOpsCache(db_path=new_db_path)
        new_backend = DevOpsBackend()
        new_backend._cache_db = new_cache

        res_import = new_backend.importMilestonesFromExcel(export_path)
        self.assertTrue(res_import["success"])
        self.assertEqual(res_import["total"], 2)

        imported_m = new_cache.get_milestones()
        self.assertEqual(len(imported_m), 2)
        m1 = next(item for item in imported_m if item["name"] == "M1 Gate")
        self.assertEqual(m1["team"], "Alpha Team")
        self.assertEqual(m1["start_date"], "2026-07-20")
        self.assertEqual(m1["end_date"], "2026-07-24")

        m2 = next(item for item in imported_m if item["name"] == "M2 Scenario Demo")
        self.assertEqual(m2["team"], "Beta Team")
        self.assertEqual(m2["start_date"], "2026-08-10")
        self.assertEqual(m2["end_date"], "2026-08-21")
        self.assertEqual(m2["week_range"], "week-2633 – week-2634")

    def test_milestone_csv_import_with_week_ranges(self):
        # Create a CSV with week-range schematics
        csv_path = os.path.join(self.test_dir, "milestones_input.csv")
        with open(csv_path, mode="w", encoding="utf-8") as f:
            f.write("Milestone Name,Team,Category,Week Range,Description\n")
            f.write("QIAV Sprint Gateway,Robotics,qiav,week-2630 – week-2633,Gateway review\n")
            f.write("Single Week Gate,Core Dev,release,week-2635,Final verification\n")

        backend = DevOpsBackend()
        backend._cache_db = self.cache

        res_import = backend.importMilestonesFromExcel(csv_path)
        self.assertTrue(res_import["success"])
        self.assertEqual(res_import["total"], 2)

        milestones = self.cache.get_milestones()
        self.assertEqual(len(milestones), 2)

        qiav = next(m for m in milestones if m["name"] == "QIAV Sprint Gateway")
        self.assertEqual(qiav["team"], "Robotics")
        self.assertEqual(qiav["start_date"], "2026-07-20")  # Monday of week-2630
        self.assertEqual(qiav["end_date"], "2026-08-14")    # Friday of week-2633
        self.assertEqual(qiav["week_range"], "week-2630 – week-2633")

        single = next(m for m in milestones if m["name"] == "Single Week Gate")
        self.assertEqual(single["team"], "Core Dev")
        self.assertEqual(single["start_date"], "2026-08-24")  # Monday of week-2635
        self.assertEqual(single["end_date"], "2026-08-28")    # Friday of week-2635
        self.assertEqual(single["week_range"], "week-2635")

    def test_get_available_teams(self):
        backend = DevOpsBackend()
        backend._tfs_team_name = "Core Dev Team"
        backend._work_items = [
            {"id": 1, "team_name": "Alpha Team"},
            {"id": 2, "team_name": "Beta Team"},
            {"id": 3, "team_name": "Alpha Team"},
        ]
        self.cache.save_milestone(
            name="Gamma Milestone",
            target_date="2026-08-10",
            category_id="general",
            team="Gamma Team"
        )
        backend._cache_db = self.cache

        teams = backend.getAvailableTeams()
        self.assertIn("Alpha Team", teams)
        self.assertIn("Beta Team", teams)
        self.assertIn("Core Dev Team", teams)
        self.assertIn("Gamma Team", teams)


if __name__ == "__main__":
    unittest.main()


