# -*- coding: UTF-8 -*-
import os
import sys
import tempfile
import csv
import unittest

# Add py directory to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from azure import AzureDevOpsCache
import generate_artifacts_report


class TestArtifactsReport(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmp_dir, "test_cache.db")
        self.md_path = os.path.join(self.tmp_dir, "test_report.md")
        self.csv_path = os.path.join(self.tmp_dir, "test_report.csv")
        self.cache = AzureDevOpsCache(self.db_path)

    def tearDown(self):
        del self.cache
        import gc
        gc.collect()
        for f in (self.db_path, self.md_path, self.csv_path):
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

    def test_calculate_metrics(self):
        sample_artifacts = [
            {
                "build_id": 1,
                "artifact_name": "art1.zip",
                "pipeline_name": "PipeA",
                "repo_name": "Repo1",
                "build_result": "succeeded",
                "size_bytes": 10485760,  # 10 MB
                "size_mb": 10.0,
                "is_deleted": 0,
                "finish_time": "2026-09-01 12:00:00"
            },
            {
                "build_id": 1,
                "artifact_name": "art2.zip",
                "pipeline_name": "PipeA",
                "repo_name": "Repo1",
                "build_result": "succeeded",
                "size_bytes": 20971520,  # 20 MB
                "size_mb": 20.0,
                "is_deleted": 1,
                "finish_time": "2026-09-01 12:00:00"
            },
            {
                "build_id": 2,
                "artifact_name": "crash.dmp",
                "pipeline_name": "PipeB",
                "repo_name": "Repo2",
                "build_result": "failed",
                "size_bytes": 52428800,  # 50 MB
                "size_mb": 50.0,
                "is_deleted": 0,
                "finish_time": "2026-08-01 12:00:00"
            }
        ]

        metrics = generate_artifacts_report.calculate_metrics(sample_artifacts)
        self.assertEqual(metrics["total_builds"], 2)
        self.assertEqual(metrics["total_artifacts"], 3)
        self.assertEqual(metrics["active_artifacts_count"], 2)
        self.assertEqual(metrics["deleted_artifacts_count"], 1)
        self.assertAlmostEqual(metrics["total_size_mb"], 80.0, places=1)
        self.assertAlmostEqual(metrics["active_size_mb"], 60.0, places=1)
        self.assertAlmostEqual(metrics["deleted_size_mb"], 20.0, places=1)
        self.assertEqual(metrics["failed_count"], 1)
        self.assertAlmostEqual(metrics["failed_size_mb"], 50.0, places=1)

    def test_run_reports_end_to_end(self):
        # Seed test build and artifact data into database
        with self.cache._connection() as conn:
            conn.execute("INSERT OR REPLACE INTO projects (id, name) VALUES (?, ?)", ("TEST_PROJ", "Test Project"))
            conn.execute("""
                INSERT OR REPLACE INTO builds (id, project_id, build_number, status, result, queue_time, start_time, finish_time)
                VALUES (1, 'TEST_PROJ', '20260901.1', 'completed', 'succeeded', '2026-09-01 10:00:00', '2026-09-01 10:01:00', '2026-09-01 10:05:00')
            """)
            conn.execute("""
                INSERT OR REPLACE INTO artifacts (id, build_id, name, type, size_bytes, size_mb, download_url, url, is_deleted)
                VALUES (101, 1, 'art1.zip', 'Container', 10485760, 10.0, 'http://tfs/art1.zip', 'http://tfs/art1', 0)
            """)

        success = generate_artifacts_report.run_reports(
            db_path=self.db_path,
            md_path=self.md_path,
            csv_path=self.csv_path,
            auto_seed=False
        )
        self.assertTrue(success)
        self.assertTrue(os.path.exists(self.md_path))
        self.assertTrue(os.path.exists(self.csv_path))


if __name__ == "__main__":
    unittest.main()
