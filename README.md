# Azure TagDay & DevOps Management UI

A modern desktop application and Python automation suite for Azure DevOps / TFS project management, Git repository tracking, Tag Day readiness auditing, build artifact storage monitoring, and automated document generation.

---

## Features

- **Desktop GUI (PySide6 / QML)**: Fast, modern UI with dark mode, real-time TFS sync, repository categorization, active pull request tracking, work item search, and artifact storage visualizer.
- **Agile Weekly Sprint Reports**: Automated sprint reports for weekly iterations (`week-YYWW`), detailing velocity, completed vs active User Stories / Requirements, Bugs / Defects, and Technical Tasks with Markdown and CSV export.
- **Team Workload & Capacity Explorer**: Interactive calendar matrix visualizing team member workload across **4, 8, or 12 iterations** (1 month, 2 months, 1 quarter) with real-time capacity heatmap and item drill-down drawer.
- **Deadlines & Urgency Visualizer**: Automatic milestone deadline detection with visual urgency countdown badges (`🚨 Overdue`, `⏳ Due This Week`, `📅 Due Next Week`, `🔮 Upcoming`, `✓ Closed`).
- **Tag Day Audits & Reporting**: Multi-view release readiness evaluation comparing repos against reference tags, analyzing unmerged branches, ahead/behind commit counts, and pull request activity.
- **Build & Artifact Storage Analytics**: Tracks build executions, container/file sizes, reclaimed space, and pipeline storage trends across SQLite databases.
- **Automated Documentation**: Generates `REVISION.md` / `REVISION.docx` tracking history, `SPRINT_REPORT_<sprint>.md` / `.csv`, and `BUILD_ARTIFACTS.md` / `BUILD_ARTIFACTS.csv` summaries.
- **Local SQLite Caching**: Offline-first architecture caching repositories, branches, tags, PRs, work items, builds, and artifacts.

---

## Quick Start with `uv`

This project uses [`uv`](https://docs.astral.sh/uv/) for Python environment and dependency management.

### 1. Prerequisites

Install `uv` (if not already installed):

```powershell
# Windows (PowerShell)
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"

# Or via pip
pip install uv
```

### 2. Install Dependencies

Sync and install the project virtual environment automatically:

```powershell
uv sync
```

---

## Running the Application

### Launching the Desktop GUI

You can launch the GUI using the integrated shortcut:

```powershell
uv run gui
```

Or via direct script invocation:

```powershell
uv run python src/gui/main.py
```

To run a headless smoke test:

```powershell
uv run gui --test
```

### Running CLI Tools & Automation

All CLI tools can be run seamlessly using `uv run`:

```powershell
# Sync project data from Azure DevOps / TFS into local SQLite cache
uv run python src/devops_helper.py --sync

# Force fresh synchronization bypassing delay threshold
uv run python src/devops_helper.py --sync --force

# Generate the Tag Day release readiness report (TAGDAY.md)
uv run python src/devops_helper.py --report-tagday

# Generate build artifact storage reports (BUILD_ARTIFACTS.md & .csv)
uv run python src/devops_helper.py --report-artifacts

# Generate revision history document (REVISION.md and REVISION.docx)
uv run python src/devops_helper.py --revision

# Export pull requests to Excel and Markdown
uv run python src/devops_helper.py --export-prs PR_EXPORT

# Generate Agile weekly sprint report (Markdown & CSV)
uv run python src/generate_sprint_report.py --sprint week-2633

# Generate sprint report with custom output paths
uv run python src/generate_sprint_report.py --sprint week-2633 --out-md doc/SPRINT_2633.md --out-csv doc/SPRINT_2633.csv
```

---

## Agile Weekly Sprints, Workload & Deadlines

### 1. Sprint Naming & Date Math (`week-YYWW`)
In our agile workflow, sprints follow a **weekly sprint cycle** identified by ISO calendar year and week number (e.g. `week-2633` represents **Year 2026, Week 33**, running from Monday `2026-08-10` through Friday `2026-08-14`).
- Automatic date range resolution (`start_date`, `end_date`, user-friendly range labels).
- Supports standard `week-YYWW`, `week_YYWW`, `sprint-YYWW`, and nested iteration paths like `Project\week-2633`.

### 2. Timeframe Reports (Markdown & CSV)
- **KPI Metrics**: Total Work Items, Stories/Requirements, Bugs/Defects, Technical Tasks, Completed vs Active counts, and overall Velocity completion rate (%).
- **Functional Breakdown**: Dedicated sections grouping User Stories / Requirements, Bugs Handled, and Tasks with linked PR counts.
- **Team Contribution**: Workload table listing total assigned items, stories, bugs, tasks, and completion rate per engineer.
- **Export**: Exports to GitHub-flavored Markdown wiki (`SPRINT_REPORT_<sprint>.md`) and flat semicolon-delimited CSV (`SPRINT_REPORT_<sprint>.csv`).
- **Interactive UI**: Integrated into the GUI under **Reports & Analytics ➔ 🚀 Sprint Report**.

### 3. Interactive Workload & Capacity Explorer
Accessible from the sidebar navigation (**👥 Workload Explorer**):
- **Horizon Switcher**: Toggle across **4 Sprints (1 Month)**, **8 Sprints (2 Months)**, and **12 Sprints (1 Quarter)**.
- **Heatmap Capacity Matrix**: Grid showing each team member (with avatar and total workload) against chronological sprint columns.
- **Visual Breakdown**: Cells indicate total count, stories (`🎯`), bugs (`🐛`), and overdue warnings (`🚨`), color-coded by workload density.
- **Interactive Drill-Down**: Click on any cell to open a slideout drawer displaying the full list of assigned work items with status badges, countdown urgency pills, and direct TFS links.

### 4. Deadlines & Urgency Visualizer
- Automatically resolves work item deadlines from `TargetDate`, `FinishDate`, `DueDate`, or falls back to the sprint Friday milestone date.
- **Dynamic Urgency Badges**:
  - `🚨 <N>d Overdue`: Highlighted in red when the milestone is in the past.
  - `⏳ <N>d left` / `⚡ Due Today`: Highlighted in amber when due within 7 days.
  - `📅 Next Wk (Mmm DD)`: Highlighted in blue when due within 8–14 days.
  - `🔮 Mmm DD`: Neutral indicator for future deadlines.
  - `✓ Closed`: Green completed badge.
- **Table Filters**: Filter by `🚨 Overdue`, `⏳ Due This Week`, `📅 Due Next Week`, and `🔮 Upcoming` in **Work Items**.

---

## Running Tests

Execute the full automated unit test suite with `uv`:

```powershell
# Run all unit tests
uv run python -m unittest discover -s src/tests

# Or using the built-in runner script
uv run python src/tests/run_tests.py

# Run sprint and deadline tests specifically
uv run python -m unittest src/tests/test_sprint_workload_and_deadlines.py
```

---

## Building Executables & Installers

### 1. One-Click Build (Executable + Setup Installer + Wheel)

Run the automated build orchestrator:

```powershell
uv run python build_installer.py
```

This script will automatically:
1. Compile the PyInstaller bundle in `dist/azure-tagday-ui/`.
2. Compile the Windows Setup installer (`dist/AzureTagDayUI-Setup-0.1.0.exe`) using **NSIS** or **Inno Setup**.
3. Build the distributable Python wheel and source distribution (`dist/*.whl`, `dist/*.tar.gz`).

---

### 2. Standalone Desktop Executable (PyInstaller)

To compile the application bundle directly:

```powershell
uv run pyinstaller --noconfirm azure-tagday-ui.spec
```

The output executable and bundled resources will be generated under:
`dist/azure-tagday-ui/azure-tagday-ui.exe`

To smoke-test the built executable:
```powershell
.\dist\azure-tagday-ui\azure-tagday-ui.exe --test
```

---

### 3. Windows System Installer (NSIS / Inno Setup)

The project includes two pre-configured installer scripts:

- **NSIS**: [`installer.nsi`](installer.nsi)
  ```powershell
  & "C:\Program Files (x86)\NSIS\makensis.exe" installer.nsi
  ```
  Produces `dist/AzureTagDayUI-Setup-0.1.0.exe` with desktop shortcut, Start Menu items, and Windows Uninstaller registration.

- **Inno Setup**: [`installer.iss`](installer.iss)
  ```powershell
  & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
  ```
  Produces `dist/AzureTagDayUI-InnoSetup-0.1.0.exe`.

---

### 4. Distributable Python Packages (Wheel & Source Distribution)

To build standard `.whl` and `.tar.gz` packages:

```powershell
uv build
```

The installable wheel can be installed into any environment via:
```powershell
pip install dist/azure_tagday_ui-0.1.0-py3-none-any.whl
```



---

## Configuration

Configuration files are centrally managed in the top-level [`config/`](config/) folder and optional root `.env`:

### 1. `config/user_settings.yaml`

Stores the active database connection, project selection, and recent databases:

```yaml
db_path: C:\path\to\tfs_cache_MY_PROJECT.db
project_id: MY_PROJECT
project_name: MY_PROJECT
recent_databases:
  - C:\path\to\tfs_cache_MY_PROJECT.db
```

### 2. `config/repo_categories.yaml`

Maps repository names or prefixes to logical functional categories and display badge colors.

### 3. `config/status_icons.yaml`

Configures status indicator emojis, badge styles, and visual icon tokens.

### 4. Optional `.env` File

For headless/CLI sync, create a `.env` in the repository root:

```ini
AZURE_BASE_URL=https://tfs.example.local:8080/tfs
AZURE_COLLECTION=DefaultCollection
AZURE_PERSONAL_ACCESS_TOKEN=your_pat_token
AZURE_PROJECT_ID=MY_PROJECT
```

---

## Project Structure

```text
├── config/                      # Application and reporting configuration
│   ├── repo_categories.yaml     # Repository category definitions & colors
│   ├── status_icons.yaml        # Status badge & icon mappings
│   └── user_settings.yaml       # User database and project preferences (gitignored)
├── src/
│   ├── azure/                   # Azure DevOps REST client & SQLite cache layer
│   │   ├── azure_base_client.py # HTTP transport & authentication
│   │   ├── azure_db.py          # SQLite database engine (AzureDevOpsCache)
│   │   ├── azure_helper.py      # Timestamp formatting and date helpers
│   │   ├── azure_info_base_client.py # Low-level TFS REST client
│   │   └── azure_info_handler.py     # High-level domain aggregator
│   ├── gui/                     # Desktop GUI application
│   │   ├── backend.py           # PySide6 backend controller & QObject bridge
│   │   ├── main.py              # Application bootstrap & QML engine loader
│   │   ├── workers.py           # Background sync threads
│   │   └── qml/                 # QML views, components, and Theme
│   ├── tests/                   # Unit test suite
│   ├── devops_helper.py         # CLI orchestrator
│   ├── generate_artifacts_report.py # Build & artifact disk usage reporter
│   ├── generate_revision.py     # REVISION.md / .docx document generator
│   ├── generate_sprint_report.py # Agile weekly sprint & timeframe reporter
│   ├── generate_tagday_report.py    # Tag Day release audit reporter
│   └── utils.py                 # Core utilities & environment loaders
├── templates/                   # Jinja2 markdown report templates
├── pyproject.toml               # Project metadata and dependency definitions
└── uv.lock                      # Exact locked dependency versions
```
