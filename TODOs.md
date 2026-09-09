# TODOs

## OPEN

### Configuration

- only use the .env or environment file mechanism, when really needed, or triggered through CLI, but not as default. By default we consider the settings to be within our databasee

### UI Related

- Update Milestone Information does a direct synchronous synch with TFS, that is blocking the UI
- The workload explorer Task view is not updated, when it was shown, and a background synch was run
- Allow a scheduled synchronisatin, e.g. every 5 minutes, but allow also manual syncs

### Milestone Information

- I would like to import/export the milestones (which include the team + week-range) to/from a file, e.g. Excel, to allow for easier modification and synchronization

### Performance improvements

- The initial load of some pages takes very long, e.g. when loading all projects or when using the search functionality, can you improve the performance?

### Report Generation

- Sprint report generation does not seem to be filtered by sprint - if find way to many entries

## DONE

- TFS / Azure DevOps Sprint View linking with team resolution and direct item modal focusing (`?workitem={id}` or `_sprints/taskboard?workitem={id}` for active current sprint fallback).
- High-performance parallel repository synchronization via `ThreadPoolExecutor` and direct bulk REST PR discovery (`status=all&$top=100`), eliminating sequential push/PR round trips.
- Fixed missing PRs and stuck PR timestamp caused by non-monotonic collection-wide PR IDs breaking pagination prematurely and `DELETE FROM pull_requests` dropping inactive records.
- Real-time sync progress reporting (% bar and status message) with live cancellation token support (`TaskWorker.cancel()` and UI "⏹️ Abort Sync" button).
- Prepare weekly iterations already in advance, and continue the schematics up until a given deadline
- Jump from Workitem Explorer directly into the current teams sprint view of the item (considering the API provides the right team and iteration info)
- Fix WIQL query HTTP 400 caused by date precision on System.ChangedDate (added timePrecision=true and automatic date-only fallback) and debug logging
- Fixed top-right refresh buttons across all pages (Reports, Workload Explorer, Work Items, Dashboard, Repos, Pull Requests) to reload cache, storage/tagday reports, sprint analytics, and trigger reactive UI updates.
