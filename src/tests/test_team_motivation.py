# -*- coding: UTF-8 -*-
"""
Unit tests for Team Motivation, Leaderboard, Badges, and Streaks Engine.
Tests PRs, Work Items, Commits, Feature Branches, Tags, and CI Builds.
"""

import os
import sys
import unittest
import tempfile
import json
from datetime import datetime, timedelta

# Ensure src directory is in path
src_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if src_dir not in sys.path:
    sys.path.insert(0, src_dir)

from azure import AzureDevOpsCache
import team_motivation
from team_motivation import (
    compute_team_motivation_data,
    generate_motivation_markdown_summary,
    BADGE_DEFINITIONS
)


class TestTeamMotivation(unittest.TestCase):
    def setUp(self):
        self.tmp_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        self.tmp_db.close()
        self.cache = AzureDevOpsCache(self.tmp_db.name)

        now = datetime.now()
        cur_year, cur_week, _ = now.isocalendar()
        self.cur_sprint = f"week-{str(cur_year)[-2:]}{cur_week:02d}"

        last_dt = now - timedelta(days=7)
        ly, lw, _ = last_dt.isocalendar()
        self.last_sprint = f"week-{str(ly)[-2:]}{lw:02d}"

        # Populate sample PRs
        prs_sample = [
            {
                "pullRequestId": 101,
                "title": "Feature: Add telemetry",
                "status": "completed",
                "createdBy": {"displayName": "Alice Smith", "id": "1"},
                "closedBy": {"displayName": "Alice Smith", "id": "1"},
                "creationDate": (now - timedelta(days=5)).isoformat(),
                "closedDate": (now - timedelta(days=4)).isoformat(),
                "sourceRefName": "refs/heads/feature/telemetry",
                "reviewers": [
                    {"displayName": "Bob Jones", "id": "2", "vote": 10}
                ]
            },
            {
                "pullRequestId": 102,
                "title": "Fix: Critical crash",
                "status": "completed",
                "createdBy": {"displayName": "Alice Smith", "id": "1"},
                "closedBy": {"displayName": "Alice Smith", "id": "1"},
                "creationDate": (now - timedelta(days=6)).isoformat(),
                "closedDate": (now - timedelta(days=5, hours=20)).isoformat(),
                "sourceRefName": "refs/heads/bugfix/crash",
                "reviewers": [
                    {"displayName": "Charlie Brown", "id": "3", "vote": 10}
                ]
            },
            {
                "pullRequestId": 103,
                "title": "Refactor: Engine sync",
                "status": "completed",
                "createdBy": {"displayName": "Bob Jones", "id": "2"},
                "closedBy": {"displayName": "Bob Jones", "id": "2"},
                "creationDate": (now - timedelta(days=4)).isoformat(),
                "closedDate": (now - timedelta(days=3)).isoformat(),
                "sourceRefName": "refs/heads/feature/engine-sync",
                "reviewers": [
                    {"displayName": "Alice Smith", "id": "1", "vote": 10}
                ]
            }
        ]
        self.cache.save_pull_requests("repo1", prs_sample)

        # Populate sample Work Items
        wis_sample = [
            (201, "Implement auth module", "Task", "Closed", "Alice Smith", (now - timedelta(days=4)).strftime("%Y-%m-%d %H:%M:%S"),
             {"fields": {"System.Title": "Implement auth module", "System.IterationPath": f"Project\\{self.last_sprint}", "System.State": "Closed", "System.WorkItemType": "Task", "System.AssignedTo": {"displayName": "Alice Smith"}}}),
            (202, "Fix memory leak in parser", "Bug", "Resolved", "Alice Smith", (now - timedelta(days=3)).strftime("%Y-%m-%d %H:%M:%S"),
             {"fields": {"System.Title": "Fix memory leak in parser", "System.IterationPath": f"Project\\{self.last_sprint}", "System.State": "Resolved", "System.WorkItemType": "Bug", "System.AssignedTo": {"displayName": "Alice Smith"}}}),
            (203, "Design new dashboard", "User Story", "Closed", "Bob Jones", (now - timedelta(days=4)).strftime("%Y-%m-%d %H:%M:%S"),
             {"fields": {"System.Title": "Design new dashboard", "System.IterationPath": f"Project\\{self.last_sprint}", "System.State": "Closed", "System.WorkItemType": "User Story", "System.AssignedTo": {"displayName": "Bob Jones"}}}),
        ]
        for wid, title, wtype, state, assigned, cdate, raw_obj in wis_sample:
            self.cache.save_work_item(wid, title, wtype, state, assigned, cdate, raw_obj)

        # Populate sample Tags & Branches
        self.cache.save_single_tag("repo1", "v1.0.0", "commit1", commit_date=(now - timedelta(days=4)).strftime("%Y-%m-%d %H:%M:%S"), committer="Alice Smith")
        
        with self.cache._connection() as conn:
            conn.execute("""
                INSERT INTO branches (repo_id, name, commit_id, commit_date, committer_name, comment)
                VALUES ('repo1', 'feature/new-ui', 'c101', ?, 'Alice Smith', 'Initial UI draft')
            """, ((now - timedelta(days=4)).strftime("%Y-%m-%d %H:%M:%S"),))

            # Populate sample Builds
            conn.execute("""
                INSERT INTO builds (id, project_id, repo_id, pipeline_id, pipeline_name, build_number, status, result, start_time, finish_time, requested_by)
                VALUES (1, 'p1', 'repo1', 10, 'CI Build', '1.0.1', 'completed', 'succeeded', ?, ?, 'Alice Smith')
            """, ((now - timedelta(days=4)).strftime("%Y-%m-%d %H:%M:%S"), (now - timedelta(days=4)).strftime("%Y-%m-%d %H:%M:%S")))

            conn.execute("""
                INSERT INTO builds (id, project_id, repo_id, pipeline_id, pipeline_name, build_number, status, result, start_time, finish_time, requested_by)
                VALUES (2, 'p1', 'repo1', 10, 'CI Build', '1.0.2', 'completed', 'succeeded', ?, ?, 'Alice Smith')
            """, ((now - timedelta(days=3)).strftime("%Y-%m-%d %H:%M:%S"), (now - timedelta(days=3)).strftime("%Y-%m-%d %H:%M:%S")))

    def tearDown(self):
        if os.path.exists(self.tmp_db.name):
            try:
                os.remove(self.tmp_db.name)
            except Exception:
                pass

    def test_compute_team_motivation_all_time(self):
        data = compute_team_motivation_data(self.cache, timeframe="all_time")
        self.assertIn("team_summary", data)
        self.assertIn("members", data)
        self.assertIn("leaderboards", data)
        self.assertIn("all_badges", data)

        ts = data["team_summary"]
        self.assertGreaterEqual(ts["prs_created"], 3)
        self.assertGreaterEqual(ts["prs_closed"], 3)
        self.assertGreaterEqual(ts["tasks_completed"], 3)
        self.assertGreaterEqual(ts["commits_count"], 3)
        self.assertGreaterEqual(ts["branches_started"], 3)
        self.assertGreaterEqual(ts["branches_closed"], 3)
        self.assertGreaterEqual(ts["tags_pushed"], 1)
        self.assertGreaterEqual(ts["builds_total"], 2)
        self.assertGreaterEqual(ts["builds_succeeded"], 2)
        self.assertEqual(ts["build_success_rate"], 100.0)
        self.assertGreaterEqual(ts["active_contributors"], 2)

        # Verify leaderboard entries
        overall_lb = data["leaderboards"]["overall"]
        self.assertIsNotNone(overall_lb["leader"])
        self.assertIn(overall_lb["leader"]["name"], ["Alice Smith", "Bob Jones"])

        commits_lb = data["leaderboards"]["commits"]
        self.assertIsNotNone(commits_lb["leader"])

        builds_lb = data["leaderboards"]["builds"]
        self.assertIsNotNone(builds_lb["leader"])
        self.assertEqual(builds_lb["leader"]["name"], "Alice Smith")

    def test_badges_assignment(self):
        data = compute_team_motivation_data(self.cache, timeframe="all_time")
        members = {m["name"]: m for m in data["members"]}

        self.assertIn("Alice Smith", members)
        alice = members["Alice Smith"]
        self.assertGreater(alice["score"], 0)
        self.assertIsInstance(alice["badges"], list)

        # Check Speed Demon badge (fast turnaround under 24h)
        speed_badge = any(b["id"] == "speed_demon" for b in alice["badges"])
        self.assertTrue(speed_badge, "Alice should receive the Speed Demon badge for PR closed <24h")

        # Check CI Hero badge
        ci_badge = any(b["id"] == "ci_hero" for b in alice["badges"])
        self.assertTrue(ci_badge, "Alice should receive the CI Hero badge for successful builds")

    def test_markdown_summary_generation(self):
        data = compute_team_motivation_data(self.cache, timeframe="all_time")
        md = generate_motivation_markdown_summary(data)
        self.assertIn("Team Sprint Motivation & Hall of Fame", md)
        self.assertIn("Pull Requests Started / Merged", md)
        self.assertIn("Code Commits", md)
        self.assertIn("Feature Branches", md)
        self.assertIn("CI Pipeline Builds", md)
        self.assertIn("Leaderboard & Badges", md)
        self.assertIn("Alice Smith", md)

    def test_time_based_analytics_and_badges(self):
        data = compute_team_motivation_data(self.cache, timeframe="all_time")
        ts = data["team_summary"]
        self.assertIn("time_analytics", ts)
        ta = ts["time_analytics"]
        self.assertIn("daytime_pct", ta)
        self.assertIn("night_pct", ta)
        self.assertIn("weekend_pct", ta)
        self.assertIn("hourly_distribution", ta)
        self.assertEqual(len(ta["hourly_distribution"]), 24)
        self.assertEqual(len(ta["daily_distribution"]), 7)

        # Leaderboards check
        self.assertIn("night_owls", data["leaderboards"])
        self.assertIn("early_birds", data["leaderboards"])
        self.assertIn("weekend_warriors", data["leaderboards"])
        self.assertIn("daytime", data["leaderboards"])

        # Check badges list
        badge_ids = [b["id"] for b in data["all_badges"]]
        self.assertIn("night_owl", badge_ids)
        self.assertIn("early_bird", badge_ids)
        self.assertIn("weekend_warrior", badge_ids)
        self.assertIn("zen_balancer", badge_ids)
        self.assertIn("friday_hero", badge_ids)

        # Check member time stats and persona
        members = {m["name"]: m for m in data["members"]}
        for name, m in members.items():
            self.assertIn("time_stats", m)
            self.assertIn("persona", m["time_stats"])
            self.assertIn("hourly_distribution", m["time_stats"])
            self.assertEqual(len(m["time_stats"]["hourly_distribution"]), 24)


if __name__ == "__main__":
    unittest.main()
