# -*- coding: UTF-8 -*-
"""
Team Motivation, Gamification & Sprint Leaderboard Engine
Computes weekly and sprint-based team activity metrics, gamified badges,
consecutive activity streaks, and competitive leaderboards from cached Azure DevOps data.
Includes commits, feature branches, tags, PRs, work items, and CI build health.
"""

import os
import json
import logging
from datetime import datetime, date, timedelta
import re
import utils
from utils import parse_iso_datetime, parse_sprint_week, get_sprint_date_range

logger = logging.getLogger("team_motivation")

# Badge Definitions with rules and visual metadata
BADGE_DEFINITIONS = {
    "sprint_mvp": {
        "id": "sprint_mvp",
        "name": "Sprint MVP",
        "icon": "👑",
        "color": "#ffd700",
        "bg_color": "#3b2d00",
        "description": "Highest overall composite contribution score in the sprint cycle.",
        "tier": "legendary"
    },
    "pr_dynamo": {
        "id": "pr_dynamo",
        "name": "PR Dynamo",
        "icon": "🚀",
        "color": "#58a6ff",
        "bg_color": "#0d2344",
        "description": "Created 3 or more pull requests in this timeframe.",
        "tier": "gold"
    },
    "the_closer": {
        "id": "the_closer",
        "name": "The Closer",
        "icon": "🏁",
        "color": "#3fb950",
        "bg_color": "#162b20",
        "description": "Successfully merged/closed 3 or more pull requests.",
        "tier": "gold"
    },
    "task_crusher": {
        "id": "task_crusher",
        "name": "Task Crusher",
        "icon": "🔨",
        "color": "#a371f7",
        "bg_color": "#271052",
        "description": "Completed 5 or more work items / tasks.",
        "tier": "gold"
    },
    "bug_slayer": {
        "id": "bug_slayer",
        "name": "Bug Slayer",
        "icon": "🛡️",
        "color": "#f85149",
        "bg_color": "#3d1418",
        "description": "Smashed and resolved 2 or more bugs / defects.",
        "tier": "silver"
    },
    "commit_machine": {
        "id": "commit_machine",
        "name": "Code Machine",
        "icon": "💻",
        "color": "#7ee787",
        "bg_color": "#122a18",
        "description": "Pushed 5 or more code commits to repositories.",
        "tier": "gold"
    },
    "branch_architect": {
        "id": "branch_architect",
        "name": "Feature Pioneer",
        "icon": "🌳",
        "color": "#79c0ff",
        "bg_color": "#16243b",
        "description": "Initiated 2 or more feature / bugfix branches.",
        "tier": "silver"
    },
    "eagle_eye": {
        "id": "eagle_eye",
        "name": "Eagle Eye Reviewer",
        "icon": "🔍",
        "color": "#39c5cf",
        "bg_color": "#0d2d30",
        "description": "Actively reviewed and approved 3 or more peer pull requests.",
        "tier": "gold"
    },
    "speed_demon": {
        "id": "speed_demon",
        "name": "Speed Demon",
        "icon": "⚡",
        "color": "#e3b341",
        "bg_color": "#3d2800",
        "description": "Turned around and merged a PR within 24 hours.",
        "tier": "silver"
    },
    "ci_hero": {
        "id": "ci_hero",
        "name": "CI / Build Champion",
        "icon": "🏗️",
        "color": "#56d364",
        "bg_color": "#142d1b",
        "description": "Triggered 2+ successful CI pipeline builds with zero failures.",
        "tier": "gold"
    },
    "sprint_sniper": {
        "id": "sprint_sniper",
        "name": "Sprint Sniper",
        "icon": "🎯",
        "color": "#2ea043",
        "bg_color": "#162b20",
        "description": "100% on-time delivery: Completed assigned items with zero delay shifts.",
        "tier": "gold"
    },
    "streak_master": {
        "id": "streak_master",
        "name": "On Fire Streak 🔥",
        "icon": "🔥",
        "color": "#ff7b72",
        "bg_color": "#3f1a18",
        "description": "Maintained an active contribution streak across 3+ consecutive weeks.",
        "tier": "legendary"
    },
    "task_architect": {
        "id": "task_architect",
        "name": "Task Architect",
        "icon": "📐",
        "color": "#79c0ff",
        "bg_color": "#16243b",
        "description": "Created and refined 4 or more structured work items.",
        "tier": "bronze"
    },
    "tag_hero": {
        "id": "tag_hero",
        "name": "Release Hero",
        "icon": "🏷️",
        "color": "#d2a8ff",
        "bg_color": "#2c1b4d",
        "description": "Pushed or authored release tags to production.",
        "tier": "silver"
    },
    "night_owl": {
        "id": "night_owl",
        "name": "Night Owl",
        "icon": "🦉",
        "color": "#a371f7",
        "bg_color": "#2d164d",
        "description": "Active in late night hours (9 PM – 5 AM) delivering commits, PRs, or tasks.",
        "tier": "silver"
    },
    "early_bird": {
        "id": "early_bird",
        "name": "Early Bird",
        "icon": "🌅",
        "color": "#f0883e",
        "bg_color": "#3e1e0d",
        "description": "Up before sunrise delivering contributions early in the morning (5 AM – 9 AM).",
        "tier": "bronze"
    },
    "weekend_warrior": {
        "id": "weekend_warrior",
        "name": "The Week-ender",
        "icon": "⚡",
        "color": "#d29922",
        "bg_color": "#382900",
        "description": "Unstoppable dedication: coded, reviewed, or shipped work over the weekend (Sat/Sun).",
        "tier": "gold"
    },
    "zen_balancer": {
        "id": "zen_balancer",
        "name": "Zen Work-Life Balancer",
        "icon": "🧘",
        "color": "#3fb950",
        "bg_color": "#102a18",
        "description": "Master of focus: delivers 85%+ work strictly within daytime hours with 0 weekend overtime.",
        "tier": "silver"
    },
    "friday_hero": {
        "id": "friday_hero",
        "name": "Friday Finisher",
        "icon": "🚀",
        "color": "#58a6ff",
        "bg_color": "#0d2344",
        "description": "Shipped and closed PRs or tasks on Friday afternoon before sprint close.",
        "tier": "bronze"
    }
}


def _clean_user_name(user_obj_or_str):
    """Normalizes user identity into a readable display name string."""
    if not user_obj_or_str:
        return ""
    if isinstance(user_obj_or_str, dict):
        return (
            user_obj_or_str.get("displayName")
            or user_obj_or_str.get("uniqueName")
            or user_obj_or_str.get("name")
            or ""
        ).strip()
    return str(user_obj_or_str).strip()


def _is_valid_member(name):
    """Filters out empty or system placeholder names."""
    if not name:
        return False
    low = name.lower()
    if low in ("unassigned", "undefined", "none", "unknown", "system", "[deleted]", "github-actions[bot]", "tfs build service"):
        return False
    return True


def compute_team_motivation_data(cache_db, timeframe="last_week", custom_sprint="", work_items=None, pull_requests=None):
    """
    Computes team activity, leaderboards, streaks, badges, and team pulse stats including commits, branches, tags, and CI builds.

    Args:
        cache_db (AzureDevOpsCache): Active SQLite cache database.
        timeframe (str): 'last_week', 'current_week', 'last_4_weeks', 'all_time', or 'sprint'.
        custom_sprint (str): Sprint identifier (e.g. 'week-2639') if timeframe is 'sprint' or override.
        work_items (list): Optional pre-fetched work items list.
        pull_requests (list): Optional pre-fetched pull requests list.

    Returns:
        dict: Full motivational analysis payload ready for QML UI consumption.
    """
    if not cache_db:
        return {}

    now = datetime.now()
    cur_year, cur_week_num, _ = now.isocalendar()
    cur_sprint_name = f"week-{str(cur_year)[-2:]}{cur_week_num:02d}"

    # Determine date range & sprint labels
    last_week_dt = now - timedelta(days=7)
    last_year, last_week_num, _ = last_week_dt.isocalendar()
    last_sprint_name = f"week-{str(last_year)[-2:]}{last_week_num:02d}"

    # Compute bounds for timeframes
    cur_start_dt, cur_end_dt, cur_start_str, cur_end_str = get_sprint_date_range(cur_year, cur_week_num)
    last_start_dt, last_end_dt, last_start_str, last_end_str = get_sprint_date_range(last_year, last_week_num)

    target_sprint = ""
    range_label = ""
    filter_start_str = ""
    filter_end_str = ""

    if timeframe == "last_week":
        target_sprint = last_sprint_name
        range_label = f"Last Week ({last_sprint_name} • {last_start_str} to {last_end_str})"
        filter_start_str = last_start_str
        filter_end_str = cur_start_str  # up to current week start
    elif timeframe == "current_week":
        target_sprint = cur_sprint_name
        range_label = f"Current Sprint ({cur_sprint_name} • {cur_start_str} to {cur_end_str})"
        filter_start_str = cur_start_str
        filter_end_str = (cur_end_dt + timedelta(days=1)).strftime("%Y-%m-%d")
    elif timeframe == "last_4_weeks":
        four_wks_ago = now - timedelta(days=28)
        filter_start_str = four_wks_ago.strftime("%Y-%m-%d")
        filter_end_str = (now + timedelta(days=1)).strftime("%Y-%m-%d")
        range_label = f"Past 4 Weeks ({filter_start_str} to {now.strftime('%Y-%m-%d')})"
    elif timeframe == "all_time":
        range_label = "All-Time Hall of Fame"
        filter_start_str = "1970-01-01"
        filter_end_str = "2099-12-31"
    elif timeframe == "sprint" or custom_sprint:
        clean_s = custom_sprint.strip() if custom_sprint else last_sprint_name
        target_sprint = clean_s
        sy, sw, _ = parse_sprint_week(clean_s)
        if sy and sw:
            s_dt, e_dt, s_str, e_str = get_sprint_date_range(sy, sw)
            filter_start_str = s_str
            filter_end_str = (e_dt + timedelta(days=1)).strftime("%Y-%m-%d")
            range_label = f"Sprint {clean_s} ({s_str} to {e_str})"
        else:
            filter_start_str = "1970-01-01"
            filter_end_str = "2099-12-31"
            range_label = f"Sprint {clean_s}"
    else:
        # Default fallback to last week
        target_sprint = last_sprint_name
        range_label = f"Last Week ({last_sprint_name} • {last_start_str} to {last_end_str})"
        filter_start_str = last_start_str
        filter_end_str = cur_start_str

    # Fetch raw datasets if not provided
    all_wis = work_items if work_items is not None else cache_db.get_all_work_items()
    all_prs = []
    if pull_requests is not None:
        all_prs = pull_requests
    else:
        try:
            with cache_db._connection() as conn:
                rows = conn.execute("SELECT raw_json FROM pull_requests").fetchall()
                for r in rows:
                    if r["raw_json"]:
                        try:
                            all_prs.append(json.loads(r["raw_json"]))
                        except Exception:
                            pass
        except Exception as e:
            logger.debug(f"Error reading PRs from cache: {e}")

    # Fetch tags
    all_tags = []
    try:
        with cache_db._connection() as conn:
            t_rows = conn.execute("""
                SELECT t.name as tag_name, t.commit_date, t.committer_name, COALESCE(r.name, t.repo_id) as repo_name, t.is_stable, t.is_unstable
                FROM tags t
                LEFT JOIN repositories r ON t.repo_id = r.id
                ORDER BY t.commit_date DESC
            """).fetchall()
            for tr in t_rows:
                all_tags.append({
                    "tag_name": tr["tag_name"],
                    "commit_date": tr["commit_date"] or "",
                    "committer": tr["committer_name"] or "",
                    "repo_name": tr["repo_name"] or "",
                    "is_stable": tr["is_stable"],
                    "is_unstable": tr["is_unstable"]
                })
    except Exception as e:
        logger.debug(f"Error reading tags: {e}")

    # Fetch branches
    all_branches = []
    try:
        with cache_db._connection() as conn:
            b_rows = conn.execute("""
                SELECT b.name as branch_name, b.commit_date, b.committer_name, COALESCE(r.name, b.repo_id) as repo_name, b.raw_json
                FROM branches b
                LEFT JOIN repositories r ON b.repo_id = r.id
                ORDER BY b.commit_date DESC
            """).fetchall()
            for br in b_rows:
                all_branches.append({
                    "branch_name": br["branch_name"],
                    "commit_date": br["commit_date"] or "",
                    "committer": br["committer_name"] or "",
                    "repo_name": br["repo_name"] or "",
                    "raw_json": br["raw_json"]
                })
    except Exception as e:
        logger.debug(f"Error reading branches: {e}")

    # Fetch builds
    all_builds = []
    try:
        with cache_db._connection() as conn:
            build_rows = conn.execute("""
                SELECT id, pipeline_name, status, result, finish_time, start_time, requested_by, source_branch
                FROM builds
                ORDER BY finish_time DESC
            """).fetchall()
            for b in build_rows:
                all_builds.append({
                    "id": b["id"],
                    "pipeline_name": b["pipeline_name"] or "",
                    "status": (b["status"] or "").lower(),
                    "result": (b["result"] or "").lower(),
                    "finish_time": b["finish_time"] or b["start_time"] or "",
                    "requested_by": _clean_user_name(b["requested_by"]),
                    "source_branch": b["source_branch"] or ""
                })
    except Exception as e:
        logger.debug(f"Error reading builds: {e}")

    # Fetch iteration shifts to measure delay/sprint predictability
    shifts_by_user = {}
    try:
        shifts = cache_db.get_iteration_shifts(limit=2000)
        for s in shifts:
            user = _clean_user_name(s.get("assigned_to"))
            if _is_valid_member(user):
                shifts_by_user.setdefault(user, []).append(s)
    except Exception as e:
        logger.debug(f"Error reading shifts: {e}")

    # Team-level time analytics accumulator
    team_time_agg = {
        "total_samples": 0,
        "daytime_count": 0,
        "early_bird_count": 0,
        "evening_count": 0,
        "night_count": 0,
        "weekend_count": 0,
        "friday_pm_count": 0,
        "hourly_distribution": [0] * 24,
        "daily_distribution": [0] * 7,  # Mon(0)..Sun(6)
    }

    # Initialize Per-Member Aggregation dictionary
    members = {}

    def _get_or_create_member(name):
        cname = _clean_user_name(name)
        if not _is_valid_member(cname):
            return None
        if cname not in members:
            # Generate initials
            parts = cname.split()
            initials = (parts[0][0] + (parts[-1][0] if len(parts) > 1 else "")).upper() if parts else "??"
            members[cname] = {
                "name": cname,
                "initials": initials,
                "prs_created": 0,
                "prs_closed": 0,
                "prs_fast_merged": 0,
                "prs_reviewed": 0,
                "tasks_created": 0,
                "tasks_completed": 0,
                "bugs_resolved": 0,
                "stories_completed": 0,
                "commits_count": 0,
                "branches_started": 0,
                "branches_closed": 0,
                "tags_pushed": 0,
                "builds_total": 0,
                "builds_succeeded": 0,
                "builds_failed": 0,
                "build_success_rate": 100.0,
                "total_shifts": 0,
                "total_delay_weeks": 0,
                "avg_pr_hours": 0.0,
                "night_activities": 0,
                "early_bird_activities": 0,
                "weekend_activities": 0,
                "daytime_activities": 0,
                "evening_activities": 0,
                "friday_afternoon_activities": 0,
                "time_stats": {
                    "total_actions": 0,
                    "daytime_count": 0,
                    "early_bird_count": 0,
                    "evening_count": 0,
                    "night_count": 0,
                    "weekend_count": 0,
                    "friday_pm_count": 0,
                    "daytime_pct": 0.0,
                    "night_pct": 0.0,
                    "weekend_pct": 0.0,
                    "early_bird_pct": 0.0,
                    "hourly_distribution": [0] * 24,
                    "daily_distribution": [0] * 7,
                    "peak_hour": 14,
                    "peak_hour_label": "14:00",
                    "peak_day": "Wednesday",
                    "persona": "☀️ Daytime Core",
                },
                "_pr_durations": [],
                "recent_achievements": [],
                "badges": [],
                "badges_count": 0,
                "score": 0,
                "weekly_activity_history": {},  # sprint_week -> activity count
                "current_streak_weeks": 0,
                "best_streak_weeks": 0,
            }
        return members[cname]

    def _track_activity_time(member_dict, ts_str):
        """Categorizes when work happened (daytime vs night-owl vs weekend vs early-bird)."""
        if not member_dict or not ts_str:
            return
        dt = parse_iso_datetime(ts_str) if isinstance(ts_str, str) else ts_str
        if not dt or not isinstance(dt, datetime):
            return

        hour = dt.hour
        weekday = dt.weekday()  # 0=Mon .. 6=Sun

        ts = member_dict["time_stats"]
        ts["total_actions"] += 1
        ts["hourly_distribution"][hour] += 1
        ts["daily_distribution"][weekday] += 1

        team_time_agg["total_samples"] += 1
        team_time_agg["hourly_distribution"][hour] += 1
        team_time_agg["daily_distribution"][weekday] += 1

        if weekday in (5, 6):
            ts["weekend_count"] += 1
            member_dict["weekend_activities"] += 1
            team_time_agg["weekend_count"] += 1
            if hour >= 21 or hour < 5:
                ts["night_count"] += 1
                member_dict["night_activities"] += 1
                team_time_agg["night_count"] += 1
        else:
            if hour >= 21 or hour < 5:
                ts["night_count"] += 1
                member_dict["night_activities"] += 1
                team_time_agg["night_count"] += 1
            elif 5 <= hour < 9:
                ts["early_bird_count"] += 1
                member_dict["early_bird_activities"] += 1
                team_time_agg["early_bird_count"] += 1
            elif 9 <= hour < 18:
                ts["daytime_count"] += 1
                member_dict["daytime_activities"] += 1
                team_time_agg["daytime_count"] += 1
            else:
                ts["evening_count"] += 1
                member_dict["evening_activities"] += 1
                team_time_agg["evening_count"] += 1

            if weekday == 4 and hour >= 14:
                ts["friday_pm_count"] += 1
                member_dict["friday_afternoon_activities"] += 1
                team_time_agg["friday_pm_count"] += 1

    # 1. Process Work Items
    for wi in all_wis:
        if wi.get("deleted") or wi.get("is_deleted"):
            continue

        raw = {}
        if wi.get("raw_json"):
            try:
                raw = json.loads(wi["raw_json"]) if isinstance(wi["raw_json"], str) else wi["raw_json"]
            except Exception:
                pass
        fields = raw.get("fields", {}) if isinstance(raw, dict) else {}

        assigned_name = _clean_user_name(wi.get("assigned_to") or fields.get("System.AssignedTo"))
        created_by = _clean_user_name(wi.get("CreatedBy") or fields.get("System.CreatedBy"))
        changed_date_raw = wi.get("changed_date") or fields.get("System.ChangedDate") or ""
        created_date_raw = wi.get("CreatedDate") or fields.get("System.CreatedDate") or ""
        changed_date_str = changed_date_raw[:10]
        created_date_str = created_date_raw[:10]
        state = str(wi.get("state") or fields.get("System.State") or "").capitalize()
        wi_type = str(wi.get("type") or fields.get("System.WorkItemType") or "").lower()
        iter_path = str(wi.get("iteration_path") or fields.get("System.IterationPath") or "")

        # Extract sprint week from item
        _, _, item_sprint = parse_sprint_week(iter_path)
        if not item_sprint and changed_date_str:
            dt = parse_iso_datetime(changed_date_str)
            if dt:
                y, w, _ = dt.isocalendar()
                item_sprint = f"week-{str(y)[-2:]}{w:02d}"

        # Track historical activity per user across weeks for streak calculation
        if _is_valid_member(assigned_name) and item_sprint:
            m = _get_or_create_member(assigned_name)
            if m:
                m["weekly_activity_history"][item_sprint] = m["weekly_activity_history"].get(item_sprint, 0) + 1

        # Check if item matches the selected timeframe
        in_timeframe = False
        if target_sprint and item_sprint == target_sprint:
            in_timeframe = True
        elif filter_start_str and filter_end_str:
            if (changed_date_str and filter_start_str <= changed_date_str < filter_end_str) or \
               (created_date_str and filter_start_str <= created_date_str < filter_end_str):
                in_timeframe = True

        if not in_timeframe:
            continue

        # Completed items
        if state in ("Closed", "Resolved", "Done", "Completed"):
            if _is_valid_member(assigned_name):
                m = _get_or_create_member(assigned_name)
                if m:
                    m["tasks_completed"] += 1
                    _track_activity_time(m, changed_date_raw)
                    if "bug" in wi_type or "defect" in wi_type or "problem" in wi_type:
                        m["bugs_resolved"] += 1
                    elif "story" in wi_type or "requirement" in wi_type or "pbi" in wi_type:
                        m["stories_completed"] += 1

        # Created tasks
        if created_date_str and filter_start_str <= created_date_str < filter_end_str:
            if _is_valid_member(created_by):
                m = _get_or_create_member(created_by)
                if m:
                    m["tasks_created"] += 1
                    _track_activity_time(m, created_date_raw)

    # 2. Process Pull Requests & Feature Branches
    for pr in all_prs:
        cb = _clean_user_name(pr.get("createdBy"))
        clb = _clean_user_name(pr.get("closedBy"))
        c_date_raw = pr.get("creationDate") or pr.get("creationDateStr") or ""
        cl_date_raw = pr.get("closedDate") or pr.get("closedDateStr") or ""
        c_date_str = c_date_raw[:10]
        cl_date_str = cl_date_raw[:10]
        status = str(pr.get("status") or pr.get("statusStr") or "").lower()
        source_ref = str(pr.get("sourceRefName") or pr.get("source_branch") or "")

        # Track weekly activity for streaks
        if cl_date_str:
            dt = parse_iso_datetime(cl_date_str)
            if dt:
                y, w, _ = dt.isocalendar()
                pr_sprint = f"week-{str(y)[-2:]}{w:02d}"
                if _is_valid_member(cb):
                    m = _get_or_create_member(cb)
                    if m:
                        m["weekly_activity_history"][pr_sprint] = m["weekly_activity_history"].get(pr_sprint, 0) + 1
                if _is_valid_member(clb) and clb != cb:
                    m = _get_or_create_member(clb)
                    if m:
                        m["weekly_activity_history"][pr_sprint] = m["weekly_activity_history"].get(pr_sprint, 0) + 1

        # Check PR creation timeframe (Feature branch started)
        if c_date_str and filter_start_str <= c_date_str < filter_end_str:
            if _is_valid_member(cb):
                m = _get_or_create_member(cb)
                if m:
                    m["prs_created"] += 1
                    m["branches_started"] += 1
                    m["commits_count"] += 1  # PR branch initiation commit
                    _track_activity_time(m, c_date_raw)

        # Check PR closed timeframe (Feature branch closed/merged)
        if status in ("completed", "closed", "3") and cl_date_str and filter_start_str <= cl_date_str < filter_end_str:
            closer = clb or cb
            if _is_valid_member(closer):
                m = _get_or_create_member(closer)
                if m:
                    m["prs_closed"] += 1
                    m["branches_closed"] += 1
                    m["commits_count"] += 1  # Merge commit
                    _track_activity_time(m, cl_date_raw)

            # Check PR turnaround speed
            if pr.get("creationDate") and pr.get("closedDate"):
                try:
                    dt_c = parse_iso_datetime(pr["creationDate"])
                    dt_cl = parse_iso_datetime(pr["closedDate"])
                    if dt_c and dt_cl and dt_cl >= dt_c:
                        diff_hours = (dt_cl - dt_c).total_seconds() / 3600.0
                        if diff_hours <= 24.0:
                            if _is_valid_member(cb):
                                m_cb = _get_or_create_member(cb)
                                if m_cb:
                                    m_cb["prs_fast_merged"] += 1
                        if _is_valid_member(closer):
                            m_cl = _get_or_create_member(closer)
                            if m_cl:
                                m_cl["_pr_durations"].append(diff_hours)
                except Exception:
                    pass

        # Code Reviewers
        if filter_start_str <= (cl_date_str or c_date_str) < filter_end_str:
            for rev in pr.get("reviewers", []):
                rev_name = _clean_user_name(rev)
                vote = rev.get("vote", 0) if isinstance(rev, dict) else 0
                if _is_valid_member(rev_name) and rev_name != cb and vote > 0:
                    m = _get_or_create_member(rev_name)
                    if m:
                        m["prs_reviewed"] += 1
                        _track_activity_time(m, cl_date_raw or c_date_raw)

    # 3. Process Tags
    for tag in all_tags:
        t_date_raw = tag.get("commit_date", "")
        t_date = t_date_raw[:10]
        committer = _clean_user_name(tag.get("committer"))
        if t_date and filter_start_str <= t_date < filter_end_str:
            if _is_valid_member(committer):
                m = _get_or_create_member(committer)
                if m:
                    m["tags_pushed"] += 1
                    m["commits_count"] += 1
                    _track_activity_time(m, t_date_raw)

    # 4. Process Direct Branch Commits
    for br in all_branches:
        b_date_raw = br.get("commit_date", "")
        b_date = b_date_raw[:10]
        committer = _clean_user_name(br.get("committer"))
        if b_date and filter_start_str <= b_date < filter_end_str:
            if _is_valid_member(committer):
                m = _get_or_create_member(committer)
                if m:
                    m["commits_count"] += 1
                    _track_activity_time(m, b_date_raw)

    # 5. Process CI Builds & Pipeline Executions
    for b in all_builds:
        build_date_raw = b.get("finish_time") or b.get("start_time") or ""
        b_date = build_date_raw[:10]
        requester = b.get("requested_by")
        if b_date and filter_start_str <= b_date < filter_end_str:
            is_succ = b["result"] == "succeeded"
            is_fail = b["result"] in ("failed", "partiallysucceeded")
            if _is_valid_member(requester):
                m = _get_or_create_member(requester)
                if m:
                    m["builds_total"] += 1
                    _track_activity_time(m, build_date_raw)
                    if is_succ:
                        m["builds_succeeded"] += 1
                    elif is_fail:
                        m["builds_failed"] += 1

    # 6. Process Shifts & Predictability
    for user, shift_list in shifts_by_user.items():
        if user in members:
            # Count shifts in this timeframe
            relevant_shifts = [
                s for s in shift_list
                if (s.get("recorded_at") or "")[:10] >= filter_start_str and (s.get("recorded_at") or "")[:10] < filter_end_str
            ]
            members[user]["total_shifts"] = len(relevant_shifts)
            members[user]["total_delay_weeks"] = sum((s.get("delta_weeks") or 0) for s in relevant_shifts if (s.get("delta_weeks") or 0) > 0)

    # 7. Compute Streaks, Build Rates, Badges & Composite Scores
    # Prepare chronological list of past 12 sprint weeks
    recent_sprint_weeks = []
    base_dt = now
    for i in range(12):
        w_dt = base_dt - timedelta(days=i * 7)
        y, w, _ = w_dt.isocalendar()
        s_code = f"week-{str(y)[-2:]}{w:02d}"
        if s_code not in recent_sprint_weeks:
            recent_sprint_weeks.append(s_code)

    member_list = list(members.values())

    for m in member_list:
        # Calculate Average PR Turnaround
        if m["_pr_durations"]:
            m["avg_pr_hours"] = round(sum(m["_pr_durations"]) / len(m["_pr_durations"]), 1)

        # Calculate Build Success Rate
        if m["builds_total"] > 0:
            m["build_success_rate"] = round((m["builds_succeeded"] / m["builds_total"]) * 100.0, 1)

        # Calculate Weekly Streak
        cur_streak = 0
        for s_code in recent_sprint_weeks:
            if m["weekly_activity_history"].get(s_code, 0) > 0:
                cur_streak += 1
            else:
                break
        m["current_streak_weeks"] = cur_streak

        # Compute Time Profile & Persona
        tot_act = m["time_stats"]["total_actions"]
        if tot_act > 0:
            m["time_stats"]["daytime_pct"] = round((m["time_stats"]["daytime_count"] / tot_act) * 100.0, 1)
            m["time_stats"]["night_pct"] = round((m["time_stats"]["night_count"] / tot_act) * 100.0, 1)
            m["time_stats"]["weekend_pct"] = round((m["time_stats"]["weekend_count"] / tot_act) * 100.0, 1)
            m["time_stats"]["early_bird_pct"] = round((m["time_stats"]["early_bird_count"] / tot_act) * 100.0, 1)

            # Peak hour
            peak_h = max(range(24), key=lambda h: m["time_stats"]["hourly_distribution"][h])
            m["time_stats"]["peak_hour"] = peak_h
            m["time_stats"]["peak_hour_label"] = f"{peak_h:02d}:00"

            # Peak day
            day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            peak_d = max(range(7), key=lambda d: m["time_stats"]["daily_distribution"][d])
            m["time_stats"]["peak_day"] = day_names[peak_d]

            # Persona determination
            if m["night_activities"] >= 3 and m["night_activities"] >= m["daytime_activities"] * 0.4:
                m["time_stats"]["persona"] = "🦉 Night Owl"
            elif m["weekend_activities"] >= 2 and m["weekend_activities"] >= tot_act * 0.25:
                m["time_stats"]["persona"] = "⚡ Weekend Warrior"
            elif m["early_bird_activities"] >= 3 and m["early_bird_activities"] >= m["daytime_activities"] * 0.4:
                m["time_stats"]["persona"] = "🌅 Early Bird"
            elif tot_act >= 5 and (m["daytime_activities"] / tot_act) >= 0.85 and m["weekend_activities"] == 0 and m["night_activities"] == 0:
                m["time_stats"]["persona"] = "🧘 Zen Balanced"
            elif m["friday_afternoon_activities"] >= 2:
                m["time_stats"]["persona"] = "🚀 Friday Finisher"
            else:
                m["time_stats"]["persona"] = "☀️ Daytime Core"

        # Compute Badges
        badges = []
        if m["prs_created"] >= 3:
            badges.append(BADGE_DEFINITIONS["pr_dynamo"])
        if m["prs_closed"] >= 3:
            badges.append(BADGE_DEFINITIONS["the_closer"])
        if m["tasks_completed"] >= 5:
            badges.append(BADGE_DEFINITIONS["task_crusher"])
        if m["bugs_resolved"] >= 2:
            badges.append(BADGE_DEFINITIONS["bug_slayer"])
        if m["commits_count"] >= 5:
            badges.append(BADGE_DEFINITIONS["commit_machine"])
        if m["branches_started"] >= 2:
            badges.append(BADGE_DEFINITIONS["branch_architect"])
        if m["prs_reviewed"] >= 3:
            badges.append(BADGE_DEFINITIONS["eagle_eye"])
        if m["prs_fast_merged"] >= 1:
            badges.append(BADGE_DEFINITIONS["speed_demon"])
        if m["builds_succeeded"] >= 2 and m["builds_failed"] == 0:
            badges.append(BADGE_DEFINITIONS["ci_hero"])
        if m["tasks_completed"] >= 3 and m["total_delay_weeks"] == 0:
            badges.append(BADGE_DEFINITIONS["sprint_sniper"])
        if m["current_streak_weeks"] >= 3:
            badges.append(BADGE_DEFINITIONS["streak_master"])
        if m["tasks_created"] >= 4:
            badges.append(BADGE_DEFINITIONS["task_architect"])
        if m["tags_pushed"] >= 1:
            badges.append(BADGE_DEFINITIONS["tag_hero"])
        if m["night_activities"] >= 3:
            badges.append(BADGE_DEFINITIONS["night_owl"])
        if m["early_bird_activities"] >= 3:
            badges.append(BADGE_DEFINITIONS["early_bird"])
        if m["weekend_activities"] >= 2:
            badges.append(BADGE_DEFINITIONS["weekend_warrior"])
        if tot_act >= 5 and (m["daytime_activities"] / tot_act) >= 0.85 and m["weekend_activities"] == 0 and m["night_activities"] == 0:
            badges.append(BADGE_DEFINITIONS["zen_balancer"])
        if m["friday_afternoon_activities"] >= 2:
            badges.append(BADGE_DEFINITIONS["friday_hero"])

        m["badges"] = badges
        m["badges_count"] = len(badges)

        # Composite Motivation Score Formula:
        # PRs closed * 15 + PRs created * 10 + Commits * 3 + Branches closed * 5 + Tasks completed * 8
        # + Bugs resolved * 10 + PRs reviewed * 6 + Tags * 12 + Successful builds * 4
        # + Badges * 5 + Streak * 4 - Delays * 3 - Failed builds * 2
        score = (
            m["prs_closed"] * 15
            + m["prs_created"] * 10
            + m["commits_count"] * 3
            + m["branches_closed"] * 5
            + m["tasks_completed"] * 8
            + m["bugs_resolved"] * 10
            + m["prs_reviewed"] * 6
            + m["tags_pushed"] * 12
            + m["builds_succeeded"] * 4
            + len(badges) * 5
            + m["current_streak_weeks"] * 4
            - (m["total_delay_weeks"] * 3)
            - (m["builds_failed"] * 2)
        )
        m["score"] = max(0, score)

    # Award Sprint MVP badge to the top scorer
    sorted_by_score = sorted(member_list, key=lambda x: x["score"], reverse=True)
    if sorted_by_score and sorted_by_score[0]["score"] > 0:
        mvp = sorted_by_score[0]
        # Add MVP badge if not already present
        if not any(b["id"] == "sprint_mvp" for b in mvp["badges"]):
            mvp["badges"].insert(0, BADGE_DEFINITIONS["sprint_mvp"])
            mvp["badges_count"] = len(mvp["badges"])

    # 8. Generate Category Leaderboards (Top performers per category)
    def _make_leaderboard(key, title, icon, unit="items", reverse_sort=True):
        filtered = [m for m in member_list if m.get(key, 0) > 0]
        sorted_m = sorted(filtered, key=lambda x: x.get(key, 0), reverse=reverse_sort)
        entries = []
        for rank, item in enumerate(sorted_m[:10], start=1):
            entries.append({
                "rank": rank,
                "name": item["name"],
                "initials": item["initials"],
                "value": item[key],
                "unit": unit,
                "score": item["score"],
                "badges_count": item["badges_count"],
                "streak": item["current_streak_weeks"],
                "is_top_3": rank <= 3,
                "medal": "🥇" if rank == 1 else ("🥈" if rank == 2 else ("🥉" if rank == 3 else f"#{rank}"))
            })
        return {
            "category_id": key,
            "title": title,
            "icon": icon,
            "leader": entries[0] if entries else None,
            "entries": entries,
            "total_contributors": len(entries)
        }

    leaderboard_prs_closed = _make_leaderboard("prs_closed", "The Closer (PRs Merged)", "🏁", "PRs")
    leaderboard_prs_created = _make_leaderboard("prs_created", "PR Pioneer (PRs Started)", "🔀", "PRs")
    leaderboard_commits = _make_leaderboard("commits_count", "Code Committer (Commits)", "💻", "commits")
    leaderboard_branches_started = _make_leaderboard("branches_started", "Branch Pioneer (Branches Started)", "🌳", "branches")
    leaderboard_branches_closed = _make_leaderboard("branches_closed", "Branch Closer (Branches Merged)", "🌿", "branches")
    leaderboard_tasks_completed = _make_leaderboard("tasks_completed", "Task Crusher (Tasks Done)", "🔨", "tasks")
    leaderboard_bugs_resolved = _make_leaderboard("bugs_resolved", "Bug Hunter (Defects Fixed)", "🛡️", "bugs")
    leaderboard_prs_reviewed = _make_leaderboard("prs_reviewed", "Review Rockstar (Code Reviews)", "🔍", "reviews")
    leaderboard_tags = _make_leaderboard("tags_pushed", "Release Titan (Tags Pushed)", "🏷️", "tags")
    leaderboard_builds = _make_leaderboard("builds_succeeded", "Build Master (Successful Builds)", "🏗️", "builds")
    leaderboard_streaks = _make_leaderboard("current_streak_weeks", "Streak Champion (Weekly Streak)", "🔥", "wks")
    leaderboard_night_owls = _make_leaderboard("night_activities", "Night Owls (9PM – 5AM)", "🦉", "actions")
    leaderboard_early_birds = _make_leaderboard("early_bird_activities", "Early Birds (5AM – 9AM)", "🌅", "actions")
    leaderboard_weekend_warriors = _make_leaderboard("weekend_activities", "The Week-enders (Sat/Sun)", "⚡", "actions")
    leaderboard_daytime = _make_leaderboard("daytime_activities", "Daytime Champions (9AM – 6PM)", "☀️", "actions")
    leaderboard_overall = _make_leaderboard("score", "Sprint MVP (Overall Hall of Fame)", "👑", "pts")

    # Team Overview Summary
    team_total_prs_created = sum(m["prs_created"] for m in member_list)
    team_total_prs_closed = sum(m["prs_closed"] for m in member_list)
    team_total_commits = sum(m["commits_count"] for m in member_list)
    team_total_branches_started = sum(m["branches_started"] for m in member_list)
    team_total_branches_closed = sum(m["branches_closed"] for m in member_list)
    team_total_tasks_completed = sum(m["tasks_completed"] for m in member_list)
    team_total_bugs_resolved = sum(m["bugs_resolved"] for m in member_list)
    team_total_reviews = sum(m["prs_reviewed"] for m in member_list)
    team_total_tags = sum(m["tags_pushed"] for m in member_list)
    team_total_builds = sum(m["builds_total"] for m in member_list)
    team_total_builds_succeeded = sum(m["builds_succeeded"] for m in member_list)
    team_total_builds_failed = sum(m["builds_failed"] for m in member_list)
    team_build_success_rate = round((team_total_builds_succeeded / team_total_builds * 100.0), 1) if team_total_builds > 0 else 100.0
    active_contributors_count = sum(1 for m in member_list if m["score"] > 0)

    # Compute Team Time Analytics
    team_tot_samples = team_time_agg["total_samples"]
    day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    peak_h_team = max(range(24), key=lambda h: team_time_agg["hourly_distribution"][h]) if team_tot_samples > 0 else 14
    peak_d_idx = max(range(7), key=lambda d: team_time_agg["daily_distribution"][d]) if team_tot_samples > 0 else 2
    peak_d_team = day_names[peak_d_idx]

    team_time_analytics = {
        "total_samples": team_tot_samples,
        "daytime_count": team_time_agg["daytime_count"],
        "daytime_pct": round((team_time_agg["daytime_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "night_count": team_time_agg["night_count"],
        "night_pct": round((team_time_agg["night_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "weekend_count": team_time_agg["weekend_count"],
        "weekend_pct": round((team_time_agg["weekend_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "early_bird_count": team_time_agg["early_bird_count"],
        "early_bird_pct": round((team_time_agg["early_bird_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "evening_count": team_time_agg["evening_count"],
        "evening_pct": round((team_time_agg["evening_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "friday_pm_count": team_time_agg["friday_pm_count"],
        "peak_hour": peak_h_team,
        "peak_hour_label": f"{peak_h_team:02d}:00",
        "peak_day": peak_d_team,
        "hourly_distribution": team_time_agg["hourly_distribution"],
        "daily_distribution": [
            {"day": "Mon", "short": "M", "count": team_time_agg["daily_distribution"][0]},
            {"day": "Tue", "short": "T", "count": team_time_agg["daily_distribution"][1]},
            {"day": "Wed", "short": "W", "count": team_time_agg["daily_distribution"][2]},
            {"day": "Thu", "short": "T", "count": team_time_agg["daily_distribution"][3]},
            {"day": "Fri", "short": "F", "count": team_time_agg["daily_distribution"][4]},
            {"day": "Sat", "short": "S", "count": team_time_agg["daily_distribution"][5]},
            {"day": "Sun", "short": "S", "count": team_time_agg["daily_distribution"][6]},
        ]
    }

    # Dynamic Motivational Quotes / Pulse
    motivational_quotes = [
        "🔥 Incredible momentum! Every commit, merged PR, and green build drives the team forward.",
        "⚡ Velocity Surge: High code review participation and clean CI builds this cycle!",
        "🎯 Focus & Quality: Smashing bugs, delivering on commitments, and hitting milestones.",
        "🚀 High Performance: Smooth branch integration and automated builds keep us shipping fast.",
        "🛡️ Zero Regressions: Thorough peer reviews and solid test builds maintain top stability."
    ]
    pulse_index = (cur_week_num + len(member_list)) % len(motivational_quotes)
    motivational_pulse = motivational_quotes[pulse_index]

    # Clean member list for JSON serialization (remove internal helpers)
    for m in member_list:
        m.pop("_pr_durations", None)
        # Format recent highlights
        highlights = []
        if m["prs_closed"] > 0:
            highlights.append(f"Merged {m['prs_closed']} PR{'s' if m['prs_closed'] > 1 else ''}")
        if m["commits_count"] > 0:
            highlights.append(f"{m['commits_count']} commits")
        if m["branches_started"] > 0:
            highlights.append(f"{m['branches_started']} branch{'es' if m['branches_started'] > 1 else ''}")
        if m["tasks_completed"] > 0:
            highlights.append(f"Completed {m['tasks_completed']} item{'s' if m['tasks_completed'] > 1 else ''}")
        if m["bugs_resolved"] > 0:
            highlights.append(f"Fixed {m['bugs_resolved']} bug{'s' if m['bugs_resolved'] > 1 else ''}")
        if m["builds_succeeded"] > 0:
            highlights.append(f"{m['builds_succeeded']} green builds")
        if m["tags_pushed"] > 0:
            highlights.append(f"{m['tags_pushed']} tags")
        if m["prs_reviewed"] > 0:
            highlights.append(f"Reviewed {m['prs_reviewed']} PR{'s' if m['prs_reviewed'] > 1 else ''}")
        if m["night_activities"] >= 3:
            highlights.append(f"🦉 Night Owl ({m['night_activities']} late acts)")
        if m["weekend_activities"] >= 2:
            highlights.append(f"⚡ Weekend Warrior ({m['weekend_activities']} wknd acts)")
        if m["current_streak_weeks"] >= 2:
            highlights.append(f"🔥 {m['current_streak_weeks']}-week streak")
        m["recent_achievements"] = highlights

    # Top 3 Podium (from overall score)
    podium = []
    sorted_all = sorted(member_list, key=lambda x: x["score"], reverse=True)
    if len(sorted_all) >= 1 and sorted_all[0]["score"] > 0:
        podium.append({"rank": 1, "medal": "🥇", "title": "1st Place", "member": sorted_all[0]})
    if len(sorted_all) >= 2 and sorted_all[1]["score"] > 0:
        podium.append({"rank": 2, "medal": "🥈", "title": "2nd Place", "member": sorted_all[1]})
    if len(sorted_all) >= 3 and sorted_all[2]["score"] > 0:
        podium.append({"rank": 3, "medal": "🥉", "title": "3rd Place", "member": sorted_all[2]})

    return {
        "timeframe": timeframe,
        "custom_sprint": custom_sprint,
        "target_sprint": target_sprint,
        "range_label": range_label,
        "start_date": filter_start_str,
        "end_date": filter_end_str,
        "motivational_pulse": motivational_pulse,
        "team_summary": {
            "prs_created": team_total_prs_created,
            "prs_closed": team_total_prs_closed,
            "commits_count": team_total_commits,
            "branches_started": team_total_branches_started,
            "branches_closed": team_total_branches_closed,
            "tasks_completed": team_total_tasks_completed,
            "bugs_resolved": team_total_bugs_resolved,
            "reviews_completed": team_total_reviews,
            "tags_pushed": team_total_tags,
            "builds_total": team_total_builds,
            "builds_succeeded": team_total_builds_succeeded,
            "builds_failed": team_total_builds_failed,
            "build_success_rate": team_build_success_rate,
            "active_contributors": active_contributors_count,
            "total_points": sum(m["score"] for m in member_list),
            "time_analytics": team_time_analytics,
        },
        "podium": podium,
        "members": sorted_all,
        "leaderboards": {
            "overall": leaderboard_overall,
            "prs_closed": leaderboard_prs_closed,
            "prs_created": leaderboard_prs_created,
            "commits": leaderboard_commits,
            "branches_started": leaderboard_branches_started,
            "branches_closed": leaderboard_branches_closed,
            "tasks_completed": leaderboard_tasks_completed,
            "bugs_resolved": leaderboard_bugs_resolved,
            "prs_reviewed": leaderboard_prs_reviewed,
            "tags": leaderboard_tags,
            "builds": leaderboard_builds,
            "streaks": leaderboard_streaks,
            "night_owls": leaderboard_night_owls,
            "early_birds": leaderboard_early_birds,
            "weekend_warriors": leaderboard_weekend_warriors,
            "daytime": leaderboard_daytime,
        },
        "all_badges": list(BADGE_DEFINITIONS.values()),
    }


def generate_motivation_markdown_summary(data):
    """
    Generates a stylish markdown summary of the team achievements for Slack/Teams sprint retro sharing.
    """
    if not data:
        return "No motivational data available."

    ts = data.get("team_summary", {})
    ta = ts.get("time_analytics", {})
    rl = data.get("range_label", "Sprint Period")
    pulse = data.get("motivational_pulse", "")
    podium = data.get("podium", [])
    members = data.get("members", [])

    lines = [
        f"# 🏆 Team Sprint Motivation & Hall of Fame",
        f"**Period:** {rl}",
        f"",
        f"> {pulse}",
        f"",
        f"## 📊 Team Sprint Pulse",
        f"- **🔀 Pull Requests Started / Merged:** {ts.get('prs_created', 0)} / {ts.get('prs_closed', 0)}",
        f"- **💻 Code Commits:** {ts.get('commits_count', 0)}",
        f"- **🌳 Feature Branches (Started / Merged):** {ts.get('branches_started', 0)} / {ts.get('branches_closed', 0)}",
        f"- **🏷️ Release Tags:** {ts.get('tags_pushed', 0)}",
        f"- **🏗️ CI Pipeline Builds:** {ts.get('builds_total', 0)} ({ts.get('builds_succeeded', 0)} succeeded, {ts.get('builds_failed', 0)} failed • **{ts.get('build_success_rate', 100.0)}% success**)",
        f"- **🔨 Work Items Completed:** {ts.get('tasks_completed', 0)} ({ts.get('bugs_resolved', 0)} bugs fixed)",
        f"- **🔍 Peer Code Reviews:** {ts.get('reviews_completed', 0)}",
        f"- **⏰ Work Rhythm:** {ta.get('daytime_pct', 0)}% Daytime (9-18h) • {ta.get('night_pct', 0)}% Night Owl (21-5h) • {ta.get('weekend_pct', 0)}% Weekend",
        f"- **👥 Active Contributors:** {ts.get('active_contributors', 0)}",
        f"",
    ]

    if podium:
        lines.append("## 🥇 Sprint Podium")
        for p in podium:
            m = p["member"]
            med = p["medal"]
            lines.append(f"- **{med} {p['title']}:** {m['name']} ({m.get('time_stats', {}).get('persona', '')}) — **{m['score']} pts** ({', '.join(m.get('recent_achievements', []))})")
        lines.append("")

    lines.append("## 🌟 Leaderboard & Badges")
    lines.append("| Rank | Contributor | Score | Commits | Branches (S/C) | PRs (M/C) | Tasks | Bugs | Builds (✓/✗) | Rhythm | Streak | Badges |")
    lines.append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |")

    for i, m in enumerate(members[:15], start=1):
        badge_icons = "".join(b.get("icon", "") for b in m.get("badges", []))
        streak_str = f"🔥 {m['current_streak_weeks']}w" if m['current_streak_weeks'] > 0 else "-"
        build_str = f"{m.get('builds_succeeded', 0)}/{m.get('builds_failed', 0)}" if m.get('builds_total', 0) > 0 else "—"
        br_str = f"{m.get('branches_started', 0)}/{m.get('branches_closed', 0)}"
        persona = m.get("time_stats", {}).get("persona", "☀️")
        lines.append(
            f"| #{i} | **{m['name']}** | **{m['score']}** | {m.get('commits_count', 0)} | {br_str} | {m['prs_closed']}/{m['prs_created']} | {m['tasks_completed']} | {m['bugs_resolved']} | {build_str} | {persona} | {streak_str} | {badge_icons} |"
        )

    lines.append("")
    lines.append("---")
    lines.append("*Generated by DevOps Manager Motivation & Sprint Gamification Engine*")

    return "\n".join(lines)
