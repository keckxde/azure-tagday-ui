# Azure TagDay & DevOps Management UI

A modern desktop application and Python automation suite for Azure DevOps / TFS project management, Git repository tracking, Tag Day readiness auditing, build artifact storage monitoring, and automated document generation.

---

## Features

- **Desktop GUI (PySide6 / QML)**: Fast, modern UI with dark mode, real-time TFS sync, repository categorization, active pull request tracking, work item search, and artifact storage visualizer.
- **Tag Day Audits & Reporting**: Multi-view release readiness evaluation comparing repos against reference tags, analyzing unmerged branches, ahead/behind commit counts, and pull request activity.
- **Build & Artifact Storage Analytics**: Tracks build executions, container/file sizes, reclaimed space, and pipeline storage trends across SQLite databases.
- **Automated Documentation**: Generates `REVISION.md` / `REVISION.docx` tracking history and `BUILD_ARTIFACTS.md` / `BUILD_ARTIFACTS.csv` summaries.
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
```

---

## Running Tests

Execute the full automated unit test suite with `uv`:

```powershell
# Run all unit tests
uv run python -m unittest discover -s src/tests

# Or using the built-in runner script
uv run python src/tests/run_tests.py

# Run a specific test module
uv run python -m unittest src/tests/test_settings_and_project_switch.py
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
│   ├── generate_tagday_report.py    # Tag Day release audit reporter
│   └── utils.py                 # Core utilities & environment loaders
├── templates/                   # Jinja2 markdown report templates
├── pyproject.toml               # Project metadata and dependency definitions
└── uv.lock                      # Exact locked dependency versions
```
