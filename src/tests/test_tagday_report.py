# -*- coding: UTF-8 -*-
import os
import sys
import tempfile
import unittest

# Add py directory to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from azure import AzureDevOpsCache
import generate_tagday_report


class TestTagDayReport(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmp_dir, "test_tagday.db")
        self.md_path = os.path.join(self.tmp_dir, "TAGDAY_TEST.md")
        self.cache = AzureDevOpsCache(self.db_path)

    def tearDown(self):
        del self.cache
        import gc
        gc.collect()
        for f in (self.db_path, self.md_path):
            if os.path.exists(f):
                try:
                    os.remove(f)
                except OSError:
                    pass
        if os.path.exists(self.tmp_dir):
            try:
                os.rmdir(self.tmp_dir)
            except OSError:
                pass

    def test_parse_semver_tuple(self):
        self.assertEqual(generate_tagday_report.parse_semver_tuple("v01.02.2632"), (1, 2, 2632))
        self.assertEqual(generate_tagday_report.parse_semver_tuple("v2.1.0"), (2, 1, 0))
        self.assertEqual(generate_tagday_report.parse_semver_tuple("v1"), (1, 0, 0))
        self.assertEqual(generate_tagday_report.parse_semver_tuple(""), (0, 0, 0))
        self.assertEqual(generate_tagday_report.parse_semver_tuple(None), (0, 0, 0))

    def test_categorize_repository(self):
        custom_config = {
            "default_category": "OTHERS",
            "prefix_rules": {
                "core-": "CORE_GROUP",
                "generic-": "GENERIC",
                "3rdparty-": "3RDPARTY",
            },
            "repositories": {
                "repo-core": "CORE",
                "repo-app": "CORE APPS",
            }
        }
        self.assertEqual(generate_tagday_report.categorize_repository("repo-core", config=custom_config), "CORE")
        self.assertEqual(generate_tagday_report.categorize_repository("repo-app", config=custom_config), "CORE APPS")
        self.assertEqual(generate_tagday_report.categorize_repository("core-doc-dev", config=custom_config), "CORE_GROUP")
        self.assertEqual(generate_tagday_report.categorize_repository("generic-lib", config=custom_config), "GENERIC")
        self.assertEqual(generate_tagday_report.categorize_repository("3rdparty-lib", config=custom_config), "3RDPARTY")
        self.assertEqual(generate_tagday_report.categorize_repository("unknown-repo", config=custom_config), "OTHERS")

    def _seed_sample_repo_data(self):
        """Helper to seed sample repos, tags, branches, and PRs into test database."""
        with self.cache._connection() as conn:
            # 1. Projects
            conn.execute("INSERT OR REPLACE INTO projects (id, name) VALUES (?, ?)", ("TEST_PROJ", "Test Project"))

            # 2. Repositories
            repos = [
                ("r-doc", "TEST_PROJ", "repo-docs", "refs/heads/dev", "http://tfs/doc-dev"),
                ("r-app", "TEST_PROJ", "repo-app", "refs/heads/dev", "http://tfs/app"),
                ("r-core", "TEST_PROJ", "repo-core", "refs/heads/master", "http://tfs/core"),
            ]
            for r_id, p_id, name, def_b, url in repos:
                conn.execute("""
                    INSERT OR REPLACE INTO repositories (id, project_id, name, default_branch, web_url, is_disabled)
                    VALUES (?, ?, ?, ?, ?, 0)
                """, (r_id, p_id, name, def_b, url))

            # 3. Tags (each repo has its own latest tag)
            tags = [
                ("r-doc", "v01.01.2618", "c1", "2026-05-01 10:00:00", "Dev1", "old tag"),
                ("r-doc", "v01.01.2628", "c2", "2026-07-20 07:20:00", "Dev1", "latest doc tag"),
                ("r-app", "v01.02.2632", "c3", "2026-08-08 12:00:00", "Dev2", "latest app tag"),
            ]
            for repo_id, name, commit_id, dt, committer, comment in tags:
                conn.execute("""
                    INSERT OR REPLACE INTO tags (repo_id, name, commit_id, commit_date, committer_name, comment)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (repo_id, name, commit_id, dt, committer, comment))

            # 4. Pull Requests
            prs = [
                # In repo-app: tag is 2026-08-08
                (101, "r-app", "Fix prior to app tag", "completed", "refs/heads/dev", "refs/heads/feat1", "Dev1", "2026-08-01 12:00:00", '{"description":"old"}'),
                (102, "r-app", "New feature after app tag", "completed", "refs/heads/dev", "refs/heads/feat2", "Dev2", "2026-08-15 14:00:00", '{"description":"new feature"}'),
                (103, "r-app", "Active PR in review", "active", "refs/heads/dev", "refs/heads/feat3", "Dev3", "", '{"creationDateStr":"2026-08-16 10:00:00","description":"under review"}'),
                # In repo-docs: tag is 2026-07-20
                (104, "r-doc", "Doc update after doc tag", "completed", "refs/heads/dev", "refs/heads/docfix", "Dev1", "2026-07-25 09:00:00", '{"description":"doc changes"}'),
                (105, "r-doc", "Doc change prior to doc tag", "completed", "refs/heads/dev", "refs/heads/olddoc", "Dev1", "2026-06-15 09:00:00", '{"description":"old doc"}'),
            ]
            for pr_id, repo_id, title, status, target, source, author, closed_dt, raw_j in prs:
                conn.execute("""
                    INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_date, raw_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (pr_id, repo_id, title, status, target, source, author, closed_dt, raw_j))

            # 5. Branches
            branches = [
                ("r-app", "refs/heads/features/pending-work", "b_hash_1", "2026-08-20 11:00:00", "Dev2", "WIP work", 3, 1),
                ("r-app", "refs/heads/feat3", "b_hash_4", "2026-08-21 12:00:00", "Dev3", "Prepared PR branch", 2, 0),
                ("r-app", "refs/heads/dev", "b_hash_2", "2026-08-10 11:00:00", "Dev2", "dev branch", 0, 0),
                ("r-doc", "refs/heads/dev", "b_hash_3", "2026-07-25 11:00:00", "Dev1", "dev branch", 0, 0),
            ]
            for repo_id, name, commit_id, dt, committer, comment, ahead, behind in branches:
                conn.execute("""
                    INSERT OR REPLACE INTO branches (repo_id, name, commit_id, commit_date, committer_name, comment, ahead_count, behind_count)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (repo_id, name, commit_id, dt, committer, comment, ahead, behind))

    def test_load_tagday_data_per_repository_baseline(self):
        self._seed_sample_repo_data()
        data = generate_tagday_report.load_tagday_data(self.cache, project_id="TEST_PROJ")

        # Repos with PRs
        self.assertIn("repo-app", data["repos_with_prs"])
        self.assertIn("repo-docs", data["repos_with_prs"])
        self.assertNotIn("repo-core", data["repos_with_prs"])

        # Check that PR 101 (before repo-app's tag 2026-08-08) was excluded from prs_after_tag
        app_prs = data["repos_with_prs"]["repo-app"]["prs_after_tag"]
        app_pr_ids = [p["pr_id"] for p in app_prs]
        self.assertIn(102, app_pr_ids)
        self.assertNotIn(101, app_pr_ids)

        # Check that PR 105 (before doc's tag 2026-07-20) was excluded
        doc_prs = data["repos_with_prs"]["repo-docs"]["prs_after_tag"]
        doc_pr_ids = [p["pr_id"] for p in doc_prs]
        self.assertIn(104, doc_pr_ids)
        self.assertNotIn(105, doc_pr_ids)

        # Active PR in repo-app
        app_active = data["repos_with_prs"]["repo-app"]["active_prs"]
        self.assertEqual(len(app_active), 1)
        self.assertEqual(app_active[0]["pr_id"], 103)

        # Check all_prs list and tagging information per repository
        app_all = data["all_repositories"]["repo-app"]["all_prs"]
        self.assertEqual(len(app_all), 3)
        app_all_by_id = {p["pr_id"]: p for p in app_all}
        # PR 101: merged before tag v01.02.2632 -> tagged
        self.assertTrue(app_all_by_id[101]["is_tagged"])
        self.assertEqual(app_all_by_id[101]["tag_name"], "v01.02.2632")
        # PR 102: merged after tag v01.02.2632 -> untagged candidate
        self.assertFalse(app_all_by_id[102]["is_tagged"])
        self.assertEqual(app_all_by_id[102]["tag_type"], "untagged")
        # PR 103: active PR -> untagged active
        self.assertFalse(app_all_by_id[103]["is_tagged"])
        self.assertEqual(app_all_by_id[103]["tag_type"], "active")

        # In repo-docs: PR 105 merged before doc tag v01.01.2628, PR 104 after
        doc_all = data["all_repositories"]["repo-docs"]["all_prs"]
        self.assertEqual(len(doc_all), 2)
        doc_all_by_id = {p["pr_id"]: p for p in doc_all}
        self.assertTrue(doc_all_by_id[105]["is_tagged"])
        self.assertEqual(doc_all_by_id[105]["tag_name"], "v01.01.2628")
        self.assertFalse(doc_all_by_id[104]["is_tagged"])

        # Repos with unmerged branches
        self.assertIn("repo-app", data["repos_with_unmerged_branches"])
        app_branches = data["repos_with_unmerged_branches"]["repo-app"]["unmerged_branches"]
        self.assertEqual(len(app_branches), 2)
        
        # Check prepared PR linking on branches
        feat3_branch = next(b for b in app_branches if b["branch_name"] == "feat3")
        self.assertIsNotNone(feat3_branch["prepared_pr"])
        self.assertEqual(feat3_branch["prepared_pr"]["pr_id"], 103)

        pending_branch = next(b for b in app_branches if b["branch_name"] == "features/pending-work")
        self.assertIsNone(pending_branch["prepared_pr"])

        # Chronological timeline
        self.assertGreaterEqual(len(data["all_changes_timeline"]), 3)
        dates = [item["date"] for item in data["all_changes_timeline"] if item.get("date")]
        self.assertEqual(dates, sorted(dates, reverse=True))

    def test_generate_tagday_markdown(self):
        self._seed_sample_repo_data()
        data = generate_tagday_report.load_tagday_data(self.cache, project_id="TEST_PROJ")

        md_content = generate_tagday_report.generate_tagday_markdown(data, output_path=self.md_path)

        # Verify output file created
        self.assertTrue(os.path.exists(self.md_path))
        with open(self.md_path, "r", encoding="utf-8") as f:
            saved_content = f.read()
        self.assertEqual(md_content, saved_content)

        # Verify views exist
        self.assertIn("# Tag Day Release Overview", md_content)
        self.assertIn("Release readiness evaluation per repository", md_content)
        self.assertIn("## 1. Repositories with Unmerged Branch Updates", md_content)
        self.assertIn("## 2. Repositories with Pull Requests after Latest Tag", md_content)
        self.assertIn("## 3. Consolidated Global Changes Timeline", md_content)
        self.assertIn("## 4. Individual Repository Walkthrough", md_content)

        # Verify Prepared PR column is present in tables
        self.assertIn("| Prepared PR |", md_content)

        # Verify repo links and anchors
        self.assertIn("[repo-app](#repo-repo-app)", md_content)
        self.assertIn('<a id="repo-repo-app"></a>', md_content)
        self.assertIn("#### repo-app", md_content)
        # Verify no octicons in headings
        self.assertNotIn("#### :octicons", md_content)
        self.assertIn("features/pending-work", md_content)
        self.assertIn("feat3", md_content)
        self.assertIn("!102", md_content)
        self.assertIn("!103", md_content)

    def test_run_tagday_report_end_to_end(self):
        self._seed_sample_repo_data()
        success = generate_tagday_report.run_tagday_report(
            db_path=self.db_path,
            output_path=self.md_path,
            project_id="TEST_PROJ"
        )
        self.assertTrue(success)
        self.assertTrue(os.path.exists(self.md_path))
        with open(self.md_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("Tag Day Release Overview", content)


if __name__ == "__main__":
    unittest.main()
