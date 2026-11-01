# -*- coding: UTF-8 -*-
"""
Repository Submodule URL Auditor & Local Backup / Standby Migration Service.

Implements:
- Milestone 1: Submodule `.gitmodules` discovery, URL classification
  (`RELATIVE_OK`, `ABSOLUTE_SAME_PROJECT`, `ABSOLUTE_CROSS_PROJECT`, `EXTERNAL_OR_MISSING`),
  diff generation, and interactive/automated conversion to relative paths (`../<RepoName>`).
- Milestone 2 (Path 1): `LocalBackupManager` supporting `worktree` (`--recurse-submodules`),
  `mirror` (`--mirror`), and `both` modes with transient HTTP Basic Auth headers,
  topological submodule ordering, delta push-ID standby checks, integrity verification,
  SQLite cache snapshot export, and `backup_manifest.json` generation.
"""

import base64
import difflib
import json
import logging
import os
import re
import shutil
import sqlite3
import subprocess
import time
import urllib.error
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

logger = logging.getLogger(__name__)

VALID_BACKUP_MODES = ("worktree", "mirror", "both")
DEFAULT_GIT_TIMEOUT_SECONDS = 3600  # 60 minutes per git step (0 = unlimited)

CLASSIFICATION_RELATIVE_OK = "RELATIVE_OK"
CLASSIFICATION_ABSOLUTE_SAME_PROJECT = "ABSOLUTE_SAME_PROJECT"
CLASSIFICATION_ABSOLUTE_CROSS_PROJECT = "ABSOLUTE_CROSS_PROJECT"
CLASSIFICATION_EXTERNAL_OR_MISSING = "EXTERNAL_OR_MISSING"


def parse_gitmodules_content(content: str) -> List[Dict[str, Any]]:
    """
    Parses the raw text of a `.gitmodules` file into a list of submodule entries.

    Args:
        content (str): Raw `.gitmodules` file content.

    Returns:
        List[Dict[str, Any]]: List of dicts with keys `'name'`, `'path'`, `'url'`, and optional `'branch'`.
    """
    if not content or not isinstance(content, str):
        return []

    submodules: List[Dict[str, Any]] = []
    current: Optional[Dict[str, Any]] = None

    for raw_line in content.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith(";"):
            continue

        sec_match = re.match(r'^\[submodule\s+"([^"]+)"\]', stripped, re.IGNORECASE)
        if sec_match:
            if current and (current.get("path") or current.get("url")):
                submodules.append(current)
            current = {
                "name": sec_match.group(1).strip(),
                "path": "",
                "url": "",
                "branch": "",
            }
            continue

        if "=" in stripped:
            if current is None:
                current = {"name": "", "path": "", "url": "", "branch": ""}
            key, val = stripped.split("=", 1)
            k = key.strip().lower()
            v = val.strip()
            if k in ("path", "url", "branch"):
                current[k] = v
            else:
                current[k] = v

    if current and (current.get("path") or current.get("url")):
        if not current.get("name"):
            current["name"] = current.get("path", "")
        submodules.append(current)

    return submodules


def _strip_git_suffix(repo_name: str) -> str:
    """Strips trailing `.git` and slashes from a repository name."""
    cleaned = str(repo_name or "").strip().rstrip("/")
    if cleaned.lower().endswith(".git"):
        cleaned = cleaned[:-4]
    return cleaned


def classify_submodule_url(
    url: str,
    parent_repo_name: str = "",
    project_id: str = "",
    known_repo_names: Optional[Iterable[str]] = None,
    tfs_base_url: str = "",
) -> Dict[str, Any]:
    """
    Classifies a `.gitmodules` submodule URL and computes a proposed relative path (`../<RepoName>`)
    when applicable.

    Classifications:
    - `RELATIVE_OK`: Already uses a clean relative sibling path (`../<RepoName>` or `../<RepoName>.git`)
      and target repository exists (when `known_repo_names` is provided).
    - `ABSOLUTE_SAME_PROJECT`: Hardcoded TFS URL (or TFS `/_git/` relative traversal) pointing to
      a repository in the same project. Recommended conversion: `../<RepoName>`.
    - `ABSOLUTE_CROSS_PROJECT`: Hardcoded TFS URL pointing to a different project on the TFS server.
      Recommended conversion: `../<RepoName>` (when flattened into one target org/folder).
    - `EXTERNAL_OR_MISSING`: Points to an external server (e.g., GitHub) or a repository not found
      in the project's known repositories.

    Args:
        url (str): The submodule URL from `.gitmodules`.
        parent_repo_name (str, optional): Name of the parent repository.
        project_id (str, optional): Current TFS project name or ID.
        known_repo_names (Iterable[str], optional): Known active repository names in the project.
        tfs_base_url (str, optional): Base URL of the TFS server/collection.

    Returns:
        Dict[str, Any]: Classification dictionary containing:
            - `current_url` (str)
            - `classification` (str)
            - `proposed_relative_url` (str)
            - `target_repo_name` (str)
            - `target_project` (str)
            - `target_repo_exists` (bool)
    """
    raw_url = str(url or "").strip()
    known_map: Dict[str, str] = {}
    if known_repo_names is not None:
        for rname in known_repo_names:
            if rname:
                clean_r = _strip_git_suffix(str(rname))
                known_map[clean_r.lower()] = clean_r

    has_known_list = known_repo_names is not None
    clean_project = urllib.parse.unquote(str(project_id or "").strip())

    # 1. Check relative URLs (starts with ./ or ../)
    is_relative = (
        (raw_url.startswith("../") or raw_url.startswith("./"))
        and "://" not in raw_url
        and not raw_url.startswith("git@")
    )

    if is_relative:
        norm_rel = raw_url.replace("\\", "/").rstrip("/")
        # Check if relative URL still embeds TFS-specific /_git/ routing (e.g. ../../Proj/_git/Repo)
        git_Marker = re.search(r'(?:/([^/]+))?/_(?:git|ssh)/([^/?#]+)$', norm_rel, re.IGNORECASE)
        if git_Marker:
            rel_proj = urllib.parse.unquote(git_Marker.group(1) or "")
            raw_target = urllib.parse.unquote(git_Marker.group(2) or "")
            clean_target = _strip_git_suffix(raw_target)
            canonical_target = known_map.get(clean_target.lower(), clean_target)
            exists = (clean_target.lower() in known_map) if has_known_list else True
            if rel_proj and clean_project and rel_proj.lower() != clean_project.lower():
                return {
                    "current_url": raw_url,
                    "classification": CLASSIFICATION_ABSOLUTE_CROSS_PROJECT,
                    "proposed_relative_url": f"../{canonical_target}",
                    "target_repo_name": canonical_target,
                    "target_project": rel_proj,
                    "target_repo_exists": exists,
                }
            return {
                "current_url": raw_url,
                "classification": CLASSIFICATION_ABSOLUTE_SAME_PROJECT,
                "proposed_relative_url": f"../{canonical_target}",
                "target_repo_name": canonical_target,
                "target_project": rel_proj or clean_project,
                "target_repo_exists": exists,
            }

        # Standard sibling relative path: ../RepoName or ../RepoName.git or ./RepoName
        parts = [p for p in norm_rel.split("/") if p and p != "."]
        leaf = urllib.parse.unquote(parts[-1]) if parts else ""
        clean_target = _strip_git_suffix(leaf)
        canonical_target = known_map.get(clean_target.lower(), clean_target)
        exists = (clean_target.lower() in known_map) if has_known_list else bool(clean_target)

        # Clean sibling path is ../<RepoName> or ../<RepoName>.git
        is_direct_sibling = (len(parts) == 2 and parts[0] == "..")
        if is_direct_sibling and exists:
            return {
                "current_url": raw_url,
                "classification": CLASSIFICATION_RELATIVE_OK,
                "proposed_relative_url": raw_url,
                "target_repo_name": canonical_target,
                "target_project": clean_project,
                "target_repo_exists": True,
            }
        elif is_direct_sibling and not exists:
            return {
                "current_url": raw_url,
                "classification": CLASSIFICATION_EXTERNAL_OR_MISSING,
                "proposed_relative_url": f"../{canonical_target}" if canonical_target else raw_url,
                "target_repo_name": canonical_target,
                "target_project": clean_project,
                "target_repo_exists": False,
            }
        else:
            # Deeper relative path like ../../OtherProj/Repo
            return {
                "current_url": raw_url,
                "classification": CLASSIFICATION_ABSOLUTE_SAME_PROJECT if exists else CLASSIFICATION_ABSOLUTE_CROSS_PROJECT,
                "proposed_relative_url": f"../{canonical_target}" if canonical_target else raw_url,
                "target_repo_name": canonical_target,
                "target_project": clean_project,
                "target_repo_exists": exists,
            }

    # 2. Check Absolute URLs (http://, https://, ssh://, git@, file://)
    # Match TFS / Azure DevOps pattern: .../<project>/_git/<repo> or .../_git/<repo>
    tfs_match = re.search(r'(?:/([^/:]+))?/_(?:git|ssh)/([^/?#]+?)(?:\.git)?/?$', raw_url, re.IGNORECASE)
    if tfs_match:
        url_proj = urllib.parse.unquote(tfs_match.group(1) or "")
        # Ignore collection prefix if URL was /tfs/DefaultCollection/_git/Repo
        if url_proj.lower() in ("defaultcollection", "tfs", "collection"):
            url_proj = ""
        raw_target = urllib.parse.unquote(tfs_match.group(2) or "")
        clean_target = _strip_git_suffix(raw_target)
        canonical_target = known_map.get(clean_target.lower(), clean_target)
        exists = (clean_target.lower() in known_map) if has_known_list else True

        same_proj = (
            not url_proj
            or not clean_project
            or url_proj.lower() == clean_project.lower()
        )
        if same_proj:
            if has_known_list and not exists:
                return {
                    "current_url": raw_url,
                    "classification": CLASSIFICATION_EXTERNAL_OR_MISSING,
                    "proposed_relative_url": f"../{canonical_target}",
                    "target_repo_name": canonical_target,
                    "target_project": url_proj or clean_project,
                    "target_repo_exists": False,
                }
            return {
                "current_url": raw_url,
                "classification": CLASSIFICATION_ABSOLUTE_SAME_PROJECT,
                "proposed_relative_url": f"../{canonical_target}",
                "target_repo_name": canonical_target,
                "target_project": url_proj or clean_project,
                "target_repo_exists": exists,
            }
        else:
            return {
                "current_url": raw_url,
                "classification": CLASSIFICATION_ABSOLUTE_CROSS_PROJECT,
                "proposed_relative_url": f"../{canonical_target}",
                "target_repo_name": canonical_target,
                "target_project": url_proj,
                "target_repo_exists": exists,
            }

    # 3. Check if host matches tfs_base_url or target repo is in known_map
    parsed_url = urllib.parse.urlparse(raw_url)
    path_Clean = urllib.parse.unquote(parsed_url.path or "").rstrip("/")
    leaf_name = _strip_git_suffix(path_Clean.split("/")[-1]) if path_Clean else ""

    tfs_host = ""
    if tfs_base_url:
        try:
            tfs_host = (urllib.parse.urlparse(tfs_base_url).hostname or "").lower()
        except Exception:
            tfs_host = ""

    url_host = (parsed_url.hostname or "").lower()
    is_same_host = bool(tfs_host and url_host and tfs_host == url_host)

    if is_same_host and leaf_name:
        canonical_target = known_map.get(leaf_name.lower(), leaf_name)
        exists = (leaf_name.lower() in known_map) if has_known_list else True
        return {
            "current_url": raw_url,
            "classification": CLASSIFICATION_ABSOLUTE_SAME_PROJECT if exists else CLASSIFICATION_ABSOLUTE_CROSS_PROJECT,
            "proposed_relative_url": f"../{canonical_target}",
            "target_repo_name": canonical_target,
            "target_project": clean_project,
            "target_repo_exists": exists,
        }

    # External or unknown URL
    return {
        "current_url": raw_url,
        "classification": CLASSIFICATION_EXTERNAL_OR_MISSING,
        "proposed_relative_url": f"../{known_map[leaf_name.lower()]}" if (leaf_name and leaf_name.lower() in known_map) else "",
        "target_repo_name": leaf_name,
        "target_project": "",
        "target_repo_exists": bool(leaf_name and leaf_name.lower() in known_map),
    }


def rewrite_gitmodules_to_relative(
    content: str,
    parent_repo_name: str = "",
    project_id: str = "",
    known_repo_names: Optional[Iterable[str]] = None,
    tfs_base_url: str = "",
    include_cross_project: bool = True,
    custom_replacements: Optional[Dict[str, str]] = None,
) -> Tuple[str, List[Dict[str, Any]], str]:
    """
    Rewrites non-relative submodule URLs in a `.gitmodules` file content string to relative URLs
    (`../<RepoName>`), preserving comments, indentation, line endings, and extra keys.

    Args:
        content (str): Original `.gitmodules` text.
        parent_repo_name (str, optional): Parent repository name for diff headers.
        project_id (str, optional): Current TFS project ID/name.
        known_repo_names (Iterable[str], optional): Known repository names in the project.
        tfs_base_url (str, optional): Base TFS server URL.
        include_cross_project (bool, optional): Whether to also rewrite `ABSOLUTE_CROSS_PROJECT` URLs. Defaults to True.
        custom_replacements (Dict[str, str], optional): Optional explicit map of `{submodule_path_or_url: new_url}`.

    Returns:
        Tuple[str, List[Dict[str, Any]], str]:
            - `new_content` (str): Updated `.gitmodules` text.
            - `changes` (list): List of change dicts (`submodule_name`, `submodule_path`, `old_url`, `new_url`, `classification`).
            - `diff_text` (str): Unified diff string comparing original and updated `.gitmodules`.
    """
    if not content or not isinstance(content, str):
        return content or "", [], ""

    allowed_classifications = {CLASSIFICATION_ABSOLUTE_SAME_PROJECT}
    if include_cross_project:
        allowed_classifications.add(CLASSIFICATION_ABSOLUTE_CROSS_PROJECT)

    # First pass: parse sections so we know each submodule's name and path even if `url` appears before `path`
    parsed_subs = parse_gitmodules_content(content)
    sub_by_name = {s.get("name", ""): s for s in parsed_subs if s.get("name")}

    lines = content.splitlines(keepends=True)
    new_lines: List[str] = []
    changes: List[Dict[str, Any]] = []

    current_sec_name = ""
    current_path = ""

    for line in lines:
        stripped = line.strip()
        sec_match = re.match(r'^\[submodule\s+"([^"]+)"\]', stripped, re.IGNORECASE)
        if sec_match:
            current_sec_name = sec_match.group(1).strip()
            current_path = sub_by_name.get(current_sec_name, {}).get("path", "")
            new_lines.append(line)
            continue

        path_match = re.match(r'^(\s*path\s*=\s*)(.+?)(\r?\n?)$', line, re.IGNORECASE)
        if path_match:
            current_path = path_match.group(2).strip()
            new_lines.append(line)
            continue

        url_match = re.match(r'^(\s*url\s*=\s*)(.+?)(\r?\n?)$', line, re.IGNORECASE)
        if url_match:
            prefix, old_url_raw, line_ending = url_match.group(1), url_match.group(2), url_match.group(3)
            old_url = old_url_raw.strip()

            info = classify_submodule_url(
                old_url,
                parent_repo_name=parent_repo_name,
                project_id=project_id,
                known_repo_names=known_repo_names,
                tfs_base_url=tfs_base_url,
            )

            target_new_url = ""
            if custom_replacements:
                if current_path and current_path in custom_replacements:
                    target_new_url = custom_replacements[current_path]
                elif current_sec_name and current_sec_name in custom_replacements:
                    target_new_url = custom_replacements[current_sec_name]
                elif old_url in custom_replacements:
                    target_new_url = custom_replacements[old_url]

            if not target_new_url and info["classification"] in allowed_classifications:
                target_new_url = info.get("proposed_relative_url", "")

            if target_new_url and target_new_url != old_url:
                new_lines.append(f"{prefix}{target_new_url}{line_ending}")
                changes.append({
                    "submodule_name": current_sec_name or current_path,
                    "submodule_path": current_path or current_sec_name,
                    "old_url": old_url,
                    "new_url": target_new_url,
                    "classification": info["classification"],
                })
            else:
                new_lines.append(line)
            continue

        new_lines.append(line)

    new_content = "".join(new_lines)
    diff_text = ""
    if new_content != content:
        label = f"{parent_repo_name}/.gitmodules" if parent_repo_name else ".gitmodules"
        diff_lines = difflib.unified_diff(
            content.splitlines(keepends=True),
            new_content.splitlines(keepends=True),
            fromfile=f"a/{label}",
            tofile=f"b/{label}",
        )
        diff_text = "".join(diff_lines)

    return new_content, changes, diff_text


class SubmoduleAuditor:
    """
    Audits `.gitmodules` across all repositories in an Azure DevOps / TFS project,
    identifies hardcoded absolute TFS URLs vs. portable relative URLs, and assists
    with interactive or automated conversion to relative URLs (`../<RepoName>`).
    """

    def __init__(self, info_handler=None, project_id: str = "", cache_db=None):
        self.info_handler = info_handler
        self.project_id = project_id
        self.cache_db = cache_db

    def audit_project_submodules(
        self,
        repos: Optional[List[Dict[str, Any]]] = None,
        branch_name: Optional[str] = None,
        progress_callback: Optional[Callable] = None,
        max_workers: int = 8,
    ) -> Dict[str, Any]:
        """
        Scans `.gitmodules` across all enabled repositories in the project, classifies each
        submodule URL, computes proposed relative URLs and diffs, and persists audit entries
        into `cache_db`.

        Args:
            repos (List[Dict], optional): Pre-fetched list of repository info dicts. If None,
                                          fetched via `info_handler.get_repositories(project_id)`
                                          or loaded from `cache_db`.
            branch_name (str, optional): Specific branch to inspect (defaults to each repo's defaultBranch).
            progress_callback (Callable, optional): Progress callback `(pct, message)` or `(message, cur, total)`.
            max_workers (int, optional): Parallel workers for querying `.gitmodules`. Defaults to 8.

        Returns:
            Dict[str, Any]: Comprehensive project submodule audit summary.
        """
        tfs_base_url = getattr(self.info_handler, "url", "") if self.info_handler else ""

        if repos is None:
            if self.info_handler and self.project_id:
                try:
                    raw_repos = self.info_handler.get_repositories(self.project_id)
                    repos = [
                        r for r in raw_repos
                        if not r.get("isDisabled", False)
                        and "CANCEL" not in r.get("name", "")
                        and "DEPRECATE" not in r.get("name", "")
                    ]
                except Exception as e:
                    logger.warning("Could not fetch live repositories for submodule audit, falling back to cache: %s", e)

            if repos is None and self.cache_db:
                with self.cache_db._connection() as conn:
                    rows = conn.execute(
                        "SELECT id, name, default_branch, web_url, is_disabled FROM repositories WHERE is_disabled = 0 ORDER BY name"
                    ).fetchall()
                    repos = [
                        {
                            "id": r["id"],
                            "name": r["name"],
                            "defaultBranch": r["default_branch"],
                            "webUrl": r["web_url"],
                            "isDisabled": bool(r["is_disabled"]),
                        }
                        for r in rows
                    ]

        repos = list(repos or [])
        known_repo_names = [r.get("name", "") for r in repos if r.get("name")]
        total = len(repos)
        logger.info("🔍 Scanning .gitmodules across %d repositories in project '%s'...", total, self.project_id or "default")

        def _notify(cur: int, r_name: str):
            pct = int((cur / total) * 100) if total > 0 else 100
            msg = f"Checking .gitmodules in {r_name} ({cur}/{total})..."
            if hasattr(progress_callback, "report_progress"):
                try:
                    progress_callback.report_progress(pct, msg)
                    return
                except Exception:
                    pass
            if not callable(progress_callback):
                return
            try:
                progress_callback(pct, msg)
            except TypeError:
                try:
                    progress_callback(msg, cur, total)
                except Exception:
                    pass

        def _audit_single_repo(repo_dict: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
            repo_id = repo_dict.get("id", "")
            repo_name = repo_dict.get("name", "")
            target_branch = (
                branch_name
                or (repo_dict.get("defaultBranch") or repo_dict.get("default_branch") or "").replace("refs/heads/", "")
            )

            content = ""
            if self.info_handler and self.project_id and repo_id:
                params = {"$format": "text"}
                if target_branch:
                    params["versionDescriptor.version"] = target_branch
                    params["versionDescriptor.versionType"] = "branch"

                def _fetch_gitmodules(req_params):
                    try:
                        return self.info_handler.get_repository_items(
                            self.project_id, repo_id, ".gitmodules",
                            params=req_params, raw_text=True, suppress_error_log=True
                        )
                    except TypeError:
                        return self.info_handler.get_repository_items(
                            self.project_id, repo_id, ".gitmodules",
                            params=req_params, raw_text=True
                        )

                try:
                    res = _fetch_gitmodules(params)
                    if isinstance(res, str):
                        content = res
                except urllib.error.HTTPError as he:
                    if he.code != 404 and target_branch:
                        # Fallback to default item query without versionDescriptor
                        try:
                            res = _fetch_gitmodules({"$format": "text"})
                            if isinstance(res, str):
                                content = res
                        except Exception:
                            pass
                except Exception:
                    pass

            parsed = parse_gitmodules_content(content) if content else []
            # If offline and no content from API, check cached submodules in DB
            if not parsed and not self.info_handler and self.cache_db and repo_id:
                with self.cache_db._connection() as conn:
                    sub_rows = conn.execute(
                        "SELECT path, url, raw_json FROM submodules WHERE parent_repo_id = ?", (repo_id,)
                    ).fetchall()
                    for sr in sub_rows:
                        parsed.append({
                            "name": sr["path"],
                            "path": sr["path"],
                            "url": sr["url"],
                        })

            audited_entries: List[Dict[str, Any]] = []
            now_iso = datetime.now(timezone.utc).isoformat()

            for sub in parsed:
                cls_info = classify_submodule_url(
                    sub.get("url", ""),
                    parent_repo_name=repo_name,
                    project_id=self.project_id,
                    known_repo_names=known_repo_names,
                    tfs_base_url=tfs_base_url,
                )
                entry = {
                    "parent_repo_id": repo_id,
                    "parent_repo_name": repo_name,
                    "submodule_name": sub.get("name") or sub.get("path") or "",
                    "submodule_path": sub.get("path") or "",
                    "current_url": sub.get("url") or "",
                    "classification": cls_info["classification"],
                    "proposed_relative_url": cls_info["proposed_relative_url"],
                    "target_repo_name": cls_info["target_repo_name"],
                    "target_project": cls_info["target_project"],
                    "target_repo_exists": cls_info["target_repo_exists"],
                    "audited_at": now_iso,
                }
                audited_entries.append(entry)

            new_content, changes, diff_text = rewrite_gitmodules_to_relative(
                content,
                parent_repo_name=repo_name,
                project_id=self.project_id,
                known_repo_names=known_repo_names,
                tfs_base_url=tfs_base_url,
            )

            repo_report = {
                "repo_id": repo_id,
                "repo_name": repo_name,
                "branch": target_branch or "default",
                "submodules": audited_entries,
                "needs_conversion": len(changes) > 0,
                "original_content": content,
                "proposed_content": new_content,
                "diff": diff_text,
                "changes": changes,
            }
            return repo_name, repo_report

        repo_reports: Dict[str, Dict[str, Any]] = {}
        completed = 0

        if total > 0:
            with ThreadPoolExecutor(max_workers=min(max_workers, max(1, total))) as executor:
                futs = {executor.submit(_audit_single_repo, r): r for r in repos}
                for fut in as_completed(futs):
                    r = futs[fut]
                    completed += 1
                    _notify(completed, r.get("name", ""))
                    r_name, r_rep = fut.result()
                    repo_reports[r_name] = r_rep
                    if self.cache_db and r_rep.get("repo_id"):
                        try:
                            # Persist both submodules and submodule_audit
                            if r_rep["submodules"]:
                                sub_list = [
                                    {
                                        "name": s["submodule_name"],
                                        "path": s["submodule_path"],
                                        "url": s["current_url"],
                                        "info": {"commitId": ""},
                                    }
                                    for s in r_rep["submodules"]
                                ]
                                self.cache_db.save_submodules(r_rep["repo_id"], sub_list)
                            self.cache_db.save_submodule_audit(
                                r_rep["repo_id"], r_name, r_rep["submodules"]
                            )
                        except Exception as db_err:
                            logger.warning("Failed to save submodule audit for %s: %s", r_name, db_err)

        total_subs = 0
        rel_ok = 0
        needs_conv = 0
        ext_or_missing = 0
        repos_with_subs = 0
        repos_needing_conv = 0

        for r_name in sorted(repo_reports.keys()):
            rep = repo_reports[r_name]
            subs = rep.get("submodules", [])
            if subs:
                repos_with_subs += 1
            if rep.get("needs_conversion"):
                repos_needing_conv += 1
            for s in subs:
                total_subs += 1
                c = s.get("classification")
                if c == CLASSIFICATION_RELATIVE_OK:
                    rel_ok += 1
                elif c in (CLASSIFICATION_ABSOLUTE_SAME_PROJECT, CLASSIFICATION_ABSOLUTE_CROSS_PROJECT):
                    needs_conv += 1
                else:
                    ext_or_missing += 1

        logger.info(
            "🏁 Submodule audit complete: %d repositories scanned, %d submodule(s) found (%d relative OK, %d needing conversion).",
            total, total_subs, rel_ok, needs_conv,
        )

        return {
            "project_id": self.project_id,
            "total_repos_scanned": total,
            "repos_with_submodules": repos_with_subs,
            "repos_needing_conversion": repos_needing_conv,
            "total_submodules": total_subs,
            "relative_ok_count": rel_ok,
            "needs_conversion_count": needs_conv,
            "external_or_missing_count": ext_or_missing,
            "repositories": dict(sorted(repo_reports.items())),
        }

    def convert_submodules_to_relative_in_tfs(
        self,
        audit_report: Optional[Dict[str, Any]] = None,
        repo_names: Optional[Iterable[str]] = None,
        branch_name: Optional[str] = None,
        dry_run: bool = False,
        auto_confirm: bool = False,
        prompt_callback: Optional[Callable[[str, str, List[Dict[str, Any]]], bool]] = None,
    ) -> Dict[str, Any]:
        """
        Converts hardcoded TFS submodule URLs in `.gitmodules` to relative URLs (`../<RepoName>`)
        and pushes the commit to TFS (unless `dry_run=True`), prompting the user per repository
        unless `auto_confirm=True`.

        Args:
            audit_report (Dict, optional): Result from `audit_project_submodules()`. If None, runs audit first.
            repo_names (Iterable[str], optional): Subset of repository names to convert.
            branch_name (str, optional): Target branch to push `.gitmodules` commit to (defaults to repo's branch).
            dry_run (bool, optional): If True, computes diffs without pushing to TFS. Defaults to False.
            auto_confirm (bool, optional): If True, skips user confirmation prompt. Defaults to False.
            prompt_callback (Callable, optional): Function `(repo_name, diff_text, changes) -> bool` asking user.

        Returns:
            Dict[str, Any]: Summary with `'updated_repos'`, `'skipped_repos'`, `'failed_repos'`, and `'details'`.
        """
        if audit_report is None:
            audit_report = self.audit_project_submodules(branch_name=branch_name)

        target_filter = {r.strip() for r in repo_names if r} if repo_names else None
        repos_map = audit_report.get("repositories", {})

        updated: List[str] = []
        skipped: List[str] = []
        failed: List[Dict[str, str]] = []
        details: Dict[str, Any] = {}

        for r_name, rep in repos_map.items():
            if target_filter is not None and r_name not in target_filter:
                continue
            if not rep.get("needs_conversion"):
                continue

            diff_text = rep.get("diff", "")
            changes = rep.get("changes", [])
            new_content = rep.get("proposed_content", "")
            repo_id = rep.get("repo_id", "")
            target_branch = branch_name or rep.get("branch") or "dev"

            proceed = auto_confirm
            if not proceed and callable(prompt_callback):
                proceed = bool(prompt_callback(r_name, diff_text, changes))

            if not proceed:
                skipped.append(r_name)
                details[r_name] = {"status": "SKIPPED", "changes": changes, "diff": diff_text}
                continue

            if dry_run:
                updated.append(r_name)
                details[r_name] = {"status": "DRY_RUN", "changes": changes, "diff": diff_text}
                continue

            if not self.info_handler:
                failed.append({"repo_name": r_name, "error": "No active TFS info_handler configured"})
                details[r_name] = {"status": "FAILED", "error": "No active TFS info_handler configured"}
                continue

            try:
                commit_msg = (
                    f"Convert {len(changes)} submodule URL(s) in .gitmodules to relative paths"
                )
                push_res = self.info_handler.push_file_update(
                    project_id=self.project_id,
                    repo_id=repo_id,
                    branch_name=target_branch,
                    file_path="/.gitmodules",
                    new_content=new_content,
                    commit_message=commit_msg,
                )
                updated.append(r_name)
                details[r_name] = {
                    "status": "UPDATED",
                    "branch": target_branch,
                    "changes": changes,
                    "push_id": push_res.get("pushId") if isinstance(push_res, dict) else None,
                }
                # Update cached audit state to RELATIVE_OK
                if self.cache_db and repo_id:
                    updated_audit = []
                    for s in rep.get("submodules", []):
                        s_copy = dict(s)
                        if s_copy.get("classification") in (
                            CLASSIFICATION_ABSOLUTE_SAME_PROJECT,
                            CLASSIFICATION_ABSOLUTE_CROSS_PROJECT,
                        ):
                            s_copy["current_url"] = s_copy.get("proposed_relative_url") or s_copy["current_url"]
                            s_copy["classification"] = CLASSIFICATION_RELATIVE_OK
                        updated_audit.append(s_copy)
                    self.cache_db.save_submodule_audit(repo_id, r_name, updated_audit)
            except Exception as e:
                logger.error("Failed to push .gitmodules update for %s: %s", r_name, e)
                failed.append({"repo_name": r_name, "error": str(e)})
                details[r_name] = {"status": "FAILED", "error": str(e)}

        return {
            "project_id": self.project_id,
            "dry_run": dry_run,
            "updated_repos": updated,
            "skipped_repos": skipped,
            "failed_repos": failed,
            "details": details,
        }


def sort_repos_topologically(
    repos: List[Dict[str, Any]],
    submodule_map: Optional[Dict[str, List[str]]] = None,
) -> List[Dict[str, Any]]:
    """
    Sorts repositories topologically so leaf repositories (submodules) are processed
    before the parent repositories that depend on them.
    Gracefully handles cyclic or external dependencies.

    Args:
        repos (List[Dict]): List of repository dictionaries (`'name'`, `'id'`, etc.).
        submodule_map (Dict[str, List[str]], optional): Map of `{parent_repo_name: [child_repo_name, ...]}`.

    Returns:
        List[Dict[str, Any]]: Topologically ordered list of repository dicts.
    """
    repo_by_lower: Dict[str, Dict[str, Any]] = {}
    for r in repos:
        r_name = r.get("name", "")
        if r_name:
            repo_by_lower[_strip_git_suffix(r_name).lower()] = r

    deps_by_lower: Dict[str, List[str]] = {k: [] for k in repo_by_lower}
    if submodule_map:
        for parent_name, child_names in submodule_map.items():
            p_key = _strip_git_suffix(parent_name).lower()
            if p_key in deps_by_lower:
                for c_name in (child_names or []):
                    c_key = _strip_git_suffix(c_name).lower()
                    if c_key in repo_by_lower and c_key != p_key and c_key not in deps_by_lower[p_key]:
                        deps_by_lower[p_key].append(c_key)

    visited: Dict[str, int] = {}  # 0 = unvisited, 1 = visiting, 2 = visited
    ordered: List[Dict[str, Any]] = []

    def _visit(key: str):
        state = visited.get(key, 0)
        if state == 2:
            return
        if state == 1:
            # Cycle detected; break cycle gracefully
            return
        visited[key] = 1
        for child_key in sorted(deps_by_lower.get(key, [])):
            _visit(child_key)
        visited[key] = 2
        ordered.append(repo_by_lower[key])

    for key in sorted(repo_by_lower.keys()):
        _visit(key)

    return ordered


def build_git_auth_args(
    pat: str = "",
    tfs_project_git_base: str = "",
    local_override_base: str = "",
) -> List[str]:
    """
    Builds ephemeral Git CLI `-c` configuration arguments so PAT credentials
    are never persisted to `.git/config` on disk, SSL verification is relaxed
    for self-signed TFS certificates, `safe.directory=*` is enabled for network/UNC
    shares, and local/file submodule protocols work.

    Args:
        pat (str, optional): Personal Access Token for HTTP Basic auth.
        tfs_project_git_base (str, optional): Original TFS project `/_git/` base URL.
        local_override_base (str, optional): Optional URL base to substitute via `url.<base>.insteadOf`.

    Returns:
        List[str]: List of `-c <key>=<value>` arguments for `git`.
    """
    args = [
        "-c", "safe.directory=*",
        "-c", "http.sslVerify=false",
        "-c", "protocol.file.allow=always",
    ]
    if pat:
        encoded = base64.b64encode(f":{pat}".encode("utf-8")).decode("utf-8")
        args.extend(["-c", f"http.extraHeader=Authorization: Basic {encoded}"])

    if tfs_project_git_base and local_override_base:
        base_src = tfs_project_git_base.rstrip("/") + "/"
        base_dst = local_override_base.rstrip("/") + "/"
        if base_src != base_dst:
            args.extend(["-c", f"url.{base_dst}.insteadOf={base_src}"])

    return args


def _candidate_safe_directory_patterns(raw_path: str) -> List[str]:
    """
    Produces normalized Git `safe.directory` entries for a local or mapped-network/UNC path,
    including `%(prefix)///server/share/...` forms required by Git for Windows on UNC shares.
    """
    if not raw_path or not str(raw_path).strip():
        return []
    raw_s = str(raw_path).strip().strip("'\"")
    if raw_s == "*":
        return ["*"]

    out: List[str] = []

    def _add(val: str):
        if val and val not in out:
            out.append(val)

    variants = [raw_s]
    try:
        abs_p = os.path.abspath(raw_s)
        if abs_p not in variants:
            variants.append(abs_p)
    except Exception:
        pass
    try:
        real_p = os.path.realpath(raw_s)
        if real_p not in variants:
            variants.append(real_p)
    except Exception:
        pass

    for v in variants:
        if v.startswith("%(prefix)/"):
            _add(v)
            continue
        norm = v.replace("\\", "/").rstrip("/")
        if not norm:
            continue
        _add(norm)
        # If UNC path (//server/share/...), Git on Windows requires '%(prefix)///server/share/...'
        if norm.startswith("//"):
            _add(f"%(prefix)/{norm}")
            _add(f"%(prefix)/{norm}/*")
        else:
            _add(f"{norm}/*")

    return out


def extract_dubious_ownership_paths(stderr_text: str) -> List[str]:
    """
    Extracts the exact `safe.directory` path(s) suggested by Git when a
    `fatal: detected dubious ownership in repository` error occurs.
    """
    if not stderr_text:
        return []
    found: List[str] = []

    def _add(p: str):
        clean = p.strip().strip("'\"")
        if clean and clean not in found:
            found.append(clean)
            if clean.startswith("//") and not clean.startswith("%(prefix)/"):
                pref = f"%(prefix)/{clean}"
                if pref not in found:
                    found.append(pref)

    for m in re.finditer(r"safe\.directory\s+['\"]?([^'\"\r\n]+)['\"]?", stderr_text):
        _add(m.group(1))
    for m in re.finditer(r"dubious ownership in repository at\s+['\"]([^'\"\r\n]+)['\"]", stderr_text):
        _add(m.group(1))

    return found


def ensure_git_safe_directories(
    paths: Iterable[str],
    git_executable: str = "git",
    include_wildcard: bool = True,
) -> List[str]:
    """
    Prepares global Git configuration (`git config --global --add safe.directory ...`)
    for the chosen backup directory, `mirrors`, `worktrees`, UNC paths (`%(prefix)///...`),
    and `*` so Git never rejects repositories or mirrors on network drives with
    `fatal: detected dubious ownership`.

    Returns:
        List[str]: Newly added `safe.directory` entries.
    """
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"

    existing: set = set()
    try:
        res = subprocess.run(
            [git_executable, "config", "--global", "--get-all", "safe.directory"],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
            check=False,
        )
        if res.returncode == 0 and res.stdout:
            for line in res.stdout.splitlines():
                if line.strip():
                    existing.add(line.strip())
    except Exception as exc:
        logger.debug("Could not read existing global git safe.directory list: %s", exc)

    desired: List[str] = []
    if include_wildcard:
        desired.append("*")

    for p in (paths or []):
        for cand in _candidate_safe_directory_patterns(p):
            if cand not in desired:
                desired.append(cand)

    added: List[str] = []
    for entry in desired:
        if entry in existing:
            continue
        try:
            add_res = subprocess.run(
                [git_executable, "config", "--global", "--add", "safe.directory", entry],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
                check=False,
            )
            if add_res.returncode == 0:
                existing.add(entry)
                added.append(entry)
        except Exception as exc:
            logger.debug("Could not add global git safe.directory '%s': %s", entry, exc)

    if added:
        logger.info("🛡️ Prepared global git safe.directory config (%d entries added)", len(added))
    return added


class LocalBackupManager:
    """
    Path 1 Engine: Clones and incrementally updates all project Git repositories
    to a local backup directory with a toggleable format:
    - `'worktree'`: Working-tree clones with `--recurse-submodules` under `worktrees/<RepoName>`
    - `'mirror'`: Bare mirror clones (`--mirror`) under `mirrors/<RepoName>.git`
    - `'both'`: Maintains both `mirrors/<RepoName>.git` and `worktrees/<RepoName>`
      (using `--reference-if-able` for fast object sharing).
    """

    def __init__(
        self,
        target_dir: str,
        mode: str = "both",
        info_handler=None,
        project_id: str = "",
        pat: str = "",
        cache_db=None,
        git_executable: str = "git",
        git_timeout_seconds: Optional[int] = DEFAULT_GIT_TIMEOUT_SECONDS,
        extend_timeout_on_activity: bool = True,
        auto_configure_safe_directory: bool = True,
    ):
        norm_mode = str(mode or "both").strip().lower()
        if norm_mode not in VALID_BACKUP_MODES:
            raise ValueError(f"Invalid backup mode '{mode}'. Must be one of {VALID_BACKUP_MODES}.")
        self.target_dir = os.path.abspath(target_dir)
        self.mode = norm_mode
        self.info_handler = info_handler
        self.project_id = project_id
        self.pat = pat
        self.cache_db = cache_db
        self.git_executable = git_executable
        self.git_timeout_seconds = (
            None if (git_timeout_seconds is None or int(git_timeout_seconds) <= 0) else int(git_timeout_seconds)
        )
        self.extend_timeout_on_activity = bool(extend_timeout_on_activity)
        self.auto_configure_safe_directory = bool(auto_configure_safe_directory)
        if self.auto_configure_safe_directory:
            self.ensure_global_safe_directories()

    def ensure_global_safe_directories(self, extra_paths: Optional[Iterable[str]] = None) -> List[str]:
        """
        Ensures global Git `safe.directory` configuration is prepared for `target_dir`,
        `mirrors_dir`, `worktrees_dir`, any existing `.git` mirrors/worktrees, and `extra_paths`.
        """
        paths = [self.target_dir, self.mirrors_dir, self.worktrees_dir]
        if extra_paths:
            for ep in extra_paths:
                if ep and ep not in paths:
                    paths.append(ep)
        # Also include existing mirror directories if present on disk
        if os.path.isdir(self.mirrors_dir):
            try:
                with os.scandir(self.mirrors_dir) as it:
                    for entry in it:
                        if entry.is_dir():
                            paths.append(entry.path)
            except OSError:
                pass
        return ensure_git_safe_directories(
            paths=paths,
            git_executable=self.git_executable,
            include_wildcard=True,
        )

    @property
    def mirrors_dir(self) -> str:
        return os.path.join(self.target_dir, "mirrors")

    @property
    def worktrees_dir(self) -> str:
        return os.path.join(self.target_dir, "worktrees")

    @property
    def cache_snapshot_dir(self) -> str:
        return os.path.join(self.target_dir, "cache_snapshot")

    @property
    def manifest_path(self) -> str:
        return os.path.join(self.target_dir, "backup_manifest.json")

    @staticmethod
    def _probe_disk_activity(watch_path: Optional[str]) -> Tuple[int, float]:
        """
        Samples file count and latest modification timestamp inside `watch_path`
        (and `.git/objects` if present) to detect ongoing Git disk I/O on slow network drives.
        """
        if not watch_path or not os.path.exists(watch_path):
            return (0, 0.0)
        count = 0
        latest_mtime = 0.0
        probe_dirs = [watch_path]
        for sub in (".git", os.path.join(".git", "objects"), os.path.join(".git", "objects", "pack"), "objects", os.path.join("objects", "pack")):
            cand = os.path.join(watch_path, sub)
            if os.path.isdir(cand):
                probe_dirs.append(cand)
        for d in probe_dirs:
            try:
                st = os.stat(d)
                if st.st_mtime > latest_mtime:
                    latest_mtime = st.st_mtime
                with os.scandir(d) as it:
                    for idx, entry in enumerate(it):
                        if idx > 250:
                            break
                        count += 1
                        try:
                            est = entry.stat()
                            if est.st_mtime > latest_mtime:
                                latest_mtime = est.st_mtime
                        except OSError:
                            pass
            except OSError:
                pass
        return (count, latest_mtime)

    def _run_git(
        self,
        git_args: List[str],
        cwd: Optional[str] = None,
        extra_config_args: Optional[List[str]] = None,
        timeout: Optional[int] = -1,
        watch_path: Optional[str] = None,
        _retried_safe_dir: bool = False,
    ) -> subprocess.CompletedProcess:
        """
        Executes a git command with ephemeral auth/config flags and captures output.
        Supports unlimited timeout (`timeout=None` or `0`), automatic timeout extension
        when disk I/O is still active on slow network shares, automatic global `safe.directory`
        self-healing on `dubious ownership`, and catches `TimeoutExpired` cleanly so a slow
        command never crashes the caller with an unhandled exception.
        """
        cmd = [self.git_executable, "-c", "safe.directory=*"]
        if extra_config_args:
            cmd.extend(extra_config_args)
        cmd.extend(git_args)

        env = os.environ.copy()
        env["GIT_TERMINAL_PROMPT"] = "0"

        effective_timeout: Optional[int]
        if timeout == -1:
            effective_timeout = self.git_timeout_seconds
        elif timeout is None or int(timeout) <= 0:
            effective_timeout = None
        else:
            effective_timeout = int(timeout)

        target_watch = watch_path or cwd
        if not target_watch and git_args:
            last_arg = str(git_args[-1])
            if os.path.isabs(last_arg) or os.path.exists(os.path.dirname(last_arg) or "."):
                target_watch = last_arg

        start_ts = time.monotonic()
        last_activity = self._probe_disk_activity(target_watch)
        max_extensions = 6  # Up to 6x window extensions if disk is actively writing
        extensions_used = 0

        try:
            proc = subprocess.Popen(
                cmd,
                cwd=cwd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        except Exception as exc:
            return subprocess.CompletedProcess(
                args=cmd,
                returncode=1,
                stdout="",
                stderr=f"Failed to start git process: {exc}",
            )

        while True:
            try:
                stdout_str, stderr_str = proc.communicate(timeout=effective_timeout)
                err_txt = stderr_str or ""
                if (
                    proc.returncode != 0
                    and not _retried_safe_dir
                    and ("dubious ownership" in err_txt or "safe.directory" in err_txt)
                ):
                    extracted = extract_dubious_ownership_paths(err_txt)
                    if cwd:
                        extracted.append(cwd)
                    if target_watch:
                        extracted.append(target_watch)
                    logger.info(
                        "🛡️ Detected Git dubious ownership on network/mirror directory; adding to global safe.directory and retrying: %s",
                        extracted,
                    )
                    ensure_git_safe_directories(
                        paths=extracted,
                        git_executable=self.git_executable,
                        include_wildcard=True,
                    )
                    return self._run_git(
                        git_args=git_args,
                        cwd=cwd,
                        extra_config_args=extra_config_args,
                        timeout=timeout,
                        watch_path=watch_path,
                        _retried_safe_dir=True,
                    )
                return subprocess.CompletedProcess(
                    args=cmd,
                    returncode=proc.returncode,
                    stdout=stdout_str or "",
                    stderr=err_txt,
                )
            except subprocess.TimeoutExpired as te:
                cur_activity = self._probe_disk_activity(target_watch)
                if (
                    self.extend_timeout_on_activity
                    and effective_timeout
                    and effective_timeout >= 60
                    and extensions_used < max_extensions
                    and cur_activity != (0, 0.0)
                    and cur_activity != last_activity
                ):
                    extensions_used += 1
                    last_activity = cur_activity
                    elapsed = int(time.monotonic() - start_ts)
                    logger.info(
                        "⏳ Git operation still actively writing to disk (%s, %ds elapsed) — extending timeout window (%d/%d)...",
                        target_watch or "git", elapsed, extensions_used, max_extensions,
                    )
                    continue

                # Terminate timed-out git process cleanly without raising an unhandled exception
                try:
                    proc.kill()
                except Exception:
                    pass
                try:
                    out_part, err_part = proc.communicate(timeout=5)
                except Exception:
                    out_part = getattr(te, "stdout", "") or ""
                    err_part = getattr(te, "stderr", "") or ""
                if isinstance(out_part, bytes):
                    out_part = out_part.decode("utf-8", errors="replace")
                if isinstance(err_part, bytes):
                    err_part = err_part.decode("utf-8", errors="replace")
                elapsed = int(time.monotonic() - start_ts)
                timeout_msg = (
                    f"Git command timed out after {elapsed}s (configured step timeout: {effective_timeout}s). "
                    f"Consider increasing the Git Timeout in Settings -> Migration & Backup or syncing this repository individually."
                )
                if err_part and err_part.strip():
                    timeout_msg = f"{timeout_msg} Details: {err_part.strip()}"
                logger.warning("⚠️ %s", timeout_msg)
                return subprocess.CompletedProcess(
                    args=cmd,
                    returncode=124,
                    stdout=out_part or "",
                    stderr=timeout_msg,
                )

    def _resolve_repo_clone_url(self, repo: Dict[str, Any]) -> str:
        """Resolves the Git clone URL for a repository dictionary."""
        for key in ("remoteUrl", "webUrl", "web_url", "url"):
            val = repo.get(key)
            if val and isinstance(val, str) and ("/_git/" in val or os.path.exists(val) or val.startswith("file://") or val.endswith(".git")):
                return val
        if self.info_handler and getattr(self.info_handler, "url", "") and self.project_id:
            base = self.info_handler.url.rstrip("/")
            proj_q = urllib.parse.quote(str(self.project_id))
            name_q = urllib.parse.quote(str(repo.get("name", "")))
            return f"{base}/{proj_q}/_git/{name_q}"
        return str(repo.get("webUrl") or repo.get("web_url") or repo.get("url") or "")

    def backup_single_repository(
        self,
        repo: Dict[str, Any],
        force: bool = False,
        tfs_project_git_base: str = "",
        local_override_base: str = "",
    ) -> Dict[str, Any]:
        """
        Clones or incrementally updates a single repository according to `self.mode`
        (`'worktree'`, `'mirror'`, or `'both'`), verifies `HEAD` and submodule status,
        and updates `migration_status` in SQLite.

        Args:
            repo (Dict[str, Any]): Repository dictionary (`id`, `name`, `remoteUrl`/`webUrl`, `last_push_id`).
            force (bool, optional): Force fetch/update even if `last_push_id` has not changed. Defaults to False.
            tfs_project_git_base (str, optional): Base TFS `/_git/` URL for automatic submodule `insteadOf` mapping.
            local_override_base (str, optional): Target base path/URL for submodule `insteadOf` rewrite.

        Returns:
            Dict[str, Any]: Backup result dictionary for the repository.
        """
        repo_id = str(repo.get("id") or repo.get("name") or "")
        repo_name = str(repo.get("name") or repo_id)
        clone_url = self._resolve_repo_clone_url(repo)
        remote_push_id = repo.get("last_push_id") or repo.get("lastPushId")

        mirror_path = os.path.join(self.mirrors_dir, f"{repo_name}.git")
        worktree_path = os.path.join(self.worktrees_dir, repo_name)

        want_mirror = self.mode in ("mirror", "both")
        want_worktree = self.mode in ("worktree", "both")

        if self.auto_configure_safe_directory:
            self.ensure_global_safe_directories([mirror_path, worktree_path])

        # Check Standby Delta: skip network fetch if push_id matches and required folders already exist
        if not force and self.cache_db and remote_push_id is not None:
            existing_status = self.cache_db.get_migration_status(repo_id=repo_id)
            if existing_status and existing_status.get("local_status") == "OK":
                cached_push_id = existing_status.get("last_tfs_push_id")
                mirror_ready = (not want_mirror) or os.path.isdir(mirror_path)
                worktree_ready = (not want_worktree) or os.path.isdir(os.path.join(worktree_path, ".git"))
                if cached_push_id is not None and int(cached_push_id) == int(remote_push_id) and mirror_ready and worktree_ready:
                    return {
                        "repo_id": repo_id,
                        "repo_name": repo_name,
                        "mode": self.mode,
                        "status": "OK",
                        "action": "SKIPPED_UP_TO_DATE",
                        "mirror_path": mirror_path if want_mirror else "",
                        "worktree_path": worktree_path if want_worktree else "",
                        "head_commit": existing_status.get("head_commit", ""),
                        "submodules_ok": True,
                        "error": "",
                    }

        auth_args = build_git_auth_args(
            pat=self.pat,
            tfs_project_git_base=tfs_project_git_base,
            local_override_base=local_override_base,
        )

        errors: List[str] = []
        action_taken = "CLONED"

        # Step 1: Bare Mirror (`mirrors/<RepoName>.git`)
        if want_mirror:
            os.makedirs(self.mirrors_dir, exist_ok=True)
            if os.path.isdir(mirror_path) and os.path.isfile(os.path.join(mirror_path, "HEAD")):
                action_taken = "UPDATED"
                logger.info("  ↳ [%s] Updating bare mirror (%s)...", repo_name, mirror_path)
                self._run_git(["remote", "set-url", "origin", clone_url], cwd=mirror_path, extra_config_args=auth_args)
                res = self._run_git(["remote", "update", "--prune"], cwd=mirror_path, extra_config_args=auth_args)
                if res.returncode != 0:
                    errors.append(f"Mirror update failed: {res.stderr.strip()}")
            else:
                if os.path.exists(mirror_path):
                    shutil.rmtree(mirror_path, ignore_errors=True)
                logger.info("  ↳ [%s] Cloning bare mirror (%s)...", repo_name, mirror_path)
                res = self._run_git(["clone", "--mirror", clone_url, mirror_path], extra_config_args=auth_args)
                if res.returncode != 0:
                    errors.append(f"Mirror clone failed: {res.stderr.strip()}")

        # Step 2: Working Tree (`worktrees/<RepoName>`) with recursive submodules
        submodules_ok = True
        submodule_details: List[str] = []

        if want_worktree and not errors:
            os.makedirs(self.worktrees_dir, exist_ok=True)
            git_dir_marker = os.path.join(worktree_path, ".git")

            # If we have a local override base or sibling worktrees/mirrors, configure submodule URL resolution
            wt_auth_args = list(auth_args)

            def _sync_and_init_submodules() -> bool:
                gm_file = os.path.join(worktree_path, ".gitmodules")
                if not os.path.isfile(gm_file):
                    return True
                logger.info("  ↳ [%s] Updating recursive submodules in worktree...", repo_name)
                self._run_git(
                    ["submodule", "sync", "--recursive"],
                    cwd=worktree_path,
                    extra_config_args=wt_auth_args,
                    watch_path=worktree_path,
                )
                sub_res = self._run_git(
                    ["submodule", "update", "--init", "--recursive"],
                    cwd=worktree_path,
                    extra_config_args=wt_auth_args,
                    watch_path=worktree_path,
                )
                if sub_res.returncode == 0:
                    return True

                # Fallback: update each submodule from .gitmodules individually so one slow/huge submodule
                # gets its own dedicated timeout window and does not block the remaining submodules.
                try:
                    with open(gm_file, "r", encoding="utf-8", errors="replace") as f:
                        gm_entries = parse_gitmodules_content(f.read())
                except Exception:
                    gm_entries = []

                if not gm_entries:
                    errors.append(f"Submodule update failed: {sub_res.stderr.strip()}")
                    return False

                logger.info(
                    "  ↳ [%s] Retrying %d submodule(s) individually...",
                    repo_name, len(gm_entries),
                )
                all_subs_ok = True
                for sub_entry in gm_entries:
                    sub_path = sub_entry.get("path") or ""
                    if not sub_path:
                        continue
                    ind_res = self._run_git(
                        ["submodule", "update", "--init", "--recursive", "--", sub_path],
                        cwd=worktree_path,
                        extra_config_args=wt_auth_args,
                        watch_path=os.path.join(worktree_path, sub_path),
                    )
                    if ind_res.returncode != 0:
                        all_subs_ok = False
                        errors.append(f"Submodule '{sub_path}' failed: {ind_res.stderr.strip()}")
                return all_subs_ok

            if os.path.isdir(worktree_path) and os.path.exists(git_dir_marker):
                action_taken = "UPDATED"
                logger.info("  ↳ [%s] Fetching & updating worktree (%s)...", repo_name, worktree_path)
                self._run_git(["remote", "set-url", "origin", clone_url], cwd=worktree_path, extra_config_args=wt_auth_args)
                fetch_res = self._run_git(
                    ["fetch", "--all", "--tags", "--prune"],
                    cwd=worktree_path,
                    extra_config_args=wt_auth_args,
                    watch_path=worktree_path,
                )
                if fetch_res.returncode != 0:
                    errors.append(f"Worktree fetch failed: {fetch_res.stderr.strip()}")
                else:
                    # Check if HEAD is valid; if a previous clone was interrupted before checkout finished, recover checkout
                    head_check = self._run_git(["rev-parse", "--verify", "HEAD"], cwd=worktree_path, timeout=30)
                    if head_check.returncode != 0:
                        default_br = str(repo.get("defaultBranch") or repo.get("default_branch") or "").replace("refs/heads/", "").strip()
                        if default_br:
                            self._run_git(["checkout", "-f", default_br], cwd=worktree_path, extra_config_args=wt_auth_args, watch_path=worktree_path)
                        else:
                            self._run_git(["checkout", "-f"], cwd=worktree_path, extra_config_args=wt_auth_args, watch_path=worktree_path)
                    else:
                        # Fast-forward current branch if tracking upstream
                        self._run_git(["pull", "--ff-only"], cwd=worktree_path, extra_config_args=wt_auth_args, watch_path=worktree_path)
                    if not _sync_and_init_submodules():
                        submodules_ok = False
            else:
                if os.path.exists(worktree_path):
                    shutil.rmtree(worktree_path, ignore_errors=True)
                logger.info("  ↳ [%s] Cloning worktree (%s)...", repo_name, worktree_path)
                # Clone parent repository first (with --reference-if-able when local mirror is available),
                # then initialize recursive submodules as a separate step so huge repos + submodules do not share a single timeout.
                clone_cmd = ["clone", "--recurse-submodules"]
                if want_mirror and os.path.isdir(mirror_path):
                    clone_cmd.extend(["--reference-if-able", mirror_path])
                clone_cmd.extend([clone_url, worktree_path])

                res = self._run_git(clone_cmd, extra_config_args=wt_auth_args, watch_path=worktree_path)
                if res.returncode != 0:
                    # If clone --recurse-submodules timed out or failed on submodules, attempt 2-stage recovery
                    if os.path.exists(git_dir_marker):
                        logger.info("  ↳ [%s] Attempting in-place worktree & submodule recovery...", repo_name)
                        self._run_git(["fetch", "--all", "--tags", "--prune"], cwd=worktree_path, extra_config_args=wt_auth_args, watch_path=worktree_path)
                        self._run_git(["checkout", "-f"], cwd=worktree_path, extra_config_args=wt_auth_args, watch_path=worktree_path)
                        if not _sync_and_init_submodules():
                            submodules_ok = False
                            errors.append(f"Submodule clone warning: {res.stderr.strip()}")
                    else:
                        # Retry base clone without --recurse-submodules, then init submodules separately
                        if os.path.exists(worktree_path):
                            shutil.rmtree(worktree_path, ignore_errors=True)
                        base_clone_cmd = ["clone"]
                        if want_mirror and os.path.isdir(mirror_path):
                            base_clone_cmd.extend(["--reference-if-able", mirror_path])
                        base_clone_cmd.extend([clone_url, worktree_path])
                        base_res = self._run_git(base_clone_cmd, extra_config_args=wt_auth_args, watch_path=worktree_path)
                        if base_res.returncode == 0 and os.path.exists(git_dir_marker):
                            if not _sync_and_init_submodules():
                                submodules_ok = False
                        else:
                            errors.append(f"Worktree clone failed: {(base_res.stderr or res.stderr).strip()}")

            # Verify submodule status if worktree exists
            if os.path.isdir(worktree_path) and os.path.exists(git_dir_marker):
                st_res = self._run_git(["submodule", "status", "--recursive"], cwd=worktree_path)
                if st_res.returncode == 0 and st_res.stdout.strip():
                    for line in st_res.stdout.splitlines():
                        submodule_details.append(line.strip())
                        # Leading '-' means uninitialized, 'U' means merge conflict
                        if line.startswith("-") or line.startswith("U"):
                            submodules_ok = False
                elif st_res.returncode != 0:
                    submodules_ok = False

        # Step 3: Verify HEAD commit SHA
        head_commit = ""
        check_dir = worktree_path if (want_worktree and os.path.isdir(worktree_path)) else (mirror_path if want_mirror else "")
        if check_dir and os.path.isdir(check_dir):
            rev_res = self._run_git(["rev-parse", "HEAD"], cwd=check_dir)
            if rev_res.returncode == 0:
                head_commit = rev_res.stdout.strip()

        now_iso = datetime.now(timezone.utc).isoformat()
        if errors and not head_commit:
            local_status = "FAILED"
        elif not submodules_ok or errors:
            local_status = "SUBMODULE_WARN"
        else:
            local_status = "OK"

        err_msg = "; ".join(errors)

        if self.cache_db and repo_id:
            try:
                self.cache_db.save_migration_status({
                    "repo_id": repo_id,
                    "repo_name": repo_name,
                    "project_id": self.project_id,
                    "backup_mode": self.mode,
                    "local_mirror_path": mirror_path if want_mirror else "",
                    "local_worktree_path": worktree_path if want_worktree else "",
                    "last_tfs_push_id": remote_push_id,
                    "last_backup_at": now_iso,
                    "local_status": local_status,
                    "last_error": err_msg,
                })
            except Exception as db_err:
                logger.warning("Failed to update migration_status for %s: %s", repo_name, db_err)

        return {
            "repo_id": repo_id,
            "repo_name": repo_name,
            "mode": self.mode,
            "status": local_status,
            "action": action_taken,
            "mirror_path": mirror_path if want_mirror else "",
            "worktree_path": worktree_path if want_worktree else "",
            "head_commit": head_commit,
            "submodules_ok": submodules_ok,
            "submodule_details": submodule_details,
            "backed_up_at": now_iso,
            "error": err_msg,
        }

    def snapshot_sqlite_cache(self) -> Optional[str]:
        """
        Creates a consistent point-in-time backup of the SQLite cache database
        inside `<target_dir>/cache_snapshot/`.
        """
        if not self.cache_db or not getattr(self.cache_db, "db_path", None):
            return None
        src_db_path = self.cache_db.db_path
        if src_db_path == ":memory:" or not os.path.isfile(src_db_path):
            return None

        os.makedirs(self.cache_snapshot_dir, exist_ok=True)
        dst_db_path = os.path.join(self.cache_snapshot_dir, os.path.basename(src_db_path))
        try:
            src_conn = sqlite3.connect(src_db_path, timeout=30.0)
            dst_conn = sqlite3.connect(dst_db_path, timeout=30.0)
            try:
                src_conn.backup(dst_conn)
            finally:
                dst_conn.close()
                src_conn.close()
            return dst_db_path
        except Exception as e:
            logger.warning("SQLite live backup fallback to file copy: %s", e)
            try:
                shutil.copy2(src_db_path, dst_db_path)
                return dst_db_path
            except Exception:
                return None

    def backup_all_repositories(
        self,
        repos: Optional[List[Dict[str, Any]]] = None,
        submodule_map: Optional[Dict[str, List[str]]] = None,
        force: bool = False,
        tfs_project_git_base: str = "",
        local_override_base: str = "",
        progress_callback: Optional[Callable] = None,
        cancel_token: Optional[Any] = None,
    ) -> Dict[str, Any]:
        """
        Executes Path 1 local backup across all active repositories in topological order
        (submodules first, then parent repositories), snapshots the SQLite cache, and writes
        `backup_manifest.json`.

        Args:
            repos (List[Dict], optional): Repositories to back up. If None, loaded from `info_handler` or `cache_db`.
            submodule_map (Dict[str, List[str]], optional): Dependency map `{parent_repo: [child_repo, ...]}`.
            force (bool, optional): Force update even if push ID is unchanged. Defaults to False.
            tfs_project_git_base (str, optional): TFS `/_git/` URL prefix for automatic submodule URL resolution.
            local_override_base (str, optional): Replacement base URL for submodule `insteadOf`.
            progress_callback (Callable, optional): Progress callback `(pct, msg)` or `(msg, cur, total)`.
            cancel_token (Any, optional): Cancellation callable or token object.

        Returns:
            Dict[str, Any]: Full backup manifest dictionary.
        """
        os.makedirs(self.target_dir, exist_ok=True)

        if repos is None:
            if self.info_handler and self.project_id:
                try:
                    raw_repos = self.info_handler.get_repositories(self.project_id)
                    repos = [
                        r for r in raw_repos
                        if not r.get("isDisabled", False)
                        and "CANCEL" not in r.get("name", "")
                        and "DEPRECATE" not in r.get("name", "")
                    ]
                except Exception as e:
                    logger.warning("Falling back to cached repository list for backup: %s", e)

            if repos is None and self.cache_db:
                with self.cache_db._connection() as conn:
                    rows = conn.execute(
                        "SELECT id, name, default_branch, web_url, last_push_id, raw_json FROM repositories WHERE is_disabled = 0 ORDER BY name"
                    ).fetchall()
                    repos = []
                    for r in rows:
                        raw_d = {}
                        if r["raw_json"]:
                            try:
                                raw_d = json.loads(r["raw_json"])
                            except Exception:
                                raw_d = {}
                        repos.append({
                            "id": r["id"],
                            "name": r["name"],
                            "defaultBranch": r["default_branch"],
                            "webUrl": r["web_url"] or raw_d.get("remoteUrl") or raw_d.get("webUrl") or "",
                            "remoteUrl": raw_d.get("remoteUrl") or r["web_url"] or "",
                            "last_push_id": r["last_push_id"],
                        })

        repos = list(repos or [])

        # Build submodule dependency map from cache_db if not explicitly provided
        if submodule_map is None and self.cache_db:
            submodule_map = {}
            try:
                audit_rows = self.cache_db.get_submodule_audit()
                for row in audit_rows:
                    p_name = row.get("parent_repo_name", "")
                    c_url = row.get("proposed_relative_url") or row.get("current_url") or ""
                    c_name = _strip_git_suffix(c_url.replace("\\", "/").split("/")[-1])
                    if p_name and c_name:
                        submodule_map.setdefault(p_name, []).append(c_name)
            except Exception:
                pass

        ordered_repos = sort_repos_topologically(repos, submodule_map=submodule_map)
        total = len(ordered_repos)
        logger.info(
            "📦 Starting local repository backup [mode=%s, force=%s] for %d repositories -> %s",
            self.mode, force, total, self.target_dir,
        )

        # Auto-derive tfs_project_git_base if not supplied
        if not tfs_project_git_base and self.info_handler and getattr(self.info_handler, "url", "") and self.project_id:
            tfs_project_git_base = f"{self.info_handler.url.rstrip('/')}/{urllib.parse.quote(str(self.project_id))}/_git"

        # If backing up mirrors too and no explicit local_override_base was passed, allow resolving TFS URLs
        def _is_cancelled() -> bool:
            if not cancel_token:
                if hasattr(progress_callback, "is_cancelled") and callable(progress_callback.is_cancelled):
                    return bool(progress_callback.is_cancelled())
                return False
            if callable(cancel_token):
                return bool(cancel_token())
            return bool(getattr(cancel_token, "is_cancelled", lambda: False)())

        def _notify(cur: int, r_name: str):
            pct = int((cur / total) * 100) if total > 0 else 100
            msg = f"Backing up {r_name} [{self.mode}] ({cur}/{total})..."
            logger.info("⏳ [%d/%d] (%d%%) %s", cur, total, pct, msg)
            if hasattr(progress_callback, "report_progress"):
                try:
                    progress_callback.report_progress(pct, msg)
                    return
                except Exception:
                    pass
            if not callable(progress_callback):
                return
            try:
                progress_callback(pct, msg)
            except TypeError:
                try:
                    progress_callback(msg, cur, total)
                except Exception:
                    pass

        results: List[Dict[str, Any]] = []
        ok_count = 0
        warn_count = 0
        failed_count = 0
        skipped_count = 0

        for idx, repo in enumerate(ordered_repos, start=1):
            if _is_cancelled():
                logger.info("⏹️ Local backup cancelled at repository %d/%d", idx, total)
                break
            r_name = repo.get("name", "")
            r_id = str(repo.get("id") or r_name)
            _notify(idx, r_name)
            try:
                res = self.backup_single_repository(
                    repo,
                    force=force,
                    tfs_project_git_base=tfs_project_git_base,
                    local_override_base=local_override_base,
                )
            except Exception as repo_exc:
                err_str = f"Unexpected backup error: {repo_exc}"
                logger.error("❌ [%d/%d] '%s' failed with exception (continuing with remaining repos): %s", idx, total, r_name, repo_exc)
                now_iso = datetime.now(timezone.utc).isoformat()
                if self.cache_db and r_id:
                    try:
                        self.cache_db.save_migration_status({
                            "repo_id": r_id,
                            "repo_name": r_name,
                            "project_id": self.project_id,
                            "backup_mode": self.mode,
                            "last_backup_at": now_iso,
                            "local_status": "FAILED",
                            "last_error": err_str,
                        })
                    except Exception:
                        pass
                res = {
                    "repo_id": r_id,
                    "repo_name": r_name,
                    "mode": self.mode,
                    "status": "FAILED",
                    "action": "FAILED",
                    "mirror_path": "",
                    "worktree_path": "",
                    "head_commit": "",
                    "submodules_ok": False,
                    "submodule_details": [],
                    "backed_up_at": now_iso,
                    "error": err_str,
                }
            results.append(res)
            st = res.get("status")
            action = res.get("action", "")
            short_sha = (res.get("head_commit") or "")[:8] or "empty"
            sub_cnt = len(res.get("submodule_details") or [])
            sub_note = f", {sub_cnt} submodule(s)" if sub_cnt else ""
            if st == "OK":
                ok_count += 1
                if action == "SKIPPED_UP_TO_DATE":
                    skipped_count += 1
                    logger.info(
                        "⏭️ [%d/%d] '%s' skipped (already up to date, push_id=%s)",
                        idx, total, r_name, repo.get("last_push_id") or repo.get("lastPushId") or "-",
                    )
                else:
                    logger.info(
                        "✅ [%d/%d] '%s' %s successfully [HEAD=%s%s]",
                        idx, total, r_name, action.lower() or "backed up", short_sha, sub_note,
                    )
            elif st == "SUBMODULE_WARN":
                warn_count += 1
                logger.warning(
                    "⚠️ [%d/%d] '%s' backed up with submodule warning [HEAD=%s]: %s",
                    idx, total, r_name, short_sha, res.get("error"),
                )
            else:
                failed_count += 1
                logger.error(
                    "❌ [%d/%d] '%s' backup failed: %s",
                    idx, total, r_name, res.get("error"),
                )

        snapshot_path = self.snapshot_sqlite_cache()
        if snapshot_path:
            logger.info("💾 SQLite cache snapshot saved to: %s", snapshot_path)

        manifest = {
            "project_id": self.project_id,
            "backup_mode": self.mode,
            "target_dir": self.target_dir,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "total_repositories": total,
            "ok_count": ok_count,
            "skipped_up_to_date_count": skipped_count,
            "submodule_warning_count": warn_count,
            "failed_count": failed_count,
            "sqlite_snapshot_path": snapshot_path or "",
            "repositories": results,
        }

        try:
            with open(self.manifest_path, "w", encoding="utf-8") as f:
                json.dump(manifest, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logger.error("Failed to write backup_manifest.json: %s", e)

        logger.info(
            "🏁 Local repository backup completed: %d/%d OK (%d skipped up-to-date), %d warnings, %d failed. Manifest: %s",
            ok_count, total, skipped_count, warn_count, failed_count, self.manifest_path,
        )
        return manifest


VALID_FORGEJO_STRATEGIES = ("push", "pull_mirror")


class ForgejoClient:
    """
    REST API v1 client for a local Forgejo / Gitea instance.
    Handles organization creation, repository provisioning, metadata updates,
    and pull-mirror configuration without third-party dependencies.
    """

    def __init__(self, url: str, token: str = ""):
        import ssl
        self.url = str(url or "").strip().rstrip("/")
        self.token = str(token or "").strip()
        self.headers = {
            "Accept": "application/json",
            "Content-Type": "application/json",
        }
        if self.token:
            self.headers["Authorization"] = f"token {self.token}"

        self.ssl_context = ssl.create_default_context()
        self.ssl_context.check_hostname = False
        self.ssl_context.verify_mode = ssl.CERT_NONE

    def _request(
        self,
        method: str,
        path: str,
        params: Optional[Dict[str, Any]] = None,
        data: Optional[Any] = None,
        timeout: int = 30,
    ) -> Tuple[Any, int]:
        if not self.url:
            raise ValueError("Forgejo server URL is not configured.")
        full_url = f"{self.url}/{path.lstrip('/')}"
        if params:
            full_url = f"{full_url}?{urllib.parse.urlencode(params, doseq=True)}"

        req = urllib.request.Request(full_url, headers=dict(self.headers), method=method)
        if data is not None:
            req.data = json.dumps(data).encode("utf-8")

        try:
            with urllib.request.urlopen(req, context=self.ssl_context, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
                parsed = json.loads(raw) if raw.strip() else {}
                return parsed, resp.status
        except urllib.error.HTTPError as he:
            err_body = ""
            try:
                err_body = he.read().decode("utf-8", errors="replace")
            except Exception:
                pass
            if he.code == 404:
                return None, 404
            msg = err_body
            try:
                err_json = json.loads(err_body)
                if isinstance(err_json, dict) and err_json.get("message"):
                    msg = err_json["message"]
            except Exception:
                pass
            raise RuntimeError(f"Forgejo API {method} {path} failed (HTTP {he.code}): {msg}") from he
        except urllib.error.URLError as ue:
            raise ConnectionError(f"Could not connect to Forgejo server at {self.url}: {ue}") from ue

    def test_connection(self) -> Dict[str, Any]:
        """Tests connectivity and token authentication with the Forgejo instance."""
        if not self.url:
            return {"success": False, "url": "", "version": "", "username": "", "error": "Forgejo URL is empty."}
        try:
            ver_res, _ = self._request("GET", "/api/v1/version")
            version = ver_res.get("version", "unknown") if isinstance(ver_res, dict) else "unknown"
            username = ""
            if self.token:
                user_res, status = self._request("GET", "/api/v1/user")
                if status == 200 and isinstance(user_res, dict):
                    username = user_res.get("login") or user_res.get("username") or ""
            return {
                "success": True,
                "url": self.url,
                "version": version,
                "username": username,
                "authenticated": bool(username),
                "error": "",
            }
        except Exception as e:
            return {
                "success": False,
                "url": self.url,
                "version": "",
                "username": "",
                "authenticated": False,
                "error": str(e),
            }

    def get_org(self, org_name: str) -> Optional[Dict[str, Any]]:
        """Retrieves a Forgejo Organization by name, or None if not found."""
        enc_org = urllib.parse.quote(str(org_name).strip(), safe="")
        res, status = self._request("GET", f"/api/v1/orgs/{enc_org}")
        return res if status == 200 and isinstance(res, dict) else None

    def ensure_org(
        self,
        org_name: str,
        full_name: str = "",
        description: str = "",
        visibility: str = "private",
    ) -> Dict[str, Any]:
        """Ensures the target Organization exists in Forgejo, creating it if absent."""
        clean_org = str(org_name).strip()
        existing = self.get_org(clean_org)
        if existing:
            return existing
        payload = {
            "username": clean_org,
            "full_name": full_name or clean_org,
            "description": description or f"Standby mirror of TFS project {clean_org}",
            "visibility": visibility,
        }
        res, _ = self._request("POST", "/api/v1/orgs", data=payload)
        return res if isinstance(res, dict) else {"username": clean_org}

    def get_repo(self, org_name: str, repo_name: str) -> Optional[Dict[str, Any]]:
        """Retrieves a repository under `org_name`, or None if it does not exist."""
        enc_org = urllib.parse.quote(str(org_name).strip(), safe="")
        enc_repo = urllib.parse.quote(str(repo_name).strip(), safe="")
        res, status = self._request("GET", f"/api/v1/repos/{enc_org}/{enc_repo}")
        return res if status == 200 and isinstance(res, dict) else None

    def ensure_repo(
        self,
        org_name: str,
        repo_name: str,
        description: str = "",
        private: bool = True,
        default_branch: str = "dev",
    ) -> Dict[str, Any]:
        """Ensures an uninitialized repository exists in the target Forgejo Organization."""
        clean_org = str(org_name).strip()
        clean_repo = str(repo_name).strip()
        existing = self.get_repo(clean_org, clean_repo)
        if existing:
            return existing
        enc_org = urllib.parse.quote(clean_org, safe="")
        payload = {
            "name": clean_repo,
            "description": description,
            "private": private,
            "auto_init": False,
            "default_branch": str(default_branch or "dev").replace("refs/heads/", ""),
        }
        res, _ = self._request("POST", f"/api/v1/orgs/{enc_org}/repos", data=payload)
        return res if isinstance(res, dict) else {"name": clean_repo}

    def update_repo_metadata(
        self,
        org_name: str,
        repo_name: str,
        default_branch: Optional[str] = None,
        archived: Optional[bool] = None,
        description: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Updates repository settings (`default_branch`, `archived`, `description`) in Forgejo."""
        enc_org = urllib.parse.quote(str(org_name).strip(), safe="")
        enc_repo = urllib.parse.quote(str(repo_name).strip(), safe="")
        payload: Dict[str, Any] = {}
        if default_branch:
            payload["default_branch"] = str(default_branch).replace("refs/heads/", "")
        if archived is not None:
            payload["archived"] = bool(archived)
        if description is not None:
            payload["description"] = description
        if not payload:
            return {}
        res, _ = self._request("PATCH", f"/api/v1/repos/{enc_org}/{enc_repo}", data=payload)
        return res if isinstance(res, dict) else {}

    def migrate_pull_mirror(
        self,
        org_name: str,
        repo_name: str,
        clone_addr: str,
        auth_token: str = "",
        auth_username: str = "",
        mirror: bool = True,
        private: bool = True,
        description: str = "",
        mirror_interval: str = "1h",
    ) -> Dict[str, Any]:
        """
        Configures a Forgejo native Pull-Mirror (`POST /api/v1/repos/migrate`) if the repository
        does not exist yet, or triggers an immediate `mirror-sync` if it already exists.
        """
        clean_org = str(org_name).strip()
        clean_repo = str(repo_name).strip()
        existing = self.get_repo(clean_org, clean_repo)
        if existing:
            if existing.get("mirror"):
                self.trigger_mirror_sync(clean_org, clean_repo)
            return existing

        payload: Dict[str, Any] = {
            "clone_addr": clone_addr,
            "repo_owner": clean_org,
            "repo_name": clean_repo,
            "service": "git",
            "mirror": bool(mirror),
            "private": bool(private),
            "description": description,
            "mirror_interval": mirror_interval,
        }
        if auth_token:
            payload["auth_token"] = auth_token
        if auth_username:
            payload["auth_username"] = auth_username

        res, _ = self._request("POST", "/api/v1/repos/migrate", data=payload, timeout=120)
        return res if isinstance(res, dict) else {"name": clean_repo}

    def trigger_mirror_sync(self, org_name: str, repo_name: str) -> bool:
        """Triggers an immediate pull-mirror synchronization on Forgejo."""
        enc_org = urllib.parse.quote(str(org_name).strip(), safe="")
        enc_repo = urllib.parse.quote(str(repo_name).strip(), safe="")
        _, status = self._request("POST", f"/api/v1/repos/{enc_org}/{enc_repo}/mirror-sync")
        return status in (200, 202, 204)

    def convert_mirror_to_normal(self, org_name: str, repo_name: str) -> Dict[str, Any]:
        """Converts a read-only Forgejo pull-mirror into a normal writable repository for cutover."""
        enc_org = urllib.parse.quote(str(org_name).strip(), safe="")
        enc_repo = urllib.parse.quote(str(repo_name).strip(), safe="")
        res, _ = self._request("PATCH", f"/api/v1/repos/{enc_org}/{enc_repo}", data={"mirror": False})
        return res if isinstance(res, dict) else {}


class ForgejoStandbySyncManager:
    """
    Path 2 Engine: Synchronizes all project Git repositories and submodules to a local
    Forgejo instance in topological order (submodules first, then parent repositories).

    Supports two standby strategies:
    - `'push'` (Default): Ensures local bare mirrors are up to date via `LocalBackupManager`,
      provisions the target Organization and repositories in Forgejo, and pushes all branches
      (`refs/heads/*`) and tags (`refs/tags/*`) using ephemeral HTTP Basic auth headers.
    - `'pull_mirror'`: Registers each repository in Forgejo as a native Pull-Mirror from TFS
      (or triggers `mirror-sync` if already registered).
    """

    def __init__(
        self,
        forgejo_client: ForgejoClient,
        org_name: str,
        strategy: str = "push",
        backup_dir: Optional[str] = None,
        info_handler=None,
        project_id: str = "",
        tfs_pat: str = "",
        cache_db=None,
        git_executable: str = "git",
        git_timeout_seconds: Optional[int] = DEFAULT_GIT_TIMEOUT_SECONDS,
    ):
        norm_strat = str(strategy or "push").strip().lower()
        if norm_strat not in VALID_FORGEJO_STRATEGIES:
            raise ValueError(f"Invalid Forgejo strategy '{strategy}'. Must be one of {VALID_FORGEJO_STRATEGIES}.")
        self.forgejo = forgejo_client
        self.org_name = str(org_name or project_id or "TFS-Standby").strip()
        self.strategy = norm_strat
        self.backup_dir = os.path.abspath(backup_dir) if backup_dir else ""
        self.info_handler = info_handler
        self.project_id = project_id
        self.tfs_pat = tfs_pat
        self.cache_db = cache_db
        self.git_executable = git_executable
        self.git_timeout_seconds = (
            None if (git_timeout_seconds is None or int(git_timeout_seconds) <= 0) else int(git_timeout_seconds)
        )

    def _run_git_push_to_forgejo(self, mirror_path: str, forgejo_clone_url: str) -> subprocess.CompletedProcess:
        """
        Pushes all branches (`refs/heads/*`) and tags (`refs/tags/*`) from a local bare mirror
        to the target Forgejo repository using ephemeral HTTP Basic Auth headers.
        """
        env = os.environ.copy()
        env["GIT_TERMINAL_PROMPT"] = "0"

        # Check if the bare mirror is completely empty (no branches/tags, e.g. VS403403 empty TFS repo)
        ref_check = subprocess.run(
            [self.git_executable, "-c", "safe.directory=*", "show-ref"],
            cwd=mirror_path,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
        if not (ref_check.stdout or "").strip():
            return subprocess.CompletedProcess(
                args=[self.git_executable, "push"],
                returncode=0,
                stdout="Empty repository (no refs to push).",
                stderr="",
            )

        cmd = [
            self.git_executable,
            "-c", "safe.directory=*",
            "-c", "http.sslVerify=false",
            "-c", "protocol.file.allow=always",
        ]
        if self.forgejo.token:
            encoded = base64.b64encode(f"token:{self.forgejo.token}".encode("utf-8")).decode("utf-8")
            cmd.extend(["-c", f"http.extraHeader=Authorization: Basic {encoded}"])

        cmd.extend([
            "push",
            "--prune",
            forgejo_clone_url,
            "+refs/heads/*:refs/heads/*",
            "+refs/tags/*:refs/tags/*",
        ])

        try:
            return subprocess.run(
                cmd,
                cwd=mirror_path,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=self.git_timeout_seconds,
                check=False,
            )
        except subprocess.TimeoutExpired as te:
            return subprocess.CompletedProcess(
                args=cmd,
                returncode=124,
                stdout=getattr(te, "stdout", "") or "",
                stderr=f"git push to Forgejo timed out after {self.git_timeout_seconds}s.",
            )

    def sync_single_repository(
        self,
        repo: Dict[str, Any],
        local_backup_mgr: Optional[LocalBackupManager] = None,
        force: bool = False,
    ) -> Dict[str, Any]:
        """
        Synchronizes a single repository to the target Forgejo Organization.
        """
        repo_id = str(repo.get("id") or repo.get("name") or "")
        repo_name = str(repo.get("name") or repo_id)
        default_branch = str(repo.get("defaultBranch") or repo.get("default_branch") or "dev").replace("refs/heads/", "")
        is_disabled = bool(repo.get("isDisabled") or repo.get("is_disabled"))
        now_iso = datetime.now(timezone.utc).isoformat()

        forgejo_repo_web_url = f"{self.forgejo.url}/{urllib.parse.quote(self.org_name)}/{urllib.parse.quote(repo_name)}"
        forgejo_clone_url = repo.get("forgejoCloneUrl") or f"{forgejo_repo_web_url}.git"

        try:
            if self.strategy == "pull_mirror":
                # Resolve source TFS URL
                source_url = ""
                if local_backup_mgr:
                    source_url = local_backup_mgr._resolve_repo_clone_url(repo)
                elif repo.get("remoteUrl") or repo.get("webUrl"):
                    source_url = repo.get("remoteUrl") or repo.get("webUrl")

                fg_repo = self.forgejo.migrate_pull_mirror(
                    org_name=self.org_name,
                    repo_name=repo_name,
                    clone_addr=source_url,
                    auth_token=self.tfs_pat,
                    mirror=True,
                    private=True,
                )
                if isinstance(fg_repo, dict) and fg_repo.get("html_url"):
                    forgejo_repo_web_url = fg_repo["html_url"]
                status = "OK"
                err_msg = ""
            else:
                # Strategy == "push": Ensure local mirror is available and push refs to Forgejo
                mirror_path = repo.get("local_mirror_path") or ""
                if not mirror_path and local_backup_mgr:
                    mirror_path = os.path.join(local_backup_mgr.mirrors_dir, f"{repo_name}.git")

                if (not mirror_path or not os.path.isdir(mirror_path)) and local_backup_mgr:
                    b_res = local_backup_mgr.backup_single_repository(repo, force=force)
                    mirror_path = b_res.get("mirror_path") or mirror_path
                    if b_res.get("status") == "FAILED":
                        raise RuntimeError(f"Local mirror backup failed prior to Forgejo push: {b_res.get('error')}")
                elif local_backup_mgr and force:
                    local_backup_mgr.backup_single_repository(repo, force=True)

                if not mirror_path or not os.path.isdir(mirror_path):
                    raise FileNotFoundError(f"Local mirror directory not found for '{repo_name}': {mirror_path}")

                fg_repo = self.forgejo.ensure_repo(
                    org_name=self.org_name,
                    repo_name=repo_name,
                    default_branch=default_branch,
                )
                if isinstance(fg_repo, dict):
                    if fg_repo.get("html_url"):
                        forgejo_repo_web_url = fg_repo["html_url"]
                    if fg_repo.get("clone_url"):
                        forgejo_clone_url = fg_repo["clone_url"]

                push_res = self._run_git_push_to_forgejo(mirror_path, forgejo_clone_url)
                if push_res.returncode != 0:
                    raise RuntimeError(f"git push to Forgejo failed: {push_res.stderr.strip()}")

                # Sync default branch and archived state
                try:
                    self.forgejo.update_repo_metadata(
                        org_name=self.org_name,
                        repo_name=repo_name,
                        default_branch=default_branch,
                        archived=is_disabled if is_disabled else None,
                    )
                except Exception as meta_err:
                    logger.debug("Non-fatal warning updating repo metadata on Forgejo for %s: %s", repo_name, meta_err)

                status = "OK"
                err_msg = ""
        except Exception as e:
            logger.error("Forgejo sync failed for repository %s: %s", repo_name, e)
            status = "FAILED"
            err_msg = str(e)

        if self.cache_db and repo_id:
            try:
                self.cache_db.save_migration_status({
                    "repo_id": repo_id,
                    "repo_name": repo_name,
                    "project_id": self.project_id,
                    "forgejo_repo_url": forgejo_repo_web_url,
                    "last_forgejo_sync_at": now_iso,
                    "forgejo_status": status,
                    "last_error": err_msg,
                })
            except Exception as db_err:
                logger.warning("Failed to update Forgejo migration_status for %s: %s", repo_name, db_err)

        return {
            "repo_id": repo_id,
            "repo_name": repo_name,
            "org_name": self.org_name,
            "strategy": self.strategy,
            "forgejo_repo_url": forgejo_repo_web_url,
            "status": status,
            "synced_at": now_iso,
            "error": err_msg,
        }

    def sync_all_repositories(
        self,
        repos: Optional[List[Dict[str, Any]]] = None,
        submodule_map: Optional[Dict[str, List[str]]] = None,
        force: bool = False,
        progress_callback: Optional[Callable] = None,
        cancel_token: Optional[Any] = None,
    ) -> Dict[str, Any]:
        """
        Synchronizes all active project repositories to the target Forgejo Organization
        in topological order (submodules first, then parent repositories).
        """
        # 1. Ensure target Organization exists on Forgejo
        self.forgejo.ensure_org(self.org_name)

        local_backup_mgr = None
        if self.backup_dir:
            local_backup_mgr = LocalBackupManager(
                target_dir=self.backup_dir,
                mode="mirror",
                info_handler=self.info_handler,
                project_id=self.project_id,
                pat=self.tfs_pat,
                cache_db=self.cache_db,
                git_executable=self.git_executable,
                git_timeout_seconds=self.git_timeout_seconds,
            )

        if repos is None:
            if self.info_handler and self.project_id:
                try:
                    raw_repos = self.info_handler.get_repositories(self.project_id)
                    repos = [
                        r for r in raw_repos
                        if not r.get("isDisabled", False)
                        and "CANCEL" not in r.get("name", "")
                        and "DEPRECATE" not in r.get("name", "")
                    ]
                except Exception as e:
                    logger.warning("Falling back to cached repository list for Forgejo sync: %s", e)

            if repos is None and self.cache_db:
                with self.cache_db._connection() as conn:
                    rows = conn.execute(
                        "SELECT id, name, default_branch, web_url, last_push_id, is_disabled, raw_json FROM repositories WHERE is_disabled = 0 ORDER BY name"
                    ).fetchall()
                    repos = []
                    for r in rows:
                        raw_d = {}
                        if r["raw_json"]:
                            try:
                                raw_d = json.loads(r["raw_json"])
                            except Exception:
                                raw_d = {}
                        repos.append({
                            "id": r["id"],
                            "name": r["name"],
                            "defaultBranch": r["default_branch"],
                            "webUrl": r["web_url"] or raw_d.get("remoteUrl") or "",
                            "remoteUrl": raw_d.get("remoteUrl") or r["web_url"] or "",
                            "last_push_id": r["last_push_id"],
                            "isDisabled": bool(r["is_disabled"]),
                        })

        repos = list(repos or [])

        if submodule_map is None and self.cache_db:
            submodule_map = {}
            try:
                for row in self.cache_db.get_submodule_audit():
                    p_name = row.get("parent_repo_name", "")
                    c_url = row.get("proposed_relative_url") or row.get("current_url") or ""
                    c_name = _strip_git_suffix(c_url.replace("\\", "/").split("/")[-1])
                    if p_name and c_name:
                        submodule_map.setdefault(p_name, []).append(c_name)
            except Exception:
                pass

        ordered_repos = sort_repos_topologically(repos, submodule_map=submodule_map)
        total = len(ordered_repos)
        logger.info(
            "🚀 Starting Forgejo standby sync [strategy=%s, org=%s] for %d repositories -> %s",
            self.strategy, self.org_name, total, self.forgejo.url,
        )

        def _is_cancelled() -> bool:
            if not cancel_token:
                if hasattr(progress_callback, "is_cancelled") and callable(progress_callback.is_cancelled):
                    return bool(progress_callback.is_cancelled())
                return False
            if callable(cancel_token):
                return bool(cancel_token())
            return bool(getattr(cancel_token, "is_cancelled", lambda: False)())

        def _notify(cur: int, r_name: str):
            pct = int((cur / total) * 100) if total > 0 else 100
            msg = f"Syncing {r_name} to Forgejo [{self.org_name}] ({cur}/{total})..."
            logger.info("⏳ [%d/%d] (%d%%) %s", cur, total, pct, msg)
            if hasattr(progress_callback, "report_progress"):
                try:
                    progress_callback.report_progress(pct, msg)
                    return
                except Exception:
                    pass
            if not callable(progress_callback):
                return
            try:
                progress_callback(pct, msg)
            except TypeError:
                try:
                    progress_callback(msg, cur, total)
                except Exception:
                    pass

        results: List[Dict[str, Any]] = []
        ok_count = 0
        failed_count = 0

        for idx, repo in enumerate(ordered_repos, start=1):
            if _is_cancelled():
                logger.info("⏹️ Forgejo standby sync cancelled at repository %d/%d", idx, total)
                break
            r_name = repo.get("name", "")
            _notify(idx, r_name)
            res = self.sync_single_repository(
                repo,
                local_backup_mgr=local_backup_mgr,
                force=force,
            )
            results.append(res)
            if res.get("status") == "OK":
                ok_count += 1
                logger.info("✅ [%d/%d] '%s' synced -> %s", idx, total, r_name, res.get("forgejo_repo_url"))
            else:
                failed_count += 1
                logger.error("❌ [%d/%d] '%s' Forgejo sync failed: %s", idx, total, r_name, res.get("error"))

        logger.info("🏁 Forgejo standby sync completed: %d/%d OK, %d failed.", ok_count, total, failed_count)
        return {
            "project_id": self.project_id,
            "forgejo_url": self.forgejo.url,
            "org_name": self.org_name,
            "strategy": self.strategy,
            "synced_at": datetime.now(timezone.utc).isoformat(),
            "total_repositories": total,
            "ok_count": ok_count,
            "failed_count": failed_count,
            "repositories": results,
        }


