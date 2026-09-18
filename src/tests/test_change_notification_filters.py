# -*- coding: UTF-8 -*-
import os
import sys
import json
import tempfile
import unittest

py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from azure import AzureDevOpsCache
import utils
from gui.backend import DevOpsBackend


class TestChangeNotificationFilters(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmp_dir, "test_filters.db")
        self.cache = AzureDevOpsCache(self.db_path)
        self.backend = DevOpsBackend()
        self.backend._db_path = self.db_path
        self.backend._cache_db = self.cache

    def tearDown(self):
        del self.backend
        del self.cache
        import gc
        gc.collect()
        if os.path.exists(self.db_path):
            try:
                os.remove(self.db_path)
            except OSError:
                pass
        if os.path.exists(self.tmp_dir):
            try:
                os.rmdir(self.tmp_dir)
            except OSError:
                pass

    def test_pattern_matching_utils(self):
        # Case insensitive and wildcard tests
        self.assertTrue(utils.matches_pattern("DEPRECATED", "*deprecated*"))
        self.assertTrue(utils.matches_pattern("deprecated_apps", "*deprecated*"))
        self.assertTrue(utils.matches_pattern("Repo-Deprecated-Tool", "*deprecated*"))
        self.assertTrue(utils.matches_pattern("repo-deprecated-tool", "*DEPRECATED*"))
        self.assertTrue(utils.matches_pattern("REPO-DEPRECATED-TOOL", "*Deprecated*"))
        self.assertTrue(utils.matches_pattern("archive/feature-1", "*archive*"))
        self.assertTrue(utils.matches_pattern("ARCHIVE/FEATURE-1", "archive/*"))
        self.assertTrue(utils.matches_pattern("archive/FEATURE-1", "ARCHIVE/*"))
        self.assertTrue(utils.matches_pattern("test/experiment", "test/*"))
        self.assertTrue(utils.matches_pattern("TEST/EXPERIMENT", "test/*"))
        self.assertTrue(utils.matches_pattern("Demo-branch", "*demo*"))
        self.assertTrue(utils.matches_pattern("DEMO-BRANCH", "*DEMO*"))
        self.assertFalse(utils.matches_pattern("main", "*archive*"))
        self.assertFalse(utils.matches_pattern("MAIN", "*ARCHIVE*"))
        self.assertFalse(utils.matches_pattern("feature/login", "*archive*"))
        self.assertFalse(utils.matches_pattern("CORE", "*deprecated*"))

        # matches_any_pattern with mixed casing
        patterns = ["*Archive*", "*DEMO*", "*Deprecated*"]
        self.assertTrue(utils.matches_any_pattern("archive/v1", patterns))
        self.assertTrue(utils.matches_any_pattern("ARCHIVE/V1", patterns))
        self.assertTrue(utils.matches_any_pattern("DEMO_TEST", patterns))
        self.assertTrue(utils.matches_any_pattern("demo_test", patterns))
        self.assertTrue(utils.matches_any_pattern("My-Deprecated-App", patterns))
        self.assertFalse(utils.matches_any_pattern("feature/work", patterns))

    def test_default_patterns_loaded_when_db_empty(self):
        cats, branches = utils.load_change_filter_patterns(cache_db=self.cache)
        self.assertEqual(cats, ["*deprecated*"])
        self.assertIn("*archive*", branches)
        self.assertIn("*demo*", branches)
        self.assertIn("*deprecated*", branches)
        self.assertIn("*test*", branches)

    def test_save_and_load_change_filters_in_backend(self):
        new_cats = ["*deprecated*", "*legacy*", "*sandbox*"]
        new_branches = ["*archive*", "archive/*", "*wip*", "*temp*"]

        success = self.backend.save_change_filters(
            json.dumps(new_cats),
            json.dumps(new_branches)
        )
        self.assertTrue(success)

        # Check properties on backend
        self.assertEqual(self.backend.repoCategoryFilterPatterns, new_cats)
        self.assertEqual(self.backend.branchFilterPatterns, new_branches)

        # Check direct reading from DB
        db_cats_json = self.cache.get_config("IGNORE_REPO_CATEGORY_PATTERNS")
        db_branches_json = self.cache.get_config("IGNORE_BRANCH_PATTERNS")
        self.assertEqual(json.loads(db_cats_json), new_cats)
        self.assertEqual(json.loads(db_branches_json), new_branches)

    def test_reset_change_filters_to_defaults(self):
        # Save custom filters
        self.backend.save_change_filters(
            json.dumps(["*custom_cat*"]),
            json.dumps(["*custom_branch*"])
        )
        self.assertEqual(self.backend.repoCategoryFilterPatterns, ["*custom_cat*"])

        # Reset
        res = self.backend.reset_change_filters_to_defaults()
        self.assertTrue(res)
        self.assertEqual(self.backend.repoCategoryFilterPatterns, ["*deprecated*"])
        self.assertIn("*archive*", self.backend.branchFilterPatterns)

    def test_test_pattern_match_slot(self):
        self.assertTrue(self.backend.test_pattern_match("*archive*", "archive/my-branch"))
        self.assertFalse(self.backend.test_pattern_match("*archive*", "feature/my-branch"))


if __name__ == "__main__":
    unittest.main()
