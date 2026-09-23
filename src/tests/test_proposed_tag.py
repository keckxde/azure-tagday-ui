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
        "taggedObject": {"objectId": "deadbeef12345678"}
    })
    
    res = handler.create_repository_tag("my-project", "MyRepo", "v01.02.2639", branch_name="dev", message="Weekly Tag", cache_db=mock_db)
    assert res["success"] is True
    assert res["tag_name"] == "v01.02.2639"
    assert res["commit_id"] == "deadbeef12345678"
    handler.get_branch_commit_id.assert_called_with("my-project", "repo-guid-123", "dev")
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
