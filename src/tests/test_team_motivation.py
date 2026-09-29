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

        # Populate sample Commits
        commits_sample = [
            {
                "commitId": "sha101",
                "author": {"name": "Alice Smith", "email": "alice@company.com", "date": (now - timedelta(days=4)).isoformat()},
                "committer": {"name": "Alice Smith", "email": "alice@company.com", "date": (now - timedelta(days=4)).isoformat()},
                "comment": "Feature: Implement high-performance buffer",
                "changeCounts": {"Add": 15, "Edit": 20, "Delete": 2}
            },
            {
                "commitId": "sha102",
                "author": {"name": "Alice Smith", "email": "alice@company.com", "date": (now - timedelta(days=3)).isoformat()},
                "committer": {"name": "Alice Smith", "email": "alice@company.com", "date": (now - timedelta(days=3)).isoformat()},
                "comment": "Fix: Handle null pointer on empty input",
                "changeCounts": {"Add": 2, "Edit": 5, "Delete": 0}
            },
            {
                "commitId": "sha103",
                "author": {"name": "Bob Jones", "email": "bob@company.com", "date": (now - timedelta(days=2)).isoformat()},
                "committer": {"name": "Bob Jones", "email": "bob@company.com", "date": (now - timedelta(days=2)).isoformat()},
                "comment": "Refactor: Modularize DB connection pool",
                "changeCounts": {"Add": 40, "Edit": 10, "Delete": 30}
            }
        ]
        self.cache.save_commits("repo1", commits_sample)

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

    def test_work_item_closed_date_gating_and_attribution(self):
        """
        Verify that:
        1. An old task closed a year ago, but touched/changed last week, is NOT credited as completed last week.
        2. An old task assigned to an inactive employee, but closed last week by an active employee,
           credits the active employee (ClosedBy) and NOT the inactive employee.
        """
        now = datetime.now()
        one_year_ago = now - timedelta(days=365)
        last_week = now - timedelta(days=4)

        # 1. Old task closed 1 year ago, but System.ChangedDate updated last week (e.g. tag/bulk edit)
        self.cache.save_work_item(
            301, "Old legacy task", "Task", "Closed", "Inactive Colleague",
            last_week.strftime("%Y-%m-%d %H:%M:%S"),
            {
                "fields": {
                    "System.Title": "Old legacy task",
                    "System.State": "Closed",
                    "System.WorkItemType": "Task",
                    "System.AssignedTo": {"displayName": "Inactive Colleague"},
                    "Microsoft.VSTS.Common.ClosedDate": one_year_ago.isoformat(),
                    "Microsoft.VSTS.Common.ClosedBy": {"displayName": "Inactive Colleague"},
                    "System.ChangedDate": last_week.isoformat(),
                }
            }
        )

        # 2. Old task assigned to Inactive Colleague, but closed last week by Alice Smith
        self.cache.save_work_item(
            302, "Cleaned up old bug", "Bug", "Closed", "Inactive Colleague",
            last_week.strftime("%Y-%m-%d %H:%M:%S"),
            {
                "fields": {
                    "System.Title": "Cleaned up old bug",
                    "System.State": "Closed",
                    "System.WorkItemType": "Bug",
                    "System.AssignedTo": {"displayName": "Inactive Colleague"},
                    "Microsoft.VSTS.Common.ClosedDate": last_week.isoformat(),
                    "Microsoft.VSTS.Common.ClosedBy": {"displayName": "Alice Smith"},
                    "System.ChangedDate": last_week.isoformat(),
                }
            }
        )

        data = compute_team_motivation_data(self.cache, timeframe="last_week")
        members = {m["name"]: m for m in data["members"]}

        # Inactive Colleague should NOT have tasks_completed in last_week
        if "Inactive Colleague" in members:
            self.assertEqual(members["Inactive Colleague"]["tasks_completed"], 0,
                             "Inactive colleague must not be credited for old tasks touched last week")

        # Alice Smith should receive credit for closing task 302
        self.assertIn("Alice Smith", members)
        # Alice already had tasks from setUp plus this 1 bug
        self.assertGreaterEqual(members["Alice Smith"]["tasks_completed"], 1)

    def test_commits_caching_and_sync(self):
        """
        Verify that commits saved to SQLite cache are retrieved correctly,
        and accurately aggregated into member commit metrics and motivation leaderboards.
        """
        all_commits = self.cache.get_all_commits()
        self.assertGreaterEqual(len(all_commits), 3)
        self.assertEqual(self.cache.get_commit_count(), len(all_commits))

        repo_commits = self.cache.get_commits_for_repo("repo1")
        self.assertGreaterEqual(len(repo_commits), 3)

        data = compute_team_motivation_data(self.cache, timeframe="all_time")
        members = {m["name"]: m for m in data["members"]}

        self.assertIn("Alice Smith", members)
        self.assertGreaterEqual(members["Alice Smith"]["commits_count"], 2)

        self.assertIn("Bob Jones", members)
        self.assertGreaterEqual(members["Bob Jones"]["commits_count"], 1)

        ts = data["team_summary"]
        self.assertGreaterEqual(ts["commits_count"], 3)

    def test_state_transition_recording_and_cleaner_decliner_badges(self):
        """
        Verify that state transition events (forward cleaning and backward pushbacks)
        are properly detected and recorded, and award 'The Cleaner' and 'The Decliner' badges.
        """
        now = datetime.now()
        yesterday = now - timedelta(days=1)

        # 1. Cleaner: Charlie cleans up 4 tasks to Resolved / Closed
        for i in range(1, 5):
            self.cache.record_state_event(
                work_item_id=400 + i,
                old_state="Active",
                new_state="Closed",
                changed_by="Charlie Brown",
                recorded_at=yesterday.isoformat(),
                is_pushback=0
            )

        # 2. Decliner: Diana pushes back 2 tasks from Resolved/Done back to Active/ToDo
        for i in range(1, 3):
            self.cache.record_state_event(
                work_item_id=500 + i,
                old_state="Resolved",
                new_state="Active",
                changed_by="Diana Prince",
                recorded_at=yesterday.isoformat(),
                is_pushback=1
            )

        data = compute_team_motivation_data(self.cache, timeframe="all_time")
        members = {m["name"]: m for m in data["members"]}

        # Charlie Brown check
        self.assertIn("Charlie Brown", members)
        charlie = members["Charlie Brown"]
        self.assertGreaterEqual(charlie["tasks_cleaned"], 4)
        self.assertTrue(charlie["is_cleaner"])
        has_cleaner_badge = any(b["id"] == "the_cleaner" for b in charlie["badges"])
        self.assertTrue(has_cleaner_badge, "Charlie should earn the 'The Cleaner' badge")

        # Diana Prince check
        self.assertIn("Diana Prince", members)
        diana = members["Diana Prince"]
        self.assertGreaterEqual(diana["pushbacks_count"], 2)
        self.assertTrue(diana["is_decliner"])
        has_decliner_badge = any(b["id"] == "the_decliner" for b in diana["badges"])
        self.assertTrue(has_decliner_badge, "Diana should earn the 'The Decliner' badge")
        self.assertEqual(diana["time_stats"]["persona"], "🛡️ The Gatekeeper")

        # Check leaderboards
        self.assertIn("cleaners", data["leaderboards"])
        self.assertIn("decliners", data["leaderboards"])
        self.assertIn("state_movers", data["leaderboards"])
        self.assertEqual(data["leaderboards"]["cleaners"]["leader"]["name"], "Charlie Brown")
        self.assertEqual(data["leaderboards"]["decliners"]["leader"]["name"], "Diana Prince")

    def test_stale_task_radar_and_ignorer_detection(self):
        """
        Verify that open work items with >=14 days of inactivity are captured in the Stale Radar,
        and contributors with multiple stale tasks and zero transitions receive the 'Backlog Stasher' persona.
        """
        now = datetime.now()
        twenty_days_ago = now - timedelta(days=20)

        # Create 3 stale tasks assigned to "Edward Stasher"
        for i in range(1, 4):
            self.cache.save_work_item(
                600 + i, f"Unattended task {i}", "Task", "Active", "Edward Stasher",
                twenty_days_ago.strftime("%Y-%m-%d %H:%M:%S"),
                {
                    "fields": {
                        "System.Title": f"Unattended task {i}",
                        "System.State": "Active",
                        "System.WorkItemType": "Task",
                        "System.AssignedTo": {"displayName": "Edward Stasher"},
                        "System.ChangedDate": twenty_days_ago.isoformat(),
                    }
                }
            )

        data = compute_team_motivation_data(self.cache, timeframe="all_time")
        stale_radar = data.get("stale_radar", [])

        # Verify Stale Radar contains Edward's items
        stale_ids = [item["id"] for item in stale_radar]
        self.assertIn(601, stale_ids)
        self.assertIn(602, stale_ids)
        self.assertIn(603, stale_ids)

        members = {m["name"]: m for m in data["members"]}
        self.assertIn("Edward Stasher", members)
        edward = members["Edward Stasher"]
        self.assertGreaterEqual(edward["stale_tasks_count"], 3)
        self.assertTrue(edward["is_ignorer"])
        self.assertEqual(edward["time_stats"]["persona"], "💤 Backlog Stasher")

    def test_current_week_activity_aggregation(self):
        """
        Verify that commits, PRs, work items, and branch updates performed during the current week
        are properly aggregated and score positive points under timeframe='current_week'.
        """
        now = datetime.now()

        # Save a fresh commit today in the current sprint
        self.cache.save_commits("repo1", [{
            "commitId": "today_sha_1",
            "author": {"name": "Alice Smith", "email": "alice@company.com", "date": now.isoformat()},
            "committer": {"name": "Alice Smith", "email": "alice@company.com", "date": now.isoformat()},
            "comment": "Current sprint progress",
            "changeCounts": {"Add": 5, "Edit": 10, "Delete": 1}
        }])

        # Save an active task updated today
        self.cache.save_work_item(
            701, "Current sprint active task", "Task", "Closed", "Alice Smith",
            now.strftime("%Y-%m-%d %H:%M:%S"),
            {
                "fields": {
                    "System.Title": "Current sprint active task",
                    "System.State": "Closed",
                    "System.WorkItemType": "Task",
                    "System.AssignedTo": {"displayName": "Alice Smith"},
                    "Microsoft.VSTS.Common.ClosedDate": now.isoformat(),
                    "Microsoft.VSTS.Common.ClosedBy": {"displayName": "Alice Smith"},
                    "System.ChangedDate": now.isoformat(),
                }
            }
        )

        data = compute_team_motivation_data(self.cache, timeframe="current_week")
        self.assertIn("team_summary", data)
        self.assertIn("members", data)

        ts = data["team_summary"]
        self.assertGreaterEqual(ts["commits_count"], 1)
        self.assertGreaterEqual(ts["tasks_completed"], 1)
        self.assertGreaterEqual(ts["active_contributors"], 1)

        members = {m["name"]: m for m in data["members"]}
        self.assertIn("Alice Smith", members)
        self.assertGreaterEqual(members["Alice Smith"]["commits_count"], 1)
        self.assertGreaterEqual(members["Alice Smith"]["tasks_completed"], 1)
        self.assertGreater(members["Alice Smith"]["score"], 0)

    def test_pr_closer_and_reviewer_tracking(self):
        """Tests that PR closers, approvers, and reviewers are all accurately credited."""
        now = datetime.now()
        # Create completed PR merged by Bob, created by Alice, approved by Charlie
        pr_data = [
            {
                "pullRequestId": 801,
                "title": "PR: Engine Optimizations",
                "status": "completed",
                "createdBy": {"displayName": "Alice Smith"},
                "closedBy": {"displayName": "Bob Jones"},
                "creationDate": (now - timedelta(days=2)).isoformat(),
                "closedDate": (now - timedelta(days=1)).isoformat(),
                "reviewers": [
                    {"displayName": "Charlie Brown", "vote": 10},
                    {"displayName": "Diana Prince", "vote": 5},
                ]
            },
            {
                "pullRequestId": 802,
                "title": "PR: Auto-completed bugfix",
                "status": "3",  # enum for completed
                "createdBy": {"displayName": "Bob Jones"},
                "closedBy": "",  # empty closedBy fallback to approver
                "creationDate": (now - timedelta(days=2)).isoformat(),
                "closedDate": (now - timedelta(days=1)).isoformat(),
                "reviewers": [
                    {"displayName": "Diana Prince", "vote": 10},
                ]
            }
        ]
        self.cache.save_pull_requests("repo1", pr_data)

        data = compute_team_motivation_data(self.cache, timeframe="all_time")
        members = {m["name"]: m for m in data["members"]}
        
        # Bob Jones closed PR 801
        self.assertGreaterEqual(members["Bob Jones"]["prs_closed"], 1)
        # Diana Prince approved PR 801 and 802
        self.assertGreaterEqual(members["Diana Prince"]["prs_approved"], 2)
        self.assertGreaterEqual(members["Diana Prince"]["prs_reviewed"], 2)
        # Charlie Brown approved PR 801
        self.assertGreaterEqual(members["Charlie Brown"]["prs_approved"], 1)
        self.assertGreaterEqual(members["Charlie Brown"]["prs_reviewed"], 1)

        # Leaderboards check
        lb = data["leaderboards"]
        self.assertIn("prs_closed", lb)
        self.assertIn("prs_approved", lb)
        self.assertIn("prs_reviewed", lb)
        self.assertGreater(lb["prs_closed"]["total_contributors"], 0)
        self.assertGreater(lb["prs_approved"]["total_contributors"], 0)

    def test_oldest_task_fastest_closer_evidences_and_syntax_bonus(self):
        now = datetime.now()
        work_items = [
            # 1. Oldest open task (assigned to Old Timer, created 120 days ago)
            (
                9001,
                "[Task_9001] Legacy Migration Architecture",
                "Task",
                "Active",
                "Old Timer",
                (now - timedelta(days=5)).strftime("%Y-%m-%d %H:%M:%S"),
                {
                    "fields": {
                        "System.Title": "[Task_9001] Legacy Migration Architecture",
                        "System.State": "Active",
                        "System.WorkItemType": "Task",
                        "System.AssignedTo": {"displayName": "Old Timer"},
                        "System.CreatedDate": (now - timedelta(days=120)).isoformat(),
                        "System.ChangedDate": (now - timedelta(days=5)).isoformat(),
                    },
                    "relations": [
                        {"rel": "ArtifactLink", "url": "vstfs:///Git/Commit/abc12345"},
                        {"rel": "Hyperlink", "url": "https://wiki.internal/docs"},
                    ]
                }
            ),
            # 2. Fast closer with syntax convention [Bug_9002] (created 2h before closed, closed by Speedy Sam)
            (
                9002,
                "[Bug_9002] Fix memory leak in auth module",
                "Bug",
                "Closed",
                "Speedy Sam",
                (now - timedelta(hours=1)).strftime("%Y-%m-%d %H:%M:%S"),
                {
                    "fields": {
                        "System.Title": "[Bug_9002] Fix memory leak in auth module",
                        "System.State": "Closed",
                        "System.WorkItemType": "Bug",
                        "System.AssignedTo": {"displayName": "Speedy Sam"},
                        "Microsoft.VSTS.Common.ClosedBy": {"displayName": "Speedy Sam"},
                        "System.CreatedDate": (now - timedelta(hours=3)).isoformat(),
                        "Microsoft.VSTS.Common.ActivatedDate": (now - timedelta(hours=2)).isoformat(),
                        "Microsoft.VSTS.Common.ClosedDate": (now - timedelta(hours=1)).isoformat(),
                    },
                    "relations": [
                        {"rel": "ArtifactLink", "url": "vstfs:///Git/PullRequestId/777"},
                        {"rel": "ArtifactLink", "url": "vstfs:///Git/Commit/def67890"},
                        {"rel": "Hyperlink", "url": "https://issue.tracker/9002"},
                    ]
                }
            ),
            # 3. Second fast close for Speedy Sam with structured syntax [Feature_9003]
            (
                9003,
                "[Feature_9003] Add dark mode theme switch",
                "Feature",
                "Done",
                "Speedy Sam",
                (now - timedelta(hours=2)).strftime("%Y-%m-%d %H:%M:%S"),
                {
                    "fields": {
                        "System.Title": "[Feature_9003] Add dark mode theme switch",
                        "System.State": "Done",
                        "System.WorkItemType": "Feature",
                        "System.AssignedTo": {"displayName": "Speedy Sam"},
                        "Microsoft.VSTS.Common.ClosedBy": {"displayName": "Speedy Sam"},
                        "System.CreatedDate": (now - timedelta(hours=5)).isoformat(),
                        "Microsoft.VSTS.Common.ClosedDate": (now - timedelta(hours=2)).isoformat(),
                    },
                    "relations": [
                        {"rel": "ArtifactLink", "url": "vstfs:///Git/Commit/feedface"},
                    ]
                }
            ),
            # 4. Third structured syntax close for Speedy Sam [UserStory_9004]
            (
                9004,
                "[UserStory_9004] Real-time activity pulse",
                "User Story",
                "Resolved",
                "Speedy Sam",
                (now - timedelta(hours=2)).strftime("%Y-%m-%d %H:%M:%S"),
                {
                    "fields": {
                        "System.Title": "[UserStory_9004] Real-time activity pulse",
                        "System.State": "Resolved",
                        "System.WorkItemType": "User Story",
                        "System.AssignedTo": {"displayName": "Speedy Sam"},
                        "Microsoft.VSTS.Common.ClosedBy": {"displayName": "Speedy Sam"},
                        "System.CreatedDate": (now - timedelta(days=1)).isoformat(),
                        "Microsoft.VSTS.Common.ClosedDate": (now - timedelta(hours=2)).isoformat(),
                    },
                    "relations": [
                        {"rel": "ArtifactLink", "url": "vstfs:///Git/Commit/12345678"},
                    ]
                }
            )
        ]
        for wid, title, wtype, state, assigned, cdate, raw_obj in work_items:
            self.cache.save_work_item(wid, title, wtype, state, assigned, cdate, raw_obj)

        data = compute_team_motivation_data(self.cache, timeframe="all_time")
        members = {m["name"]: m for m in data["members"]}

        # Check Old Timer metrics (oldest open task >= 120 days, relic_keeper badge)
        old_timer = members.get("Old Timer")
        self.assertIsNotNone(old_timer)
        self.assertGreaterEqual(old_timer["oldest_open_task_days"], 119)
        self.assertIsNotNone(old_timer["oldest_open_task"])
        self.assertEqual(old_timer["oldest_open_task"]["id"], 9001)
        self.assertTrue(any(b["id"] == "relic_keeper" for b in old_timer["badges"]))

        # Check Speedy Sam metrics (fastest closer, syntax master, evidences)
        speedy = members.get("Speedy Sam")
        self.assertIsNotNone(speedy)
        self.assertGreaterEqual(speedy["tasks_fast_closed"], 2)
        self.assertGreaterEqual(speedy["structured_syntax_completed"], 3)
        self.assertGreaterEqual(speedy["task_evidences_count"], 5)
        self.assertGreater(speedy["avg_task_turnaround_hours"], 0)
        self.assertLessEqual(speedy["fastest_task_hours"], 2.0)

        # Check badges awarded
        self.assertTrue(any(b["id"] == "speedy_task_closer" for b in speedy["badges"]))
        self.assertTrue(any(b["id"] == "syntax_master" for b in speedy["badges"]))
        self.assertTrue(any(b["id"] == "evidence_master" for b in speedy["badges"]))

        # Check leaderboards exist and are populated
        lb = data["leaderboards"]
        self.assertIn("oldest_task", lb)
        self.assertIn("fast_closer", lb)
        self.assertIn("evidences", lb)
        self.assertIn("syntax_master", lb)
        self.assertEqual(lb["oldest_task"]["leader"]["name"], "Old Timer")
        self.assertEqual(lb["fast_closer"]["leader"]["name"], "Speedy Sam")


if __name__ == "__main__":
    unittest.main()


