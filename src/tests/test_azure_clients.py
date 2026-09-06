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


if __name__ == "__main__":
    unittest.main()
