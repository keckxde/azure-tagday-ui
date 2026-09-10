import os
import json
import pytest
import sqlite3
from src.azure.azure_db import AzureDevOpsCache
from src.gui.backend import DevOpsBackend

def test_azure_db_batch_cached_repositories(tmp_path):
    db_file = str(tmp_path / "test_batch.db")
    cache = AzureDevOpsCache(db_file)

    # Insert test project and repositories
    proj_id = "test-project-1"
    with cache._connection() as conn:
        conn.execute("INSERT OR REPLACE INTO projects (id, name, last_synced_at) VALUES (?, ?, CURRENT_TIMESTAMP)", (proj_id, "Test Project"))
        conn.execute("INSERT OR REPLACE INTO repositories (id, project_id, name, default_branch, web_url) VALUES (?, ?, ?, ?, ?)",
                     ("r1", proj_id, "Repo 1", "refs/heads/main", "http://repo1"))
        conn.execute("INSERT OR REPLACE INTO repositories (id, project_id, name, default_branch, web_url) VALUES (?, ?, ?, ?, ?)",
                     ("r2", proj_id, "Repo 2", "refs/heads/master", "http://repo2"))
        
        # Branches
        conn.execute("INSERT INTO branches (repo_id, name, commit_id) VALUES (?, ?, ?)", ("r1", "main", "c_m1"))
        conn.execute("INSERT INTO branches (repo_id, name, commit_id) VALUES (?, ?, ?)", ("r1", "feature/1", "c_f1"))
        conn.execute("INSERT INTO branches (repo_id, name, commit_id) VALUES (?, ?, ?)", ("r2", "master", "c_m2"))
        
        # Tags
        conn.execute("INSERT INTO tags (repo_id, name, commit_id, commit_date, is_stable, is_unstable) VALUES (?, ?, ?, ?, ?, ?)",
                     ("r1", "v1.0.0", "c1", "2026-01-01T00:00:00Z", 1, 0))
        
        # Submodules
        conn.execute("INSERT INTO submodules (parent_repo_id, path, url) VALUES (?, ?, ?)",
                     ("r1", "libs/sub1", "http://sub1"))

    # Fetch all cached repositories (should use batch queries)
    repos = cache.get_all_cached_repositories(proj_id)
    assert len(repos) == 2
    assert "Repo 1" in repos
    assert "Repo 2" in repos
    assert repos["Repo 1"]["info"]["name"] == "Repo 1"
    assert len(repos["Repo 1"]["branches"]) == 2
    assert len(repos["Repo 1"]["tags"]) == 1
    assert len(repos["Repo 1"]["submodules"]) == 1
    assert len(repos["Repo 2"]["branches"]) == 1


def test_work_items_preparsed_fields(tmp_path):
    db_file = str(tmp_path / "test_wi.db")
    cache = AzureDevOpsCache(db_file)

    raw_json_obj = {
        "id": 101,
        "fields": {
            "System.Title": "Optimize queries",
            "System.WorkItemType": "Task",
            "System.State": "Active",
            "System.IterationPath": "Project\\Sprint 2026-W37"
        }
    }
    with cache._connection() as conn:
        conn.execute("""
            INSERT OR REPLACE INTO work_items (id, title, type, state, raw_json)
            VALUES (?, ?, ?, ?, ?)
        """, (101, "Optimize queries", "Task", "Active", json.dumps(raw_json_obj)))

    items = cache.get_all_work_items()
    assert len(items) == 1
    item = items[0]
    assert item["fields"]["System.Title"] == "Optimize queries"
    assert item["raw_dict"]["id"] == 101


def test_gui_backend_search_text_precomputation(tmp_path):
    db_file = str(tmp_path / "test_backend_search.db")
    cache = AzureDevOpsCache(db_file)

    raw_json_obj = {
        "id": 202,
        "fields": {
            "System.Title": "Fast search index verification",
            "System.WorkItemType": "User Story",
            "System.State": "Active",
            "System.IterationPath": "Project\\week-2637",
            "System.AssignedTo": {"displayName": "Alice Smith"}
        }
    }
    with cache._connection() as conn:
        conn.execute("INSERT OR REPLACE INTO projects (id, name) VALUES ('p1', 'P1')")
        conn.execute("""
            INSERT OR REPLACE INTO work_items (id, title, type, state, assigned_to, raw_json)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (202, "Fast search index verification", "User Story", "Active", "Alice Smith", json.dumps(raw_json_obj)))

    backend = DevOpsBackend()
    backend._db_path = db_file
    backend._cache_db = cache
    backend.refresh_all_data()

    assert len(backend._work_items) == 1
    wi = backend._work_items[0]
    assert "_search_text" in wi
    stext = wi["_search_text"]
    assert "202" in stext
    assert "fast search index verification" in stext
    assert "alice smith" in stext
    assert "user story" in stext

    # Test getWorkloadMatrix search filtering using _search_text
    matrix = backend.getWorkloadMatrix(search_query="Alice", horizon_weeks=8)
    assert matrix is not None
    assignees = [r["assignee"] for r in matrix.get("assignee_rows", [])]
    assert "Alice Smith" in assignees

    matrix_empty = backend.getWorkloadMatrix(search_query="NonExistentName")
    assert matrix_empty is not None
    assert len(matrix_empty.get("assignee_rows", [])) == 0


def test_fast_get_available_databases(tmp_path, monkeypatch):
    db_file = str(tmp_path / "tfs_cache_SampleProject.db")
    cache = AzureDevOpsCache(db_file)
    with cache._connection() as conn:
        conn.execute("INSERT OR REPLACE INTO projects (id, name) VALUES ('proj1', 'SampleProject')")

    backend = DevOpsBackend()
    monkeypatch.setattr(os, "getcwd", lambda: str(tmp_path))
    import devops_helper
    monkeypatch.setattr(devops_helper, "BASE_FOLDER", str(tmp_path))

    dbs = backend.get_available_databases()
    assert len(dbs) >= 1
    matched = [d for d in dbs if d["name"] == "tfs_cache_SampleProject.db"]
    assert len(matched) == 1
    assert matched[0]["project"] == "SampleProject"

    # Second call should use _db_scan_cache
    assert hasattr(backend, "_db_scan_cache")
    dbs2 = backend.get_available_databases()
    assert len(dbs2) == len(dbs)
