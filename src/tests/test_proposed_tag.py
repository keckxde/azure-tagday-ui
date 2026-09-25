from datetime import date
from unittest.mock import MagicMock
import pytest
from PySide6.QtCore import QCoreApplication

from src.utils import propose_next_tag, parse_semver_tuple


def test_propose_next_tag_weekly_standard():
    # Test on a specific target date: 2026-09-23 (Week 39 of 2026 -> YYWW = 2639)
    target_dt = date(2026, 9, 23)
    
    # Existing tag is older week (Week 38)
    proposed = propose_next_tag("v01.02.2638", target_date=target_dt)
    assert proposed == "v01.02.2639"

    # Preserves 2-digit padding and leading v
    proposed_plain = propose_next_tag("1.2.2638", target_date=target_dt)
    assert proposed_plain == "1.2.2639"


def test_propose_next_tag_same_week_increment():
    # If a tag already exists for the current week (2639), it should increment patch to 2640
    target_dt = date(2026, 9, 23)
    proposed = propose_next_tag("v01.02.2639", target_date=target_dt)
    assert proposed == "v01.02.2640"


def test_propose_next_tag_none_or_empty():
    target_dt = date(2026, 9, 23)
    proposed = propose_next_tag(None, target_date=target_dt)
    assert proposed == "v01.00.2639"
    
    proposed_dash = propose_next_tag("-", target_date=target_dt)
    assert proposed_dash == "v01.00.2639"


def test_propose_next_tag_bumps():
    target_dt = date(2026, 9, 23)
    
    # Minor bump
    proposed_minor = propose_next_tag("v01.02.2638", target_date=target_dt, bump="minor")
    assert proposed_minor == "v01.03.2639"
    
    # Major bump
    proposed_major = propose_next_tag("v01.02.2638", target_date=target_dt, bump="major")
    assert proposed_major == "v02.00.2639"


def test_propose_next_tag_padding_options():
    target_dt = date(2026, 1, 5) # Week 02 of 2026 -> 2602
    proposed_unpadded = propose_next_tag("v1.2.2550", target_date=target_dt, pad_digits=1)
    assert proposed_unpadded == "v1.2.2602"

    proposed_padded = propose_next_tag("v1.2.2550", target_date=target_dt, pad_digits=True)
    assert proposed_padded == "v01.02.2602"


def test_create_repository_tag_handler():
    from src.azure.azure_info_handler import AzureInfoHandler
    
    mock_client = MagicMock()
    mock_db = MagicMock()
    
    # Mock client and handler
    handler = AzureInfoHandler(mock_client, mock_db)
    handler.get_repositories = MagicMock(return_value=[{"id": "repo-guid-123", "name": "MyRepo"}])
    
    # Mock resolving dev commit ID
    handler.get_branch_commit_id = MagicMock(return_value="deadbeef12345678")
    handler.create_annotated_tag = MagicMock(return_value={
        "name": "v01.02.2639",
        "objectId": "tagobject12345678",
        "taggedObject": {"objectId": "deadbeef12345678"}
    })
    handler.create_tag_ref = MagicMock(return_value={
        "value": [{"name": "refs/tags/v01.02.2639", "updateStatus": "succeeded", "success": True}]
    })
    
    res = handler.create_repository_tag("my-project", "MyRepo", "v01.02.2639", branch_name="dev", message="Weekly Tag", cache_db=mock_db)
    assert res["success"] is True
    assert res["tag_name"] == "v01.02.2639"
    assert res["commit_id"] == "deadbeef12345678"
    handler.get_branch_commit_id.assert_called_with("my-project", "repo-guid-123", "dev")
    handler.create_annotated_tag.assert_called_once()
    handler.create_tag_ref.assert_called_once_with("my-project", "repo-guid-123", "v01.02.2639", "tagobject12345678")
    mock_db.save_single_tag.assert_called_once()


def test_backend_propose_and_branches():
    if not QCoreApplication.instance():
        app = QCoreApplication([])
    else:
        app = QCoreApplication.instance()

    from src.gui.backend import DevOpsBackend
    
    backend = DevOpsBackend()
    backend._tagday_data = {
        "repos_summary": [
            {"name": "RepoA", "latest_tag": "v01.00.2630"}
        ]
    }
    
    # Propose from tag string
    tag1 = backend.propose_next_tag("v01.02.2630", "patch")
    assert tag1.startswith("v01.02.")
    
    # Propose for repo
    repo_tag = backend.propose_repo_tag("RepoA", "minor")
    assert repo_tag.startswith("v01.01.")
    
    # Default branches fallback
    branches = backend.get_repo_branches("RepoA")
    assert "dev" in branches


def test_proposed_tag_only_when_untagged_prs_exist(tmp_path):
    if not QCoreApplication.instance():
        app = QCoreApplication([])
    else:
        app = QCoreApplication.instance()

    from src.gui.backend import DevOpsBackend
    from azure import AzureDevOpsCache
    import devops_helper

    devops_helper.AZURE_PROJECT_ID = "p1"
    db_path = str(tmp_path / "test_tagday.db")
    cache = AzureDevOpsCache(db_path)

    with cache._connection() as conn:
        conn.execute("INSERT OR REPLACE INTO projects (id, name) VALUES ('p1', 'p1')")
        conn.execute("INSERT OR REPLACE INTO repositories (id, name, project_id, default_branch, web_url, is_disabled) VALUES ('r1', 'RepoWithChanges', 'p1', 'main', '', 0)")
        conn.execute("INSERT OR REPLACE INTO repositories (id, name, project_id, default_branch, web_url, is_disabled) VALUES ('r2', 'RepoWithBranchesOnly', 'p1', 'main', '', 0)")

        # RepoWithChanges has latest tag v01.00.2630 and an untagged completed PR
        conn.execute("""
            INSERT OR REPLACE INTO tags (repo_id, name, commit_id, commit_date, raw_json)
            VALUES ('r1', 'v01.00.2630', 'c1', '2026-07-20 10:00:00', '{}')
        """)
        conn.execute("""
            INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, status_str, closed_date, raw_json)
            VALUES (101, 'r1', 'Untagged Feature PR', 'completed', 'COMPLETED', '2026-08-01 12:00:00', '{"lastMergeCommit": {"commitId": "m1"}}')
        """)

        # RepoWithBranchesOnly has latest tag v01.00.2630, unmerged branch, and PR closed before tag
        conn.execute("""
            INSERT OR REPLACE INTO tags (repo_id, name, commit_id, commit_date, raw_json)
            VALUES ('r2', 'v01.00.2630', 'c2', '2026-07-20 10:00:00', '{}')
        """)
        conn.execute("""
            INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, status_str, closed_date, raw_json)
            VALUES (102, 'r2', 'Old Tagged PR', 'completed', 'COMPLETED', '2026-07-15 12:00:00', '{"lastMergeCommit": {"commitId": "m2"}}')
        """)
        conn.execute("""
            INSERT OR REPLACE INTO branches (repo_id, name, commit_id, commit_date, ahead_count, behind_count)
            VALUES ('r2', 'feature/experiment', 'b1', '2026-08-02 12:00:00', 2, 0)
        """)

    backend = DevOpsBackend()
    backend._db_path = db_path
    backend._cache_db = cache
    backend.refresh_all_data()

    tagday = backend.tagDayData
    assert tagday is not None
    repos = {r["name"]: r for r in tagday.get("repos_summary", [])}

    # RepoWithChanges should propose a new release tag
    assert "RepoWithChanges" in repos
    r_changed = repos["RepoWithChanges"]
    assert r_changed["prs_count"] > 0
    assert r_changed["proposed_tag"] != ""
    assert r_changed["proposed_tag"].startswith("v01.00.")

    # RepoWithBranchesOnly has unmerged branch but NO untagged PRs -> should NOT propose a release tag
    assert "RepoWithBranchesOnly" in repos
    r_branches_only = repos["RepoWithBranchesOnly"]
    assert r_branches_only["prs_count"] == 0
    assert r_branches_only["branches_count"] > 0
    assert r_branches_only["proposed_tag"] == ""
    assert r_branches_only["proposed_minor_tag"] == ""
    assert r_branches_only["proposed_major_tag"] == ""


def test_create_tag_async_worker():
    if not QCoreApplication.instance():
        app = QCoreApplication([])
    else:
        app = QCoreApplication.instance()

    from src.gui.backend import DevOpsBackend

    backend = DevOpsBackend()
    
    # Mock info_handler
    mock_handler = MagicMock()
    mock_handler.create_repository_tag.return_value = {
        "success": True,
        "tag_name": "v01.00.2639",
        "commit_id": "c123456"
    }
    backend._info_handler = mock_handler
    backend._project_id = "test-proj"
    
    emitted_tags = []
    backend.tagCreated.connect(lambda r, t, s, m: emitted_tags.append((r, t, s, m)))
    
    # Trigger create_tag_async
    worker = backend.create_tag_async("RepoA", "v01.00.2639", "dev", "Release tag")
    assert worker is not None
    worker.wait(5000)
    app.processEvents()
    
    assert len(emitted_tags) == 1
    assert emitted_tags[0][0] == "RepoA"
    assert emitted_tags[0][1] == "v01.00.2639"
    assert emitted_tags[0][2] is True



