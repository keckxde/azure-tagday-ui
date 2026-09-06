# -*- coding: UTF-8 -*-
import os
import sys
import unittest
from unittest.mock import MagicMock

# Add py directory to sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import devops_helper


class TestPatchPrTitle(unittest.TestCase):

    def setUp(self):
        self.mock_cache = MagicMock()
        # Seed mock work items
        self.work_items = {
            138058: {
                "id": 138058,
                "title": "OI-171: LoupeDeck Profil PWR Implementieren",
                "raw_json": '{"fields": {"System.Title": "OI-171: LoupeDeck Profil PWR Implementieren", "System.Description": "Implement profile"}}'
            },
            141501: {
                "id": 141501,
                "title": "OI 162 3/13 aus dem Wartungsmenu",
                "raw_json": '{"fields": {"System.Title": "OI 162 3/13 aus dem Wartungsmenu", "System.Description": ""}}'
            },
            200001: {
                "id": 200001,
                "title": "MP-05: Milestone check",
                "raw_json": '{"fields": {"System.Title": "MP-05: Milestone check", "System.Description": "Follow [OIL_12] guidelines"}}'
            },
            200002: {
                "id": 200002,
                "title": "Scenario tests",
                "raw_json": '{"fields": {"System.Title": "Scenario tests", "System.Description": "Resolves SCENARIO-42 test case"}}'
            },
            300001: {
                "id": 300001,
                "title": "Ordinary task without schematics",
                "raw_json": '{"fields": {"System.Title": "Ordinary task without schematics", "System.Description": "Just normal work"}}'
            }
        }
        self.mock_cache.get_work_item.side_effect = lambda wid: self.work_items.get(int(str(wid).lstrip("#")))

    def test_extract_schematics_from_text(self):
        # Bracketed schematics
        self.assertEqual(devops_helper.extract_schematics_from_text("[OI_171] Fix something"), ["[OI_171]"])
        self.assertEqual(devops_helper.extract_schematics_from_text("[OIL_45] and [MP_02]"), ["[OIL_45]", "[MP_02]"])
        self.assertEqual(devops_helper.extract_schematics_from_text("[SCENARIO_12]"), ["[SCENARIO_12]"])

        # Unbracketed named schematics with dash, underscore, space
        self.assertEqual(devops_helper.extract_schematics_from_text("OI-171: LoupeDeck"), ["[OI_171]"])
        self.assertEqual(devops_helper.extract_schematics_from_text("OI_171: LoupeDeck"), ["[OI_171]"])
        self.assertEqual(devops_helper.extract_schematics_from_text("OI 171 LoupeDeck"), ["[OI_171]"])
        self.assertEqual(devops_helper.extract_schematics_from_text("OIL-99 list issue"), ["[OIL_99]"])
        self.assertEqual(devops_helper.extract_schematics_from_text("MP-03 milestone item"), ["[MP_03]"])
        self.assertEqual(devops_helper.extract_schematics_from_text("SCENARIO-7 verification"), ["[SCENARIO_7]"])

        # Empty or None
        self.assertEqual(devops_helper.extract_schematics_from_text(""), [])
        self.assertEqual(devops_helper.extract_schematics_from_text(None), [])

    def test_patch_pr_title_from_referenced_work_item(self):
        # PR references work item 138058 via #138058 in title -> #138058 is removed
        pr = {"title": "#138058: LoupeDeck Profil PWR Implementieren"}
        patched = devops_helper.patch_pr_title_for_release_notes(pr, cache_db=self.mock_cache)
        self.assertEqual(patched, "[OI_171] LoupeDeck Profil PWR Implementieren")

        # PR references work item 141501 in description
        pr2 = {
            "title": "Fix maintenance menu crash",
            "description": "This addresses #141501 reported during testing"
        }
        patched2 = devops_helper.patch_pr_title_for_release_notes(pr2, cache_db=self.mock_cache)
        self.assertEqual(patched2, "[OI_162] Fix maintenance menu crash")

    def test_patch_pr_title_with_multiple_schematics(self):
        # PR references work item 200001 which has MP-05 in title and OIL_12 in description
        pr = {"title": "Update milestone", "description": "Relates to #200001"}
        patched = devops_helper.patch_pr_title_for_release_notes(pr, cache_db=self.mock_cache)
        self.assertEqual(patched, "[MP_05] [OIL_12] Update milestone")

    def test_patch_pr_title_already_prefixed(self):
        # Title already has exact prefix -> do not duplicate
        pr = {"title": "[OI_171] LoupeDeck Profil PWR Implementieren"}
        patched = devops_helper.patch_pr_title_for_release_notes(pr, cache_db=self.mock_cache)
        self.assertEqual(patched, "[OI_171] LoupeDeck Profil PWR Implementieren")

        # Title starts with raw format e.g. OI-171: -> normalize to [OI_171]
        pr2 = {"title": "OI-171: LoupeDeck Profil PWR Implementieren"}
        patched2 = devops_helper.patch_pr_title_for_release_notes(pr2, cache_db=self.mock_cache)
        self.assertEqual(patched2, "[OI_171] LoupeDeck Profil PWR Implementieren")

    def test_patch_pr_title_remove_embedded_type_or_nr_references(self):
        # Embedded in parentheses without separator (OI171)
        pr = {"title": "Screenshot / Eval Dialog (OI171) / Erkunden Fz"}
        patched = devops_helper.patch_pr_title_for_release_notes(pr, cache_db=self.mock_cache)
        self.assertEqual(patched, "[OI_171] Screenshot / Eval Dialog / Erkunden Fz")

        # Trailing work item reference #138058
        pr2 = {"title": "Replace the temporary Bttr Of Icons with new ones from armasuisse #138058"}
        patched2 = devops_helper.patch_pr_title_for_release_notes(pr2, cache_db=self.mock_cache)
        self.assertEqual(patched2, "[OI_171] Replace the temporary Bttr Of Icons with new ones from armasuisse")

        # PR title is only the work item number -> fall back to cleaned work item title
        pr3 = {"title": "#138058"}
        patched3 = devops_helper.patch_pr_title_for_release_notes(pr3, cache_db=self.mock_cache)
        self.assertEqual(patched3, "[OI_171] LoupeDeck Profil PWR Implementieren")

    def test_patch_pr_title_no_matching_schematics(self):
        # Normal title referencing non-schematic work item
        pr = {"title": "#300001: Standard code cleanup"}
        patched = devops_helper.patch_pr_title_for_release_notes(pr, cache_db=self.mock_cache)
        self.assertEqual(patched, "#300001: Standard code cleanup")

        # Simple string title with no work item
        title = "Refactor database access layer"
        patched2 = devops_helper.patch_pr_title_for_release_notes(title, cache_db=self.mock_cache)
        self.assertEqual(patched2, "Refactor database access layer")

    def test_patch_pr_title_string_and_row_inputs(self):
        # String with inline schematic
        res = devops_helper.patch_pr_title_for_release_notes("SCENARIO-42: Test navigation flow")
        self.assertEqual(res, "[SCENARIO_42] Test navigation flow")

        # Empty string
        self.assertEqual(devops_helper.patch_pr_title_for_release_notes(""), "")

    def test_patch_pr_title_logs_warning(self):
        pr = {"id": 1234, "title": "#138058: LoupeDeck Profil"}
        with self.assertLogs("devops_helper", level="WARNING") as cm:
            patched = devops_helper.patch_pr_title_for_release_notes(pr, cache_db=self.mock_cache)
        self.assertEqual(patched, "[OI_171] LoupeDeck Profil")
        self.assertTrue(any("PR #1234: title patched" in log_msg for log_msg in cm.output))

    def test_is_version_title(self):
        # Pure version titles
        self.assertTrue(devops_helper.is_version_title("v1.02.2632"))
        self.assertTrue(devops_helper.is_version_title("v0.10.24"))
        self.assertTrue(devops_helper.is_version_title("1.02.2632"))
        self.assertTrue(devops_helper.is_version_title("v01.02.2632"))
        self.assertTrue(devops_helper.is_version_title("v1.0.0-rc.1"))
        self.assertTrue(devops_helper.is_version_title("Merged PR 27375: v0.10.24"))
        self.assertTrue(devops_helper.is_version_title("Merged PR 27376: Merged PR 27375: v0.10.24"))

        # Titles with additional words/descriptions -> False
        self.assertFalse(devops_helper.is_version_title("Make v1.3.15 the new stable"))
        self.assertFalse(devops_helper.is_version_title("v0.10.24 - First Test Release for Bière"))
        self.assertFalse(devops_helper.is_version_title("OI-171: LoupeDeck Profil"))
        self.assertFalse(devops_helper.is_version_title(None))
        self.assertFalse(devops_helper.is_version_title(""))

    def test_do_not_patch_version_titles(self):
        # PR title is only version reference, even if it has referenced work item #138058
        pr = {
            "title": "v1.02.2632",
            "description": "Addresses #138058",
            "work_items": [138058]
        }
        patched = devops_helper.patch_pr_title_for_release_notes(pr, cache_db=self.mock_cache)
        self.assertEqual(patched, "v1.02.2632")

        # TFS auto-merge version title
        pr2 = {
            "title": "Merged PR 27375: v0.10.24",
            "description": "Fixes #138058",
            "work_items": [138058]
        }
        patched2 = devops_helper.patch_pr_title_for_release_notes(pr2, cache_db=self.mock_cache)
        self.assertEqual(patched2, "Merged PR 27375: v0.10.24")


if __name__ == "__main__":
    unittest.main()
