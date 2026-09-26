import pytest
from unittest.mock import MagicMock
from PySide6.QtCore import QCoreApplication
from src.gui.backend import DevOpsBackend


def test_separate_pending_prs_and_unmerged_branches_cache_computation():
    """Verify that backend._compute_all_cache_data correctly separates has_untagged_prs and has_unmerged_branches."""
    app = QCoreApplication.instance() or QCoreApplication([])
    backend = DevOpsBackend()
    backend._cache_db = MagicMock()
    backend._stats = {}
    backend._tfs_team_name = "Default Team"
    backend._db_path = ":memory:"

    backend._cache_db.get_all_cached_repositories.return_value = {
        "1": {"info": {"name": "repo_prs", "defaultBranch": "refs/heads/main", "webUrl": "http://example.com/repo_prs"}, "category": "GENERIC"},
        "2": {"info": {"name": "repo_branches", "defaultBranch": "refs/heads/main", "webUrl": "http://example.com/repo_branches"}, "category": "GENERIC"},
        "3": {"info": {"name": "repo_both", "defaultBranch": "refs/heads/main", "webUrl": "http://example.com/repo_both"}, "category": "GENERIC"},
        "4": {"info": {"name": "repo_clean", "defaultBranch": "refs/heads/main", "webUrl": "http://example.com/repo_clean"}, "category": "GENERIC"},
    }
    backend._cache_db.get_all_categories.return_value = []
    backend._cache_db.get_change_filter_patterns.return_value = {}
    backend._cache_db.get_all_work_items.return_value = []
    backend._cache_db.get_all_prs.return_value = []
    backend._cache_db.get_project_last_synced.return_value = None

    repos_mock = {
        "repo_prs": {
            "latest_tag": {"name": "v01.00.2600"},
            "prs_after_tag": [{"pr_id": 101, "title": "Feature PR 1"}, {"pr_id": 102, "title": "Feature PR 2"}],
            "unmerged_branches": [],
            "active_prs": [],
            "all_prs": [],
        },
        "repo_branches": {
            "latest_tag": {"name": "v01.00.2600"},
            "prs_after_tag": [],
            "unmerged_branches": [{"branch_name": "feature/branch1"}, {"branch_name": "feature/branch2"}, {"branch_name": "feature/branch3"}],
            "active_prs": [],
            "all_prs": [],
        },
        "repo_both": {
            "latest_tag": {"name": "v01.00.2600"},
            "prs_after_tag": [{"pr_id": 103, "title": "Feature PR 3"}],
            "unmerged_branches": [{"branch_name": "feature/branch4"}],
            "active_prs": [],
            "all_prs": [],
        },
    }

    import generate_tagday_report
    orig_load_tagday_data = generate_tagday_report.load_tagday_data
    try:
        generate_tagday_report.load_tagday_data = lambda *args, **kwargs: {
            "all_repositories": repos_mock,
            "repos_with_any_changes": repos_mock,
            "all_changes_timeline": [],
            "generated_at": "2026-09-26 07:00:00",
        }

        data = backend._compute_all_cache_data()
        repos = {r["name"]: r for r in data["repositories"]}

        # Check repo_prs
        assert repos["repo_prs"]["has_untagged_prs"] is True
        assert repos["repo_prs"]["has_unmerged_branches"] is False
        assert repos["repo_prs"]["prs_after_tag_count"] == 2
        assert repos["repo_prs"]["unmerged_branches_count"] == 0

        # Check repo_branches
        assert repos["repo_branches"]["has_untagged_prs"] is False
        assert repos["repo_branches"]["has_unmerged_branches"] is True
        assert repos["repo_branches"]["prs_after_tag_count"] == 0
        assert repos["repo_branches"]["unmerged_branches_count"] == 3

        # Check repo_both
        assert repos["repo_both"]["has_untagged_prs"] is True
        assert repos["repo_both"]["has_unmerged_branches"] is True
        assert repos["repo_both"]["prs_after_tag_count"] == 1
        assert repos["repo_both"]["unmerged_branches_count"] == 1

        # Check repo_clean
        assert repos["repo_clean"]["has_untagged_prs"] is False
        assert repos["repo_clean"]["has_unmerged_branches"] is False

        # Check stats breakdown
        stats = data["stats"]
        assert stats["pending_repos_count"] == 3
        assert stats["untagged_prs_repos_count"] == 2  # repo_prs and repo_both
        assert stats["unmerged_branches_repos_count"] == 2  # repo_branches and repo_both

        # Check tagday_data breakdown
        tagday = data["tagday_data"]
        assert tagday["repos_with_prs_count"] == 2
        assert tagday["repos_with_branches_count"] == 2
    finally:
        generate_tagday_report.load_tagday_data = orig_load_tagday_data
