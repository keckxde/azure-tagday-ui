import unittest
from unittest.mock import MagicMock, patch
import os
import tempfile
import yaml

from src.gui.backend import DevOpsBackend, USER_SETTINGS_PATH


class TestWorkloadParentGrouping(unittest.TestCase):
    def setUp(self):
        self.backend = DevOpsBackend()
        # Mock database and data
        self.backend.tfs_db = MagicMock()

    def test_group_items_like_user_story_mode(self):
        """Test grouping when bug_mode is 'like_user_story' (Bugs act as container cards)."""
        all_wis_by_id = {
            100: {
                "id": 100,
                "type": "User Story",
                "title": "Implement Login Flow",
                "state": "Active",
                "assigned_to": "Alice",
                "parent_id": None,
                "deadline": "2026-09-15",
                "iteration_path": "Sprint 1",
            },
            200: {
                "id": 200,
                "type": "Bug",
                "title": "Fix Memory Leak in Cache",
                "state": "Active",
                "assigned_to": "Alice",
                "parent_id": None,
                "deadline": "2026-09-12",
                "iteration_path": "Sprint 1",
            },
            101: {
                "id": 101,
                "type": "Task",
                "title": "Build Auth Form UI",
                "state": "Closed",
                "assigned_to": "Alice",
                "parent_id": 100,
                "deadline": None,
                "iteration_path": "Sprint 1",
            },
            102: {
                "id": 102,
                "type": "Task",
                "title": "Connect Auth API",
                "state": "Active",
                "assigned_to": "Alice",
                "parent_id": 100,
                "deadline": None,
                "iteration_path": "Sprint 1",
            },
            201: {
                "id": 201,
                "type": "Task",
                "title": "Profile heap allocations",
                "state": "Active",
                "assigned_to": "Alice",
                "parent_id": 200,
                "deadline": None,
                "iteration_path": "Sprint 1",
            },
            301: {
                "id": 301,
                "type": "Task",
                "title": "Standalone Maintenance Task",
                "state": "New",
                "assigned_to": "Alice",
                "parent_id": None,
                "deadline": None,
                "iteration_path": "Sprint 1",
            },
        }

        items_in_cell = [
            all_wis_by_id[100],
            all_wis_by_id[101],
            all_wis_by_id[102],
            all_wis_by_id[200],
            all_wis_by_id[201],
            all_wis_by_id[301],
        ]

        containers = self.backend._group_items_into_containers(
            items_in_cell, all_wis_by_id, bug_mode="like_user_story"
        )

        # We should have 3 containers: Story 100, Bug 200, and Standalone Tasks (0)
        self.assertEqual(len(containers), 3)

        # Check Story 100
        c100 = next(c for c in containers if c["id"] == 100)
        self.assertEqual(c100["type"], "User Story")
        self.assertEqual(c100["title"], "Implement Login Flow")
        self.assertEqual(len(c100["tasks"]), 2)
        self.assertEqual(c100["completed_tasks_count"], 1)
        self.assertEqual(c100["total_tasks_count"], 2)
        self.assertEqual(c100["progress_pct"], 50)

        # Check Bug 200 (treated as container)
        c200 = next(c for c in containers if c["id"] == 200)
        self.assertEqual(c200["type"], "Bug")
        self.assertEqual(c200["title"], "Fix Memory Leak in Cache")
        self.assertEqual(len(c200["tasks"]), 1)
        self.assertEqual(c200["total_tasks_count"], 1)

        # Check Standalone Container
        c_standalone = next(c for c in containers if c["id"] == 0)
        self.assertEqual(c_standalone["type"], "Standalone")
        self.assertEqual(len(c_standalone["tasks"]), 1)
        self.assertEqual(c_standalone["tasks"][0]["id"], 301)

    def test_group_items_like_task_mode(self):
        """Test grouping when bug_mode is 'like_task' (Bugs act as child tasks under User Story/Requirement)."""
        all_wis_by_id = {
            100: {
                "id": 100,
                "type": "Requirement",
                "title": "Security Hardening",
                "state": "Active",
                "assigned_to": "Bob",
                "parent_id": None,
                "deadline": "2026-09-30",
                "iteration_path": "Sprint 1",
            },
            101: {
                "id": 101,
                "type": "Task",
                "title": "Enable TLS 1.3",
                "state": "Closed",
                "assigned_to": "Bob",
                "parent_id": 100,
                "deadline": None,
                "iteration_path": "Sprint 1",
            },
            102: {
                "id": 102,
                "type": "Bug",
                "title": "Cipher suite mismatch on older clients",
                "state": "Active",
                "assigned_to": "Bob",
                "parent_id": 100,
                "deadline": None,
                "iteration_path": "Sprint 1",
            },
            202: {
                "id": 202,
                "type": "Bug",
                "title": "Standalone Bug without parent",
                "state": "New",
                "assigned_to": "Bob",
                "parent_id": None,
                "deadline": None,
                "iteration_path": "Sprint 1",
            },
        }

        items_in_cell = [
            all_wis_by_id[100],
            all_wis_by_id[101],
            all_wis_by_id[102],
            all_wis_by_id[202],
        ]

        containers = self.backend._group_items_into_containers(
            items_in_cell, all_wis_by_id, bug_mode="like_task"
        )

        # Containers: Requirement 100 and Standalone (0)
        self.assertEqual(len(containers), 2)

        c100 = next(c for c in containers if c["id"] == 100)
        self.assertEqual(c100["type"], "Requirement")
        # Both Task 101 and Bug 102 should be child tasks inside container 100
        self.assertEqual(len(c100["tasks"]), 2)
        task_types = [t["type"] for t in c100["tasks"]]
        self.assertIn("Task", task_types)
        self.assertIn("Bug", task_types)

        # Standalone container should contain Bug 202
        c_standalone = next(c for c in containers if c["id"] == 0)
        self.assertEqual(len(c_standalone["tasks"]), 1)
        self.assertEqual(c_standalone["tasks"][0]["id"], 202)

    def test_group_items_external_parent(self):
        """Test grouping when child task is assigned to member but parent story is assigned to someone else or outside sprint."""
        all_wis_by_id = {
            500: {
                "id": 500,
                "type": "User Story",
                "title": "Architecture Redesign",
                "state": "Active",
                "assigned_to": "Carol (Architect)",
                "parent_id": None,
                "deadline": "2026-10-01",
                "iteration_path": "Sprint 2",
            },
            501: {
                "id": 501,
                "type": "Task",
                "title": "Implement Subsystem A",
                "state": "Active",
                "assigned_to": "Dave (Dev)",
                "parent_id": 500,
                "deadline": None,
                "iteration_path": "Sprint 1",
            },
        }

        # Dave only has Task 501 in this cell
        items_in_cell = [all_wis_by_id[501]]

        containers = self.backend._group_items_into_containers(
            items_in_cell, all_wis_by_id, bug_mode="like_user_story"
        )

        self.assertEqual(len(containers), 1)
        c500 = containers[0]
        self.assertEqual(c500["id"], 500)
        self.assertEqual(c500["title"], "Architecture Redesign")
        self.assertEqual(c500["assigned_to"], "Carol (Architect)")
        self.assertTrue(c500["is_external_parent"])
        self.assertEqual(len(c500["tasks"]), 1)
        self.assertEqual(c500["tasks"][0]["id"], 501)

    def test_bug_hierarchy_mode_property_and_persistence(self):
        """Test getting, setting, and persisting bugHierarchyMode."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_yaml = os.path.join(tmpdir, "user_settings.yaml")
            with patch("src.gui.backend.USER_SETTINGS_PATH", test_yaml):
                # Set to like_task
                self.backend.setBugHierarchyMode("like_task")
                self.assertEqual(self.backend.bugHierarchyMode, "like_task")

                # Verify file was written
                self.assertTrue(os.path.exists(test_yaml))
                with open(test_yaml, "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f)
                    self.assertEqual(data.get("bug_behavior"), "like_task")

                # Change to like_user_story
                self.backend.setBugHierarchyMode("like_user_story")
                self.assertEqual(self.backend.bugHierarchyMode, "like_user_story")
                with open(test_yaml, "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f)
                    self.assertEqual(data.get("bug_behavior"), "like_user_story")


if __name__ == "__main__":
    unittest.main()
