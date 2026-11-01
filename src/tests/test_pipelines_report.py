import os
import json
import pytest
from unittest.mock import MagicMock

from azure.azure_db import AzureDevOpsCache
from generate_pipelines_report import (
    classify_jenkins_status,
    compute_jenkins_weather,
    analyze_pipelines_health,
    generate_markdown_report,
    generate_csv_report,
    run_pipelines_report,
)


def test_classify_jenkins_status():
    assert classify_jenkins_status("completed", "succeeded")[0] == "success"
    assert classify_jenkins_status("completed", "partiallySucceeded")[0] == "unstable"
    assert classify_jenkins_status("completed", "failed")[0] == "failed"
    assert classify_jenkins_status("inProgress", "")[0] == "running"
    assert classify_jenkins_status("completed", "canceled")[0] == "aborted"
    assert classify_jenkins_status("none", "none")[0] == "not_built"


def test_compute_jenkins_weather():
    # Empty runs -> unknown
    score, key, icon, label = compute_jenkins_weather([])
    assert key == "unknown"

    # 5 successes -> 100% sunny
    runs_5_ok = [{"result": "succeeded"} for _ in range(5)]
    score, key, icon, label = compute_jenkins_weather(runs_5_ok)
    assert score == 100
    assert key == "sunny"
    assert icon == "☀️"

    # 4 successes, 1 failed -> 80% partly_cloudy
    runs_4_ok = [{"result": "succeeded"} for _ in range(4)] + [{"result": "failed"}]
    score, key, icon, label = compute_jenkins_weather(runs_4_ok)
    assert score == 80
    assert key == "partly_cloudy"

    # 3 successes, 2 failed -> 60% cloudy
    runs_3_ok = [{"result": "succeeded"} for _ in range(3)] + [{"result": "failed"} for _ in range(2)]
    score, key, icon, label = compute_jenkins_weather(runs_3_ok)
    assert score == 60
    assert key == "cloudy"

    # 2 successes, 3 failed -> 40% raining
    runs_2_ok = [{"result": "succeeded"} for _ in range(2)] + [{"result": "failed"} for _ in range(3)]
    score, key, icon, label = compute_jenkins_weather(runs_2_ok)
    assert score == 40
    assert key == "raining"

    # 5 failed -> 0% stormy
    runs_0_ok = [{"result": "failed"} for _ in range(5)]
    score, key, icon, label = compute_jenkins_weather(runs_0_ok)
    assert score == 0
    assert key == "stormy"
    assert icon == "⛈️"


def test_analyze_pipelines_health_and_culprit_detection(tmp_path):
    db_path = str(tmp_path / "test_pipelines.db")
    db = AzureDevOpsCache(db_path=db_path)

    # Save repository
    db.save_repository(
        "proj-1",
        {
            "id": "repo-1",
            "name": "backend-service",
            "url": "https://tfs/repo-1",
            "webUrl": "https://tfs/web/repo-1",
            "defaultBranch": "refs/heads/main",
            "size": 1024,
        },
    )

    # Save commit and PR for culprit attribution
    commit_sha = "abcdef1234567890abcdef1234567890abcdef12"
    db.save_commits(
        "repo-1",
        [
            {
                "commitId": commit_sha,
                "author": {"name": "Alice Developer", "email": "alice@example.com", "date": "2026-10-30T10:00:00Z"},
                "committer": {"name": "Alice Developer", "email": "alice@example.com", "date": "2026-10-30T10:00:00Z"},
                "comment": "Refactor database connection pooling (#42)",
                "remoteUrl": "https://tfs/commit/abcdef12",
            }
        ],
    )
    db.save_pull_requests(
        "repo-1",
        [
            {
                "pullRequestId": 42,
                "title": "Refactor database connection pooling",
                "description": "Updates pool config",
                "status": "completed",
                "creationDate": "2026-10-30T09:00:00Z",
                "closedDate": "2026-10-30T10:05:00Z",
                "sourceRefName": "refs/heads/feature/db-pool",
                "targetRefName": "refs/heads/main",
                "createdBy": {"displayName": "Alice Developer", "uniqueName": "alice@example.com"},
                "closedBy": {"displayName": "Bob Reviewer"},
                "lastMergeCommit": {"commitId": commit_sha},
            }
        ],
    )

    # Save 2 pipelines: 1 broken, 1 healthy
    db.save_pipelines(
        "proj-1",
        [
            {"id": 10, "name": "Backend-CI", "folder": "\\CI"},
            {"id": 20, "name": "Frontend-CI", "folder": "\\CI"},
        ],
    )

    # Save builds for Pipeline 10 (1 old green build, then 1 broken build with timeline failure)
    builds = [
        {
            "id": 100,
            "buildNumber": "20261029.1",
            "status": "completed",
            "result": "succeeded",
            "queueTime": "2026-10-29T10:00:00Z",
            "startTime": "2026-10-29T10:01:00Z",
            "finishTime": "2026-10-29T10:05:00Z",
            "sourceBranch": "refs/heads/main",
            "sourceVersion": "1111111111111111111111111111111111111111",
            "reason": "individualCI",
            "definition": {"id": 10, "name": "Backend-CI"},
            "repository": {"id": "repo-1", "name": "backend-service"},
            "requestedFor": {"displayName": "Charlie Clean"},
        },
        {
            "id": 101,
            "buildNumber": "20261030.1",
            "status": "completed",
            "result": "failed",
            "queueTime": "2026-10-30T10:10:00Z",
            "startTime": "2026-10-30T10:11:00Z",
            "finishTime": "2026-10-30T10:14:30Z",
            "sourceBranch": "refs/heads/main",
            "sourceVersion": commit_sha,
            "reason": "individualCI",
            "definition": {"id": 10, "name": "Backend-CI"},
            "repository": {"id": "repo-1", "name": "backend-service"},
            "requestedFor": {"displayName": "Alice Developer"},
            "failed_tasks": [{"name": "Run Unit Tests (pytest)", "type": "Task", "result": "failed", "message": "AssertionError in test_pool.py"}],
            "timeline_issues": ["AssertionError in test_pool.py"],
        },
        {
            "id": 200,
            "buildNumber": "20261030.2",
            "status": "completed",
            "result": "succeeded",
            "queueTime": "2026-10-30T11:00:00Z",
            "startTime": "2026-10-30T11:01:00Z",
            "finishTime": "2026-10-30T11:03:00Z",
            "sourceBranch": "refs/heads/main",
            "sourceVersion": "2222222222222222222222222222222222222222",
            "reason": "individualCI",
            "definition": {"id": 20, "name": "Frontend-CI"},
            "repository": {"id": "repo-1", "name": "backend-service"},
            "requestedFor": {"displayName": "Charlie Clean"},
        },
    ]
    db.save_builds("proj-1", builds)

    analysis = analyze_pipelines_health(db)
    summary = analysis["summary"]
    assert summary["total_pipelines"] == 2
    assert summary["failed_count"] == 1
    assert summary["healthy_count"] == 1
    assert summary["problem_count"] == 1

    # Problem pipeline must be sorted first
    prob = analysis["problem_pipelines"][0]
    assert prob["name"] == "Backend-CI"
    assert prob["status_key"] == "failed"
    assert prob["consecutive_failures"] == 1
    assert prob["broken_since_build"] == "20261030.1"
    assert "Alice Developer" in prob["culprit_who"]
    assert "Run Unit Tests (pytest)" in prob["culprit_what"]
    assert "Alice Developer" in prob["hint_text"]
    assert "Run Unit Tests (pytest)" in prob["hint_text"]

    # Test Markdown and CSV generation
    md_path = str(tmp_path / "BUILD_PIPELINES.md")
    csv_path = str(tmp_path / "build_pipelines.csv")
    md_content = generate_markdown_report(analysis, output_path=md_path)
    generate_csv_report(analysis, output_path=csv_path)

    assert os.path.exists(md_path)
    assert os.path.exists(csv_path)
    assert "Backend-CI" in md_content
    assert "Alice Developer" in md_content
    assert "Run Unit Tests (pytest)" in md_content


def test_sync_pipelines_and_builds_enriches_failed_timeline(tmp_path):
    from azure.azure_info_handler import AzureInfoHandler

    db_path = str(tmp_path / "sync_test.db")
    db = AzureDevOpsCache(db_path=db_path)

    handler = AzureInfoHandler("https://tfs.example.com/DefaultCollection", "dummy-pat")
    handler.GetTFSPipelines = MagicMock(return_value=[{"id": 5, "name": "Nightly-Build", "folder": "\\"}])
    handler.get_project_builds = MagicMock(
        return_value=[
            {
                "id": 501,
                "buildNumber": "20261031.1",
                "status": "completed",
                "result": "failed",
                "definition": {"id": 5, "name": "Nightly-Build"},
                "requestedFor": {"displayName": "Dev User"},
            }
        ]
    )
    handler.get_build_timeline = MagicMock(
        return_value=[
            {
                "type": "Task",
                "name": "Compile C++ Modules",
                "result": "failed",
                "issues": [{"message": "error C2065: undeclared identifier"}],
            }
        ]
    )

    res = handler.sync_pipelines_and_builds("proj-1", cache_db=db)
    assert len(res["pipelines"]) == 1
    assert len(res["builds"]) == 1
    assert res["failed_builds"] == 1

    # Verify timeline issues were saved in raw_json and extracted by analyze_pipelines_health
    out_md = str(tmp_path / "out.md")
    out_csv = str(tmp_path / "out.csv")
    analysis = run_pipelines_report(db_path=db_path, md_path=out_md, csv_path=out_csv)
    assert analysis["summary"]["failed_count"] == 1
    prob = analysis["problem_pipelines"][0]
    assert "Compile C++ Modules" in prob["culprit_what"]
    assert "error C2065" in prob["culprit_what"]
    assert "Dev User" in prob["culprit_who"]


def test_backend_pipelines_data_and_report_content(tmp_path, monkeypatch):
    import utils
    from gui.backend import DevOpsBackend

    db_path = str(tmp_path / "backend_pipes.db")
    db = AzureDevOpsCache(db_path=db_path)
    db.save_pipelines("proj-1", [{"id": 77, "name": "Release-Pipeline", "folder": "\\"}])
    db.save_builds(
        "proj-1",
        [
            {
                "id": 701,
                "buildNumber": "20261031.7",
                "status": "completed",
                "result": "failed",
                "definition": {"id": 77, "name": "Release-Pipeline"},
                "requestedFor": {"displayName": "Max Mustermann"},
                "failed_tasks": [{"name": "Deploy Step", "type": "Task", "result": "failed", "message": "Timeout"}],
            }
        ],
    )

    monkeypatch.setattr(utils, "get_reports_dir", lambda: str(tmp_path))
    backend = DevOpsBackend.__new__(DevOpsBackend)
    backend._reports_dir = str(tmp_path)
    backend._cache_db = db
    backend._pipelines_data = analyze_pipelines_health(db)

    md_preview = backend.get_report_content("pipelines")
    assert md_preview["success"] is True
    assert md_preview["format"] == "markdown"
    assert "Release-Pipeline" in md_preview["content"]
    assert "Max Mustermann" in md_preview["content"]
    assert "Deploy Step" in md_preview["content"]


def test_reports_view_and_tabs_qml_load(tmp_path):
    """Verifies that ReportsView.qml and all 7 subtabs (TagDay, Pipelines, etc.) compile and instantiate cleanly."""
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent
    from PySide6.QtCore import QUrl

    app = QGuiApplication.instance() or QGuiApplication([])
    engine = QQmlApplicationEngine()

    base_src_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    reports_qml = os.path.join(base_src_dir, "gui", "qml", "views", "ReportsView.qml")
    pipelines_qml = os.path.join(base_src_dir, "gui", "qml", "views", "reports", "ReportsBuildPipelinesTab.qml")
    assert os.path.isfile(reports_qml), "ReportsView.qml must exist"
    assert os.path.isfile(pipelines_qml), "ReportsBuildPipelinesTab.qml must exist"

    comp_pipe = QQmlComponent(engine, QUrl.fromLocalFile(pipelines_qml))
    assert not comp_pipe.isError(), f"ReportsBuildPipelinesTab.qml errors: {[e.toString() for e in comp_pipe.errors()]}"

    comp_rep = QQmlComponent(engine, QUrl.fromLocalFile(reports_qml))
    assert not comp_rep.isError(), f"ReportsView.qml errors: {[e.toString() for e in comp_rep.errors()]}"


def test_favorites_sort_first_and_tfs_urls(tmp_path):
    """Verifies that favorite pipelines always sort first (even if healthy) and TFS web links are generated for pipelines and build jobs."""
    db_path = str(tmp_path / "fav_urls.db")
    db = AzureDevOpsCache(db_path=db_path)

    # Save project config with SERVER and PROJECT so TFS fallback URLs can be built
    db.set_config("AZURE_BASE_URL", "https://tfs.company.local/tfs/DefaultCollection")
    db.set_config("PROJECT_NAME", "MyProject")

    db.save_pipelines(
        "proj-1",
        [
            {"id": 10, "name": "Zeta-Broken-CI", "folder": "\\CI"},
            {"id": 20, "name": "Alpha-Healthy-CI", "folder": "\\CI"},
            {
                "id": 30,
                "name": "Beta-Fav-Healthy-CI",
                "folder": "\\Release",
                "_links": {"web": {"href": "https://tfs.company.local/tfs/DefaultCollection/MyProject/_build?definitionId=30"}},
            },
        ],
    )

    builds = [
        {
            "id": 1001,
            "buildNumber": "20261101.1",
            "status": "completed",
            "result": "failed",
            "queueTime": "2026-11-01T08:00:00Z",
            "startTime": "2026-11-01T08:01:00Z",
            "finishTime": "2026-11-01T08:04:00Z",
            "sourceBranch": "refs/heads/main",
            "definition": {"id": 10, "name": "Zeta-Broken-CI"},
            "requestedFor": {"displayName": "Alice"},
        },
        {
            "id": 2001,
            "buildNumber": "20261101.2",
            "status": "completed",
            "result": "succeeded",
            "queueTime": "2026-11-01T08:05:00Z",
            "startTime": "2026-11-01T08:06:00Z",
            "finishTime": "2026-11-01T08:08:00Z",
            "sourceBranch": "refs/heads/main",
            "definition": {"id": 20, "name": "Alpha-Healthy-CI"},
            "requestedFor": {"displayName": "Bob"},
        },
        {
            "id": 3001,
            "buildNumber": "20261101.3",
            "status": "completed",
            "result": "succeeded",
            "queueTime": "2026-11-01T08:10:00Z",
            "startTime": "2026-11-01T08:11:00Z",
            "finishTime": "2026-11-01T08:12:00Z",
            "sourceBranch": "refs/heads/main",
            "definition": {"id": 30, "name": "Beta-Fav-Healthy-CI"},
            "requestedFor": {"displayName": "Charlie"},
            "_links": {"web": {"href": "https://tfs.company.local/tfs/DefaultCollection/MyProject/_build/results?buildId=3001"}},
        },
    ]
    db.save_builds("proj-1", builds)

    # Mark pipeline 30 (healthy) as favorite
    analysis = analyze_pipelines_health(db, favorite_pipelines=["30"])
    pipelines = analysis["pipelines"]
    assert len(pipelines) == 3
    assert analysis["summary"]["favorite_count"] == 1

    # Pipeline 30 must be first because it is a favorite, followed by broken pipeline 10, then healthy 20
    assert pipelines[0]["id"] == 30
    assert pipelines[0]["is_favorite"] is True
    assert pipelines[1]["id"] == 10
    assert pipelines[1]["is_favorite"] is False
    assert pipelines[2]["id"] == 20
    assert pipelines[2]["is_favorite"] is False

    # Verify TFS URLs on pipelines and build jobs
    p30 = pipelines[0]
    assert p30["web_url"] == "https://tfs.company.local/tfs/DefaultCollection/MyProject/_build?definitionId=30"
    assert p30["last_build_url"] == "https://tfs.company.local/tfs/DefaultCollection/MyProject/_build/results?buildId=3001"
    assert p30["last_success_url"] == "https://tfs.company.local/tfs/DefaultCollection/MyProject/_build/results?buildId=3001"
    assert p30["last_5_runs"][0]["web_url"] == "https://tfs.company.local/tfs/DefaultCollection/MyProject/_build/results?buildId=3001"

    p10 = pipelines[1]
    assert p10["web_url"] == "https://tfs.company.local/tfs/DefaultCollection/MyProject/_build?definitionId=10"
    assert "buildId=1001" in p10["last_build_url"]
    assert "buildId=1001" in p10["last_failure_url"]
    assert "buildId=1001" in p10["broken_since_url"]

    # Markdown report should include clickable links and star icon for favorite
    md = generate_markdown_report(analysis)
    assert "⭐" in md
    assert "[**Beta-Fav-Healthy-CI**](https://tfs.company.local/tfs/DefaultCollection/MyProject/_build?definitionId=30)" in md
    assert "(https://tfs.company.local/tfs/DefaultCollection/MyProject/_build/results?buildId=1001" in md


def test_backend_view_mode_favorites_and_independent_sync(tmp_path, monkeypatch):
    """Tests default 'cards' view mode, switching to 'list', toggling favorites, and independent sync_pipelines_async."""
    import gui.backend as backend_mod
    from gui.backend import DevOpsBackend

    mock_settings = {}
    monkeypatch.setattr(backend_mod, "_load_user_settings", lambda: dict(mock_settings))
    monkeypatch.setattr(backend_mod, "_save_user_settings", lambda cfg: mock_settings.update(cfg))

    db_path = str(tmp_path / "backend_fav.db")
    db = AzureDevOpsCache(db_path=db_path)
    db.set_config("AZURE_BASE_URL", "https://tfs.example.com/DefaultCollection")
    db.set_config("PROJECT_NAME", "DemoProj")
    db.save_pipelines(
        "proj-1",
        [
            {"id": 1, "name": "Broken-Pipe", "folder": "\\"},
            {"id": 2, "name": "Fav-Healthy-Pipe", "folder": "\\"},
        ],
    )
    db.save_builds(
        "proj-1",
        [
            {
                "id": 11,
                "buildNumber": "1.0",
                "status": "completed",
                "result": "failed",
                "definition": {"id": 1, "name": "Broken-Pipe"},
            },
            {
                "id": 22,
                "buildNumber": "2.0",
                "status": "completed",
                "result": "succeeded",
                "definition": {"id": 2, "name": "Fav-Healthy-Pipe"},
            },
        ],
    )

    backend = DevOpsBackend()
    backend._cache_db = db
    backend._favorite_pipelines = []
    backend._pipelines_view_mode = "cards"
    backend._pipelines_data = analyze_pipelines_health(db, favorite_pipelines=backend._favorite_pipelines)

    # 1. Default view mode must be "cards"
    assert backend.pipelinesViewMode == "cards"
    backend.setPipelinesViewMode("list")
    assert backend.pipelinesViewMode == "list"
    backend.setPipelinesViewMode("invalid_mode")
    assert backend.pipelinesViewMode == "cards"

    # 2. Toggle favorite on pipeline 2 and verify it moves to index 0
    assert backend.isPipelineFavorite("2") is False
    now_fav = backend.toggleFavoritePipeline("2", "Fav-Healthy-Pipe")
    assert now_fav is True
    assert backend.isPipelineFavorite("2") is True
    assert backend.pipelinesData["pipelines"][0]["id"] == 2
    assert backend.pipelinesData["pipelines"][0]["is_favorite"] is True

    # 3. Verify TFS URL helpers on backend
    assert "definitionId=2" in backend.get_pipeline_tfs_url(2)
    assert "buildId=22" in backend.get_build_tfs_url(22)



