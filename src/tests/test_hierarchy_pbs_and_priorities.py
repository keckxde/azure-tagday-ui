import unittest
from src.utils import (
    parse_pbs_tag,
    parse_level3_priority,
    get_work_item_level,
    resolve_work_item_hierarchy,
)
from src.gui.backend import DevOpsBackend


class TestHierarchyPBSAndPriorities(unittest.TestCase):
    def test_parse_pbs_tag(self):
        """Test parsing [<PBS Number>] <Name> tag syntax."""
        # Valid PBS tags
        self.assertEqual(
            parse_pbs_tag("[PBS-01] Powertrain Subsystem"),
            ("PBS-01", "Powertrain Subsystem")
        )
        self.assertEqual(
            parse_pbs_tag("[1.2.3] Engine Control Unit"),
            ("1.2.3", "Engine Control Unit")
        )
        self.assertEqual(
            parse_pbs_tag("[SYS-A_01] Battery Management"),
            ("SYS-A_01", "Battery Management")
        )

        # Invalid or non-PBS tags
        self.assertEqual(parse_pbs_tag("Powertrain Subsystem without brackets"), ("", "Powertrain Subsystem without brackets"))
        self.assertEqual(parse_pbs_tag(""), ("", ""))
        self.assertEqual(parse_pbs_tag(None), ("", ""))

    def test_parse_level3_priority_focus_types(self):
        """Test Level 3 priority notation [<Type>_<Number>] Name for OI, MP, SCEN, SPEC, PA, CS, DOC."""
        focus_types = ["OI", "MP", "SCEN", "SPEC", "PA", "CS", "DOC"]
        for ptype in focus_types:
            title = f"[{ptype}_101] Implement {ptype} Requirement"
            res = parse_level3_priority(title)
            self.assertTrue(res["is_prio1"], f"Expected {ptype} to be recognized as Prio 1")
            self.assertEqual(res["prio_type"], ptype)
            self.assertEqual(res["prio_tag"], f"[{ptype}_101]")
            self.assertIn(f"Prio 1 [{ptype}_101]", res["prio_badge"])

        # Case-insensitivity test
        res_lower = parse_level3_priority("[oi_42] Sensor issue")
        self.assertTrue(res_lower["is_prio1"])
        self.assertEqual(res_lower["prio_type"], "OI")
        self.assertEqual(res_lower["prio_tag"], "[OI_42]")

    def test_parse_level3_priority_non_focus(self):
        """Non-focus tags or normal titles should return is_prio1=False."""
        self.assertFalse(parse_level3_priority("[CUSTOM_99] Custom feature")["is_prio1"])
        self.assertFalse(parse_level3_priority("Standard User Story without tag")["is_prio1"])
        self.assertFalse(parse_level3_priority("")["is_prio1"])
        self.assertFalse(parse_level3_priority(None)["is_prio1"])

    def test_get_work_item_level(self):
        """Backlog hierarchy levels 1 to 4."""
        self.assertEqual(get_work_item_level("Epic"), 1)
        self.assertEqual(get_work_item_level("Feature"), 2)
        self.assertEqual(get_work_item_level("User Story"), 3)
        self.assertEqual(get_work_item_level("Requirement"), 3)
        self.assertEqual(get_work_item_level("Product Backlog Item"), 3)
        self.assertEqual(get_work_item_level("Task"), 4)

        # Bug handled like user story (Level 3) vs bug handled like task (Level 4)
        self.assertEqual(get_work_item_level("Bug", bug_hierarchy_mode="like_user_story"), 3)
        self.assertEqual(get_work_item_level("Bug", bug_hierarchy_mode="like_task"), 4)

    def test_resolve_work_item_hierarchy_grouped(self):
        """A work item with valid Level 1 and Level 2 PBS parents is marked as grouped."""
        items = [
            {"id": 10, "type": "Epic", "title": "[PBS-01] Chassis System", "parent_id": None},
            {"id": 20, "type": "Feature", "title": "[1.1] Braking Subsystem", "parent_id": 10},
            {"id": 30, "type": "User Story", "title": "[OI_55] Caliper Calibration", "parent_id": 20},
            {"id": 40, "type": "Task", "title": "Run bench test", "parent_id": 30},
        ]
        items_map = {item["id"]: item for item in items}

        task_res = resolve_work_item_hierarchy(items_map[40], items_map, bug_hierarchy_mode="like_user_story")
        self.assertEqual(task_res["level"], 4)
        self.assertEqual(task_res["level1_id"], 10)
        self.assertEqual(task_res["level1_display"], "[PBS-01] Chassis System")
        self.assertEqual(task_res["level2_id"], 20)
        self.assertEqual(task_res["level2_display"], "[1.1] Braking Subsystem")
        self.assertTrue(task_res["is_grouped"])
        self.assertEqual(task_res["grouping_status"], "grouped")
        # Level 3 story priority should propagate to task
        self.assertTrue(task_res["is_prio1"])
        self.assertEqual(task_res["prio_type"], "OI")

        story_res = resolve_work_item_hierarchy(items_map[30], items_map, bug_hierarchy_mode="like_user_story")
        self.assertEqual(story_res["level"], 3)
        self.assertTrue(story_res["is_grouped"])
        self.assertTrue(story_res["is_prio1"])
        self.assertEqual(story_res["prio_tag"], "[OI_55]")

    def test_resolve_work_item_hierarchy_ungrouped(self):
        """Items without proper PBS Level 1 and Level 2 parents are marked as ungrouped."""
        items = [
            {"id": 100, "type": "Feature", "title": "Orphan Feature Without PBS", "parent_id": None},
            {"id": 101, "type": "User Story", "title": "Orphan Story", "parent_id": 100},
            {"id": 102, "type": "Task", "title": "Orphan Task", "parent_id": 101},
        ]
        items_map = {item["id"]: item for item in items}

        task_res = resolve_work_item_hierarchy(items_map[102], items_map, bug_hierarchy_mode="like_user_story")
        self.assertFalse(task_res["is_grouped"])
        self.assertEqual(task_res["grouping_status"], "ungrouped")
        self.assertFalse(task_res["is_prio1"])

    def test_get_workload_matrix_filtering(self):
        """Test backend.getWorkloadMatrix filtering with L1, L2, prio1, and hide_closed."""
        from src.gui.backend import DevOpsBackend
        import tempfile
        import sqlite3
        from unittest.mock import MagicMock

        backend = DevOpsBackend()
        # Mock database work items
        mock_items = [
            {
                "id": 1,
                "type": "Task",
                "title": "Task In Chassis",
                "assigned_to": "Alice",
                "iteration_path": "week-2610",
                "state": "Active",
                "parent_id": 30,
            },
            {
                "id": 2,
                "type": "Task",
                "title": "Closed Task In Powertrain",
                "assigned_to": "Bob",
                "iteration_path": "week-2610",
                "state": "Closed",
                "parent_id": 40,
            },
            {
                "id": 10,
                "type": "Epic",
                "title": "[PBS-01] Chassis System",
                "parent_id": None,
            },
            {
                "id": 11,
                "type": "Epic",
                "title": "[PBS-02] Powertrain System",
                "parent_id": None,
            },
            {
                "id": 20,
                "type": "Feature",
                "title": "[1.1] Braking Subsystem",
                "parent_id": 10,
            },
            {
                "id": 21,
                "type": "Feature",
                "title": "[2.1] Motor Subsystem",
                "parent_id": 11,
            },
            {
                "id": 30,
                "type": "User Story",
                "title": "[OI_10] Urgent Brake Calibration",
                "parent_id": 20,
            },
            {
                "id": 40,
                "type": "User Story",
                "title": "Regular Motor Test",
                "parent_id": 21,
            },
            {
                "id": 5,
                "type": "Task",
                "title": "Unparented Task Without PBS",
                "assigned_to": "Charlie",
                "iteration_path": "week-2610",
                "state": "Active",
                "parent_id": None,
            },
            {
                "id": 6,
                "type": "Task",
                "title": "Task Under Plain Feature Without PBS",
                "assigned_to": "Dana",
                "iteration_path": "week-2610",
                "state": "Active",
                "parent_id": 50,
            },
            {
                "id": 50,
                "type": "Feature",
                "title": "Plain Feature Without PBS Tag",
                "parent_id": None,
            },
        ]
        
        all_wis_map = {w["id"]: w for w in mock_items}
        for item in mock_items:
            h_info = resolve_work_item_hierarchy(item, all_wis_map, bug_hierarchy_mode="like_user_story")
            item.update(h_info)

        backend._work_items = mock_items

        # 1. No filters (hide_closed=False) -> 4 tasks total (1, 2, 5, 6)
        matrix_all = backend.getWorkloadMatrix(4, "ALL", "ALL", False, False, False, "")
        self.assertEqual(matrix_all["total_tasks"], 4)

        # 2. Filter by Level 1 text 'Chassis'
        matrix_l1 = backend.getWorkloadMatrix(4, "Chassis", "ALL", False, False, False, "")
        self.assertEqual(matrix_l1["total_tasks"], 1)
        self.assertEqual(matrix_l1["assignee_rows"][0]["assignee"], "Alice")

        # 3. Filter by Level 1 'PBS-02' (Powertrain) but hide_closed=True -> should be 0 tasks
        matrix_l1_closed = backend.getWorkloadMatrix(4, "PBS-02", "ALL", False, False, True, "")
        self.assertEqual(matrix_l1_closed["total_tasks"], 0)

        # 4. Filter by Prio 1 focus only -> only Task 1 has parent story [OI_10]
        matrix_prio1 = backend.getWorkloadMatrix(4, "ALL", "ALL", True, False, False, "")
        self.assertEqual(matrix_prio1["total_tasks"], 1)
        self.assertEqual(matrix_prio1["assignee_rows"][0]["assignee"], "Alice")

        # 5. Filter by Level 1 WITHOUT [<NR>] SYNTAX -> tasks 5 and 6 don't have Level 1 PBS
        matrix_l1_no_pbs = backend.getWorkloadMatrix(4, "[ WITHOUT [<NR>] SYNTAX ]", "ALL", False, False, False, "")
        self.assertEqual(matrix_l1_no_pbs["total_tasks"], 2)
        assignees = {r["assignee"] for r in matrix_l1_no_pbs["assignee_rows"]}
        self.assertIn("Charlie", assignees)
        self.assertIn("Dana", assignees)

        # 6. Filter by Level 2 WITHOUT [<NR>] SYNTAX -> tasks 5 and 6 don't have Level 2 PBS
        matrix_l2_no_pbs = backend.getWorkloadMatrix(4, "ALL", "WITHOUT [<NR>] SYNTAX", False, False, False, "")
        self.assertEqual(matrix_l2_no_pbs["total_tasks"], 2)

    def test_complying_pbs_items_ordered_first(self):
        """Test that Level 1 & 2 filter lists order items complying with [<NR>] <Name> before non-complying items."""
        backend = DevOpsBackend()
        backend._work_items = [
            {"id": 1, "level1_display": "Zebra Non PBS", "level2_display": "Alpha Non PBS", "is_grouped": False},
            {"id": 2, "level1_display": "[20] Powertrain", "level2_display": "[200] Battery", "is_grouped": True},
            {"id": 3, "level1_display": "[10] Chassis", "level2_display": "[100] Suspension", "is_grouped": True},
            {"id": 4, "level1_display": "Beta Non PBS", "level2_display": "Gamma Non PBS", "is_grouped": False},
        ]

        l1_list = backend.workItemLevel1List
        self.assertEqual(l1_list[0], "[10] Chassis")
        self.assertEqual(l1_list[1], "[20] Powertrain")
        self.assertEqual(l1_list[2], "Beta Non PBS")
        self.assertEqual(l1_list[3], "Zebra Non PBS")

        l2_list = backend.workItemLevel2List
        self.assertEqual(l2_list[0], "[100] Suspension")
        self.assertEqual(l2_list[1], "[200] Battery")
        self.assertEqual(l2_list[2], "Alpha Non PBS")
        self.assertEqual(l2_list[3], "Gamma Non PBS")


if __name__ == "__main__":
    unittest.main()



