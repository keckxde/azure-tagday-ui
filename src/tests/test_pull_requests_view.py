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

from azure import AzureDevOpsCache


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


if __name__ == "__main__":
    unittest.main()
