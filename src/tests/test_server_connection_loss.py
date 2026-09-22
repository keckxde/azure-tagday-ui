# -*- coding: UTF-8 -*-
import os
import shutil
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import urllib.error
import socket

from azure import AzureBaseClient, AzureInfoHandler, AzureDevOpsCache, AzureServerConnectionError, is_connection_error
import devops_helper
from gui.backend import DevOpsBackend


class TestServerConnectionLoss(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_conn.db")
        self.cache = AzureDevOpsCache(self.db_path)
        self.handler = AzureInfoHandler("https://tfs.test.com/tfs/DefaultCollection", "dummy_token")

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_is_connection_error_detection(self):
        """Verifies that is_connection_error correctly identifies network and server outage exceptions."""
        self.assertTrue(is_connection_error(AzureServerConnectionError("Connection dropped")))
        self.assertTrue(is_connection_error(urllib.error.URLError("Connection refused")))
        self.assertTrue(is_connection_error(urllib.error.HTTPError("http://test", 503, "Service Unavailable", {}, None)))
        self.assertTrue(is_connection_error(urllib.error.HTTPError("http://test", 502, "Bad Gateway", {}, None)))
        self.assertTrue(is_connection_error(urllib.error.HTTPError("http://test", 504, "Gateway Timeout", {}, None)))
        self.assertTrue(is_connection_error(urllib.error.HTTPError("http://test", 401, "Unauthorized", {}, None)))
        self.assertTrue(is_connection_error(TimeoutError("Operation timed out")))
        self.assertTrue(is_connection_error(ConnectionResetError("Connection reset by peer")))
        self.assertTrue(is_connection_error(socket.gaierror(-2, "Name or service not known")))
        self.assertTrue(is_connection_error(RuntimeError("WinError 10060 A connection attempt failed")))

        # Normal errors should return False
        self.assertFalse(is_connection_error(urllib.error.HTTPError("http://test", 404, "Not Found", {}, None)))
        self.assertFalse(is_connection_error(ValueError("Invalid argument")))
        self.assertFalse(is_connection_error(None))

    def test_azure_base_client_request_raises_connection_error_on_urlerror(self):
        """Verifies AzureBaseClient._request raises AzureServerConnectionError on network connection failure."""
        client = AzureBaseClient("https://unreachable.server.local", "pat")
        with patch("urllib.request.urlopen", side_effect=urllib.error.URLError(socket.gaierror(-2, "Name or service not known"))):
            with self.assertRaises(AzureServerConnectionError) as ctx:
                client._request("GET", "_apis/projects")
            self.assertIn("Lost connection to repository server", str(ctx.exception))

    def test_azure_base_client_request_raises_connection_error_on_http_503(self):
        """Verifies AzureBaseClient._request raises AzureServerConnectionError on 503 Service Unavailable."""
        client = AzureBaseClient("https://tfs.server.local", "pat")
        with patch("urllib.request.urlopen", side_effect=urllib.error.HTTPError("https://tfs.server.local", 503, "Service Unavailable", {}, None)):
            with self.assertRaises(AzureServerConnectionError) as ctx:
                client._request("GET", "_apis/projects")
            self.assertIn("Repository server unavailable", str(ctx.exception))

    def test_get_tfs_repositories_aborts_on_connection_error(self):
        """Verifies GetTFSRepositories raises AzureServerConnectionError and immediately stops sync."""
        with patch.object(self.handler, "get_repositories", side_effect=AzureServerConnectionError("Lost connection to server")):
            with self.assertRaises(AzureServerConnectionError):
                self.handler.GetTFSRepositories("TEST_PROJ", cache_db=self.cache)

    def test_get_tfs_repositories_parallel_worker_stops_on_connection_error(self):
        """Verifies that if a repository worker loses connection, GetTFSRepositories aborts immediately."""
        fake_repos = [
            {"id": "r1", "name": "repo1", "isDisabled": False},
            {"id": "r2", "name": "repo2", "isDisabled": False},
        ]
        with patch.object(self.handler, "get_repositories", return_value=fake_repos):
            with patch.object(self.handler, "_get_cached_repo_if_up_to_date", return_value=(None, 1)):
                with patch.object(self.handler, "get_repository_refs", side_effect=AzureServerConnectionError("Connection refused by server")):
                    with self.assertRaises(AzureServerConnectionError):
                        self.handler.GetTFSRepositories("TEST_PROJ", cache_db=self.cache)

    def test_sync_work_items_aborts_on_wiql_connection_error(self):
        """Verifies sync_work_items raises AzureServerConnectionError on WIQL discovery connection loss."""
        # Seed cache with an item to ensure it does not mistakenly delete it
        self.cache.save_work_item(100, "Existing Task", "Task", "Active", "Alice", "2026-01-01", {}, deleted=0)

        with patch.object(self.handler, "query_work_item_ids_wiql", side_effect=AzureServerConnectionError("Lost connection to repository server")):
            with self.assertRaises(AzureServerConnectionError):
                self.handler.sync_work_items(self.cache, project_id="TEST_PROJ")

        # Ensure existing cached work item was NOT deleted
        wi = self.cache.get_work_item(100)
        self.assertIsNotNone(wi)
        self.assertEqual(wi["deleted"], 0)

    def test_sync_work_items_aborts_on_batch_connection_error(self):
        """Verifies sync_work_items raises AzureServerConnectionError during batch download on connection loss."""
        with patch.object(self.handler, "query_work_item_ids_wiql", return_value=[201, 202]):
            with patch.object(self.handler, "get_work_items_batch", side_effect=AzureServerConnectionError("Connection timed out")):
                with self.assertRaises(AzureServerConnectionError):
                    self.handler.sync_work_items(self.cache, project_id="TEST_PROJ")

    def test_sync_pull_requests_aborts_on_connection_error(self):
        """Verifies sync_pull_requests raises AzureServerConnectionError on connection loss during PR reconcile."""
        self.cache.save_single_pull_request({"id": 10, "repo_id": "r1", "status": "active", "title": "Active PR"})

        with patch.object(self.handler, "_safe_get_pr", side_effect=AzureServerConnectionError("Lost connection to repository server")):
            with self.assertRaises(AzureServerConnectionError):
                self.handler.sync_pull_requests(self.cache, project_id="TEST_PROJ")

    def test_devops_helper_sync_propagates_connection_error(self):
        """Verifies devops_helper.sync aborts execution and raises AzureServerConnectionError."""
        with patch("devops_helper._getHandler", return_value=self.handler):
            with patch("devops_helper._getDBCacheHandler", return_value=(self.db_path, self.cache)):
                with patch.object(self.handler, "GetTFSRepositories", side_effect=AzureServerConnectionError("Lost connection to repository server")):
                    with self.assertRaises(AzureServerConnectionError):
                        devops_helper.sync(force_sync=True)

    def test_backend_on_worker_finished_informs_user_on_connection_loss(self):
        """Verifies backend updates status message and emits connectionLost signal when connection is lost."""
        backend = DevOpsBackend()
        connection_lost_events = []
        backend.connectionLost.connect(lambda msg: connection_lost_events.append(msg))

        err_msg = "Lost connection to repository server (https://tfs.test.com): [WinError 10060] Connection timed out"
        backend._on_worker_finished(False, err_msg)

        self.assertIn("Lost connection to repository server", backend.statusMessage)
        self.assertEqual(len(connection_lost_events), 1)
        self.assertIn("Lost connection", connection_lost_events[0])


if __name__ == "__main__":
    unittest.main()
