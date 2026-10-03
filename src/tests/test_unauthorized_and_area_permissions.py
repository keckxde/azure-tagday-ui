import os
import io
import sys
import unittest
import urllib.error
from unittest.mock import MagicMock, patch

py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from azure.azure_base_client import AzureBaseClient, AzureAuthenticationError, AzureServerConnectionError
from azure.azure_info_handler import AzureInfoHandler
from azure.azure_db import is_work_item_in_area_path


class TestAzureUnauthorizedAndAreaPermissions(unittest.TestCase):

    def test_azure_base_client_raises_authentication_error_on_401(self):
        client = AzureBaseClient("https://dev.azure.com/fakeorg", "faketoken")
        mock_http_err = urllib.error.HTTPError(
            url="https://dev.azure.com/fakeorg/_apis/projects",
            code=401,
            msg="Unauthorized",
            hdrs={},
            fp=io.BytesIO(b"Access Denied: Invalid PAT token.")
        )

        with patch("urllib.request.urlopen", side_effect=mock_http_err):
            with self.assertRaises(AzureAuthenticationError) as ctx:
                client._request("GET", "https://dev.azure.com/fakeorg/_apis/projects")

            err_msg = str(ctx.exception)
            self.assertIn("401", err_msg)
            self.assertIn("Personal Access Token (PAT)", err_msg)
            self.assertIn("Work Items (Read & Write)", err_msg)
            self.assertIn("Project and Team (Read)", err_msg)
            # Must also be an instance of AzureServerConnectionError for backward compatibility
            self.assertIsInstance(ctx.exception, AzureServerConnectionError)

    def test_azure_base_client_raises_authentication_error_on_403(self):
        client = AzureBaseClient("https://dev.azure.com/fakeorg", "faketoken")
        mock_http_err = urllib.error.HTTPError(
            url="https://dev.azure.com/fakeorg/_apis/work/teamsettings/teamfieldvalues",
            code=403,
            msg="Forbidden",
            hdrs={},
            fp=io.BytesIO(b"User does not have team settings permissions.")
        )

        with patch("urllib.request.urlopen", side_effect=mock_http_err):
            with self.assertRaises(AzureAuthenticationError) as ctx:
                client._request("GET", "https://dev.azure.com/fakeorg/_apis/work/teamsettings/teamfieldvalues")

            err_msg = str(ctx.exception)
            self.assertIn("403", err_msg)
            self.assertIn("Personal Access Token (PAT)", err_msg)
            self.assertIsInstance(ctx.exception, AzureServerConnectionError)

    def test_get_project_area_path_settings_fallback_on_401_403(self):
        handler = AzureInfoHandler("https://dev.azure.com/fakeorg", "faketoken")

        # Simulate 401/403 when trying to fetch teamfieldvalues and classification nodes
        auth_err = AzureAuthenticationError("HTTP 401 Unauthorized - Update PAT scopes.")
        with patch.object(handler, '_request', side_effect=auth_err):
            result = handler.get_project_area_path_settings("MyProject", "MyTeam")

            self.assertIsNotNone(result)
            self.assertTrue(result.get("had_permission_error"))
            self.assertEqual(result.get("default_area"), "MyProject")
            rules = result.get("rules", [])
            self.assertEqual(len(rules), 1)
            self.assertEqual(rules[0]["path"], "MyProject")
            self.assertTrue(rules[0]["include_children"])
            self.assertIn("MyProject", result.get("all_areas", []))

    def test_area_path_matching_works_with_manual_rules(self):
        # Define manual rules without needing server permissions
        manual_rules = [
            {"path": "MyProject\\TeamAlpha", "include_children": True},
            {"path": "MyProject\\Legacy\\Core", "include_children": False}
        ]

        # Exact and sub-area matches
        self.assertTrue(is_work_item_in_area_path("MyProject\\TeamAlpha", manual_rules))
        self.assertTrue(is_work_item_in_area_path("MyProject\\TeamAlpha\\SubModule", manual_rules))
        self.assertTrue(is_work_item_in_area_path("MyProject\\Legacy\\Core", manual_rules))
        # Excluded sub-area since include_children is False
        self.assertFalse(is_work_item_in_area_path("MyProject\\Legacy\\Core\\Extra", manual_rules))
        # Unrelated path
        self.assertFalse(is_work_item_in_area_path("MyProject\\TeamBeta", manual_rules))


if __name__ == '__main__':
    unittest.main()
