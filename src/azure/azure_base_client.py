# -*- coding: UTF-8 -*-
import urllib.request
import urllib.parse
import json
import base64
import ssl

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
            
        with urllib.request.urlopen(req, context=self.ssl_context) as response:
            content = response.read()
            if raw_text:
                return content.decode('utf-8'), response.status
            else:
                return json.loads(content.decode('utf-8')), response.status

    def get_distributed_task_tasks(self):
        """
        Retrieves the list of distributed task definitions.

        Returns:
            list: List of task definition dictionaries.
        """
        res, _ = self._request("GET", "_apis/distributedtask/tasks", params={"api-version": "6.0"})
        return res.get("value", [])

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

    def query_work_item_ids_wiql(self, project_id=None, query=None):
        """
        Queries work item IDs directly using WIQL without needing to know task IDs in advance.

        Args:
            project_id (str, optional): Target project ID or name. Defaults to None.
            query (str, optional): Custom WIQL query string. If None, queries all work items in project.

        Returns:
            list: List of integer work item IDs matching the query.
        """
        path = f"{project_id}/_apis/wit/wiql" if project_id else "_apis/wit/wiql"
        if not query:
            if project_id:
                query = f"SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = '{project_id}' ORDER BY [System.Id]"
            else:
                query = "SELECT [System.Id] FROM WorkItems ORDER BY [System.Id]"

        data = {"query": query}
        res, _ = self._request("POST", path, params={"api-version": "6.0"}, data=data)
        work_items = res.get("workItems", []) if isinstance(res, dict) else []
        return [item["id"] for item in work_items if "id" in item]

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

