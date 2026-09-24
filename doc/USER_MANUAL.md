# DevOps Manager & Azure TagDay UI - User Manual

A comprehensive guide to configuring, operating, and automating the **Azure TagDay & DevOps Management UI** desktop application and automation toolset.

---

## Table of Contents

1. [Introduction & System Architecture](#1-introduction--system-architecture)
2. [Getting Started & Project Connection](#2-getting-started--project-connection)
3. [Repositories Management & Categorization](#3-repositories-management--categorization)
4. [Work Items & Agile Planning](#4-work-items--agile-planning)
5. [Team Workload & Capacity Explorer](#5-team-workload--capacity-explorer)
6. [Pull Request Tracking & Review](#6-pull-request-tracking--review)
7. [Tag Day Release Audits & Reporting](#7-tag-day-release-audits--reporting)
8. [Change Notification & Tag Day Filters](#8-change-notification--tag-day-filters)
9. [Build Artifacts & Storage Analytics](#9-build-artifacts--storage-analytics)
10. [Application Settings & Customization](#10-application-settings--customization)
11. [CLI Automation & Scripting Reference](#11-cli-automation--scripting-reference)
12. [Troubleshooting & FAQs](#12-troubleshooting--faqs)

---

## 1. Introduction & System Architecture

**DevOps Manager** is a desktop client built with **PySide6 (Qt Quick / QML)** and Python designed for multi-repository Azure DevOps (TFS) ecosystems.

```
┌─────────────────────────────────────────────────────────────┐
│                    DevOps Manager GUI                       │
│        (PySide6 / QML Dark Mode Desktop Interface)          │
└──────────────────────────────┬──────────────────────────────┘
                               │
               ┌───────────────┴───────────────┐
               ▼                               ▼
┌──────────────────────────────┐ ┌──────────────────────────────┐
│     Local SQLite Cache       │ │    Azure DevOps / TFS API    │
│  (tfs_cache_<PROJECT>.db)    │ │   (REST API, WIQL, Git)      │
│  - Repositories & Branches   │ └───────────────▲──────────────┘
│  - Tags & Pull Requests      │                 │
│  - Work Items & Shifts       │                 │ Fast Delta Sync
│  - Configuration & Filters   │◄────────────────┘ (WIQL ChangedDate)
└──────────────────────────────┘
```

### Key Architectural Benefits

- **Offline-First SQLite Cache**: Full browsing, search, capacity analysis, and report generation work offline without network lag.
- **Fast Delta Sync**: Synchronizes only modified work items and active git updates using TFS WIQL queries with `[System.ChangedDate]`.
- **Zero Configuration Fallback**: Project credentials and options are stored locally within the active database's `project_config` table.

---

## 2. Getting Started & Project Connection

### Launching the Application

Using [`uv`](https://docs.astral.sh/uv/):

```powershell
uv run azure-tagday-ui
```

Or with standard Python:

```powershell
python src/gui/main.py
```

### Connecting to a TFS / Azure DevOps Project

1. Navigate to **Settings** (gear icon in sidebar).
2. Click **➕ Connect New Project...** in the top right.
3. Fill in the connection parameters:
   - **TFS Server Base URL**: (e.g. `http://tfs.company.local:8080/tfs` or `https://dev.azure.com/org`)
   - **Collection**: (e.g. `DefaultCollection`)
   - **Project Name / Identifier**: (e.g. `MY_PROJECT`)
   - **Personal Access Token (PAT)**: Optional, for authenticated remote queries.
   - **SQLite Database Path**: Default is `tfs_cache_<PROJECT>.db`.
4. Click **Connect & Sync**. The application will initialize the cache, create database schemas, and begin initial data download.

### Switching Active Databases

All `.db` files located in your workspace are automatically discovered in **Settings → Discovered Databases in Workspace**. Click **Switch** next to any database to immediately swap the active workspace context without restarting.

---

## 3. Repositories Management & Categorization

The **Repositories** view provides a high-level inventory of all git repositories tracked in the project.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Repositories (42 repos • 7 pending)     [🏷️ Category Settings] [↻ Refresh]  │
├─────────────────────────────────────────────────────────────────────────────┤
│ [⚠️ PENDING (7)] [ALL] [CORE] [CORE APPS] [GENERIC] [BUILD & SCRIPTS] ...   │
├─────────────────────────────────────────────────────────────────────────────┤
│ REPOSITORY          CATEGORY    LATEST TAG    STABLE TAG    PENDING STATUS   │
│ repo-core-engine    CORE        v01.02.2632   v01.02.2632   Up to date       │
│ repo-app-client     CORE APPS   v01.01.2630   v01.01.2630   2 untagged PRs   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Category Filter Bar & Wrapping Layout

- **Dedicated Filter Row**: Category filter chips are rendered on their own dedicated line below the toolbar using a wrapping `Flow` layout.
- **Responsive Wrapping**: If your project defines numerous or long category names, chips wrap gracefully across multiple lines without overflowing the screen.
- **`⚠️ PENDING` Filter & Ignored Pattern Rules**: Instantly filters the list to show only repositories that have untagged pull requests, active PRs in review, or unmerged feature branches. Repositories whose category **or repository name** matches configured *Repository Category Filters* (e.g. `*deprecated*`) are automatically excluded from the pending count and pending status.

### Managing Categories & Prefix Rules

Click **🏷️ Category Settings** to open the management dialog:

1. **Categories Tab**: Create custom category names (e.g. `CORE`, `GENERIC`, `3RDPARTY`), define custom hex colors, background badges, and sort priority.
2. **Prefix Rules Tab**: Define automatic prefix matching rules (e.g. `generic-*` → `GENERIC`, `3rdparty-*` → `3RDPARTY`).
3. **Explicit Overrides Tab**: Assign specific repositories to categories regardless of naming conventions.

---

## 4. Work Items & Agile Planning

The **Work Items** view provides hierarchical inspection of User Stories, Requirements, Bugs, Defects, and Technical Tasks.

### Collapsible Filter Panel & Focus Mode

- **Collapse / Expand Toggle**: Use the **`🔼 Hide Filters` / `🔽 Filters`** button in the top toolbar to toggle the filter panel. Collapsing the filters maximizes vertical space so you can focus entirely on the work items table.
- **Active Filter Strip**: When filters are collapsed but active criteria remain applied, a compact blue summary strip is displayed above the table showing active filters (e.g. `State`, `Sprint`, `Milestone`, `User`) along with quick **`Show Filters`** and **`Reset All`** buttons.
- **Strict Table Column Bounds**: The Title column flexibly expands with elided badges and text clipping, ensuring the table never overflows horizontally regardless of window size or long badge names.

### Filtering & Search

- **Multi-Field Search**: Real-time substring search across IDs, titles, assignees, and descriptions.
- **Two-Step Tag Filtering**: Select a tag category first (e.g. `Milestone`, `PBS`, `Software Revision`), then pick the specific tag.
- **Urgency Badges**:
  - `🚨 Overdue`: Due date has passed and the item remains open.
  - `⏳ Due This Week`: Target date falls within the current calendar week.
  - `📅 Due Next Week`: Scheduled for completion next week.
  - `🔮 Upcoming`: Due in future sprints.
  - `✓ Closed`: Completed item.

### Inline Deadline Editing

Click on any work item's deadline badge or date field to adjust its target milestone date or assign a deadline directly from the UI. Changes are recorded in the local cache and surfaced in timeline metrics.

---

## 5. Team Workload & Capacity Explorer

The **Workload Explorer** view visualizes team workload distribution across upcoming weekly iterations (`week-YYWW`).

### Horizon Selection

Toggle between planning horizons:

- **4 Iterations (1 Month)**: Granular weekly sprint execution.
- **8 Iterations (2 Months)**: Mid-term milestone planning.
- **12 Iterations (1 Quarter)**: Quarterly capacity and release readiness.

### Capacity Heatmap & Drill-Down

- **Heatmap Indicators**: Green (normal load), Yellow (near capacity), Red (over-allocated).
- **Drill-down Drawer**: Click on any team member's cell to open the drill-down inspector showing specific assigned work items, effort hours, and dependencies.

### Bug Hierarchy Modes

In **Settings → Bug Hierarchy & Workload Container Grouping**, choose how Bugs are treated:

1. **Bugs as Stories (Containers)**: Bugs are top-level backlog items that contain child tasks (recommended for Scrum).
2. **Bugs as Tasks (Child Items)**: Bugs belong directly to parent User Stories or Requirements.

---

## 6. Pull Request Tracking & Review

The **Pull Requests** view centralizes pull request activity across all project repositories.

### Key Capabilities

- **Status Tabs**: Filter by `Active`, `Completed`, or `Abandoned`.
- **Work Item Linking**: Mentions of `#12345` in PR titles or descriptions automatically resolve to work item details.
- **Release Association**: Completed PRs are matched to their corresponding release version tag based on merge commits and completion timestamps.
- **Direct Web Access**: Click any PR badge (e.g. `!1042`) to open the pull request directly in your web browser.

---

## 7. Tag Day Release Audits & Reporting

The **Reports → Tag Day Overview** tool automates release audits by evaluating each repository against its own latest semantic version tag (`vXX.YY.WWxx` or SemVer).

```
┌─────────────────────────────────────────────────────────────┐
│ # Tag Day Release Overview                                  │
│ Scope: Per-repository latest version tag baseline           │
├─────────────────────────────────────────────────────────────┤
│ 1. Repositories with Unmerged Branch Updates                │
│ 2. Repositories with Pull Requests after Latest Tag         │
│ 3. Consolidated Global Changes Timeline                     │
│ 4. Individual Repository Walkthrough                        │
└─────────────────────────────────────────────────────────────┘
```

### Release Readiness Views & Explorer
 
1. **Unmerged Ahead Branches**: Lists branches ahead of the default tracking branch (`main` / `dev`), displaying ahead/behind commit counts and links to prepared PRs.
2. **Untagged PRs**: Highlights completed or active PRs merged after the repository's latest release tag.
3. **Consolidated Changes Timeline**: Chronological log of all commits and PRs across the entire project.
4. **Repository Deep-Dive**: Per-category repository walkthrough with web links and commit logs.
5. **Interactive Tag Day Explorer**: Explore candidate release items in GUI (**Reports → 🏷️ Tag Day Explorer**). Repositories whose category or name matches configured *Repository Category Filters* (e.g. `*deprecated*`) are automatically omitted from "Repositories with Changes" and timeline candidate items.

### Weekly Proposed Tags & Direct 'dev' Branch Tagging

Tagday Explorer automatically generates proposed release tags and allows tagging repository branches directly:

- **Weekly `<YYWW>` Proposal**: The default mechanism calculates the patch level number based on the current ISO calendar week (e.g. `v01.02.2639` for Year 2026, Week 39), preserving leading `v` prefixes and 2-digit padding.
- **Repository List Badge & Quick Action**: Each repository with candidate updates shows its latest tag and proposed tag (`v01.02.2638 ➔ v01.02.2639`) along with a quick `🏷️` tag launcher.
- **Repository Inspector & Quick Bumps**: When inspecting a repository, the **Proposed Release Tag** card provides 1-click bump presets:
  - `Weekly Patch (<YYWW>)`: Sets patch number to current calendar week.
  - `+0.1 Minor`: Bumps minor version and sets patch to current week (e.g. `v01.03.2639`).
  - `+1.0 Major`: Bumps major version, resets minor to `00`, and sets patch to current week (e.g. `v02.00.2639`).
- **Interactive Tagging Modal**:
  - Click **🏷️ Tag Dev Branch...** in the top action bar or repository inspector.
  - Select target branch (defaults to `dev`, with automatic fallback to `develop`/`development`/`main`).
  - Customize tag name or annotation message.
  - Click **🚀 Create & Push Tag** to create the Git tag in Azure DevOps / TFS and immediately refresh the local database and UI.

### Generating Reports

- In GUI: Click **📑 Open TAGDAY.md** or trigger report generation in **Reports**.
- Via CLI:

  ```powershell
  uv run python src/devops_helper.py --report-tagday
  ```

---

## 8. Change Notification & Tag Day Filters

To prevent obsolete repositories and non-production branches from cluttering change notifications and release reports, DevOps Manager includes customizable wildcard filter rules.

### Configuring Filters in Settings

Navigate to **Settings → Change Notification & Tag Day Filters**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 🔔 Change Notification & Tag Day Filters          [↺ Reset to Defaults] │
├─────────────────────────────────────────────────────────────────────────┤
│ 📁 Repository Category Filters (Ignore for Change Notifications)        │
│    Suggested: [+ *deprecated*] [+ *archive*] [+ *legacy*] [+ *sandbox*] │
│    1. *deprecated*                                            [↑] [↓] [✕]│
│    [ + New category pattern...                   ] [Add Pattern]        │
├─────────────────────────────────────────────────────────────────────────┤
│ 🌿 Git Branch Filters (Ignore for Ahead & Change Tracking)               │
│    Suggested: [+ *archive*] [+ archive/*] [+ *demo*] [+ *test*]         │
│    1. *archive*                                               [↑] [↓] [✕]│
│    2. *demo*                                                  [↑] [↓] [✕]│
│    3. *deprecated*                                            [↑] [↓] [✕]│
│    4. *test*                                                  [↑] [↓] [✕]│
│    5. archive/*                                               [↑] [↓] [✕]│
│    [ + New branch pattern...                     ] [Add Pattern]        │
├─────────────────────────────────────────────────────────────────────────┤
│ 🧪 Filter Rule Test Sandbox                                             │
│    [ archive/old-feature                      ] [🚫 Excluded (Ignored)] │
├─────────────────────────────────────────────────────────────────────────┤
│ 7 total rule(s) configured                         [💾 Save Filter Rules]│
└─────────────────────────────────────────────────────────────────────────┘
```

### 1. Repository Category Filters

- **Purpose**: Repositories whose category matches these patterns (e.g. `*deprecated*`, `*sandbox*`) will **not** trigger change notifications, pending change badges, or appear in the Tag Day changes timeline.
- **Default**: `["*deprecated*"]`.

### 2. Git Branch Filters

- **Purpose**: Branches matching these patterns (e.g. `*archive*`, `*demo*`, `*test*`, `archive/*`, `test/*`) are excluded from ahead commit tracking and unmerged branch lists.
- **Default**: `["*archive*", "*demo*", "*deprecated*", "*test*", "archive/*", "demo/*", "test/*"]`.

### 3. Interactive Filter Sandbox

Type any category or branch name into the test input box to immediately verify whether it will be **✓ Included (Active)** or **🚫 Excluded (Ignored)** under the current rule set.

### 4. Persistence

Click **💾 Save Filter Rules** to persist the patterns to the SQLite cache database (`project_config` table). Repository indicators and reports update automatically.

---

## 9. Build Artifacts & Storage Analytics

The **Builds & Storage** report tracks pipeline build executions and artifact storage consumption.

### Features

- **Total Storage Metrics**: Active artifact size, deleted container size, reclaimed space.
- **Pipeline Breakdown**: Storage consumption grouped by build pipeline and repository.
- **Export Formats**: Outputs `BUILD_ARTIFACTS.md` (Markdown summary) and `BUILD_ARTIFACTS.csv` (detailed file-level spreadsheet).

---

## 10. Application Settings & Customization

### Scheduled Synchronization (Auto-Sync)

In **Settings → Scheduled Synchronization**:

- **Toggle**: Enable or disable background synchronization.
- **Interval**: Choose from 1 min, 2 min, 5 min (default), 10 min, 15 min, 30 min, 60 min.
- **Scope**:
  - `Full Sync`: Repositories, git branches, tags, WIQL work items, pull requests.
  - `Work Items Only`: Fast agile status update.
  - `Pull Requests Only`: Lightweight PR refresh.

### Sprint URL Syntax Templates

Configure how sprint board links are constructed for your TFS server environment:

- **Modern Hierarchical**: `{base_url}/{collection}/{project}/_sprints/{view_mode}/{team}/{iteration_path}`
- **TFS Boards Taskboard**: `{base_url}/{collection}/{project}/{team}/_boards/iteration/taskboard/{iteration_leaf}`
- **TFS Legacy Backlogs**: `{base_url}/{collection}/{project}/{team}/_backlogs/iteration/{iteration_leaf}`

### Display Scaling & Typography

In **Settings → Display & Typography Scaling**:

- **Small (90%)**: Compact for dense data tables and smaller laptop screens.
- **Medium (100% - Default)**: Balanced standard scale.
- **Large (115%)**: Enhanced readability for 1440p displays.
- **Extra Large (130%)**: HiDPI / 4K UHD monitors and accessibility.

### Collapsible Navigation Sidebar

The left sidebar can be collapsed to maximize screen real estate for wide data tables, kanban columns, and workload timelines:

- **Toggle Button**: Click `◀` in the sidebar header to collapse, or `▶` / `⚡` to expand.
- **Keyboard Shortcut**: Press `Ctrl+B` anywhere in the app to toggle the sidebar.
- **Smooth Animation**: Fluid 180ms ease transition between 240px and 64px width.
- **Hover Tooltips**: In collapsed mode, hovering over any navigation icon reveals a quick tooltip with the page title.
- **Compact Quick Actions**: In collapsed mode, quick 1-click action buttons remain easily accessible:
  - `🔤`: Compact font mode switcher (click to cycle through S / M / L / XL).
  - `🔄`: Full Data Sync (Cache & Remote).
  - `⚡`: WIQL Work Items Sync.
  - `🔀`: Pull Requests Sync.
  - `⏹️`: Abort active background synchronization.
  - `⏱️`: Auto-sync status indicator chip (click to toggle).
  - `▲ / ▼`: Quick Sync Log drawer toggle.
- **State Persistence**: Your sidebar preference (`sidebar_collapsed: true/false`) is automatically saved in `user_settings.yaml` and restored on startup.

---

## 11. CLI Automation & Scripting Reference

All backend commands can be automated from CI/CD pipelines, PowerShell, or bash:

```powershell
# Full synchronization of repositories and work items
uv run python src/devops_helper.py --sync

# Force synchronization (ignoring recent delay threshold)
uv run python src/devops_helper.py --sync --force

# Generate Tag Day release readiness report (TAGDAY.md)
uv run python src/devops_helper.py --report-tagday

# Generate Revision history (REVISION.md & REVISION.docx)
uv run python src/devops_helper.py --revision

# Generate weekly agile sprint report
uv run python src/generate_sprint_report.py --sprint week-2633

# Export build artifacts report
uv run python src/devops_helper.py --report-artifacts

# Export pull requests to spreadsheet
uv run python src/devops_helper.py --export-prs PR_SUMMARY
```

---

## 12. Troubleshooting & FAQs

### Q: Why does a repository show pending changes even though all branches are merged?

**A**: Check whether there are pull requests merged after the latest release tag. If new commits were merged into `main`/`dev` after the tag, the repository is marked as having untagged changes until a new version tag (e.g. `v01.02.2633`) is created.

### Q: How do I ignore experimental or archived branches from Tag Day reports?

**A**: Go to **Settings → Change Notification & Tag Day Filters → Git Branch Filters** and add a pattern such as `*archive*`, `archive/*`, or `*exp*`. Click **💾 Save Filter Rules**.

### Q: Can I run DevOps Manager completely offline?

**A**: Yes. Once synchronized, the entire application operates directly against the local SQLite database. You can inspect repositories, review PR history, analyze team capacity, and generate reports without connecting to TFS.

### Q: How can I reset all filter rules to defaults?

**A**: Go to **Settings → Change Notification & Tag Day Filters** and click **↺ Reset to Defaults**.
