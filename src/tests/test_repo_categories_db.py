import os
import shutil
import tempfile
import unittest
from azure.azure_db import AzureDevOpsCache
import utils
import devops_helper


class TestRepoCategoriesDatabase(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_repo_cats.db")
        self.cache = AzureDevOpsCache(self.db_path)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_default_categories_seeded(self):
        cats = self.cache.get_repo_categories()
        cat_names = [c["name"] for c in cats]
        self.assertIn("CORE", cat_names)
        self.assertIn("GENERIC", cat_names)
        self.assertIn("3RDPARTY", cat_names)
        self.assertIn("OTHERS", cat_names)

        # OTHERS should be default
        others = [c for c in cats if c["name"] == "OTHERS"][0]
        self.assertTrue(others["is_default"])

    def test_default_prefix_rules_seeded(self):
        rules = self.cache.get_repo_prefix_rules()
        rule_map = {r["prefix"]: r["category"] for r in rules}
        self.assertEqual(rule_map.get("generic-"), "GENERIC")
        self.assertEqual(rule_map.get("3rdparty-"), "3RDPARTY")

    def test_category_crud(self):
        # Create new category
        res = self.cache.save_repo_category("INFRA", "#da3633", bg_color="#3d1418", sort_order=10, is_default=False)
        self.assertTrue(res)

        cats = self.cache.get_repo_categories()
        cat_names = [c["name"] for c in cats]
        self.assertIn("INFRA", cat_names)
        infra_cat = [c for c in cats if c["name"] == "INFRA"][0]
        self.assertEqual(infra_cat["color"], "#da3633")

        # Update category
        self.cache.save_repo_category("INFRA", "#ff7b72", bg_color="#3d1418", sort_order=10, is_default=False)
        cats2 = self.cache.get_repo_categories()
        infra_cat2 = [c for c in cats2 if c["name"] == "INFRA"][0]
        self.assertEqual(infra_cat2["color"], "#ff7b72")

        # Delete category
        del_res = self.cache.delete_repo_category("INFRA")
        self.assertTrue(del_res)
        cats3 = self.cache.get_repo_categories()
        self.assertNotIn("INFRA", [c["name"] for c in cats3])

    def test_prefix_rule_crud(self):
        # Create prefix rule
        res = self.cache.save_repo_prefix_rule("tool-", "GENERIC")
        self.assertTrue(res)

        rules = self.cache.get_repo_prefix_rules()
        rule_map = {r["prefix"]: r["category"] for r in rules}
        self.assertEqual(rule_map.get("tool-"), "GENERIC")

        # Delete prefix rule
        del_res = self.cache.delete_repo_prefix_rule("tool-")
        self.assertTrue(del_res)
        rules2 = self.cache.get_repo_prefix_rules()
        self.assertNotIn("tool-", [r["prefix"] for r in rules2])

    def test_category_override_crud(self):
        # Explicit repo assignment
        res = self.cache.save_repo_category_override("my-special-repo", "CORE")
        self.assertTrue(res)

        overrides = self.cache.get_repo_category_overrides()
        self.assertEqual(overrides.get("my-special-repo"), "CORE")

        # Delete override
        del_res = self.cache.delete_repo_category_override("my-special-repo")
        self.assertTrue(del_res)
        overrides2 = self.cache.get_repo_category_overrides()
        self.assertNotIn("my-special-repo", overrides2)

    def test_utils_categorize_repository_with_cache_db(self):
        self.cache.save_repo_prefix_rule("service-", "CORE")
        self.cache.save_repo_category_override("custom-service-one", "3RDPARTY")

        # Explicit override matches
        self.assertEqual(utils.categorize_repository("custom-service-one", cache_db=self.cache), "3RDPARTY")

        # Prefix rule matches
        self.assertEqual(utils.categorize_repository("service-auth", cache_db=self.cache), "CORE")

        # Default fallback
        self.assertEqual(utils.categorize_repository("random-repo", cache_db=self.cache), "OTHERS")

    def test_devops_helper_add_categories_with_cache_db(self):
        repos = {
            "r1": {"name": "generic-logging"},
            "r2": {"name": "service-auth"},
            "r3": {"name": "unknown-repo"},
        }
        self.cache.save_repo_prefix_rule("service-", "CORE")

        devops_helper.addCategoriesToRepos(repos, cache_db=self.cache, auto_save_missing=True)

        self.assertEqual(repos["r1"]["category"], "GENERIC")
        self.assertEqual(repos["r2"]["category"], "CORE")
        self.assertEqual(repos["r3"]["category"], "OTHERS")

        # Check that missing repo was saved to DB overrides
        overrides = self.cache.get_repo_category_overrides()
        self.assertEqual(overrides.get("unknown-repo"), "OTHERS")


if __name__ == "__main__":
    unittest.main()
