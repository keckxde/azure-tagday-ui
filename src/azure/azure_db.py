# -*- coding: UTF-8 -*-
import sqlite3
import json
import os
import re
import contextlib
from datetime import datetime, date

class DateTimeEncoder(json.JSONEncoder):
    """
    Custom JSON encoder that serializes datetime and date objects to ISO formatted strings.
    """
    def default(self, obj):
        if isinstance(obj, (datetime, date)):
            return obj.isoformat()
def _calculate_sprint_delta_weeks(old_iter, new_iter):
    """
    Calculates the difference in weeks between two sprint/iteration path strings.
    Positive delta means shifted to a later sprint (postponed / delayed).
    Negative delta means moved to an earlier sprint (pulled forward).
    """
    if not old_iter or not new_iter or old_iter == new_iter:
        return 0

    import re
    from datetime import date

    def _parse_sprint(s):
        clean = str(s or "").replace("\\", "/").strip("/")
        leaf = clean.split("/")[-1]
        # 4-digit year format: e.g. "Sprint 2026-31", "2026-W31", "week-2026-31"
        m1 = re.search(r'(?:sprint|week)?\s*(20\d{2})[_\-\s]+w?(\d{1,2})', leaf, re.IGNORECASE)
        if m1:
            year = int(m1.group(1))
            week = int(m1.group(2))
            return year, week, f"week-{str(year)[-2:]}{week:02d}"
        # 2-digit year format: e.g. "week-2631", "sprint-2631", "week_2631"
        m2 = re.search(r'(?:sprint|week)[_\-\s]*(\d{2})(\d{2})', leaf, re.IGNORECASE)
        if m2:
            yy = int(m2.group(1))
            ww = int(m2.group(2))
            return 2000 + yy, ww, f"week-{yy:02d}{ww:02d}"
        return None, None, leaf

    y1, w1, s1 = _parse_sprint(old_iter)
    y2, w2, s2 = _parse_sprint(new_iter)

    if y1 and w1 and y2 and w2:
        try:
            d1 = date.fromisocalendar(y1, w1, 1)
            d2 = date.fromisocalendar(y2, w2, 1)
            return (d2 - d1).days // 7
        except Exception:
            return (y2 - y1) * 52 + (w2 - w1)
    return 0


def _is_scheduled_sprint(iteration_str):
    """
    Determines if an iteration path represents an already scheduled sprint/iteration
    (e.g., 'week-2631', 'Sprint 2026-31', 'Iteration 4') rather than unassigned backlog or project root.
    """
    if not iteration_str:
        return False
    clean = str(iteration_str).strip().replace("\\", "/").strip("/")
    if not clean:
        return False
    leaf = clean.split("/")[-1].strip()
    leaf_lower = leaf.lower()
    if leaf_lower in ("", "backlog", "unassigned", "none", "root", "future"):
        return False

    import re
    # Check if leaf contains sprint/week/iteration indicators or year/week numbers
    if re.search(r'(?:sprint|week|iteration|\bw\d{1,2}\b|\b20\d{2}[_\-\s]w?\d{1,2}\b|\b\d{2}\d{2}\b)', leaf, re.IGNORECASE):
        return True

    # If path has sub-iteration components (more than 1 segment and leaf isn't backlog/root)
    parts = [p for p in clean.split("/") if p.strip()]
    if len(parts) > 1 and leaf_lower not in ("backlog", "unassigned", "none"):
        return True

    return False


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

            # Table: iteration_shifts
            conn.execute("""
            CREATE TABLE IF NOT EXISTS iteration_shifts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                work_item_id INTEGER NOT NULL,
                title TEXT,
                type TEXT,
                assigned_to TEXT,
                old_iteration TEXT,
                new_iteration TEXT,
                old_sprint TEXT,
                new_sprint TEXT,
                delta_weeks INTEGER DEFAULT 0,
                source TEXT DEFAULT 'tfs_sync',
                recorded_at TEXT NOT NULL,
                review_status TEXT DEFAULT 'pending',
                reviewed_at TEXT,
                reviewed_by TEXT
            )""")

            # Schema migrations for iteration_shifts
            try:
                conn.execute("ALTER TABLE iteration_shifts ADD COLUMN review_status TEXT DEFAULT 'pending'")
            except Exception:
                pass
            try:
                conn.execute("ALTER TABLE iteration_shifts ADD COLUMN reviewed_at TEXT")
            except Exception:
                pass
            try:
                conn.execute("ALTER TABLE iteration_shifts ADD COLUMN reviewed_by TEXT")
            except Exception:
                pass

            # Table: project_config (stores environment & project configuration previously kept in .env)
            conn.execute("""
            CREATE TABLE IF NOT EXISTS project_config (
                key TEXT PRIMARY KEY,
                value TEXT,
                updated_at TEXT NOT NULL
            )""")

            # Table: milestone_categories
            conn.execute("""
            CREATE TABLE IF NOT EXISTS milestone_categories (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color TEXT NOT NULL,
                bg_color TEXT NOT NULL,
                icon TEXT NOT NULL,
                sort_order INTEGER DEFAULT 0
            )""")

            # Table: milestones
            conn.execute("""
            CREATE TABLE IF NOT EXISTS milestones (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                target_date TEXT NOT NULL,
                end_date TEXT,
                category_id TEXT NOT NULL,
                description TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(category_id) REFERENCES milestone_categories(id)
            )""")

            # Schema migration for existing milestones table
            try:
                conn.execute("ALTER TABLE milestones ADD COLUMN end_date TEXT")
            except Exception:
                pass

            # Populate default milestone categories if none exist
            try:
                cat_count = conn.execute("SELECT COUNT(*) AS c FROM milestone_categories").fetchone()["c"]
                if cat_count == 0:
                    default_cats = [
                        ("ddqs", "Internal Process (DDQS)", "#bc8cff", "#2c1b4d", "⚙️", 1),
                        ("qiav", "External Process (QIAV)", "#58a6ff", "#0d2344", "🔷", 2),
                        ("scenario", "External Scenario", "#f0883e", "#3d2800", "🚀", 3),
                        ("release", "Release Milestone", "#3fb950", "#162b20", "🏁", 4),
                        ("general", "General Milestone", "#79c0ff", "#16243b", "🚩", 5),
                    ]
                    conn.executemany("""
                    INSERT INTO milestone_categories (id, name, color, bg_color, icon, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, default_cats)
            except Exception:
                pass

            # Table: repo_categories
            conn.execute("""
            CREATE TABLE IF NOT EXISTS repo_categories (
                name TEXT PRIMARY KEY,
                color TEXT NOT NULL,
                bg_color TEXT,
                sort_order INTEGER DEFAULT 0,
                is_default INTEGER DEFAULT 0
            )""")

            # Table: repo_prefix_rules
            conn.execute("""
            CREATE TABLE IF NOT EXISTS repo_prefix_rules (
                prefix TEXT PRIMARY KEY,
                category TEXT NOT NULL
            )""")

            # Table: repo_category_overrides
            conn.execute("""
            CREATE TABLE IF NOT EXISTS repo_category_overrides (
                repo_name TEXT PRIMARY KEY,
                category TEXT NOT NULL
            )""")

            # Populate default repo categories if none exist
            try:
                rc_count = conn.execute("SELECT COUNT(*) AS c FROM repo_categories").fetchone()["c"]
                if rc_count == 0:
                    default_repo_cats = [
                        ("CORE", "#1f6feb", "#0d2344", 1, 0),
                        ("CORE APPS", "#238636", "#162b20", 2, 0),
                        ("GENERIC", "#6e40c9", "#261b4d", 3, 0),
                        ("3RDPARTY", "#d29922", "#3d2800", 4, 0),
                        ("OTHERS", "#6e7681", "#21262d", 5, 1),
                    ]
                    conn.executemany("""
                    INSERT OR IGNORE INTO repo_categories (name, color, bg_color, sort_order, is_default)
                    VALUES (?, ?, ?, ?, ?)
                    """, default_repo_cats)

                    default_rules = [
                        ("generic-", "GENERIC"),
                        ("3rdparty-", "3RDPARTY"),
                    ]
                    conn.executemany("""
                    INSERT OR IGNORE INTO repo_prefix_rules (prefix, category)
                    VALUES (?, ?)
                    """, default_rules)
            except Exception:
                pass

            # Indexes for faster joins and queries
            conn.execute("CREATE INDEX IF NOT EXISTS idx_milestones_date ON milestones(target_date)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_milestones_cat ON milestones(category_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_repos_project ON repositories(project_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_branches_repo ON branches(repo_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_tags_repo ON tags(repo_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_submodules_repo ON submodules(parent_repo_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_prs_repo ON pull_requests(repo_id)")
            
            # Table: cached_iterations (stores advance prepared weekly iterations)
            conn.execute("""
            CREATE TABLE IF NOT EXISTS cached_iterations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project TEXT,
                iteration_name TEXT NOT NULL,
                iteration_path TEXT,
                start_date TEXT,
                end_date TEXT,
                year INTEGER,
                week INTEGER,
                is_server_synced INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                UNIQUE(project, iteration_name)
            )""")

            # Indices
            conn.execute("CREATE INDEX IF NOT EXISTS idx_pipelines_project ON pipelines(project_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_builds_project ON builds(project_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_builds_repo ON builds(repo_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_builds_pipeline ON builds(pipeline_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_artifacts_build ON artifacts(build_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_shifts_wi ON iteration_shifts(work_item_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_shifts_date ON iteration_shifts(recorded_at)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_cached_iter_proj ON cached_iterations(project)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_cached_iter_name ON cached_iterations(iteration_name)")

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

    def get_config(self, key, default=None):
        """
        Retrieves a project configuration value by key.
        """
        try:
            with self._connection() as conn:
                row = conn.execute("SELECT value FROM project_config WHERE key = ?", (key,)).fetchone()
                return row["value"] if row and row["value"] is not None else default
        except Exception:
            return default

    def set_config(self, key, value):
        """
        Sets or updates a project configuration value.
        """
        now_str = datetime.now().isoformat()
        val_str = str(value) if value is not None else ""
        with self._connection() as conn:
            conn.execute("""
            INSERT INTO project_config (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = excluded.updated_at
            """, (key, val_str, now_str))

    def get_all_config(self):
        """
        Returns all project configuration key-value pairs as a dictionary.
        """
        try:
            with self._connection() as conn:
                rows = conn.execute("SELECT key, value FROM project_config").fetchall()
                return {row["key"]: row["value"] for row in rows}
        except Exception:
            return {}

    def set_many_config(self, config_dict):
        """
        Sets or updates multiple project configuration values in a single transaction.
        """
        if not config_dict:
            return
        now_str = datetime.now().isoformat()
        with self._connection() as conn:
            for k, v in config_dict.items():
                val_str = str(v) if v is not None else ""
                conn.execute("""
                INSERT INTO project_config (key, value, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value,
                    updated_at = excluded.updated_at
                """, (k, val_str, now_str))

    def get_milestone_categories(self):
        """Returns all milestone categories sorted by sort_order ascending."""
        try:
            with self._connection() as conn:
                rows = conn.execute("""
                SELECT id, name, color, bg_color, icon, sort_order
                FROM milestone_categories
                ORDER BY sort_order ASC, name ASC
                """).fetchall()
                return [dict(r) for r in rows]
        except Exception:
            return []

    def save_milestone_category(self, cat_id, name, color, bg_color, icon, sort_order=0):
        """Creates or updates a milestone category."""
        import re
        clean_name = (name or "").strip()
        clean_id = (cat_id or "").strip().lower()
        if not clean_id:
            clean_id = re.sub(r'[^a-z0-9_]+', '_', clean_name.lower()).strip('_')
        if not clean_id:
            clean_id = "category"
        clean_color = (color or "#79c0ff").strip()
        clean_bg = (bg_color or "#16243b").strip()
        clean_icon = (icon or "🚩").strip()

        with self._connection() as conn:
            conn.execute("""
            INSERT INTO milestone_categories (id, name, color, bg_color, icon, sort_order)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                color = excluded.color,
                bg_color = excluded.bg_color,
                icon = excluded.icon,
                sort_order = excluded.sort_order
            """, (clean_id, clean_name, clean_color, clean_bg, clean_icon, int(sort_order or 0)))
        return clean_id

    def delete_milestone_category(self, cat_id):
        """Deletes a milestone category and its associated milestones."""
        try:
            with self._connection() as conn:
                conn.execute("DELETE FROM milestones WHERE category_id = ?", (str(cat_id),))
                conn.execute("DELETE FROM milestone_categories WHERE id = ?", (str(cat_id),))
            return True
        except Exception:
            return False

    def get_milestones(self):
        """Returns all milestones joined with category information sorted by target_date ascending."""
        try:
            with self._connection() as conn:
                rows = conn.execute("""
                SELECT 
                    m.id,
                    m.name,
                    m.target_date,
                    COALESCE(m.end_date, m.target_date) AS end_date,
                    m.category_id,
                    m.description,
                    m.created_at,
                    m.updated_at,
                    COALESCE(c.name, 'General') AS category_name,
                    COALESCE(c.color, '#79c0ff') AS category_color,
                    COALESCE(c.bg_color, '#16243b') AS category_bg_color,
                    COALESCE(c.icon, '🚩') AS category_icon
                FROM milestones m
                LEFT JOIN milestone_categories c ON m.category_id = c.id
                ORDER BY m.target_date ASC, m.name ASC
                """).fetchall()
                results = []
                for r in rows:
                    item = dict(r)
                    start_d = (item.get("target_date") or "").strip()
                    end_d = (item.get("end_date") or start_d).strip()
                    item["start_date"] = start_d
                    item["end_date"] = end_d

                    is_multi = False
                    duration = 1
                    if start_d and end_d and end_d != start_d:
                        try:
                            s_obj = datetime.strptime(start_d.split("T")[0].split(" ")[0], "%Y-%m-%d").date()
                            e_obj = datetime.strptime(end_d.split("T")[0].split(" ")[0], "%Y-%m-%d").date()
                            if e_obj > s_obj:
                                is_multi = True
                                duration = (e_obj - s_obj).days + 1
                        except Exception:
                            pass

                    item["is_multi_day"] = is_multi
                    item["duration_days"] = duration
                    if is_multi:
                        item["date_display"] = f"{start_d} – {end_d}"
                    else:
                        item["date_display"] = start_d
                    results.append(item)
                return results
        except Exception:
            return []

    def save_milestone(self, name, target_date, category_id, description="", milestone_id=0, end_date=""):
        """Creates or updates a milestone, supporting single-day or multi-day date ranges."""
        now_str = datetime.now().isoformat()
        clean_name = (name or "").strip()
        clean_date = (target_date or "").strip()
        clean_end_date = (end_date or "").strip()
        clean_cat = (category_id or "general").strip()
        clean_desc = (description or "").strip()

        if clean_end_date and clean_date:
            try:
                s_obj = datetime.strptime(clean_date.split("T")[0].split(" ")[0], "%Y-%m-%d").date()
                e_obj = datetime.strptime(clean_end_date.split("T")[0].split(" ")[0], "%Y-%m-%d").date()
                if e_obj < s_obj:
                    clean_date, clean_end_date = clean_end_date, clean_date
            except Exception:
                pass
        elif not clean_end_date:
            clean_end_date = clean_date

        with self._connection() as conn:
            if milestone_id and int(milestone_id) > 0:
                conn.execute("""
                UPDATE milestones
                SET name = ?, target_date = ?, end_date = ?, category_id = ?, description = ?, updated_at = ?
                WHERE id = ?
                """, (clean_name, clean_date, clean_end_date, clean_cat, clean_desc, now_str, int(milestone_id)))
                return int(milestone_id)
            else:
                cursor = conn.execute("""
                INSERT INTO milestones (name, target_date, end_date, category_id, description, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (clean_name, clean_date, clean_end_date, clean_cat, clean_desc, now_str, now_str))
                return cursor.lastrowid

    def delete_milestone(self, milestone_id):
        """Deletes a milestone by ID."""
        try:
            with self._connection() as conn:
                conn.execute("DELETE FROM milestones WHERE id = ?", (int(milestone_id),))
            return True
        except Exception:
            return False

    def discover_and_prefill_milestones_from_work_items(self):
        """
        Scans all cached work items for tags matching 'Target:<TargetShortName>'.
        For each unique target short name discovered that does not already exist in the milestones table,
        creates a new milestone with inferred category and the most representative target date from those items.

        Returns:
            list of dict: The newly created milestones.
        """
        from collections import Counter
        with self._connection() as conn:
            rows = conn.execute("SELECT id, raw_json FROM work_items WHERE deleted = 0").fetchall()
            discovered = {}
            for r in rows:
                raw_s = r["raw_json"]
                if not raw_s:
                    continue
                try:
                    data = json.loads(raw_s) if isinstance(raw_s, str) else raw_s
                    fields = data.get("fields", {}) if isinstance(data, dict) else {}
                    tags_str = fields.get("System.Tags") or fields.get("Tags") or data.get("tags") or ""
                    if not tags_str:
                        continue

                    wi_date = (
                        fields.get("Microsoft.VSTS.Scheduling.TargetDate")
                        or fields.get("System.TargetDate")
                        or fields.get("Microsoft.VSTS.Scheduling.DueDate")
                        or fields.get("System.DueDate")
                        or data.get("target_date")
                        or data.get("finish_date")
                        or data.get("due_date")
                        or ""
                    )
                    if wi_date:
                        wi_date = str(wi_date).split("T")[0].split(" ")[0].strip()

                    for part in re.split(r'[;,]', tags_str):
                        part = part.strip()
                        m = re.match(r"^Target\s*:\s*(.+)$", part, re.IGNORECASE)
                        if m:
                            short_name = m.group(1).strip()
                            if short_name:
                                if short_name not in discovered:
                                    discovered[short_name] = []
                                if wi_date:
                                    discovered[short_name].append(wi_date)
                except Exception:
                    continue

            if not discovered:
                return []

            existing_rows = conn.execute("SELECT name FROM milestones").fetchall()
            existing_names_lower = {
                r["name"].lower().strip() for r in existing_rows if r["name"]
            }
            for r in existing_rows:
                nm = (r["name"] or "").lower().strip()
                if nm.startswith("target:"):
                    existing_names_lower.add(nm.split("target:", 1)[1].strip())

            newly_added = []
            now_str = datetime.now().isoformat()

            for short_name, dates_list in discovered.items():
                if short_name.lower() in existing_names_lower:
                    continue

                sn_lower = short_name.lower()
                if "qiav" in sn_lower:
                    cat_id = "qiav"
                elif "ddqs" in sn_lower:
                    cat_id = "ddqs"
                elif "scen" in sn_lower:
                    cat_id = "scenario"
                elif "rel" in sn_lower or "release" in sn_lower or re.match(r"^v\d+", sn_lower):
                    cat_id = "release"
                else:
                    cat_id = "general"

                chosen_date = ""
                if dates_list:
                    counts = Counter(dates_list)
                    chosen_date = counts.most_common(1)[0][0]

                desc = f"Auto-discovered from work item tag Target:{short_name}"

                cursor = conn.execute("""
                INSERT INTO milestones (name, target_date, category_id, description, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, (short_name, chosen_date, cat_id, desc, now_str, now_str))

                new_id = cursor.lastrowid
                existing_names_lower.add(short_name.lower())
                newly_added.append({
                    "id": new_id,
                    "name": short_name,
                    "target_date": chosen_date,
                    "category_id": cat_id,
                    "description": desc,
                })

            return newly_added

    def get_repo_categories(self):
        """Returns all repository categories sorted by sort_order ascending."""
        try:
            with self._connection() as conn:
                rows = conn.execute("""
                SELECT name, color, bg_color, sort_order, is_default
                FROM repo_categories
                ORDER BY sort_order ASC, name ASC
                """).fetchall()
                return [dict(r) for r in rows]
        except Exception:
            return []

    def save_repo_category(self, name, color, bg_color="", sort_order=0, is_default=False):
        """Creates or updates a repository category."""
        clean_name = (name or "").strip()
        if not clean_name:
            return False
        clean_color = (color or "#6e7681").strip()
        clean_bg = (bg_color or "").strip()
        is_def_val = 1 if is_default else 0

        with self._connection() as conn:
            if is_def_val:
                conn.execute("UPDATE repo_categories SET is_default = 0")
            conn.execute("""
            INSERT INTO repo_categories (name, color, bg_color, sort_order, is_default)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                color = excluded.color,
                bg_color = excluded.bg_color,
                sort_order = excluded.sort_order,
                is_default = excluded.is_default
            """, (clean_name, clean_color, clean_bg, int(sort_order or 0), is_def_val))
        return True

    def delete_repo_category(self, name):
        """Deletes a repository category and cleans up rules referencing it."""
        try:
            with self._connection() as conn:
                conn.execute("DELETE FROM repo_prefix_rules WHERE category = ?", (str(name),))
                conn.execute("DELETE FROM repo_category_overrides WHERE category = ?", (str(name),))
                conn.execute("DELETE FROM repo_categories WHERE name = ?", (str(name),))
            return True
        except Exception:
            return False

    def get_repo_prefix_rules(self):
        """Returns all repository prefix rules."""
        try:
            with self._connection() as conn:
                rows = conn.execute("""
                SELECT prefix, category
                FROM repo_prefix_rules
                ORDER BY prefix ASC
                """).fetchall()
                return [dict(r) for r in rows]
        except Exception:
            return []

    def save_repo_prefix_rule(self, prefix, category):
        """Creates or updates a repository prefix rule."""
        clean_prefix = (prefix or "").strip().lower()
        clean_cat = (category or "").strip()
        if not clean_prefix or not clean_cat:
            return False
        with self._connection() as conn:
            conn.execute("""
            INSERT INTO repo_prefix_rules (prefix, category)
            VALUES (?, ?)
            ON CONFLICT(prefix) DO UPDATE SET
                category = excluded.category
            """, (clean_prefix, clean_cat))
        return True

    def delete_repo_prefix_rule(self, prefix):
        """Deletes a repository prefix rule."""
        try:
            with self._connection() as conn:
                conn.execute("DELETE FROM repo_prefix_rules WHERE prefix = ?", (str(prefix),))
            return True
        except Exception:
            return False

    def get_repo_category_overrides(self):
        """Returns explicit repository category mappings as a dictionary {repo_name: category}."""
        try:
            with self._connection() as conn:
                rows = conn.execute("SELECT repo_name, category FROM repo_category_overrides").fetchall()
                return {r["repo_name"]: r["category"] for r in rows}
        except Exception:
            return {}

    def save_repo_category_override(self, repo_name, category):
        """Saves an explicit category assignment for a repository."""
        clean_name = (repo_name or "").strip()
        clean_cat = (category or "").strip()
        if not clean_name or not clean_cat:
            return False
        with self._connection() as conn:
            conn.execute("""
            INSERT INTO repo_category_overrides (repo_name, category)
            VALUES (?, ?)
            ON CONFLICT(repo_name) DO UPDATE SET
                category = excluded.category
            """, (clean_name, clean_cat))
        return True

    def delete_repo_category_override(self, repo_name):
        """Removes explicit category assignment for a repository."""
        try:
            with self._connection() as conn:
                conn.execute("DELETE FROM repo_category_overrides WHERE repo_name = ?", (str(repo_name),))
            return True
        except Exception:
            return False

    def get_full_repo_category_config(self):
        """Returns the full repository category configuration dictionary compatible with utils.categorize_repository."""
        cats = self.get_repo_categories()
        rules = self.get_repo_prefix_rules()
        overrides = self.get_repo_category_overrides()

        default_cat = "OTHERS"
        colors = {}
        for c in cats:
            cname = c["name"]
            colors[cname] = c["color"]
            if c.get("is_default"):
                default_cat = cname

        prefix_rules = {r["prefix"]: r["category"] for r in rules}

        return {
            "default_category": default_cat,
            "category_colors": colors,
            "prefix_rules": prefix_rules,
            "repositories": overrides,
        }

    def save_full_repo_category_config(self, config_dict):
        """Persists a complete repository categories configuration dictionary into the database."""
        if not config_dict or not isinstance(config_dict, dict):
            return False
        default_cat = config_dict.get("default_category", "OTHERS")
        colors = config_dict.get("category_colors", {})
        prefix_rules = config_dict.get("prefix_rules", {})
        repos_map = config_dict.get("repositories", {})

        with self._connection() as conn:
            conn.execute("DELETE FROM repo_categories")
            conn.execute("DELETE FROM repo_prefix_rules")
            conn.execute("DELETE FROM repo_category_overrides")

            order = 1
            all_cat_names = list(colors.keys())
            if default_cat not in all_cat_names:
                all_cat_names.append(default_cat)

            for cname in all_cat_names:
                col = colors.get(cname, "#6e7681")
                is_def = 1 if cname == default_cat else 0
                conn.execute("""
                INSERT INTO repo_categories (name, color, bg_color, sort_order, is_default)
                VALUES (?, ?, ?, ?, ?)
                """, (cname, col, "", order, is_def))
                order += 1

            for pfx, cname in prefix_rules.items():
                conn.execute("""
                INSERT INTO repo_prefix_rules (prefix, category)
                VALUES (?, ?)
                """, (pfx, cname))

            for rname, cname in repos_map.items():
                conn.execute("""
                INSERT INTO repo_category_overrides (repo_name, category)
                VALUES (?, ?)
                """, (rname, cname))
        return True

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
        Saves or updates PRs for a repository in the database without deleting previously cached PRs.
        """
        if not prs:
            return
        from utils import normalize_pr_status
        with self._connection() as conn:
            for pr in prs:
                pr_id = pr.get("pullRequestId") or pr.get("id")
                if not pr_id:
                    continue
                created_by = pr.get("createdBy", {}).get("displayName", "") if isinstance(pr.get("createdBy"), dict) else str(pr.get("createdBy") or "")
                closed_by = pr.get("closedBy", {}).get("displayName", "") if isinstance(pr.get("closedBy"), dict) else str(pr.get("closedBy") or "")
                closed_date = pr.get("closedDateStr", "")
                creation_date = pr.get("creationDateStr", "")
                norm_status = normalize_pr_status(pr.get("status"))
                status_str = pr.get("statusStr", "")
                if not status_str:
                    if norm_status == "completed":
                        status_str = f"DON {closed_date}"
                    elif norm_status == "abandoned":
                        status_str = f"ABANDONED {closed_date}"
                    else:
                        status_str = f"OPN {creation_date}"
                raw_json = json.dumps(pr, cls=DateTimeEncoder, ensure_ascii=False)

                conn.execute("""
                INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, status_str, raw_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (int(pr_id), repo_id, pr.get("title"), norm_status, pr.get("targetRefName"), pr.get("sourceRefName"), created_by, closed_by, closed_date, status_str, raw_json))

    def get_pr_ids_for_repo(self, repo_id):
        """
        Retrieves a set of all integer PR IDs currently stored in SQLite for a repository.
        """
        with self._connection() as conn:
            rows = conn.execute("SELECT id FROM pull_requests WHERE repo_id = ?", (repo_id,)).fetchall()
            return {int(r["id"]) for r in rows if r["id"] is not None}

    def get_active_pull_requests(self, repo_id=None):
        """
        Retrieves all PRs currently stored in the database with active status ('active', '1', 'open', or 'OPN%').
        """
        with self._connection() as conn:
            if repo_id:
                rows = conn.execute(
                    "SELECT * FROM pull_requests WHERE repo_id = ? AND (status IN ('1', 'active', 'open', 'in_progress') OR status_str LIKE 'OPN%')",
                    (repo_id,)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM pull_requests WHERE status IN ('1', 'active', 'open', 'in_progress') OR status_str LIKE 'OPN%'"
                ).fetchall()
            return [dict(r) for r in rows]

    def get_max_pr_id(self, repo_id=None):
        """
        Retrieves the maximum Pull Request ID stored in the database (optionally filtered by repo_id).
        Returns 0 if no pull requests exist.
        """
        with self._connection() as conn:
            if repo_id:
                row = conn.execute("SELECT MAX(id) as max_id FROM pull_requests WHERE repo_id = ?", (repo_id,)).fetchone()
            else:
                row = conn.execute("SELECT MAX(id) as max_id FROM pull_requests").fetchone()
            if row and row["max_id"] is not None:
                return int(row["max_id"])
            return 0

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

    def _record_shift_in_conn(self, conn, wi_id, old_iter, new_iter, source="tfs_sync", title="", type_str="", assigned_to=""):
        """Internal helper to record an iteration shift event in SQLite."""
        if not old_iter or not new_iter or old_iter == new_iter:
            return

        import re
        def _get_leaf(s):
            clean = str(s or "").replace("\\", "/").strip("/")
            return clean.split("/")[-1]

        s1 = _get_leaf(old_iter)
        s2 = _get_leaf(new_iter)
        delta = _calculate_sprint_delta_weeks(old_iter, new_iter)

        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        conn.execute("""
        INSERT INTO iteration_shifts (work_item_id, title, type, assigned_to, old_iteration, new_iteration, old_sprint, new_sprint, delta_weeks, source, recorded_at, review_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (wi_id, title or "", type_str or "", assigned_to or "", old_iter, new_iter, s1 or old_iter, s2 or new_iter, delta, source, now_str, "pending"))

    def save_work_item(self, wi_id, title, type_str, state, assigned_to, changed_date, raw_json_obj, deleted=0):
        """
        Saves a work item definition to the cache database and tracks iteration changes.
        """
        try:
            wi_int = int(str(wi_id).lstrip("#"))
        except (ValueError, TypeError):
            wi_int = wi_id

        raw_json = json.dumps(raw_json_obj, cls=DateTimeEncoder, ensure_ascii=False)
        deleted_val = 1 if deleted else 0

        new_fields = raw_json_obj.get("fields", {}) if isinstance(raw_json_obj, dict) else {}
        new_iter = new_fields.get("System.IterationPath") or ""

        with self._connection() as conn:
            if new_iter:
                old_row = conn.execute("SELECT raw_json FROM work_items WHERE id = ?", (wi_int,)).fetchone()
                if old_row and old_row["raw_json"]:
                    try:
                        old_raw = json.loads(old_row["raw_json"])
                        old_fields = old_raw.get("fields", {}) if isinstance(old_raw, dict) else {}
                        old_iter = old_fields.get("System.IterationPath") or ""
                        if old_iter and old_iter != new_iter:
                            self._record_shift_in_conn(
                                conn,
                                wi_int,
                                old_iter,
                                new_iter,
                                source="tfs_sync",
                                title=title,
                                type_str=type_str,
                                assigned_to=assigned_to
                            )
                    except Exception:
                        pass

            conn.execute("""
            INSERT OR REPLACE INTO work_items (id, title, type, state, assigned_to, changed_date, deleted, raw_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (wi_int, title, type_str, state, assigned_to, changed_date, deleted_val, raw_json))

    def update_work_item_iteration(self, wi_id, new_iteration_path, source="gui_manual"):
        """
        Updates the System.IterationPath of a cached work item in SQLite and records the shift event.

        Args:
            wi_id (int/str): Work item ID.
            new_iteration_path (str): Target iteration path.
            source (str): 'gui_manual' or 'tfs_sync'.

        Returns:
            bool: True if updated, False otherwise.
        """
        try:
            wi_int = int(str(wi_id).lstrip("#"))
        except (ValueError, TypeError):
            return False

        with self._connection() as conn:
            row = conn.execute("SELECT * FROM work_items WHERE id = ?", (wi_int,)).fetchone()
            if not row:
                return False

            raw_s = row["raw_json"]
            raw_obj = {}
            if raw_s:
                try:
                    raw_obj = json.loads(raw_s)
                except Exception:
                    raw_obj = {}

            if not isinstance(raw_obj, dict):
                raw_obj = {}
            if "fields" not in raw_obj or not isinstance(raw_obj["fields"], dict):
                raw_obj["fields"] = {}

            old_iter = raw_obj["fields"].get("System.IterationPath") or ""
            raw_obj["fields"]["System.IterationPath"] = new_iteration_path

            if old_iter != new_iteration_path:
                self._record_shift_in_conn(
                    conn,
                    wi_int,
                    old_iter,
                    new_iteration_path,
                    source=source,
                    title=row["title"],
                    type_str=row["type"],
                    assigned_to=row["assigned_to"]
                )

            updated_raw = json.dumps(raw_obj, cls=DateTimeEncoder, ensure_ascii=False)
            conn.execute("UPDATE work_items SET raw_json = ? WHERE id = ?", (updated_raw, wi_int))
            return True

    def update_shift_review_status(self, shift_id, status="accepted", reviewed_by="User"):
        """
        Updates the review status of an individual iteration shift event.
        """
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with self._connection() as conn:
            cur = conn.execute("""
                UPDATE iteration_shifts 
                SET review_status = ?, reviewed_at = ?, reviewed_by = ?
                WHERE id = ?
            """, (status, now_str if status == "accepted" else None, reviewed_by if status == "accepted" else None, int(shift_id)))
            return cur.rowcount > 0

    def update_work_item_shifts_review_status(self, work_item_id, status="accepted", reviewed_by="User"):
        """
        Updates the review status of all iteration shift events for a specific work item.
        """
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        wi_int = int(str(work_item_id).lstrip("#"))
        with self._connection() as conn:
            cur = conn.execute("""
                UPDATE iteration_shifts 
                SET review_status = ?, reviewed_at = ?, reviewed_by = ?
                WHERE work_item_id = ?
            """, (status, now_str if status == "accepted" else None, reviewed_by if status == "accepted" else None, wi_int))
            return cur.rowcount > 0

    def update_all_shifts_review_status(self, status="accepted", reviewed_by="User"):
        """
        Bulk updates review status for all shift records.
        """
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with self._connection() as conn:
            cur = conn.execute("""
                UPDATE iteration_shifts 
                SET review_status = ?, reviewed_at = ?, reviewed_by = ?
            """, (status, now_str if status == "accepted" else None, reviewed_by if status == "accepted" else None))
            return cur.rowcount

    def get_iteration_shifts(self, limit=200, work_item_id=None, review_status=None, sprint_to_sprint_only=False):
        """
        Retrieves recorded iteration shift events ordered by most recent first.
        """
        query = "SELECT * FROM iteration_shifts WHERE 1=1"
        params = []
        if work_item_id:
            query += " AND work_item_id = ?"
            params.append(int(str(work_item_id).lstrip("#")))
        if review_status and review_status.lower() in ("pending", "accepted"):
            query += " AND review_status = ?"
            params.append(review_status.lower())
        query += " ORDER BY id DESC LIMIT ?"
        params.append(int(limit))

        with self._connection() as conn:
            rows = conn.execute(query, params).fetchall()
            results = [dict(r) for r in rows]
            if sprint_to_sprint_only:
                results = [r for r in results if _is_scheduled_sprint(r.get("old_iteration"))]
            return results

    def get_sprint_to_sprint_shifts(self, limit=500, review_status=None):
        """
        Retrieves iteration shifts where the item was already scheduled to a sprint prior to moving.
        Filters out initial moves from Backlog to a sprint.
        """
        all_shifts = self.get_iteration_shifts(limit=limit, review_status=review_status)
        return [s for s in all_shifts if _is_scheduled_sprint(s.get("old_iteration"))]

    def get_shift_metrics(self):
        """
        Calculates aggregate iteration shift & postponement statistics, including review policy breakdown.
        """
        with self._connection() as conn:
            shifts = conn.execute("SELECT * FROM iteration_shifts ORDER BY id DESC").fetchall()
            shift_dicts = [dict(s) for s in shifts]
            total_shifts = len(shift_dicts)
            postponed = sum(1 for s in shift_dicts if (s.get("delta_weeks") or 0) > 0)
            accelerated = sum(1 for s in shift_dicts if (s.get("delta_weeks") or 0) < 0)
            net_delta = sum((s.get("delta_weeks") or 0) for s in shift_dicts)
            affected_wis = len(set(s["work_item_id"] for s in shift_dicts))

            pending_count = sum(1 for s in shift_dicts if (s.get("review_status") or "pending") == "pending")
            accepted_count = sum(1 for s in shift_dicts if (s.get("review_status") or "pending") == "accepted")

            # Sprint-to-sprint stats
            sprint_to_sprint_shifts = [s for s in shift_dicts if _is_scheduled_sprint(s.get("old_iteration"))]
            sprint_to_sprint_count = len(sprint_to_sprint_shifts)
            sprint_to_sprint_delayed_weeks = sum((s.get("delta_weeks") or 0) for s in sprint_to_sprint_shifts)

            top_rows = conn.execute("""
                SELECT work_item_id as id, work_item_id, title, type, assigned_to, 
                       old_sprint, new_sprint, SUM(delta_weeks) as total_delayed_weeks,
                       COUNT(*) as shift_count, MAX(recorded_at) as last_shift_at,
                       SUM(CASE WHEN review_status = 'pending' OR review_status IS NULL THEN 1 ELSE 0 END) as pending_count,
                       SUM(CASE WHEN review_status = 'accepted' THEN 1 ELSE 0 END) as accepted_count
                FROM iteration_shifts
                WHERE delta_weeks > 0
                GROUP BY work_item_id
                ORDER BY total_delayed_weeks DESC, shift_count DESC
                LIMIT 15
            """).fetchall()

            top_list = []
            for r in top_rows:
                rd = dict(r)
                rd["review_status"] = "accepted" if (rd.get("pending_count") or 0) == 0 else "pending"
                rd["is_reviewed"] = (rd.get("pending_count") or 0) == 0
                top_list.append(rd)

            most_delayed = top_list[0] if top_list else None

            return {
                "total_shifts": total_shifts,
                "total_shifted_items": affected_wis,
                "affected_work_items": affected_wis,
                "total_postponed": postponed,
                "total_accelerated": accelerated,
                "net_delay_weeks": net_delta,
                "net_delayed_weeks": net_delta,
                "pending_shifts_count": pending_count,
                "accepted_shifts_count": accepted_count,
                "sprint_to_sprint_count": sprint_to_sprint_count,
                "sprint_to_sprint_delayed_weeks": sprint_to_sprint_delayed_weeks,
                "top_delayed_items": top_list,
                "top_postponed": top_list,
                "most_delayed_item": most_delayed
            }

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

    def update_work_item_deadline(self, wi_id, deadline_str, field_name="Microsoft.VSTS.Scheduling.TargetDate"):
        """
        Updates the target deadline field inside raw_json of a cached work item in SQLite.

        Args:
            wi_id (int/str): Work item ID.
            deadline_str (str): Target deadline (YYYY-MM-DD or ISO string, or empty string to clear).
            field_name (str): The field reference name to update.

        Returns:
            bool: True if record was found and updated, False otherwise.
        """
        try:
            wi_int = int(str(wi_id).lstrip("#"))
        except (ValueError, TypeError):
            return False

        with self._connection() as conn:
            row = conn.execute("SELECT raw_json FROM work_items WHERE id = ?", (wi_int,)).fetchone()
            if not row:
                return False

            raw_s = row["raw_json"]
            raw_obj = {}
            if raw_s:
                try:
                    raw_obj = json.loads(raw_s)
                except Exception:
                    raw_obj = {}

            if not isinstance(raw_obj, dict):
                raw_obj = {}
            if "fields" not in raw_obj or not isinstance(raw_obj["fields"], dict):
                raw_obj["fields"] = {}

            target_field = field_name or "Microsoft.VSTS.Scheduling.TargetDate"
            if deadline_str:
                raw_obj["fields"][target_field] = deadline_str
            else:
                if target_field:
                    raw_obj["fields"].pop(target_field, None)
                for k in list(raw_obj["fields"].keys()):
                    if (
                        k in (
                            "Microsoft.VSTS.Scheduling.TargetDate",
                            "Microsoft.VSTS.Scheduling.DueDate",
                            "Microsoft.VSTS.Scheduling.FinishDate",
                            "Custom.Deadline",
                            "Custom.TargetDate",
                            "Custom.Milestone",
                            "Custom.MilestoneDeadline"
                        )
                        or k.lower().endswith("deadline")
                        or k.lower().endswith("targetdate")
                    ):
                        raw_obj["fields"].pop(k, None)

            updated_raw = json.dumps(raw_obj, cls=DateTimeEncoder, ensure_ascii=False)
            conn.execute("UPDATE work_items SET raw_json = ? WHERE id = ?", (updated_raw, wi_int))
            return True

    def get_all_work_item_ids(self, include_deleted=True):
        """
        Retrieves all work item IDs stored in the cache database.
        """
        filter_deleted = "" if include_deleted else " WHERE (deleted = 0 OR deleted IS NULL)"
        with self._connection() as conn:
            rows = conn.execute(f"SELECT id FROM work_items{filter_deleted} ORDER BY id").fetchall()
            return [r["id"] for r in rows]

    def get_max_work_item_changed_date(self):
        """
        Retrieves the latest System.ChangedDate timestamp among all non-deleted cached work items.
        Used for high-speed incremental synchronization.
        """
        with self._connection() as conn:
            row = conn.execute(
                "SELECT MAX(changed_date) as max_date FROM work_items WHERE (deleted = 0 OR deleted IS NULL) AND changed_date IS NOT NULL AND changed_date != ''"
            ).fetchone()
            if row and row["max_date"]:
                return str(row["max_date"]).strip()
            return None

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
        from utils import normalize_pr_status
        repo_id = pr.get("repository", {}).get("id")
        if not repo_id:
            return
        created_by = pr.get("createdBy", {}).get("displayName", "")
        closed_by = pr.get("closedBy", {}).get("displayName", "") if pr.get("closedBy") else ""
        closed_date = pr.get("closedDateStr", "")
        creation_date = pr.get("creationDateStr", "")
        norm_status = normalize_pr_status(pr.get("status"))
        status_str = pr.get("statusStr", "")
        if not status_str:
            if norm_status == "completed":
                status_str = f"DON {closed_date}"
            elif norm_status == "abandoned":
                status_str = f"ABANDONED {closed_date}"
            else:
                status_str = f"OPN {creation_date}"
        raw_json = json.dumps(pr, cls=DateTimeEncoder, ensure_ascii=False)

        with self._connection() as conn:
            conn.execute("""
            INSERT OR REPLACE INTO pull_requests (id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, status_str, raw_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (pr["pullRequestId"], repo_id, pr.get("title"), norm_status, pr.get("targetRefName"), pr.get("sourceRefName"), created_by, closed_by, closed_date, status_str, raw_json))

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

    def save_cached_iteration(self, project, name, path=None, start_date=None, end_date=None, year=None, week=None, is_synced=0):
        """
        Saves or updates a prepared weekly iteration in SQLite cache.
        """
        proj = (project or "").strip()
        iter_name = str(name).strip()
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with self._connection() as conn:
            conn.execute("""
                INSERT INTO cached_iterations (project, iteration_name, iteration_path, start_date, end_date, year, week, is_server_synced, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(project, iteration_name) DO UPDATE SET
                    iteration_path = excluded.iteration_path,
                    start_date = excluded.start_date,
                    end_date = excluded.end_date,
                    year = excluded.year,
                    week = excluded.week,
                    is_server_synced = excluded.is_server_synced
            """, (proj, iter_name, path or iter_name, start_date, end_date, year, week, int(is_synced), now_str))

    def get_cached_iterations(self, project=None):
        """
        Retrieves all cached prepared iterations, optionally filtered by project, sorted chronologically.
        """
        query = "SELECT * FROM cached_iterations"
        params = []
        if project:
            query += " WHERE project = ? OR project = '' OR project IS NULL"
            params.append(project.strip())
        query += " ORDER BY year ASC, week ASC, id ASC"

        with self._connection() as conn:
            rows = conn.execute(query, params).fetchall()
            return [dict(r) for r in rows]

    def delete_cached_iteration(self, iteration_name, project=None):
        """
        Deletes a specific cached iteration by name.
        """
        query = "DELETE FROM cached_iterations WHERE iteration_name = ?"
        params = [iteration_name.strip()]
        if project:
            query += " AND (project = ? OR project = '' OR project IS NULL)"
            params.append(project.strip())
        with self._connection() as conn:
            conn.execute(query, params)

    def clear_cached_iterations(self, project=None):
        """
        Clears cached iterations for a project or all cached iterations if project is None.
        """
        query = "DELETE FROM cached_iterations"
        params = []
        if project:
            query += " WHERE project = ? OR project = '' OR project IS NULL"
            params.append(project.strip())
        with self._connection() as conn:
            conn.execute(query, params)




