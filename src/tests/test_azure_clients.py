# -*- coding: UTF-8 -*-
import os
import sys
import json
import base64
import unittest
from unittest.mock import patch, MagicMock
import urllib.error
import io

# Add py directory to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from azure import AzureBaseClient, AzureInfoBaseClient


class TestAzureBaseClient(unittest.TestCase):

    def setUp(self):
        self.base_url = "https://tfs.example.com/tfs"
        self.token = "my-secret-token"
        self.client = AzureBaseClient(self.base_url, self.token)

    def test_headers_and_initialization(self):
        expected_auth = base64.b64encode(f":{self.token}".encode("utf-8")).decode("utf-8")
        self.assertEqual(self.client.headers["Authorization"], f"Basic {expected_auth}")
        self.assertEqual(self.client.headers["Content-Type"], "application/json")
        self.assertFalse(self.client.ssl_context.check_hostname)

    @patch("urllib.request.urlopen")
    def test_request_get_json_success(self, mock_urlopen):
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = json.dumps({"value": [{"id": 1}]}).encode("utf-8")
        mock_urlopen.return_value.__enter__.return_value = mock_response

        data, status = self.client._request("GET", "DefaultCollection/_apis/projects", params={"api-version": "5.0"})
        self.assertEqual(status, 200)
        self.assertIn("value", data)
        self.assertEqual(data["value"][0]["id"], 1)

    @patch("urllib.request.urlopen")
    def test_request_post_json_success(self, mock_urlopen):
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = json.dumps({"id": 12345, "status": "created"}).encode("utf-8")
        mock_urlopen.return_value.__enter__.return_value = mock_response

        payload = {"name": "New Entity"}
        data, status = self.client._request("POST", "DefaultCollection/_apis/items", data=payload)
        self.assertEqual(status, 200)
        self.assertEqual(data["id"], 12345)

    @patch("urllib.request.urlopen")
    def test_request_http_error(self, mock_urlopen):
        error_fp = io.BytesIO(b'{"message": "Not Found"}')
        http_err = urllib.error.HTTPError(
            url="https://tfs.example.com",
            code=404,
            msg="Not Found",
            hdrs={},
            fp=error_fp
        )
        mock_urlopen.side_effect = http_err

        with self.assertRaises(urllib.error.HTTPError):
            self.client._request("GET", "nonexistent/endpoint")
        http_err.close()

    @patch.object(AzureBaseClient, "_request")
    def test_get_repositories(self, mock_request):
        mock_request.return_value = ({"value": [{"id": "repo-1", "name": "test-repo-1"}]}, 200)
        repos = self.client.get_repositories("proj-1")
        self.assertEqual(len(repos), 1)
        self.assertEqual(repos[0]["name"], "test-repo-1")
        mock_request.assert_called_once_with("GET", "proj-1/_apis/git/repositories", params={"api-version": "6.0"})

    @patch.object(AzureBaseClient, "_request")
    def test_get_pull_request(self, mock_request):
        mock_request.return_value = ({"pullRequestId": 27676, "title": "Test PR"}, 200)
        pr = self.client.get_pull_request(27676)
        self.assertIsNotNone(pr)
        self.assertEqual(pr["pullRequestId"], 27676)

    @patch.object(AzureBaseClient, "_request")
    def test_get_pull_requests(self, mock_request):
        mock_request.return_value = ({"value": [{"pullRequestId": 27676, "title": "Active PR", "status": "active"}]}, 200)
        prs = self.client.get_pull_requests("proj-1", "repo-1", status="active")
        self.assertEqual(len(prs), 1)
        self.assertEqual(prs[0]["pullRequestId"], 27676)
        self.assertEqual(prs[0]["status"], "active")
        mock_request.assert_called_once_with(
            "GET",
            "proj-1/_apis/git/repositories/repo-1/pullrequests",
            params={"api-version": "6.0", "searchCriteria.status": "active"}
        )


class TestAzureInfoBaseClient(unittest.TestCase):

    def setUp(self):
        self.base_url = "https://tfs.example.com/tfs"
        self.token = "my-secret-token"
        self.client = AzureInfoBaseClient(self.base_url, self.token)

    @patch.object(AzureInfoBaseClient, "_request")
    def test_get_project_builds(self, mock_request):
        mock_request.return_value = (
            {"value": [{"id": 5001, "buildNumber": "2026.1", "status": "completed"}]},
            200
        )
        builds = self.client.get_project_builds("proj-1")
        self.assertEqual(len(builds), 1)
        self.assertEqual(builds[0]["id"], 5001)

    @patch.object(AzureInfoBaseClient, "get_project_builds")
    @patch.object(AzureInfoBaseClient, "get_build_artifacts")
    def test_get_all_build_artefacts_and_cache(self, mock_get_arts, mock_get_builds):
        mock_get_builds.return_value = [
            {"id": 5001, "buildNumber": "2026.1", "status": "completed"}
        ]
        mock_get_arts.return_value = [
            {"id": 1, "name": "dist", "resource": {"properties": {"artifactsize": 1048576}, "downloadUrl": "https://example.com/dist"}}
        ]
        mock_db = MagicMock()

        builds = self.client.get_all_build_artifacts("proj-1", cache_db=mock_db)
        self.assertEqual(len(builds), 1)
        self.assertEqual(builds[0]["id"], 5001)
        self.assertEqual(builds[0]["artifacts"][0]["name"], "dist")
        mock_db.save_build.assert_called_once()

    @patch.object(AzureInfoBaseClient, "_request")
    def test_get_build_artifacts_success(self, mock_request):
        mock_request.return_value = ({"value": [{"id": 10, "name": "binaries"}]}, 200)
        mock_db = MagicMock()
        artifacts = self.client.get_build_artifacts("proj-1", 5001, cache_db=mock_db)
        self.assertEqual(len(artifacts), 1)
        self.assertEqual(artifacts[0]["name"], "binaries")
        mock_db.save_artifacts.assert_called_once_with(5001, artifacts)

    @patch.object(AzureInfoBaseClient, "_request")
    def test_get_build_artifacts_failure_assumes_deleted(self, mock_request):
        # Simulate 404 failure from TFS
        mock_request.return_value = ({"message": "Artifact not found or deleted"}, 404)
        mock_db = MagicMock()
        artifacts = self.client.get_build_artifacts("proj-1", 5001, cache_db=mock_db)
        self.assertEqual(len(artifacts), 1)
        self.assertEqual(artifacts[0]["name"], "[deleted]")
        self.assertEqual(artifacts[0]["is_deleted"], 1)
        # Database marks artifacts for build 5001 as deleted
        mock_db.mark_build_artifacts_deleted.assert_called_once_with(5001)

    @patch.object(AzureInfoBaseClient, "_request")
    def test_delete_artifact(self, mock_request):
        mock_request.return_value = ({}, 200)
        mock_db = MagicMock()
        self.client.delete_artifact("proj-1", 5001, "drop", cache_db=mock_db)
        mock_request.assert_called_once_with(
            "DELETE", "proj-1/_apis/build/builds/5001/artifacts", params={"artifactName": "drop"}
        )
        mock_db.mark_artifact_deleted.assert_called_once_with(5001, "drop")


class TestAzureInfoHandlerTags(unittest.TestCase):

    def setUp(self):
        from azure.azure_info_handler import AzureInfoHandler
        self.handler = AzureInfoHandler("https://tfs.example.com/tfs", "dummy-pat")

    @patch.object(AzureInfoBaseClient, "get_repository_refs")
    @patch.object(AzureInfoBaseClient, "get_annotated_tag")
    def test_process_tags_filtering_and_classification(self, mock_get_annotated, mock_get_refs):
        mock_get_refs.return_value = [
            {"name": "refs/tags/v1.00.0", "objectId": "obj1"},
            {"name": "refs/tags/v1.01.0", "objectId": "obj2"},
            {"name": "refs/tags/v1.02.0", "objectId": "obj3"},
            {"name": "refs/tags/invalid_tag", "objectId": "obj4"},
        ]
        mock_get_annotated.return_value = {
            "taggedObject": {"objectId": "abcdef123456"},
            "taggedBy": {"name": "Dev", "date": "2026-03-01T10:00:00Z"},
            "message": "Release v1.02.0"
        }
        repo = {"id": "repo-123", "name": "Repo1"}

        tags, last_stable, last_unstable = self.handler._process_tags("proj-1", repo, filter_version_tags_format=True)

        self.assertEqual(len(tags), 3)
        self.assertEqual(last_stable, "v1.02.0")
        self.assertEqual(last_unstable, "v1.01.0")
        self.assertIn("LatestTag", repo)
        self.assertEqual(repo["LatestTag"]["FriendlyName"], "v1.02.0")

    def test_process_branches_with_get_diff(self):
        repo = {"id": "repo-123", "name": "Repo1", "defaultBranch": "refs/heads/main"}
        branches = [
            {"name": "refs/heads/main", "objectId": "sha1111111"},
            {"name": "refs/heads/dev", "objectId": "sha2222222"}
        ]
        self.handler.get_commit = MagicMock(return_value={
            "committer": {"name": "Alice", "date": "2026-03-01T10:00:00Z"},
            "comment": "Dev commit"
        })
        self.handler.get_diff = MagicMock(return_value={"aheadCount": 3, "behindCount": 1})

        has_dev = self.handler._process_branches("proj-1", repo, branches)

        self.assertTrue(has_dev)
        dev_branch = next(b for b in branches if b["FriendlyName"] == "dev")
        self.assertEqual(dev_branch["Ahead"], 3)
        self.assertEqual(dev_branch["Behind"], 1)
        self.assertEqual(dev_branch["Stats"]["aheadCount"], 3)
        self.assertEqual(dev_branch["Stats"]["behindCount"], 1)


if __name__ == "__main__":
    unittest.main()
