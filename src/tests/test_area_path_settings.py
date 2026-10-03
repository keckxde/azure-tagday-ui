# -*- coding: UTF-8 -*-
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from PySide6.QtCore import QCoreApplication
from azure.azure_db import AzureDevOpsCache, is_work_item_in_area_path
from azure.azure_info_handler import AzureInfoHandler
from gui.backend import DevOpsBackend


class TestAreaPathSettings(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not QCoreApplication.instance():
            cls.app = QCoreApplication([])
        else:
            cls.app = QCoreApplication.instance()

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmp_dir, "test_areapaths.db")
        self.cache = AzureDevOpsCache(self.db_path)

    def tearDown(self):
        if os.path.exists(self.db_path):
            try:
                os.remove(self.db_path)
            except Exception:
                pass

    # ==========================================
    # 1. Matching Logic Tests
    # ==========================================
    def test_is_work_item_in_area_path_empty_rules(self):
        """When rules are empty, all area paths should match."""
        self.assertTrue(is_work_item_in_area_path("MyProject\\Area1", []))
        self.assertTrue(is_work_item_in_area_path("", []))
        self.assertTrue(is_work_item_in_area_path(None, []))

    def test_is_work_item_in_area_path_exact_match_only(self):
        """include_children=False should only match the exact area path."""
        rules = [{"value": "MyProject\\Area1", "include_children": False}]
        self.assertTrue(is_work_item_in_area_path("MyProject\\Area1", rules))
        self.assertTrue(is_work_item_in_area_path("myproject/area1", rules))  # Case and slash insensitive
        self.assertFalse(is_work_item_in_area_path("MyProject\\Area1\\SubArea", rules))
        self.assertFalse(is_work_item_in_area_path("MyProject\\Area2", rules))

    def test_is_work_item_in_area_path_with_children(self):
        """include_children=True should match exact and child paths."""
        rules = [{"value": "MyProject\\Backend", "include_children": True}]
        self.assertTrue(is_work_item_in_area_path("MyProject\\Backend", rules))
        self.assertTrue(is_work_item_in_area_path("MyProject\\Backend\\API", rules))
        self.assertTrue(is_work_item_in_area_path("MyProject\\Backend\\API\\V2", rules))
        self.assertTrue(is_work_item_in_area_path("myproject/backend/api", rules))
        
        # Should not match sibling or parent or prefix that is not a child path
        self.assertFalse(is_work_item_in_area_path("MyProject\\BackendSpecial", rules))
        self.assertFalse(is_work_item_in_area_path("MyProject", rules))
        self.assertFalse(is_work_item_in_area_path("MyProject\\Frontend", rules))
        self.assertFalse(is_work_item_in_area_path("", rules))
        self.assertFalse(is_work_item_in_area_path(None, rules))

    def test_is_work_item_in_area_path_multiple_rules(self):
        rules = [
            {"value": "MyProject\\Backend", "include_children": True},
            {"value": "MyProject\\Shared\\Common", "include_children": False},
        ]
        self.assertTrue(is_work_item_in_area_path("MyProject\\Backend\\Database", rules))
        self.assertTrue(is_work_item_in_area_path("MyProject\\Shared\\Common", rules))
        self.assertFalse(is_work_item_in_area_path("MyProject\\Shared\\Common\\Sub", rules))
        self.assertFalse(is_work_item_in_area_path("MyProject\\Shared\\Other", rules))

    # ==========================================
    # 2. Database Persistence & Filtering Tests
    # ==========================================
    def test_db_get_set_area_path_settings(self):
        # Default settings
        settings = self.cache.get_area_path_settings()
        self.assertFalse(settings["filter_enabled"])
        self.assertEqual(settings["default_value"], "")
        self.assertEqual(settings["rules"], [])
        self.assertEqual(settings["all_discovered"], [])

        # Update settings
        new_settings = {
            "filter_enabled": True,
            "default_value": "MyProject\\CoreTeam",
            "rules": [
                {"value": "MyProject\\CoreTeam", "include_children": True}
            ],
            "all_discovered": [
                "MyProject\\CoreTeam",
                "MyProject\\CoreTeam\\UI",
                "MyProject\\OtherTeam"
            ]
        }
        self.cache.set_area_path_settings(new_settings)

        loaded = self.cache.get_area_path_settings()
        self.assertTrue(loaded["filter_enabled"])
        self.assertEqual(loaded["default_value"], "MyProject\\CoreTeam")
        self.assertEqual(len(loaded["rules"]), 1)
        self.assertEqual(len(loaded["all_discovered"]), 3)

    def test_db_get_all_work_items_with_area_filter(self):
        # Seed work items
        raw1 = {
            "id": 101,
            "fields": {
                "System.Title": "Core Feature",
                "System.WorkItemType": "Feature",
                "System.State": "Active",
                "System.AreaPath": "MyProject\\CoreTeam\\UI",
            }
        }
        raw2 = {
            "id": 102,
            "fields": {
                "System.Title": "Other Team Bug",
                "System.WorkItemType": "Bug",
                "System.State": "Active",
                "System.AreaPath": "MyProject\\OtherTeam",
            }
        }
        self.cache.save_work_item(101, raw1["fields"]["System.Title"], "Feature", "Active", "", "", raw1)
        self.cache.save_work_item(102, raw2["fields"]["System.Title"], "Bug", "Active", "", "", raw2)

        # Set filter
        self.cache.set_area_path_settings({
            "filter_enabled": True,
            "rules": [{"value": "MyProject\\CoreTeam", "include_children": True}]
        })

        # Unfiltered query
        all_items = self.cache.get_all_work_items(filter_area_paths=False)
        self.assertEqual(len(all_items), 2)

        # Filtered query
        filtered_items = self.cache.get_all_work_items(filter_area_paths=True)
        self.assertEqual(len(filtered_items), 1)
        self.assertEqual(filtered_items[0]["id"], 101)

    # ==========================================
    # 3. Backend Integration & Signals Tests
    # ==========================================
    def test_backend_area_path_properties_and_actions(self):
        backend = DevOpsBackend()
        backend.set_cache_db(self.cache)

        self.assertFalse(backend.areaPathFilterEnabled)
        self.assertEqual(backend.areaPathRules, [])

        # Add rule
        backend.addAreaPathRule("MyProject\\TeamAlpha", True)
        self.assertEqual(len(backend.areaPathRules), 1)
        self.assertEqual(backend.areaPathRules[0]["value"], "MyProject\\TeamAlpha")
        self.assertTrue(backend.areaPathRules[0]["include_children"])

        # Enable filter
        backend.setAreaPathFilterEnabled(True)
        self.assertTrue(backend.areaPathFilterEnabled)

        # Sandbox match test
        match_res = backend.test_area_path_match("MyProject\\TeamAlpha\\SubModule")
        self.assertTrue(match_res["matched"])
        self.assertEqual(match_res["matching_rule"]["value"], "MyProject\\TeamAlpha")

        match_fail = backend.test_area_path_match("MyProject\\TeamBeta")
        self.assertFalse(match_fail["matched"])

        # Remove rule
        backend.removeAreaPathRule("MyProject\\TeamAlpha")
        self.assertEqual(len(backend.areaPathRules), 0)

        # Reset
        backend.reset_area_path_settings()
        self.assertFalse(backend.areaPathFilterEnabled)

    def test_backend_work_item_filtering_during_load(self):
        raw1 = {
            "id": 201,
            "fields": {
                "System.Title": "Frontend Task",
                "System.WorkItemType": "Task",
                "System.State": "Active",
                "System.AreaPath": "MyProject\\Frontend",
            }
        }
        raw2 = {
            "id": 202,
            "fields": {
                "System.Title": "Backend Task",
                "System.WorkItemType": "Task",
                "System.State": "Active",
                "System.AreaPath": "MyProject\\Backend",
            }
        }
        self.cache.save_work_item(201, "Frontend Task", "Task", "Active", "", "", raw1)
        self.cache.save_work_item(202, "Backend Task", "Task", "Active", "", "", raw2)

        # Configure filter to only include Frontend
        self.cache.set_area_path_settings({
            "filter_enabled": True,
            "default_value": "MyProject\\Frontend",
            "rules": [{"value": "MyProject\\Frontend", "include_children": False}],
            "all_discovered": ["MyProject\\Frontend", "MyProject\\Backend"]
        })

        backend = DevOpsBackend()
        backend.set_cache_db(self.cache)

        # Synchronously run load
        backend._load_all_data_sync()

        self.assertEqual(len(backend.workItems), 1)
        self.assertEqual(backend.workItems[0]["id"], 201)
        self.assertEqual(backend.workItemsFilteredByAreaPathCount, 1)
        self.assertEqual(backend.workItemsTotalBeforeAreaFilterCount, 2)

    # ==========================================
    # 4. Azure Info Handler Settings Discovery
    # ==========================================
    def test_azure_info_handler_area_path_discovery(self):
        handler = AzureInfoHandler("http://example.com", "token")
        handler.get_team_field_values = MagicMock(return_value={
            "defaultValue": "ProjectX\\Team1",
            "values": [
                {"value": "ProjectX\\Team1", "includeChildren": True},
                {"value": "ProjectX\\Team1\\SubArea", "includeChildren": False}
            ]
        })
        handler.get_classification_nodes = MagicMock(return_value={
            "name": "ProjectX",
            "children": [
                {
                    "name": "Team1",
                    "children": [{"name": "SubArea"}]
                },
                {
                    "name": "Team2"
                }
            ]
        })

        discovered = handler.get_project_area_path_settings(project_id="ProjectX", team_name="Team1")

        self.assertEqual(discovered["default_value"], "ProjectX\\Team1")
        self.assertEqual(len(discovered["rules"]), 2)
        self.assertTrue(discovered["rules"][0]["include_children"])
        self.assertFalse(discovered["rules"][1]["include_children"])
        self.assertIn("ProjectX\\Team1", discovered["all_discovered"])
        self.assertIn("ProjectX\\Team1\\SubArea", discovered["all_discovered"])
        self.assertIn("ProjectX\\Team2", discovered["all_discovered"])

    # ==========================================
    # 5. Export / Import Settings
    # ==========================================
    def test_export_import_area_path_settings(self):
        original_settings = {
            "filter_enabled": True,
            "default_value": "MyProject\\Engineering",
            "rules": [{"value": "MyProject\\Engineering", "include_children": True}],
            "all_discovered": ["MyProject\\Engineering", "MyProject\\Design"]
        }
        self.cache.set_area_path_settings(original_settings)

        # Export
        exported = self.cache.export_user_settings(include_sections=["area_path_settings"])
        self.assertIn("area_path_settings", exported["settings"])
        self.assertEqual(exported["settings"]["area_path_settings"]["default_value"], "MyProject\\Engineering")
        self.assertTrue(exported["settings"]["area_path_settings"]["filter_enabled"])

        # Reset cache DB
        self.cache.set_area_path_settings({"filter_enabled": False, "rules": [], "default_value": "", "all_discovered": []})
        reset_settings = self.cache.get_area_path_settings()
        self.assertFalse(reset_settings["filter_enabled"])

        # Import
        imported = self.cache.import_user_settings(exported, clear_existing=False, include_sections=["area_path_settings"])
        self.assertIn("area_path_settings", imported.get("imported_sections", []))

        restored_settings = self.cache.get_area_path_settings()
        self.assertTrue(restored_settings["filter_enabled"])
        self.assertEqual(restored_settings["default_value"], "MyProject\\Engineering")
        self.assertEqual(len(restored_settings["rules"]), 1)

    def test_delete_default_area_path_and_filter_only_subareas(self):
        """Deleting default area path allows filtering strictly on specified sub-areas across TagDay UI."""
        from datetime import date
        today_obj = date.today()
        curr_y, curr_w, _ = today_obj.isocalendar()
        curr_sprint = f"week-{str(curr_y)[-2:]}{curr_w:02d}"

        raw_root = {
            "id": 301,
            "fields": {
                "System.Title": "Project Root Work Item",
                "System.WorkItemType": "Task",
                "System.State": "Active",
                "System.AreaPath": "MyProject",
                "System.AssignedTo": {"displayName": "Alice Dev"},
                "System.IterationPath": f"MyProject\\{curr_sprint}"
            }
        }
        raw_sub1 = {
            "id": 302,
            "fields": {
                "System.Title": "Component A Feature",
                "System.WorkItemType": "Task",
                "System.State": "Active",
                "System.AreaPath": "MyProject\\ComponentA",
                "System.AssignedTo": {"displayName": "Alice Dev"},
                "System.IterationPath": f"MyProject\\{curr_sprint}"
            }
        }
        raw_sub2 = {
            "id": 303,
            "fields": {
                "System.Title": "Component B Feature",
                "System.WorkItemType": "Task",
                "System.State": "Active",
                "System.AreaPath": "MyProject\\ComponentB",
                "System.AssignedTo": {"displayName": "Bob Dev"},
                "System.IterationPath": f"MyProject\\{curr_sprint}"
            }
        }
        self.cache.save_work_item(301, "Project Root Work Item", "Task", "Active", "Alice Dev", "2026-10-01", raw_root)
        self.cache.save_work_item(302, "Component A Feature", "Task", "Active", "Alice Dev", "2026-10-01", raw_sub1)
        self.cache.save_work_item(303, "Component B Feature", "Task", "Active", "Bob Dev", "2026-10-01", raw_sub2)

        backend = DevOpsBackend()
        backend.set_cache_db(self.cache)

        # Initially set default area and rule
        backend.setDefaultAreaPath("MyProject")
        backend.addAreaPathRule("MyProject", True)
        self.assertEqual(backend.defaultAreaPath, "MyProject")

        # Delete default area path
        del_ok = backend.deleteDefaultAreaPath()
        self.assertTrue(del_ok)
        self.assertEqual(backend.defaultAreaPath, "")

        # Now configure rule ONLY for ComponentA subarea
        backend.addAreaPathRule("MyProject\\ComponentA", True)
        backend.setAreaPathFilterEnabled(True)

        backend._load_all_data_sync()

        # 1. Work Items Page data
        self.assertEqual(len(backend.workItems), 1)
        self.assertEqual(backend.workItems[0]["id"], 302)
        self.assertEqual(backend.workItems[0]["area_path"], "MyProject\\ComponentA")
        self.assertIn("MyProject\\ComponentA", backend.workItemAreaPaths)

        # 2. Member Workload Details (Right Sidebar & Workload Plan)
        details = backend.get_member_workload_details("Alice Dev")
        self.assertEqual(details["assignee"], "Alice Dev")
        self.assertEqual(details["total_items"], 1)
        self.assertEqual(details["work_items"][0]["id"], 302)

        # Excluded member Bob Dev should have 0 items in workload details
        bob_details = backend.get_member_workload_details("Bob Dev")
        self.assertEqual(bob_details["total_items"], 0)

        # 3. Team Motivation Data
        import team_motivation
        motiv_data = team_motivation.compute_team_motivation_data(
            self.cache,
            timeframe="all_time",
            work_items=backend.workItems
        )
        roster = motiv_data.get("members", [])
        self.assertEqual(len(roster), 1)
        self.assertEqual(roster[0]["name"], "Alice Dev")

    def test_team_motivation_excludes_unmatched_area_paths(self):
        """Verify tasks and bugs outside configured Team Area Filter are not counted in Hall of Fame or Rhythm."""
        import team_motivation

        # Save work items in different area paths
        raw_in_scope = {
            "fields": {
                "System.AreaPath": "MyProject\\AlphaTeam",
                "System.WorkItemType": "Task",
                "System.State": "Closed",
                "System.AssignedTo": {"displayName": "Alpha Worker"},
                "Microsoft.VSTS.Common.ClosedBy": {"displayName": "Alpha Worker"},
                "Microsoft.VSTS.Common.ClosedDate": "2026-10-01T14:30:00Z",
            }
        }
        raw_bug_out_scope = {
            "fields": {
                "System.AreaPath": "MyProject\\OtherTeam",
                "System.WorkItemType": "Bug",
                "System.State": "Resolved",
                "System.AssignedTo": {"displayName": "Beta Worker"},
                "Microsoft.VSTS.Common.ClosedBy": {"displayName": "Beta Worker"},
                "Microsoft.VSTS.Common.ClosedDate": "2026-10-01T15:30:00Z",
            }
        }
        self.cache.save_work_item(401, "Alpha Task Done", "Task", "Closed", "Alpha Worker", "2026-10-01", raw_in_scope)
        self.cache.save_work_item(402, "Beta Bug Resolved", "Bug", "Resolved", "Beta Worker", "2026-10-01", raw_bug_out_scope)

        # Set Area Filter rule ONLY for AlphaTeam
        self.cache.set_area_path_settings({
            "filter_enabled": True,
            "rules": [{"path": "MyProject\\AlphaTeam", "include_sub_areas": True}]
        })

        # Compute motivation data directly from cache_db
        data = team_motivation.compute_team_motivation_data(self.cache, timeframe="all_time")

        members = {m["name"]: m for m in data.get("members", [])}
        self.assertIn("Alpha Worker", members)
        self.assertEqual(members["Alpha Worker"]["tasks_completed"], 1)

        # Beta Worker should NOT have the out-of-scope bug counted
        if "Beta Worker" in members:
            self.assertEqual(members["Beta Worker"]["bugs_resolved"], 0)
            self.assertEqual(members["Beta Worker"]["tasks_completed"], 0)


if __name__ == "__main__":
    unittest.main()

