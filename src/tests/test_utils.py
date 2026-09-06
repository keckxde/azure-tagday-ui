# -*- coding: UTF-8 -*-
import os
import sys
import tempfile
import json
import unittest
from datetime import datetime

# Add py directory to sys.path so utils is importable
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import utils


class TestUtils(unittest.TestCase):

    def test_uniqueList(self):
        input_list = ["  apple  ", "banana", "apple", " banana ", "cherry"]
        expected = ["apple", "banana", "cherry"]
        self.assertEqual(utils.uniqueList(input_list), expected)

    def test_uniqueList_empty(self):
        self.assertEqual(utils.uniqueList([]), [])

    def test_MatchUniqueRegularExpr(self):
        pattern = r"\b[A-Z]{2,}\b"
        source = "HELLO WORLD HELLO FOO BAR BAR"
        matches = utils.MatchUniqueRegularExpr(pattern, source)
        self.assertEqual(matches, ["HELLO", "WORLD", "FOO", "BAR"])

    def test_MatchUniqueRegularExpr_no_matches(self):
        pattern = r"\d+"
        source = "no numbers here"
        matches = utils.MatchUniqueRegularExpr(pattern, source)
        self.assertEqual(matches, [])

    def test_parse_iso_datetime_various_formats(self):
        # ISO with Z and milliseconds
        dt1 = utils.parse_iso_datetime("2025-06-15T14:30:00.123456Z")
        self.assertEqual(dt1, datetime(2025, 6, 15, 14, 30, 0))

        # Standard ISO format with T
        dt2 = utils.parse_iso_datetime("2025-06-15T14:30:00")
        self.assertEqual(dt2, datetime(2025, 6, 15, 14, 30, 0))

        # Space separated format
        dt3 = utils.parse_iso_datetime("2025-06-15 14:30:00")
        self.assertEqual(dt3, datetime(2025, 6, 15, 14, 30, 0))

        # Pass-through if already datetime
        existing_dt = datetime(2025, 1, 1, 12, 0, 0)
        self.assertEqual(utils.parse_iso_datetime(existing_dt), existing_dt)

        # None / empty / invalid
        self.assertIsNone(utils.parse_iso_datetime(None))
        self.assertIsNone(utils.parse_iso_datetime(""))
        self.assertIsNone(utils.parse_iso_datetime("invalid-date-string"))

    def test_UpdateDateString(self):
        # From string
        self.assertEqual(utils.UpdateDateString("2025-06-15T14:30:00Z"), "2025-06-15 14:30:00")
        # From datetime object
        dt = datetime(2025, 12, 31, 23, 59, 59)
        self.assertEqual(utils.UpdateDateString(dt), "2025-12-31 23:59:59")
        # Empty or invalid
        self.assertEqual(utils.UpdateDateString(""), "")
        self.assertEqual(utils.UpdateDateString(None), "")
        self.assertEqual(utils.UpdateDateString("not a date"), "")

    def test_GetEnvVariable(self):
        test_key = "TEST_CUSTOM_VAR_123"
        try:
            # Set variable
            os.environ[test_key] = "custom_value"
            self.assertEqual(utils.GetEnvVariable(test_key), "custom_value")

            # Remove variable and test default
            del os.environ[test_key]
            self.assertEqual(utils.GetEnvVariable(test_key, default="fallback"), "fallback")
            # Without default
            self.assertEqual(utils.GetEnvVariable(test_key), "")
        finally:
            if test_key in os.environ:
                del os.environ[test_key]

    def test_parseJSONFile(self):
        data = {"name": "TEST_APP", "version": "1.0", "items": [1, 2, 3]}
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False, encoding="utf-8") as tmp:
            json.dump(data, tmp)
            tmp_path = tmp.name

        try:
            parsed = utils.parseJSONFile(tmp_path)
            self.assertIsNotNone(parsed)
            self.assertEqual(parsed["name"], "TEST_APP")
            self.assertEqual(parsed["version"], "1.0")
            self.assertEqual(parsed["items"], [1, 2, 3])
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_parseJSONFile_nonexistent(self):
        result = utils.parseJSONFile("nonexistent_file_path_12345.json")
        self.assertIsNone(result)

    def test_parseYAMLFile(self):
        yaml_content = "project: TEST_PROJ\nbuild_status:\n  succeeded: icon-ok\n  failed: icon-fail\n"
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False, encoding="utf-8") as tmp:
            tmp.write(yaml_content)
            tmp_path = tmp.name

        try:
            parsed = utils.parseYAMLFile(tmp_path)
            self.assertIsNotNone(parsed)
            self.assertEqual(parsed["project"], "TEST_PROJ")
            self.assertEqual(parsed["build_status"]["succeeded"], "icon-ok")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_parseYAMLFile_nonexistent(self):
        result = utils.parseYAMLFile("nonexistent_file_path_12345.yaml")
        self.assertIsNone(result)

    def test_load_status_icons_default(self):
        icons = utils.load_status_icons()
        self.assertIn("build_status", icons)
        self.assertIn("artifact_status", icons)
        self.assertIn("tagday_status", icons)

        build_icons = utils.load_status_icons("build_status")
        self.assertIn("succeeded", build_icons)
        self.assertIn("failed", build_icons)
        self.assertIn("partiallySucceeded", build_icons)
        self.assertIn("canceled", build_icons)

    def test_load_status_icons_custom_yaml(self):
        custom_content = """
build_status:
  succeeded: "CUSTOM_SUCCESS"
  failed: "CUSTOM_FAIL"
artifact_status:
  active: "CUSTOM_ACTIVE"
  deleted: "CUSTOM_DELETED"
"""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False, encoding="utf-8") as tmp:
            tmp.write(custom_content)
            tmp_path = tmp.name

        try:
            icons = utils.load_status_icons("build_status", custom_path=tmp_path)
            self.assertEqual(icons["succeeded"], "CUSTOM_SUCCESS")
            self.assertEqual(icons["failed"], "CUSTOM_FAIL")

            art_icons = utils.load_status_icons("artifact_status", custom_path=tmp_path)
            self.assertEqual(art_icons["active"], "CUSTOM_ACTIVE")
            self.assertEqual(art_icons["deleted"], "CUSTOM_DELETED")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_load_and_save_repo_categories(self):
        custom_content = """
default_category: "CUSTOM_OTHER"
prefix_rules:
  test-: "TEST"
repositories:
  custom-repo: "SPECIAL"
"""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False, encoding="utf-8") as tmp:
            tmp.write(custom_content)
            tmp_path = tmp.name

        try:
            config, resolved = utils.load_repo_categories(custom_path=tmp_path)
            self.assertEqual(config["default_category"], "CUSTOM_OTHER")
            self.assertEqual(config["repositories"].get("custom-repo"), "SPECIAL")

            import devops_helper
            repos = {
                "1": {"info": {"name": "custom-repo"}},
                "2": {"info": {"name": "test-module"}},
                "3": {"info": {"name": "unknown-repo"}},
            }
            devops_helper.addCategoriesToRepos(repos, config_path=tmp_path, auto_save_missing=True)

            self.assertEqual(repos["1"]["category"], "SPECIAL")
            self.assertEqual(repos["2"]["category"], "TEST")
            self.assertEqual(repos["3"]["category"], "CUSTOM_OTHER")

            # Verify that missing repos were persisted to the YAML file
            reloaded, _ = utils.load_repo_categories(custom_path=tmp_path)
            self.assertEqual(reloaded["repositories"].get("unknown-repo"), "CUSTOM_OTHER")
            self.assertEqual(reloaded["repositories"].get("test-module"), "TEST")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_get_category_color(self):
        custom_config = {
            "default_category": "OTHERS",
            "category_colors": {
                "SPECIAL": "#ff0000",
                "OTHERS": "#6e7681",
            }
        }
        self.assertEqual(utils.get_category_color("SPECIAL", config=custom_config), "#ff0000")
        self.assertEqual(utils.get_category_color("UNKNOWN_CAT", config=custom_config), "#6e7681")


if __name__ == "__main__":
    unittest.main()

