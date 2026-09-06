# -*- coding: UTF-8 -*-
"""
Tag Day Report Generator.

Provides an enhanced Tag Day view for multi-repository Azure DevOps / TFS setups:
- Evaluates changes per repository relative to each repository's own latest version tag (starting with "v").
- Lists all repositories that have Pull Requests merged/completed or active after their latest tag.
- Identifies all repositories that have updates in branches that are not yet merged.
- Generates a consolidated chronological timeline of all untagged changes across all repositories.
- Provides an individual repository walkthrough view with deep-dive inspection.
"""

import os
import sys
import re
import json
import logging
from datetime import datetime

# Add py directory to sys.path
py_dir = os.path.dirname(os.path.abspath(__file__))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import devops_helper
try:
    from devops_helper import patch_pr_title_for_release_notes
except ImportError:
    patch_pr_title_for_release_notes = getattr(devops_helper, "patch_pr_title_for_release_notes", None)

from jinja2 import Template
from azure import AzureDevOpsCache
from utils import (
    load_status_icons,
    load_repo_categories,
    categorize_repository,
    sort_categories_for_report,
    parse_semver_tuple,
)

logger = logging.getLogger(__name__)


def check_branch_important(text: str) -> bool:
    """Überprüft, ob 'archiv', 'demo' oder 'deprecated' im String vorkommen. Falls ja => false, Falls nein: true """
    keywords = ("archive/", "demo/", "deprecated","test/")
    
    # Text in Kleinbuchstaben umwandeln für einen case-insensitive Abgleich
    text_clean = text.lower().strip()
    
    # Prüfen, ob eines der Keywords im Text existiert => Nicht wichtig
    if text_clean.startswith(keywords):
        return False
    # Wichtiger Branch, den wir nicht filtern
    return True


def load_tagday_data(cache_db, project_id=None, ignore_repos=None):
    """
    Queries SQLite cache database and prepares Tag Day data evaluated per repository
    relative to each repository's own latest version tag.

    Args:
        cache_db (AzureDevOpsCache): Cache database instance.
        project_id (str, optional): Project identifier.
        ignore_repos (list, optional): List of repository names to ignore.

    Returns:
        dict: Structured datasets for Tag Day report.
    """
    if ignore_repos is None:
        ignore_str = os.getenv("IGNORE_REPOS", "")
        ignore_repos = ignore_str.split() if ignore_str else []

    with cache_db._connection() as conn:
        # 1. Fetch all repositories
        repos_query = "SELECT id, name, default_branch, web_url, is_disabled FROM repositories"
        if project_id:
            repos_query += " WHERE project_id = ?"
            repos_rows = conn.execute(repos_query, (project_id,)).fetchall()
        else:
            repos_rows = conn.execute(repos_query).fetchall()

        repositories = {}
        for r in repos_rows:
            name = r["name"]
            if name in ignore_repos:
                continue
            repositories[name] = {
                "id": r["id"],
                "name": name,
                "default_branch": r["default_branch"],
                "web_url": r["web_url"] or f"{devops_helper.AZURE_BASE_URL}/{devops_helper.AZURE_COLLECTION}/{project_id}/_git/{name}",
                "is_disabled": bool(r["is_disabled"]),
                "category": categorize_repository(name),
                "latest_tag": None,
                "prs_after_tag": [],
                "unmerged_branches": [],
                "active_prs": [],
                "all_prs": []
            }

        # 2. Fetch all version tags starting with 'v' and determine latest tag per repository
        all_tags = conn.execute("""
            SELECT t.repo_id, r.name AS repo_name, t.name AS tag_name, t.commit_date, t.committer_name, t.comment
            FROM tags t
            JOIN repositories r ON t.repo_id = r.id
            WHERE t.name LIKE 'v%'
        """).fetchall()

        repo_tags_map = {}
        for t in all_tags:
            rname = t["repo_name"]
            if rname not in repo_tags_map:
                repo_tags_map[rname] = []
            repo_tags_map[rname].append(t)

        repo_tags_chronological = {}
        for rname in repositories.keys():
            if rname in repo_tags_map:
                tags = repo_tags_map[rname]
                # Chronological order ascending for resolving which release tag a PR belongs to
                repo_tags_chronological[rname] = sorted(
                    tags,
                    key=lambda x: (x["commit_date"] or "1970-01-01", parse_semver_tuple(x["tag_name"]))
                )
                sorted_tags = sorted(
                    tags,
                    key=lambda x: (x["commit_date"] or "1970-01-01", parse_semver_tuple(x["tag_name"])),
                    reverse=True
                )
                if sorted_tags:
                    latest = sorted_tags[0]
                    repositories[rname]["latest_tag"] = {
                        "name": latest["tag_name"],
                        "commit_date": latest["commit_date"] or "",
                        "committer": latest["committer_name"] or "",
                        "comment": (latest["comment"] or "").strip(),
                        "semver": parse_semver_tuple(latest["tag_name"])
                    }

        # 3. Fetch Pull Requests and filter each against its repository's latest tag
        prs_rows = conn.execute("""
            SELECT 
                pr.id AS pr_id,
                pr.repo_id,
                pr.title,
                pr.status,
                pr.target_branch,
                pr.source_branch,
                pr.created_by,
                pr.closed_by,
                pr.closed_date,
                pr.status_str,
                pr.raw_json,
                r.name AS repo_name,
                t_direct.name AS direct_tag_name
            FROM pull_requests pr
            JOIN repositories r ON pr.repo_id = r.id
            LEFT JOIN tags t_direct ON pr.repo_id = t_direct.repo_id AND 
                (
                    json_extract(pr.raw_json, '$.lastMergeCommit.commitId') = 
                    COALESCE(json_extract(t_direct.raw_json, '$.addinfo.taggedObject.objectId'), json_extract(t_direct.raw_json, '$.objectId'))
                    OR (
                        t_direct.commit_id IS NOT NULL AND t_direct.commit_id != '' AND
                        json_extract(pr.raw_json, '$.lastMergeCommit.commitId') LIKE (t_direct.commit_id || '%')
                    )
                )
            ORDER BY pr.closed_date DESC, pr.id DESC
        """).fetchall()

        all_changes_timeline = []
        prs_by_repo_and_source = {}

        for pr in prs_rows:
            rname = pr["repo_name"]
            if rname not in repositories:
                continue

            status = (pr["status"] or "").lower()
            closed_date = pr["closed_date"] or ""

            # Parse raw_json for additional metadata
            creation_date = ""
            description = ""
            if pr["raw_json"]:
                try:
                    meta = json.loads(pr["raw_json"])
                    creation_date = meta.get("creationDateStr") or meta.get("creationDate") or ""
                    description = meta.get("description") or ""
                except Exception:
                    pass

            target_branch = (pr["target_branch"] or "").replace("refs/heads/", "").strip()
            source_branch = (pr["source_branch"] or "").replace("refs/heads/", "").strip()

            pr_title = pr["title"] or "(No title)"
            if patch_pr_title_for_release_notes:
                pr_title = patch_pr_title_for_release_notes(pr, cache_db=cache_db, default_title=pr_title)

            # Determine tag association: direct tag match or release tag based on closed_date
            direct_tag = pr["direct_tag_name"]
            assigned_tag = direct_tag
            tag_type = "direct" if direct_tag else "untagged"

            if not assigned_tag and closed_date and status in ("completed", "3"):
                for t in repo_tags_chronological.get(rname, []):
                    t_dt = t["commit_date"] or ""
                    if t_dt and t_dt >= closed_date:
                        assigned_tag = t["tag_name"]
                        tag_type = "in_release"
                        break

            is_tagged = bool(assigned_tag)
            if not is_tagged:
                if status in ("active", "1"):
                    tag_type = "active"
                elif status in ("abandoned", "2"):
                    tag_type = "abandoned"
                else:
                    tag_type = "untagged"

            pr_item = {
                "pr_id": pr["pr_id"],
                "repo_name": rname,
                "title": pr_title,
                "description": description.strip(),
                "status": status,
                "status_str": pr["status_str"] or status.upper(),
                "target_branch": target_branch,
                "source_branch": source_branch,
                "created_by": pr["created_by"] or "Unknown",
                "closed_date": closed_date,
                "creation_date": creation_date,
                "date": closed_date if closed_date else creation_date,
                "item_type": "PR",
                "tag_name": assigned_tag or "",
                "is_tagged": is_tagged,
                "tag_type": tag_type
            }

            prs_by_repo_and_source.setdefault((rname, source_branch), []).append(pr_item)
            repositories[rname]["all_prs"].append(pr_item)

            # Per-repository baseline cutoff date
            repo_latest_tag = repositories[rname]["latest_tag"]
            repo_cutoff_date = repo_latest_tag["commit_date"] if repo_latest_tag and repo_latest_tag["commit_date"] else "1970-01-01 00:00:00"

            is_completed_after_repo_tag = (status in ("completed", "3") and closed_date and closed_date > repo_cutoff_date)
            is_active = (status in ("active", "1"))

            if is_completed_after_repo_tag:
                repositories[rname]["prs_after_tag"].append(pr_item)
                all_changes_timeline.append(pr_item)
            elif is_active:
                repositories[rname]["active_prs"].append(pr_item)
                all_changes_timeline.append(pr_item)

        # 4. Fetch Branches with unmerged commits (ahead_count > 0)
        branches_rows = conn.execute("""
            SELECT 
                b.repo_id,
                b.name AS branch_name,
                b.commit_id,
                b.commit_date,
                b.committer_name,
                b.comment,
                b.ahead_count,
                b.behind_count,
                r.name AS repo_name
            FROM branches b
            JOIN repositories r ON b.repo_id = r.id
            WHERE b.ahead_count > 0
            ORDER BY b.commit_date DESC
        """).fetchall()

        for b in branches_rows:
            rname = b["repo_name"]
            if rname not in repositories:
                continue

            bname = (b["branch_name"] or "").replace("refs/heads/", "").strip()
            # Skip base tracking branches like 'main', 'dev', 'master'
            if bname in ("main", "dev", "master"):
                continue

            matching_prs = prs_by_repo_and_source.get((rname, bname), [])
            active_matching = [p for p in matching_prs if p.get("status") in ("active", "1")]
            prepared_pr = active_matching[0] if active_matching else (matching_prs[0] if matching_prs else None)

            branch_item = {
                "repo_name": rname,
                "branch_name": bname,
                "commit_id": b["commit_id"] or "",
                "short_hash": (b["commit_id"] or "")[:7],
                "commit_date": b["commit_date"] or "",
                "committer": b["committer_name"] or "Unknown",
                "comment": (b["comment"] or "").strip(),
                "ahead": b["ahead_count"] if b["ahead_count"] is not None else 0,
                "behind": b["behind_count"] if b["behind_count"] is not None else 0,
                "date": b["commit_date"] or "",
                "item_type": "BRANCH",
                "prepared_pr": prepared_pr,
                "prepared_prs": active_matching if active_matching else matching_prs,
            }
            if check_branch_important(bname):
                repositories[rname]["unmerged_branches"].append(branch_item)

            # Per-repository baseline cutoff date
            repo_latest_tag = repositories[rname]["latest_tag"]
            repo_cutoff_date = repo_latest_tag["commit_date"] if repo_latest_tag and repo_latest_tag["commit_date"] else "1970-01-01 00:00:00"

            # If commit date of ahead branch is after repo's latest tag, add to changes timeline
            if branch_item["commit_date"] and branch_item["commit_date"] > repo_cutoff_date:
                pr_note = f" (PR !{prepared_pr['pr_id']})" if prepared_pr else ""
                all_changes_timeline.append({
                    "pr_id": f"Branch:{branch_item['short_hash']}",
                    "repo_name": rname,
                    "title": f"[{bname}]{pr_note} {branch_item['comment']}",
                    "description": f"Ahead by {branch_item['ahead']} commits" + (f", PR !{prepared_pr['pr_id']}" if prepared_pr else ""),
                    "status": "unmerged",
                    "status_str": f"AHEAD +{branch_item['ahead']}",
                    "target_branch": bname,
                    "source_branch": bname,
                    "created_by": branch_item["committer"],
                    "closed_date": "",
                    "creation_date": branch_item["commit_date"],
                    "date": branch_item["commit_date"],
                    "item_type": "BRANCH_UPDATE"
                })

        # Sort timeline chronologically descending
        all_changes_timeline.sort(key=lambda x: x.get("date") or "1970-01-01", reverse=True)

        # 5. Filter repositories with changes
        repos_with_prs = {k: v for k, v in repositories.items() if len(v["prs_after_tag"]) > 0 or len(v["active_prs"]) > 0}
        repos_with_unmerged_branches = {k: v for k, v in repositories.items() if len(v["unmerged_branches"]) > 0}
        repos_with_any_changes = {
            k: v for k, v in repositories.items()
            if len(v["prs_after_tag"]) > 0 or len(v["active_prs"]) > 0 or len(v["unmerged_branches"]) > 0
        }

        return {
            "project_id": project_id,
            "all_repositories": repositories,
            "repos_with_prs": repos_with_prs,
            "repos_with_unmerged_branches": repos_with_unmerged_branches,
            "repos_with_any_changes": repos_with_any_changes,
            "all_changes_timeline": all_changes_timeline,
            "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
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


def format_prepared_pr_link(branch_item, project_id):
    """
    Formats markdown link(s) to prepared pull requests for a branch.

    Args:
        branch_item (dict): Branch dictionary containing prepared_prs or prepared_pr.
        project_id (str): TFS / Azure DevOps project ID.

    Returns:
        str: Markdown link or '-' if no PR is prepared.
    """
    matching_prs = branch_item.get("prepared_prs") or []
    if not matching_prs and branch_item.get("prepared_pr"):
        matching_prs = [branch_item["prepared_pr"]]
    if not matching_prs:
        return "-"
    active_prs = [p for p in matching_prs if p.get("status") in ("active", "1")]
    if active_prs:
        links = [
            f"[!{p['pr_id']}]({devops_helper.AZURE_BASE_URL}/{devops_helper.AZURE_COLLECTION}/{project_id}/_git/{p['repo_name']}/pullrequest/{p['pr_id']})"
            for p in active_prs
        ]
        return ", ".join(links)

    # If no active PR, show latest completed/abandoned PR with status indicator
    p = matching_prs[0]
    st = (p.get("status") or "").lower()
    st_label = "completed" if st in ("completed", "3") else ("abandoned" if st in ("abandoned", "2") else st)
    url = f"{devops_helper.AZURE_BASE_URL}/{devops_helper.AZURE_COLLECTION}/{project_id}/_git/{p['repo_name']}/pullrequest/{p['pr_id']}"
    return f"[!{p['pr_id']}]({url}) *({st_label})*" if st_label else f"[!{p['pr_id']}]({url})"


def generate_tagday_markdown(data, output_path=None, template_path=None, config_path=None, project_id=None):
    """
    Renders the Tag Day release overview report into Markdown using Jinja2 templates.
    """
    gen_time = data.get("generated_at") or datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Load status icons from YAML configuration file
    status_icons_config = load_status_icons(custom_path=config_path)
    tagday_icons = status_icons_config.get("tagday_status", {})
    completed_icon = tagday_icons.get("completed_pr", ":octicons-check-circle-16:")
    active_icon = tagday_icons.get("active_pr", ":octicons-git-pull-request-16:")
    unmerged_icon = tagday_icons.get("unmerged_branch", ":octicons-git-branch-16:")

    repos_with_prs = data["repos_with_prs"]
    repos_with_branches = data["repos_with_unmerged_branches"]
    repos_with_any = data["repos_with_any_changes"]
    timeline = data["all_changes_timeline"]

    total_repos_tracked = len(data["all_repositories"])
    total_prs_after_tag = sum(len(r["prs_after_tag"]) for r in repos_with_prs.values())
    total_active_prs = sum(len(r["active_prs"]) for r in data["all_repositories"].values())
    total_unmerged_branches = sum(len(r["unmerged_branches"]) for r in repos_with_branches.values())

    # 1. Format sorted PR repositories for View 1
    sorted_prs_repos = []
    for rname in sorted(repos_with_prs.keys(), key=lambda k: len(repos_with_prs[k]["prs_after_tag"]), reverse=True):
        r = repos_with_prs[rname]
        latest_pr_item = r["prs_after_tag"][0] if r["prs_after_tag"] else (r["active_prs"][0] if r["active_prs"] else None)
        latest_date = latest_pr_item["date"] if latest_pr_item else "-"
        latest_title = latest_pr_item["title"][:45] + "..." if latest_pr_item and len(latest_pr_item["title"]) > 45 else (latest_pr_item["title"] if latest_pr_item else "-")
        latest_pr_link = f"[!{latest_pr_item['pr_id']}]({devops_helper.AZURE_BASE_URL}/{devops_helper.AZURE_COLLECTION}/{project_id}/_git/{rname}/pullrequest/{latest_pr_item['pr_id']}) {latest_title}" if latest_pr_item else "-"

        sorted_prs_repos.append({
            "name": rname,
            "anchor": rname.lower().replace(".", "").replace("/", "-"),
            "category": r["category"],
            "latest_tag_str": r["latest_tag"]["name"] if r["latest_tag"] else "*None*",
            "latest_tag_date": r["latest_tag"]["commit_date"] if r["latest_tag"] else "-",
            "merged_count": len(r["prs_after_tag"]),
            "active_count": len(r["active_prs"]),
            "latest_pr_date": latest_date,
            "latest_pr_link": latest_pr_link,
        })

    # 2. Format unmerged branches for View 2
    unmerged_branch_rows = []
    for rname in sorted(repos_with_branches.keys()):
        r = repos_with_branches[rname]
        anchor = rname.lower().replace(".", "").replace("/", "-")
        for b in r["unmerged_branches"]:
            comment_clean = b["comment"].replace("\n", " ")
            if len(comment_clean) > 55:
                comment_clean = comment_clean[:52] + "..."
            pr_link = format_prepared_pr_link(b, project_id)
            unmerged_branch_rows.append({
                "repo_name": rname,
                "anchor": anchor,
                "branch_name": b["branch_name"],
                "ahead": b["ahead"],
                "behind": b["behind"],
                "commit_date": b["commit_date"],
                "committer": b["committer"],
                "comment_clean": comment_clean,
                "pr_link": pr_link,
                "prepared_pr": b.get("prepared_pr"),
            })

    # 3. Format timeline items for View 3
    formatted_timeline = []
    for ch in timeline:
        item_id = str(ch.get("pr_id", ""))
        status_badge = ch["status_str"]
        if "DON" in status_badge or "COMPLETED" in status_badge:
            status_badge = f"{completed_icon} `{status_badge}`"
        elif "OPN" in status_badge or "ACTIVE" in status_badge:
            status_badge = f"{active_icon} `{status_badge}`"
        elif "AHEAD" in status_badge:
            status_badge = f"{unmerged_icon} `{status_badge}`"

        title_clean = ch["title"].replace("\n", " ").replace("|", "\\|")
        if len(title_clean) > 75:
            title_clean = title_clean[:72] + "..."
        link_col = item_id
        if str(item_id).isdigit():
            link_col = f"[!{item_id}]({devops_helper.AZURE_BASE_URL}/{devops_helper.AZURE_COLLECTION}/{project_id}/_git/{ch['repo_name']}/pullrequest/{item_id})"

        formatted_timeline.append({
            "date": ch["date"],
            "repo_name": ch["repo_name"],
            "anchor": ch["repo_name"].lower().replace(".", "").replace("/", "-"),
            "item_link": link_col,
            "status_badge": status_badge,
            "target_branch": ch["target_branch"],
            "created_by": ch["created_by"],
            "title_clean": title_clean,
        })

    # 4. Format category groups for View 4 Walkthrough
    active_categories = set(r.get("category", "OTHERS") for r in repos_with_any.values())
    categories = sort_categories_for_report(active_categories)

    category_groups = []
    for cat in categories:
        cat_repos = []
        for rname in [name for name, r in sorted(repos_with_any.items()) if r["category"] == cat]:
            r = repos_with_any[rname]
            anchor = rname.lower().replace(".", "").replace("/", "-")
            tag_info = r["latest_tag"]
            tag_display = f"`{tag_info['name']}` ({tag_info['commit_date']})" if tag_info else "*No version tag found*"
            tag_label = tag_info['name'] if tag_info else "initial"

            unmerged_branches = []
            for b in r["unmerged_branches"]:
                c_clean = b["comment"].replace("\n", " ").replace("|", "\\|")
                pr_link = format_prepared_pr_link(b, project_id)
                unmerged_branches.append({
                    "branch_name": b["branch_name"],
                    "short_hash": b["short_hash"],
                    "commit_date": b["commit_date"],
                    "committer": b["committer"],
                    "ahead": b["ahead"],
                    "behind": b["behind"],
                    "comment_clean": c_clean,
                    "pr_link": pr_link,
                    "prepared_pr": b.get("prepared_pr"),
                })

            all_prs = []
            source_prs = r.get("all_prs", []) if r.get("all_prs") else r.get("prs_after_tag", [])
            for pr in source_prs:
                desc_text = pr["title"]
                if pr.get("description"):
                    clean_desc = pr["description"].replace("\n", ", ").replace("|", "\\|")
                    if clean_desc and clean_desc != desc_text:
                        desc_text = f"{desc_text} (*{clean_desc}*)"
                if len(desc_text) > 90:
                    desc_text = desc_text[:87] + "..."
                all_prs.append({
                    "pr_id": pr["pr_id"],
                    "date": pr["date"],
                    "status_str": pr["status_str"],
                    "target_branch": pr["target_branch"],
                    "created_by": pr["created_by"],
                    "desc_clean": desc_text,
                    "tag_name": pr.get("tag_name", ""),
                    "is_tagged": pr.get("is_tagged", False),
                    "tag_type": pr.get("tag_type", ""),
                })

            prs_after_tag_list = []
            for pr in r.get("prs_after_tag", []):
                desc_text = pr["title"]
                if pr.get("description"):
                    clean_desc = pr["description"].replace("\n", ", ").replace("|", "\\|")
                    if clean_desc and clean_desc != desc_text:
                        desc_text = f"{desc_text} (*{clean_desc}*)"
                if len(desc_text) > 90:
                    desc_text = desc_text[:87] + "..."
                prs_after_tag_list.append({
                    "pr_id": pr["pr_id"],
                    "date": pr["date"],
                    "status_str": pr["status_str"],
                    "target_branch": pr["target_branch"],
                    "created_by": pr["created_by"],
                    "desc_clean": desc_text,
                    "tag_name": pr.get("tag_name", ""),
                    "is_tagged": pr.get("is_tagged", False),
                    "tag_type": pr.get("tag_type", ""),
                })

            cat_repos.append({
                "name": rname,
                "anchor": anchor,
                "web_url": r["web_url"],
                "tag_display": tag_display,
                "tag_label": tag_label,
                "unmerged_branches": unmerged_branches,
                "all_prs": all_prs,
                "prs_after_tag": prs_after_tag_list,
            })

        if cat_repos:
            category_groups.append({
                "name": cat,
                "repos": cat_repos,
            })

    # Load template
    template = load_jinja_template("TAGDAY_REPORT.tmpl", custom_path=template_path)
    if not template:
        template = load_jinja_template("TAGDAY.tmpl", custom_path=template_path)

    if not template:
        logger.error("Could not find TAGDAY_REPORT.tmpl or TAGDAY.tmpl template.")
        return ""

    rendered = template.render(
        project_id=project_id,
        gen_time=gen_time,
        total_repos_tracked=total_repos_tracked,
        repos_with_any=repos_with_any,
        repos_with_prs=repos_with_prs,
        sorted_prs_repos=sorted_prs_repos,
        repos_with_branches=repos_with_branches,
        unmerged_branch_rows=unmerged_branch_rows,
        timeline=formatted_timeline,
        category_groups=category_groups,
        total_prs_after_tag=total_prs_after_tag,
        total_active_prs=total_active_prs,
        total_unmerged_branches=total_unmerged_branches,
        status_icons=status_icons_config,
        azure_base_url=devops_helper.AZURE_BASE_URL,
        azure_collection=devops_helper.AZURE_COLLECTION,
    )

    if output_path:
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(rendered)
        logger.info(f"Tag Day Markdown report saved from template: {output_path}")

    return rendered


def run_tagday_report(db_path, output_path, project_id, config_path=None, template_path=None):
    """
    Executes Tag Day report generation workflow end-to-end.
    All path and project parameters are mandatory and provided by the caller.
    """
    if not os.path.exists(db_path):
        logger.error(f"TFS SQLite cache database not found at: {db_path}")
        return False

    cache_db = AzureDevOpsCache(db_path)

    logger.info(f"Loading repository data from cache DB: {db_path}...")
    data = load_tagday_data(cache_db, project_id=project_id)

    generate_tagday_markdown(data, output_path=output_path, template_path=template_path, config_path=config_path, project_id=project_id)

    print("\n" + "=" * 60)
    print("Tag Day Report Generated Successfully!")
    print("=" * 60)
    print(f"Scope:                Per-repository latest tag evaluation")
    print(f"Repos Analyzed:       {len(data['all_repositories'])}")
    print(f"Repos with Changes:   {len(data['repos_with_any_changes'])}")
    print(f"Repos with PRs:       {len(data['repos_with_prs'])}")
    print(f"Repos with Ahead Br.: {len(data['repos_with_unmerged_branches'])}")
    print(f"Total Untagged Logs:  {len(data['all_changes_timeline'])}")
    print(f"Markdown Output:      {output_path}")
    print("=" * 60 + "\n")
    return True

