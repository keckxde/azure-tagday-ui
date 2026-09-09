# -*- coding: UTF-8 -*-
import urllib.request
import urllib.parse
import json
import base64
import ssl
import re

import logging

logger = logging.getLogger(__name__)

class AzureBaseClient:
    """
    A base HTTP client for communicating with the Azure DevOps (TFS) REST API.
    Handles basic authentication, request encoding/decoding, and general request lifecycle.
    """

    def __init__(self, url, token):
        """
        Initializes the Azure DevOps base client.

        Args:
            url (str): The base URL of the TFS/Azure DevOps instance.
            token (str): The personal access token (PAT) for basic authentication.
        """
        self.url = url.rstrip('/')
        auth_str = f":{token}"
        encoded_auth = base64.b64encode(auth_str.encode('utf-8')).decode('utf-8')
        self.headers = {
            "Authorization": f"Basic {encoded_auth}",
            "Content-Type": "application/json"
        }
        # Ignore SSL certification errors for local/private server TFS
        self.ssl_context = ssl.create_default_context()
        self.ssl_context.check_hostname = False
        self.ssl_context.verify_mode = ssl.CERT_NONE

    def _request(self, method, path, params=None, data=None, raw_text=False):
        """
        Sends an HTTP request to the Azure DevOps API.

        Args:
            method (str): The HTTP method (e.g., 'GET', 'POST').
            path (str): The API endpoint path.
            params (dict, optional): URL query parameters. Defaults to None.
            data (dict, optional): Request JSON body. Defaults to None.
            raw_text (bool, optional): If True, returns decoded text response instead of JSON. Defaults to False.

        Returns:
            tuple: A tuple containing the response content (dict/str) and status code (int).
        """
        if path.startswith('http://') or path.startswith('https://'):
            full_url = path
        else:
            full_url = f"{self.url}/{path.lstrip('/')}"
        
        if params:
            query_str = urllib.parse.urlencode(params, doseq=True)
            full_url = f"{full_url}?{query_str}"
            
        req = urllib.request.Request(full_url, headers=self.headers, method=method)
        if data is not None:
            req.data = json.dumps(data).encode('utf-8')

        is_wiql = "_apis/wit/wiql" in full_url
        if is_wiql:
            query_text = data.get("query", "") if isinstance(data, dict) else ""
            print(f"[WIQL REQUEST] Method: {method} | URL: {full_url}\n[WIQL QUERY] {query_text}")
            logger.info("[WIQL REQUEST] Method: %s | URL: %s | Query: %s", method, full_url, query_text)

        try:
            with urllib.request.urlopen(req, context=self.ssl_context) as response:
                content = response.read()
                if is_wiql:
                    try:
                        parsed = json.loads(content.decode('utf-8'))
                        wi_count = len(parsed.get("workItems", [])) if isinstance(parsed, dict) else 0
                        rel_count = len(parsed.get("workItemRelations", [])) if isinstance(parsed, dict) else 0
                        print(f"[WIQL RESPONSE] Status: {response.status} | URL: {full_url} | Found: {wi_count} work items, {rel_count} relations")
                        logger.info("[WIQL RESPONSE] Status: %s | URL: %s | WorkItems: %d | Relations: %d", response.status, full_url, wi_count, rel_count)
                    except Exception as parse_ex:
                        print(f"[WIQL RESPONSE] Status: {response.status} | URL: {full_url} | Bytes: {len(content)}")
                if raw_text:
                    return content.decode('utf-8'), response.status
                else:
                    return json.loads(content.decode('utf-8')), response.status
        except urllib.error.HTTPError as err:
            try:
                err_body = err.read().decode('utf-8', errors='replace')
            except Exception:
                err_body = ""
            print(f"[HTTP ERROR {err.code}] {method} {full_url}\n[REQUEST DATA] {data}\n[SERVER ERROR RESPONSE]\n{err_body}")
            logger.error("[HTTP %s %s] URL: %s | Reason: %s | Response: %s", method, err.code, full_url, err.reason, err_body)
            raise err

    def get_distributed_task_tasks(self):
        """
        Retrieves the list of distributed task definitions.

        Returns:
            list: List of task definition dictionaries.
        """
        res, _ = self._request("GET", "_apis/distributedtask/tasks", params={"api-version": "6.0"})
        return res.get("value", [])

    def get_classification_nodes(self, project_id, structure_group="iterations", depth=4):
        """
        Retrieves the classification nodes tree (e.g. Iterations or Areas) for a project.

        Args:
            project_id (str): The project ID or name.
            structure_group (str, optional): 'iterations' or 'areas'. Defaults to 'iterations'.
            depth (int, optional): Depth of children to retrieve. Defaults to 4.

        Returns:
            dict: The classification node hierarchy dictionary.
        """
        path = f"{project_id}/_apis/wit/classificationnodes/{structure_group}"
        params = {"$depth": depth, "api-version": "6.0"}
        res, _ = self._request("GET", path, params=params)
        return res

    def create_classification_node(self, project_id, name, structure_group="iterations", start_date=None, finish_date=None, parent_path=None):
        """
        Creates a new classification node (e.g., an iteration / sprint) in Azure DevOps / TFS.

        Args:
            project_id (str): The target project ID or name.
            name (str): The name of the node (e.g. 'week-2635').
            structure_group (str, optional): 'iterations' or 'areas'. Defaults to 'iterations'.
            start_date (str, optional): Start date string (ISO format or YYYY-MM-DD).
            finish_date (str, optional): Finish/end date string (ISO format or YYYY-MM-DD).
            parent_path (str, optional): Path of parent node if creating a sub-iteration.

        Returns:
            dict: The created node definition returned by the API.
        """
        base_path = f"{project_id}/_apis/wit/classificationnodes/{structure_group}"
        path = f"{base_path}/{parent_path.strip('/')}" if parent_path else base_path
        
        data = {"name": name}
        attributes = {}
        if start_date:
            attributes["startDate"] = f"{start_date.split('T')[0]}T00:00:00Z" if "T" not in str(start_date) else str(start_date)
        if finish_date:
            attributes["finishDate"] = f"{finish_date.split('T')[0]}T23:59:59Z" if "T" not in str(finish_date) else str(finish_date)
        if attributes:
            data["attributes"] = attributes

        res, _ = self._request("POST", path, params={"api-version": "6.0"}, data=data)
        return res

    def get_pipelines(self, project_id):
        """
        Retrieves pipeline definitions for a specific project.

        Args:
            project_id (str): The target project ID or name.

        Returns:
            list: List of pipeline definition dictionaries.
        """
        res, _ = self._request("GET", f"{project_id}/_apis/pipelines", params={"api-version": "6.0-preview.1"})
        return res.get("value", [])

    def get_project_builds(self, project_id):
            """
            Retrieves builds definitions for a specific project.
    
            Args:
                project_id (str): The target project ID or name.
    
            Returns:
                list: List of pipeline definition dictionaries.
            """
            res, _ = self._request("GET", f"{project_id}/_apis/build/builds", params={})
            return res.get("value", [])

    def get_all_build_artifacts(self, project_id, cache_db=None):
        """
        Retrieves build definitions and artifacts for a specific project.
        Saves builds and artifacts into SQLite cache if cache_db is provided.

        Args:
            project_id (str): The target project ID or name.
            cache_db (AzureDevOpsCache, optional): Database cache instance.

        Returns:
            list: List of build dictionaries with associated artifacts.
        """
        builds = self.get_project_builds(project_id)
        print(f"Found {len(builds)} builds.\n")

        count = 0
        for i, build in enumerate(builds):
            try:
                build_id = build["id"]
                build_number = build.get("buildNumber", "")
                artifacts = self.get_build_artifacts(project_id, build_id, cache_db=cache_db)

                builds[i]["artifacts"] = artifacts or []

                if artifacts:
                    for artifact in artifacts:
                        artifact_name = artifact.get("name", "")
                        resource = artifact.get("resource") or {}
                        props = resource.get("properties") or {} if isinstance(resource, dict) else {}
                        artifact_size = props.get("artifactsize", 0) if isinstance(props, dict) else 0
                        try:
                            artifact_size_mb = int(artifact_size) / 1024 / 1024
                        except (ValueError, TypeError):
                            artifact_size_mb = 0.0

                        count += artifact_size_mb
                        print(f"{i}; #{build_number}; ID: {build_id}; {artifact_name}; {artifact_size_mb:.2f} MB; ")

                if cache_db:
                    cache_db.save_build(project_id, builds[i])
            except Exception as e:
                print(f"Error processing build {build.get('id')}: {e}")

        print(f"COUNT: {count:.2f} MB")
        return builds


    def delete_artifact(self, project_id, build_id, artifact_name, cache_db=None):
        """Deletes a specific artifact from a build and marks it deleted in cache_db if provided."""
        res, _ = self._request("DELETE", f"{project_id}/_apis/build/builds/{build_id}/artifacts", params={"artifactName": artifact_name})
        if cache_db:
            cache_db.mark_artifact_deleted(build_id, artifact_name)
        return res

    def get_build_artifacts(self, project_id, build_id, cache_db=None):
        """
        Retrieves build artifacts for a specific build.
        If a failure occurs in the response (e.g. 404, 410, or network exception),
        it assumes that the build artifact was deleted and records this deleted information
        in the database cache.

        Args:
            project_id (str): The target project ID or name.
            build_id (int/str): The build ID.
            cache_db (AzureDevOpsCache, optional): Database cache instance.

        Returns:
            list: List of artifact dictionaries, or marked deleted artifact records on failure.
        """
        try:
            res, status = self._request("GET", f"{project_id}/_apis/build/builds/{build_id}/artifacts", params={})
            if status >= 400:
                raise urllib.error.HTTPError(None, status, f"HTTP {status}", None, None)
            artifacts = res.get("value", []) if isinstance(res, dict) else []
            if cache_db and artifacts:
                cache_db.save_artifacts(build_id, artifacts)
            return artifacts
        except Exception as e:
            print(f"Warning: Failed to retrieve artifacts for build {build_id} in {project_id}: {e}. Assuming artifact was deleted.")
            if cache_db:
                cache_db.mark_build_artifacts_deleted(build_id)
            return [{
                "id": None,
                "build_id": build_id,
                "name": "[deleted]",
                "type": "Deleted",
                "size_bytes": 0,
                "size_mb": 0.0,
                "is_deleted": 1,
                "deleted": True
            }]

    def get_work_item(self, task_id):
        """
        Retrieves details of a specific work item by ID.

        Args:
            task_id (int/str): The ID of the work item.

        Returns:
            dict: The work item details dictionary.
        """
        res, _ = self._request("GET", f"_apis/wit/workitems/{task_id}", params={"api-version": "6.0"})
        return res

    def get_work_items_batch(self, task_ids, fields=None, expand=None, chunk_size=200):
        """
        Retrieves work items in batches of up to chunk_size (max 200) by IDs using POST _apis/wit/workitemsbatch.

        Args:
            task_ids (list): List of work item IDs (int or str).
            fields (list, optional): Specific field names to retrieve. Defaults to None.
            expand (str, optional): Expand options ('none', 'relations', 'fields', 'links', 'all'). Defaults to None.
            chunk_size (int, optional): Max IDs per batch request (Azure DevOps / TFS limit is 200). Defaults to 200.

        Returns:
            list: List of work item dictionaries returned by the API.
        """
        if not task_ids:
            return []

        clean_ids = []
        for tid in task_ids:
            try:
                clean_ids.append(int(str(tid).lstrip("#")))
            except (ValueError, TypeError):
                continue

        if not clean_ids:
            return []

        all_results = []
        for i in range(0, len(clean_ids), chunk_size):
            chunk = clean_ids[i:i + chunk_size]
            data = {"ids": chunk}
            if fields:
                data["fields"] = fields
            if expand:
                data["$expand"] = expand

            res, _ = self._request("POST", "_apis/wit/workitemsbatch", params={"api-version": "6.0"}, data=data)
            items = res.get("value", []) if isinstance(res, dict) else []
            all_results.extend(items)

        return all_results

    def query_work_item_ids_wiql(self, project_id=None, query=None, changed_since=None, time_precision=True):
        """
        Queries work item IDs directly using WIQL without needing to know task IDs in advance.
        Supports both flat work item queries (FROM WorkItems) and hierarchical link queries (FROM WorkItemLinks).
        Supports filtering by changed_since timestamp for high-performance incremental sync.

        Args:
            project_id (str, optional): Target project ID or name. Defaults to None.
            query (str, optional): Custom WIQL query string. If None, queries work items in project.
            changed_since (str or datetime, optional): Filter work items where System.ChangedDate >= changed_since.
            time_precision (bool, optional): Whether to request time precision. Defaults to True.

        Returns:
            list: List of integer work item IDs matching the query.
        """
        proj_part = urllib.parse.quote(str(project_id)) if project_id else ""
        path = f"{proj_part}/_apis/wit/wiql" if proj_part else "_apis/wit/wiql"
        params = {"timePrecision": "true", "api-version": "6.0"} if time_precision else {"timePrecision": "false", "api-version": "6.0"}

        def _build_wiql(with_time=True):
            where_clauses = []
            if project_id:
                where_clauses.append(f"[System.TeamProject] = '{project_id}'")
            if changed_since:
                if hasattr(changed_since, "strftime"):
                    fmt = "%Y-%m-%d %H:%M:%S" if with_time else "%Y-%m-%d"
                    date_str = changed_since.strftime(fmt)
                else:
                    date_str = str(changed_since).replace("T", " ").replace("Z", "").strip()
                    if "." in date_str:
                        date_str = date_str.split(".")[0]
                    if "+" in date_str:
                        date_str = date_str.split("+")[0]
                    date_str = re.sub(r'-\d{2}:?\d{2}$', '', date_str).strip()
                    if not with_time and " " in date_str:
                        date_str = date_str.split(" ")[0]
                where_clauses.append(f"[System.ChangedDate] >= '{date_str}'")

            where_str = f" WHERE {' AND '.join(where_clauses)}" if where_clauses else ""
            return f"SELECT [System.Id] FROM WorkItems{where_str} ORDER BY [System.Id]"

        wiql_query = query if query else _build_wiql(with_time=time_precision)
        data = {"query": wiql_query}

        try:
            res, _ = self._request("POST", path, params=params, data=data)
        except Exception as ex:
            err_str = str(ex).lower()
            if time_precision and ("cannot supply a time" in err_str or "date precision" in err_str or "system.changeddate" in err_str):
                logger.warning("WIQL query failed with date precision issue (%s). Retrying with date-only precision...", ex)
                fallback_query = _build_wiql(with_time=False) if not query else re.sub(r"'\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}'", lambda m: m.group(0).split()[0] + "'", query)
                fallback_params = {"timePrecision": "false", "api-version": "6.0"}
                res, _ = self._request("POST", path, params=fallback_params, data={"query": fallback_query})
            else:
                raise

        if not isinstance(res, dict):
            return []

        ids = []
        seen = set()

        # Flat query results
        for item in res.get("workItems", []):
            if isinstance(item, dict) and "id" in item:
                iid = item["id"]
                if iid not in seen:
                    seen.add(iid)
                    ids.append(iid)

        # Hierarchical / Link query results (Tree & OneHop)
        for rel in res.get("workItemRelations", []):
            if isinstance(rel, dict):
                for key in ("target", "source"):
                    node = rel.get(key)
                    if node and isinstance(node, dict) and "id" in node:
                        iid = node["id"]
                        if iid not in seen:
                            seen.add(iid)
                            ids.append(iid)

        return ids

    def query_work_item_hierarchy_wiql(self, project_id=None, query=None):
        """
        Executes a hierarchical Tree / Links WIQL query and returns relations structure.

        Args:
            project_id (str, optional): Target project ID or name.
            query (str, optional): Custom hierarchical WIQL query.

        Returns:
            list: List of workItemRelations dicts with 'source', 'target', and 'rel'.
        """
        proj_part = urllib.parse.quote(str(project_id)) if project_id else ""
        path = f"{proj_part}/_apis/wit/wiql" if proj_part else "_apis/wit/wiql"
        if not query:
            if project_id:
                query = (
                    f"SELECT [System.Id] FROM WorkItemLinks "
                    f"WHERE ([Source].[System.TeamProject] = '{project_id}') "
                    f"AND ([System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward') "
                    f"MODE (MustContain)"
                )
            else:
                query = (
                    "SELECT [System.Id] FROM WorkItemLinks "
                    "WHERE [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward' "
                    "MODE (MustContain)"
                )
        data = {"query": query}
        res, _ = self._request("POST", path, params={"api-version": "6.0"}, data=data)
        return res.get("workItemRelations", []) if isinstance(res, dict) else []

    def get_all_work_items_from_api(self, project_id=None, fields=None, expand=None, chunk_size=200):
        """
        Discovers and retrieves all available work items for a project directly from the API,
        without needing to know work item IDs in advance.

        Args:
            project_id (str, optional): Target project ID or name. Defaults to None.
            fields (list, optional): Specific field names to retrieve. Defaults to None.
            expand (str, optional): Expand options ('none', 'relations', 'fields', 'links', 'all'). Defaults to None.
            chunk_size (int, optional): Max IDs per batch request (limit 200). Defaults to 200.

        Returns:
            list: List of all work item dictionaries returned by the API.
        """
        wi_ids = self.query_work_item_ids_wiql(project_id)
        if not wi_ids:
            return []
        return self.get_work_items_batch(wi_ids, fields=fields, expand=expand, chunk_size=chunk_size)

    def get_recent_work_items(self):
        """
        Retrieves recent work items for the current user.

        Returns:
            list: List of recent work item dictionaries.
        """
        res, _ = self._request("GET", "_apis/wit/workitems/recents", params={"api-version": "6.0"})
        return res.get("value", [])

    def get_pull_request(self, pr_id):
        """
        Retrieves details of a specific pull request by ID.

        Args:
            pr_id (int/str): The ID of the pull request.

        Returns:
            dict: Pull request details dictionary.
        """
        res, _ = self._request("GET", f"_apis/git/pullrequests/{pr_id}", params={"api-version": "6.0"})
        return res

    def get_pull_requests(self, project_id, repo_id, status=None, top=None, skip=None):
        """
        Retrieves pull requests for a specific repository.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            status (str, optional): Status filter (e.g. 'active', 'completed', 'abandoned', 'all').
            top (int, optional): Number of pull requests to retrieve.
            skip (int, optional): Number of pull requests to skip.

        Returns:
            list: List of pull request dictionaries.
        """
        params = {"api-version": "6.0"}
        if status:
            params["searchCriteria.status"] = status
        if top is not None:
            params["$top"] = top
        if skip is not None:
            params["$skip"] = skip
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/pullrequests", params=params)
        return res.get("value", [])

    def get_repositories(self, project_id):
        """
        Retrieves all Git repositories for a specific project.

        Args:
            project_id (str): The target project ID or name.

        Returns:
            list: List of repository dictionaries.
        """
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories", params={"api-version": "6.0"})
        return res.get("value", [])

    def get_repository_items(self, project_id, repo_id, path, params=None, raw_text=False):
        """
        Retrieves details or content of a file/folder in a repository.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            path (str): The path to the item inside the repository.
            params (dict, optional): Additional request parameters. Defaults to None.
            raw_text (bool, optional): If True, returns file content as text instead of JSON metadata. Defaults to False.

        Returns:
            dict/str: The response containing file content or metadata.
        """
        req_params = {"path": path, "api-version": "6.0"}
        if params:
            req_params.update(params)
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/items", params=req_params, raw_text=raw_text)
        return res

    def get_repository_refs(self, project_id, repo_id, filter_str):
        """
        Retrieves git references (branches or tags) for a repository.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            filter_str (str): The reference filter (e.g. 'heads/' or 'tags/').

        Returns:
            list: List of reference dictionaries.
        """
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/refs", params={"filter": filter_str, "api-version": "6.0"})
        return res.get("value", [])

    def get_commit(self, project_id, repo_id, object_id):
        """
        Retrieves details of a specific commit.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            object_id (str): The commit hash / object ID.

        Returns:
            dict: Commit details dictionary.
        """
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/commits/{object_id}", params={"api-version": "6.0"})
        return res

    def get_branch_stats(self, project_id, repo_id, branch_name):
        """
        Retrieves branch stats (ahead/behind counts) relative to the default branch.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            branch_name (str): The name of the branch.

        Returns:
            dict: Branch stats dictionary.
        """
        quoted_branch = urllib.parse.quote(branch_name)
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/stats/branches/{quoted_branch}", params={"api-version": "6.0"})
        return res

    def get_diff(self, project_id, repo_id, base_version, target_version):
        """
        Retrieves branch diff/stats between base and target branch versions.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            base_version (str): The base branch name.
            target_version (str): The target branch name.

        Returns:
            dict: Diff or branch stats dictionary.
        """
        try:
            return self.get_branch_stats(project_id, repo_id, target_version)
        except Exception:
            params = {
                "api-version": "6.0",
                "baseVersion": base_version,
                "targetVersion": target_version
            }
            res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/diffs/commits", params=params)
            return res

    def get_annotated_tag(self, project_id, repo_id, object_id):
        """
        Retrieves details of an annotated tag.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            object_id (str): The object ID (annotated tag ID).

        Returns:
            dict: Annotated tag details dictionary.
        """
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/annotatedtags/{object_id}", params={"api-version": "6.0"})
        return res

    def get_pushes(self, project_id, repo_id):
        """
        Retrieves list of pushes to the repository.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.

        Returns:
            list: List of push dictionaries.
        """
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/pushes", params={"api-version": "6.0"})
        return res.get("value", [])

    def get_push_detail(self, project_id, repo_id, push_id):
        """
        Retrieves details of a specific push, including ref updates.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            push_id (int/str): The push ID.

        Returns:
            dict: Push details dictionary.
        """
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/pushes/{push_id}", params={"includeCommits": 0, "includeRefUpdates": True, "api-version": "6.0"})
        return res

    def get_commits(self, project_id, repo_id, branch_name=None, limit=100):
        """
        Retrieves commits for a repository with optional branch filtering.

        Args:
            project_id (str): The project ID or name.
            repo_id (str): The repository ID.
            branch_name (str, optional): The branch name to retrieve commits from.
            limit (int): Maximum number of commits to retrieve.

        Returns:
            list: List of commit dictionaries.
        """
        params = {"api-version": "6.0", "$top": limit}
        if branch_name:
            params["searchCriteria.itemVersion.version"] = branch_name
            params["searchCriteria.itemVersion.versionType"] = "branch"
        res, _ = self._request("GET", f"{project_id}/_apis/git/repositories/{repo_id}/commits", params=params)
        return res.get("value", [])

