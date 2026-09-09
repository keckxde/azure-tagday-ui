# TODOs

## OPEN

### Repository Related

- Is there a mechanism to improve the sync of repository / git / PR data? (we are missing quite a lot of PRs and the update takes very long - this could be improved)

### PR Related

- The PR list still is not updated, I seem to be stuck at a specific time, and no PRs after are shown or updated in the PR-list or updated in the repo view

### Sprint related

- Links to Sprint view still fail can you check the TFS API to properly set up the link to an item in the current sprint?

### Synchronization

- The sync display does not show a progress, and cannot be aborted
- The refresh report buttons on the top right on different pages does not seem to work

### Milestone Information

- I would like to import/export the milestones (which include the team + week-range) to/from a file, e.g. Excel, to allow for easier modification and synchronization

### Performance improvements

- The initial load of some pages takes very long, e.g. when loading all projects or when using the search functionality, can you improve the performance?

### Report Generation

- Sprint report generation does not seem to be filtered by sprint - if find way to many entries

## DONE

- Prepare weekly iterations already in advance, and continue the schematics up until a given deadline
- Jump from Workitem Explorer directly into the current teams sprint view of the item (considering the API provides the right team and iteration info)
- Fix WIQL query HTTP 400 caused by date precision on System.ChangedDate (added timePrecision=true and automatic date-only fallback) and debug logging
