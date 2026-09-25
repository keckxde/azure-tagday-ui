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

    def test_export_and_import_yaml(self):
        # Configure some categories, prefix rules, overrides
        self.cache.save_repo_category("INFRA", "#da3633", bg_color="#3d1418", sort_order=5, is_default=False)
        self.cache.save_repo_prefix_rule("infra-", "INFRA")
        self.cache.save_repo_category_override("infra-core-service", "CORE")

        cfg = self.cache.get_full_repo_category_config()
        export_file = os.path.join(self.test_dir, "export_cats.yaml")

        ok = utils.export_repo_categories_to_file(cfg, export_file)
        self.assertTrue(ok)
        self.assertTrue(os.path.exists(export_file))

        # Import back
        imported_cfg = utils.import_repo_categories_from_file(export_file)
        self.assertIsNotNone(imported_cfg)
        self.assertEqual(imported_cfg["default_category"], cfg["default_category"])
        self.assertIn("INFRA", imported_cfg["category_colors"])
        self.assertEqual(imported_cfg["category_colors"]["INFRA"], "#da3633")
        self.assertEqual(imported_cfg["prefix_rules"].get("infra-"), "INFRA")
        self.assertEqual(imported_cfg["repositories"].get("infra-core-service"), "CORE")

    def test_export_and_import_json(self):
        self.cache.save_repo_category("TOOLS", "#58a6ff", bg_color="#0d2844", sort_order=6, is_default=False)
        self.cache.save_repo_prefix_rule("tool-", "TOOLS")
        self.cache.save_repo_category_override("tool-deploy", "TOOLS")

        cfg = self.cache.get_full_repo_category_config()
        export_file = os.path.join(self.test_dir, "export_cats.json")

        ok = utils.export_repo_categories_to_file(cfg, export_file)
        self.assertTrue(ok)
        self.assertTrue(os.path.exists(export_file))

        imported_cfg = utils.import_repo_categories_from_file(export_file)
        self.assertIsNotNone(imported_cfg)
        self.assertIn("TOOLS", imported_cfg["category_colors"])
        self.assertEqual(imported_cfg["category_colors"]["TOOLS"], "#58a6ff")
        self.assertEqual(imported_cfg["prefix_rules"].get("tool-"), "TOOLS")
        self.assertEqual(imported_cfg["repositories"].get("tool-deploy"), "TOOLS")

    def test_export_and_import_excel(self):
        try:
            import openpyxl
        except ImportError:
            self.skipTest("openpyxl is not installed in the test environment")

        self.cache.save_repo_category("PLATFORM", "#3fb950", bg_color="#163c20", sort_order=3, is_default=False)
        self.cache.save_repo_prefix_rule("plat-", "PLATFORM")
        self.cache.save_repo_category_override("plat-gateway", "PLATFORM")

        cfg = self.cache.get_full_repo_category_config()
        export_file = os.path.join(self.test_dir, "export_cats.xlsx")

        ok = utils.export_repo_categories_to_file(cfg, export_file)
        self.assertTrue(ok)
        self.assertTrue(os.path.exists(export_file))

        imported_cfg = utils.import_repo_categories_from_file(export_file)
        self.assertIsNotNone(imported_cfg)
        self.assertIn("PLATFORM", imported_cfg["category_colors"])
        self.assertEqual(imported_cfg["category_colors"]["PLATFORM"], "#3fb950")
        self.assertEqual(imported_cfg["prefix_rules"].get("plat-"), "PLATFORM")
        self.assertEqual(imported_cfg["repositories"].get("plat-gateway"), "PLATFORM")

    def test_save_full_repo_category_config_merge(self):
        # Initial state
        self.cache.save_repo_category("CAT_A", "#111111", sort_order=1)
        self.cache.save_repo_prefix_rule("pfx-a-", "CAT_A")
        self.cache.save_repo_category_override("repo-a", "CAT_A")

        # Merge new config without overwriting CAT_A
        new_config = {
            "default_category": "OTHERS",
            "category_colors": {"CAT_B": "#222222"},
            "category_bg_colors": {},
            "category_sort_orders": {"CAT_B": 2},
            "prefix_rules": {"pfx-b-": "CAT_B"},
            "repositories": {"repo-b": "CAT_B"},
        }
        self.cache.save_full_repo_category_config(new_config, merge=True)

        cats = {c["name"]: c["color"] for c in self.cache.get_repo_categories()}
        self.assertIn("CAT_A", cats)
        self.assertIn("CAT_B", cats)

        rules = {r["prefix"]: r["category"] for r in self.cache.get_repo_prefix_rules()}
        self.assertIn("pfx-a-", rules)
        self.assertIn("pfx-b-", rules)

        overrides = self.cache.get_repo_category_overrides()
        self.assertIn("repo-a", overrides)
        self.assertIn("repo-b", overrides)


if __name__ == "__main__":
    unittest.main()
