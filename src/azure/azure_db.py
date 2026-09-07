# -*- coding: UTF-8 -*-
import sqlite3
import json
import os
import contextlib
from datetime import datetime, date

class DateTimeEncoder(json.JSONEncoder):
    """
    Custom JSON encoder that serializes datetime and date objects to ISO formatted strings.
    """
    def default(self, obj):
        if isinstance(obj, (datetime, date)):
            return obj.isoformat()
        return super().default(obj)

class AzureDevOpsCache:
    """
    Manages caching of Azure DevOps (TFS) data inside an SQLite database.
    Optimizes synchronization by keeping track of repository versions and metadata.
    """

    def __init__(self, db_path):
        """
        Initializes the SQLite cache database and creates all tables if they do not exist.

        Args:
            db_path (str): Path to the SQLite database file.
        """
        self.db_path = db_path
        self._init_db()

    @contextlib.contextmanager
    def _connection(self):
        """
        Context manager for database connections. Ensures transaction integrity and closes the connection.
        """
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def _init_db(self):
        """
        Creates schema tables and indexes.
        """
        with self._connection() as conn:
            # Table: projects
            conn.execute("""
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                last_synced_at TEXT
            )""")

            # Table: repositories
            conn.execute("""
            CREATE TABLE IF NOT EXISTS repositories (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                name TEXT NOT NULL,
                is_disabled INTEGER DEFAULT 0,
                default_branch TEXT,
                web_url TEXT,
                last_push_id INTEGER,
                last_synced_at TEXT,
                raw_json TEXT
            )""")

            # Table: branches
            conn.execute("""
            CREATE TABLE IF NOT EXISTS branches (
                repo_id TEXT NOT NULL,
                name TEXT NOT NULL,
                commit_id TEXT NOT NULL,
                commit_date TEXT,
                committer_name TEXT,
                comment TEXT,
                ahead_count INTEGER DEFAULT -1,
                behind_count INTEGER DEFAULT -1,
                raw_json TEXT,
                PRIMARY KEY(repo_id, name)
            )""")

            # Table: tags
            conn.execute("""
            CREATE TABLE IF NOT EXISTS tags (
                repo_id TEXT NOT NULL,
                name TEXT NOT NULL,
                commit_id TEXT NOT NULL,
                commit_date TEXT,
                committer_name TEXT,
                comment TEXT,
                is_stable INTEGER DEFAULT 0,
                is_unstable INTEGER DEFAULT 0,
                raw_json TEXT,
                PRIMARY KEY(repo_id, name)
            )""")

            # Table: submodules
            conn.execute("""
            CREATE TABLE IF NOT EXISTS submodules (
                parent_repo_id TEXT NOT NULL,
                path TEXT NOT NULL,
                url TEXT NOT NULL,
                commit_id TEXT,
                raw_json TEXT,
                PRIMARY KEY(parent_repo_id, path)
            )""")

            # Table: pull_requests
            conn.execute("""
            CREATE TABLE IF NOT EXISTS pull_requests (
                id INTEGER PRIMARY KEY,
                repo_id TEXT NOT NULL,
                title TEXT,
                status TEXT,
                target_branch TEXT,
                source_branch TEXT,
                created_by TEXT,
                closed_by TEXT,
                closed_date TEXT,
                status_str TEXT,
                raw_json TEXT
            )""")

            # Table: work_items
            conn.execute("""
            CREATE TABLE IF NOT EXISTS work_items (
                id INTEGER PRIMARY KEY,
                title TEXT,
                type TEXT,
                state TEXT,
                assigned_to TEXT,
                changed_date TEXT,
                deleted INTEGER DEFAULT 0,
                raw_json TEXT
            )""")

            # Schema migration for existing work_items table
            try:
                conn.execute("ALTER TABLE work_items ADD COLUMN deleted INTEGER DEFAULT 0")
            except Exception:
                pass

            # Table: pipelines
            conn.execute("""
            CREATE TABLE IF NOT EXISTS pipelines (
                id INTEGER PRIMARY KEY,
                project_id TEXT NOT NULL,
                name TEXT NOT NULL,
                folder TEXT,
                revision INTEGER DEFAULT 1,
                url TEXT,
                raw_json TEXT
            )""")

            # Table: builds
            conn.execute("""
            CREATE TABLE IF NOT EXISTS builds (
                id INTEGER PRIMARY KEY,
                project_id TEXT NOT NULL,
                repo_id TEXT,
                pipeline_id INTEGER,
                build_number TEXT,
                status TEXT,
                result TEXT,
                queue_time TEXT,
                start_time TEXT,
                finish_time TEXT,
                source_branch TEXT,
                source_version TEXT,
                requested_by TEXT,
                url TEXT,
                raw_json TEXT
            )""")

            # Table: artifacts
            conn.execute("""
            CREATE TABLE IF NOT EXISTS artifacts (
                id INTEGER,
                build_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                type TEXT,
                size_bytes INTEGER DEFAULT 0,
                size_mb REAL DEFAULT 0.0,
                download_url TEXT,
                url TEXT,
                is_deleted INTEGER DEFAULT 0,
                deleted_at TEXT,
                raw_json TEXT,
                PRIMARY KEY(build_id, name)
            )""")

            # Schema migration for existing artifacts table
            try:
                conn.execute("ALTER TABLE artifacts ADD COLUMN is_deleted INTEGER DEFAULT 0")
            except Exception:
                pass
            try:
                conn.execute("ALTER TABLE artifacts ADD COLUMN deleted_at TEXT")
            except Exception:
                pass

            # Indexes for faster joins and queries
            conn.execute("CREATE INDEX IF NOT EXISTS idx_repos_project ON repositories(project_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_branches_repo ON branches(repo_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_tags_repo ON tags(repo_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_submodules_repo ON submodules(parent_repo_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_prs_repo ON pull_requests(repo_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_pipelines_project ON pipelines(project_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_builds_project ON builds(project_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_builds_repo ON builds(repo_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_builds_pipeline ON builds(pipeline_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_artifacts_build ON artifacts(build_id)")

            # View: v_branches
            conn.execute("""
            CREATE VIEW IF NOT EXISTS v_branches AS
            SELECT 
                b.repo_id,
                b.name AS branch_name,
                b.commit_id,
                b.commit_date,
                b.committer_name,
                b.comment,
                b.ahead_count,
                b.behind_count,
                b.raw_json,
                r.name AS repo_name,
                p.name AS project_name
            FROM branches b
            JOIN repositories r ON b.repo_id = r.id
            LEFT JOIN projects p ON r.project_id = p.id
            """)

            # View: v_pull_requests_tagged
            conn.execute("""
            CREATE VIEW IF NOT EXISTS v_pull_requests_tagged AS
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
                p.name AS project_name,
                json_extract(pr.raw_json, '$.lastMergeCommit.commitId') AS merge_commit_id,
                t.name AS tag_name,
                CASE WHEN t.name IS NOT NULL THEN 1 ELSE 0 END AS is_tagged
            FROM pull_requests pr
            JOIN repositories r ON pr.repo_id = r.id
            LEFT JOIN projects p ON r.project_id = p.id
            LEFT JOIN tags t ON pr.repo_id = t.repo_id AND 
                json_extract(pr.raw_json, '$.lastMergeCommit.commitId') = 
                COALESCE(json_extract(t.raw_json, '$.addinfo.taggedObject.objectId'), json_extract(t.raw_json, '$.objectId'))
            """)

            # View: v_tags
            conn.execute("""
            CREATE VIEW IF NOT EXISTS v_tags AS
            SELECT 
                t.repo_id,
                t.name AS tag_name,
                t.commit_id,
                t.commit_date,
                t.committer_name,
                t.comment,
                t.is_stable,
                t.is_unstable,
                t.raw_json,
                r.name AS repo_name,
                p.name AS project_name
            FROM tags t
            JOIN repositories r ON t.repo_id = r.id
            LEFT JOIN projects p ON r.project_id = p.id
            """)

            # View: v_builds
            conn.execute("""
            CREATE VIEW IF NOT EXISTS v_builds AS
            SELECT 
                b.id AS build_id,
                b.project_id,
                b.pipeline_id,
                b.repo_id,
                b.build_number,
                b.status,
                b.result,
                b.source_branch,
                b.source_version,
                b.queue_time,
                b.start_time,
                b.finish_time,
                b.requested_by,
                b.url,
                p.name AS project_name,
                r.name AS repo_name,
                pl.name AS pipeline_name,
                b.raw_json
            FROM builds b
            LEFT JOIN repositories r ON b.repo_id = r.id
            LEFT JOIN projects p ON b.project_id = p.id
            LEFT JOIN pipelines pl ON b.pipeline_id = pl.id
            """)

            # View: v_artifacts
            conn.execute("DROP VIEW IF EXISTS v_artifacts")
            conn.execute("""
            CREATE VIEW IF NOT EXISTS v_artifacts AS
            SELECT
                a.build_id,
                a.id AS artifact_id,
                a.name AS artifact_name,
                a.type AS resource_type,
                a.size_bytes,
                a.size_mb,
                a.download_url,
                a.url AS artifact_url,
                a.is_deleted,
                a.deleted_at,
                b.build_number,
                b.repo_id,
                r.name AS repo_name,
                p.name AS project_name,
                b.finish_time AS build_finish_time,
                b.status AS build_status,
                b.result AS build_result,
                a.raw_json
            FROM artifacts a
            JOIN builds b ON a.build_id = b.id
            LEFT JOIN repositories r ON b.repo_id = r.id
            LEFT JOIN projects p ON b.project_id = p.id
            """)

    def get_last_push_id(self, repo_id):
        """
        Gets the cached push ID of a repository.

        Args:
            repo_id (str): Repository UUID.

        Returns:
            int: The cached push ID, or None.
        """
        with self._connection() as conn:
            row = conn.execute("SELECT last_push_id FROM repositories WHERE id = ?", (repo_id,)).fetchone()
            return row["last_push_id"] if row else None

    def save_repository(self, project_id, repo, last_push_id=None):
        """
        Saves or updates a repository definition in cache.
        """
        is_disabled = 1 if repo.get("isDisabled") else 0
        raw_json = json.dumps(repo, cls=DateTimeEncoder, ensure_ascii=False)
        with self._connection() as conn:
            conn.execute("""
            INSERT INTO repositories (id, project_id, name, is_disabled, default_branch, web_url, last_push_id, raw_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                is_disabled = excluded.is_disabled,
                default_branch = excluded.default_branch,
                web_url = excluded.web_url,
                last_push_id = COALESCE(excluded.last_push_id, repositories.last_push_id),
                raw_json = excluded.raw_json
            """, (repo["id"], project_id, repo["name"], is_disabled, repo.get("defaultBranch"), repo.get("webUrl"), last_push_id, raw_json))

    def update_repo_last_push_id(self, repo_id, push_id):
        """
        Updates the cached last push ID for a repository.
        """
        with self._connection() as conn:
            conn.execute("UPDATE repositories SET last_push_id = ? WHERE id = ?", (push_id, repo_id))

    def save_branches(self, repo_id, branches):
        """
        Saves branches for a repository. Clears old branches of this repo first.
        """
        with self._connection() as conn:
            conn.execute("DELETE FROM branches WHERE repo_id = ?", (repo_id,))
            for branch in branches:
                stats = branch.get("Stats") or branch.get("stats") or {}
                ahead = stats.get("aheadCount", -1)
                behind = stats.get("behindCount", -1)
                committer_info = branch.get("LatestCommit", {}).get("committer", {})
                committer_name = committer_info.get("name", "")
                commit_date = branch.get("CommitDate", "")
                comment = branch.get("Comment", "")
                raw_json = json.dumps(branch, cls=DateTimeEncoder, ensure_ascii=False)

                conn.execute("""
                INSERT OR REPLACE INTO branches (repo_id, name, commit_id, commit_date, committer_name, comment, ahead_count, behind_count, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (repo_id, branch["FriendlyName"], branch["CommitId"], commit_date, committer_name, comment, ahead, behind, raw_json))

    def save_tags(self, repo_id, tags):
        """
        Saves tags for a repository. Clears old tags of this repo first.
        """
        with self._connection() as conn:
            conn.execute("DELETE FROM tags WHERE repo_id = ?", (repo_id,))
            for tag in tags:
                is_stable = 1 if tag.get("stable") else 0
                is_unstable = 1 if tag.get("unstable") else 0
                committer_name = tag.get("Committer", "")
                commit_date = tag.get("CommitDate", "")
                comment = tag.get("Comment", "")
                raw_json = json.dumps(tag, cls=DateTimeEncoder, ensure_ascii=False)

                conn.execute("""
                INSERT OR REPLACE INTO tags (repo_id, name, commit_id, commit_date, committer_name, comment, is_stable, is_unstable, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (repo_id, tag["FriendlyName"], tag["objectId"][:7], commit_date, committer_name, comment, is_stable, is_unstable, raw_json))

    def save_submodules(self, repo_id, submodules):
        """
        Saves submodules for a repository. Clears old submodules of this repo first.
        """
        with self._connection() as conn:
            conn.execute("DELETE FROM submodules WHERE parent_repo_id = ?", (repo_id,))
            for sub in submodules:
                commit_id = sub.get("info", {}).get("commitId", "")
                raw_json = json.dumps(sub, cls=DateTimeEncoder, ensure_ascii=False)
                conn.execute("""
                INSERT OR REPLACE INTO submodules (parent_repo_id, path, url, commit_id, raw_json)
                VALUES (?, ?, ?, ?, ?)
                """, (repo_id, sub["path"], sub["url"], commit_id, raw_json))

    def save_pull_requests(self, repo_id, prs):
        """
        Saves PRs for a repository. Clears old PRs of this repo first.
        """
        with self._connection() as conn:
            conn.execute("DELETE FROM pull_requests WHERE repo_id = ?", (repo_id,))
            for pr in prs:
                created_by = pr.get("createdBy", {}).get("displayName", "")
                closed_by = pr.get("closedBy", {}).get("displayName", "") if pr.get("closedBy") else ""
                closed_date = pr.get("closedDateStr", "")
                status_str = pr.get("statusStr", "")
                raw_json = json.dumps(pr, cls=DateTimeEncoder, ensure_ascii=False)

                conn.execute("""
                INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, status_str, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (pr["pullRequestId"], repo_id, pr.get("title"), str(pr.get("status")), pr.get("targetRefName"), pr.get("sourceRefName"), created_by, closed_by, closed_date, status_str, raw_json))

    def get_cached_repository(self, repo_id, repo_name):
        """
        Reconstructs and returns the cached dictionary structure for a specific repository.
        """
        with self._connection() as conn:
            r_row = conn.execute("SELECT * FROM repositories WHERE id = ?", (repo_id,)).fetchone()
            if not r_row:
                return None
            repo_info = json.loads(r_row["raw_json"])

            # Reconstruct branches
            branches_rows = conn.execute("SELECT * FROM v_branches WHERE repo_id = ?", (repo_id,)).fetchall()
            branches = [json.loads(b["raw_json"]) for b in branches_rows]

            # Reconstruct tags
            tags_rows = conn.execute("SELECT * FROM tags WHERE repo_id = ?", (repo_id,)).fetchall()
            tags = [json.loads(t["raw_json"]) for t in tags_rows]

            # Reconstruct submodules
            submodules_rows = conn.execute("SELECT * FROM submodules WHERE parent_repo_id = ?", (repo_id,)).fetchall()
            submodules = [json.loads(s["raw_json"]) for s in submodules_rows]

            # Reconstruct PRs
            pr_rows = conn.execute("SELECT * FROM pull_requests WHERE repo_id = ?", (repo_id,)).fetchall()
            dev_prs = []
            stable_prs = []
            for p in pr_rows:
                pr_data = json.loads(p["raw_json"])
                target = pr_data.get("targetRefName", "")
                if "dev" in target:
                    dev_prs.append(pr_data)
                else:
                    stable_prs.append(pr_data)

            # Determine Stable/Unstable tag names
            stable_tags = [t["FriendlyName"] for t in tags if t.get("stable")]
            unstable_tags = [t["FriendlyName"] for t in tags if t.get("unstable")]
            
            last_stable_tag = max(stable_tags) if stable_tags else ""
            last_unstable_tag = max(unstable_tags) if unstable_tags else ""

            return {
                "info": repo_info,
                "branches": branches,
                "tags": tags,
                "submodules": submodules,
                "devPRs": dev_prs,
                "stablePRs": stable_prs,
                "StableTag": last_stable_tag,
                "UnstableTag": last_unstable_tag
            }

    def get_all_cached_repositories(self, project_id):
        """
        Reconstructs and returns the complete nested dict cache structure mapping repository names
        to their aggregated branch, tag, PR, and submodule details.

        Returns:
            dict: Aggregated dictionary structure identical to ParseSubmodules / GetTFSRepositories output.
        """
        result = {}
        with self._connection() as conn:
            repos = conn.execute("SELECT * FROM repositories WHERE project_id = ? AND is_disabled = 0", (project_id,)).fetchall()
            for r_row in repos:
                repo_id = r_row["id"]
                repo_name = r_row["name"]
                repo_info = json.loads(r_row["raw_json"])

                # Reconstruct branches
                branches_rows = conn.execute("SELECT * FROM v_branches WHERE repo_id = ?", (repo_id,)).fetchall()
                branches = [json.loads(b["raw_json"]) for b in branches_rows]

                # Reconstruct tags
                tags_rows = conn.execute("SELECT * FROM tags WHERE repo_id = ?", (repo_id,)).fetchall()
                tags = [json.loads(t["raw_json"]) for t in tags_rows]

                # Reconstruct submodules
                submodules_rows = conn.execute("SELECT * FROM submodules WHERE parent_repo_id = ?", (repo_id,)).fetchall()
                submodules = [json.loads(s["raw_json"]) for s in submodules_rows]

                # Reconstruct PRs
                pr_rows = conn.execute("SELECT * FROM pull_requests WHERE repo_id = ?", (repo_id,)).fetchall()
                dev_prs = []
                stable_prs = []
                for p in pr_rows:
                    pr_data = json.loads(p["raw_json"])
                    # Check whether dev or stable PR (based on targetRefName)
                    target = pr_data.get("targetRefName", "")
                    if "dev" in target:
                        dev_prs.append(pr_data)
                    else:
                        stable_prs.append(pr_data)

                # Determine Stable/Unstable tag names
                stable_tags = [t["FriendlyName"] for t in tags if t.get("stable")]
                unstable_tags = [t["FriendlyName"] for t in tags if t.get("unstable")]
                
                last_stable_tag = max(stable_tags) if stable_tags else ""
                last_unstable_tag = max(unstable_tags) if unstable_tags else ""

                result[repo_name] = {
                    "info": repo_info,
                    "branches": branches,
                    "tags": tags,
                    "submodules": submodules,
                    "devPRs": dev_prs,
                    "stablePRs": stable_prs,
                    "StableTag": last_stable_tag,
                    "UnstableTag": last_unstable_tag
                }
        return result

    def save_work_item(self, wi_id, title, type_str, state, assigned_to, changed_date, raw_json_obj, deleted=0):
        """
        Saves a work item definition to the cache database.
        """
        raw_json = json.dumps(raw_json_obj, cls=DateTimeEncoder, ensure_ascii=False)
        deleted_val = 1 if deleted else 0
        with self._connection() as conn:
            conn.execute("""
            INSERT OR REPLACE INTO work_items (id, title, type, state, assigned_to, changed_date, deleted, raw_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (wi_id, title, type_str, state, assigned_to, changed_date, deleted_val, raw_json))

    def mark_work_item_deleted(self, wi_id):
        """
        Marks a specific work item as deleted in the cache database.
        Preserves existing cached metadata if present, or creates a placeholder record.
        """
        try:
            wi_int = int(str(wi_id).lstrip("#"))
        except (ValueError, TypeError):
            return 0
        with self._connection() as conn:
            cur = conn.execute("UPDATE work_items SET deleted = 1 WHERE id = ?", (wi_int,))
            if cur.rowcount == 0:
                conn.execute("""
                INSERT OR REPLACE INTO work_items (id, title, type, state, assigned_to, changed_date, deleted, raw_json)
                VALUES (?, '[deleted]', 'Unknown', 'Deleted', 'Unknown', '', 1, '{}')
                """, (wi_int,))
                return 1
            return cur.rowcount

    def get_all_work_item_ids(self, include_deleted=True):
        """
        Retrieves all work item IDs stored in the cache database.
        """
        filter_deleted = "" if include_deleted else " WHERE (deleted = 0 OR deleted IS NULL)"
        with self._connection() as conn:
            rows = conn.execute(f"SELECT id FROM work_items{filter_deleted} ORDER BY id").fetchall()
            return [r["id"] for r in rows]

    def get_all_work_items(self, include_deleted=True):
        """
        Retrieves all work items stored in the cache database as structured dictionaries.
        """
        filter_deleted = "" if include_deleted else " WHERE (deleted = 0 OR deleted IS NULL)"
        with self._connection() as conn:
            rows = conn.execute(f"""
            SELECT id, title, type, state, assigned_to, changed_date, deleted, raw_json
            FROM work_items{filter_deleted}
            ORDER BY id
            """).fetchall()
            result = []
            for row in rows:
                is_del = bool(row["deleted"]) if ("deleted" in row.keys() and row["deleted"] is not None) else False
                raw = {}
                if row["raw_json"]:
                    try:
                        raw = json.loads(row["raw_json"])
                    except Exception:
                        pass
                fields = raw.get("fields", {}) if isinstance(raw, dict) else {}
                assigned = fields.get("System.AssignedTo")
                assigned_name = ""
                if isinstance(assigned, dict):
                    assigned_name = assigned.get("displayName") or assigned.get("uniqueName") or ""
                elif isinstance(assigned, str):
                    assigned_name = assigned
                if not assigned_name or assigned_name.lower() in ("undefined", "none", "unknown"):
                    assigned_name = row["assigned_to"] or "Unassigned"

                resolved_state = row["state"] or fields.get("System.State", "") or "Active"
                resolved_type = row["type"] or fields.get("System.WorkItemType", "") or "Task"
                resolved_title = row["title"] or fields.get("System.Title", "") or f"Work Item #{row['id']}"

                result.append({
                    "id": row["id"],
                    "teamProject": fields.get("System.TeamProject"),
                    "url": raw.get("url"),
                    "htmlLink": raw.get("_links", {}).get("html", {}).get("href", ""),
                    "Title": resolved_title,
                    "title": resolved_title,
                    "WorkItemType": resolved_type,
                    "type": resolved_type,
                    "State": resolved_state,
                    "state": resolved_state,
                    "CreatedDate": fields.get("System.CreatedDate"),
                    "AssignedTo": assigned,
                    "assigned_to": assigned_name,
                    "CreatedBy": fields.get("System.CreatedBy"),
                    "ChangedBy": fields.get("System.ChangedBy"),
                    "changed_date": row["changed_date"] or fields.get("System.ChangedDate", ""),
                    "iteration_path": fields.get("System.IterationPath") or "",
                    "iteration_id": fields.get("System.IterationId"),
                    "area_path": fields.get("System.AreaPath") or "",
                    "deleted": is_del,
                    "is_deleted": 1 if is_del else 0,
                    "raw_json": row["raw_json"],
                })
            return result

    def get_all_prs(self):
        """
        Retrieves all cached pull requests with repository names and direct tag matching if available.
        """
        with self._connection() as conn:
            rows = conn.execute("""
            SELECT r.name AS repo_name, pr.target_branch, pr.source_branch, pr.id AS pr_id, pr.title, pr.status, pr.created_by, pr.closed_by, pr.closed_date, pr.status_str, pr.raw_json,
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
            return [dict(r) for r in rows]

    def get_project_last_synced(self, project_id):
        """
        Gets the last synced timestamp of a project.
        """
        with self._connection() as conn:
            row = conn.execute("SELECT last_synced_at FROM projects WHERE id = ?", (project_id,)).fetchone()
            if row and row["last_synced_at"]:
                return datetime.fromisoformat(row["last_synced_at"])
            return None

    def update_project_last_synced(self, project_id, project_name):
        """
        Updates the last synced timestamp of a project to the current time.
        """
        now_str = datetime.now().isoformat()
        with self._connection() as conn:
            conn.execute("""
            INSERT INTO projects (id, name, last_synced_at)
            VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                last_synced_at = excluded.last_synced_at
            """, (project_id, project_name, now_str))

    def save_single_pull_request(self, pr):
        """
        Saves a single pull request to the database.
        """
        repo_id = pr.get("repository", {}).get("id")
        if not repo_id:
            return
        created_by = pr.get("createdBy", {}).get("displayName", "")
        closed_by = pr.get("closedBy", {}).get("displayName", "") if pr.get("closedBy") else ""
        closed_date = pr.get("closedDateStr", "")
        status_str = pr.get("statusStr", "")
        raw_json = json.dumps(pr, cls=DateTimeEncoder, ensure_ascii=False)

        with self._connection() as conn:
            conn.execute("""
            INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, status_str, raw_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (pr["pullRequestId"], repo_id, pr.get("title"), str(pr.get("status")), pr.get("targetRefName"), pr.get("sourceRefName"), created_by, closed_by, closed_date, status_str, raw_json))

    def save_pipeline(self, project_id, pipeline):
        """
        Saves or updates a pipeline definition in the database.
        """
        pipe_id = pipeline.get("id")
        if not pipe_id:
            return
        name = pipeline.get("name", "")
        folder = pipeline.get("folder", "")
        revision = pipeline.get("revision", 1)
        url = pipeline.get("url", "")
        raw_json = json.dumps(pipeline, cls=DateTimeEncoder, ensure_ascii=False)
        with self._connection() as conn:
            conn.execute("""
            INSERT OR REPLACE INTO pipelines (id, project_id, name, folder, revision, url, raw_json)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (pipe_id, project_id, name, folder, revision, url, raw_json))

    def save_pipelines(self, project_id, pipelines):
        """
        Saves multiple pipeline definitions to the database.
        """
        for p in pipelines:
            self.save_pipeline(project_id, p)

    def save_build(self, project_id, build):
        """
        Saves or updates a build execution record and any associated artifacts.
        """
        build_id = build.get("id")
        if not build_id:
            return
        repo = build.get("repository") or {}
        repo_id = repo.get("id") if isinstance(repo, dict) else None
        definition = build.get("definition") or {}
        pipeline_id = definition.get("id") if isinstance(definition, dict) else None
        build_number = build.get("buildNumber", "")
        status = build.get("status", "")
        result = build.get("result", "")
        queue_time = build.get("queueTime", "")
        start_time = build.get("startTime", "")
        finish_time = build.get("finishTime", "")
        source_branch = build.get("sourceBranch", "")
        source_version = build.get("sourceVersion", "")
        requested_for = build.get("requestedFor") or {}
        requested_by = requested_for.get("displayName", "") if isinstance(requested_for, dict) else ""
        url = build.get("url", "")
        raw_json = json.dumps(build, cls=DateTimeEncoder, ensure_ascii=False)

        with self._connection() as conn:
            conn.execute("""
            INSERT OR REPLACE INTO builds (id, project_id, repo_id, pipeline_id, build_number, status, result,
                                           queue_time, start_time, finish_time, source_branch, source_version,
                                           requested_by, url, raw_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (build_id, project_id, repo_id, pipeline_id, build_number, status, result,
                  queue_time, start_time, finish_time, source_branch, source_version,
                  requested_by, url, raw_json))

        # Save any attached artifacts
        if "artifacts" in build and build["artifacts"]:
            self.save_artifacts(build_id, build["artifacts"])

    def save_builds(self, project_id, builds):
        """
        Saves multiple builds to the database.
        """
        for b in builds:
            self.save_build(project_id, b)

    def save_artifact(self, build_id, artifact):
        """
        Saves or updates a build artifact record.
        """
        art_id = artifact.get("id")
        name = artifact.get("name", "")
        if not name:
            return
        resource = artifact.get("resource") or {}
        res_type = resource.get("type", "") if isinstance(resource, dict) else ""
        download_url = resource.get("downloadUrl", "") if isinstance(resource, dict) else ""
        url = resource.get("url", "") if isinstance(resource, dict) else artifact.get("url", "")

        size_bytes = 0
        if "size_bytes" in artifact:
            size_raw = artifact.get("size_bytes")
        elif isinstance(resource, dict) and "properties" in resource:
            props = resource.get("properties") or {}
            size_raw = props.get("artifactsize") or props.get("itemLength") or 0
        else:
            size_raw = 0
        try:
            size_bytes = int(size_raw)
        except (ValueError, TypeError):
            size_bytes = 0
        size_mb = round(size_bytes / (1024 * 1024), 2)
        raw_json = json.dumps(artifact, cls=DateTimeEncoder, ensure_ascii=False)

        is_deleted = 1 if artifact.get("is_deleted") or artifact.get("deleted") else 0
        deleted_at = artifact.get("deleted_at")
        if is_deleted and not deleted_at:
            deleted_at = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")

        with self._connection() as conn:
            conn.execute("""
            INSERT OR REPLACE INTO artifacts (id, build_id, name, type, size_bytes, size_mb, download_url, url, is_deleted, deleted_at, raw_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (art_id, build_id, name, res_type, size_bytes, size_mb, download_url, url, is_deleted, deleted_at, raw_json))

    def save_artifacts(self, build_id, artifacts):
        """
        Saves multiple artifacts for a build.
        """
        for a in artifacts:
            self.save_artifact(build_id, a)

    def mark_build_artifacts_deleted(self, build_id, deleted_at=None):
        """
        Marks all artifacts for a given build_id as deleted.
        If no artifacts currently exist for this build, inserts a deleted placeholder.
        """
        try:
            b_int = int(build_id)
        except (ValueError, TypeError):
            return 0
        if not deleted_at:
            deleted_at = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")

        with self._connection() as conn:
            cur = conn.execute("""
            UPDATE artifacts 
            SET is_deleted = 1, deleted_at = ? 
            WHERE build_id = ?
            """, (deleted_at, b_int))
            updated_count = cur.rowcount

            if updated_count == 0:
                conn.execute("""
                INSERT OR REPLACE INTO artifacts (id, build_id, name, type, size_bytes, size_mb, is_deleted, deleted_at, raw_json)
                VALUES (NULL, ?, '[deleted]', 'Deleted', 0, 0.0, 1, ?, '{}')
                """, (b_int, deleted_at))
                updated_count = 1

            return updated_count

    def mark_artifact_deleted(self, build_id, artifact_name, deleted_at=None):
        """
        Marks a specific artifact of a build as deleted.
        """
        try:
            b_int = int(build_id)
        except (ValueError, TypeError):
            return 0
        if not deleted_at:
            deleted_at = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")

        with self._connection() as conn:
            cur = conn.execute("""
            UPDATE artifacts 
            SET is_deleted = 1, deleted_at = ? 
            WHERE build_id = ? AND name = ?
            """, (deleted_at, b_int, artifact_name))
            updated_count = cur.rowcount

            if updated_count == 0:
                conn.execute("""
                INSERT OR REPLACE INTO artifacts (id, build_id, name, type, size_bytes, size_mb, is_deleted, deleted_at, raw_json)
                VALUES (NULL, ?, ?, 'Deleted', 0, 0.0, 1, ?, '{}')
                """, (b_int, artifact_name, deleted_at))
                updated_count = 1

            return updated_count

    def get_build(self, build_id):
        """
        Retrieves a single build by ID along with its artifacts, repo name, and pipeline name.
        """
        try:
            b_int = int(build_id)
        except (ValueError, TypeError):
            return None

        with self._connection() as conn:
            row = conn.execute("""
            SELECT b.*, r.name AS repo_name, p.name AS project_name, pl.name AS pipeline_name
            FROM builds b
            LEFT JOIN repositories r ON b.repo_id = r.id
            LEFT JOIN projects p ON b.project_id = p.id
            LEFT JOIN pipelines pl ON b.pipeline_id = pl.id
            WHERE b.id = ?
            """, (b_int,)).fetchone()

        if not row:
            for alt_db in self._find_alternate_dbs():
                try:
                    alt_cache = AzureDevOpsCache(alt_db)
                    with alt_cache._connection() as alt_conn:
                        alt_row = alt_conn.execute("""
                        SELECT b.*, r.name AS repo_name, p.name AS project_name, pl.name AS pipeline_name
                        FROM builds b
                        LEFT JOIN repositories r ON b.repo_id = r.id
                        LEFT JOIN projects p ON b.project_id = p.id
                        LEFT JOIN pipelines pl ON b.pipeline_id = pl.id
                        WHERE b.id = ?
                        """, (b_int,)).fetchone()
                        if alt_row:
                            row = alt_row
                            break
                except Exception:
                    continue

        if not row:
            return None

        artifacts = self.get_build_artifacts(b_int)
        raw = {}
        if row["raw_json"]:
            try:
                raw = json.loads(row["raw_json"])
            except Exception:
                pass

        return {
            "id": row["id"],
            "project_id": row["project_id"],
            "project_name": row["project_name"] or "",
            "repo_id": row["repo_id"],
            "repo_name": row["repo_name"] or "",
            "pipeline_id": row["pipeline_id"],
            "pipeline_name": row["pipeline_name"] or "",
            "build_number": row["build_number"],
            "status": row["status"],
            "result": row["result"],
            "queue_time": row["queue_time"],
            "start_time": row["start_time"],
            "finish_time": row["finish_time"],
            "source_branch": row["source_branch"],
            "source_version": row["source_version"],
            "requested_by": row["requested_by"],
            "url": row["url"],
            "artifacts": artifacts,
            "raw": raw
        }

    def get_build_artifacts(self, build_id, include_deleted=True):
        """
        Retrieves all artifacts for a specific build.
        """
        try:
            b_int = int(build_id)
        except (ValueError, TypeError):
            return []

        filter_deleted = "" if include_deleted else " AND (is_deleted = 0 OR is_deleted IS NULL)"

        with self._connection() as conn:
            rows = conn.execute(f"""
            SELECT id, build_id, name, type, size_bytes, size_mb, download_url, url, is_deleted, deleted_at, raw_json
            FROM artifacts
            WHERE build_id = ?{filter_deleted}
            ORDER BY name
            """, (b_int,)).fetchall()

        if not rows:
            for alt_db in self._find_alternate_dbs():
                try:
                    alt_cache = AzureDevOpsCache(alt_db)
                    with alt_cache._connection() as alt_conn:
                        alt_rows = alt_conn.execute(f"""
                        SELECT id, build_id, name, type, size_bytes, size_mb, download_url, url, is_deleted, deleted_at, raw_json
                        FROM artifacts
                        WHERE build_id = ?{filter_deleted}
                        ORDER BY name
                        """, (b_int,)).fetchall()
                        if alt_rows:
                            rows = alt_rows
                            break
                except Exception:
                    continue

        return [dict(r) for r in rows]

    def get_all_builds(self, project_id=None, repo_id=None, limit=100):
        """
        Retrieves builds with repository and pipeline details.
        """
        query = """
        SELECT b.id AS build_id, b.project_id, b.pipeline_id, b.repo_id, b.build_number,
               b.status, b.result, b.source_branch, b.source_version, b.start_time,
               b.finish_time, b.requested_by, r.name AS repo_name, p.name AS project_name,
               pl.name AS pipeline_name
        FROM builds b
        LEFT JOIN repositories r ON b.repo_id = r.id
        LEFT JOIN projects p ON b.project_id = p.id
        LEFT JOIN pipelines pl ON b.pipeline_id = pl.id
        WHERE 1=1
        """
        params = []
        if project_id:
            query += " AND b.project_id = ?"
            params.append(project_id)
        if repo_id:
            query += " AND b.repo_id = ?"
            params.append(repo_id)
        query += " ORDER BY b.id DESC LIMIT ?"
        params.append(limit)

        with self._connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(r) for r in rows]

    def get_all_artifacts(self, project_id=None, limit=200, include_deleted=True):
        """
        Retrieves artifacts across builds with build metadata.
        """
        query = """
        SELECT a.build_id, a.id AS artifact_id, a.name AS artifact_name, a.type AS resource_type,
               a.size_bytes, a.size_mb, a.download_url, a.is_deleted, a.deleted_at, b.build_number, b.repo_id,
               r.name AS repo_name, b.status AS build_status, b.result AS build_result,
               b.finish_time AS build_finish_time
        FROM artifacts a
        JOIN builds b ON a.build_id = b.id
        LEFT JOIN repositories r ON b.repo_id = r.id
        WHERE 1=1
        """
        params = []
        if project_id:
            query += " AND b.project_id = ?"
            params.append(project_id)
        if not include_deleted:
            query += " AND (a.is_deleted = 0 OR a.is_deleted IS NULL)"
        query += " ORDER BY a.build_id DESC, a.name ASC LIMIT ?"
        params.append(limit)

        with self._connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(r) for r in rows]

    def get_pipeline(self, pipeline_id):
        """
        Retrieves pipeline definition by ID.
        """
        try:
            p_int = int(pipeline_id)
        except (ValueError, TypeError):
            return None

        with self._connection() as conn:
            row = conn.execute("SELECT * FROM pipelines WHERE id = ?", (p_int,)).fetchone()
            return dict(row) if row else None

    def _find_alternate_dbs(self):
        """
        Finds any other tfs cache databases in the same directory as fallback.
        """
        db_dir = os.path.dirname(self.db_path) or "."
        base_name = os.path.basename(self.db_path)
        candidates = []
        try:
            for fname in os.listdir(db_dir):
                if "tfs_cache" in fname and fname.endswith(".db") and fname != base_name:
                    candidates.append(os.path.join(db_dir, fname))
        except Exception:
            pass
        return candidates

    def get_pull_request(self, pr_id):
        """
        Retrieves a single pull request by ID with repository and author details.
        Falls back to alternate cache databases in the same directory if missing.
        """
        try:
            pr_int = int(str(pr_id).lstrip("!"))
        except (ValueError, TypeError):
            return None

        with self._connection() as conn:
            row = conn.execute("""
            SELECT pr.id, pr.repo_id, pr.title, pr.status, pr.target_branch, 
                   pr.source_branch, pr.created_by, pr.closed_by, pr.closed_date, 
                   pr.status_str, pr.raw_json, r.name AS repo_name, r.web_url AS repo_url
            FROM pull_requests pr
            LEFT JOIN repositories r ON pr.repo_id = r.id
            WHERE pr.id = ?
            """, (pr_int,)).fetchone()

        if not row:
            for alt_db in self._find_alternate_dbs():
                try:
                    alt_cache = AzureDevOpsCache(alt_db)
                    with alt_cache._connection() as alt_conn:
                        alt_row = alt_conn.execute("""
                        SELECT pr.id, pr.repo_id, pr.title, pr.status, pr.target_branch, 
                               pr.source_branch, pr.created_by, pr.closed_by, pr.closed_date, 
                               pr.status_str, pr.raw_json, r.name AS repo_name, r.web_url AS repo_url
                        FROM pull_requests pr
                        LEFT JOIN repositories r ON pr.repo_id = r.id
                        WHERE pr.id = ?
                        """, (pr_int,)).fetchone()
                        if alt_row:
                            try:
                                with self._connection() as conn:
                                    conn.execute("""
                                    INSERT OR IGNORE INTO pull_requests 
                                    (id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, status_str, raw_json)
                                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                                    """, (alt_row["id"], alt_row["repo_id"], alt_row["title"], alt_row["status"],
                                          alt_row["target_branch"], alt_row["source_branch"], alt_row["created_by"],
                                          alt_row["closed_by"], alt_row["closed_date"], alt_row["status_str"], alt_row["raw_json"]))
                            except Exception:
                                pass
                            row = alt_row
                            break
                except Exception:
                    continue

        if not row:
            return None

        raw = {}
        if row["raw_json"]:
            try:
                raw = json.loads(row["raw_json"])
            except Exception:
                pass

        repo = raw.get("repository", {}) if isinstance(raw, dict) else {}
        repo_name = row["repo_name"] or repo.get("name") or ""
        repo_url = repo.get("remoteUrl") or repo.get("webUrl") or row["repo_url"] or ""

        created_by = raw.get("createdBy", {}) if isinstance(raw, dict) else {}
        created_by_name = (
            created_by.get("displayName") if isinstance(created_by, dict) and created_by.get("displayName")
            else (row["created_by"] or "")
        )

        closed_by = raw.get("closedBy", {}) if isinstance(raw, dict) else {}
        closed_by_name = (
            closed_by.get("displayName") if isinstance(closed_by, dict) and closed_by.get("displayName")
            else (row["closed_by"] or "")
        )

        return {
            "id": row["id"],
            "repository": repo_name,
            "url": repo_url,
            "Title": row["title"] or (raw.get("title") if isinstance(raw, dict) else "") or f"!{pr_int}",
            "Description": raw.get("description", "") if isinstance(raw, dict) else "",
            "Source": row["source_branch"] or (raw.get("sourceRefName") if isinstance(raw, dict) else "") or "",
            "Target": row["target_branch"] or (raw.get("targetRefName") if isinstance(raw, dict) else "") or "",
            "CreatedBy": created_by_name,
            "ClosedBy": closed_by_name,
            "ClosedDate": row["closed_date"] or (raw.get("closedDate") if isinstance(raw, dict) else ""),
            "Status": row["status"] or (raw.get("status") if isinstance(raw, dict) else "") or row["status_str"] or ""
        }

    def get_work_item(self, work_item_id):
        """
        Retrieves a single work item by ID.
        Falls back to alternate cache databases in the same directory if missing.
        """
        try:
            wi_int = int(str(work_item_id).lstrip("#"))
        except (ValueError, TypeError):
            return None

        with self._connection() as conn:
            row = conn.execute("""
            SELECT id, title, type, state, assigned_to, changed_date, deleted, raw_json
            FROM work_items
            WHERE id = ?
            """, (wi_int,)).fetchone()

        if not row:
            for alt_db in self._find_alternate_dbs():
                try:
                    alt_cache = AzureDevOpsCache(alt_db)
                    with alt_cache._connection() as alt_conn:
                        alt_row = alt_conn.execute("""
                        SELECT id, title, type, state, assigned_to, changed_date, deleted, raw_json
                        FROM work_items
                        WHERE id = ?
                        """, (wi_int,)).fetchone()
                        if alt_row:
                            try:
                                alt_deleted = alt_row["deleted"] if "deleted" in alt_row.keys() else 0
                                with self._connection() as conn:
                                    conn.execute("""
                                    INSERT OR IGNORE INTO work_items
                                    (id, title, type, state, assigned_to, changed_date, deleted, raw_json)
                                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                                    """, (alt_row["id"], alt_row["title"], alt_row["type"], alt_row["state"],
                                          alt_row["assigned_to"], alt_row["changed_date"], alt_deleted, alt_row["raw_json"]))
                            except Exception:
                                pass
                            row = alt_row
                            break
                except Exception:
                    continue

        if not row:
            return None

        raw = {}
        if row["raw_json"]:
            try:
                raw = json.loads(row["raw_json"])
            except Exception:
                pass

        fields = raw.get("fields", {}) if isinstance(raw, dict) else {}
        assigned = fields.get("System.AssignedTo")
        assigned_name = ""
        if isinstance(assigned, dict):
            assigned_name = assigned.get("displayName") or assigned.get("uniqueName") or ""
        elif isinstance(assigned, str):
            assigned_name = assigned
        if not assigned_name or assigned_name.lower() in ("undefined", "none", "unknown"):
            assigned_name = row["assigned_to"] or "Unassigned"

        resolved_state = row["state"] or fields.get("System.State", "") or "Active"
        resolved_type = row["type"] or fields.get("System.WorkItemType", "") or "Task"
        resolved_title = row["title"] or fields.get("System.Title", "") or f"Work Item #{row['id']}"

        is_del = bool(row["deleted"]) if ("deleted" in row.keys() and row["deleted"] is not None) else False

        return {
            "id": row["id"],
            "teamProject": fields.get("System.TeamProject"),
            "url": raw.get("url"),
            "htmlLink": raw.get("_links", {}).get("html", {}).get("href", ""),
            "Title": resolved_title,
            "title": resolved_title,
            "WorkItemType": resolved_type,
            "type": resolved_type,
            "State": resolved_state,
            "state": resolved_state,
            "CreatedDate": fields.get("System.CreatedDate"),
            "AssignedTo": assigned,
            "assigned_to": assigned_name,
            "CreatedBy": fields.get("System.CreatedBy"),
            "ChangedBy": fields.get("System.ChangedBy"),
            "changed_date": row["changed_date"] or fields.get("System.ChangedDate", ""),
            "iteration_path": fields.get("System.IterationPath") or "",
            "iteration_id": fields.get("System.IterationId"),
            "area_path": fields.get("System.AreaPath") or "",
            "deleted": is_del,
            "is_deleted": 1 if is_del else 0,
            "raw_json": row["raw_json"],
        }

    def get_repository(self, name_or_id):
        """
        Retrieves repository details by repository name or id.
        """
        if not name_or_id:
            return None
        name_str = str(name_or_id).strip()
        with self._connection() as conn:
            row = conn.execute("""
            SELECT id, name, default_branch, web_url, raw_json
            FROM repositories
            WHERE name = ? OR id = ?
            """, (name_str, name_str)).fetchone()

        if not row:
            for alt_db in self._find_alternate_dbs():
                try:
                    alt_cache = AzureDevOpsCache(alt_db)
                    with alt_cache._connection() as alt_conn:
                        alt_row = alt_conn.execute("""
                        SELECT id, name, default_branch, web_url, raw_json
                        FROM repositories
                        WHERE name = ? OR id = ?
                        """, (name_str, name_str)).fetchone()
                        if alt_row:
                            row = alt_row
                            break
                except Exception:
                    continue

        if not row:
            return None

        url = row["web_url"] or ""
        if not url and row["raw_json"]:
            try:
                raw = json.loads(row["raw_json"])
                url = raw.get("remoteUrl") or raw.get("webUrl") or ""
            except Exception:
                pass

        return {
            "id": row["id"],
            "name": row["name"],
            "default_branch": row["default_branch"],
            "web_url": url,
            "url": url
        }

    def get_user(self, user_id):
        """
        Retrieves user display name by user id.
        """
        if not user_id:
            return None
        user_str = str(user_id).strip()

        with self._connection() as conn:
            # Check pull requests
            rows = conn.execute("""
            SELECT created_by, raw_json FROM pull_requests
            WHERE raw_json LIKE ? LIMIT 5
            """, (f'%"{user_str}"%',)).fetchall()
            for row in rows:
                if row["raw_json"]:
                    try:
                        raw = json.loads(row["raw_json"])
                        cb = raw.get("createdBy", {})
                        if str(cb.get("id")) == user_str:
                            return cb.get("displayName")
                        for rev in raw.get("reviewers", []):
                            if str(rev.get("id")) == user_str:
                                return rev.get("displayName")
                    except Exception:
                        pass

            # Check work items
            rows = conn.execute("""
            SELECT raw_json FROM work_items
            WHERE raw_json LIKE ? LIMIT 5
            """, (f'%"{user_str}"%',)).fetchall()
            for row in rows:
                if row["raw_json"]:
                    try:
                        raw = json.loads(row["raw_json"])
                        fields = raw.get("fields", {})
                        for k in ("System.AssignedTo", "System.CreatedBy", "System.ChangedBy"):
                            v = fields.get(k)
                            if isinstance(v, dict) and str(v.get("id")) == user_str:
                                return v.get("displayName")
                    except Exception:
                        pass
        return None


    def load_hook_data(self):
        """
        Loads all cached users, tasks, repositories, and pull requests from SQLite.
        Returns a tuple of (users, tasks, repos, prs) formatted for use in tfs_hooks.
        """
        users = {}
        tasks = {}
        repos = {}
        prs = {}

        with self._connection() as conn:
            # 1. Load repositories
            repo_rows = conn.execute("SELECT name, web_url FROM repositories").fetchall()
            for r in repo_rows:
                repos[r["name"]] = r["web_url"]

            # 2. Load work items (tasks)
            wi_rows = conn.execute("SELECT id, deleted, raw_json FROM work_items").fetchall()
            for row in wi_rows:
                wi = {}
                if row["raw_json"]:
                    try:
                        wi = json.loads(row["raw_json"])
                    except Exception:
                        pass
                fields = wi.get("fields", {})
                links = wi.get("_links", {})
                html_link = links.get("html", {}).get("href", "")
                
                assigned = fields.get("System.AssignedTo")
                if not assigned:
                    assigned = {"id": 0, "displayName": "undefined"}

                is_del = bool(row["deleted"]) if ("deleted" in row.keys() and row["deleted"] is not None) else False

                element = {
                    "id": wi.get("id") or row["id"],
                    "teamProject": fields.get("System.TeamProject"),
                    "url": wi.get("url"),
                    "htmlLink": html_link,
                    "Title": fields.get("System.Title") or "[deleted]",
                    "WorkItemType": fields.get("System.WorkItemType") or "Unknown",
                    "State": "Deleted" if is_del else fields.get("System.State"),
                    "CreatedDate": fields.get("System.CreatedDate"),
                    "AssignedTo": assigned,
                    "CreatedBy": fields.get("System.CreatedBy"),
                    "ChangedBy": fields.get("System.ChangedBy"),
                    "deleted": is_del,
                    "is_deleted": 1 if is_del else 0,
                }
                tasks[str(row["id"])] = element

                # Collect users from task
                for identity_field in ("AssignedTo", "CreatedBy", "ChangedBy"):
                    val = element.get(identity_field)
                    if isinstance(val, dict):
                        id_val = val.get("id")
                        disp_val = val.get("displayName")
                        if id_val and disp_val:
                            users[str(id_val)] = disp_val

            # 3. Load pull requests
            pr_rows = conn.execute("SELECT id, raw_json FROM pull_requests").fetchall()
            for row in pr_rows:
                pr = json.loads(row["raw_json"])
                repo = pr.get("repository", {})
                created_by = pr.get("createdBy", {})
                closed_by = pr.get("closedBy", {})

                element = {
                    "id": pr.get("pullRequestId"),
                    "repository": repo.get("name"),
                    "url": repo.get("webUrl"),
                    "Title": pr.get("title"),
                    "Description": pr.get("description", ""),
                    "Source": pr.get("sourceRefName"),
                    "Target": pr.get("targetRefName"),
                    "CreatedBy": created_by.get("displayName") if created_by else None,
                    "ClosedBy": closed_by.get("displayName") if closed_by else None,
                    "ClosedDate": pr.get("closedDate"),
                    "Status": pr.get("status")
                }
                prs[str(pr.get("pullRequestId"))] = element

                # Add repository URL to repos mapping
                repo_name = repo.get("name")
                if repo_name:
                    repos[repo_name] = repo.get("remoteUrl") or repo.get("webUrl")

                # Collect users from PR
                if created_by and created_by.get("id") and created_by.get("displayName"):
                    users[str(created_by["id"])] = created_by["displayName"]
                for reviewer in pr.get("reviewers", []):
                    r_id = reviewer.get("id")
                    r_name = reviewer.get("displayName")
                    if r_id and r_name:
                        users[str(r_id)] = r_name

        return users, tasks, repos, prs



