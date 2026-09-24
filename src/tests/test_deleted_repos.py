# -*- coding: UTF-8 -*-
import os
import sys
import json
import sqlite3
import tempfile
import shutil
import unittest
from unittest.mock import MagicMock, patch

# Ensure src path is available
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from azure import AzureDevOpsCache
from azure.azure_info_handler import AzureInfoHandler
import utils
import devops_helper
import generate_revision


class TestDeletedRepositories(unittest.TestCase):

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_cache.db")
        self.cache = AzureDevOpsCache(self.db_path)
        self.project_id = "test-project-guid"

        # Seed sample repositories
        self.repo_active_1 = {"id": "repo-uuid-1", "name": "ActiveRepoOne", "defaultBranch": "refs/heads/main"}
        self.repo_active_2 = {"id": "repo-uuid-2", "name": "ActiveRepoTwo", "defaultBranch": "refs/heads/main"}
        self.repo_deleted_1 = {"id": "repo-uuid-3", "name": "OldDeletedRepo", "defaultBranch": "refs/heads/main"}

        self.cache.save_repository(self.project_id, self.repo_active_1)
        self.cache.save_repository(self.project_id, self.repo_active_2)
        self.cache.save_repository(self.project_id, self.repo_deleted_1)

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_reconcile_deleted_repositories_direct(self):
        """Tests that reconcile_deleted_repositories identifies and marks missing repos as DELETED."""
        active_names = ["ActiveRepoOne", "ActiveRepoTwo"]
        active_ids = ["repo-uuid-1", "repo-uuid-2"]

        marked = self.cache.reconcile_deleted_repositories(self.project_id, active_names, active_ids)
        self.assertIn("OldDeletedRepo", marked)
        self.assertEqual(len(marked), 1)

        # Check category override
        overrides = self.cache.get_repo_category_overrides()
        self.assertEqual(overrides.get("OldDeletedRepo"), "DELETED")

        # Categorization check
        cat = utils.categorize_repository("OldDeletedRepo", cache_db=self.cache)
        self.assertEqual(cat, "DELETED")

        # Active repos should not be marked DELETED
        cat_active = utils.categorize_repository("ActiveRepoOne", cache_db=self.cache)
        self.assertNotEqual(cat_active, "DELETED")

    def test_get_tfs_repositories_triggers_deletion_reconcile(self):
        """Tests that GetTFSRepositories automatically marks removed TFS repositories as DELETED."""
        handler = AzureInfoHandler(
            "https://dev.azure.com/fake",
            "fakepat123"
        )

        # TFS now only returns ActiveRepoOne (ActiveRepoTwo and OldDeletedRepo were deleted from TFS)
        handler.get_repositories = MagicMock(return_value=[
            {"id": "repo-uuid-1", "name": "ActiveRepoOne", "defaultBranch": "refs/heads/main"}
        ])
        handler.get_repository_refs = MagicMock(return_value=[])
        handler.get_pushes = MagicMock(return_value=[])

        handler.GetTFSRepositories(
            self.project_id,
            cache_db=self.cache
        )

        overrides = self.cache.get_repo_category_overrides()
        self.assertEqual(overrides.get("ActiveRepoTwo"), "DELETED")
        self.assertEqual(overrides.get("OldDeletedRepo"), "DELETED")
        self.assertNotIn("ActiveRepoOne", overrides)

    def test_add_categories_to_repos_handles_deleted_repos(self):
        """Tests that devops_helper.addCategoriesToRepos preserves DELETED category on repositories."""
        self.cache.save_repo_category_override("OldDeletedRepo", "DELETED")

        repos_dict = self.cache.get_all_cached_repositories(self.project_id)
        devops_helper.addCategoriesToRepos(repos_dict, cache_db=self.cache)

        deleted_entry = repos_dict.get("repo-uuid-3") or repos_dict.get("OldDeletedRepo")
        self.assertIsNotNone(deleted_entry)
        self.assertEqual(deleted_entry.get("category"), "DELETED")

    def test_generate_revision_md_excludes_deleted_repos(self):
        """Tests that generate_revision_md excludes DELETED repos from Overview table and detail sections."""
        # Add tags and PRs to ActiveRepoOne
        self.cache.save_tags("repo-uuid-1", [{
            "name": "v1.0.0",
            "FriendlyName": "v1.0.0",
            "CommitId": "1111111",
            "CommitDate": "2026-06-01 12:00:00",
            "Committer": "Alice",
            "stable": True,
            "unstable": False
        }])
        self.cache.save_pull_requests("repo-uuid-1", [{
            "id": 101,
            "title": "FEAT_101: Active repo feature",
            "status": "completed",
            "targetRefName": "refs/heads/main",
            "sourceRefName": "refs/heads/feat",
            "closedDateStr": "2026-06-01 10:00:00",
            "lastMergeCommit": {"commitId": "1111111"}
        }])

        # Add tags and PRs to OldDeletedRepo
        self.cache.save_tags("repo-uuid-3", [{
            "name": "v0.9.0",
            "FriendlyName": "v0.9.0",
            "CommitId": "3333333",
            "CommitDate": "2026-05-20 12:00:00",
            "Committer": "Bob",
            "stable": True,
            "unstable": False
        }])
        self.cache.save_pull_requests("repo-uuid-3", [{
            "id": 301,
            "title": "FEAT_301: Old repo feature",
            "status": "completed",
            "targetRefName": "refs/heads/main",
            "sourceRefName": "refs/heads/oldfeat",
            "closedDateStr": "2026-05-20 10:00:00",
            "lastMergeCommit": {"commitId": "3333333"}
        }])

        # Mark OldDeletedRepo as DELETED
        self.cache.save_repo_category_override("OldDeletedRepo", "DELETED")

        # Also prepare pre-existing REVISION.md containing OldDeletedRepo to verify it gets stripped
        rev_md_path = os.path.join(self.test_dir, "REVISION.md")
        initial_content = (
            "# Revision History\n\n"
            "| Package | SuperInstaller | Unstable (Nightly) | Stable | Last Change | Owner |\n"
            "| ------- | -------------- | ------------------ | ------ | ----------- | ----- |\n"
            "| [ActiveRepoOne](#activerepoone) | | | v1.0.0 | | Alice |\n"
            "| [OldDeletedRepo](#olddeletedrepo) | | | v0.9.0 | | Bob |\n\n"
            "### OldDeletedRepo\n\n"
            "**Info:** Legacy Info\n\n"
            "**Version:**\n\n"
            "| Date     | Version        | Stable | Description |\n"
            "| -------- | -------------- | ------ | ----------- |\n"
            "| 20.05.26 | v0.9.0         | X      | !301: FEAT_301: Old repo feature |\n\n"
        )
        with open(rev_md_path, "w", encoding="utf-8") as f:
            f.write(initial_content)

        # Generate Release Notes
        success = generate_revision.generate_revision_md(self.db_path, rev_md_path)
        self.assertTrue(success)

        with open(rev_md_path, "r", encoding="utf-8") as f:
            updated_content = f.read()

        # Active repo must be present
        self.assertIn("ActiveRepoOne", updated_content)
        self.assertIn("### ActiveRepoOne", updated_content)

        # Deleted repo MUST NOT be present in overview table or detail sections
        self.assertNotIn("[OldDeletedRepo]", updated_content)
        self.assertNotIn("### OldDeletedRepo", updated_content)
        self.assertNotIn("!301: FEAT_301", updated_content)

    def test_export_prs_excludes_deleted_repos(self):
        """Tests that export_prs ignores PRs belonging to DELETED repositories."""
        self.cache.save_pull_requests("repo-uuid-1", [{
            "id": 101,
            "title": "FEAT_101: Active repo feature",
            "status": "completed",
            "targetRefName": "refs/heads/main",
            "sourceRefName": "refs/heads/feat",
            "closedDateStr": "2026-06-01 10:00:00"
        }])
        self.cache.save_pull_requests("repo-uuid-3", [{
            "id": 301,
            "title": "FEAT_301: Old deleted repo feature",
            "status": "completed",
            "targetRefName": "refs/heads/main",
            "sourceRefName": "refs/heads/feat",
            "closedDateStr": "2026-06-01 10:00:00"
        }])

        self.cache.save_repo_category_override("OldDeletedRepo", "DELETED")

        export_base = os.path.join(self.test_dir, "PR_EXPORT")
        with patch.object(devops_helper, "_getDBCacheHandler", return_value=(self.db_path, self.cache)):
            devops_helper.export_prs(export_base)

        export_md = f"{export_base}.md"
        if os.path.exists(export_md):
            with open(export_md, "r", encoding="utf-8") as f:
                content = f.read()
            self.assertIn("ActiveRepoOne", content)
            self.assertNotIn("OldDeletedRepo", content)


if __name__ == "__main__":
    unittest.main()
