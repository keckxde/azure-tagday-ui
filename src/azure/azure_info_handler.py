# -*- coding: UTF-8 -*-
import urllib.error
import re
import logging
import sys,os
# Add module and parent py directory to sys.path so we can import local modules
py_dir = os.path.dirname(os.path.realpath(__file__))
parent_dir = os.path.dirname(py_dir)
for p in (py_dir, parent_dir):
    if p not in sys.path:
        sys.path.insert(0, p)


from utils import UpdateDateString, parse_iso_datetime, timedelta, parse_semver_tuple
try:
    from .azure_info_base_client import AzureBaseClient
except ImportError:
    from azure_info_base_client import AzureBaseClient

logger = logging.getLogger(__name__)


def _enrich_pr(pr, normalize_pr_status):
    """
    Enriches a raw PR dict with formatted date strings and a human-readable statusStr.
    Modifies the dict in-place.

    Args:
        pr (dict): Pull request dict from the TFS API.
        normalize_pr_status (callable): Function that normalises a raw status string.
    """
    pr["closedDateStr"] = UpdateDateString(pr.get("closedDate"))
    pr["creationDateStr"] = UpdateDateString(pr.get("creationDate"))
    norm_status = normalize_pr_status(pr.get("status"))
    pr["status"] = norm_status
    if norm_status == "active":
        pr["statusStr"] = f"OPN {pr['creationDateStr']}"
    elif norm_status == "completed":
        pr["statusStr"] = f"DON {pr['closedDateStr']}"
    elif norm_status == "abandoned":
        pr["statusStr"] = f"ABANDONED {pr['closedDateStr']}"
    else:
        pr["statusStr"] = f"REJECTED {pr['closedDateStr']}"


class AzureInfoHandler(AzureBaseClient):
    """
    A high-level client helper to query, fetch, and aggregate project and repository data from Azure DevOps (TFS).
    Implements domain-specific workflows on top of AzureBaseClient.
    """

    def __init__(self, url, token):
        """
        Initializes the Azure DevOps info handler.

        Args:
            url (str): The base URL of the TFS/Azure DevOps instance.
            token (str): The personal access token (PAT) for basic authentication.
        """
        super().__init__(url, token)

    def taskTest(self, project_id):
        """
        Queries and prints task definitions for testing connectivity.

        Args:
            project_id (str): The project ID or name.
        """
        # Sample function mirroring JS
        logger.info("Task Samples %s", project_id)
        try:
            # GET _apis/distributedtask/tasks
            tasks = self.get_distributed_task_tasks()
            logger.info("You have %d task definition(s)", len(tasks))
        except Exception as e:
            logger.error("Error in taskTest: %s", e)

    def GetTFSPipelines(self, project_id):
        """
        Queries pipelines for a project.

        Args:
            project_id (str): The project ID or name.

        Returns:
            list: List of pipeline definitions.
        """
        logger.info("Ask for Pipelines %s", project_id)
        try:
            pipes = self.get_pipelines(project_id)
            logger.info("-- You have %d pipeline definition(s)", len(pipes))
            return pipes
        except Exception as e:
            logger.error("Error in GetTFSPipelines: %s", e)
            return []

    def GetTFSWorkItems(self, task_id_list, cache_db=None):
        """
        Retrieves work item details for a list of work item IDs.

        Args:
            task_id_list (list): List of work item IDs.
            cache_db (AzureDevOpsCache, optional): If provided, caches fetched work items or marks missing ones as deleted.

        Returns:
            list: List of work item details dictionaries.
        """
        work_item_list = []
        clean_ids = []
        for tid in task_id_list:
            try:
                clean_ids.append(int(str(tid).lstrip("#")))
            except (ValueError, TypeError):
                continue

        try:
            batch_items = self.get_work_items_batch(clean_ids)
            found_ids = set()
            for wi in batch_items:
                if wi and isinstance(wi, dict) and "id" in wi:
                    work_item_list.append(wi)
                    found_ids.add(wi["id"])
                    if cache_db:
                        fields = wi.get("fields", {})
                        assigned = fields.get("System.AssignedTo", {})
                        assigned_name = assigned.get("displayName", "") if isinstance(assigned, dict) else str(assigned or "")
                        cache_db.save_work_item(
                            wi["id"],
                            fields.get("System.Title"),
                            fields.get("System.WorkItemType"),
                            fields.get("System.State"),
                            assigned_name,
                            fields.get("System.ChangedDate"),
                            wi,
                            deleted=0
                        )
            if cache_db:
                for tid in clean_ids:
                    if tid not in found_ids:
                        logger.warning(" - GetTFSWorkItems: #%s not found in API batch", tid)
                        cache_db.mark_work_item_deleted(tid)
            return work_item_list
        except Exception as batch_err:
            logger.warning(" - GetTFSWorkItems: batch request failed (%s), falling back to individual requests", batch_err)

        # Fallback to single item requests
        for task_id in task_id_list:
            try:
                wi = self.get_work_item(task_id)
                if wi and isinstance(wi, dict) and "id" in wi:
                    work_item_list.append(wi)
                    if cache_db:
                        fields = wi.get("fields", {})
                        assigned = fields.get("System.AssignedTo", {})
                        assigned_name = assigned.get("displayName", "") if isinstance(assigned, dict) else str(assigned or "")
                        cache_db.save_work_item(
                            wi["id"],
                            fields.get("System.Title"),
                            fields.get("System.WorkItemType"),
                            fields.get("System.State"),
                            assigned_name,
                            fields.get("System.ChangedDate"),
                            wi,
                            deleted=0
                        )
                else:
                    logger.warning(" - GetTFSWorkItems: #%s err no such task id", task_id)
                    if cache_db:
                        cache_db.mark_work_item_deleted(task_id)
            except urllib.error.HTTPError as e:
                if e.code in (404, 410):
                    logger.warning(" - GetTFSWorkItems: #%s not found (HTTP %s)", task_id, e.code)
                    if cache_db:
                        cache_db.mark_work_item_deleted(task_id)
                else:
                    logger.error(" - GetTFSWorkItems: #%s err %s", task_id, e)
            except Exception as e:
                err_str = str(e).lower()
                if "404" in err_str or "not found" in err_str or "does not exist" in err_str:
                    logger.warning(" - GetTFSWorkItems: #%s not found (%s)", task_id, e)
                    if cache_db:
                        cache_db.mark_work_item_deleted(task_id)
                else:
                    logger.error(" - GetTFSWorkItems: #%s err %s", task_id, e)
        return work_item_list

    def sync_work_items(self, cache_db, project_id=None, chunk_size=200, progress_callback=None, force_full_sync=False):
        """
        Synchronizes all work items in the SQLite database cache with the TFS API.
        Optimized with high-performance incremental timestamp-based sync:
        1. Queries all remote work item IDs using a fast flat WIQL query.
        2. Reconciles deletions immediately: cached items no longer on server are marked deleted=1.
        3. Checks latest System.ChangedDate timestamp in cache. If available and force_full_sync=False,
           executes a WIQL filter [System.ChangedDate] >= watermark to retrieve only new/modified items.
        4. Downloads full details only for new and modified work items using batch requests.
        5. Recursively resolves missing parent/ancestor work items for complete hierarchy.
        6. Pre-fills major milestones.

        Args:
            cache_db (AzureDevOpsCache): Database cache instance.
            project_id (str, optional): Project ID or name. Defaults to None.
            chunk_size (int, optional): Max IDs per batch request (TFS limit is 200). Defaults to 200.
            progress_callback (callable, optional): Callback function(msg: str, current: int, total: int) for live progress updates.
            force_full_sync (bool, optional): If True, re-downloads all work items regardless of timestamp. Defaults to False.

        Returns:
            dict: Summary of synced, deleted, unchanged, and error counts.
        """
        def _notify(msg, current=0, total=0):
            logger.info(msg)
            if callable(progress_callback):
                try:
                    progress_callback(msg, current, total)
                except TypeError:
                    progress_callback(msg)
                except Exception as ex:
                    logger.debug("Progress callback exception: %s", ex)

        summary = {"synced": 0, "deleted": 0, "unchanged": 0, "errors": 0}
        target_proj = project_id or getattr(self, "project_id", "") or "default"
        _notify(f"Executing WIQL query to discover work items for project '{target_proj}'...", 0, 0)

        # 1. Discover all remote work items in the project
        try:
            remote_all_ids_list = self.query_work_item_ids_wiql(project_id)
            remote_all_ids = set(remote_all_ids_list)
            _notify(f"WIQL discovery successful: found {len(remote_all_ids)} work item(s) for project '{target_proj}'", 0, len(remote_all_ids))
        except Exception as wiql_err:
            logger.warning("WIQL query failed (%s), falling back to cached DB IDs", wiql_err)
            _notify(f"⚠️ WIQL query failed: {wiql_err}. Falling back to cached DB IDs.", 0, 0)
            remote_all_ids_list = cache_db.get_all_work_item_ids(include_deleted=True)
            remote_all_ids = set(remote_all_ids_list)

        # 2. Check cached DB IDs
        active_db_ids = set(cache_db.get_all_work_item_ids(include_deleted=False))

        # 3. Mark deleted items (items in active cache that no longer exist on remote)
        missing_on_remote = active_db_ids - remote_all_ids
        for did in missing_on_remote:
            cache_db.mark_work_item_deleted(did)
            summary["deleted"] += 1
            if did in active_db_ids:
                active_db_ids.remove(did)

        # 4. Determine items that need fetching (incremental vs full)
        new_or_restored_ids = remote_all_ids - active_db_ids
        max_changed_date = None if force_full_sync else (
            cache_db.get_max_work_item_changed_date() if hasattr(cache_db, "get_max_work_item_changed_date") else None
        )

        items_to_fetch = set()

        if max_changed_date and not force_full_sync and active_db_ids:
            # Incremental sync: compute watermark with a 5-minute safety buffer
            watermark_str = max_changed_date
            dt_obj = parse_iso_datetime(max_changed_date)
            if dt_obj:
                safe_dt = dt_obj - timedelta(minutes=5)
                watermark_str = safe_dt.strftime("%Y-%m-%d %H:%M:%S")

            try:
                modified_ids_list = self.query_work_item_ids_wiql(project_id, changed_since=watermark_str)
                modified_ids = set(modified_ids_list) & remote_all_ids
                items_to_fetch = (new_or_restored_ids | modified_ids) & remote_all_ids
                unchanged_count = len(remote_all_ids) - len(items_to_fetch)
                summary["unchanged"] = max(0, unchanged_count)
                _notify(
                    f"Incremental WIQL sync: found {len(items_to_fetch)} modified/new item(s) since {watermark_str} "
                    f"({len(remote_all_ids)} total in project, {summary['unchanged']} up-to-date, {summary['deleted']} deleted)",
                    0, len(items_to_fetch)
                )
            except Exception as inc_err:
                logger.warning("Incremental WIQL query failed (%s), falling back to full sync", inc_err)
                _notify(f"⚠️ Incremental WIQL query failed: {inc_err}. Falling back to full sync.", 0, 0)
                items_to_fetch = remote_all_ids
        else:
            # Full sync or first sync
            items_to_fetch = remote_all_ids
            _notify(
                f"Full sync: discovered {len(remote_all_ids)} total work items for project '{target_proj}'",
                0, len(remote_all_ids)
            )

        clean_ids = []
        for tid in sorted(items_to_fetch):
            try:
                clean_ids.append(int(str(tid).lstrip("#")))
            except (ValueError, TypeError):
                continue

        if not clean_ids:
            _notify("All work items are up-to-date. No modifications detected.", 0, 0)
            # Auto-discover and pre-fill major milestones
            try:
                if hasattr(cache_db, "discover_and_prefill_milestones_from_work_items"):
                    cache_db.discover_and_prefill_milestones_from_work_items()
            except Exception:
                pass
            return summary

        total_items = len(clean_ids)
        total_batches = (total_items + chunk_size - 1) // chunk_size
        _notify(f"Downloading {total_items} work items in {total_batches} batch(es) of up to {chunk_size} items...", 0, total_items)

        found_ids = set()
        all_parent_ids = set()

        def _extract_parent_id(wi_data):
            if not wi_data or not isinstance(wi_data, dict):
                return None
            f_map = wi_data.get("fields", {})
            p_val = f_map.get("System.Parent")
            if p_val is not None:
                try:
                    return int(str(p_val).lstrip("#"))
                except (ValueError, TypeError):
                    pass
            for rel in wi_data.get("relations") or []:
                rel_name = rel.get("rel") or ""
                if "Hierarchy-Reverse" in rel_name or rel_name == "Parent" or (rel.get("attributes") or {}).get("name") == "Parent":
                    url = rel.get("url", "")
                    if url:
                        try:
                            return int(url.rstrip("/").split("/")[-1])
                        except (ValueError, TypeError):
                            pass
            return None

        for i in range(0, len(clean_ids), chunk_size):
            chunk = clean_ids[i:i + chunk_size]
            batch_num = (i // chunk_size) + 1
            batch_start = i + 1
            batch_end = min(i + len(chunk), total_items)
            pct = round((batch_end / total_items) * 100) if total_items > 0 else 0
            _notify(
                f"Syncing work items batch [{batch_num}/{total_batches}] (#{batch_start}-#{batch_end} of {total_items}, {pct}%)...",
                batch_end, total_items
            )
            try:
                batch_items = self.get_work_items_batch(chunk, expand="all", chunk_size=chunk_size)
                for wi in batch_items:
                    if wi and isinstance(wi, dict) and "id" in wi:
                        wi_id = wi["id"]
                        found_ids.add(wi_id)
                        fields = wi.get("fields", {})
                        assigned = fields.get("System.AssignedTo", {})
                        assigned_name = assigned.get("displayName", "") if isinstance(assigned, dict) else str(assigned or "")
                        cache_db.save_work_item(
                            wi_id,
                            fields.get("System.Title"),
                            fields.get("System.WorkItemType"),
                            fields.get("System.State"),
                            assigned_name,
                            fields.get("System.ChangedDate"),
                            wi,
                            deleted=0
                        )
                        summary["synced"] += 1
                        pid = _extract_parent_id(wi)
                        if pid:
                            all_parent_ids.add(pid)

                for tid in chunk:
                    if tid not in found_ids:
                        logger.warning(" - sync_work_items: #%s not returned by API batch. Marking as deleted.", tid)
                        cache_db.mark_work_item_deleted(tid)
                        summary["deleted"] += 1

            except Exception as batch_err:
                _notify(f"Batch #{batch_num} failed ({batch_err}), falling back to individual requests...", batch_end, total_items)
                for idx, task_id in enumerate(chunk):
                    if (idx + 1) % 25 == 0 or idx == len(chunk) - 1:
                        _notify(f"Batch #{batch_num} individual fallback: querying item {idx + 1}/{len(chunk)}...", batch_end, total_items)
                    try:
                        wi = self.get_work_item(task_id)
                        if wi and isinstance(wi, dict) and "id" in wi:
                            found_ids.add(wi["id"])
                            fields = wi.get("fields", {})
                            assigned = fields.get("System.AssignedTo", {})
                            assigned_name = assigned.get("displayName", "") if isinstance(assigned, dict) else str(assigned or "")
                            cache_db.save_work_item(
                                wi["id"],
                                fields.get("System.Title"),
                                fields.get("System.WorkItemType"),
                                fields.get("System.State"),
                                assigned_name,
                                fields.get("System.ChangedDate"),
                                wi,
                                deleted=0
                            )
                            summary["synced"] += 1
                            pid = _extract_parent_id(wi)
                            if pid:
                                all_parent_ids.add(pid)
                        else:
                            logger.warning(" - sync_work_items: #%s not found via API. Marking as deleted.", task_id)
                            cache_db.mark_work_item_deleted(task_id)
                            summary["deleted"] += 1
                    except urllib.error.HTTPError as e:
                        if e.code in (404, 410):
                            logger.warning(" - sync_work_items: #%s returned HTTP %s. Marking as deleted.", task_id, e.code)
                            cache_db.mark_work_item_deleted(task_id)
                            summary["deleted"] += 1
                        else:
                            logger.error(" - sync_work_items: #%s HTTP error %s", task_id, e)
                            summary["errors"] += 1
                    except Exception as e:
                        err_str = str(e).lower()
                        if "404" in err_str or "not found" in err_str or "does not exist" in err_str:
                            logger.warning(" - sync_work_items: #%s not found (%s). Marking as deleted.", task_id, e)
                            cache_db.mark_work_item_deleted(task_id)
                            summary["deleted"] += 1
                        else:
                            logger.error(" - sync_work_items: #%s error %s", task_id, e)
                            summary["errors"] += 1

        # Recursively retrieve missing parent / ancestor work items so full hierarchy is stored in database
        active_db_ids = set(cache_db.get_all_work_item_ids(include_deleted=False)) if hasattr(cache_db, "get_all_work_item_ids") else set()
        missing_parents = (all_parent_ids - found_ids) - active_db_ids
        depth = 0
        while missing_parents and depth < 5:
            depth += 1
            p_chunk = list(missing_parents)[:chunk_size]
            next_level_parents = set()
            _notify(f"Resolving work item hierarchy (Level {depth}): fetching {len(p_chunk)} parent containers...", total_items, total_items)
            try:
                p_items = self.get_work_items_batch(p_chunk, expand="all", chunk_size=chunk_size)
                for p_wi in p_items:
                    if p_wi and isinstance(p_wi, dict) and "id" in p_wi:
                        p_id = p_wi["id"]
                        found_ids.add(p_id)
                        active_db_ids.add(p_id)
                        p_fields = p_wi.get("fields", {})
                        p_assigned = p_fields.get("System.AssignedTo", {})
                        p_assigned_name = p_assigned.get("displayName", "") if isinstance(p_assigned, dict) else str(p_assigned or "")
                        cache_db.save_work_item(
                            p_id,
                            p_fields.get("System.Title"),
                            p_fields.get("System.WorkItemType"),
                            p_fields.get("System.State"),
                            p_assigned_name,
                            p_fields.get("System.ChangedDate"),
                            p_wi,
                            deleted=0
                        )
                        summary["synced"] += 1
                        grandparent_id = _extract_parent_id(p_wi)
                        if grandparent_id:
                            next_level_parents.add(grandparent_id)
            except Exception as p_err:
                logger.warning(" - sync_work_items: error fetching missing parent items %s: %s", p_chunk, p_err)
                break
            missing_parents = (next_level_parents - found_ids) - active_db_ids

        # Auto-discover and pre-fill major milestones from work item tags
        try:
            if hasattr(cache_db, "discover_and_prefill_milestones_from_work_items"):
                cache_db.discover_and_prefill_milestones_from_work_items()
        except Exception as ms_err:
            logger.debug("Could not prefill milestones from work item tags: %s", ms_err)

        unchanged_str = f", {summary.get('unchanged', 0)} already up-to-date" if summary.get("unchanged") else ""
        _notify(
            f"Work items sync completed: {summary.get('synced', 0)} synced, {summary.get('deleted', 0)} marked deleted{unchanged_str}, {summary.get('errors', 0)} errors",
            total_items, total_items
        )

        return summary

    def GetRecentActivityData(self, project_id=None):
        """
        Retrieves and groups recent work item activities by their state.

        Args:
            project_id (str, optional): Filter by project ID. Defaults to None.

        Returns:
            dict: Dictionary grouping recent activities by state (e.g. {'Done': [...]}).
        """
        try:
            recent_activities = self.get_recent_work_items()
            activity_obj = {}
            for activity in recent_activities:
                activity["activityDate"] = UpdateDateString(activity.get("activityDate"))
                activity["changedDate"] = UpdateDateString(activity.get("changedDate"))
                if project_id and project_id != activity.get("teamProject"):
                    continue
                state = activity.get("state")
                if not state:
                    continue
                if state not in activity_obj:
                    activity_obj[state] = []
                activity_obj[state].append(activity)
            return activity_obj
        except Exception as e:
            logger.error("Error in GetRecentActivityData: %s", e)
            return {}

    def GetTFSPullRequest(self, pr_list):
        """
        Retrieves pull request details for a list of pull request IDs.

        Args:
            pr_list (list): List of pull request IDs.

        Returns:
            list: List of pull request detail dictionaries.
        """
        prs = []
        for pr_id in pr_list:
            try:
                pr = self.get_pull_request(pr_id)
                if pr:
                    prs.append(pr)
                else:
                    logger.warning(" - GetTFSPullRequest: !%s err no such PR id", pr_id)
            except Exception as e:
                logger.error(" - GetTFSPullRequest: !%s err %s", pr_id, e)
        return prs

    def ParseSubmodules(self, repo, project_id):
        """
        Parses the `.gitmodules` file in a repository to find submodule mappings and queries their metadata.

        Args:
            repo (dict): Repository info dictionary (containing 'id' and 'name').
            project_id (str): The project ID or name.

        Returns:
            list: List of parsed submodules with path, url, and metadata info.
        """
        submodules = []
        try:
            # GET {projectID}/_apis/git/repositories/{repositoryId}/items?path={path}&$format=text&api-version=6.0
            content = self.get_repository_items(
                project_id, repo['id'], ".gitmodules", params={"$format": "text"}, raw_text=True
            )
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return submodules
            raise e
        except Exception:
            return submodules

        if content:
            submodule = {"path": "", "url": ""}
            for line in content.splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                params = line.split("=", 1)
                if len(params) < 2:
                    if submodule["url"] != "":
                        path = submodule["path"].strip().strip("/")
                        try:
                            # GET item metadata info
                            info = self.get_repository_items(project_id, repo['id'], path)
                            submodule["info"] = info
                        except Exception as e:
                            logger.error("Error getting submodule info for %s: %s", path, e)
                            submodule["info"] = {"commitId": ""}
                        submodule["path"] = path
                        submodules.append(submodule)
                    submodule = {"path": "", "url": ""}
                    continue
                key = params[0].strip()
                val = params[1].strip()
                submodule[key] = val

            if submodule["url"] != "":
                path = submodule["path"].strip().strip("/")
                try:
                    # GET item metadata info
                    info = self.get_repository_items(project_id, repo['id'], path)
                    submodule["info"] = info
                except Exception as e:
                    logger.error("Error getting submodule info for %s: %s", path, e)
                    submodule["info"] = {"commitId": ""}
                submodule["path"] = path
                submodules.append(submodule)

        return submodules

    def _should_skip_repo(self, repo, filter_repos):
        """Checks if the repository should be ignored or skipped."""
        is_disabled = repo.get("isDisabled", False)
        if is_disabled:
            return True
        repo_name = repo.get("name", "")
        if filter_repos and repo_name in filter_repos:
            logger.info("-- Repo: %s ignored by environment", repo_name)
            return True
        if repo_name and ("CANCEL" in repo_name or "DEPRECATE" in repo_name):
            return True
        return False

    def _get_cached_repo_if_up_to_date(self, project_id, repo, cache_db):
        """
        Checks if cached repository details are up to date via latest push ID comparison.
        Always synchronizes and updates PR states first before retrieving and returning the cached repo.
        """
        if cache_db is None:
            return None, None
        repo_id = repo["id"]
        repo_name = repo.get("name", "")
        try:
            pushes = self.get_pushes(project_id, repo_id)
            if pushes:
                remote_push_id = pushes[0].get("pushId")
                cached_push_id = cache_db.get_last_push_id(repo_id)
                if remote_push_id is not None and remote_push_id == cached_push_id:
                    # Check and synchronize PR states (open PR updates, new PRs) before loading cached state
                    self._refresh_active_prs(project_id, repo_id, repo_name, cache_db)
                    cached_repo = cache_db.get_cached_repository(repo_id, repo_name)
                    if cached_repo:
                        logger.info("  -- Repo %s is up to date (Push ID: %s). Skipping remote query.", repo_name, remote_push_id)
                        return cached_repo, remote_push_id
                return None, remote_push_id
        except Exception as e:
            logger.warning("  -- Failed to check push ID for %s: %s", repo_name, e)
        return None, None

    def _fetch_new_prs_incremental(self, project_id, repo, cache_db):
        """
        Incrementally discovers new PRs for a repository from TFS by querying PRs
        in descending order and stopping as soon as pr_id <= max_known_pr_id.

        Args:
            project_id (str): The project ID or name.
            repo (dict): Repository metadata dictionary (must contain 'id').
            cache_db: The database cache instance.

        Returns:
            int: Number of new PRs saved to the database cache.
        """
        from utils import normalize_pr_status
        repo_id = repo["id"]
        repo_name = repo.get("name", "")
        max_known_id = cache_db.get_max_pr_id(repo_id) if cache_db else 0
        new_count = 0
        skip = 0
        top = 100

        while True:
            try:
                page = self.get_pull_requests(project_id, repo_id, status="all", top=top, skip=skip)
            except Exception as e:
                logger.warning("  -- Error querying pull requests for repo %s (skip=%s): %s", repo_name, skip, e)
                break

            if not page:
                break

            stop_pagination = False
            for pr in page:
                pr_id = int(pr.get("pullRequestId") or pr.get("id") or 0)
                if max_known_id > 0 and pr_id <= max_known_id:
                    stop_pagination = True
                    break

                if not pr.get("repository"):
                    pr["repository"] = repo

                _enrich_pr(pr, normalize_pr_status)
                if cache_db:
                    cache_db.save_single_pull_request(pr)
                new_count += 1
                logger.info("  -- Discovered new PR #%s in %s (%s)", pr_id, repo_name, pr.get("status"))

            if stop_pagination or len(page) < top:
                break
            skip += len(page)

        return new_count

    def _refresh_active_prs(self, project_id, repo_id, repo_name, cache_db):
        """
        Re-syncs pull requests for a repository from TFS into the cache DB:
        1. Refreshes all PRs currently stored as active in SQLite (detects completion/abandonment).
        2. Incrementally searches for any newly created PRs until hitting latest known PR ID.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            repo_name (str): The repository name (for logging).
            cache_db: The database cache instance.

        Returns:
            bool: True if any PR was added or updated in the cache.
        """
        from utils import normalize_pr_status
        has_changes = False
        try:
            # 1. Re-fetch every PR currently stored as active in the DB to capture closures & changes.
            active_db_prs = cache_db.get_active_pull_requests(repo_id) if cache_db else []
            for db_pr in active_db_prs:
                pr_id_str = str(db_pr.get("id"))
                try:
                    updated_pr = self.get_pull_request(pr_id_str)
                    if updated_pr:
                        if not updated_pr.get("repository"):
                            updated_pr["repository"] = {"id": repo_id, "name": repo_name}
                        _enrich_pr(updated_pr, normalize_pr_status)
                        if cache_db:
                            cache_db.save_single_pull_request(updated_pr)
                        has_changes = True
                        logger.info("  -- PR #%s in %s refreshed: %s", pr_id_str, repo_name, updated_pr["status"])
                except Exception as ex:
                    logger.warning("Could not refresh active PR #%s: %s", pr_id_str, ex)

            # 2. Incremental scan for new PRs stopping at max_known_pr_id
            repo_dict = {"id": repo_id, "name": repo_name}
            new_prs_count = self._fetch_new_prs_incremental(project_id, repo_dict, cache_db)
            if new_prs_count > 0:
                has_changes = True

        except Exception as e:
            logger.warning("  -- Failed to refresh active PRs for %s: %s", repo_name, e)
        return has_changes

    def _process_branches(self, project_id, repo, branches):
        """Processes branch references, updates latest commit details, and returns whether 'dev' exists."""
        b_we_have_dev_branch = False
        repo_id = repo["id"]
        for branch in branches:
            try:
                latest_commit = self.get_commit(project_id, repo_id, branch['objectId'])
                branch["LatestCommit"] = latest_commit
            except Exception as e:
                logger.error("Error fetching commit %s for branch %s: %s", branch['objectId'], branch.get('name'), e)
                branch["LatestCommit"] = {}

            branch["FriendlyName"] = branch.get("name", "").replace("refs/heads/", "")
            branch["CommitId"] = branch.get("objectId", "")[:7]

            committer_info = branch["LatestCommit"].get("committer", {})
            commit_date_raw = committer_info.get("date")
            branch["CommitDateObj"] = parse_iso_datetime(commit_date_raw)
            branch["CommitDate"] = UpdateDateString(branch["CommitDateObj"])
            branch["Committer"] = committer_info.get("name", "")
            
            comment_complete = branch["LatestCommit"].get("comment", "").replace("\n", " ")
            branch["CommentComplete"] = comment_complete
            branch["Comment"] = comment_complete[:46] + "..." if len(comment_complete) > 46 else comment_complete

            if branch["FriendlyName"] == "dev":
                b_we_have_dev_branch = True

            if repo.get("defaultBranch"):
                default_branch = repo["defaultBranch"].replace("refs/heads/", "")
                if branch["FriendlyName"] != default_branch:
                    try:
                        diff = self.get_diff(project_id, repo_id, default_branch, branch['FriendlyName'])
                        ahead = diff.get("aheadCount", 0)
                        behind = diff.get("behindCount", 0)
                        branch["Ahead"] = ahead
                        branch["Behind"] = behind
                        branch["Stats"] = {"aheadCount": ahead, "behindCount": behind}
                    except Exception as e:
                        logger.error("Error getting diff for branch %s against %s: %s", branch['FriendlyName'], default_branch, e)
                        branch["Ahead"] = 0
                        branch["Behind"] = 0
                        branch["Stats"] = {"aheadCount": -1, "behindCount": -1}
                else:
                    branch["Ahead"] = 0
                    branch["Behind"] = 0
                    branch["Stats"] = {"aheadCount": 0, "behindCount": 0}
            else:
                branch["Ahead"] = 0
                branch["Behind"] = 0
                branch["Stats"] = {"aheadCount": 0, "behindCount": 0}

            last_commit_raw_date = repo.get("LastCommitRawDate")
            commit_date_obj = branch["CommitDateObj"]
            if commit_date_obj and (not last_commit_raw_date or commit_date_obj > last_commit_raw_date):
                repo["LastCommitRawDate"] = commit_date_obj
                repo["LatestCommit"] = branch["CommitId"]
                repo["CommitDate"] = branch["CommitDate"]
                repo["Committer"] = branch["Committer"]
                repo["Comment"] = branch["Comment"]

        branches.sort(key=lambda x: x.get("CommitDate", ""))
        return b_we_have_dev_branch

    def _process_tags(self, project_id, repo, filter_version_tags_format):
        """Filters tags, extracts annotated tag information, and returns stable/unstable lists."""
        tags_filtered = []
        last_stable_tag = ""
        last_unstable_tag = ""
        repo_id = repo["id"]
        repo_name = repo.get("name", "")

        tags = []
        try:
            tags = self.get_repository_refs(project_id, repo_id, "tags/")
        except Exception as e:
            logger.error("Error fetching tags for %s: %s", repo_name, e)
            return tags_filtered, last_stable_tag, last_unstable_tag

        for tag in tags:
            tag["FriendlyName"] = tag.get("name", "").replace("refs/tags/", "")
            if filter_version_tags_format and not tag["FriendlyName"].startswith("v"):
                logger.debug("  -- Ignore Tag %s -> missing 'v'", tag['name'])
                continue

            version_parts = tag["FriendlyName"].split(".")
            if filter_version_tags_format and len(version_parts) < 3:
                logger.debug("  -- Ignore Tag %s -> wrong version number %d", tag['FriendlyName'], len(version_parts))
                continue

            if filter_version_tags_format and len(version_parts[1]) < 2:
                logger.debug("  -- Ignore Tag %s -> wrong MINOR version number %s", tag['FriendlyName'], version_parts[1])
                continue

            if len(version_parts) == 3:
                try:
                    minor = int(version_parts[1])
                    if minor % 2:
                        tag["unstable"] = True
                        tag["stable"] = False
                        if not last_unstable_tag or tag["FriendlyName"] > last_unstable_tag:
                            last_unstable_tag = tag["FriendlyName"]
                    else:
                        tag["unstable"] = False
                        tag["stable"] = True
                        if not last_stable_tag or tag["FriendlyName"] > last_stable_tag:
                            last_stable_tag = tag["FriendlyName"]
                except ValueError:
                    pass

            try:
                tag["addinfo"] = self.get_annotated_tag(project_id, repo_id, tag['objectId'])
                if tag["addinfo"]:
                    try:
                        tag["CommitId"] = tag["addinfo"]["taggedObject"]["objectId"][:7]
                    except Exception:
                        logger.warning("Ignore error - cannot work with taggedObject %s, %s", repo_id, tag['objectId'])
            except Exception:
                tag["addinfo"] = None

            if tag.get("CommitId") and tag.get("addinfo"):
                try:
                    date_str = tag["addinfo"]["taggedBy"]["date"]
                    tag_date_obj = parse_iso_datetime(date_str)
                    if tag_date_obj:
                        tag_date_obj = tag_date_obj + timedelta(hours=1)
                        tag["CommitDateObj"] = tag_date_obj
                        tag["CommitDate"] = UpdateDateString(tag_date_obj)
                    tag["Committer"] = tag["addinfo"]["taggedBy"]["name"]
                    tag["CommentComplete"] = tag["addinfo"].get("message", "").replace("\n", " ")
                    if len(tag["CommentComplete"]) > 50:
                        tag["Comment"] = tag["CommentComplete"][:46] + "..."
                    else:
                        tag["Comment"] = tag["CommentComplete"]
                except Exception as e:
                    logger.error("Error parsing annotated tag info for %s: %s", tag['FriendlyName'], e)

            tags_filtered.append(tag)

        tags_filtered.reverse()
        tags_filtered = tags_filtered[:10]

        if tags_filtered:
            repo["LatestTag"] = tags_filtered[0]
        else:
            repo["LatestTag"] = {"FriendlyName": "", "CommitDate": ""}

        return tags_filtered, last_stable_tag, last_unstable_tag

    def _process_pushes_and_prs(self, project_id, repo, cache_db=None):
        """Scans push events and fetches all active and merged Pull Requests."""
        dev_prs = []
        stable_prs = []
        repo_id = repo["id"]
        repo_name = repo.get("name", "")
        prs_list = []

        # 1. If database cache is available, re-check any PRs currently recorded as active
        if cache_db is not None:
            try:
                active_db_prs = cache_db.get_active_pull_requests(repo_id)
                for db_pr in active_db_prs:
                    p_id_str = str(db_pr.get("id"))
                    if p_id_str and p_id_str not in prs_list:
                        prs_list.append(p_id_str)
            except Exception as e:
                logger.debug("Could not query active PRs from DB for %s: %s", repo_name, e)

        # 2. Scan push details for merged PRs
        pushes = []
        try:
            pushes = self.get_pushes(project_id, repo_id)
        except Exception as e:
            logger.error("Error fetching pushes for %s: %s", repo_name, e)

        for push_meta in pushes:
            try:
                push_detail = self.get_push_detail(project_id, repo_id, push_meta['pushId'])
                ref_updates = push_detail.get("refUpdates", [])
                for ref_up in ref_updates:
                    match = re.search(r"refs/pull/(\d+)/merge", ref_up.get("name", ""))
                    if match:
                        pr_id = match.group(1)
                        if pr_id not in prs_list:
                            prs_list.append(pr_id)
            except Exception as e:
                logger.error("Error retrieving push detail for %s: %s", repo_name, e)

        # 3. Also fetch all PRs that have not been closed yet (active PRs)
        try:
            active_prs = self.get_pull_requests(project_id, repo_id, status="active")
            for a_pr in active_prs:
                a_id = str(a_pr.get("pullRequestId") or a_pr.get("id") or "")
                if a_id and a_id not in prs_list:
                    prs_list.append(a_id)
        except Exception as e:
            logger.error("Error fetching active pull requests for %s: %s", repo_name, e)

        from utils import normalize_pr_status
        for pr_id in prs_list:
            try:
                pr = self.get_pull_request(pr_id)
                _enrich_pr(pr, normalize_pr_status)
                if "dev" in pr.get("targetRefName", ""):
                    dev_prs.append(pr)
                else:
                    stable_prs.append(pr)
            except Exception as e:
                logger.error("Error fetching PR %s details: %s", pr_id, e)

        return dev_prs, stable_prs

    def sync_pull_requests(self, cache_db, project_id=None, filter_repos=""):
        """
        Directly synchronizes pull request states between TFS and SQLite database.
        Phase 1: Refreshes all PRs currently recorded as active in SQLite (detects completion/abandonment).
        Phase 2: Incrementally scans for new PRs across all repositories, stopping at max_known_pr_id.
        """
        if not cache_db:
            return {"synced": 0, "updated": 0, "new": 0, "errors": 0}
        
        proj = project_id or getattr(self, "project_id", "")
        summary = {"synced": 0, "updated": 0, "new": 0, "errors": 0}
        from utils import normalize_pr_status
        
        # Phase 1: Re-check all PRs currently stored in SQLite as active
        active_db_prs = cache_db.get_active_pull_requests()
        for db_pr in active_db_prs:
            pr_id = str(db_pr.get("id"))
            try:
                live_pr = self.get_pull_request(pr_id)
                if live_pr:
                    _enrich_pr(live_pr, normalize_pr_status)
                    old_st = normalize_pr_status(db_pr.get("status"))
                    if old_st != live_pr["status"]:
                        logger.info("PR #%s status changed: %s -> %s", pr_id, old_st, live_pr["status"])
                        summary["updated"] += 1
                    
                    cache_db.save_single_pull_request(live_pr)
                    summary["synced"] += 1
            except Exception as e:
                logger.warning("Could not sync status for active PR #%s: %s", pr_id, e)
                summary["errors"] += 1

        # Phase 2: Incremental Scan for New PRs across enabled repositories
        if proj:
            try:
                repos = self.get_repositories(proj)
                for repo in repos:
                    if self._should_skip_repo(repo, filter_repos):
                        continue
                    new_count = self._fetch_new_prs_incremental(proj, repo, cache_db)
                    summary["new"] += new_count
                    summary["synced"] += new_count
            except Exception as e:
                logger.warning("Could not incrementally fetch new PRs for project %s: %s", proj, e)
                summary["errors"] += 1
        
        return summary

    def GetTFSRepositories(self, project_id, filter_version_tags_format=False, filter_repos="", cache_db=None):
        """
        Retrieves all repositories, branches, tags, pushes, pull requests, and submodules for a project,
        aggregating them into a structured dict. Uses SQLite cache database for fast sync.

        Args:
            project_id (str): The project ID or name.
            filter_version_tags_format (bool, optional): If True, filters out tags not matching tag philosophy. Defaults to False.
            filter_repos (str/list, optional): Filter repositories list. Defaults to "".
            cache_db (AzureDevOpsCache, optional): The database cache manager. Defaults to None.

        Returns:
            dict: A detailed map of repository names to their aggregated info (branches, tags, PRs, submodules, etc.).
        """
        try:
            repos = self.get_repositories(project_id)
        except Exception as e:
            logger.error("Error fetching repositories: %s", e)
            return {}

        result = {}
        for repo in repos:
            if self._should_skip_repo(repo, filter_repos):
                continue

            repo_name = repo.get("name", "")
            repo_id = repo["id"]
            logger.info("-- Repo: %s ENABLED", repo_name)

            # Delta Sync Check
            cached_repo, remote_push_id = self._get_cached_repo_if_up_to_date(project_id, repo, cache_db)
            if cached_repo:
                result[repo_name] = cached_repo
                continue

            # Load submodules
            submodules = []
            #try:
            #    submodules = self.ParseSubmodules(repo, project_id)
            #except Exception as e:
            #    logger.error("Error parsing submodules for %s: %s", repo_name, e)

            # Load branches
            branches = []
            try:
                branches = self.get_repository_refs(project_id, repo_id, "heads/")
            except Exception as e:
                logger.error("Error fetching branches for %s: %s", repo_name, e)

            b_we_have_dev_branch = self._process_branches(project_id, repo, branches)

            # Load tags
            tags_filtered, last_stable_tag, last_unstable_tag = self._process_tags(
                project_id, repo, filter_version_tags_format
            )

            # Load pushes and PRs (including active unclosed PRs)
            dev_prs, stable_prs = self._process_pushes_and_prs(project_id, repo, cache_db=cache_db)

            result[repo_name] = {
                "info": repo,
                "branches": branches,
                "tags": tags_filtered,
                "submodules": submodules,
                "devPRs": dev_prs,
                "stablePRs": stable_prs,
                "StableTag": last_stable_tag,
                "UnstableTag": last_unstable_tag
            }

            if cache_db is not None:
                try:
                    cache_db.save_repository(project_id, repo, remote_push_id)
                    cache_db.save_branches(repo_id, branches)
                    cache_db.save_tags(repo_id, tags_filtered)
                    cache_db.save_submodules(repo_id, submodules)
                    cache_db.save_pull_requests(repo_id, dev_prs + stable_prs)
                except Exception as e:
                    logger.error("  -- Failed to write %s cache to database: %s", repo_name, e)

        return result


    def GetTagsAndContainingBranches(self, project_id, repo_id):
        """
        Reads all tags from a repository and detects which branch(es) contain them.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID or name.

        Returns:
            list: A list of dicts, each with 'tag_name', 'commit_id', and 'branches' (list of branch names).
        """
        logger.info("Fetching tags and branches to map tags to their branches...")
        try:
            tags_refs = self.get_repository_refs(project_id, repo_id, "tags/")
            branches_refs = self.get_repository_refs(project_id, repo_id, "heads/")
        except Exception as e:
            logger.error("Failed to retrieve tags or branches for repository %s: %s", repo_id, e)
            return []

        # Map branch_name -> latest commit_id (branch tip)
        branch_tips = {}
        for b in branches_refs:
            b_name = b.get("name", "").replace("refs/heads/", "")
            b_commit = b.get("objectId")
            if b_name and b_commit:
                branch_tips[b_name] = b_commit

        # Pre-fetch recent commit history for each branch
        branch_histories = {}
        for b_name in branch_tips.keys():
            try:
                # Retrieve the last 100 commits for this branch to scan for tag commits
                commits = self.get_commits(project_id, repo_id, branch_name=b_name, limit=100)
                branch_histories[b_name] = {c.get("commitId") for c in commits if c.get("commitId")}
            except Exception as e:
                logger.error("Error fetching commit history for branch %s: %s", b_name, e)
                branch_histories[b_name] = set()

        results = []
        for tag in tags_refs:
            tag_name = tag.get("name", "").replace("refs/tags/", "")
            tag_commit = tag.get("objectId")

            containing_branches = []
            # 1. Check if it matches a branch tip directly
            for b_name, tip_commit in branch_tips.items():
                if tip_commit == tag_commit:
                    containing_branches.append(b_name)

            # 2. Check recent commit history of each branch
            if not containing_branches:
                for b_name, history in branch_histories.items():
                    if tag_commit in history:
                        containing_branches.append(b_name)

            results.append({
                "tag_name": tag_name,
                "commit_id": tag_commit,
                "branches": containing_branches
            })

        return results

