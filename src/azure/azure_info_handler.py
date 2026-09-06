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


from utils import UpdateDateString,parse_iso_datetime, timedelta
try:
    from .azure_info_base_client import AzureBaseClient
except ImportError:
    from azure_info_base_client import AzureBaseClient

logger = logging.getLogger(__name__)

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

    def sync_work_items(self, cache_db, project_id=None, chunk_size=200):
        """
        Synchronizes all work items in the SQLite database cache with the TFS API.
        Always queries the TFS API directly using WIQL:
        1. Directly queries all available work items from the TFS API using WIQL.
        2. Retrieves all work items in high-speed batches using POST _apis/wit/workitemsbatch.
        3. Updates/inserts active work items with deleted=0.
        4. Any previously cached work item in the database that is no longer returned by the API is marked as deleted=1.

        Args:
            cache_db (AzureDevOpsCache): Database cache instance.
            project_id (str, optional): Project ID or name. Defaults to None.
            chunk_size (int, optional): Max IDs per batch request (Azure DevOps / TFS limit is 200). Defaults to 200.

        Returns:
            dict: Summary of synced, deleted, and error counts.
        """
        summary = {"synced": 0, "deleted": 0, "errors": 0}
        db_ids = set(cache_db.get_all_work_item_ids(include_deleted=True))

        # Always query the API directly without needing known task IDs
        try:
            remote_ids = self.query_work_item_ids_wiql(project_id)
            logger.info("WIQL discovered %d available work items in TFS", len(remote_ids))
            # Combine remote IDs with any IDs previously stored in DB to check for deletions
            target_ids = list(set(remote_ids) | db_ids)
        except Exception as wiql_err:
            logger.warning("WIQL query failed (%s), falling back to cached DB IDs", wiql_err)
            target_ids = list(db_ids)

        clean_ids = []
        for tid in target_ids:
            try:
                clean_ids.append(int(str(tid).lstrip("#")))
            except (ValueError, TypeError):
                continue

        if not clean_ids:
            return summary

        found_ids = set()

        for i in range(0, len(clean_ids), chunk_size):
            chunk = clean_ids[i:i + chunk_size]
            try:
                batch_items = self.get_work_items_batch(chunk, chunk_size=chunk_size)
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

                for tid in chunk:
                    if tid not in found_ids:
                        logger.warning(" - sync_work_items: #%s not returned by API batch. Marking as deleted.", tid)
                        cache_db.mark_work_item_deleted(tid)
                        summary["deleted"] += 1

            except Exception as batch_err:
                logger.warning(" - sync_work_items: batch request failed (%s). Falling back to individual requests.", batch_err)
                for task_id in chunk:
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
        """Checks if cached repository details are up to date via latest push ID comparison."""
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
                    cached_repo = cache_db.get_cached_repository(repo_id, repo_name)
                    if cached_repo:
                        logger.info("  -- Repo %s is up to date (Push ID: %s). Skipping remote query.", repo_name, remote_push_id)
                        return cached_repo, remote_push_id
                return None, remote_push_id
        except Exception as e:
            logger.warning("  -- Failed to check push ID for %s: %s", repo_name, e)
        return None, None

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
                        branch["Stats"] = self.get_branch_stats(project_id, repo_id, branch['FriendlyName'])
                    except Exception:
                        branch["Stats"] = {"aheadCount": -1, "behindCount": -1}

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

    def _process_tags(self, project_id, repo, filter_version_tags_format=True):
        """Filters tags, extracts annotated tag information, and returns stable/unstable lists."""
        tags_filtered = []
        last_stable_tag = ""
        last_unstable_tag = ""
        repo_id = repo["id"]

        tags = []
        try:
            tags = self.get_repository_refs(project_id, repo_id, "tags/")
        except Exception as e:
            logger.error("Error fetching tags for %s: %s", repo["name"], e)
            return

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
                    major = 0 
                    major_v_splits = version_parts[0].split("v")
                    if len(major_v_splits)>0:
                        major = int(major_v_splits[1])
                    minor = int(version_parts[1])
                    patch = int(version_parts[2].split("-")[0])
                    tag["FriendlyName"] = f"v{major:02d}.{minor:02d}.{patch:04d}"

                    # todo: Try to understand if we can get the information here to see to which branch a Tag / Tagged Commit actually belongs
                    # then we can get rid of the declaration with even/uneven numbers for the minor versions
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

    def _process_pushes_and_prs(self, project_id, repo):
        """Scans push events to find all Pull Requests merged since the latest tag."""
        dev_prs = []
        stable_prs = []
        repo_id = repo["id"]
        repo_name = repo.get("name", "")
        prs_list = []
#        latest_tag_date = repo["LatestTag"].get("CommitDateObj")

        pushes = []
        try:
            pushes = self.get_pushes(project_id, repo_id)
        except Exception as e:
            logger.error("Error fetching pushes for %s: %s", repo_name, e)

        for push_meta in pushes:
            try:
                #push_date = parse_iso_datetime(push_meta.get("date"))
                #if latest_tag_date and push_date and push_date > latest_tag_date:
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

        for pr_id in prs_list:
            try:
                pr = self.get_pull_request(pr_id)
                pr["closedDateStr"] = UpdateDateString(pr.get("closedDate"))
                pr["creationDateStr"] = UpdateDateString(pr.get("creationDate"))

                status_val = pr.get("status")
                status_str = str(status_val).lower()
                if status_str in ("1", "active"):
                    pr["statusStr"] = f"OPN {pr['creationDateStr']}"
                elif status_str in ("3", "completed"):
                    pr["statusStr"] = f"DON {pr['closedDateStr']}"
                else:
                    pr["statusStr"] = f"REJECTED {pr['closedDateStr']}"

                if status_str in ("1", "3", "active", "completed"):
                    if "dev" in pr.get("targetRefName", ""):
                        dev_prs.append(pr)
                    else:
                        stable_prs.append(pr)
            except Exception as e:
                logger.error("Error fetching PR %s details: %s", pr_id, e)

        return dev_prs, stable_prs

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

            # Load pushes and PRs
            dev_prs, stable_prs = [], []
            if b_we_have_dev_branch:
                
                dev_prs, stable_prs = self._process_pushes_and_prs(project_id, repo)

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

