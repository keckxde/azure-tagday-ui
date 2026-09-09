# -*- coding: UTF-8 -*-
import unittest
from unittest.mock import MagicMock, patch
import os
import sys
import tempfile
import time

# Add src and src/azure to sys.path
src_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if src_dir not in sys.path:
    sys.path.insert(0, src_dir)

from azure.azure_db import AzureDevOpsCache
from azure.azure_info_handler import AzureInfoHandler
from gui.workers import TaskWorker


class TestFastRepoAndPRSync(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.tmp_dir.name, "test_sync.db")
        self.cache_db = AzureDevOpsCache(self.db_path)
        self.handler = AzureInfoHandler("https://dev.azure.com/fakeorg", "fake_pat")

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_fetch_new_prs_incremental_multi_page_no_premature_break(self):
        """
        Verify that out-of-order PR IDs across multiple pages are NOT skipped
        by premature break on pr_id <= max_known_id.
        """
        repo = {"id": "repo-uuid-1", "name": "RepoOne"}

        # Simulate initial DB having PR #500
        self.cache_db.save_single_pull_request({
            "pullRequestId": 500,
            "id": 500,
            "title": "Old known PR",
            "status": "completed",
            "repository": repo,
            "targetRefName": "refs/heads/master"
        })
        self.assertEqual(len(self.cache_db.get_pr_ids_for_repo("repo-uuid-1")), 1)

        # Page 1 has PR #600 and PR #450 (which has ID < 500 but is a new PR in this repo!)
        # Page 2 has PR #300 (new) and PR #200 (new)
        page1 = [
            {"pullRequestId": 600, "title": "New PR 600", "status": "active", "targetRefName": "refs/heads/dev"},
            {"pullRequestId": 450, "title": "New PR 450", "status": "completed", "targetRefName": "refs/heads/master"},
        ]
        page2 = [
            {"pullRequestId": 300, "title": "New PR 300", "status": "completed", "targetRefName": "refs/heads/dev"},
            {"pullRequestId": 200, "title": "New PR 200", "status": "completed", "targetRefName": "refs/heads/master"},
        ]

        def fake_get_pull_requests(proj, repo_id, status="all", top=100, skip=0):
            if skip == 0:
                return page1
            elif skip == 2:
                return page2
            return []

        self.handler.get_pull_requests = MagicMock(side_effect=fake_get_pull_requests)

        # Run incremental fetch with top=2
        new_count = self.handler._fetch_new_prs_incremental("ProjA", repo, self.cache_db, top=2)

        # All 4 new PRs (600, 450, 300, 200) should be discovered and saved
        all_ids = self.cache_db.get_pr_ids_for_repo("repo-uuid-1")
        self.assertIn(600, all_ids)
        self.assertIn(450, all_ids)
        self.assertIn(300, all_ids)
        self.assertIn(200, all_ids)
        self.assertIn(500, all_ids)
        self.assertEqual(len(all_ids), 5)

    def test_process_pushes_and_prs_bulk(self):
        """
        Verifies bulk PR retrieval properly categorizes devPRs and stablePRs without per-push calls.
        """
        repo = {"id": "repo-uuid-2", "name": "RepoTwo"}
        raw_prs = [
            {"pullRequestId": 101, "title": "Feature A", "status": "completed", "targetRefName": "refs/heads/dev", "closedDate": "2026-09-08T12:00:00Z"},
            {"pullRequestId": 102, "title": "Hotfix B", "status": "completed", "targetRefName": "refs/heads/master", "closedDate": "2026-09-08T12:00:00Z"},
            {"pullRequestId": 103, "title": "Feature C", "status": "active", "targetRefName": "refs/heads/dev_2636", "creationDate": "2026-09-08T10:00:00Z"},
        ]
        self.handler.get_pull_requests = MagicMock(return_value=raw_prs)
        self.handler.get_pushes = MagicMock(return_value=[])

        dev_prs, stable_prs = self.handler._process_pushes_and_prs("ProjA", repo, self.cache_db)

        self.assertEqual(len(dev_prs), 2)  # 101 and 103 contain 'dev'
        self.assertEqual(len(stable_prs), 1)  # 102 is master
        self.assertTrue(dev_prs[0]["statusStr"].startswith("DON"))
        self.assertTrue(dev_prs[1]["statusStr"].startswith("OPN"))

    def test_get_tfs_repositories_parallel_and_progress(self):
        """
        Verifies that GetTFSRepositories processes repositories concurrently and invokes progress_callback.
        """
        repos = [
            {"id": f"repo-id-{i}", "name": f"Repo_{i}", "defaultBranch": "refs/heads/main"}
            for i in range(5)
        ]
        self.handler.get_repositories = MagicMock(return_value=repos)
        self.handler.get_repository_refs = MagicMock(return_value=[])
        self.handler._process_tags = MagicMock(return_value=([], None, None))
        self.handler._process_pushes_and_prs = MagicMock(return_value=([], []))

        progress_reports = []
        def _on_prog(pct, msg):
            progress_reports.append((pct, msg))

        results = self.handler.GetTFSRepositories(
            "ProjA",
            cache_db=self.cache_db,
            progress_callback=_on_prog,
            max_workers=4
        )

        self.assertEqual(len(results), 5)
        self.assertEqual(len(progress_reports), 5)
        # Verify last report reaches 100%
        self.assertEqual(progress_reports[-1][0], 100)

    def test_get_tfs_repositories_cancellation(self):
        """
        Verifies that GetTFSRepositories stops execution when cancel_token is triggered.
        """
        repos = [
            {"id": f"repo-id-{i}", "name": f"Repo_{i}", "defaultBranch": "refs/heads/main"}
            for i in range(10)
        ]
        self.handler.get_repositories = MagicMock(return_value=repos)
        
        cancel_requested = False
        def cancel_check():
            return cancel_requested

        def fake_process_tags(*args, **kwargs):
            nonlocal cancel_requested
            time.sleep(0.01)
            cancel_requested = True
            return ([], None, None)

        self.handler.get_repository_refs = MagicMock(return_value=[])
        self.handler._process_tags = MagicMock(side_effect=fake_process_tags)
        self.handler._process_pushes_and_prs = MagicMock(return_value=([], []))

        results = self.handler.GetTFSRepositories(
            "ProjA",
            cache_db=self.cache_db,
            cancel_token=cancel_check,
            max_workers=2
        )

        # Should have stopped early before processing all 10
        self.assertLess(len(results), 10)

    def test_sync_pull_requests_reconciles_active(self):
        """
        Verifies sync_pull_requests updates previously active PR that transitioned to completed.
        """
        repo = {"id": "repo-uuid-3", "name": "RepoThree"}
        # Save active PR in DB
        self.cache_db.save_single_pull_request({
            "pullRequestId": 999,
            "id": 999,
            "title": "PR in review",
            "status": "active",
            "repository": repo,
            "targetRefName": "refs/heads/dev"
        })
        active_before = self.cache_db.get_active_pull_requests()
        self.assertEqual(len(active_before), 1)

        # TFS now reports it as completed
        self.handler.get_pull_request = MagicMock(return_value={
            "pullRequestId": 999,
            "id": 999,
            "title": "PR in review",
            "status": "completed",
            "closedDate": "2026-09-09T05:00:00Z",
            "repository": repo,
            "targetRefName": "refs/heads/dev"
        })
        self.handler.get_repositories = MagicMock(return_value=[repo])
        self.handler._fetch_new_prs_incremental = MagicMock(return_value=0)

        summary = self.handler.sync_pull_requests(self.cache_db, project_id="ProjA")

        self.assertEqual(summary["synced"], 1)
        self.assertEqual(summary["updated"], 1)
        active_after = self.cache_db.get_active_pull_requests()
        self.assertEqual(len(active_after), 0)

    def test_fetch_new_prs_incremental_captures_recent_completed_and_active_prs(self):
        """
        Verifies _fetch_new_prs_incremental captures both newly created active PRs
        and PRs created weeks ago but completed/merged recently.
        """
        repo = {"id": "repo-uuid-4", "name": "RepoFour"}
        self.cache_db.save_repository("ProjA", repo)

        # SQLite has PR 100 stored as active from 2 weeks ago
        self.cache_db.save_single_pull_request({
            "pullRequestId": 100,
            "id": 100,
            "title": "Old Branch Feature",
            "status": "active",
            "repository": repo,
            "creationDate": "2026-08-20T10:00:00Z"
        })

        # Mock get_pull_requests:
        # Active query returns PR 105 (new PR created yesterday)
        # Completed query returns PR 100 (merged yesterday)
        def mock_get_prs(project_id, repo_id, status=None, top=None, skip=None):
            if status == "active":
                return [{
                    "pullRequestId": 105,
                    "title": "Brand New Active PR",
                    "status": "active",
                    "creationDate": "2026-09-08T11:00:00Z",
                    "repository": repo
                }]
            elif status == "completed":
                return [{
                    "pullRequestId": 100,
                    "title": "Old Branch Feature",
                    "status": "completed",
                    "creationDate": "2026-08-20T10:00:00Z",
                    "closedDate": "2026-09-08T16:00:00Z",
                    "repository": repo
                }]
            return []

        self.handler.get_pull_requests = MagicMock(side_effect=mock_get_prs)

        new_count = self.handler._fetch_new_prs_incremental("ProjA", repo, self.cache_db)

        # PR 105 is new
        self.assertEqual(new_count, 1)

        # Check DB state
        active_prs = self.cache_db.get_active_pull_requests("repo-uuid-4")
        self.assertEqual(len(active_prs), 1)
        self.assertEqual(active_prs[0]["id"], 105)

        # Check PR 100 updated to completed
        all_prs = self.cache_db.get_prs_for_repo("repo-uuid-4")
        pr_100 = next(p for p in all_prs if p["id"] == 100)
        self.assertEqual(pr_100["status"], "completed")

    def test_get_pull_request_with_repo_and_project_scoping(self):
        """
        Verifies get_pull_request queries repo-level URL first when project_id and repo_id are supplied.
        """
        self.handler._request = MagicMock(return_value=({"pullRequestId": 777, "title": "Repo PR"}, 200))
        pr = self.handler.get_pull_request(777, project_id="ProjA", repo_id="repo-1")

        self.assertEqual(pr["pullRequestId"], 777)
        self.handler._request.assert_called_with(
            "GET",
            "ProjA/_apis/git/repositories/repo-1/pullrequests/777",
            params={"api-version": "6.0"}
        )

    def test_task_worker_cancellation(self):
        """
        Verifies TaskWorker cancellation method and flag.
        """
        worker = TaskWorker(lambda w: None)
        self.assertFalse(worker.is_cancelled())
        worker.cancel()
        self.assertTrue(worker.is_cancelled())


if __name__ == "__main__":
    unittest.main()
