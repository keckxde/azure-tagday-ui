# Python Backend & Toolchain Documentation (`src/`)

This directory contains the Python backend modules, PySide6 desktop GUI integration, CLI utilities, TFS/Azure DevOps data synchronization engine, and release tracking tools.

---

## 1. Architecture Overview

```text
src/
├── README.md               # This documentation
├── devops_helper.py        # CLI synchronization & document generation orchestrator
├── generate_artifacts_report.py # Build & artifact disk usage reporter
├── generate_revision.py    # REVISION.md and REVISION.docx generator
├── generate_tagday_report.py # Enhanced Tag Day release readiness auditor
├── utils.py                # Configuration loading and string/date helpers
├── requirements.txt        # Python dependency list
│
├── azure/                  # Azure DevOps / TFS Integration Package
│   ├── __init__.py         # Package exports
│   ├── azure_db.py         # SQLite cache engine (AzureDevOpsCache) & on-demand getters
│   ├── azure_info_handler.py # High-level domain client for TFS repositories/PRs/workitems
│   ├── azure_info_base_client.py # HTTP REST client communicating with Azure DevOps
│   ├── azure_base_client.py # Base HTTP client implementation
│   └── azure_helper.py     # Legacy helper and date parsing utilities
│
├── gui/                    # Desktop GUI (PySide6 / QML)
│   ├── __init__.py         # Package exports
│   ├── backend.py          # PySide6 backend controller & QObject bridge
│   ├── main.py             # Application bootstrap & QML engine loader
│   ├── workers.py          # Background worker threads
│   └── qml/                # QML views, components, and Theme
│
└── tests/                  # Unit Test Suite (unittest framework)
    ├── __init__.py         # Test package marker
    ├── run_tests.py        # Test runner script
    ├── test_utils.py       # Tests for utils.py (regex, dates, env, json)
    ├── test_azure_db.py    # Tests for SQLite schema, CRUD, builds, artifacts, views
    ├── test_azure_clients.py # Tests for AzureBaseClient and AzureInfoBaseClient
    ├── test_generate_revision.py # Tests for revision dates and version calculation
    ├── test_tagday_report.py # Tests for Tag Day report generation
    ├── test_reports.py     # Tests for artifact reports
    ├── test_sync_work_items.py # Tests for work item sync routines
    ├── test_pull_requests_view.py # Tests for PR filtering and database views
    ├── test_settings_and_project_switch.py # Tests for settings persistence & database switching
    └── test_backend_logging.py # Tests for logging captures
```

---

## 2. Python Packages & Modules

### `azure` Package (`src/azure/`)

Encapsulates all communication, data mapping, and local SQLite caching for Azure DevOps / TFS.

| Module | Primary Class / Functions | Description |
| :--- | :--- | :--- |
| [`azure_db.py`](azure/azure_db.py) | `AzureDevOpsCache`, `DateTimeEncoder` | SQLite database caching layer for repositories, branches, tags, submodules, pull requests, work items, builds, and artifacts. Supports on-demand lookups and multi-cache fallback. |
| [`azure_info_handler.py`](azure/azure_info_handler.py) | `AzureInfoHandler` | High-level domain client that queries project repositories, parses submodules (`.gitmodules`), aggregates tags/branches, and retrieves work items & pull requests. |
| [`azure_info_base_client.py`](azure/azure_info_base_client.py) | `AzureBaseClient` | Low-level REST API client handling Basic Authentication (PAT), SSL configuration, JSON encoding, and raw HTTP endpoints. |
| [`azure_base_client.py`](azure/azure_base_client.py) | `AzureBaseClient` | Base HTTP request implementation. |
| [`azure_helper.py`](azure/azure_helper.py) | `parse_iso_datetime`, `UpdateDateString` | Utility routines for parsing ISO 8601 timestamps and repo links. |

#### `AzureDevOpsCache` On-Demand Methods

Instead of loading entire databases into memory at once, `AzureDevOpsCache` provides on-demand querying:

- `get_pull_request(pr_id)`: Fetches PR metadata (`Title`, `repository`, `CreatedBy`, `Target`, `Status`), joined with repository URL.
- `get_work_item(work_item_id)`: Fetches work item metadata (`Title`, `State`, `WorkItemType`, `AssignedTo`).
- `get_repository(name_or_id)`: Fetches repository URL and metadata.
- `get_user(user_id)`: Extracts user display name.
- **Fallback Mechanism**: If an item is not found in the project's primary database (e.g. `tfs_cache_<PROJECT>.db`), it automatically searches sibling `*tfs_cache*.db` files and imports the missing record.

---

### `gui` Package (`src/gui/`)

Provides the desktop graphical interface using PySide6 (Qt for Python) and QML.

Launch shortcut:
```powershell
uv run gui
# or
uv run tagday-gui
```

| Module / Component | Description |
| :--- | :--- |
| [`main.py`](gui/main.py) | Application entrypoint (`main()`). Loads QML engine, connects logging, and registers `DevOpsBackend`. Supports `--test` smoke test mode. |
| [`backend.py`](gui/backend.py) | `DevOpsBackend` QObject bridging Python business logic, SQLite cache queries, TFS connection testing, settings persistence (`config/user_settings.yaml`), and async background tasks. |
| [`workers.py`](gui/workers.py) | Background `QThread` workers for asynchronous TFS sync and long-running report generation. |
| [`qml/`](gui/qml/) | Modern declarative UI containing navigation sidebar, dashboard, repos view, pull requests view, work items view, reports view, and settings dialogs. |

---

### Standalone Orchestrators & Utilities

#### `devops_helper.py`

The command-line interface and automation orchestrator for TFS data synchronization and document rendering.

```powershell
# Using uv (recommended)
uv run python src/devops_helper.py [OPTIONS]

# Or with python
python src/devops_helper.py [OPTIONS]
```

**Available Options:**

- `--sync`: Synchronizes pipelines, repositories, tags, branches, and work items from TFS into the local SQLite cache.
- `--force`: Bypasses the recent sync delay check and forces a re-query from TFS.
- `--templates`: Renders Markdown summary pages (`TAGDAY.md`) from Jinja2 templates using cached data.
- `--export-prs <OUTPUT_BASE>`: Exports pull requests grouped by repository and branch into `<OUTPUT_BASE>.xlsx` and `<OUTPUT_BASE>.md`.
- `--revision`: Triggers generation and update of `REVISION.md` and `REVISION.docx`.
- `--untagged-repos`: Lists all repositories whose latest PR is not closed or lacks a version tag.
- `--check-artefacts`: Queries and validates latest build artifacts across pipelines.
- `--report-artifacts`: Generates Markdown (`BUILD_ARTIFACTS.md`) and CSV (`BUILD_ARTIFACTS.csv`) reports analyzing build and artifact disk space usage.
- `--report-tagday`: Generates enhanced Tag Day report (`TAGDAY.md`) relative to reference tag baseline with PR summaries, unmerged branch tracking, global changes timeline, and per-repository walkthrough.

#### `generate_tagday_report.py`

Enhanced Tag Day report generator providing multi-view release readiness evaluation:

```powershell
uv run python src/generate_tagday_report.py [--db DB_PATH] [--output TAGDAY.md] [--reference-repo REPO] [--cutoff-tag TAG] [--project PROJ]
```

#### `generate_artifacts_report.py`

Analyzes build executions and artifact storage consumption from SQLite, generating:

1. **Markdown Wiki Report** (`doc/BUILD_ARTIFACTS.md`): Rendered in the Wiki with KPI cards, pipeline breakdowns, repo usage, top largest artifacts, and cleanup/retention recommendations.
2. **CSV Report** (`doc/BUILD_ARTIFACTS.csv`): Complete flat inventory with row-level metrics for external spreadsheet analysis.

```powershell
uv run python src/generate_artifacts_report.py [--db DB_PATH] [--md MD_PATH] [--csv CSV_PATH] [--no-seed]
```

#### `generate_revision.py`

- Parses cached repository release tags, commit dates, and pull requests.
- Generates the chronological release tracking document `REVISION.md`.
- Converts `REVISION.md` into formatted Word document `REVISION.docx` using `python-docx`.

#### `utils.py`

- `GetEnvVariable(name, default=None)`: Reads environment variables from `.env` or system environment, with logging warnings for mandatory values.
- `parse_iso_datetime(date_str)`: Normalizes ISO 8601 strings into naive UTC `datetime` objects.
- `UpdateDateString(date_val)`: Formats dates into unified `"%Y-%m-%d %H:%M:%S"`.
- `MatchUniqueRegularExpr(pattern, source)`: Deduplicated regex finder.

---

## 3. SQLite Cache Database Schema

The cache file is named `tfs_cache_<AZURE_PROJECT_ID>.db` (located at workspace root).

### Tables & Entities

- **`projects`**: Project IDs, names, and last sync timestamp.
- **`repositories`**: Repository IDs, names, default branches, web URLs, and raw TFS payload. References `projects(id)`.
- **`branches`**: Branch names, commit IDs, committer names, and ahead/behind counts. References `repositories(id)`.
- **`tags`**: Tag names, commit IDs, stable/unstable markers. References `repositories(id)`.
- **`submodules`**: Submodule mappings from `.gitmodules` files. References `repositories(id)` via `parent_repo_id`.
- **`pull_requests`**: PR ID, repo ID, title, status, source/target branches, authors, close dates, and `raw_json`. References `repositories(id)`.
- **`work_items`**: Work item ID, title, type, state, assigned user, change date, and `raw_json`.
- **`pipelines`**: Pipeline definition ID, name, folder path, revision, URL, and `raw_json`. References `projects(id)`.
- **`builds`**: Build execution ID, build number, status, result, queue/start/finish timestamps, source branch, commit version, requested by user, and `raw_json`. References `projects(id)`, `repositories(id)`, and `pipelines(id)`.
- **`artifacts`**: Build artifact ID and name, resource type (`Container`, `FilePath`), calculated size in bytes and megabytes, download/view URLs, `is_deleted` flag, `deleted_at` timestamp, and `raw_json`. References `builds(id)`.

### Relational Views

- **`v_branches`**: Branches joined with repository and project details.
- **`v_tags`**: Tags joined with repository and project details.
- **`v_pull_requests_tagged`**: Pull requests joined with repository, project, and matching release tag information.
- **`v_builds`**: Builds joined with repository, project, and pipeline definition details.
- **`v_artifacts`**: Artifacts joined with their parent build, repository, and project details (including `is_deleted` and `deleted_at`).

---

## 4. Configuration

Configuration is managed across `config/` YAML files and optional `.env`:

1. **`config/user_settings.yaml`**: Selected project, active database path, and recent databases.
2. **`config/repo_categories.yaml`**: Repository category definitions and badge colors.
3. **`config/status_icons.yaml`**: Status icon and badge formatting tokens.
4. **`.env`**: Optional Azure DevOps connection credentials and path defaults.

---

## 5. Unit Testing (`src/tests/`)

The unit test suite uses Python's standard `unittest` framework and is designed to execute quickly with zero configuration.

### Running the Tests with `uv`

```powershell
# Run the entire test suite
uv run python -m unittest discover -s src/tests

# Run using the test runner script
uv run python src/tests/run_tests.py

# Run an individual test file
uv run python -m unittest src/tests/test_settings_and_project_switch.py
```
