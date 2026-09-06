# -*- coding: UTF-8 -*-
import os
import sys
import tempfile
import sqlite3
import json
import unittest
from datetime import datetime, date

# Add py directory to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from azure import AzureDevOpsCache, DateTimeEncoder


class TestAzureDevOpsCache(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmp_dir, "test_tfs_cache.db")
        self.cache = AzureDevOpsCache(self.db_path)

    def tearDown(self):
        # Explicitly delete cache reference to release any SQLite locks
        del self.cache
        import gc
        gc.collect()
        if os.path.exists(self.db_path):
            try:
                os.remove(self.db_path)
            except OSError:
                pass
        if os.path.exists(self.tmp_dir):
            try:
                os.rmdir(self.tmp_dir)
            except OSError:
                pass

    def test_init_db_schema(self):
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
            tables = {row[0] for row in cursor.fetchall()}
            expected_tables = {
                "projects",
                "repositories",
                "branches",
                "tags",
                "submodules",
                "pull_requests",
                "work_items",
                "pipelines",
                "builds",
                "artifacts",
            }
            self.assertTrue(expected_tables.issubset(tables), f"Missing tables: {expected_tables - tables}")

            cursor.execute("SELECT name FROM sqlite_master WHERE type='view'")
            views = {row[0] for row in cursor.fetchall()}
            expected_views = {"v_branches", "v_pull_requests_tagged", "v_builds", "v_artifacts"}
            self.assertTrue(expected_views.issubset(views), f"Missing views: {expected_views - views}")
        finally:
            conn.close()

    def test_project_last_synced(self):
        self.assertIsNone(self.cache.get_project_last_synced("proj-1"))
        self.cache.update_project_last_synced("proj-1", "TEST_PROJECT")
        last_synced = self.cache.get_project_last_synced("proj-1")
        self.assertIsNotNone(last_synced)

    def test_repository_save_and_retrieve(self):
        project_id = "proj-1"
        repo = {
            "id": "repo-uuid-1",
            "name": "test-repo-1",
            "defaultBranch": "refs/heads/master",
            "webUrl": "https://tfs.example.com/_git/test-repo-1",
            "isDisabled": False,
        }
        self.cache.save_repository(project_id, repo, last_push_id=100)

        # Retrieve by id
        found_by_id = self.cache.get_repository("repo-uuid-1")
        self.assertIsNotNone(found_by_id)
        self.assertEqual(found_by_id["name"], "test-repo-1")
        self.assertEqual(found_by_id["default_branch"], "refs/heads/master")
        self.assertEqual(found_by_id["web_url"], "https://tfs.example.com/_git/test-repo-1")

        # Retrieve by name
        found_by_name = self.cache.get_repository("test-repo-1")
        self.assertIsNotNone(found_by_name)
        self.assertEqual(found_by_name["id"], "repo-uuid-1")

        # Check last push id
        self.assertEqual(self.cache.get_last_push_id("repo-uuid-1"), 100)

        # Update last push id
        self.cache.update_repo_last_push_id("repo-uuid-1", 105)
        self.assertEqual(self.cache.get_last_push_id("repo-uuid-1"), 105)

    def test_branches_tags_submodules(self):
        project_id = "proj-1"
        repo_id = "repo-uuid-1"
        self.cache.save_repository(project_id, {"id": repo_id, "name": "test-repo-1"})

        # Save branches
        branches = [{
            "FriendlyName": "master",
            "CommitId": "sha1234",
            "CommitDate": "2026-09-01 12:00:00",
            "Comment": "Initial commit",
            "LatestCommit": {"committer": {"name": "Alice"}},
            "Stats": {"aheadCount": 0, "behindCount": 0}
        }]
        self.cache.save_branches(repo_id, branches)

        # Save tags
        tags = [{
            "FriendlyName": "v1.0.0-unstable-1",
            "objectId": "tag1234567890",
            "CommitDate": "2026-09-01 12:00:00",
            "Comment": "Release v1.0.0",
            "Committer": "Alice",
            "unstable": True
        }]
        self.cache.save_tags(repo_id, tags)

        # Save submodules
        submodules = [{
            "path": "sub/repo",
            "url": "https://tfs.example.com/_git/sub-repo",
            "info": {"commitId": "subsha123"}
        }]
        self.cache.save_submodules(repo_id, submodules)

        # Query cached repository summary
        cached_repo = self.cache.get_cached_repository(repo_id, "test-repo-1")
        self.assertIsNotNone(cached_repo)
        self.assertEqual(len(cached_repo["branches"]), 1)
        self.assertEqual(len(cached_repo["tags"]), 1)
        self.assertEqual(len(cached_repo["submodules"]), 1)

    def test_pull_request_save_and_retrieve(self):
        repo_id = "repo-uuid-1"
        self.cache.save_repository("proj-1", {"id": repo_id, "name": "test-repo-1"})

        pr = {
            "pullRequestId": 27676,
            "title": "Fix memory leak in parser",
            "status": "completed",
            "createdBy": {"displayName": "John Doe", "id": "user-uuid-1"},
            "closedDate": "2025-06-16T12:00:00Z",
            "targetRefName": "refs/heads/master",
            "sourceRefName": "refs/heads/feature/fix-leak",
            "repository": {"id": repo_id, "name": "test-repo-1"},
        }
        # Test save_single_pull_request
        self.cache.save_single_pull_request(pr)

        fetched = self.cache.get_pull_request(27676)
        self.assertIsNotNone(fetched)
        self.assertEqual(fetched["id"], 27676)
        self.assertEqual(fetched["Title"], "Fix memory leak in parser")
        self.assertEqual(fetched["Target"], "refs/heads/master")
        self.assertEqual(fetched["repository"], "test-repo-1")

        # Test batch save_pull_requests
        pr2 = {
            "pullRequestId": 27677,
            "title": "Add logging",
            "status": "active",
            "createdBy": {"displayName": "Jane Smith", "id": "user-uuid-2"},
            "targetRefName": "refs/heads/develop",
        }
        self.cache.save_pull_requests(repo_id, [pr, pr2])
        fetched2 = self.cache.get_pull_request(27677)
        self.assertIsNotNone(fetched2)
        self.assertEqual(fetched2["id"], 27677)

        # Test get_all_prs
        all_prs = self.cache.get_all_prs()
        self.assertEqual(len(all_prs), 2)

    def test_work_item_save_and_retrieve(self):
        wi_id = 12345
        title = "Implement OAuth authentication"
        type_str = "Task"
        state = "Resolved"
        assigned_to = "Alice Bob"
        changed_date = "2025-01-02 09:00:00"
        raw_json_obj = {
            "id": wi_id,
            "fields": {
                "System.Title": title,
                "System.WorkItemType": type_str,
                "System.State": state,
                "System.AssignedTo": {"displayName": assigned_to, "id": "user-uuid-3"},
                "System.ChangedDate": changed_date,
            }
        }
        self.cache.save_work_item(wi_id, title, type_str, state, assigned_to, changed_date, raw_json_obj)

        fetched = self.cache.get_work_item(wi_id)
        self.assertIsNotNone(fetched)
        self.assertEqual(fetched["id"], 12345)
        self.assertEqual(fetched["Title"], title)
        self.assertEqual(fetched["WorkItemType"], type_str)
        self.assertEqual(fetched["State"], state)
        self.assertFalse(fetched["deleted"])
        self.assertEqual(fetched["is_deleted"], 0)

    def test_work_item_mark_deleted(self):
        wi_id = 54321
        title = "Obsolete feature"
        raw_obj = {"id": wi_id, "fields": {"System.Title": title, "System.State": "Active"}}
        self.cache.save_work_item(wi_id, title, "Task", "Active", "Charlie", "2025-01-01", raw_obj)

        # Mark as deleted
        updated = self.cache.mark_work_item_deleted(wi_id)
        self.assertEqual(updated, 1)

        fetched = self.cache.get_work_item(wi_id)
        self.assertIsNotNone(fetched)
        self.assertTrue(fetched["deleted"])
        self.assertEqual(fetched["is_deleted"], 1)
        # Verify title and original fields were preserved
        self.assertEqual(fetched["Title"], title)

        # Mark non-existent work item deleted (placeholder creation)
        new_wi_id = 99999
        created = self.cache.mark_work_item_deleted(new_wi_id)
        self.assertEqual(created, 1)
        placeholder = self.cache.get_work_item(new_wi_id)
        self.assertIsNotNone(placeholder)
        self.assertTrue(placeholder["deleted"])
        self.assertEqual(placeholder["is_deleted"], 1)
        self.assertEqual(placeholder["Title"], "[deleted]")

    def test_get_all_work_items_and_ids(self):
        self.cache.save_work_item(101, "Task 1", "Task", "Active", "Dev 1", "2025-01-01", {"id": 101})
        self.cache.save_work_item(102, "Task 2", "Task", "Closed", "Dev 2", "2025-01-01", {"id": 102})
        self.cache.mark_work_item_deleted(102)

        # IDs
        all_ids = self.cache.get_all_work_item_ids(include_deleted=True)
        self.assertIn(101, all_ids)
        self.assertIn(102, all_ids)

        active_ids = self.cache.get_all_work_item_ids(include_deleted=False)
        self.assertIn(101, active_ids)
        self.assertNotIn(102, active_ids)

        # Items
        all_items = self.cache.get_all_work_items(include_deleted=True)
        item_101 = next(item for item in all_items if item["id"] == 101)
        item_102 = next(item for item in all_items if item["id"] == 102)
        self.assertFalse(item_101["deleted"])
        self.assertTrue(item_102["deleted"])

    def test_get_user_from_pr_and_work_item(self):
        # 1. User in PR createdBy
        pr = {
            "pullRequestId": 30001,
            "title": "User test PR",
            "status": "completed",
            "createdBy": {"displayName": "Alice Wonderland", "id": "usr-alice"},
            "repository": {"id": "repo-uuid-1", "name": "test-repo-1"},
        }
        self.cache.save_single_pull_request(pr)

        user_name = self.cache.get_user("usr-alice")
        self.assertEqual(user_name, "Alice Wonderland")

        # 2. User in Work Item AssignedTo
        raw_wi = {
            "id": 8888,
            "fields": {
                "System.Title": "User task",
                "System.AssignedTo": {"displayName": "Bob Builder", "id": "usr-bob"}
            }
        }
        self.cache.save_work_item(8888, "User task", "Task", "Active", "Bob Builder", "2025-01-01", raw_wi)

        user_name_bob = self.cache.get_user("usr-bob")
        self.assertEqual(user_name_bob, "Bob Builder")

        # 3. Non-existent user
        self.assertIsNone(self.cache.get_user("nonexistent-user-id"))

    def test_pipeline_crud(self):
        project_id = "proj-1"
        pipeline = {
            "id": 42,
            "name": "CI-Build-Pipeline",
            "folder": "\\Pipelines",
            "revision": 3,
            "url": "https://tfs.example.com/pipeline/42",
        }
        self.cache.save_pipeline(project_id, pipeline)

        p = self.cache.get_pipeline(42)
        self.assertIsNotNone(p)
        self.assertEqual(p["name"], "CI-Build-Pipeline")
        self.assertEqual(p["project_id"], project_id)

    def test_build_and_artifact_crud_and_views(self):
        project_id = "proj-1"
        repo_id = "repo-1"

        # Update project and repo
        self.cache.update_project_last_synced(project_id, "TEST_PROJECT")
        self.cache.save_repository(project_id, {"id": repo_id, "name": "test-repo-1"})
        self.cache.save_pipeline(project_id, {"id": 10, "name": "Doc-Build"})

        # Save build
        build = {
            "id": 9999,
            "buildNumber": "20260906.1",
            "status": "completed",
            "result": "succeeded",
            "repository": {"id": repo_id},
            "definition": {"id": 10},
            "sourceBranch": "refs/heads/master",
            "sourceVersion": "commit-sha-123456",
            "queueTime": "2026-09-06 08:00:00",
            "startTime": "2026-09-06 08:01:00",
            "finishTime": "2026-09-06 08:05:00",
            "requestedFor": {"displayName": "Alice"},
            "url": "https://tfs.example.com/build/9999",
        }
        self.cache.save_build(project_id, build)

        b = self.cache.get_build(9999)
        self.assertIsNotNone(b)
        self.assertEqual(b["build_number"], "20260906.1")
        self.assertEqual(b["result"], "succeeded")
        self.assertEqual(b["project_id"], project_id)

        # Save artifacts
        art1 = {
            "id": 1,
            "name": "documentation-site",
            "type": "Container",
            "resource": {
                "properties": {"itemLength": 10485760},
                "downloadUrl": "https://tfs.example.com/artifact/1"
            }
        }
        art2 = {
            "id": 2,
            "name": "test-results",
            "type": "FilePath",
            "resource": {
                "properties": {"itemLength": 524288}
            }
        }
        self.cache.save_artifacts(9999, [art1, art2])

        artifacts = self.cache.get_build_artifacts(9999)
        self.assertEqual(len(artifacts), 2)
        names = {a["name"] for a in artifacts}
        self.assertIn("documentation-site", names)
        self.assertIn("test-results", names)

        # Check size calculation
        doc_art = [a for a in artifacts if a["name"] == "documentation-site"][0]
        self.assertAlmostEqual(doc_art["size_mb"], 10.0, places=1)

        # Verify get_all_builds and get_all_artifacts
        all_builds = self.cache.get_all_builds(project_id=project_id)
        self.assertEqual(len(all_builds), 1)
        self.assertEqual(all_builds[0]["build_id"], 9999)

        all_artifacts = self.cache.get_all_artifacts(project_id=project_id)
        self.assertEqual(len(all_artifacts), 2)

    def test_mark_artifacts_deleted(self):
        project_id = "proj-1"
        self.cache.update_project_last_synced(project_id, "TEST_PROJECT")
        self.cache.save_build(project_id, {"id": 1234, "buildNumber": "1.0"})

        # Save active artifact
        self.cache.save_artifact(1234, {"name": "binary.zip", "size_bytes": 1024})
        arts = self.cache.get_build_artifacts(1234)
        self.assertEqual(len(arts), 1)
        self.assertEqual(arts[0]["is_deleted"], 0)

        # Mark specific artifact deleted
        self.cache.mark_artifact_deleted(1234, "binary.zip")
        arts_all = self.cache.get_build_artifacts(1234, include_deleted=True)
        self.assertEqual(len(arts_all), 1)
        self.assertEqual(arts_all[0]["is_deleted"], 1)
        self.assertIsNotNone(arts_all[0]["deleted_at"])

        # Exclude deleted
        arts_active = self.cache.get_build_artifacts(1234, include_deleted=False)
        self.assertEqual(len(arts_active), 0)

        # Mark non-existent build artifacts deleted (placeholder)
        self.cache.mark_build_artifacts_deleted(5678)
        del_arts = self.cache.get_build_artifacts(5678, include_deleted=True)
        self.assertEqual(len(del_arts), 1)
        self.assertEqual(del_arts[0]["name"], "[deleted]")
        self.assertEqual(del_arts[0]["is_deleted"], 1)

    def test_DateTimeEncoder(self):
        payload = {
            "timestamp": datetime(2026, 9, 6, 12, 0, 0),
            "date": date(2026, 9, 6),
            "text": "sample",
        }
        encoded = json.dumps(payload, cls=DateTimeEncoder)
        decoded = json.loads(encoded)
        self.assertEqual(decoded["timestamp"], "2026-09-06T12:00:00")
        self.assertEqual(decoded["date"], "2026-09-06")
        self.assertEqual(decoded["text"], "sample")


if __name__ == "__main__":
    unittest.main()
