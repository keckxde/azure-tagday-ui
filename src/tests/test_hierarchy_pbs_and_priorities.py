import unittest
from src.utils import (
    parse_pbs_tag,
    parse_level3_priority,
    get_work_item_level,
    resolve_work_item_hierarchy,
)


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


if __name__ == "__main__":
    unittest.main()
