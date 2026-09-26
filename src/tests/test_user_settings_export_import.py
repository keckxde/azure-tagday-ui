# -*- coding: UTF-8 -*-
import os
import sys
import json
import yaml
import tempfile
import unittest
from unittest.mock import patch, MagicMock
from PySide6.QtCore import QCoreApplication

# Add src to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import shutil
from azure.azure_db import AzureDevOpsCache
from utils import export_user_settings_to_file, import_user_settings_from_file
from gui.backend import DevOpsBackend, USER_SETTINGS_PATH


class TestUserSettingsExportImport(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not QCoreApplication.instance():
            cls.app = QCoreApplication([])
        else:
            cls.app = QCoreApplication.instance()

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_settings.db")
        self.db = AzureDevOpsCache(self.db_path)

        # Seed sample data for all 5 sections
        # 1. Repo Categories
        self.db.save_repo_category("Core", color="#da3633", bg_color="#3d1418", sort_order=1)
        self.db.save_repo_category("Plugins", color="#238636", bg_color="#0e2a18", sort_order=2)
        self.db.save_repo_prefix_rule("core-", "Core")
        self.db.save_repo_category_override("special-plugin", "Plugins")
        self.db.save_repo_category("Uncategorized", color="#888888", sort_order=99, is_default=True)

        # 2. Git Branch Filters
        self.db.set_config("branch_filter_patterns", ["features/*", "releases/*"])
        self.db.set_config("repo_category_filter_patterns", ["Core", "Plugins"])

        # 3. Milestones
        self.db.save_milestone_category(name="Q1 Release", cat_id="q1", color="#388bfd", bg_color="#101e38", icon="🚀", sort_order=10)
        self.db.save_milestone(name="v1.0.0", target_date="2026-03-31", category_id="q1", description="First major release", team="Team Alpha", end_date="2026-04-05")

        # 4. Work Item Categories
        self.db.set_config("work_item_tag_categories", {
            "Bug": ["bug", "defect"],
            "Feature": ["user-story", "enhancement"]
        })
        self.db.set_config("custom_deadline_field", "Custom.ReleaseDeadline")
        self.db.set_config("REPORTS_DIR", "C:/Reports/Custom")

        # 5. Team Assignment and Sprint URL
        self.db.set_config("tfs_team_name", "AlphaTeam")
        self.db.set_config("sprint_url_template", "https://dev.azure.com/org/proj/_sprints/taskboard/{team}/{iteration}")
        self.db.set_config("default_tfs_team", "AlphaTeam")

    def tearDown(self):
        if hasattr(self, "db"):
            del self.db
        import gc
        gc.collect()
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_export_all_user_settings_from_db(self):
        exported = self.db.export_user_settings()
        self.assertIn("version", exported)
        self.assertIn("settings", exported)
        settings = exported["settings"]

        # Check section 1: Repo categories
        self.assertIn("repo_categories", settings)
        self.assertEqual(settings["repo_categories"]["default_category"], "Uncategorized")
        cat_names = [c["name"] for c in settings["repo_categories"]["categories"]]
        self.assertIn("Core", cat_names)
        self.assertIn("Plugins", cat_names)
        self.assertIn({"prefix": "core-", "category": "Core"}, settings["repo_categories"]["prefix_rules"])
        self.assertIn({"repo_name": "special-plugin", "category": "Plugins"}, settings["repo_categories"]["repo_overrides"])

        # Check section 2: Git branch filters
        self.assertIn("git_branch_filters", settings)
        self.assertEqual(settings["git_branch_filters"]["branch_filter_patterns"], ["features/*", "releases/*"])
        self.assertEqual(settings["git_branch_filters"]["repo_category_filter_patterns"], ["Core", "Plugins"])

        # Check section 3: Milestones
        self.assertIn("milestones", settings)
        self.assertTrue(any(c["name"] == "Q1 Release" for c in settings["milestones"]["categories"]))
        self.assertTrue(any(m["name"] == "v1.0.0" and m.get("team") == "Team Alpha" for m in settings["milestones"]["milestones"]))

        # Check section 4: Work Item Categories & Deadlines
        self.assertIn("work_item_categories", settings)
        self.assertIn("Bug", settings["work_item_categories"]["work_item_tag_categories"])
        self.assertEqual(settings["work_item_categories"]["custom_deadline_field"], "Custom.ReleaseDeadline")
        self.assertEqual(settings["work_item_categories"]["reports_dir"], "C:/Reports/Custom")

        # Check section 5: Team & Sprint URL
        self.assertIn("team_and_sprint_url", settings)
        self.assertEqual(settings["team_and_sprint_url"]["tfs_team_name"], "AlphaTeam")
        self.assertIn("{team}", settings["team_and_sprint_url"]["sprint_url_template"])

    def test_export_selective_sections(self):
        exported = self.db.export_user_settings(include_sections=["milestones", "team_and_sprint_url"])
        settings = exported["settings"]
        self.assertIn("milestones", settings)
        self.assertIn("team_and_sprint_url", settings)
        self.assertNotIn("repo_categories", settings)
        self.assertNotIn("git_branch_filters", settings)
        self.assertNotIn("work_item_categories", settings)

    def test_file_export_and_import_yaml_and_json(self):
        exported = self.db.export_user_settings()

        # Test YAML
        yaml_path = os.path.join(self.test_dir, "user_settings.yaml")
        self.assertTrue(export_user_settings_to_file(exported, yaml_path))
        imported_yaml = import_user_settings_from_file(yaml_path)
        self.assertIsNotNone(imported_yaml)
        self.assertIn("settings", imported_yaml)
        self.assertEqual(imported_yaml["settings"]["team_and_sprint_url"]["tfs_team_name"], "AlphaTeam")

        # Test JSON
        json_path = os.path.join(self.test_dir, "user_settings.json")
        self.assertTrue(export_user_settings_to_file(exported, json_path))
        imported_json = import_user_settings_from_file(json_path)
        self.assertIsNotNone(imported_json)
        self.assertIn("settings", imported_json)
        self.assertEqual(imported_json["settings"]["git_branch_filters"]["branch_filter_patterns"], ["features/*", "releases/*"])

    def test_import_into_fresh_db_with_clear(self):
        exported = self.db.export_user_settings()

        new_db_path = os.path.join(self.test_dir, "fresh_target.db")
        new_db = AzureDevOpsCache(new_db_path)
        try:
            success, msg = new_db.import_user_settings(exported, clear_existing=True)
            self.assertTrue(success)

            # Verify contents in fresh DB
            cats = new_db.get_repo_categories()
            cat_names = [c["name"] for c in cats]
            self.assertIn("Core", cat_names)
            self.assertIn("Plugins", cat_names)
            rules = new_db.get_repo_prefix_rules()
            self.assertIn({"prefix": "core-", "category": "Core"}, rules)
            branch_patterns = new_db.get_config("branch_filter_patterns", [])
            self.assertEqual(branch_patterns, ["features/*", "releases/*"])
            ms = new_db.get_milestones()
            self.assertTrue(any(m["name"] == "v1.0.0" for m in ms))
            self.assertEqual(new_db.get_config("custom_deadline_field"), "Custom.ReleaseDeadline")
            self.assertEqual(new_db.get_config("tfs_team_name"), "AlphaTeam")
        finally:
            del new_db
            import gc
            gc.collect()

    def test_import_selective_and_merge(self):
        # Create target DB with existing data
        target_db_path = os.path.join(self.test_dir, "target_merge.db")
        target_db = AzureDevOpsCache(target_db_path)
        try:
            target_db.save_repo_category("ExistingCat", color="#555555", sort_order=0)
            target_db.save_milestone(name="v0.1.0", target_date="2026-01-01", category_id="general", description="Old milestone", team="Team Beta")
            target_db.set_config("tfs_team_name", "BetaTeam")

            # Export from source, import only milestones and repo_categories into target (merging)
            source_data = self.db.export_user_settings()
            success, msg = target_db.import_user_settings(
                source_data,
                clear_existing=False,
                include_sections=["repo_categories", "milestones"]
            )
            self.assertTrue(success)

            # Check that repo categories merged
            cats = {c["name"] for c in target_db.get_repo_categories()}
            self.assertIn("ExistingCat", cats)
            self.assertIn("Core", cats)
            self.assertIn("Plugins", cats)

            # Check that milestones merged
            ms_names = {m["name"] for m in target_db.get_milestones()}
            self.assertIn("v0.1.0", ms_names)
            self.assertIn("v1.0.0", ms_names)

            # Team name should NOT have changed since team_and_sprint_url was not in include_sections
            self.assertEqual(target_db.get_config("tfs_team_name"), "BetaTeam")
        finally:
            del target_db
            import gc
            gc.collect()

    def test_backend_export_and_import_flow(self):
        backend = DevOpsBackend()
        try:
            backend.db = self.db
            backend._db_name = self.db_path

            export_file = os.path.join(self.test_dir, "backend_exported.yaml")
            res = backend.export_all_user_settings(export_file, ["repo_categories", "git_branch_filters", "milestones", "work_item_categories", "team_and_sprint_url"])
            self.assertTrue(res.get("success"))
            self.assertTrue(os.path.exists(export_file))

            # Test importing into backend
            res_import = backend.import_all_user_settings(export_file, clear_existing=False, selected_sections=["repo_categories", "milestones"])
            self.assertTrue(res_import.get("success"))
        finally:
            if hasattr(backend, "_auto_sync_timer") and backend._auto_sync_timer:
                backend._auto_sync_timer.stop()
            if getattr(backend, "_worker", None) and backend._worker.isRunning():
                backend._worker.wait(500)
