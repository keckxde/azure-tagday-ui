# -*- coding: UTF-8 -*-
"""
Unit tests for dynamic git describe version detection, tag deviations, and packaging metadata.
"""
import unittest
from unittest.mock import patch
import version


class TestVersionDiscovery(unittest.TestCase):

    def test_live_git_describe_detection(self):
        info = version.get_version_info()
        self.assertIn("tag", info)
        self.assertIn("distance", info)
        self.assertIn("commit_hash", info)
        self.assertIn("is_dirty", info)
        self.assertIn("display_version", info)
        self.assertIn("pep440_version", info)
        self.assertIn("status_label", info)

    def test_exact_tag_parsing(self):
        with patch.object(version, "_get_git_describe", return_value="v0.01.2637-0-gb95f88e"):
            info = version.get_version_info()
            self.assertEqual(info["tag"], "v0.01.2637")
            self.assertEqual(info["distance"], 0)
            self.assertEqual(info["commit_hash"], "b95f88e")
            self.assertFalse(info["is_dirty"])
            self.assertTrue(info["is_exact_tag"])
            self.assertEqual(info["display_version"], "v0.01.2637")
            self.assertEqual(info["pep440_version"], "0.1.2637")
            self.assertEqual(info["status_label"], "Official Release Tag")

    def test_deviated_tag_distance_parsing(self):
        with patch.object(version, "_get_git_describe", return_value="v0.01.2637-5-g1a2b3c4"):
            info = version.get_version_info()
            self.assertEqual(info["tag"], "v0.01.2637")
            self.assertEqual(info["distance"], 5)
            self.assertEqual(info["commit_hash"], "1a2b3c4")
            self.assertFalse(info["is_dirty"])
            self.assertFalse(info["is_exact_tag"])
            self.assertEqual(info["display_version"], "v0.01.2637+5 (1a2b3c4)")
            self.assertEqual(info["pep440_version"], "0.1.2637.post5+1a2b3c4")
            self.assertEqual(info["status_label"], "+5 commits since v0.01.2637")

    def test_dirty_worktree_parsing(self):
        with patch.object(version, "_get_git_describe", return_value="v0.01.2637-3-g1a2b3c4-dirty"):
            info = version.get_version_info()
            self.assertEqual(info["distance"], 3)
            self.assertTrue(info["is_dirty"])
            self.assertFalse(info["is_exact_tag"])
            self.assertEqual(info["display_version"], "v0.01.2637+3 (1a2b3c4, modified)")
            self.assertEqual(info["pep440_version"], "0.1.2637.post3+1a2b3c4.dirty")
            self.assertIn("modified", info["status_label"])

    def test_backend_version_properties(self):
        from src.gui.backend import DevOpsBackend

        with patch.object(version, "_get_git_describe", return_value="v0.01.2637-0-gb95f88e"):
            backend = DevOpsBackend()
            self.assertEqual(backend.appVersion, "v0.01.2637")
            self.assertTrue(backend.isExactTagVersion)
            self.assertEqual(backend.appVersionInfo["commit_hash"], "b95f88e")


if __name__ == "__main__":
    unittest.main()
