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

    def test_load_tagday_data_missing_tag_date_and_title_mapping(self):
        """
        Verifies that tags with empty commit_date (e.g. from lightweight tags)
        have their dates resolved from sprint week in tag name and properly map to PRs.
        """
        with self.cache._connection() as conn:
            conn.execute("INSERT OR REPLACE INTO projects (id, name) VALUES (?, ?)", ("TEST_PROJ", "Test Project"))
            conn.execute("""
                INSERT OR REPLACE INTO repositories (id, project_id, name, default_branch, web_url, is_disabled)
                VALUES (?, ?, ?, ?, ?, 0)
            """, ("r-empty-date", "TEST_PROJ", "repo-empty-date", "refs/heads/dev", "http://tfs/repo"))

            # Tag with empty commit_date but name indicating week 2615 (April 2026)
            conn.execute("""
                INSERT OR REPLACE INTO tags (repo_id, name, commit_id, commit_date, committer_name, comment, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, ("r-empty-date", "v00.30.2615", "abc1234", "", "", "", "{}"))

            # PR completed during week 2615
            conn.execute("""
                INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_date, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (501, "r-empty-date", "Feature before release 2615", "completed", "refs/heads/dev", "refs/heads/f1", "Dev1", "2026-04-10 12:00:00", "{}"))

            # Release PR titled 'v0.30.2615'
            conn.execute("""
                INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_date, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (502, "r-empty-date", "v0.30.2615", "completed", "refs/heads/master", "refs/heads/dev", "Dev1", "2026-04-12 18:00:00", "{}"))

        data = generate_tagday_report.load_tagday_data(self.cache, project_id="TEST_PROJ")
        repo_data = data["all_repositories"]["repo-empty-date"]

        # Tag date should be resolved from sprint week
        self.assertIsNotNone(repo_data["latest_tag"])
        self.assertEqual(repo_data["latest_tag"]["name"], "v00.30.2615")
        self.assertTrue(repo_data["latest_tag"]["commit_date"].startswith("2026-04-12"))

        # Both PRs should be mapped to the tag v00.30.2615
        prs = repo_data["all_prs"]
        self.assertEqual(len(prs), 2)
        for p in prs:
            self.assertTrue(p["is_tagged"], f"PR #{p['pr_id']} should be tagged")
            self.assertEqual(p["tag_name"], "v00.30.2615")

        # Repository should have NO prs_after_tag
        self.assertEqual(len(repo_data["prs_after_tag"]), 0)

    def test_check_branch_important_and_repo_category_important(self):
        # Branch patterns
        self.assertFalse(generate_tagday_report.check_branch_important("archive/old-stuff"))
        self.assertFalse(generate_tagday_report.check_branch_important("demo/feature"))
        self.assertFalse(generate_tagday_report.check_branch_important("test/experimental"))
        self.assertFalse(generate_tagday_report.check_branch_important("my-deprecated-fix"))
        self.assertTrue(generate_tagday_report.check_branch_important("feature/login"))
        self.assertTrue(generate_tagday_report.check_branch_important("bugfix/1234"))

        # Category patterns (testing category and repo_name)
        self.assertFalse(generate_tagday_report.check_repo_category_important("DEPRECATED"))
        self.assertFalse(generate_tagday_report.check_repo_category_important("Deprecated Components"))
        self.assertTrue(generate_tagday_report.check_repo_category_important("CORE"))
        self.assertTrue(generate_tagday_report.check_repo_category_important("GENERIC"))
        self.assertTrue(generate_tagday_report.check_repo_category_important("OTHERS"))

        # Category patterns evaluated against repo_name
        self.assertFalse(generate_tagday_report.check_repo_category_important("OTHERS", repo_name="repo-deprecated-app"))
        self.assertFalse(generate_tagday_report.check_repo_category_important("CORE", repo_name="legacy-deprecated-service"))
        self.assertTrue(generate_tagday_report.check_repo_category_important("CORE", repo_name="repo-core-engine"))

        # Custom patterns
        self.assertFalse(generate_tagday_report.check_repo_category_important("SANDBOX", ignore_patterns=["*sandbox*"]))
        self.assertFalse(generate_tagday_report.check_repo_category_important("OTHERS", ignore_patterns=["*sandbox*"], repo_name="my-sandbox-repo"))
        self.assertTrue(generate_tagday_report.check_repo_category_important("CORE", ignore_patterns=["*sandbox*"], repo_name="core-service"))

    def test_load_tagday_data_with_category_and_branch_filters(self):
        self._seed_sample_repo_data()

        # Seed an additional repository with category DEPRECATED that has unmerged branches and PRs
        # and another repository with category OTHERS whose name matches *deprecated*
        with self.cache._connection() as conn:
            conn.execute("""
                INSERT OR REPLACE INTO repositories (id, project_id, name, default_branch, web_url, is_disabled)
                VALUES ('r-dep', 'TEST_PROJ', 'repo-deprecated-app', 'refs/heads/dev', 'http://tfs/dep', 0)
            """)
            conn.execute("""
                INSERT OR REPLACE INTO repo_category_overrides (repo_name, category)
                VALUES ('repo-deprecated-app', 'DEPRECATED')
            """)
            conn.execute("""
                INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_date, raw_json)
                VALUES (999, 'r-dep', 'Deprecated PR', 'active', 'refs/heads/dev', 'refs/heads/dep-feat', 'Dev1', '', '{}')
            """)
            conn.execute("""
                INSERT OR REPLACE INTO branches (repo_id, name, commit_id, commit_date, committer_name, comment, ahead_count, behind_count)
                VALUES ('r-dep', 'refs/heads/dep-feat', 'dep123', '2026-09-01 10:00:00', 'Dev1', 'Dep branch', 5, 0)
            """)

            # Repo whose category is OTHERS but name matches *deprecated*
            conn.execute("""
                INSERT OR REPLACE INTO repositories (id, project_id, name, default_branch, web_url, is_disabled)
                VALUES ('r-dep-name', 'TEST_PROJ', 'my-deprecated-tool', 'refs/heads/dev', 'http://tfs/dep-name', 0)
            """)
            conn.execute("""
                INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_date, raw_json)
                VALUES (998, 'r-dep-name', 'Another Deprecated PR', 'active', 'refs/heads/dev', 'refs/heads/dep-tool-feat', 'Dev1', '', '{}')
            """)

            # Also add an archive branch to repo-app
            conn.execute("""
                INSERT OR REPLACE INTO branches (repo_id, name, commit_id, commit_date, committer_name, comment, ahead_count, behind_count)
                VALUES ('r-app', 'refs/heads/archive/old-experiment', 'arc123', '2026-08-25 10:00:00', 'Dev2', 'Archived experiment', 10, 0)
            """)

        data = generate_tagday_report.load_tagday_data(
            self.cache,
            project_id="TEST_PROJ",
            ignore_category_patterns=["*deprecated*"],
            ignore_branch_patterns=["*archive*", "*demo*"]
        )

        # Both repos should be in all_repositories, but NOT in repos_with_prs, repos_with_unmerged_branches, or repos_with_any_changes
        self.assertIn("repo-deprecated-app", data["all_repositories"])
        self.assertIn("my-deprecated-tool", data["all_repositories"])
        self.assertNotIn("repo-deprecated-app", data["repos_with_prs"])
        self.assertNotIn("my-deprecated-tool", data["repos_with_prs"])
        self.assertNotIn("repo-deprecated-app", data["repos_with_unmerged_branches"])
        self.assertNotIn("my-deprecated-tool", data["repos_with_unmerged_branches"])
        self.assertNotIn("repo-deprecated-app", data["repos_with_any_changes"])
        self.assertNotIn("my-deprecated-tool", data["repos_with_any_changes"])

        # Timeline should NOT contain any items from either repo
        timeline_repos = [item["repo_name"] for item in data["all_changes_timeline"]]
        self.assertNotIn("repo-deprecated-app", timeline_repos)
        self.assertNotIn("my-deprecated-tool", timeline_repos)

        # The archive branch in repo-app should NOT be included in unmerged_branches
        app_branches = [b["branch_name"] for b in data["all_repositories"]["repo-app"]["unmerged_branches"]]
        self.assertNotIn("archive/old-experiment", app_branches)

    def test_branches_referencing_abandoned_or_completed_prs_excluded(self):
        """Tests that branches referencing abandoned or completed PRs are excluded from unmerged branches and timeline."""
        self._seed_sample_repo_data()

        with self.cache._connection() as conn:
            # Add an abandoned PR for branch 'features/pending-work'
            conn.execute("""
                INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_date, raw_json)
                VALUES (777, 'r-app', 'PR for pending work', 'abandoned', 'refs/heads/dev', 'refs/heads/features/pending-work', 'Dev1', '2026-08-20 12:00:00', '{}')
            """)
            # Add a branch referencing a completed PR (e.g. feat1 from seed data which has completed PR 101)
            conn.execute("""
                INSERT OR REPLACE INTO branches (repo_id, name, commit_id, commit_date, committer_name, comment, ahead_count, behind_count)
                VALUES ('r-app', 'refs/heads/feat1', 'b_hash_feat1', '2026-08-01 12:00:00', 'Dev1', 'Old merged branch', 5, 0)
            """)

        data = generate_tagday_report.load_tagday_data(self.cache, project_id="TEST_PROJ")
        app_branches = data["all_repositories"]["repo-app"]["unmerged_branches"]
        branch_names = [b["branch_name"] for b in app_branches]

        # Abandoned PR branch (features/pending-work) should NOT be in unmerged_branches
        self.assertNotIn("features/pending-work", branch_names)

        # Completed PR branch (feat1) should NOT be in unmerged_branches
        self.assertNotIn("feat1", branch_names)

        # Active PR branch (feat3) SHOULD be in unmerged_branches
        self.assertIn("feat3", branch_names)
        feat3_branch = next(b for b in app_branches if b["branch_name"] == "feat3")
        self.assertIsNotNone(feat3_branch["prepared_pr"])
        self.assertEqual(feat3_branch["prepared_pr"]["pr_id"], 103)

        # Timeline check: abandoned/completed branch updates should NOT be in timeline
        timeline_titles = [t.get("title", "") for t in data["all_changes_timeline"] if t.get("item_type") == "BRANCH_UPDATE"]
        self.assertFalse(any("features/pending-work" in title for title in timeline_titles))
        self.assertFalse(any("feat1" in title for title in timeline_titles))

    def test_is_version_tag(self):
        from utils import is_version_tag
        self.assertTrue(is_version_tag("v01.02.2632"))
        self.assertTrue(is_version_tag("v1.0.0"))
        self.assertTrue(is_version_tag("V2.1.0"))
        self.assertTrue(is_version_tag("v2026.39"))
        self.assertFalse(is_version_tag("1.0.0"))
        self.assertFalse(is_version_tag("release-1.0"))
        self.assertFalse(is_version_tag("build-1234"))
        self.assertFalse(is_version_tag("nightly-2026"))
        self.assertFalse(is_version_tag(""))
        self.assertFalse(is_version_tag(None))

    def test_tagday_ignores_non_v_prefix_tags(self):
        """Verifies that tags with prefixes other than 'v*' are ignored for repository latest tag calculation."""
        with self.cache._connection() as conn:
            conn.execute("INSERT OR REPLACE INTO projects (id, name) VALUES (?, ?)", ("TEST_PROJ", "Test Project"))
            conn.execute("INSERT OR REPLACE INTO repositories (id, project_id, name, default_branch, web_url) VALUES (?, ?, ?, ?, ?)",
                         ("r-custom", "TEST_PROJ", "repo-custom-tags", "refs/heads/main", "http://tfs/custom"))
            
            # Insert a non-v tag (newer date) and a v tag (older date)
            conn.execute("""
                INSERT OR REPLACE INTO tags (repo_id, name, commit_id, commit_date, committer_name, comment, is_stable, is_unstable, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, ("r-custom", "release-2026.99", "sha999", "2026-09-01 10:00:00", "Dev", "Non-v release tag", 1, 0, "{}"))
            conn.execute("""
                INSERT OR REPLACE INTO tags (repo_id, name, commit_id, commit_date, committer_name, comment, is_stable, is_unstable, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, ("r-custom", "v01.00.2630", "sha111", "2026-08-01 10:00:00", "Dev", "Valid v tag", 1, 0, "{}"))

        data = generate_tagday_report.load_tagday_data(self.cache, project_id="TEST_PROJ")
        repo_info = data["all_repositories"]["repo-custom-tags"]
        
        # The latest tag must be 'v01.00.2630' and NOT 'release-2026.99'
        self.assertIsNotNone(repo_info["latest_tag"])
        self.assertEqual(repo_info["latest_tag"]["name"], "v01.00.2630")


if __name__ == "__main__":
    unittest.main()


