# -*- coding: UTF-8 -*-
"""
Sprint & Timeframe Report Generator
Generates Markdown wiki documentation and CSV exports for weekly sprints and custom timeframes,
focusing on User Story / Requirement, Bug, Feature, and Task progress, deadlines, and completion.
"""

import os
import sys
import csv
import json
import logging
import argparse
from datetime import datetime, date

# Ensure src/ is on sys.path
_current_dir = os.path.dirname(os.path.abspath(__file__))
if _current_dir not in sys.path:
    sys.path.insert(0, _current_dir)

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import devops_helper
from azure import AzureDevOpsCache
from utils import (
    parse_iso_datetime,
    parse_sprint_week,
    get_sprint_date_range,
    format_sprint_range_label,
    calculate_deadline_urgency,
)

logger = logging.getLogger("sprint_report")


def is_work_item_in_sprint(wi, sprint_name):
    """
    Determines if a work item belongs to the specified sprint.
    Supports weekly sprint codes (e.g. week-2633, week-2615), full iteration paths,
    and named iterations (e.g. Sprint 1).
    """
    if not sprint_name or not wi:
        return False

    if wi.get("deleted") or wi.get("is_deleted"):
        return False

    sprint_clean = sprint_name.strip().lower()
    y_s, w_s, base_s = parse_sprint_week(sprint_clean)

    # 1. Weekly sprint matching (week-YYWW)
    if base_s:
        # Check sprint_week_name if already enriched
        s_name = wi.get("sprint_week_name")
        if s_name:
            _, _, base_i = parse_sprint_week(s_name)
            if base_i == base_s:
                return True

        # Check iteration_name
        iter_n = wi.get("iteration_name")
        if iter_n:
            _, _, base_i = parse_sprint_week(iter_n)
            if base_i == base_s:
                return True

        # Check iteration_path
        iter_p = wi.get("iteration_path")
        if iter_p:
            _, _, base_i = parse_sprint_week(iter_p)
            if base_i == base_s:
                return True

        # Check raw_json iteration path
        if wi.get("raw_json"):
            try:
                raw = json.loads(wi["raw_json"]) if isinstance(wi["raw_json"], str) else wi["raw_json"]
                fields = raw.get("fields", {}) if isinstance(raw, dict) else {}
                raw_ip = fields.get("System.IterationPath") or ""
                if raw_ip:
                    _, _, base_i = parse_sprint_week(raw_ip)
                    if base_i == base_s:
                        return True
            except Exception:
                pass

        return False

    # 2. Named sprints (e.g. "Sprint 1", "Release 2")
    iter_name = (wi.get("iteration_name") or "").strip().lower()
    if iter_name and iter_name == sprint_clean:
        return True

    iter_path = (wi.get("iteration_path") or "").replace("\\", "/").strip("/")
    if not iter_path and wi.get("raw_json"):
        try:
            raw = json.loads(wi["raw_json"]) if isinstance(wi["raw_json"], str) else wi["raw_json"]
            fields = raw.get("fields", {}) if isinstance(raw, dict) else {}
            iter_path = (fields.get("System.IterationPath") or "").replace("\\", "/").strip("/")
        except Exception:
            pass

    if iter_path:
        norm_path = iter_path.lower()
        parts = [p.strip().lower() for p in norm_path.split("/") if p.strip()]
        if parts:
            leaf = parts[-1]
            if leaf == sprint_clean:
                return True
        if norm_path == sprint_clean or norm_path.endswith("/" + sprint_clean):
            return True

    return False


def filter_work_items_for_timeframe(work_items, sprint_name=None, start_date=None, end_date=None):
    """
    Filters work items matching the given sprint name or falling within a specific date range.

    Args:
        work_items (list): List of work item dictionaries from SQLite cache or DevOpsBackend.
        sprint_name (str, optional): Target sprint name (e.g. 'week-2633', 'week-2615', 'Sprint 1').
        start_date (date/str, optional): Start date boundary for custom date-range queries.
        end_date (date/str, optional): End date boundary for custom date-range queries.

    Returns:
        list: Filtered and enriched work item records.
    """
    sprint_clean = (sprint_name or "").strip()
    start_d = datetime.strptime(start_date, "%Y-%m-%d").date() if isinstance(start_date, str) else start_date
    end_d = datetime.strptime(end_date, "%Y-%m-%d").date() if isinstance(end_date, str) else end_date

    matched = []
    for wi in work_items:
        if wi.get("deleted") or wi.get("is_deleted"):
            continue

        if sprint_clean:
            # Sprint-targeted report: work item MUST belong to the requested sprint
            if is_work_item_in_sprint(wi, sprint_clean):
                matched.append(wi)
        elif start_d or end_d:
            # Custom date timeframe query
            c_date_raw = wi.get("changed_date") or ""
            if not c_date_raw and wi.get("raw_json"):
                try:
                    raw = json.loads(wi["raw_json"]) if isinstance(wi["raw_json"], str) else wi["raw_json"]
                    fields = raw.get("fields", {}) if isinstance(raw, dict) else {}
                    c_date_raw = fields.get("System.ChangedDate") or fields.get("System.CreatedDate") or ""
                except Exception:
                    pass
            dt = parse_iso_datetime(c_date_raw) if c_date_raw else None
            if dt:
                item_d = dt.date()
                in_start = (item_d >= start_d) if start_d else True
                in_end = (item_d <= end_d) if end_d else True
                if in_start and in_end:
                    matched.append(wi)
        else:
            # No sprint or date bounds specified: include all planned items
            is_planned = wi.get("is_iteration_planned")
            if is_planned is None:
                _, _, b_name = parse_sprint_week(wi.get("iteration_path") or wi.get("iteration_name") or "")
                is_planned = bool(b_name)
            if is_planned:
                matched.append(wi)

    return matched


def generate_sprint_report_data(cache_db, sprint_name=None, start_date=None, end_date=None, now_dt=None, work_items=None):
    """
    Analyzes work items in cache and produces aggregated sprint metrics and category lists.

    Returns:
        dict: Structured sprint report data.
    """
    if work_items is not None:
        all_wis = work_items
    elif cache_db:
        all_wis = cache_db.get_all_work_items(include_deleted=False)
    else:
        all_wis = []

    # Determine sprint time bounds if sprint_name provided
    sprint_label = sprint_name or "Custom Timeframe"
    sprint_start_str = ""
    sprint_end_str = ""
    if sprint_name:
        y, w, base_name = parse_sprint_week(sprint_name)
        if y and w:
            s_d, e_d, sprint_start_str, sprint_end_str = get_sprint_date_range(y, w)
            sprint_label = format_sprint_range_label(y, w)
            if not start_date:
                start_date = s_d
            if not end_date:
                end_date = e_d

    matched_wis = filter_work_items_for_timeframe(
        all_wis,
        sprint_name=sprint_name,
        start_date=start_date if not sprint_name else None,
        end_date=end_date if not sprint_name else None
    )

    stories = []
    bugs = []
    tasks = []
    features = []
    others = []

    assignee_stats = {}
    state_stats = {}

    for wi in matched_wis:
        wi_type = (wi.get("type") or wi.get("WorkItemType") or "Task").strip()
        wi_state = (wi.get("state") or wi.get("State") or "Active").strip()
        assignee = (wi.get("assigned_to") or "Unassigned").strip()
        is_done = wi_state.lower() in ("closed", "done", "resolved", "completed", "removed", "cut")

        # Deadline resolution
        deadline_raw = wi.get("target_date") or wi.get("finish_date") or wi.get("due_date")
        if not deadline_raw and wi.get("raw_json"):
            try:
                raw = json.loads(wi["raw_json"]) if isinstance(wi["raw_json"], str) else wi["raw_json"]
                fields = raw.get("fields", {}) if isinstance(raw, dict) else {}
                deadline_raw = (
                    fields.get("Microsoft.VSTS.Scheduling.TargetDate")
                    or fields.get("Microsoft.VSTS.Scheduling.DueDate")
                    or fields.get("Microsoft.VSTS.Scheduling.FinishDate")
                    or fields.get("Custom.TargetDate")
                    or fields.get("Custom.DueDate")
                )
            except Exception:
                pass

        if not deadline_raw and sprint_end_str:
            deadline_raw = sprint_end_str
        urgency = calculate_deadline_urgency(deadline_raw, is_completed=is_done, now_dt=now_dt)

        item_enriched = dict(wi)
        item_enriched["wi_type"] = wi_type
        item_enriched["wi_state"] = wi_state
        item_enriched["assignee"] = assignee
        item_enriched["is_done"] = is_done
        item_enriched["urgency"] = urgency
        item_enriched["deadline_str"] = urgency.get("deadline_str", "")
        item_enriched["tfs_url"] = wi.get("tfs_url") or wi.get("htmlLink") or wi.get("url") or ""

        t_lower = wi_type.lower()
        if t_lower in ("requirement", "user story", "story"):
            stories.append(item_enriched)
        elif t_lower in ("bug", "defect", "problem"):
            bugs.append(item_enriched)
        elif t_lower in ("task",):
            tasks.append(item_enriched)
        elif t_lower in ("feature", "epic"):
            features.append(item_enriched)
        else:
            others.append(item_enriched)

        # Assignee counters
        if assignee not in assignee_stats:
            assignee_stats[assignee] = {"total": 0, "closed": 0, "active": 0, "stories": 0, "bugs": 0, "tasks": 0}
        assignee_stats[assignee]["total"] += 1
        if is_done:
            assignee_stats[assignee]["closed"] += 1
        else:
            assignee_stats[assignee]["active"] += 1

        if t_lower in ("requirement", "user story", "story"):
            assignee_stats[assignee]["stories"] += 1
        elif t_lower in ("bug", "defect"):
            assignee_stats[assignee]["bugs"] += 1
        elif t_lower == "task":
            assignee_stats[assignee]["tasks"] += 1

        # State counters
        state_stats[wi_state] = state_stats.get(wi_state, 0) + 1

    all_items = stories + bugs + tasks + features + others
    total_items = len(all_items)
    closed_items = sum(1 for w in all_items if w.get("is_done"))
    active_items = total_items - closed_items
    completion_rate = (closed_items / total_items * 100) if total_items > 0 else 0.0

    return {
        "sprint_name": sprint_name or "Timeframe",
        "sprint_label": sprint_label,
        "start_date": str(start_date or sprint_start_str or "N/A"),
        "end_date": str(end_date or sprint_end_str or "N/A"),
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "total_items": total_items,
        "closed_items": closed_items,
        "active_items": active_items,
        "completion_rate": round(completion_rate, 1),
        "stories": sorted(stories, key=lambda x: x["id"], reverse=True),
        "bugs": sorted(bugs, key=lambda x: x["id"], reverse=True),
        "tasks": sorted(tasks, key=lambda x: x["id"], reverse=True),
        "features": sorted(features, key=lambda x: x["id"], reverse=True),
        "others": sorted(others, key=lambda x: x["id"], reverse=True),
        "assignee_stats": assignee_stats,
        "state_stats": state_stats,
    }


def render_sprint_markdown(data):
    """
    Renders structured sprint data into a clean, modern GitHub Markdown wiki document.
    """
    lines = []
    lines.append(f"# 🚀 Agile Sprint Report: {data['sprint_label']}")
    lines.append("")
    lines.append(f"> **Timeframe:** `{data['start_date']}` – `{data['end_date']}`  ")
    lines.append(f"> **Generated:** `{data['generated_at']}` | **Completion Rate:** `{data['completion_rate']}%`")
    lines.append("")

    # Summary KPI Table
    lines.append("## 📊 Sprint Summary")
    lines.append("")
    lines.append("| Metric | Count | Details |")
    lines.append("| :--- | :--- | :--- |")
    lines.append(f"| **Total Work Items** | `{data['total_items']}` | All items planned or worked in sprint |")
    lines.append(f"| **User Stories & Requirements** | `{len(data['stories'])}` | {sum(1 for s in data['stories'] if s['is_done'])} completed, {sum(1 for s in data['stories'] if not s['is_done'])} active |")
    lines.append(f"| **Bugs / Defects** | `{len(data['bugs'])}` | {sum(1 for b in data['bugs'] if b['is_done'])} resolved, {sum(1 for b in data['bugs'] if not b['is_done'])} in progress |")
    lines.append(f"| **Technical Tasks** | `{len(data['tasks'])}` | {sum(1 for t in data['tasks'] if t['is_done'])} finished, {sum(1 for t in data['tasks'] if not t['is_done'])} pending |")
    lines.append(f"| **Completed / Closed** | `{data['closed_items']}` | **{data['completion_rate']}%** overall velocity |")
    lines.append(f"| **Active / In Progress** | `{data['active_items']}` | Pending items |")
    lines.append("")

    # Team Member Workload
    if data["assignee_stats"]:
        lines.append("## 👥 Team Workload & Contribution")
        lines.append("")
        lines.append("| Team Member | Total Items | Stories / Reqs | Bugs | Tasks | Completed | Active |")
        lines.append("| :--- | :---: | :---: | :---: | :---: | :---: | :---: |")
        for member, stat in sorted(data["assignee_stats"].items(), key=lambda x: x[1]["total"], reverse=True):
            lines.append(f"| **{member}** | `{stat['total']}` | {stat['stories']} | {stat['bugs']} | {stat['tasks']} | {stat['closed']} | `{stat['active']}` |")
        lines.append("")

    # User Stories & Requirements Section
    lines.append("## 🎯 User Stories & Functional Requirements")
    lines.append("")
    if data["stories"]:
        lines.append("| ID | Title | State | Assignee | Deadline | Urgency |")
        lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")
        for st in data["stories"]:
            title_clean = (st.get("title") or "").replace("|", "-")
            urg_badge = st.get("urgency", {}).get("badge_text", "—")
            d_str = st.get("deadline_str") or "—"
            lines.append(f"| [#{st['id']}]({st.get('tfs_url') or ''}) | {title_clean} | `{st['wi_state']}` | {st['assignee']} | `{d_str}` | {urg_badge} |")
    else:
        lines.append("*No User Stories or Requirements assigned to this sprint.*")
    lines.append("")

    # Bugs Section
    lines.append("## 🐛 Bugs & Defects Handled")
    lines.append("")
    if data["bugs"]:
        lines.append("| ID | Title | State | Assignee | Deadline | Urgency |")
        lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")
        for bg in data["bugs"]:
            title_clean = (bg.get("title") or "").replace("|", "-")
            urg_badge = bg.get("urgency", {}).get("badge_text", "—")
            d_str = bg.get("deadline_str") or "—"
            lines.append(f"| [#{bg['id']}]({bg.get('tfs_url') or ''}) | {title_clean} | `{bg['wi_state']}` | {bg['assignee']} | `{d_str}` | {urg_badge} |")
    else:
        lines.append("*No bugs tracked in this sprint timeframe.*")
    lines.append("")

    # Tasks Section (if any)
    if data["tasks"]:
        lines.append("## 🛠️ Tasks Breakdown")
        lines.append("")
        lines.append("| ID | Title | State | Assignee | Linked PRs |")
        lines.append("| :--- | :--- | :--- | :--- | :--- |")
        for tk in data["tasks"]:
            title_clean = (tk.get("title") or "").replace("|", "-")
            pr_cnt = tk.get("linked_pr_count", 0)
            pr_str = f"🔀 {pr_cnt} PR(s)" if pr_cnt > 0 else "—"
            lines.append(f"| [#{tk['id']}]({tk.get('tfs_url') or ''}) | {title_clean} | `{tk['wi_state']}` | {tk['assignee']} | {pr_str} |")
        lines.append("")

    return "\n".join(lines)


def export_sprint_csv(data, csv_path):
    """
    Exports sprint work item data to a flat CSV file for external evaluation.
    """
    all_categories = data["stories"] + data["bugs"] + data["tasks"] + data["features"] + data["others"]
    fieldnames = ["id", "type", "title", "state", "assigned_to", "is_completed", "deadline", "urgency_status", "iteration_path", "tfs_url"]

    with open(csv_path, mode="w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter=";")
        writer.writeheader()
        for item in sorted(all_categories, key=lambda x: x["id"]):
            writer.writerow({
                "id": item["id"],
                "type": item["wi_type"],
                "title": item.get("title", ""),
                "state": item["wi_state"],
                "assigned_to": item["assignee"],
                "is_completed": "1" if item["is_done"] else "0",
                "deadline": item.get("deadline_str", ""),
                "urgency_status": item.get("urgency", {}).get("status", ""),
                "iteration_path": item.get("iteration_path", ""),
                "tfs_url": item.get("tfs_url", ""),
            })


def generate_sprint_report(cache_db, sprint_name=None, start_date=None, end_date=None, output_md=None, output_csv=None, now_dt=None, work_items=None):
    """
    High-level orchestrator to generate both Markdown report and CSV file.
    """
    data = generate_sprint_report_data(cache_db, sprint_name=sprint_name, start_date=start_date, end_date=end_date, now_dt=now_dt, work_items=work_items)
    md_content = render_sprint_markdown(data)

    if output_md:
        os.makedirs(os.path.dirname(os.path.abspath(output_md)), exist_ok=True)
        with open(output_md, "w", encoding="utf-8") as f:
            f.write(md_content)
        logger.info("Saved Sprint Markdown Report: %s", output_md)

    if output_csv:
        os.makedirs(os.path.dirname(os.path.abspath(output_csv)), exist_ok=True)
        export_sprint_csv(data, output_csv)
        logger.info("Saved Sprint CSV Export: %s", output_csv)

    return data, md_content


def main():
    parser = argparse.ArgumentParser(description="Generate Weekly Sprint & Timeframe Work Item Reports.")
    parser.add_argument("--sprint", help="Sprint iteration name (e.g. week-2633, week-2615)")
    parser.add_argument("--start-date", help="Start date filter (YYYY-MM-DD)")
    parser.add_argument("--end-date", help="End date filter (YYYY-MM-DD)")
    parser.add_argument("--db", help="Path to SQLite cache DB")
    parser.add_argument("--out-md", help="Path for output Markdown file")
    parser.add_argument("--out-csv", help="Path for output CSV file")
    parser.add_argument("--env-file", type=str, default=None, help="Path to .env file to load configuration from (optional, DB used by default)")
    parser.add_argument("--load-env", action="store_true", help="Explicitly load .env from repository root or current directory.")

    args = parser.parse_args()

    if args.env_file or args.load_env:
        import utils
        utils.load_env_file(args.env_file)

    db_path = args.db
    if not db_path:
        # Check user_settings or AZURE_PROJECT_ID
        settings_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "user_settings.yaml")
        if os.path.exists(settings_path):
            try:
                import yaml
                with open(settings_path, "r", encoding="utf-8") as f:
                    cfg = yaml.safe_load(f) or {}
                    db_path = cfg.get("db_path")
            except Exception:
                pass
        if not db_path and devops_helper.AZURE_PROJECT_ID:
            cand = f"tfs_cache_{devops_helper.AZURE_PROJECT_ID}.db"
            if os.path.exists(cand):
                db_path = cand

    if not db_path or not os.path.exists(db_path):
        import glob
        dbs = glob.glob("tfs_cache_*.db")
        if dbs:
            db_path = dbs[0]
        else:
            print(f"Error: Cache database not found at {db_path}", file=sys.stderr)
            sys.exit(1)

    cache = AzureDevOpsCache(db_path)
    data, md_text = generate_sprint_report(
        cache,
        sprint_name=args.sprint,
        start_date=args.start_date,
        end_date=args.end_date,
        output_md=args.out_md,
        output_csv=args.out_csv
    )

    if not args.out_md:
        print(md_text)


if __name__ == "__main__":
    main()
