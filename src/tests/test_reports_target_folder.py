# -*- coding: UTF-8 -*-
import os
import sys
import unittest
import tempfile
import sqlite3

# Add src directory to sys.path
src_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if src_dir not in sys.path:
    sys.path.insert(0, src_dir)

import utils
import devops_helper
import generate_tagday_report
import generate_revision
import generate_artifacts_report
import generate_sprint_report
import generate_rescheduling_report
from azure import AzureDevOpsCache


class TestReportsTargetFolder(unittest.TestCase):

    def setUp(self):
        self.orig_base_folder = devops_helper.BASE_FOLDER
        self.orig_env_reports_dir = os.environ.get("REPORTS_DIR")
        self.orig_env_base_folder = os.environ.get("BASE_FOLDER")

    def tearDown(self):
        devops_helper.BASE_FOLDER = self.orig_base_folder
        if self.orig_env_reports_dir is not None:
            os.environ["REPORTS_DIR"] = self.orig_env_reports_dir
        else:
            os.environ.pop("REPORTS_DIR", None)
        if self.orig_env_base_folder is not None:
            os.environ["BASE_FOLDER"] = self.orig_env_base_folder
        else:
            os.environ.pop("BASE_FOLDER", None)

    def test_utils_get_reports_dir_default_and_env(self):
        # When not set, defaults to cwd or custom default
        os.environ.pop("REPORTS_DIR", None)
        os.environ.pop("BASE_FOLDER", None)
        self.assertEqual(utils.get_reports_dir(), os.getcwd())
        self.assertEqual(utils.get_reports_dir(default="custom/path"), os.path.normpath("custom/path"))

        # When set via environment variable
        with tempfile.TemporaryDirectory() as tmp_dir:
            os.environ["REPORTS_DIR"] = tmp_dir
            self.assertEqual(utils.get_reports_dir(), os.path.normpath(tmp_dir))
            self.assertEqual(devops_helper.get_reports_dir(), os.path.normpath(tmp_dir))

    def test_generate_revision_reads_baseline_and_writes_to_configured_target(self):
        with tempfile.TemporaryDirectory() as baseline_dir, tempfile.TemporaryDirectory() as target_dir:
            # 1. Create a baseline REVISION.md in baseline_dir
            baseline_file = os.path.join(baseline_dir, "REVISION.md")
            baseline_content = """# Revision History

| Package | SuperInstaller | Unstable (Nightly) | Stable | Last Change | Owner |
| ------- | -------------- | ------------------ | ------ | ----------- | ----- |
| [CoreRepo](#corerepo) | v1.0.0 | v1.0.0 | v1.0.0 | 0 | Bob |

### CoreRepo

**Info:**
* Baseline package description

**Version:**
| Date | Version | Stable | Description |
| ---- | ------- | ------ | ----------- |
| 10.05.25 | v1.0.0 | Yes | Initial baseline release |
"""
            with open(baseline_file, "w", encoding="utf-8") as f:
                f.write(baseline_content)

            # 2. Setup DB with new tag and PR
            db_path = os.path.join(target_dir, "test.db")
            cache = AzureDevOpsCache(db_path)
            with cache._connection() as conn:
                conn.execute("INSERT INTO projects (id, name) VALUES (?, ?)", ("proj-1", "DemoProj"))
                conn.execute("INSERT INTO repositories (id, name, project_id) VALUES (?, ?, ?)", ("repo-1", "CoreRepo", "proj-1"))
                conn.execute(
                    "INSERT INTO tags (name, repo_id, commit_date, commit_id, is_stable, is_unstable, committer_name) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    ("v1.1.0", "repo-1", "2026-09-20T10:00:00", "commit-123", 1, 0, "Alice")
                )
                conn.execute(
                    "INSERT INTO pull_requests (id, repo_id, title, closed_date, raw_json) VALUES (?, ?, ?, ?, ?)",
                    (201, "repo-1", "Add feature XYZ", "2026-09-18T12:00:00", '{"lastMergeCommit": {"commitId": "commit-123"}}')
                )

            # Configure target reports directory
            os.environ["REPORTS_DIR"] = target_dir
            devops_helper.BASE_FOLDER = target_dir

            # Generate revision report specifying target path in target_dir
            target_report_file = os.path.join(target_dir, "REVISION.md")
            target_docx_file = os.path.join(target_dir, "REVISION.docx")

            success = generate_revision.generate_revision_md(db_path, revision_md_path=target_report_file)
            self.assertTrue(success)
            self.assertTrue(os.path.exists(target_report_file))
            self.assertTrue(os.path.exists(target_docx_file))

            with open(target_report_file, "r", encoding="utf-8") as f:
                generated = f.read()
            self.assertIn("CoreRepo", generated)
            self.assertIn("v1.1.0", generated)

    def test_generate_tagday_report_in_configured_folder(self):
        with tempfile.TemporaryDirectory() as target_dir:
            db_path = os.path.join(target_dir, "test.db")
            cache = AzureDevOpsCache(db_path)
            with cache._connection() as conn:
                conn.execute("INSERT INTO projects (id, name) VALUES (?, ?)", ("p1", "TestProject"))
                conn.execute("INSERT INTO repositories (id, name, project_id, default_branch) VALUES (?, ?, ?, ?)", ("r1", "RepoAlpha", "p1", "main"))
                conn.execute("INSERT INTO tags (name, repo_id, commit_date, commit_id, is_stable, is_unstable) VALUES (?, ?, ?, ?, ?, ?)",
                             ("v1.0.2630", "r1", "2026-08-01T00:00:00", "c1", 1, 0))

            os.environ["REPORTS_DIR"] = target_dir
            devops_helper.BASE_FOLDER = target_dir

            success = devops_helper.generate_tagday_report(
                db_path=db_path,
                project_id="TestProject",
                reports_dir=target_dir
            )
            self.assertTrue(success)
            expected_tagday = os.path.join(target_dir, "TAGDAY.md")
            self.assertTrue(os.path.exists(expected_tagday))
            with open(expected_tagday, "r", encoding="utf-8") as f:
                content = f.read()
            self.assertIn("Tag Day", content)

    def test_generate_artifacts_report_in_configured_folder(self):
        with tempfile.TemporaryDirectory() as target_dir:
            db_path = os.path.join(target_dir, "test.db")
            cache = AzureDevOpsCache(db_path)
            with cache._connection() as conn:
                conn.execute("INSERT INTO projects (id, name) VALUES (?, ?)", ("p1", "TestProject"))

            os.environ["REPORTS_DIR"] = target_dir
            devops_helper.BASE_FOLDER = target_dir

            success = devops_helper.generate_artifacts_report(
                db_path=db_path,
                reports_dir=target_dir
            )
            self.assertTrue(success)
            expected_md = os.path.join(target_dir, "BUILD_ARTIFACTS.md")
            expected_csv = os.path.join(target_dir, "BUILD_ARTIFACTS.csv")
            self.assertTrue(os.path.exists(expected_md))
            self.assertTrue(os.path.exists(expected_csv))

    def test_generate_sprint_and_rescheduling_reports_in_configured_folder(self):
        with tempfile.TemporaryDirectory() as target_dir:
            db_path = os.path.join(target_dir, "test.db")
            cache = AzureDevOpsCache(db_path)
            with cache._connection() as conn:
                conn.execute("INSERT INTO projects (id, name) VALUES (?, ?)", ("p1", "TestProject"))

            os.environ["REPORTS_DIR"] = target_dir
            devops_helper.BASE_FOLDER = target_dir

            # Sprint report
            md_out = os.path.join(target_dir, "SPRINT_REPORT_week-2635.md")
            csv_out = os.path.join(target_dir, "SPRINT_REPORT_week-2635.csv")
            data, md_content = generate_sprint_report.generate_sprint_report(
                cache,
                sprint_name="week-2635",
                output_md=md_out,
                output_csv=csv_out
            )
            self.assertTrue(os.path.exists(md_out))
            self.assertTrue(os.path.exists(csv_out))

            # Rescheduling report
            res = generate_rescheduling_report.generate_rescheduling_report(
                cache_db=cache,
                output_md=os.path.join(target_dir, "RESCHEDULING_REPORT.md"),
                output_csv=os.path.join(target_dir, "RESCHEDULING_REPORT.csv")
            )
            self.assertTrue(res["success"])
            self.assertTrue(os.path.exists(res["md_path"]))
            self.assertTrue(os.path.exists(res["csv_path"]))


if __name__ == "__main__":
    unittest.main()
