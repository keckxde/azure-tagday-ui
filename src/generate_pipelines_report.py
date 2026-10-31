# -*- coding: UTF-8 -*-
"""
Classic Jenkins-Style Build Pipelines Health & Culprit Report Generator.

Analyzes cached Azure DevOps / TFS build pipelines and build runs,
evaluating each pipeline using classic Jenkins concepts:
- Status Ball (S): Success (🟢), Unstable (🟡), Failed (🔴), Running (🔄), Aborted/Not Built (⚪)
- Weather Health Icon (W): Sunny (☀️), Partly Cloudy (🌤️), Cloudy (☁️), Raining (🌧️), Stormy (⛈️)
  calculated from the stability of the last 5 completed builds (0% - 100%).
- Last Success, Last Failure, Last Duration, Consecutive Failures ("Broken since").
- Automated Culprit & Root Cause Hints ("Wer / Was könnte der Verursacher sein?"):
  Cross-references build trigger metadata, build timeline task failures, Git commits,
  and Pull Requests since the last green build to identify suspects ("Wer") and technical causes ("Was").
"""

import os
import re
import sys
import csv
import json
import logging
from datetime import datetime

# Add parent directories to sys.path
py_dir = os.path.dirname(os.path.abspath(__file__))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from jinja2 import Template
from azure import AzureDevOpsCache
import utils
from utils import load_status_icons, parse_iso_datetime

logger = logging.getLogger(__name__)


JENKINS_BALLS_DEFAULT = {
    "success": "🟢",
    "unstable": "🟡",
    "failed": "🔴",
    "running": "🔄",
    "aborted": "⚪",
    "not_built": "⚪",
}

JENKINS_WEATHER_DEFAULT = {
    "sunny": "☀️",
    "partly_cloudy": "🌤️",
    "cloudy": "☁️",
    "raining": "🌧️",
    "stormy": "⛈️",
    "unknown": "❔",
}

TRIGGER_REASON_LABELS = {
    "manual": "Manuell ausgelöst (Manual)",
    "individualci": "CI Push (Direct Commit)",
    "batchedci": "CI Push (Batched Commits)",
    "schedule": "Zeitplan / Nightly (Scheduled)",
    "scheduleforced": "Zeitplan (Forced Schedule)",
    "pullrequest": "Pull Request Validation / Merge",
    "buildcompletion": "Upstream Build-Pipeline (Build Completion)",
    "resourcetrigger": "Resource Trigger",
    "usercreated": "Benutzer-Start (User Created)",
    "validateshelveset": "Shelveset Validation",
    "checkinshelveset": "Gated Check-in",
    "triggered": "Automatischer Trigger",
}


def _clean_branch_name(branch_str):
    """Strips refs/heads/ or refs/ from branch names for readable display."""
    if not branch_str:
        return ""
    s = str(branch_str).strip()
    if s.startswith("refs/heads/"):
        return s[len("refs/heads/"):]
    if s.startswith("refs/tags/"):
        return "tag:" + s[len("refs/tags/"):]
    m_pr = re.match(r"^refs/pull/(\d+)/(merge|head)$", s)
    if m_pr:
        return f"PR !{m_pr.group(1)}"
    return s


def _extract_pr_id_from_branch(branch_str):
    """Extracts PR ID if sourceBranch is refs/pull/<id>/merge or similar."""
    if not branch_str:
        return None
    m = re.search(r"refs/pull/(\d+)", str(branch_str))
    if m:
        try:
            return int(m.group(1))
        except (ValueError, TypeError):
            return None
    return None


def _format_timestamp(ts_str):
    """Formats an ISO timestamp string to YYYY-MM-DD HH:MM."""
    if not ts_str:
        return ""
    dt = parse_iso_datetime(ts_str)
    if dt:
        return dt.strftime("%Y-%m-%d %H:%M")
    s = str(ts_str).replace("T", " ").replace("Z", "").strip()
    return s[:16]


def _compute_duration(start_str, finish_str):
    """Calculates build duration in seconds and human-readable format (e.g. '3m 42s')."""
    if not start_str or not finish_str:
        return 0, "-"
    dt_start = parse_iso_datetime(start_str)
    dt_finish = parse_iso_datetime(finish_str)
    if not dt_start or not dt_finish:
        return 0, "-"
    diff_sec = int(max(0, (dt_finish - dt_start).total_seconds()))
    if diff_sec == 0:
        return 0, "< 1s"
    hours, rem = divmod(diff_sec, 3600)
    minutes, seconds = divmod(rem, 60)
    if hours > 0:
        return diff_sec, f"{hours}h {minutes}m {seconds}s"
    if minutes > 0:
        return diff_sec, f"{minutes}m {seconds}s"
    return diff_sec, f"{seconds}s"


def classify_jenkins_status(status_str, result_str, balls_map=None):
    """
    Maps Azure DevOps build status & result to classic Jenkins ball status:
    - 'success' (🟢)
    - 'unstable' (🟡)
    - 'failed' (🔴)
    - 'running' (🔄)
    - 'aborted' (⚪)
    - 'not_built' (⚪)
    """
    balls = balls_map or JENKINS_BALLS_DEFAULT
    st = str(status_str or "").strip().lower()
    res = str(result_str or "").strip().lower()

    if st in ("inprogress", "notstarted", "postponed"):
        return "running", balls.get("running", "🔄"), "RUNNING"
    if res == "succeeded":
        return "success", balls.get("success", "🟢"), "SUCCESS"
    if res == "partiallysucceeded":
        return "unstable", balls.get("unstable", "🟡"), "UNSTABLE"
    if res == "failed":
        return "failed", balls.get("failed", "🔴"), "FAILED"
    if res == "canceled" or st == "cancelling":
        return "aborted", balls.get("aborted", "⚪"), "ABORTED"
    if not st and not res:
        return "not_built", balls.get("not_built", "⚪"), "NOT BUILT"
    if st == "completed" and not res:
        return "aborted", balls.get("aborted", "⚪"), "NONE"
    return "not_built", balls.get("not_built", "⚪"), (result_str or status_str or "UNKNOWN").upper()


def compute_jenkins_weather(completed_builds, weather_map=None):
    """
    Computes classic Jenkins Weather health score (0-100%) and icon over the last 5 completed builds.
    In Jenkins:
      - 81-100% (0 of 5 failed): ☀️ Sunny
      - 61-80%  (1 of 5 failed): 🌤️ Partly Cloudy
      - 41-60%  (2 of 5 failed): ☁️ Cloudy
      - 21-40%  (3-4 of 5 failed): 🌧️ Raining
      - 0-20%   (5 of 5 failed): ⛈️ Stormy
    """
    wmap = weather_map or JENKINS_WEATHER_DEFAULT
    recent = [
        b for b in completed_builds
        if str(b.get("result") or "").strip().lower() in ("succeeded", "partiallysucceeded", "failed")
        or str(b.get("status_key") or "").strip().lower() in ("success", "unstable", "failed")
    ][:5]

    if not recent:
        return 100, "unknown", wmap.get("unknown", "❔"), "Noch keine abgeschlossenen Builds"

    total = len(recent)
    points = 0.0
    failed_cnt = 0
    unstable_cnt = 0
    for b in recent:
        res = str(b.get("result") or "").strip().lower()
        skey = str(b.get("status_key") or "").strip().lower()
        if res == "succeeded" or skey == "success":
            points += 1.0
        elif res == "partiallysucceeded" or skey == "unstable":
            points += 0.5
            unstable_cnt += 1
        elif res == "failed" or skey == "failed":
            failed_cnt += 1

    score = int(round((points / total) * 100))
    problem_cnt = failed_cnt + unstable_cnt

    if score >= 81:
        key = "sunny"
    elif score >= 61:
        key = "partly_cloudy"
    elif score >= 41:
        key = "cloudy"
    elif score >= 21:
        key = "raining"
    else:
        key = "stormy"

    icon = wmap.get(key, "☀️")
    if problem_cnt == 0:
        label = f"Stabil: Alle letzten {total} Builds erfolgreich (100%)"
    elif failed_cnt > 0 and unstable_cnt > 0:
        label = f"{failed_cnt} fehlgeschlagen, {unstable_cnt} instabil in den letzten {total} Builds ({score}%)"
    elif failed_cnt > 0:
        label = f"{failed_cnt} von {total} letzten Builds fehlgeschlagen ({score}%)"
    else:
        label = f"{unstable_cnt} von {total} letzten Builds instabil ({score}%)"

    return score, key, icon, label


def _extract_build_details(build_row, commits_by_sha, commits_by_prefix, prs_by_id, prs_by_commit):
    """
    Enriches a single build record with commit, PR, trigger reason, and timeline failure details.
    """
    raw = {}
    raw_json_str = build_row.get("raw_json")
    if raw_json_str:
        try:
            raw = json.loads(raw_json_str) if isinstance(raw_json_str, str) else raw_json_str
        except Exception:
            raw = {}
    if not isinstance(raw, dict):
        raw = {}

    source_branch = build_row.get("source_branch") or raw.get("sourceBranch") or ""
    branch_short = _clean_branch_name(source_branch)
    source_version = (build_row.get("source_version") or raw.get("sourceVersion") or "").strip()
    commit_short = source_version[:7] if source_version else ""

    # Requested by / for
    requested_by = (build_row.get("requested_by") or "").strip()
    if not requested_by:
        req_for = raw.get("requestedFor") or raw.get("requestedBy") or {}
        if isinstance(req_for, dict):
            requested_by = req_for.get("displayName") or req_for.get("name") or req_for.get("uniqueName") or ""
        elif isinstance(req_for, str):
            requested_by = req_for

    # Trigger reason & triggerInfo
    reason_raw = str(raw.get("reason") or "").strip()
    reason_label = TRIGGER_REASON_LABELS.get(reason_raw.lower(), reason_raw or "CI / Build")
    trigger_info = raw.get("triggerInfo") if isinstance(raw.get("triggerInfo"), dict) else {}

    # Match Commit
    matched_commit = None
    if source_version:
        matched_commit = commits_by_sha.get(source_version.lower())
        if not matched_commit and len(source_version) >= 7:
            matched_commit = commits_by_prefix.get(source_version[:7].lower())

    commit_author = ""
    commit_comment = ""
    if matched_commit:
        commit_author = matched_commit.get("author_name") or matched_commit.get("committer_name") or ""
        commit_comment = (matched_commit.get("comment") or "").strip().splitlines()[0] if matched_commit.get("comment") else ""
    else:
        # Check triggerInfo fallback
        commit_comment = (trigger_info.get("ci.message") or trigger_info.get("pr.title") or "").strip()
        commit_author = (trigger_info.get("pr.sender.name") or "").strip()

    # Match Pull Request
    matched_pr = None
    pr_id_from_branch = _extract_pr_id_from_branch(source_branch)
    if not pr_id_from_branch and trigger_info.get("pr.number"):
        try:
            pr_id_from_branch = int(trigger_info.get("pr.number"))
        except (ValueError, TypeError):
            pass

    if pr_id_from_branch and pr_id_from_branch in prs_by_id:
        matched_pr = prs_by_id[pr_id_from_branch]
    elif source_version and source_version.lower() in prs_by_commit:
        matched_pr = prs_by_commit[source_version.lower()]
    elif commit_short and commit_short.lower() in prs_by_commit:
        matched_pr = prs_by_commit[commit_short.lower()]

    pr_label = ""
    pr_title = ""
    pr_author = ""
    pr_merger = ""
    if matched_pr:
        pr_id_val = matched_pr.get("id")
        pr_label = f"!{pr_id_val}"
        pr_title = matched_pr.get("title") or ""
        pr_author = matched_pr.get("created_by") or ""
        pr_merger = matched_pr.get("closed_by") or ""
    elif pr_id_from_branch:
        pr_label = f"!{pr_id_from_branch}"
        pr_title = trigger_info.get("pr.title") or ""

    # Extract failed tasks / timeline issues / validationResults
    failed_steps = []
    error_messages = []

    raw_failed_tasks = raw.get("failed_tasks") or []
    if isinstance(raw_failed_tasks, list):
        for ft in raw_failed_tasks:
            if isinstance(ft, dict):
                t_name = ft.get("name") or "Step"
                t_msg = ft.get("message") or ""
                failed_steps.append(t_name)
                if t_msg and t_msg not in error_messages:
                    error_messages.append(t_msg)
            elif isinstance(ft, str):
                failed_steps.append(ft)

    raw_timeline_issues = raw.get("timeline_issues") or []
    if isinstance(raw_timeline_issues, list):
        for iss in raw_timeline_issues:
            if iss and str(iss) not in error_messages:
                error_messages.append(str(iss))

    val_results = raw.get("validationResults") or []
    if isinstance(val_results, list):
        for vr in val_results:
            if isinstance(vr, dict) and vr.get("message"):
                v_msg = str(vr.get("message")).strip()
                if v_msg and v_msg not in error_messages:
                    error_messages.append(v_msg)

    # Determine "Wer" (Who) for this single build
    who_parts = []
    if commit_author:
        who_parts.append(f"{commit_author} (Commit)")
    if pr_author and pr_author != commit_author:
        who_parts.append(f"{pr_author} (PR {pr_label})")
    if pr_merger and pr_merger not in (commit_author, pr_author):
        who_parts.append(f"{pr_merger} (Merge)")
    if requested_by and requested_by not in (commit_author, pr_author, pr_merger):
        who_parts.append(f"{requested_by} (Trigger)")

    who_summary = ", ".join(who_parts) if who_parts else (requested_by or commit_author or "System / Unbekannt")

    # Determine "Was" (What) for this single build
    what_parts = []
    if failed_steps:
        steps_str = ", ".join(failed_steps[:3])
        what_parts.append(f"Step: {steps_str}")
    if error_messages:
        first_err = error_messages[0]
        if len(first_err) > 90:
            first_err = first_err[:87] + "..."
        what_parts.append(f"Fehler: {first_err}")
    if pr_label:
        pr_desc = f"PR {pr_label}: {pr_title[:50]}" if pr_title else f"PR {pr_label}"
        what_parts.append(pr_desc)
    elif commit_short:
        c_desc = f"Commit {commit_short}: {commit_comment[:50]}" if commit_comment else f"Commit {commit_short}"
        what_parts.append(c_desc)
    if not what_parts:
        what_parts.append(f"{reason_label} auf Branch '{branch_short or 'default'}'")

    what_summary = " · ".join(what_parts)

    start_time = build_row.get("start_time") or raw.get("startTime") or build_row.get("queue_time") or raw.get("queueTime") or ""
    finish_time = build_row.get("finish_time") or raw.get("finishTime") or ""
    dur_sec, dur_str = _compute_duration(start_time, finish_time)
    finish_str = _format_timestamp(finish_time or start_time)

    return {
        "build_id": build_row.get("build_id") or build_row.get("id"),
        "build_number": str(build_row.get("build_number") or build_row.get("buildNumber") or build_row.get("build_id") or ""),
        "pipeline_id": build_row.get("pipeline_id"),
        "pipeline_name": build_row.get("pipeline_name") or "Unknown Pipeline",
        "repo_id": build_row.get("repo_id"),
        "repo_name": build_row.get("repo_name") or "Unknown Repo",
        "status": build_row.get("status") or "",
        "result": build_row.get("result") or "",
        "source_branch": source_branch,
        "branch_short": branch_short,
        "source_version": source_version,
        "commit_short": commit_short,
        "requested_by": requested_by,
        "reason_raw": reason_raw,
        "reason_label": reason_label,
        "commit_author": commit_author,
        "commit_comment": commit_comment,
        "pr_id": matched_pr.get("id") if matched_pr else pr_id_from_branch,
        "pr_label": pr_label,
        "pr_title": pr_title,
        "pr_author": pr_author,
        "pr_merger": pr_merger,
        "failed_steps": failed_steps,
        "error_messages": error_messages,
        "who_summary": who_summary,
        "what_summary": what_summary,
        "start_time": start_time,
        "finish_time": finish_time,
        "finish_time_str": finish_str,
        "duration_seconds": dur_sec,
        "duration_str": dur_str,
        "url": build_row.get("url") or raw.get("url") or "",
    }


def analyze_pipelines_health(cache_db, project_id=None, config_path=None):
    """
    Loads all pipelines, builds, commits, and pull requests from SQLite and computes
    a complete Jenkins-style Build Pipeline Monitor & Culprit Analysis structure.
    """
    status_icons_cfg = load_status_icons(custom_path=config_path)
    balls_map = status_icons_cfg.get("jenkins_balls") or JENKINS_BALLS_DEFAULT
    weather_map = status_icons_cfg.get("jenkins_weather") or JENKINS_WEATHER_DEFAULT

    with cache_db._connection() as conn:
        # 1. Load Pipelines
        if project_id:
            pipe_rows = conn.execute(
                "SELECT id, project_id, name, folder, revision, url, raw_json FROM pipelines WHERE project_id = ? ORDER BY name ASC",
                (project_id,)
            ).fetchall()
        else:
            pipe_rows = conn.execute(
                "SELECT id, project_id, name, folder, revision, url, raw_json FROM pipelines ORDER BY name ASC"
            ).fetchall()

        # 2. Load Builds (ordered newest first)
        build_query = """
        SELECT
            b.id AS build_id,
            b.project_id,
            b.repo_id,
            b.pipeline_id,
            COALESCE(p.name, NULLIF(b.pipeline_name, ''), 'Unknown Pipeline') AS pipeline_name,
            b.build_number,
            b.status,
            b.result,
            b.queue_time,
            b.start_time,
            b.finish_time,
            b.source_branch,
            b.source_version,
            b.requested_by,
            b.url,
            b.raw_json,
            COALESCE(r.name, 'Unknown Repo') AS repo_name,
            COALESCE(pr.name, b.project_id, 'DefaultProject') AS project_name
        FROM builds b
        LEFT JOIN pipelines p ON b.pipeline_id = p.id
        LEFT JOIN repositories r ON b.repo_id = r.id
        LEFT JOIN projects pr ON b.project_id = pr.id
        WHERE 1=1
        """
        b_params = []
        if project_id:
            build_query += " AND b.project_id = ?"
            b_params.append(project_id)
        build_query += " ORDER BY COALESCE(b.finish_time, b.start_time, b.queue_time) DESC, b.id DESC"
        build_rows = [dict(r) for r in conn.execute(build_query, b_params).fetchall()]

        # 3. Load Commits for fast SHA lookup and repo commit history
        commit_rows = [dict(r) for r in conn.execute(
            "SELECT repo_id, commit_id, author_name, author_email, author_date, committer_name, committer_date, comment FROM commits"
        ).fetchall()]

        # 4. Load Pull Requests for PR correlation
        pr_rows = [dict(r) for r in conn.execute(
            "SELECT id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, raw_json FROM pull_requests"
        ).fetchall()]

    commits_by_sha = {}
    commits_by_prefix = {}
    commits_by_repo = {}
    for c in commit_rows:
        cid = (c.get("commit_id") or "").strip().lower()
        if cid:
            commits_by_sha[cid] = c
            if len(cid) >= 7:
                commits_by_prefix[cid[:7]] = c
        rid = c.get("repo_id")
        if rid:
            commits_by_repo.setdefault(rid, []).append(c)

    prs_by_id = {}
    prs_by_commit = {}
    for pr in pr_rows:
        pid = pr.get("id")
        if pid is not None:
            prs_by_id[int(pid)] = pr
        if pr.get("raw_json"):
            try:
                praw = json.loads(pr["raw_json"]) if isinstance(pr["raw_json"], str) else pr["raw_json"]
                if isinstance(praw, dict):
                    for ck in ("lastMergeCommit", "lastMergeSourceCommit"):
                        c_obj = praw.get(ck)
                        if isinstance(c_obj, dict) and c_obj.get("commitId"):
                            c_sha = str(c_obj["commitId"]).strip().lower()
                            prs_by_commit[c_sha] = pr
                            if len(c_sha) >= 7:
                                prs_by_commit[c_sha[:7]] = pr
            except Exception:
                pass

    # Group builds by pipeline key (pipeline_id if available, else pipeline_name)
    pipelines_map = {}
    pipeline_name_to_key = {}

    for p_row in pipe_rows:
        p_dict = dict(p_row)
        pid = p_dict.get("id")
        pname = (p_dict.get("name") or f"Pipeline #{pid}").strip()
        pkey = f"id:{pid}" if pid is not None else f"name:{pname.lower()}"
        pipelines_map[pkey] = {
            "pipeline_id": pid,
            "name": pname,
            "folder": p_dict.get("folder") or "\\",
            "url": p_dict.get("url") or "",
            "builds": []
        }
        pipeline_name_to_key[pname.lower()] = pkey

    enriched_builds = []
    for brow in build_rows:
        eb = _extract_build_details(brow, commits_by_sha, commits_by_prefix, prs_by_id, prs_by_commit)
        status_key, status_ball, status_label = classify_jenkins_status(eb["status"], eb["result"], balls_map)
        eb["status_key"] = status_key
        eb["status_ball"] = status_ball
        eb["status_label"] = status_label
        enriched_builds.append(eb)

        pid = eb.get("pipeline_id")
        pname = (eb.get("pipeline_name") or "Unknown Pipeline").strip()
        pkey = f"id:{pid}" if pid is not None and f"id:{pid}" in pipelines_map else pipeline_name_to_key.get(pname.lower())
        if not pkey:
            pkey = f"id:{pid}" if pid is not None else f"name:{pname.lower()}"
            pipelines_map[pkey] = {
                "pipeline_id": pid,
                "name": pname,
                "folder": "\\",
                "url": "",
                "builds": []
            }
            pipeline_name_to_key[pname.lower()] = pkey
        pipelines_map[pkey]["builds"].append(eb)

    # Evaluate each pipeline using Jenkins metrics
    pipeline_entries = []
    for pkey, pinfo in pipelines_map.items():
        p_builds = pinfo["builds"]
        pname = pinfo["name"]
        pid = pinfo["pipeline_id"]

        if not p_builds:
            # Defined pipeline with 0 cached builds
            _, ball_nb, lbl_nb = classify_jenkins_status("", "", balls_map)
            w_score, w_key, w_icon, w_label = compute_jenkins_weather([], weather_map)
            pipeline_entries.append({
                "pipeline_id": pid or 0,
                "name": pname,
                "folder": pinfo.get("folder") or "\\",
                "repo_name": "-",
                "last_branch": "-",
                "status_key": "not_built",
                "status_ball": ball_nb,
                "status_label": lbl_nb,
                "weather_score": w_score,
                "weather_key": w_key,
                "weather_icon": w_icon,
                "weather_label": w_label,
                "last_5_runs": [],
                "last_5_balls": "⚪",
                "total_runs": 0,
                "failed_runs_count": 0,
                "unstable_runs_count": 0,
                "success_runs_count": 0,
                "last_build_number": "-",
                "last_build_date": "-",
                "last_success_build": "",
                "last_success_date": "",
                "last_success_display": "Nie (Never)",
                "last_failure_build": "",
                "last_failure_date": "",
                "last_failure_display": "Nie (Never)",
                "last_duration_seconds": 0,
                "last_duration_str": "-",
                "consecutive_failures": 0,
                "broken_since_build": "",
                "broken_since_date": "",
                "has_problem": False,
                "culprit_who": "-",
                "suspects": [],
                "suspects_str": "",
                "culprit_what": "Keine Build-Läufe vorhanden",
                "trigger_reason": "-",
                "failed_steps": [],
                "error_messages": [],
                "last_commit_sha": "",
                "last_commit_comment": "",
                "last_pr_label": "",
                "hint_text": "Pipeline wurde noch nicht ausgeführt.",
            })
            continue

        latest = p_builds[0]
        completed_runs = [b for b in p_builds if b["status_key"] in ("success", "unstable", "failed", "aborted")]
        latest_completed = completed_runs[0] if completed_runs else latest

        # Status ball is based on latest build (or if running, show running; for problem detection also check latest_completed)
        status_key = latest["status_key"]
        status_ball = latest["status_ball"]
        status_label = latest["status_label"]

        w_score, w_key, w_icon, w_label = compute_jenkins_weather(completed_runs, weather_map)

        last_5 = p_builds[:5]
        last_5_balls = " ".join(b["status_ball"] for b in last_5)

        # Last Success & Last Failure
        success_runs = [b for b in p_builds if b["status_key"] == "success"]
        failure_runs = [b for b in p_builds if b["status_key"] in ("failed", "unstable")]

        last_success = success_runs[0] if success_runs else None
        last_failure = failure_runs[0] if failure_runs else None

        last_success_display = (
            f"#{(last_success['build_number'])} ({last_success['finish_time_str']})"
            if last_success else "Nie (Never)"
        )
        last_failure_display = (
            f"#{(last_failure['build_number'])} ({last_failure['finish_time_str']})"
            if last_failure else "Nie (Never)"
        )

        # Consecutive failures ("Broken Since")
        consecutive_failures = 0
        streak_builds = []
        for b in completed_runs:
            if b["status_key"] in ("failed", "unstable"):
                consecutive_failures += 1
                streak_builds.append(b)
            elif b["status_key"] == "success":
                break

        broken_since = streak_builds[-1] if streak_builds else (last_failure if last_failure else None)
        broken_since_build = broken_since["build_number"] if broken_since else ""
        broken_since_date = broken_since["finish_time_str"] if broken_since else ""

        has_problem = (
            status_key in ("failed", "unstable")
            or latest_completed["status_key"] in ("failed", "unstable")
            or consecutive_failures > 0
            or (w_score < 80 and len(failure_runs) > 0)
        )

        # Culprit & Root Cause Analysis ("Wer / Was könnte der Verursacher sein?")
        culprit_who = "-"
        suspects = []
        suspects_names = []
        culprit_what = "-"
        hint_text = "✅ Pipeline läuft fehlerfrei."
        failed_steps = []
        error_messages = []
        trigger_reason = latest.get("reason_label") or "-"

        target_problem_builds = streak_builds if streak_builds else (failure_runs[:2] if has_problem else [])
        if target_problem_builds:
            primary_bad_build = target_problem_builds[0]
            first_bad_build = target_problem_builds[-1]
            trigger_reason = primary_bad_build.get("reason_label") or "-"

            def _add_suspect(name, role, detail=""):
                clean_n = (name or "").strip()
                if not clean_n or clean_n.lower() in ("unknown", "none", "system"):
                    return
                if clean_n not in suspects_names:
                    suspects_names.append(clean_n)
                    suspects.append({"name": clean_n, "role": role, "detail": detail})

            # Collect suspects from all builds in the failure streak (oldest break first, then recent)
            for sb in reversed(target_problem_builds):
                if sb.get("commit_author"):
                    _add_suspect(
                        sb["commit_author"],
                        "Commit-Autor",
                        f"Commit {sb['commit_short']} in Build #{sb['build_number']}"
                    )
                if sb.get("pr_author"):
                    _add_suspect(
                        sb["pr_author"],
                        f"PR-Autor ({sb['pr_label']})",
                        sb.get("pr_title") or ""
                    )
                if sb.get("pr_merger"):
                    _add_suspect(
                        sb["pr_merger"],
                        f"PR-Merger ({sb['pr_label']})",
                        sb.get("pr_title") or ""
                    )
                if sb.get("requested_by"):
                    _add_suspect(
                        sb["requested_by"],
                        "Build-Auslöser (Requested For)",
                        f"Build #{sb['build_number']} ({sb['reason_label']})"
                    )

            # Also check repo commits between last_success and primary_bad_build if no commit author was matched yet
            repo_id_val = primary_bad_build.get("repo_id")
            if repo_id_val and repo_id_val in commits_by_repo and last_success:
                dt_last_ok = parse_iso_datetime(last_success.get("finish_time") or last_success.get("start_time"))
                dt_bad = parse_iso_datetime(primary_bad_build.get("finish_time") or primary_bad_build.get("start_time"))
                if dt_last_ok and dt_bad:
                    for rc in commits_by_repo[repo_id_val]:
                        dt_c = parse_iso_datetime(rc.get("committer_date") or rc.get("author_date"))
                        if dt_c and dt_last_ok <= dt_c <= dt_bad:
                            c_auth = rc.get("author_name") or rc.get("committer_name")
                            c_sha = (rc.get("commit_id") or "")[:7]
                            _add_suspect(c_auth, "Commit seit letztem grünem Build", f"Commit {c_sha}")

            if suspects:
                primary_suspect = suspects[0]
                culprit_who = f"{primary_suspect['name']} ({primary_suspect['role']})"
            else:
                culprit_who = primary_bad_build.get("requested_by") or "Unbekannt (Kein Nutzer hinterlegt)"

            # Aggregate failed steps & error messages across problem builds
            for sb in target_problem_builds:
                for stp in sb.get("failed_steps") or []:
                    if stp not in failed_steps:
                        failed_steps.append(stp)
                for em in sb.get("error_messages") or []:
                    if em not in error_messages:
                        error_messages.append(em)

            # Build "Was" (What) description
            what_pieces = []
            if failed_steps:
                what_pieces.append(f"Fehlgeschlagener Step: {', '.join(failed_steps[:3])}")
            if error_messages:
                msg_short = error_messages[0][:100] + ("..." if len(error_messages[0]) > 100 else "")
                what_pieces.append(f"Fehlermeldung: \"{msg_short}\"")
            if first_bad_build.get("pr_label"):
                pr_txt = f"PR {first_bad_build['pr_label']}"
                if first_bad_build.get("pr_title"):
                    pr_txt += f" ({first_bad_build['pr_title'][:50]})"
                what_pieces.append(pr_txt)
            if first_bad_build.get("commit_short"):
                cm_txt = f"Commit {first_bad_build['commit_short']}"
                if first_bad_build.get("commit_comment"):
                    cm_txt += f" (\"{first_bad_build['commit_comment'][:50]}\")"
                what_pieces.append(cm_txt)
            if not what_pieces:
                what_pieces.append(
                    f"{primary_bad_build['reason_label']} auf Branch '{primary_bad_build['branch_short'] or 'default'}'"
                )

            culprit_what = " · ".join(what_pieces)

            # Construct human-friendly German hint ("Einfacher Hinweis")
            who_clean = suspects[0]["name"] if suspects else culprit_who
            if len(suspects) > 1:
                others = ", ".join(s["name"] for s in suspects[1:3])
                who_hint = f"{who_clean} (weitere Beteiligte seit letztem Erfolg: {others})"
            else:
                who_hint = who_clean

            if consecutive_failures > 1:
                streak_txt = f"Seit Build #{broken_since_build} ({consecutive_failures}x in Folge fehlgeschlagen)"
            elif consecutive_failures == 1:
                streak_txt = f"Build #{primary_bad_build['build_number']} aktuell gebrochen"
            else:
                streak_txt = f"Letzter Fehler in Build #{primary_bad_build['build_number']} (aktuell wieder grün, aber Wetter {w_score}%)"

            cause_txt = ""
            if failed_steps and error_messages:
                cause_txt = f"Task '{failed_steps[0]}' meldet: {error_messages[0][:80]}."
            elif failed_steps:
                cause_txt = f"Abbruch im Build-Step '{', '.join(failed_steps[:2])}'."
            elif error_messages:
                cause_txt = f"Fehler: {error_messages[0][:80]}."
            elif first_bad_build.get("commit_comment"):
                cause_txt = f"Änderung in Commit {first_bad_build['commit_short']} (\"{first_bad_build['commit_comment'][:45]}\") prüfen."
            elif first_bad_build.get("pr_label"):
                cause_txt = f"Änderungen aus Pull Request {first_bad_build['pr_label']} prüfen."
            else:
                cause_txt = f"Ausgelöst via {primary_bad_build['reason_label']} auf Branch '{primary_bad_build['branch_short'] or 'default'}'."

            hint_text = f"{streak_txt}. Mögliche(r) Verursacher: {who_hint}. {cause_txt}"

        suspects_str = ", ".join(suspects_names)

        pipeline_entries.append({
            "pipeline_id": pid or 0,
            "name": pname,
            "folder": pinfo.get("folder") or "\\",
            "repo_name": latest.get("repo_name") or "-",
            "last_branch": latest.get("branch_short") or "-",
            "status_key": status_key,
            "status_ball": status_ball,
            "status_label": status_label,
            "weather_score": w_score,
            "weather_key": w_key,
            "weather_icon": w_icon,
            "weather_label": w_label,
            "last_5_runs": [
                {
                    "build_id": r["build_id"],
                    "build_number": r["build_number"],
                    "status_key": r["status_key"],
                    "status_ball": r["status_ball"],
                    "status_label": r["status_label"],
                    "date": r["finish_time_str"],
                    "duration_str": r["duration_str"],
                    "branch": r["branch_short"],
                    "commit": r["commit_short"],
                    "who": r["who_summary"],
                    "what": r["what_summary"],
                }
                for r in last_5
            ],
            "last_5_balls": last_5_balls,
            "total_runs": len(p_builds),
            "failed_runs_count": sum(1 for b in p_builds if b["status_key"] == "failed"),
            "unstable_runs_count": sum(1 for b in p_builds if b["status_key"] == "unstable"),
            "success_runs_count": len(success_runs),
            "last_build_number": latest.get("build_number") or "-",
            "last_build_date": latest.get("finish_time_str") or "-",
            "last_success_build": last_success["build_number"] if last_success else "",
            "last_success_date": last_success["finish_time_str"] if last_success else "",
            "last_success_display": last_success_display,
            "last_failure_build": last_failure["build_number"] if last_failure else "",
            "last_failure_date": last_failure["finish_time_str"] if last_failure else "",
            "last_failure_display": last_failure_display,
            "last_duration_seconds": latest.get("duration_seconds") or 0,
            "last_duration_str": latest.get("duration_str") or "-",
            "consecutive_failures": consecutive_failures,
            "broken_since_build": broken_since_build,
            "broken_since_date": broken_since_date,
            "has_problem": has_problem,
            "culprit_who": culprit_who,
            "suspects": suspects,
            "suspects_str": suspects_str,
            "culprit_what": culprit_what,
            "trigger_reason": trigger_reason,
            "failed_steps": failed_steps,
            "error_messages": error_messages,
            "last_commit_sha": latest.get("commit_short") or "",
            "last_commit_comment": latest.get("commit_comment") or "",
            "last_pr_label": latest.get("pr_label") or "",
            "hint_text": hint_text,
        })

    # Sort pipelines: failed first, then unstable, then by weather_score ascending, then name ascending
    status_sort_priority = {
        "failed": 0,
        "unstable": 1,
        "running": 2,
        "success": 3,
        "aborted": 4,
        "not_built": 5,
    }
    pipeline_entries.sort(
        key=lambda p: (
            status_sort_priority.get(p["status_key"], 9),
            0 if p["has_problem"] else 1,
            p["weather_score"],
            p["name"].lower()
        )
    )

    problem_pipelines = [p for p in pipeline_entries if p["has_problem"]]
    recent_failed_builds = [b for b in enriched_builds if b["status_key"] in ("failed", "unstable")][:30]

    total_pipelines = len(pipeline_entries)
    healthy_count = sum(1 for p in pipeline_entries if p["status_key"] == "success")
    unstable_count = sum(1 for p in pipeline_entries if p["status_key"] == "unstable")
    failed_count = sum(1 for p in pipeline_entries if p["status_key"] == "failed")
    running_count = sum(1 for p in pipeline_entries if p["status_key"] == "running")
    aborted_or_idle_count = sum(1 for p in pipeline_entries if p["status_key"] in ("aborted", "not_built"))

    active_weather_pipes = [p for p in pipeline_entries if p["total_runs"] > 0]
    if active_weather_pipes:
        overall_health_pct = int(round(sum(p["weather_score"] for p in active_weather_pipes) / len(active_weather_pipes)))
    else:
        overall_health_pct = 100

    if overall_health_pct >= 81:
        overall_weather_icon = weather_map.get("sunny", "☀️")
        overall_weather_key = "sunny"
    elif overall_health_pct >= 61:
        overall_weather_icon = weather_map.get("partly_cloudy", "🌤️")
        overall_weather_key = "partly_cloudy"
    elif overall_health_pct >= 41:
        overall_weather_icon = weather_map.get("cloudy", "☁️")
        overall_weather_key = "cloudy"
    elif overall_health_pct >= 21:
        overall_weather_icon = weather_map.get("raining", "🌧️")
        overall_weather_key = "raining"
    else:
        overall_weather_icon = weather_map.get("stormy", "⛈️")
        overall_weather_key = "stormy"

    summary = {
        "total_pipelines": total_pipelines,
        "healthy_count": healthy_count,
        "unstable_count": unstable_count,
        "failed_count": failed_count,
        "problem_count": len(problem_pipelines),
        "running_count": running_count,
        "aborted_or_idle_count": aborted_or_idle_count,
        "total_builds": len(enriched_builds),
        "overall_health_pct": overall_health_pct,
        "overall_weather_icon": overall_weather_icon,
        "overall_weather_key": overall_weather_key,
    }

    return {
        "summary": summary,
        "pipelines": pipeline_entries,
        "problem_pipelines": problem_pipelines,
        "recent_failed_builds": recent_failed_builds,
        "all_builds": enriched_builds[:100],
    }


def load_jinja_template(template_name="BUILD_PIPELINES.tmpl", custom_path=None):
    """Loads the Jinja2 template for the Build Pipelines report."""
    if custom_path and os.path.exists(custom_path):
        with open(custom_path, "r", encoding="utf-8") as f:
            return Template(f.read())

    candidates = [
        os.path.join(py_dir, "templates", template_name),
        os.path.join(os.path.dirname(py_dir), "src", "templates", template_name),
        os.path.join(os.getcwd(), "src", "templates", template_name),
    ]
    for c in candidates:
        if os.path.exists(c):
            with open(c, "r", encoding="utf-8") as f:
                return Template(f.read())
    return None


def generate_markdown_report(
    report_data,
    output_path,
    project_name="DemoProject",
    csv_filename="BUILD_PIPELINES.csv",
    template_path=None,
    config_path=None
):
    """Renders the Jenkins-style Build Pipelines Markdown report using Jinja2."""
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    status_icons_config = load_status_icons(custom_path=config_path)

    template = load_jinja_template("BUILD_PIPELINES.tmpl", custom_path=template_path)
    if not template:
        logger.error("Could not find BUILD_PIPELINES.tmpl template.")
        return ""

    content = template.render(
        now_str=now_str,
        project_name=project_name,
        csv_filename=csv_filename,
        summary=report_data.get("summary", {}),
        pipelines=report_data.get("pipelines", []),
        problem_pipelines=report_data.get("problem_pipelines", []),
        recent_failed_builds=report_data.get("recent_failed_builds", []),
        status_icons=status_icons_config,
    )

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)
    logger.info("Generated Build Pipelines Markdown report: %s", output_path)
    return content


def generate_csv_report(report_data, output_path):
    """Exports the Jenkins Build Pipelines health and culprit analysis to CSV."""
    fieldnames = [
        "Status",
        "Weather_Score_Pct",
        "Weather_Condition",
        "Pipeline_ID",
        "Pipeline_Name",
        "Repository",
        "Branch",
        "Total_Runs",
        "Consecutive_Failures",
        "Broken_Since_Build",
        "Last_Success_Build",
        "Last_Success_Date",
        "Last_Failure_Build",
        "Last_Failure_Date",
        "Last_Duration",
        "Culprit_Who",
        "Suspects_All",
        "Culprit_What",
        "Hint_Summary"
    ]

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for p in report_data.get("pipelines", []):
            writer.writerow({
                "Status": p.get("status_label", ""),
                "Weather_Score_Pct": p.get("weather_score", 100),
                "Weather_Condition": p.get("weather_key", ""),
                "Pipeline_ID": p.get("pipeline_id", ""),
                "Pipeline_Name": p.get("name", ""),
                "Repository": p.get("repo_name", ""),
                "Branch": p.get("last_branch", ""),
                "Total_Runs": p.get("total_runs", 0),
                "Consecutive_Failures": p.get("consecutive_failures", 0),
                "Broken_Since_Build": p.get("broken_since_build", ""),
                "Last_Success_Build": p.get("last_success_build", ""),
                "Last_Success_Date": p.get("last_success_date", ""),
                "Last_Failure_Build": p.get("last_failure_build", ""),
                "Last_Failure_Date": p.get("last_failure_date", ""),
                "Last_Duration": p.get("last_duration_str", ""),
                "Culprit_Who": p.get("culprit_who", ""),
                "Suspects_All": p.get("suspects_str", ""),
                "Culprit_What": p.get("culprit_what", ""),
                "Hint_Summary": p.get("hint_text", ""),
            })
    logger.info("Generated Build Pipelines CSV report: %s", output_path)


def run_pipelines_report(db_path=None, md_path=None, csv_path=None, project_id=None, config_path=None, template_path=None):
    """
    Main entrypoint to compute Jenkins-style pipeline health and write Markdown + CSV reports.
    """
    import devops_helper

    reports_dir = utils.get_reports_dir()
    if not md_path:
        md_path = os.path.join(reports_dir, "BUILD_PIPELINES.md")
    elif not os.path.isabs(md_path):
        md_path = os.path.join(reports_dir, md_path)

    if not csv_path:
        csv_path = os.path.join(reports_dir, "BUILD_PIPELINES.csv")
    elif not os.path.isabs(csv_path):
        csv_path = os.path.join(reports_dir, csv_path)

    if not db_path:
        db_path, _ = devops_helper._getDBCacheHandler()

    cache = AzureDevOpsCache(db_path)
    target_proj = project_id if project_id is not None else getattr(devops_helper, "AZURE_PROJECT_ID", None)

    report_data = analyze_pipelines_health(cache, project_id=None, config_path=config_path)
    csv_rel_name = os.path.basename(csv_path)

    generate_markdown_report(
        report_data,
        md_path,
        project_name=target_proj or "DefaultProject",
        csv_filename=csv_rel_name,
        template_path=template_path,
        config_path=config_path,
    )
    generate_csv_report(report_data, csv_path)
    return report_data
