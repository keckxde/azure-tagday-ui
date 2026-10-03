# -*- coding: UTF-8 -*-
"""
Tests for Universal Global Search in Azure DevOps GUI backend:
- Work item ID searches (#123, 123, WI-123)
- Commit code / SHA searches (a1b2c3d, messages, author)
- Pull Request number searches (PR 42, !42, titles)
- Open Item code searches (OI-171, [OI_171], OIL_45)
- Merkpunkt code searches (MP_01, MP-2)
- Scenario searches (SCENARIO-12, [SCENARIO_12], Scenario Milestones)
- Repository name searches (repo names, URLs)
- Category filters (ALL, WORK_ITEMS, COMMITS, PULL_REQUESTS, OPEN_ITEMS, MERKPUNKTE, SCENARIOS, REPOSITORIES)
"""
import os
import sys
import unittest
import tempfile
import shutil
import json
from datetime import datetime

# Ensure src/ is on sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from azure.azure_db import AzureDevOpsCache
from gui.backend import DevOpsBackend


class TestGlobalSearch(unittest.TestCase):

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_search.db")
        self.cache_db = AzureDevOpsCache(self.db_path)
        self.backend = DevOpsBackend()
        self.backend.set_cache_db(self.cache_db)

        # Seed Database
        with self.cache_db._connection() as conn:
            # 1. Repositories
            conn.execute(
                "INSERT INTO repositories (id, project_id, name, default_branch, web_url) VALUES (?, ?, ?, ?, ?)",
                ("r1", "Project", "azure-tagday-ui", "main", "https://tfs.server/tfs/DefaultCollection/Project/_git/azure-tagday-ui")
            )
            conn.execute(
                "INSERT INTO repositories (id, project_id, name, default_branch, web_url) VALUES (?, ?, ?, ?, ?)",
                ("r2", "Project", "core-backend-api", "master", "https://tfs.server/tfs/DefaultCollection/Project/_git/core-backend-api")
            )

            # 2. Work Items
            conn.execute(
                """INSERT INTO work_items (id, title, type, state, assigned_to, raw_json)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (101, "[OI_171] Fix authentication timeout in login screen", "User Story", "Active", "Alice Smith",
                 json.dumps({"fields": {"System.IterationPath": "Project\\week-2640", "System.Tags": "Target:Scenario_Alpha; OI"}}))
            )
            conn.execute(
                """INSERT INTO work_items (id, title, type, state, assigned_to, raw_json)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (102, "[MP_03] Refactor database connection pool [OIL_45]", "Task", "Active", "Bob Jones",
                 json.dumps({"fields": {"System.IterationPath": "Project\\week-2640", "System.Tags": "MP; Subsystem:Database"}}))
            )
            conn.execute(
                """INSERT INTO work_items (id, title, type, state, assigned_to, raw_json)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (103, "SCENARIO-12 Automated end-to-end telemetry verification", "Bug", "Closed", "Charlie Brown",
                 json.dumps({"fields": {"System.IterationPath": "Project\\week-2639", "System.Tags": "Target:Scenario_Beta; bug"}}))
            )

            # 3. Pull Requests
            conn.execute(
                """INSERT INTO pull_requests (id, repo_id, title, status, source_branch, target_branch, created_by, raw_json)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (42, "azure-tagday-ui", "[OI_171] Add search dialog and shortcuts", "completed", "feature/search", "main", "Alice Smith", json.dumps({}))
            )
            conn.execute(
                """INSERT INTO pull_requests (id, repo_id, title, status, source_branch, target_branch, created_by, raw_json)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (88, "core-backend-api", "[MP_01] Upgrade connection retry logic", "active", "feature/mp1-retry", "master", "Bob Jones", json.dumps({}))
            )

            # 4. Commits
            conn.execute(
                """INSERT INTO commits (commit_id, repo_id, comment, author_name, author_date)
                   VALUES (?, ?, ?, ?, ?)""",
                ("a1b2c3d4e5f6789012345678901234567890abcd", "azure-tagday-ui", "[OI_171] Implement fast global search modal dialog", "Alice Smith", "2026-10-03T12:00:00Z")
            )
            conn.execute(
                """INSERT INTO commits (commit_id, repo_id, comment, author_name, author_date)
                   VALUES (?, ?, ?, ?, ?)""",
                ("f9e8d7c6b5a4321098765432109876543210fedc", "core-backend-api", "[SCENARIO_12] Fix flaky telemetry assert", "Charlie Brown", "2026-10-03T13:00:00Z")
            )

        # 5. Milestones
        self.cache_db.save_milestone(
            name="Scenario Alpha Demo",
            target_date="2026-10-15",
            category_id="scenario",
            team="All Teams",
            description="End-to-end integration demo"
        )

        self.backend.refresh_all_data()

    def tearDown(self):
        if hasattr(self, "cache_db") and self.cache_db and hasattr(self.cache_db, "close"):
            self.cache_db.close()
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_search_work_item_by_id(self):
        # Numeric ID search
        res = self.backend.global_search("101")
        self.assertGreaterEqual(res["total_count"], 1)
        wi_match = next((item for item in res["results"] if item["id"] == "101"), None)
        self.assertIsNotNone(wi_match)
        self.assertEqual(wi_match["category"], "work_items")
        self.assertIn("Fix authentication timeout", wi_match["title"])

        # Hash prefix search #102
        res2 = self.backend.global_search("#102")
        self.assertGreaterEqual(res2["total_count"], 1)
        wi_match2 = next((item for item in res2["results"] if item["id"] == "102"), None)
        self.assertIsNotNone(wi_match2)
        self.assertIn("Refactor database", wi_match2["title"])

    def test_search_commit_code_hash(self):
        # Short hash search
        res = self.backend.global_search("a1b2c3d")
        self.assertGreaterEqual(res["total_count"], 1)
        commit_match = next((item for item in res["results"] if item["category"] == "commits"), None)
        self.assertIsNotNone(commit_match)
        self.assertEqual(commit_match["id"], "a1b2c3d4")
        self.assertIn("Implement fast global search", commit_match["title"])

    def test_search_pull_request_number(self):
        # PR number search: "PR 42" or "42"
        res = self.backend.global_search("PR 42")
        self.assertGreaterEqual(res["total_count"], 1)
        pr_match = next((item for item in res["results"] if item["category"] == "pull_requests" and item["id"] == "42"), None)
        self.assertIsNotNone(pr_match)
        self.assertIn("Add search dialog", pr_match["title"])

    def test_search_open_item_code(self):
        # Search by OI code
        res = self.backend.global_search("OI-171")
        self.assertGreaterEqual(res["total_count"], 1)
        self.assertGreaterEqual(res["counts_by_category"]["open_items"], 1)
        oi_match = next((item for item in res["results"] if item["category"] == "open_items"), None)
        self.assertIsNotNone(oi_match)

        # Search by OIL code
        res_oil = self.backend.global_search("[OIL_45]")
        self.assertGreaterEqual(res_oil["total_count"], 1)

    def test_search_merkpunkt_code(self):
        # Search by MP code
        res = self.backend.global_search("MP_03")
        self.assertGreaterEqual(res["total_count"], 1)
        self.assertGreaterEqual(res["counts_by_category"]["merkpunkte"], 1)
        mp_match = next((item for item in res["results"] if item["category"] == "merkpunkte"), None)
        self.assertIsNotNone(mp_match)

    def test_search_scenario(self):
        # Search by Scenario tag / title
        res = self.backend.global_search("SCENARIO-12")
        self.assertGreaterEqual(res["total_count"], 1)
        self.assertGreaterEqual(res["counts_by_category"]["scenarios"], 1)

        # Search by Scenario Milestone name
        res2 = self.backend.global_search("Scenario Alpha")
        self.assertGreaterEqual(res2["total_count"], 1)
        scen_match = next((item for item in res2["results"] if item["category"] == "scenarios"), None)
        self.assertIsNotNone(scen_match)
        self.assertEqual(scen_match["title"], "Scenario Alpha Demo")

    def test_search_repository_name(self):
        res = self.backend.global_search("azure-tagday-ui")
        self.assertGreaterEqual(res["total_count"], 1)
        repo_match = next((item for item in res["results"] if item["category"] == "repositories" and item["id"] == "azure-tagday-ui"), None)
        self.assertIsNotNone(repo_match)
        self.assertEqual(repo_match["category_label"], "Repository")

    def test_search_category_filter(self):
        # Filter strictly for WORK_ITEMS
        res_wi = self.backend.global_search("101", category_filter="WORK_ITEMS")
        for it in res_wi["results"]:
            self.assertEqual(it["category"], "work_items")

        # Filter strictly for COMMITS
        res_c = self.backend.global_search("OI", category_filter="COMMITS")
        for it in res_c["results"]:
            self.assertEqual(it["category"], "commits")


if __name__ == "__main__":
    unittest.main()
