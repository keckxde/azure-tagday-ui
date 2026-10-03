import unittest
from unittest.mock import MagicMock, patch
import os
import sys
import tempfile
import yaml

py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import utils
from gui.backend import DevOpsBackend, USER_SETTINGS_PATH


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
            with patch("gui.backend.USER_SETTINGS_PATH", test_yaml), patch("src.gui.backend.USER_SETTINGS_PATH", test_yaml, create=True):
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


    def test_task_state_relations_and_distribution(self):
        """Test calculation of not started, active, and closed tasks across matrix and containers."""
        from datetime import date
        today_obj = date.today()
        cy, cw, _ = today_obj.isocalendar()
        curr_sprint = f"week-{str(cy)[-2:]}{cw:02d}"

        all_wis_by_id = {
            100: {
                "id": 100,
                "type": "User Story",
                "title": "Core Feature",
                "state": "Active",
                "assigned_to": "Alice",
                "parent_id": None,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
            101: {
                "id": 101,
                "type": "Task",
                "title": "Task 1 (New)",
                "state": "New",
                "assigned_to": "Alice",
                "parent_id": 100,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
            102: {
                "id": 102,
                "type": "Task",
                "title": "Task 2 (In Progress)",
                "state": "In Progress",
                "assigned_to": "Alice",
                "parent_id": 100,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
            103: {
                "id": 103,
                "type": "Task",
                "title": "Task 3 (Done)",
                "state": "Done",
                "assigned_to": "Alice",
                "parent_id": 100,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
        }

        items_in_cell = [all_wis_by_id[100], all_wis_by_id[101], all_wis_by_id[102], all_wis_by_id[103]]
        containers = self.backend._group_items_into_containers(
            items_in_cell, all_wis_by_id, bug_mode="like_user_story"
        )

        self.assertEqual(len(containers), 1)
        c100 = containers[0]
        self.assertEqual(c100["total_tasks_count"], 3)
        self.assertEqual(c100["tasks_not_started_count"], 1)
        self.assertEqual(c100["tasks_active_count"], 1)
        self.assertEqual(c100["tasks_closed_count"], 1)
        self.assertEqual(c100["progress_percent"], 33)

        # Test matrix overall computation
        self.backend._work_items = list(all_wis_by_id.values())
        matrix = self.backend.getWorkloadMatrix(horizon_weeks=4)

        self.assertEqual(matrix["total_tasks"], 3)
        self.assertEqual(matrix["total_tasks_not_started"], 1)
        self.assertEqual(matrix["total_tasks_active"], 1)
        self.assertEqual(matrix["total_tasks_closed"], 1)

        # Check assignee row
        alice_row = next(r for r in matrix["assignee_rows"] if r["assignee"] == "Alice")
        self.assertEqual(alice_row["stats"]["tasks_not_started"], 1)
        self.assertEqual(alice_row["stats"]["tasks_active"], 1)
        self.assertEqual(alice_row["stats"]["tasks_closed"], 1)

        # Check cell
        cell_curr = next(c for c in alice_row["cells"] if curr_sprint == c["sprint_name"])
        self.assertEqual(cell_curr["tasks_not_started_count"], 1)
        self.assertEqual(cell_curr["tasks_active_count"], 1)
        self.assertEqual(cell_curr["tasks_closed_count"], 1)

    def test_group_item_owner_sees_all_subtasks_including_blockers(self):
        """Test that when User B owns a Story, they see subtasks assigned to User A and User C, with blockers identified."""
        from datetime import date
        curr_y, curr_w, _ = date.today().isocalendar()
        curr_sprint = f"week-{str(curr_y)[-2:]}{curr_w:02d}"

        all_wis_by_id = {
            200: {
                "id": 200,
                "type": "User Story",
                "title": "Core Payment Gateway",
                "state": "Active",
                "assigned_to": "Bob",
                "parent_id": None,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
            201: {
                "id": 201,
                "type": "Task",
                "title": "Write Payment API Client",
                "state": "Closed",
                "assigned_to": "Bob",
                "parent_id": 200,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
            202: {
                "id": 202,
                "type": "Task",
                "title": "Implement Webhook Verification",
                "state": "Active",
                "assigned_to": "Alice",
                "parent_id": 200,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
            203: {
                "id": 203,
                "type": "Task",
                "title": "QA Test Sandbox Webhooks",
                "state": "New",
                "assigned_to": "Charlie",
                "parent_id": 200,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
        }

        self.backend._work_items = list(all_wis_by_id.values())
        matrix = self.backend.getWorkloadMatrix(horizon_weeks=4)

        # Bob's row
        bob_row = next(r for r in matrix["assignee_rows"] if r["assignee"] == "Bob")
        bob_cell = next(c for c in bob_row["cells"] if c["sprint_name"] == curr_sprint)

        # Bob's cell grouped containers should contain Story 200 with all 3 tasks
        self.assertEqual(len(bob_cell["grouped_containers"]), 1)
        c200 = bob_cell["grouped_containers"][0]
        self.assertEqual(c200["id"], 200)
        self.assertEqual(c200["assigned_to"], "Bob")
        self.assertFalse(c200["is_external_parent"])
        self.assertFalse(c200["is_contributor_only"])
        self.assertEqual(len(c200["tasks"]), 3)

        # Verify all tasks are listed and cross-assignees flagged
        task_assignees = {t["id"]: t["assigned_to"] for t in c200["tasks"]}
        self.assertEqual(task_assignees[201], "Bob")
        self.assertEqual(task_assignees[202], "Alice")
        self.assertEqual(task_assignees[203], "Charlie")

        # Verify blocker metrics
        self.assertEqual(c200["total_tasks_count"], 3)
        self.assertEqual(c200["completed_tasks_count"], 1) # 201 is closed
        self.assertEqual(c200["blocking_tasks_count"], 2)  # 202 (Alice, Active) & 203 (Charlie, New)
        self.assertTrue(c200["has_blocking_external_tasks"])
        self.assertIn("Alice", c200["blocking_assignees"])
        self.assertIn("Charlie", c200["blocking_assignees"])

    def test_contributor_only_group_item_isolation(self):
        """Test that a contributing user only gets their own task and the open parent is marked is_contributor_only."""
        from datetime import date
        curr_y, curr_w, _ = date.today().isocalendar()
        curr_sprint = f"week-{str(curr_y)[-2:]}{curr_w:02d}"

        all_wis_by_id = {
            200: {
                "id": 200,
                "type": "User Story",
                "title": "Core Payment Gateway",
                "state": "Active",
                "assigned_to": "Bob",
                "parent_id": None,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
            202: {
                "id": 202,
                "type": "Task",
                "title": "Implement Webhook Verification",
                "state": "Closed",
                "assigned_to": "Alice",
                "parent_id": 200,
                "iteration_path": f"Project\\{curr_sprint}",
                "sprint_week_name": curr_sprint,
            },
        }

        self.backend._work_items = list(all_wis_by_id.values())
        matrix = self.backend.getWorkloadMatrix(horizon_weeks=4)

        # Alice's row
        alice_row = next(r for r in matrix["assignee_rows"] if r["assignee"] == "Alice")
        self.assertEqual(alice_row["stats"]["stories"], 0) # Alice does NOT own Story 200
        self.assertEqual(alice_row["stats"]["tasks"], 1)

        alice_cell = next(c for c in alice_row["cells"] if c["sprint_name"] == curr_sprint)
        self.assertEqual(alice_cell["stories_count"], 0)
        self.assertEqual(alice_cell["tasks_count"], 1)

        # Alice's container for Story 200
        self.assertEqual(len(alice_cell["grouped_containers"]), 1)
        c200_alice = alice_cell["grouped_containers"][0]
        self.assertEqual(c200_alice["id"], 200)
        self.assertTrue(c200_alice["is_external_parent"])
        self.assertTrue(c200_alice["is_contributor_only"])
        self.assertTrue(c200_alice["user_contributions_done"]) # Task 202 is Closed


if __name__ == "__main__":
    unittest.main()

