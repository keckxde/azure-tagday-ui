# -*- coding: UTF-8 -*-
import os
import re
import sqlite3
import json
import logging
from datetime import datetime

try:
    from devops_helper import (
        patch_pr_title_for_release_notes,
        BASE_FOLDER,
        AZURE_PROJECT_ID,
        REVISION_FILE_MD,
    )
except ImportError:
    patch_pr_title_for_release_notes = None
    import utils
    BASE_FOLDER = utils.GetEnvVariable("BASE_FOLDER", os.getcwd())
    AZURE_PROJECT_ID = utils.GetEnvVariable("AZURE_PROJECT_ID")
    REVISION_FILE_MD = utils.GetEnvVariable("REVISION_FILE_MD", "doc/04_Development/REVISION.md")

from azure import AzureDevOpsCache

logger = logging.getLogger(__name__)

CUTOFF_DATE = datetime(2025, 5, 16)

def parse_revision_date(date_str):
    if not date_str or date_str.strip() == "":
        return None
    parts = date_str.strip().split('.')
    if len(parts) == 3:
        try:
            day = int(parts[0])
            month = int(parts[1])
            year = int(parts[2])
            # Handle 2-digit year (e.g. 26 -> 2026, 99 -> 1999)
            if year < 100:
                year += 2000 if year < 80 else 1900
            return datetime(year, month, day)
        except ValueError:
            return None
    return None

def safe_iso_parse(date_str):
    if not date_str or date_str.strip() == "":
        return None
    try:
        return datetime.fromisoformat(date_str)
    except Exception:
        try:
            return datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
        except Exception:
            return None

def format_date_rev(dt):
    if not dt:
        return ""
    return dt.strftime("%d.%m.%y")

def get_last_change(unstable,stable,last_change):
    version_str = unstable
    if stable > version_str:
        version_str = stable
    if not version_str:
        return ""
    match = re.search(r'\d+$', version_str)
    if match and match.group(0) != "0":
        return match.group(0)
    return last_change

def generate_revision_md(db_path, revision_md_path):
    if not db_path or not os.path.exists(db_path):
        logger.error(f"TFS SQLite cache database not found at: {db_path}")
        return False

    repos_data = {}
    header_block = "# Revision History\n\n| Package | SuperInstaller | Unstable (Nightly) | Stable | Last Change | Owner |\n| ------- | -------------- | ------------------ | ------ | ----------- | ----- |"

    if os.path.exists(revision_md_path):
        try:
            with open(revision_md_path, "r", encoding="utf-8") as f:
                content = f.read()

            if content.strip():
                # 1. Parse categories and repositories from details sections
                sections = re.split(r'^(###\s+[\w\-]+)', content, flags=re.MULTILINE)
                header_block = sections[0]

                for i in range(1, len(sections), 2):
                    repo_header = sections[i]  # e.g., "### DemoProject"
                    repo_body = sections[i+1]  # everything until the next ###
                    repo_name = repo_header.replace("###", "").strip()

                    # Parse Info table (keep it exactly as is)
                    info_match = re.search(r'\*\*Info:\*\*.*?(?=\*\*Version:\*\*|$)', repo_body, re.DOTALL)
                    info_block = info_match.group(0).strip() if info_match else ""

                    # Parse existing Version table and filter for historical rows (before CUTOFF_DATE)
                    version_match = re.search(r'\*\*Version:\*\*.*$', repo_body, re.DOTALL)
                    old_rows = []
                    if version_match:
                        version_text = version_match.group(0)
                        rows = version_text.strip().split("\n")
                        current_date_val = None

                        for row in rows:
                            if not row.strip().startswith("|") or "Date" in row or "---" in row:
                                continue
                            cols = [c.strip() for c in row.split("|")[1:-1]]
                            if len(cols) < 4:
                                continue

                            row_date_str = cols[0]
                            row_ver = cols[1]
                            row_stable = cols[2]
                            row_desc = cols[3]

                            row_date = parse_revision_date(row_date_str)
                            if row_date:
                                current_date_val = row_date

                            # If date is before cutoff date, preserve the row!
                            if current_date_val and current_date_val < CUTOFF_DATE:
                                old_rows.append({
                                    "date_str": row_date_str,
                                    "version": row_ver,
                                    "stable": row_stable,
                                    "description": row_desc,
                                    "date_obj": current_date_val
                                })

                    repos_data[repo_name] = {
                        "header": repo_header,
                        "info_block": info_block,
                        "old_rows": old_rows
                    }
        except Exception as e:
            logger.warning(f"Could not read existing REVISION.md at {revision_md_path}: {e}")

    # Connect to SQLite Cache DB
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cache_db = AzureDevOpsCache(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM repositories")

    for repo_entry in cursor.fetchall():
        repo_name = repo_entry["name"]
        if repo_name not in repos_data:
            repos_data[repo_name] = {
                "header": "### " + repo_name,
                "info_block": "",
                "old_rows": []
            }

    # 2. Re-render each repository's Version table using cached SQLite data
    updated_details = []
    repo_tags_map = {}  # Maps repo_name to (stable_tag, unstable_tag, superinstaller_tag, latest, committer_name)

    for repo_name, data in repos_data.items():
        # Query repository from database
        cursor.execute("SELECT id FROM repositories WHERE name = ?", (repo_name,))
        repo_row = cursor.fetchone()

        if not repo_row:
            # Repository not found in DB, output it exactly as is
            logger.warning(f"Repository '{repo_name}' not found in DB cache. Keeping old records.")
            updated_details.append(f"{data['header']}\n\n{data['info_block']}\n\n**Version:**\n\n| Date     | Version        | Stable | Description |\n| -------- | -------------- | ------ | ----------- |\n" + "\n".join([f"| {r['date_str']:<8} | {r['version']:<14} | {r['stable']:<6} | {r['description']} |" for r in data['old_rows']]))
            continue

        repo_id = repo_row['id']

        # Query cached tags
        cursor.execute("SELECT name, commit_date, commit_id, is_stable, is_unstable, raw_json, committer_name FROM tags WHERE repo_id = ? ORDER BY commit_date DESC", (repo_id,))
        tags_rows = cursor.fetchall()

        tags = []
        stable_tags = []
        unstable_tags = []
        superinstaller_tags = []
        for trow in tags_rows:
            tag_date = safe_iso_parse(trow["commit_date"]) or datetime.min
            name = trow["name"]
            t_obj = {
                "name": name,
                "date": tag_date,
                "commit_id": trow["commit_id"][:7] if trow["commit_id"] else "",
                "stable": bool(trow["is_stable"]),
                "unstable": bool(trow["is_unstable"]),
                "committer_name": trow["committer_name"] or ""
            }
            tags.append(t_obj)
            if "CH_" in name:
                superinstaller_tags.append(name)
            elif t_obj["stable"]:
                stable_tags.append(name)
            else:
                unstable_tags.append(name)

        # Record latest stable and unstable tags for Overview table
        latest_stable = stable_tags[0] if stable_tags else ""
        latest_unstable = unstable_tags[0] if unstable_tags else ""
        latest_superinstaller = superinstaller_tags[0] if superinstaller_tags else ""
        committer_name = tags[0]["committer_name"] if tags else ""
        latest = tags[0]["date"].strftime("%y%V") if tags and tags[0]["date"] != datetime.min else ""
        repo_tags_map[repo_name] = (latest_stable, latest_unstable, latest_superinstaller, latest, committer_name)

        # Query cached pull requests
        cursor.execute("SELECT id, title, closed_date, raw_json FROM pull_requests WHERE repo_id = ? ORDER BY closed_date DESC", (repo_id,))
        prs_rows = cursor.fetchall()

        prs = []
        for prow in prs_rows:
            # Parse commit ID from raw_json
            pr_data = json.loads(prow["raw_json"]) if prow["raw_json"] else {}
            last_merge = pr_data.get("lastMergeCommit", {}) if pr_data else {}
            commit_id = last_merge.get("commitId", "")[:7] if last_merge else ""

            pr_title = prow["title"] or ""
            if patch_pr_title_for_release_notes:
                pr_title = patch_pr_title_for_release_notes(prow, cache_db=cache_db, default_title=pr_title)

            prs.append({
                "id": prow["id"],
                "title": pr_title,
                "date": safe_iso_parse(prow["closed_date"]),
                "commit_id": commit_id
            })

        # Group PRs under tags chronologically
        tag_groups = []
        sorted_tags = sorted(tags, key=lambda x: x["date"], reverse=True)
        claimed_pr_ids = set()

        for idx, tag in enumerate(sorted_tags):
            group_prs = []
            next_older_date = sorted_tags[idx+1]["date"] if idx+1 < len(sorted_tags) else datetime.min

            for pr in prs:
                if pr["id"] not in claimed_pr_ids and pr["date"]:
                    if pr["commit_id"] == tag["commit_id"]:
                        group_prs.append(pr)
                        claimed_pr_ids.add(pr["id"])
                    elif next_older_date < pr["date"] <= tag["date"]:
                        group_prs.append(pr)
                        claimed_pr_ids.add(pr["id"])

            group_prs.sort(key=lambda x: (x["date"], x["id"]), reverse=True)
            tag_groups.append({
                "tag": tag,
                "prs": group_prs
            })

        unreleased_prs = [pr for pr in prs if pr["id"] not in claimed_pr_ids]
        unreleased_prs.sort(key=lambda x: (x["date"] if x["date"] else datetime.max, x["id"]), reverse=True)

        new_table_rows = []

        # Print unreleased PRs
        last_date_str = None
        for pr in unreleased_prs:
            pr_date_str = format_date_rev(pr["date"])
            date_col = pr_date_str if pr_date_str != last_date_str else ""
            last_date_str = pr_date_str
            new_table_rows.append({
                "date": date_col,
                "version": "",
                "stable": "",
                "description": f"!{pr['id']}: {pr['title']}",
                "date_obj": pr["date"]
            })

        # Print tagged groups
        for group in tag_groups:
            tag = group["tag"]
            gprs = group["prs"]

            if gprs:
                last_date_str = None
                for idx, pr in enumerate(gprs):
                    pr_date_str = format_date_rev(pr["date"])
                    date_col = pr_date_str if pr_date_str != last_date_str else ""
                    last_date_str = pr_date_str

                    new_table_rows.append({
                        "date": date_col,
                        "version": tag["name"] if idx == 0 else "",
                        "stable": "X" if tag["stable"] and idx == 0 else "",
                        "description": f"!{pr['id']}: {pr['title']}",
                        "date_obj": pr["date"]
                    })

        # Filter new rows: only keep rows >= CUTOFF_DATE
        new_table_rows = [r for r in new_table_rows if r["date_obj"] and r["date_obj"] >= CUTOFF_DATE]
        new_table_rows.sort(key=lambda x: x["date_obj"], reverse=True)

        last_date_str = None
        for r in new_table_rows:
            d_str = format_date_rev(r["date_obj"])
            if d_str == last_date_str:
                r["date"] = ""
            else:
                r["date"] = d_str
                last_date_str = d_str

        all_rows = []
        for r in new_table_rows:
            all_rows.append(f"| {r['date']:<8} | {r['version']:<14} | {r['stable']:<6} | {r['description']:<190} |")

        for r in data["old_rows"]:
            all_rows.append(f"| {r['date_str']:<8} | {r['version']:<14} | {r['stable']:<6} | {r['description']:<190} |")

        table_str = "\n".join(all_rows)
        updated_details.append(f"{data['header']}\n\n{data['info_block']}\n\n**Version:**\n\n| Date     | Version        | Stable | Description |\n| -------- | -------------- | ------ | ----------- |\n{table_str}")

    # 3. Update or populate the Overview Table in header block
    seen_repos = set()
    lines = header_block.split("\n")
    updated_lines = []
    has_table = False

    for line in lines:
        if line.strip().startswith("|") and ("Package" in line or "---" in line):
            has_table = True
        elif line.strip().startswith("|") and not "Package" in line and not "---" in line:
            has_table = True
            cols = [c.strip() for c in line.split("|")[1:-1]]
            if len(cols) >= 4:
                pkg_match = re.search(r'\[([\w\-]+)\]', cols[0])
                owner = cols[5] if len(cols) >= 6 else ""
                if pkg_match:
                    repo_name = pkg_match.group(1)
                    if repo_name in repo_tags_map:
                        seen_repos.add(repo_name)
                        stable, unstable, superinst, latest_change, committer_name = repo_tags_map[repo_name]
                        last_change = get_last_change(unstable, stable, latest_change)
                        if not owner:
                            owner = committer_name
                        line = f"| [{repo_name}](#{repo_name.lower()}) | {superinst:<25} | {unstable:<25} | {stable:<18} | {last_change:<11} | {owner:<11} |"
        updated_lines.append(line)

    if not has_table:
        updated_lines.append("")
        updated_lines.append("| Package | SuperInstaller | Unstable (Nightly) | Stable | Last Change | Owner |")
        updated_lines.append("| ------- | -------------- | ------------------ | ------ | ----------- | ----- |")

    # Add any repositories from DB cache that were not in the Overview table yet
    for repo_name in sorted(repo_tags_map.keys()):
        if repo_name not in seen_repos:
            tag_info = repo_tags_map[repo_name]
            stable, unstable, superinst, latest_change, committer_name = tag_info
            last_change = get_last_change(unstable, stable, latest_change)
            owner = committer_name
            row_line = f"| [{repo_name}](#{repo_name.lower()}) | {superinst:<25} | {unstable:<25} | {stable:<18} | {last_change:<11} | {owner:<11} |"
            updated_lines.append(row_line)

    new_header_block = "\n".join(updated_lines).strip()

    # 4. Save the completed file
    target_dir = os.path.dirname(os.path.abspath(revision_md_path))
    if target_dir:
        os.makedirs(target_dir, exist_ok=True)

    final_output = new_header_block + "\n\n" + "\n\n".join(updated_details) + "\n"
    with open(revision_md_path, "w", encoding="utf-8") as f:
        f.write(final_output)

    logger.info(f"Successfully generated and updated {revision_md_path} from TFS database cache!")
    conn.close()

    # Export to DOCX
    docx_path = os.path.splitext(revision_md_path)[0] + ".docx"
    try:
        export_to_docx(revision_md_path, docx_path)
        logger.info(f"Successfully exported {docx_path}!")
    except Exception as e:
        logger.error(f"Error exporting Word document: {e}")

    return True

def export_to_docx(md_path, docx_path):
    from docx import Document
    from docx.shared import Inches, Pt
    
    doc = Document()
    
    # Set standard page margins (1 inch)
    for section in doc.sections:
        section.top_margin = Inches(1)
        section.bottom_margin = Inches(1)
        section.left_margin = Inches(1)
        section.right_margin = Inches(1)

    with open(md_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
        
    in_table = False
    table_headers = []
    table_rows = []
    
    def flush_table():
        nonlocal in_table, table_headers, table_rows
        if not in_table:
            return
        if not table_headers:
            in_table = False
            table_rows = []
            return
            
        num_cols = len(table_headers)
        num_rows = len(table_rows) + 1
        table = doc.add_table(rows=num_rows, cols=num_cols)
        # Apply standard clean styling
        table.style = "Light Shading Accent 1"
        
        # Populate headers
        hdr_cells = table.rows[0].cells
        for idx, header in enumerate(table_headers):
            hdr_cells[idx].text = header
            for paragraph in hdr_cells[idx].paragraphs:
                for run in paragraph.runs:
                    run.font.bold = True
                    
        # Populate data rows
        for r_idx, row_data in enumerate(table_rows):
            row_cells = table.rows[r_idx + 1].cells
            for c_idx, val in enumerate(row_data):
                if c_idx < len(row_cells):
                    row_cells[c_idx].text = val
                    
        doc.add_paragraph()
        in_table = False
        table_headers = []
        table_rows = []

    idx = 0
    while idx < len(lines):
        line = lines[idx]
        stripped = line.strip()
        
        if stripped.startswith("|"):
            if "---" in stripped:
                idx += 1
                continue
            cols = [c.strip() for c in stripped.split("|")[1:-1]]
            if not in_table:
                in_table = True
                table_headers = cols
            else:
                table_rows.append(cols)
            idx += 1
            continue
        else:
            if in_table:
                flush_table()
                
        if not stripped:
            idx += 1
            continue
            
        if stripped.startswith("# "):
            doc.add_heading(stripped[2:], level=1)
        elif stripped.startswith("## "):
            doc.add_heading(stripped[3:], level=2)
        elif stripped.startswith("### "):
            doc.add_heading(stripped[4:], level=3)
        elif stripped.startswith("- ") or stripped.startswith("* "):
            doc.add_paragraph(stripped[2:], style="List Bullet")
        else:
            p = doc.add_paragraph()
            parts = re.split(r"(\*\*.*?\*\*)", stripped)
            for part in parts:
                if part.startswith("**") and part.endswith("**"):
                    run = p.add_run(part[2:-2])
                    run.font.bold = True
                else:
                    p.add_run(part)
        idx += 1
        
    if in_table:
        flush_table()

    target_dir = os.path.dirname(os.path.abspath(docx_path))
    if target_dir:
        os.makedirs(target_dir, exist_ok=True)

    doc.save(docx_path)

