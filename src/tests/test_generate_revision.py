# -*- coding: UTF-8 -*-
import os
import sys
import unittest
from datetime import datetime

# Add py directory to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import generate_revision


class TestGenerateRevision(unittest.TestCase):

    def test_parse_revision_date(self):
        # 2-digit year >= 80 -> 1900s
        dt_old = generate_revision.parse_revision_date("31.12.95")
        self.assertEqual(dt_old, datetime(1995, 12, 31))

        # 2-digit year < 80 -> 2000s
        dt_new = generate_revision.parse_revision_date("06.09.26")
        self.assertEqual(dt_new, datetime(2026, 9, 6))

        # 4-digit year
        dt_full = generate_revision.parse_revision_date("15.05.2025")
        self.assertEqual(dt_full, datetime(2025, 5, 15))

        # Invalid formats
        self.assertIsNone(generate_revision.parse_revision_date(""))
        self.assertIsNone(generate_revision.parse_revision_date(None))
        self.assertIsNone(generate_revision.parse_revision_date("2025-05-15"))
        self.assertIsNone(generate_revision.parse_revision_date("invalid"))

    def test_safe_iso_parse(self):
        # Standard ISO
        dt_iso = generate_revision.safe_iso_parse("2026-09-06T10:30:00")
        self.assertEqual(dt_iso, datetime(2026, 9, 6, 10, 30, 0))

        # Space-separated
        dt_space = generate_revision.safe_iso_parse("2026-09-06 10:30:00")
        self.assertEqual(dt_space, datetime(2026, 9, 6, 10, 30, 0))

        # Invalid
        self.assertIsNone(generate_revision.safe_iso_parse(""))
        self.assertIsNone(generate_revision.safe_iso_parse(None))
        self.assertIsNone(generate_revision.safe_iso_parse("not-a-valid-date"))

    def test_format_date_rev(self):
        dt = datetime(2026, 9, 6)
        self.assertEqual(generate_revision.format_date_rev(dt), "06.09.26")
        self.assertEqual(generate_revision.format_date_rev(None), "")

    def test_get_last_change(self):
        # Version ending in digits
        val = generate_revision.get_last_change("v1.0.42", "v1.0.10", "fallback")
        self.assertEqual(val, "42")

        # Stable greater than unstable
        val_stable = generate_revision.get_last_change("v1.0.10", "v1.0.99", "fallback")
        self.assertEqual(val_stable, "99")

        # Fallback when version ends in 0
        val_fallback = generate_revision.get_last_change("v1.0.0", "v1.0.0", "fallback")
        self.assertEqual(val_fallback, "fallback")

        # Empty strings return ""
        val_empty = generate_revision.get_last_change("", "", "fallback")
        self.assertEqual(val_empty, "")


    def test_generate_revision_md_from_scratch(self):
        import tempfile
        import sqlite3
        import devops_helper
        from azure import AzureDevOpsCache

        with tempfile.TemporaryDirectory() as tmp_dir:
            db_path = os.path.join(tmp_dir, "test_cache.db")
            cache = AzureDevOpsCache(db_path)

            # Insert sample repository, tags, and PRs
            with cache._connection() as conn:
                conn.execute("INSERT INTO projects (id, name) VALUES (?, ?)", ("proj-1", "TestProject"))
                conn.execute("INSERT INTO repositories (id, name, project_id) VALUES (?, ?, ?)", ("repo-1", "TestRepo1", "proj-1"))
                conn.execute("INSERT INTO repositories (id, name, project_id) VALUES (?, ?, ?)", ("repo-2", "RepoNoTags", "proj-1"))
                conn.execute(
                    "INSERT INTO tags (name, repo_id, commit_date, commit_id, is_stable, is_unstable, committer_name) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    ("v1.2.0", "repo-1", "2026-08-01T10:00:00", "a1b2c3d4e5", 1, 0, "Alice")
                )
                conn.execute(
                    "INSERT INTO pull_requests (id, repo_id, title, closed_date, raw_json) VALUES (?, ?, ?, ?, ?)",
                    (101, "repo-1", "Feature A", "2026-07-20T12:00:00", '{"lastMergeCommit": {"commitId": "a1b2c3d4e5"}}')
                )

            # Target revision file in a nested subdirectory that doesn't exist yet
            target_md = os.path.join(tmp_dir, "doc", "04_Development", "REVISION.md")
            target_docx = os.path.join(tmp_dir, "doc", "04_Development", "REVISION.docx")

            self.assertFalse(os.path.exists(target_md))
            self.assertFalse(os.path.exists(target_docx))

            success = devops_helper.generate_revision_report(
                db_path=db_path,
                revision_md_path=target_md
            )

            self.assertTrue(success)
            self.assertTrue(os.path.exists(target_md))
            self.assertTrue(os.path.exists(target_docx))

            with open(target_md, "r", encoding="utf-8") as f:
                content = f.read()

            self.assertIn("# Revision History", content)
            self.assertIn("TestRepo1", content)
            self.assertIn("RepoNoTags", content)
            self.assertIn("v1.2.0", content)
            self.assertIn("!101: Feature A", content)

    def test_generate_revision_md_preserves_history(self):
        import tempfile
        import devops_helper
        from azure import AzureDevOpsCache

        with tempfile.TemporaryDirectory() as tmp_dir:
            db_path = os.path.join(tmp_dir, "test_cache.db")
            cache = AzureDevOpsCache(db_path)

            with cache._connection() as conn:
                conn.execute("INSERT INTO projects (id, name) VALUES (?, ?)", ("proj-1", "TestProject"))
                conn.execute("INSERT INTO repositories (id, name, project_id) VALUES (?, ?, ?)", ("repo-1", "HistoricalRepo", "proj-1"))
                conn.execute(
                    "INSERT INTO tags (name, repo_id, commit_date, commit_id, is_stable, is_unstable, committer_name) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    ("v2.0.0", "repo-1", "2026-08-01T10:00:00", "c0ffee123", 1, 0, "Bob")
                )


            target_md = os.path.join(tmp_dir, "REVISION.md")

            # Existing markdown file with historical entries before cutoff date (2025-05-16)
            existing_content = (
                "# Revision History\n\n"
                "| Package | SuperInstaller | Unstable (Nightly) | Stable | Last Change | Owner |\n"
                "| ------- | -------------- | ------------------ | ------ | ----------- | ----- |\n"
                "| [HistoricalRepo](#historicalrepo) | | | | | |\n\n"
                "### HistoricalRepo\n\n"
                "**Info:**\nImportant information.\n\n"
                "**Version:**\n\n"
                "| Date     | Version        | Stable | Description |\n"
                "| -------- | -------------- | ------ | ----------- |\n"
                "| 10.01.24 | v1.0.0         | X      | Legacy initial release |\n"
            )
            with open(target_md, "w", encoding="utf-8") as f:
                f.write(existing_content)

            success = generate_revision.generate_revision_md(db_path, target_md)
            self.assertTrue(success)

            with open(target_md, "r", encoding="utf-8") as f:
                updated_content = f.read()

            # Verify historical row and info block were preserved
            self.assertIn("Legacy initial release", updated_content)
            self.assertIn("**Info:**\nImportant information.", updated_content)


if __name__ == "__main__":
    unittest.main()

