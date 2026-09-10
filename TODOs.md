# TODOs

## OPEN

### Configuration

- only use the .env or environment file mechanism, when really needed, or triggered through CLI, but not as default. By default we consider the settings to be within our databasee

### UI Related

- Allow a scheduled synchronisation, e.g. every 5 minutes, but allow also manual syncs
- Progress on the sidebar bottom is sufficient, no need for information top right

### Performance improvements

- The initial load of some pages takes very long, e.g. when loading all projects or when using the search functionality, can you improve the performance?

## DONE

- TFS / Azure DevOps Sprint Taskboard URL Format Fix: Corrected URL routing structure to `http://<URL>/<COLLECTION>/<PROJECT>/_sprints/taskboard/<TEAM>/<PROJECT>/sprints/<sprint>?workitem={id}` (and current sprint fallback `_sprints/taskboard/<TEAM>?workitem={id}`), ensuring `_sprints/{view_mode}` precedes the team name, full iteration path hierarchy is preserved, and area paths/iteration paths are accurately mapped to target teams without collision with iteration folder names.

- Pull Request (PR) Multi-Status Sync & TFS On-Premise Endpoint Fix: Fixed PR list becoming stuck on older PRs. Refactored PR synchronization to query both `status="active"` (capturing 100% of open PRs) and `status="completed"` (capturing newly merged PRs ordered by completion date descending, preventing pagination cutoff from older creation dates). Fixed on-premise TFS 404 errors by adding repository-scoped API endpoints (`{project}/_apis/git/repositories/{repo_id}/pullrequests/{pr_id}`) with dual-endpoint fallback. Added direct "⚡ Sync PRs" button in Pull Requests view toolbar and a dedicated sidebar sync button under DATA SYNC.

- Milestone Dialog Default Historic Filter: Milestones whose target or end dates have elapsed are automatically filtered out by default when opening the Major Milestones dialog. A dedicated filter bar with instant search and a "Hide Historic" toggle switch/badge allows users to quickly view all past milestones or active ones on demand.

- Major Milestones Import & Export (Excel, CSV, JSON): Full roundtrip synchronization of milestones with associated team assignments, start/end dates, duration, descriptions, and ISO sprint week-range schematics (`week-YYWW`), featuring native file browser integration, flexible header mapping, and live SQLite database synchronization.

- Dynamic state synchronization for the Workload Explorer Task view / details drawer: when background synchronizations, deadline edits, or iteration updates complete, the active cell view automatically refreshes its task breakdown and parent container items against the new matrix dataset without losing user selection.
- Asynchronous TFS / Azure DevOps API synchronization for milestone deadlines and iteration shifts: local SQLite cache and memory update instantaneously with optimistic UI feedback, while REST API updates run in background daemon threads without freezing the Qt Quick interface.
- Strict sprint filtering for Sprint report generation (GUI preview, Markdown wiki, and CSV exports), strictly isolating work items assigned to the target sprint instead of matching any item modified during the calendar week.
- TFS / Azure DevOps Sprint View linking with team resolution and direct item modal focusing (`?workitem={id}` or `_sprints/taskboard?workitem={id}` for active current sprint fallback).
- High-performance parallel repository synchronization via `ThreadPoolExecutor` and direct bulk REST PR discovery (`status=all&$top=100`), eliminating sequential push/PR round trips.
- Fixed missing PRs and stuck PR timestamp caused by non-monotonic collection-wide PR IDs breaking pagination prematurely and `DELETE FROM pull_requests` dropping inactive records.
- Real-time sync progress reporting (% bar and status message) with live cancellation token support (`TaskWorker.cancel()` and UI "⏹️ Abort Sync" button).
- Prepare weekly iterations already in advance, and continue the schematics up until a given deadline
- Jump from Workitem Explorer directly into the current teams sprint view of the item (considering the API provides the right team and iteration info)
- Fix WIQL query HTTP 400 caused by date precision on System.ChangedDate (added timePrecision=true and automatic date-only fallback) and debug logging
- Fixed top-right refresh buttons across all pages (Reports, Workload Explorer, Work Items, Dashboard, Repos, Pull Requests) to reload cache, storage/tagday reports, sprint analytics, and trigger reactive UI updates.
