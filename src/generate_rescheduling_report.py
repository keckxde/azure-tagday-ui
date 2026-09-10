# -*- coding: UTF-8 -*-
"""
Sprint Rescheduling & Moved Items Report Generator
Generates Markdown wiki documentation and CSV exports specifically for work items
that were moved/rescheduled between sprints (ignoring initial backlog-to-sprint assignments).
"""

import os
import sys
import csv
import json
import logging
import argparse
from datetime import datetime

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
from azure.azure_db import AzureDevOpsCache, _is_scheduled_sprint

logger = logging.getLogger("rescheduling_report")


def get_rescheduled_items_data(cache_db=None, review_status=None):
    """
    Retrieves and aggregates all work item moves where the item was previously scheduled
    in a sprint (filtering out initial assignments from Backlog to iteration).

    Args:
        cache_db (AzureDevOpsCache, optional): Database instance.
        review_status (str, optional): Filter by 'pending' or 'accepted'.

    Returns:
        dict: Aggregated reporting structure with metrics and item lists.
    """
    if cache_db is None:
        _, db = devops_helper._getDBCacheHandler()
    else:
        db = cache_db
    raw_shifts = db.get_sprint_to_sprint_shifts(limit=1000, review_status=review_status)

    total_shifts = len(raw_shifts)
    net_delay = sum((s.get("delta_weeks") or 0) for s in raw_shifts)
    postponed_count = sum(1 for s in raw_shifts if (s.get("delta_weeks") or 0) > 0)
    accelerated_count = sum(1 for s in raw_shifts if (s.get("delta_weeks") or 0) < 0)
    pending_count = sum(1 for s in raw_shifts if (s.get("review_status") or "pending") == "pending")
    accepted_count = sum(1 for s in raw_shifts if (s.get("review_status") or "pending") == "accepted")

    # Aggregate by work item
    items_map = {}
    for s in raw_shifts:
        wid = s["work_item_id"]
        if wid not in items_map:
            items_map[wid] = {
                "id": wid,
                "title": s.get("title", ""),
                "type": s.get("type", "Item"),
                "assigned_to": s.get("assigned_to", "Unassigned"),
                "first_sprint": s.get("old_sprint", ""),
                "latest_sprint": s.get("new_sprint", ""),
                "total_delayed_weeks": 0,
                "shift_count": 0,
                "last_shifted_at": s.get("recorded_at", ""),
                "pending_shifts": 0,
                "accepted_shifts": 0,
                "shifts": []
            }
        it = items_map[wid]
        it["total_delayed_weeks"] += (s.get("delta_weeks") or 0)
        it["shift_count"] += 1
        it["latest_sprint"] = s.get("new_sprint", it["latest_sprint"])
        if (s.get("review_status") or "pending") == "accepted":
            it["accepted_shifts"] += 1
        else:
            it["pending_shifts"] += 1
        it["shifts"].append(s)

    items_list = list(items_map.values())
    for it in items_list:
        it["review_status"] = "accepted" if it["pending_shifts"] == 0 else "pending"

    # Sort items by highest delayed weeks first
    items_list.sort(key=lambda x: (x["total_delayed_weeks"], x["shift_count"]), reverse=True)

    return {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "total_shifts": total_shifts,
        "total_moved_items": len(items_list),
        "net_delay_weeks": net_delay,
        "postponed_shifts": postponed_count,
        "accelerated_shifts": accelerated_count,
        "pending_shifts_count": pending_count,
        "accepted_shifts_count": accepted_count,
        "review_filter": review_status or "all",
        "work_items": items_list,
        "audit_log": raw_shifts
    }


def render_rescheduling_markdown(data):
    """
    Renders a comprehensive Markdown wiki documentation report for moved sprint items.
    """
    lines = []
    lines.append("# 🔄 Sprint Rescheduling & Postponement Impact Report")
    lines.append("")
    lines.append(f"> **Generated on:** {data.get('generated_at', '')}  ")
    lines.append(f"> **Scope:** Work items rescheduled from a scheduled sprint to another iteration (*Initial Backlog assignments ignored*)  ")
    if data.get("review_filter") and data.get("review_filter") != "all":
        lines.append(f"> **Review Filter:** `{data.get('review_filter').upper()}` only  ")
    lines.append("")

    lines.append("## 📊 Executive Summary & Rescheduling Impact")
    lines.append("")
    lines.append("| Metric | Count / Value | Description |")
    lines.append("| :--- | :--- | :--- |")
    lines.append(f"| **Rescheduled Work Items** | `{data.get('total_moved_items', 0)}` | Unique work items moved between sprints |")
    lines.append(f"| **Total Shift Events** | `{data.get('total_shifts', 0)}` | Total number of recorded sprint-to-sprint move operations |")
    
    net_d = data.get('net_delay_weeks', 0)
    net_d_str = f"+{net_d} Weeks" if net_d > 0 else f"{net_d} Weeks"
    lines.append(f"| **Net Delay Impact** | `{net_d_str}` | Cumulative delay/postponement across all shifted items |")
    lines.append(f"| **Postponed Shifts** | `{data.get('postponed_shifts', 0)}` | Moves shifted into later sprints |")
    lines.append(f"| **Accelerated Shifts** | `{data.get('accelerated_shifts', 0)}` | Moves pulled forward into earlier sprints |")
    lines.append(f"| **Pending Review** | `{data.get('pending_shifts_count', 0)}` | Rescheduling events requiring policy review |")
    lines.append(f"| **Accepted / Approved** | `{data.get('accepted_shifts_count', 0)}` | Rescheduling events approved by team |")
    lines.append("")

    lines.append("## 🎯 Rescheduled Work Items Overview")
    lines.append("")
    lines.append("| ID | Title | Type | Assignee | Initial Sprint | Current Sprint | Delay | Moves | Review Status |")
    lines.append("| :---: | :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: |")

    items = data.get("work_items", [])
    if not items:
        lines.append("| *None* | *No sprint-to-sprint rescheduling moves found matching criteria.* | — | — | — | — | — | — | — |")
    else:
        for it in items:
            wid = it.get("id")
            title = (it.get("title") or "").replace("|", "\\|")
            wtype = it.get("type") or "Story"
            assignee = it.get("assigned_to") or "Unassigned"
            f_sprint = it.get("first_sprint") or "—"
            c_sprint = it.get("latest_sprint") or "—"
            d_weeks = it.get("total_delayed_weeks", 0)
            d_str = f"+{d_weeks}w" if d_weeks > 0 else f"{d_weeks}w"
            moves = it.get("shift_count", 1)
            status = "✅ Accepted" if it.get("review_status") == "accepted" else "⏳ Pending"
            lines.append(f"| #{wid} | {title} | {wtype} | {assignee} | `{f_sprint}` | `{c_sprint}` | **{d_str}** | {moves} | {status} |")

    lines.append("")
    lines.append("## 📜 Chronological Rescheduling Audit Log")
    lines.append("")
    lines.append("| Date & Time | Work Item | Type | Shift Transition | Delta | Source | Status | Assignee |")
    lines.append("| :--- | :--- | :---: | :--- | :---: | :---: | :---: | :--- |")

    audit = data.get("audit_log", [])
    if not audit:
        lines.append("| *No recorded shift events found.* | — | — | — | — | — | — | — |")
    else:
        for ev in audit:
            rec_at = (ev.get("recorded_at") or "").replace("T", " ")[:19]
            wid = ev.get("work_item_id")
            title = (ev.get("title") or "").replace("|", "\\|")
            wtype = ev.get("type") or "Story"
            old_s = ev.get("old_sprint") or "—"
            new_s = ev.get("new_sprint") or "—"
            delta = ev.get("delta_weeks", 0)
            delta_str = f"+{delta}w" if delta > 0 else f"{delta}w"
            src = "🖥️ GUI" if ev.get("source") == "user_gui" else "🔄 Sync"
            st = "✅ Accepted" if ev.get("review_status") == "accepted" else "⏳ Pending"
            assigned = ev.get("assigned_to") or "Unassigned"
            lines.append(f"| {rec_at} | #{wid} - {title} | {wtype} | `{old_s}` ➔ `{new_s}` | **{delta_str}** | {src} | {st} | {assigned} |")

    lines.append("")
    lines.append("---")
    lines.append("*Report automatically generated by Azure DevOps Tag Day & Workload Explorer Suite.*")
    return "\n".join(lines)


def export_rescheduling_csv(data, csv_path):
    """
    Exports sprint-to-sprint rescheduled items and shift audit logs to CSV.
    """
    os.makedirs(os.path.dirname(os.path.abspath(csv_path)), exist_ok=True)
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow([
            "WorkItemID",
            "Title",
            "Type",
            "Assignee",
            "FromSprint",
            "ToSprint",
            "DeltaWeeks",
            "Source",
            "ReviewStatus",
            "RecordedAt"
        ])
        for ev in data.get("audit_log", []):
            writer.writerow([
                ev.get("work_item_id", ""),
                ev.get("title", ""),
                ev.get("type", ""),
                ev.get("assigned_to", ""),
                ev.get("old_sprint", ""),
                ev.get("new_sprint", ""),
                ev.get("delta_weeks", 0),
                ev.get("source", ""),
                ev.get("review_status", "pending"),
                ev.get("recorded_at", "")
            ])


def generate_rescheduling_report(cache_db=None, output_md=None, output_csv=None, review_status=None):
    """
    Generates Markdown and CSV reports for sprint-to-sprint rescheduled work items.

    Returns:
        dict: Path information and metrics summary.
    """
    data = get_rescheduled_items_data(cache_db=cache_db, review_status=review_status)

    base_folder = devops_helper.BASE_FOLDER
    md_file = output_md or os.path.normpath(os.path.join(base_folder, "RESCHEDULING_REPORT.md"))
    csv_file = output_csv or os.path.normpath(os.path.join(base_folder, "RESCHEDULING_REPORT.csv"))

    # Render & write Markdown
    md_content = render_rescheduling_markdown(data)
    os.makedirs(os.path.dirname(os.path.abspath(md_file)), exist_ok=True)
    with open(md_file, "w", encoding="utf-8") as f:
        f.write(md_content)

    # Render & write CSV
    export_rescheduling_csv(data, csv_file)

    logger.info("Generated Rescheduling Markdown Report: %s", md_file)
    logger.info("Generated Rescheduling CSV Export: %s", csv_file)

    return {
        "success": True,
        "md_path": md_file,
        "csv_path": csv_file,
        "total_moved_items": data.get("total_moved_items", 0),
        "total_shifts": data.get("total_shifts", 0),
        "net_delay_weeks": data.get("net_delay_weeks", 0),
        "pending_shifts_count": data.get("pending_shifts_count", 0),
        "accepted_shifts_count": data.get("accepted_shifts_count", 0)
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    parser = argparse.ArgumentParser(description="Generate Sprint Rescheduling & Postponement Impact Report.")
    parser.add_argument("--db", type=str, default=None, help="Optional SQLite database path.")
    parser.add_argument("--output-md", type=str, default=None, help="Path for output Markdown report.")
    parser.add_argument("--output-csv", type=str, default=None, help="Path for output CSV export.")
    parser.add_argument("--review-status", type=str, default=None, choices=["pending", "accepted", "all"], help="Filter by review status.")
    parser.add_argument("--env-file", type=str, default=None, help="Path to .env file to load configuration from (optional, DB used by default)")
    parser.add_argument("--load-env", action="store_true", help="Explicitly load .env from repository root or current directory.")
    args = parser.parse_args()

    if args.env_file or args.load_env:
        import utils
        utils.load_env_file(args.env_file)

    r_stat = None if args.review_status == "all" else args.review_status
    cache = AzureDevOpsCache(args.db) if args.db else None
    res = generate_rescheduling_report(cache_db=cache, output_md=args.output_md, output_csv=args.output_csv, review_status=r_stat)
    print(f"\nReport Generated Successfully!")
    print(f"  Moved Work Items: {res['total_moved_items']}")
    print(f"  Total Shift Events: {res['total_shifts']}")
    print(f"  Net Delay Weeks: {res['net_delay_weeks']}")
    print(f"  Markdown: {res['md_path']}")
    print(f"  CSV: {res['csv_path']}")
