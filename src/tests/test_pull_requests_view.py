# -*- coding: UTF-8 -*-
import os
import sys
import unittest
import tempfile
import sqlite3
import json

# Add scripts/py to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from unittest.mock import MagicMock, patch
from azure import AzureDevOpsCache, AzureInfoHandler


class TestPullRequestsViewData(unittest.TestCase):
    """
    Tests for Pull Requests extraction, repository listing, and sorting.
    """

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmp_dir, "test_pr_cache.db")
        self.cache = AzureDevOpsCache(self.db_path)

        # Populate sample repositories and pull requests
        repo1_id = "repo-uuid-1"
        repo2_id = "repo-uuid-2"

        self.cache.save_repository("TEST_PROJECT", {
            "id": repo1_id,
            "name": "repo-alpha",
            "defaultBranch": "refs/heads/master",
            "webUrl": "https://tfs.example.com/repo-alpha",
            "isDisabled": False,
        })

        self.cache.save_repository("TEST_PROJECT", {
            "id": repo2_id,
            "name": "cmake-scripts",
            "defaultBranch": "refs/heads/master",
            "webUrl": "https://tfs.example.com/cmake-scripts",
            "isDisabled": False,
        })

        with self.cache._connection() as conn:
            # PR 1 (older, completed)
            conn.execute("""
                INSERT INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, status_str, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                1001, repo1_id, "[OI_170] Old Feature PR", "completed", "refs/heads/dev", "refs/heads/feat/old",
                "Alice", "Bob", "2026-08-01 10:00:00", "Completed",
                json.dumps({"pullRequestId": 1001, "creationDate": "2026-08-01T09:00:00Z", "description": "Fixes #145000"})
            ))

            # PR 2 (newer, completed)
            conn.execute("""
                INSERT INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, status_str, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                1002, repo1_id, "[OI_171] New Feature PR", "completed", "refs/heads/dev", "refs/heads/feat/new",
                "Charlie", "Bob", "2026-09-06 12:00:00", "Completed",
                json.dumps({"pullRequestId": 1002, "creationDate": "2026-09-06T11:00:00Z", "description": "Fixes #145001"})
            ))

            # PR 3 (different repo, active)
            conn.execute("""
                INSERT INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, status_str, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                1003, repo2_id, "In-flight cmake PR", "active", "refs/heads/main", "refs/heads/feat/cmake",
                "David", "", "", "Active",
                json.dumps({"pullRequestId": 1003, "creationDate": "2026-09-06T15:00:00Z", "description": "Work in progress"})
            ))

    def tearDown(self):
        if os.path.exists(self.db_path):
            try:
                os.remove(self.db_path)
            except Exception:
                pass
        try:
            os.rmdir(self.tmp_dir)
        except Exception:
            pass

    def test_get_all_prs_columns_and_ordering(self):
        prs = self.cache.get_all_prs()
        self.assertEqual(len(prs), 3)

        # Check fields are present
        pr = prs[0]
        self.assertIn("repo_name", pr)
        self.assertIn("target_branch", pr)
        self.assertIn("source_branch", pr)
        self.assertIn("created_by", pr)
        self.assertIn("closed_by", pr)
        self.assertIn("closed_date", pr)
        self.assertIn("raw_json", pr)

        # Completed PRs ordered by closed_date DESC: 1002 (Sept 6) before 1001 (Aug 1)
        completed = [p for p in prs if p["status"] == "completed"]
        self.assertEqual(completed[0]["pr_id"], 1002)
        self.assertEqual(completed[1]["pr_id"], 1001)

    def test_distinct_repositories(self):
        prs = self.cache.get_all_prs()
        repos = sorted(list(set(p["repo_name"] for p in prs)))
        self.assertEqual(repos, ["cmake-scripts", "repo-alpha"])

    def test_pr_tag_association(self):
        # Insert a tag matching PR 1001's merge commit
        merge_commit_1001 = "a1b2c3d4e5f67890"
        with self.cache._connection() as conn:
            conn.execute("""
                UPDATE pull_requests
                SET raw_json = ?
                WHERE id = 1001
            """, (json.dumps({
                "pullRequestId": 1001,
                "creationDate": "2026-08-01T09:00:00Z",
                "description": "Fixes #145000",
                "lastMergeCommit": {"commitId": merge_commit_1001}
            }),))
            conn.execute("""
                INSERT INTO tags (repo_id, name, commit_id, commit_date, committer_name, comment, is_stable, is_unstable, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, ("repo-uuid-1", "v2026.1-rc1", merge_commit_1001, "2026-08-02 12:00:00", "DevOps", "Release 1", 1, 0, json.dumps({
                "objectId": merge_commit_1001,
                "name": "refs/tags/v2026.1-rc1"
            })))

        prs = self.cache.get_all_prs()
        pr1001 = next(p for p in prs if p["pr_id"] == 1001)
        self.assertEqual(pr1001.get("direct_tag_name"), "v2026.1-rc1")

        pr1002 = next(p for p in prs if p["pr_id"] == 1002)
        self.assertIsNone(pr1002.get("direct_tag_name"))

    def test_process_pushes_and_prs_syncs_unclosed_active_prs(self):
        """Test that _process_pushes_and_prs syncs active (unclosed) pull requests along with merged push PRs."""
        handler = AzureInfoHandler("https://tfs.example.com/tfs", "fake-token")

        # Mock get_pushes and push detail with one merged PR (ID 5001)
        handler.get_pushes = MagicMock(return_value=[{"pushId": 101}])
        handler.get_push_detail = MagicMock(return_value={
            "refUpdates": [{"name": "refs/pull/5001/merge"}]
        })

        # Mock get_pull_requests returning active unclosed PR (ID 5002)
        handler.get_pull_requests = MagicMock(return_value=[
            {"pullRequestId": 5002, "title": "Active Unclosed PR", "status": "active"}
        ])

        # Mock get_pull_request details for both PRs
        def mock_get_pr(pr_id):
            if str(pr_id) == "5001":
                return {
                    "pullRequestId": 5001,
                    "title": "Merged PR",
                    "status": "completed",
                    "targetRefName": "refs/heads/dev",
                    "sourceRefName": "refs/heads/feat1",
                    "creationDate": "2026-09-01T10:00:00Z",
                    "closedDate": "2026-09-02T12:00:00Z",
                    "createdBy": {"displayName": "Alice"},
                }
            elif str(pr_id) == "5002":
                return {
                    "pullRequestId": 5002,
                    "title": "Active Unclosed PR",
                    "status": "active",
                    "targetRefName": "refs/heads/dev",
                    "sourceRefName": "refs/heads/feat2",
                    "creationDate": "2026-09-07T14:00:00Z",
                    "closedDate": None,
                    "createdBy": {"displayName": "Bob"},
                }
            return {}

        handler.get_pull_request = MagicMock(side_effect=mock_get_pr)

        repo = {"id": "repo-test-1", "name": "test-repo"}
        dev_prs, stable_prs = handler._process_pushes_and_prs("proj-1", repo)

        pr_ids = [p["pullRequestId"] for p in (dev_prs + stable_prs)]
        self.assertIn(5001, pr_ids, "Merged PR from push history should be synced")
        self.assertIn(5002, pr_ids, "Active unclosed PR should be synced")

        # Verify active PR has OPN statusStr
        active_pr = next(p for p in (dev_prs + stable_prs) if p["pullRequestId"] == 5002)
        self.assertTrue(active_pr["statusStr"].startswith("OPN"))

    def test_normalize_pr_status(self):
        """Tests that normalize_pr_status handles all TFS integer and string variations."""
        from utils import normalize_pr_status
        self.assertEqual(normalize_pr_status(1), "active")
        self.assertEqual(normalize_pr_status("1"), "active")
        self.assertEqual(normalize_pr_status("active"), "active")
        self.assertEqual(normalize_pr_status("Active"), "active")
        self.assertEqual(normalize_pr_status("open"), "active")

        self.assertEqual(normalize_pr_status(3), "completed")
        self.assertEqual(normalize_pr_status("3"), "completed")
        self.assertEqual(normalize_pr_status("completed"), "completed")
        self.assertEqual(normalize_pr_status("Completed"), "completed")
        self.assertEqual(normalize_pr_status("closed"), "completed")
        self.assertEqual(normalize_pr_status("merged"), "completed")

        self.assertEqual(normalize_pr_status(2), "abandoned")
        self.assertEqual(normalize_pr_status("2"), "abandoned")
        self.assertEqual(normalize_pr_status("abandoned"), "abandoned")
        self.assertEqual(normalize_pr_status("Abandoned"), "abandoned")
        self.assertEqual(normalize_pr_status("rejected"), "abandoned")
        self.assertEqual(normalize_pr_status(None), "unknown")

    def test_active_pr_reconciled_when_closed_in_tfs(self):
        """
        Tests that when a PR was cached as active in the local DB,
        and subsequently closed or abandoned in TFS, syncing updates
        its state to 'completed' / 'abandoned' in both the DB and UI backend.
        """
        # 1. Setup DB cache with a repository and an active PR
        db_fd, db_path = tempfile.mkstemp(suffix=".db")
        os.close(db_fd)
        try:
            cache_db = AzureDevOpsCache(db_path)
            repo = {"id": "repo-100", "name": "core-engine"}
            cache_db.save_repository("proj-1", repo, last_push_id=1234)

            # Initially active PR in DB
            initial_active_pr = {
                "pullRequestId": 9001,
                "title": "Add Turbo Engine",
                "status": "active",
                "targetRefName": "refs/heads/dev",
                "sourceRefName": "refs/heads/feature-turbo",
                "createdBy": {"displayName": "Alice"},
                "creationDateStr": "2026-09-01 10:00:00",
                "closedDateStr": "",
                "statusStr": "OPN 2026-09-01 10:00:00",
                "repository": {"id": "repo-100"}
            }
            cache_db.save_pull_requests("repo-100", [initial_active_pr])

            # Verify it is recorded as active
            active_prs_before = cache_db.get_active_pull_requests("repo-100")
            self.assertEqual(len(active_prs_before), 1)
            self.assertEqual(active_prs_before[0]["status"], "active")

            # 2. Mock TFS handler where PR 9001 is now COMPLETED in TFS
            handler = AzureInfoHandler("https://tfs.company.com/tfs/DefaultCollection", "dummy_pat")
            handler.get_pushes = MagicMock(return_value=[{"pushId": 1234}])  # Push ID unchanged
            handler.get_pull_requests = MagicMock(return_value=[])  # No more active PRs in TFS
            handler.get_pull_request = MagicMock(return_value={
                "pullRequestId": 9001,
                "title": "Add Turbo Engine",
                "status": "completed",  # Closed in TFS!
                "targetRefName": "refs/heads/dev",
                "sourceRefName": "refs/heads/feature-turbo",
                "createdBy": {"displayName": "Alice"},
                "closedBy": {"displayName": "Bob Reviewer"},
                "creationDate": "2026-09-01T10:00:00Z",
                "closedDate": "2026-09-08T14:30:00Z",
                "repository": {"id": "repo-100"}
            })

            # 3. Trigger Delta Sync / PR status sync
            cached_repo, push_id = handler._get_cached_repo_if_up_to_date("proj-1", repo, cache_db)

            # 4. Verify that PR was updated in SQLite
            active_prs_after = cache_db.get_active_pull_requests("repo-100")
            self.assertEqual(len(active_prs_after), 0, "PR should no longer be active in DB")

            all_prs = cache_db.get_all_prs()
            self.assertEqual(len(all_prs), 1)
            self.assertEqual(all_prs[0]["status"], "completed")
            self.assertEqual(all_prs[0]["closed_by"], "Bob Reviewer")
            self.assertTrue(all_prs[0]["status_str"].startswith("DON"))

            # 5. Verify sync_pull_requests direct method works
            handler.get_repositories = MagicMock(return_value=[repo])
            summary = handler.sync_pull_requests(cache_db, project_id="proj-1")
            self.assertIn("synced", summary)
            self.assertEqual(summary["errors"], 0)

        finally:
            if os.path.exists(db_path):
                os.remove(db_path)

    def test_incremental_pr_sync_stops_at_max_known_id(self):
        """
        Verifies that sync_pull_requests:
        1. Reconciles existing active PR states (Phase 1).
        2. Incrementally pulls newer PRs (Phase 2) and stops searching as soon as pr_id <= max_known_id.
        """
        db_fd, db_path = tempfile.mkstemp(suffix=".sqlite3")
        os.close(db_fd)
        try:
            cache_db = AzureDevOpsCache(db_path)
            repo = {"id": "repo-200", "name": "EngineCore"}
            cache_db.save_repository("proj-1", repo)

            # DB has PR 450 (active), PR 499 (completed), and PR 500 (completed)
            cache_db.save_single_pull_request({
                "pullRequestId": 450,
                "title": "Old Active Feature",
                "status": "active",
                "repository": repo
            })
            cache_db.save_single_pull_request({
                "pullRequestId": 499,
                "title": "Old PR 499",
                "status": "completed",
                "repository": repo
            })
            cache_db.save_single_pull_request({
                "pullRequestId": 500,
                "title": "Previously Merged Feature",
                "status": "completed",
                "repository": repo
            })

            self.assertEqual(cache_db.get_max_pr_id("repo-200"), 500)
            self.assertEqual(len(cache_db.get_active_pull_requests("repo-200")), 1)

            # Mock TFS Handler
            handler = AzureInfoHandler("https://tfs.company.com/tfs/DefaultCollection", "dummy_pat")
            handler.get_repositories = MagicMock(return_value=[repo])

            # PR 450 is now completed in TFS
            def mock_get_pr(pr_id):
                if str(pr_id) == "450":
                    return {
                        "pullRequestId": 450,
                        "title": "Old Active Feature",
                        "status": "completed",
                        "closedDate": "2026-09-08T15:00:00Z",
                        "repository": repo
                    }
                return None
            handler.get_pull_request = MagicMock(side_effect=mock_get_pr)

            # TFS returns PRs in descending order: 503, 502, 501, 500, 499...
            # The incremental scan should process 503, 502, 501, and STOP at 500!
            tfs_prs_page = [
                {"pullRequestId": 503, "title": "New PR 503", "status": "active", "repository": repo},
                {"pullRequestId": 502, "title": "New PR 502", "status": "completed", "repository": repo},
                {"pullRequestId": 501, "title": "New PR 501", "status": "abandoned", "repository": repo},
                {"pullRequestId": 500, "title": "Old PR 500", "status": "completed", "repository": repo},
                {"pullRequestId": 499, "title": "Old PR 499", "status": "completed", "repository": repo},
            ]
            handler.get_pull_requests = MagicMock(return_value=tfs_prs_page)

            summary = handler.sync_pull_requests(cache_db, project_id="proj-1")

            # 1 active PR updated + 3 new PRs discovered
            self.assertEqual(summary["updated"], 1)
            self.assertEqual(summary["new"], 3)
            self.assertEqual(summary["errors"], 0)

            # Max PR id in DB should now be 503
            self.assertEqual(cache_db.get_max_pr_id("repo-200"), 503)

            # Verify PR 450 is completed
            all_prs = cache_db.get_all_prs()
            pr_map = {p["pr_id"]: p for p in all_prs}
            self.assertIn(450, pr_map)
            self.assertEqual(pr_map[450]["status"], "completed")

            # Verify new PRs were inserted
            self.assertIn(503, pr_map)
            self.assertIn(502, pr_map)
            self.assertIn(501, pr_map)

            # Verify PR 499 (known) is preserved in DB
            self.assertIn(499, pr_map)

        finally:
            if os.path.exists(db_path):
                os.remove(db_path)

    def test_backend_refresh_all_data_pull_requests_and_repos(self):
        """Tests that backend.refresh_all_data properly loads pull requests, emits pullRequestsChanged, and updates stats."""
        from gui.backend import DevOpsBackend

        backend = DevOpsBackend()
        backend._db_path = self.db_path
        backend._cache_db = self.cache

        pr_signals = []
        repo_signals = []
        stats_signals = []

        backend.pullRequestsChanged.connect(lambda: pr_signals.append(True))
        backend.repositoriesChanged.connect(lambda: repo_signals.append(True))
        backend.statsChanged.connect(lambda: stats_signals.append(True))

        backend.refresh_all_data()

        self.assertGreaterEqual(len(pr_signals), 1, "pullRequestsChanged should have been emitted")
        self.assertGreaterEqual(len(repo_signals), 1, "repositoriesChanged should have been emitted")
        self.assertGreaterEqual(len(stats_signals), 1, "statsChanged should have been emitted")

        # Verify PRs in backend
        prs = backend.pullRequests
        self.assertEqual(len(prs), 3)
        self.assertEqual(backend.stats["prs_count"], 3)
        self.assertEqual(backend.stats["prs_open_count"], 1)
        self.assertEqual(backend.stats["prs_completed_count"], 2)
        self.assertEqual(backend.stats["prs_abandoned_count"], 0)

        # Verify repos in backend
        self.assertIn("cmake-scripts", backend.prRepositories)
        self.assertIn("repo-alpha", backend.prRepositories)

        # Verify active PR details
        active_pr = next(p for p in prs if p["id"] == 1003)
        self.assertEqual(active_pr["status"], "active")
        self.assertEqual(active_pr["repo_name"], "cmake-scripts")


if __name__ == "__main__":
    unittest.main()

