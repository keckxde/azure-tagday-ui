# -*- coding: UTF-8 -*-
"""
Build and Artifact Disk Space Report Generator.

Analyzes cached Azure DevOps / TFS build executions and artifact storage,
producing two comprehensive reports:
1. A Markdown report (for rendering in the MkDocs Wiki) with KPI summary cards,
   breakdowns by pipeline and repository, largest artifacts, and cleanup recommendations.
2. A detailed CSV report for external data analysis, audit, and spreadsheet evaluation.
"""

import os
import sys
import csv
import sqlite3
import logging
from datetime import datetime, timedelta

# Add parent directories to sys.path
py_dir = os.path.dirname(os.path.abspath(__file__))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import devops_helper

from jinja2 import Template
from azure import AzureDevOpsCache
from utils import load_status_icons

logger = logging.getLogger(__name__)

def load_artifacts_data(cache_db):
    """
    Loads all artifacts joined with build, pipeline, and repository details from SQLite.
    """
    with cache_db._connection() as conn:
        query = """
        SELECT
            a.build_id,
            a.id AS artifact_id,
            a.name AS artifact_name,
            COALESCE(a.type, 'Container') AS resource_type,
            COALESCE(a.size_bytes, 0) AS size_bytes,
            COALESCE(a.size_mb, 0.0) AS size_mb,
            a.download_url,
            a.url AS artifact_url,
            COALESCE(a.is_deleted, 0) AS is_deleted,
            a.deleted_at,
            b.build_number,
            b.status AS build_status,
            b.result AS build_result,
            b.source_branch,
            b.source_version,
            b.queue_time,
            b.start_time,
            b.finish_time,
            b.requested_by,
            COALESCE(p.name, 'Unknown Pipeline') AS pipeline_name,
            COALESCE(r.name, 'Unknown Repo') AS repo_name,
            COALESCE(pr.name, 'Unknown Project') AS project_name
        FROM artifacts a
        JOIN builds b ON a.build_id = b.id
        LEFT JOIN pipelines p ON b.pipeline_id = p.id
        LEFT JOIN repositories r ON b.repo_id = r.id
        LEFT JOIN projects pr ON b.project_id = pr.id
        ORDER BY a.size_bytes DESC, a.build_id DESC
        """
        rows = conn.execute(query).fetchall()
        return [dict(r) for r in rows]


def calculate_metrics(artifacts):
    """
    Computes storage analytics across artifacts.
    """
    total_artifacts = len(artifacts)
    build_ids = {a["build_id"] for a in artifacts}
    total_builds = len(build_ids)

    active_artifacts = [a for a in artifacts if not a["is_deleted"]]
    deleted_artifacts = [a for a in artifacts if a["is_deleted"]]

    total_size_bytes = sum(a["size_bytes"] for a in artifacts)
    active_size_bytes = sum(a["size_bytes"] for a in active_artifacts)
    deleted_size_bytes = sum(a["size_bytes"] for a in deleted_artifacts)

    total_size_mb = total_size_bytes / (1024 * 1024)
    active_size_mb = active_size_bytes / (1024 * 1024)
    deleted_size_mb = deleted_size_bytes / (1024 * 1024)

    total_size_gb = total_size_mb / 1024
    active_size_gb = active_size_mb / 1024
    deleted_size_gb = deleted_size_mb / 1024

    avg_size_mb = (total_size_mb / total_artifacts) if total_artifacts > 0 else 0.0

    # Group by Pipeline
    by_pipeline = {}
    for a in artifacts:
        pname = a["pipeline_name"]
        if pname not in by_pipeline:
            by_pipeline[pname] = {
                "name": pname,
                "builds": set(),
                "artifact_count": 0,
                "active_size_bytes": 0,
                "deleted_size_bytes": 0,
                "total_size_bytes": 0,
            }
        group = by_pipeline[pname]
        group["builds"].add(a["build_id"])
        group["artifact_count"] += 1
        group["total_size_bytes"] += a["size_bytes"]
        if a["is_deleted"]:
            group["deleted_size_bytes"] += a["size_bytes"]
        else:
            group["active_size_bytes"] += a["size_bytes"]

    pipeline_list = []
    for p in by_pipeline.values():
        t_mb = p["total_size_bytes"] / (1024 * 1024)
        pct = (p["total_size_bytes"] / total_size_bytes * 100) if total_size_bytes > 0 else 0.0
        pipeline_list.append({
            "pipeline": p["name"],
            "builds_count": len(p["builds"]),
            "artifacts_count": p["artifact_count"],
            "active_mb": p["active_size_bytes"] / (1024 * 1024),
            "deleted_mb": p["deleted_size_bytes"] / (1024 * 1024),
            "total_mb": t_mb,
            "percent": pct
        })
    pipeline_list.sort(key=lambda x: x["total_mb"], reverse=True)

    # Group by Repository
    by_repo = {}
    for a in artifacts:
        rname = a["repo_name"]
        if rname not in by_repo:
            by_repo[rname] = {
                "name": rname,
                "builds": set(),
                "artifact_count": 0,
                "total_size_bytes": 0,
                "active_size_bytes": 0,
                "deleted_size_bytes": 0,
            }
        group = by_repo[rname]
        group["builds"].add(a["build_id"])
        group["artifact_count"] += 1
        group["total_size_bytes"] += a["size_bytes"]
        if a["is_deleted"]:
            group["deleted_size_bytes"] += a["size_bytes"]
        else:
            group["active_size_bytes"] += a["size_bytes"]

    repo_list = []
    for r in by_repo.values():
        t_mb = r["total_size_bytes"] / (1024 * 1024)
        pct = (r["total_size_bytes"] / total_size_bytes * 100) if total_size_bytes > 0 else 0.0
        repo_list.append({
            "repo": r["name"],
            "builds_count": len(r["builds"]),
            "artifacts_count": r["artifact_count"],
            "active_mb": r["active_size_bytes"] / (1024 * 1024),
            "deleted_mb": r["deleted_size_bytes"] / (1024 * 1024),
            "total_mb": t_mb,
            "percent": pct
        })
    repo_list.sort(key=lambda x: x["total_mb"], reverse=True)

    # Group by Build Result
    by_result = {}
    for a in artifacts:
        res = a["build_result"] or "unknown"
        if res not in by_result:
            by_result[res] = {"count": 0, "size_bytes": 0, "builds": set()}
        by_result[res]["count"] += 1
        by_result[res]["size_bytes"] += a["size_bytes"]
        by_result[res]["builds"].add(a["build_id"])

    result_list = []
    for res, data in by_result.items():
        mb = data["size_bytes"] / (1024 * 1024)
        pct = (data["size_bytes"] / total_size_bytes * 100) if total_size_bytes > 0 else 0.0
        result_list.append({
            "result": res,
            "builds_count": len(data["builds"]),
            "artifacts_count": data["count"],
            "size_mb": mb,
            "percent": pct
        })
    result_list.sort(key=lambda x: x["size_mb"], reverse=True)

    # Failed build artifacts cleanup potential
    failed_artifacts = [a for a in artifacts if (a["build_result"] or "").lower() == "failed" and not a["is_deleted"]]
    failed_size_mb = sum(a["size_bytes"] for a in failed_artifacts) / (1024 * 1024)

    # Stale artifacts (>90 days old)
    now = datetime.now()
    stale_artifacts = []
    for a in active_artifacts:
        ftime = a.get("finish_time")
        if ftime:
            try:
                dt = datetime.strptime(ftime[:19], "%Y-%m-%d %H:%M:%S")
                if (now - dt).days > 90:
                    stale_artifacts.append(a)
            except Exception:
                pass
    stale_size_mb = sum(a["size_bytes"] for a in stale_artifacts) / (1024 * 1024)

    return {
        "total_builds": total_builds,
        "total_artifacts": total_artifacts,
        "active_artifacts_count": len(active_artifacts),
        "deleted_artifacts_count": len(deleted_artifacts),
        "total_size_mb": total_size_mb,
        "total_size_gb": total_size_gb,
        "active_size_mb": active_size_mb,
        "active_size_gb": active_size_gb,
        "deleted_size_mb": deleted_size_mb,
        "deleted_size_gb": deleted_size_gb,
        "avg_size_mb": avg_size_mb,
        "by_pipeline": pipeline_list,
        "by_repo": repo_list,
        "by_result": result_list,
        "top_artifacts": artifacts[:15],
        "failed_count": len(failed_artifacts),
        "failed_size_mb": failed_size_mb,
        "stale_count": len(stale_artifacts),
        "stale_size_mb": stale_size_mb,
    }


def load_jinja_template(template_filename, custom_path=None):
    """
    Locates and loads a Jinja2 template from candidate locations or a custom path.
    """
    if custom_path and os.path.exists(custom_path):
        with open(custom_path, "r", encoding="utf-8") as f:
            return Template(f.read())

    current_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(current_dir, "templates", template_filename),
        os.path.join(os.path.dirname(current_dir), "templates", template_filename),
        os.path.join(os.path.dirname(os.path.dirname(current_dir)), "scripts", "templates", template_filename),
        os.path.join(os.path.dirname(os.path.dirname(current_dir)), "templates", template_filename),
    ]
    for c in candidates:
        if os.path.exists(c):
            with open(c, "r", encoding="utf-8") as f:
                return Template(f.read())
    return None


def generate_markdown_report(metrics, artifacts, output_path, project_name="DemoProject", csv_filename="BUILD_ARTIFACTS.csv", template_path=None, config_path=None):
    """
    Renders the Wiki Markdown report optimized for MkDocs Material using Jinja2 template.
    """
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    reclaimable_mb = metrics.get("deleted_size_mb", 0.0) + metrics.get("failed_size_mb", 0.0)
    reclaimable_gb = reclaimable_mb / 1024

    # Load status icons from YAML configuration file
    status_icons_config = load_status_icons(custom_path=config_path)
    build_icons = status_icons_config.get("build_status", {})

    for res in metrics.get("by_result", []):
        if "label" not in res:
            res["label"] = build_icons.get(res["result"], res["result"])

    template = load_jinja_template("BUILD_ARTIFACTS.tmpl", custom_path=template_path)
    if not template:
        logger.error("Could not find BUILD_ARTIFACTS.tmpl template.")
        return ""

    content = template.render(
        now_str=now_str,
        project_name=project_name,
        csv_filename=csv_filename,
        metrics=metrics,
        reclaimable_gb=reclaimable_gb,
        status_icons=status_icons_config,
        azure_base_url=devops_helper.AZURE_BASE_URL,
        azure_collection=devops_helper.AZURE_COLLECTION,
    )

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)
    logger.info(f"Generated Markdown report from template: {output_path}")
    return content


def generate_csv_report(artifacts, output_path):
    """
    Exports full artifact and build details to a standardized CSV file for external evaluation.
    """
    fieldnames = [
        "Project",
        "Pipeline",
        "Build_ID",
        "Build_Number",
        "Repository",
        "Branch",
        "Commit_SHA",
        "Build_Status",
        "Build_Result",
        "Queue_Time",
        "Start_Time",
        "Finish_Time",
        "Requested_By",
        "Artifact_ID",
        "Artifact_Name",
        "Resource_Type",
        "Size_Bytes",
        "Size_MB",
        "Is_Deleted",
        "Deleted_At",
        "Download_URL"
    ]

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for a in artifacts:
            writer.writerow({
                "Project": a.get("project_name", ""),
                "Pipeline": a.get("pipeline_name", ""),
                "Build_ID": a.get("build_id", ""),
                "Build_Number": a.get("build_number", ""),
                "Repository": a.get("repo_name", ""),
                "Branch": a.get("source_branch", ""),
                "Commit_SHA": a.get("source_version", ""),
                "Build_Status": a.get("build_status", ""),
                "Build_Result": a.get("build_result", ""),
                "Queue_Time": a.get("queue_time", ""),
                "Start_Time": a.get("start_time", ""),
                "Finish_Time": a.get("finish_time", ""),
                "Requested_By": a.get("requested_by", ""),
                "Artifact_ID": a.get("artifact_id", ""),
                "Artifact_Name": a.get("artifact_name", ""),
                "Resource_Type": a.get("resource_type", ""),
                "Size_Bytes": a.get("size_bytes", 0),
                "Size_MB": f"{a.get('size_mb', 0.0):.2f}",
                "Is_Deleted": "Yes" if a.get("is_deleted") else "No",
                "Deleted_At": a.get("deleted_at") or "",
                "Download_URL": a.get("download_url", "")
            })
    logger.info(f"Generated CSV report: {output_path}")


def run_reports(db_path, md_path, csv_path, auto_seed=True, config_path=None, template_path=None):
    """
    Main execution pipeline for generating both Markdown and CSV reports.
    """
    base_folder = devops_helper.BASE_FOLDER

    logger.info(f"Connecting to Cache DB: {db_path}")
    cache = AzureDevOpsCache(db_path)

    # Check if database has builds/artifacts
    with cache._connection() as conn:
        b_count = conn.execute("SELECT COUNT(*) FROM builds").fetchone()[0]
        a_count = conn.execute("SELECT COUNT(*) FROM artifacts").fetchone()[0]

    if b_count == 0 or a_count == 0:
        logger.warning(f"Database {db_path} contains no build or artifact records.")

    artifacts = load_artifacts_data(cache)
    if not artifacts:
        logger.warning("No artifacts found to report.")
        return False

    metrics = calculate_metrics(artifacts)

    csv_rel_name = os.path.basename(csv_path)
    generate_markdown_report(metrics, artifacts, md_path, project_name=devops_helper.AZURE_PROJECT_ID, csv_filename=csv_rel_name, template_path=template_path, config_path=config_path)
    generate_csv_report(artifacts, csv_path)

    print(f"\n============================================================")
    print(f"Build & Artifact Storage Reports Generated Successfully!")
    print(f"============================================================")
    print(f"Total Builds Analyzed:   {metrics['total_builds']}")
    print(f"Total Artifacts:         {metrics['total_artifacts']} ({metrics['active_artifacts_count']} active, {metrics['deleted_artifacts_count']} deleted)")
    print(f"Total Storage Tracked:   {metrics['total_size_gb']:.2f} GB ({metrics['total_size_mb']:.1f} MB)")
    print(f"Active Live Storage:     {metrics['active_size_gb']:.2f} GB")
    print(f"Deleted / Reclaimed:     {metrics['deleted_size_gb']:.2f} GB")
    print(f"Markdown Wiki Report:    {md_path}")
    print(f"CSV External Evaluation: {csv_path}")
    print(f"============================================================\n")
    return True
