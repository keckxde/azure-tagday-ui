# TODOs

## OPEN

### Configuration

- only use the .env or environment file mechanism, when really needed, or triggered through CLI, but not as default. By default we consider the settings to be within our databasee

### UI Related

- Allow a scheduled synchronisation, e.g. every 5 minutes, but allow also manual syncs

### Milestone Information

- Milestone Dialog: Filter historic Milestones by default

### Performance improvements

- The initial load of some pages takes very long, e.g. when loading all projects or when using the search functionality, can you improve the performance?

## DONE

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
