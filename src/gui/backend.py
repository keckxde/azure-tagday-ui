# -*- coding: UTF-8 -*-
"""
QObject backend bridge connecting Python DevOps and SQLite caching services to Qt Quick / QML.
"""
import os
import sys
import json
import logging
import re
from datetime import datetime
from PySide6.QtCore import QObject, Signal, Slot, Property

# Ensure scripts/py is in sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import utils
import devops_helper
from azure import AzureDevOpsCache
from gui.workers import TaskWorker

logger = logging.getLogger("gui.backend")


class QtLogEmitter(QObject):
    """Bridge for cross-thread signal emission of logging records to Qt main thread."""
    recordReady = Signal(str, str, str, str)  # timestamp, level, logger_name, message


class QtLogHandler(logging.Handler):
    """
    Custom logging handler that intercepts all Python logger messages
    (INFO, WARNING, ERROR, CRITICAL) and forwards them safely to the Qt event loop.
    """
    def __init__(self, emitter):
        super().__init__()
        self.emitter = emitter
        self._in_emit = False

    def emit(self, record):
        if self._in_emit:
            return
        if record.name.startswith("gui.qt_log"):
            return
        self._in_emit = True
        try:
            msg = self.format(record)
            ts = datetime.now().strftime("%H:%M:%S")
            lvl = record.levelname.upper()
            if lvl in ("WARN", "WARNING"):
                lvl = "WARNING"
            elif lvl in ("ERROR", "CRITICAL"):
                lvl = "ERROR"
            else:
                lvl = "INFO"
            self.emitter.recordReady.emit(ts, lvl, record.name, msg)
        except Exception:
            pass
        finally:
            self._in_emit = False


class ConsoleOutputTee:
    """
    Captures console stdout prints and feeds them to the GUI Sync Log as INFO records,
    while preserving standard console printing in the terminal.
    """
    def __init__(self, original_stream, callback):
        self.original_stream = original_stream
        self.callback = callback
        self._buffer = ""

    def write(self, text):
        if self.original_stream:
            try:
                self.original_stream.write(text)
            except Exception:
                pass
        self._buffer += text
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            line = line.strip("\r\n")
            if line:
                try:
                    self.callback(line)
                except Exception:
                    pass

    def flush(self):
        if self.original_stream:
            try:
                self.original_stream.flush()
            except Exception:
                pass
        if self._buffer.strip():
            try:
                self.callback(self._buffer.strip())
            except Exception:
                pass
            self._buffer = ""


def _get_user_settings_path():
    if getattr(sys, "frozen", False):
        exe_dir = os.path.dirname(sys.executable)
        return os.path.join(exe_dir, "config", "user_settings.yaml")
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "user_settings.yaml"
    )


USER_SETTINGS_PATH = _get_user_settings_path()


def _load_user_settings():
    """Loads user configuration from YAML (with fallback to legacy JSON or .yml)."""
    candidates = [
        USER_SETTINGS_PATH,
        os.path.join(os.path.dirname(USER_SETTINGS_PATH), "user_settings.yml"),
        os.path.join(os.path.dirname(USER_SETTINGS_PATH), "user_settings.json"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "user_settings.yml"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "user_settings.json"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "config", "user_settings.yaml"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "config", "user_settings.json"),
    ]
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        candidates.append(os.path.join(sys._MEIPASS, "config", "user_settings.yaml"))
        candidates.append(os.path.join(sys._MEIPASS, "config", "user_settings.json"))
    for candidate in candidates:
        if os.path.exists(candidate):
            try:
                if candidate.endswith(".json"):
                    with open(candidate, "r", encoding="utf-8") as f:
                        data = json.load(f)
                else:
                    import yaml
                    with open(candidate, "r", encoding="utf-8") as f:
                        data = yaml.safe_load(f)
                if isinstance(data, dict):
                    return data
            except Exception as e:
                logger.warning(f"Failed to read user settings from {candidate}: {e}")
    return {}


def _save_user_settings(settings):
    """Saves user configuration dictionary to top-level config/user_settings.yaml."""
    try:
        import yaml
        os.makedirs(os.path.dirname(USER_SETTINGS_PATH), exist_ok=True)
        with open(USER_SETTINGS_PATH, "w", encoding="utf-8") as f:
            yaml.safe_dump(settings, f, default_flow_style=False, sort_keys=False)
    except Exception as e:
        logger.error(f"Failed to save user settings to {USER_SETTINGS_PATH}: {e}")


class DevOpsBackend(QObject):
    """
    Main backend interface for QML.
    """

    # Signals
    statsChanged = Signal()
    settingsChanged = Signal()
    repositoriesChanged = Signal()
    workItemsChanged = Signal()
    pullRequestsChanged = Signal()
    tagDayDataChanged = Signal()
    storageDataChanged = Signal()
    logRecord = Signal(str, str, str, str)  # timestamp, level, logger_name, message
    logMessage = Signal(str)                # legacy formatted string signal
    syncLogsChanged = Signal()
    busyChanged = Signal()
    statusMessageChanged = Signal()
    progressChanged = Signal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._is_busy = False
        self._status_message = "Ready"
        self._progress = 0
        self._worker = None

        # Sync Logs storage & logger bridge
        self._sync_logs = []
        self._info_count = 0
        self._warning_count = 0
        self._error_count = 0

        self._log_emitter = QtLogEmitter()
        self._log_emitter.recordReady.connect(self._on_incoming_log_record)

        self._qt_log_handler = QtLogHandler(self._log_emitter)
        self._qt_log_handler.setFormatter(logging.Formatter("%(message)s"))
        root_logger = logging.getLogger()
        if root_logger.level == logging.NOTSET or root_logger.level > logging.INFO:
            root_logger.setLevel(logging.INFO)
        root_logger.addHandler(self._qt_log_handler)

        # Intercept stdout to also capture prints into sync log
        self._stdout_tee = ConsoleOutputTee(sys.stdout, self._on_stdout_line)
        sys.stdout = self._stdout_tee

        # Stats dict
        self._stats = {
            "repos_count": 0,
            "pending_repos_count": 0,
            "latest_stable_tag": "-",
            "latest_stable_repo": "",
            "latest_stable_date": "",
            "latest_unstable_tag": "-",
            "latest_unstable_repo": "",
            "latest_unstable_date": "",
            "work_items_count": 0,
            "active_work_items_count": 0,
            "deleted_work_items_count": 0,
            "prs_count": 0,
            "prs_open_count": 0,
            "prs_completed_count": 0,
            "prs_abandoned_count": 0,
            "last_synced": "Never",
            "project_name": devops_helper.AZURE_PROJECT_ID or "N/A",
            "db_path": "",
        }

        self._repositories = []
        self._work_items = []
        self._pull_requests = []
        self._pr_repositories = []
        self._tagday_data = {}
        self._storage_data = {}

        # Initialize cache handler only — heavy data load happens in startup_load_async()
        self._init_cache()

    def _init_cache(self):
        try:
            cfg = _load_user_settings()
            custom_db = cfg.get("db_path")
            if custom_db and os.path.exists(custom_db):
                self._db_path = os.path.abspath(custom_db)
                self._cache_db = AzureDevOpsCache(self._db_path)
                self._stats["db_path"] = self._db_path
                if cfg.get("project_id"):
                    devops_helper.AZURE_PROJECT_ID = cfg["project_id"]
                    self._stats["project_name"] = cfg["project_id"]
                if cfg.get("tfs_url"):
                    devops_helper.AZURE_BASE_URL = cfg["tfs_url"]
                if cfg.get("collection"):
                    devops_helper.AZURE_COLLECTION = cfg["collection"]
                if cfg.get("pat"):
                    devops_helper.AZURE_PERSONAL_ACCESS_TOKEN = cfg["pat"]
            else:
                db_path, cache_db = devops_helper._getDBCacheHandler()
                self._db_path = db_path
                self._cache_db = cache_db
                self._stats["db_path"] = db_path

            # Also check if project name is stored in projects table
            if self._cache_db:
                try:
                    with self._cache_db._connection() as conn:
                        p_row = conn.execute("SELECT name FROM projects ORDER BY last_synced_at DESC LIMIT 1").fetchone()
                        if p_row and p_row["name"]:
                            devops_helper.AZURE_PROJECT_ID = p_row["name"]
                            self._stats["project_name"] = p_row["name"]
                except Exception:
                    pass

        except Exception as e:
            logger.error(f"Error initializing SQLite cache: {e}")
            self._db_path = ""
            self._cache_db = None

    @Property(str, notify=settingsChanged)
    def dbPath(self):
        return self._db_path or ""

    @Property(str, notify=settingsChanged)
    def projectName(self):
        return self._stats.get("project_name") or devops_helper.AZURE_PROJECT_ID or "N/A"

    @Property(str, notify=statsChanged)
    def lastSynced(self):
        return self._stats.get("last_synced", "Never")

    @Property(str, notify=settingsChanged)
    def tfsUrl(self):
        return devops_helper.AZURE_BASE_URL or ""

    @Property(str, notify=settingsChanged)
    def tfsCollection(self):
        return devops_helper.AZURE_COLLECTION or "DefaultCollection"

    @Property(str, notify=settingsChanged)
    def tfsPat(self):
        return devops_helper.AZURE_PERSONAL_ACCESS_TOKEN or ""

    @Property(list, notify=settingsChanged)
    def availableDatabases(self):
        return self.get_available_databases()

    @Property(list, notify=settingsChanged)
    def recentDatabases(self):
        cfg = _load_user_settings()
        return cfg.get("recent_databases", [])

    @Property(list, notify=settingsChanged)
    def recentProjects(self):
        cfg = _load_user_settings()
        return cfg.get("recent_projects", [])

    # Properties
    @Property(bool, notify=busyChanged)
    def isBusy(self):
        return self._is_busy

    @Property(str, notify=statusMessageChanged)
    def statusMessage(self):
        return self._status_message

    @Property(int, notify=progressChanged)
    def progress(self):
        return self._progress

    @Property(dict, notify=statsChanged)
    def stats(self):
        return self._stats

    @Property(list, notify=repositoriesChanged)
    def repositories(self):
        return self._repositories

    @Property(list, notify=workItemsChanged)
    def workItems(self):
        return self._work_items

    @Property(list, notify=workItemsChanged)
    def workItemTypes(self):
        """Returns the sorted unique list of work item types currently in cache."""
        seen = set()
        for wi in self._work_items:
            t = wi.get("type") or ""
            if t:
                seen.add(t)
        return sorted(seen)

    @Property(list, notify=pullRequestsChanged)
    def pullRequests(self):
        return self._pull_requests

    @Property(list, notify=pullRequestsChanged)
    def prRepositories(self):
        return self._pr_repositories

    @Property(dict, notify=tagDayDataChanged)
    def tagDayData(self):
        return self._tagday_data

    @Property(dict, notify=storageDataChanged)
    def storageData(self):
        return self._storage_data

    @Property(str, notify=statsChanged)
    def revisionFilePath(self):
        return os.path.join(devops_helper.BASE_FOLDER, devops_helper.REVISION_FILE_MD)

    @Property(str, notify=statsChanged)
    def tagdayFilePath(self):
        return os.path.join(devops_helper.BASE_FOLDER, devops_helper.TAGDAY_FILE_MD)

    @Property(list, notify=syncLogsChanged)
    def syncLogs(self):
        return self._sync_logs

    @Property(dict, notify=settingsChanged)
    def categoryColors(self):
        try:
            cfg, _ = utils.load_repo_categories()
            return cfg.get("category_colors", {})
        except Exception:
            return {}

    @Slot(str, result=str)
    def get_category_color(self, category):
        try:
            return utils.get_category_color(category)
        except Exception:
            return "#6e7681"

    @Property(dict, notify=syncLogsChanged)
    def logCounts(self):
        return {
            "all": len(self._sync_logs),
            "info": self._info_count,
            "warning": self._warning_count,
            "error": self._error_count
        }

    @Slot(str, str, str, str)
    def _on_incoming_log_record(self, timestamp, level, logger_name, message):
        norm_level = (level or "INFO").upper()
        if norm_level in ("WARN", "WARNING"):
            norm_level = "WARNING"
            self._warning_count += 1
        elif norm_level in ("ERROR", "CRITICAL"):
            norm_level = "ERROR"
            self._error_count += 1
        else:
            norm_level = "INFO"
            self._info_count += 1

        formatted = f"[{timestamp}] [{norm_level}] [{logger_name}] {message}"
        entry = {
            "id": len(self._sync_logs) + 1,
            "timestamp": timestamp,
            "level": norm_level,
            "logger": logger_name,
            "message": message,
            "text": formatted
        }

        self._sync_logs.append(entry)
        if len(self._sync_logs) > 2000:
            removed = self._sync_logs.pop(0)
            lvl = removed.get("level")
            if lvl == "ERROR" and self._error_count > 0:
                self._error_count -= 1
            elif lvl == "WARNING" and self._warning_count > 0:
                self._warning_count -= 1
            elif lvl == "INFO" and self._info_count > 0:
                self._info_count -= 1

        self.logRecord.emit(timestamp, norm_level, logger_name, message)
        self.logMessage.emit(formatted)
        self.syncLogsChanged.emit()

    def _on_stdout_line(self, line):
        ts = datetime.now().strftime("%H:%M:%S")
        self._log_emitter.recordReady.emit(ts, "INFO", "console", line)

    @Slot()
    def clear_logs(self):
        """Clears all accumulated sync logs and resets severity counters."""
        self._sync_logs.clear()
        self._info_count = 0
        self._warning_count = 0
        self._error_count = 0
        self.syncLogsChanged.emit()

    @Slot(str)
    def copy_to_clipboard(self, text):
        """Copies given text to the system clipboard."""
        try:
            from PySide6.QtGui import QGuiApplication
            clipboard = QGuiApplication.clipboard()
            if clipboard:
                clipboard.setText(text)
        except Exception as e:
            logger.error(f"Failed to copy to clipboard: {e}")

    @Slot(result=str)
    def get_all_logs_text(self):
        """Returns all logs as a newline-separated string."""
        return "\n".join(e.get("text", "") for e in self._sync_logs)

    def _set_busy(self, busy: bool, message: str = ""):
        self._is_busy = busy
        if message:
            self._status_message = message
            self.statusMessageChanged.emit()
        self.busyChanged.emit()

    @Slot()
    def startup_load_async(self):
        """Deferred startup: loads all local cache data in a background thread after the GUI is shown."""
        logger.info("Starting initial data load from local cache...")

        def _work(worker):
            worker.log_message.emit("Loading data from local database...")
            # refresh_all_data() is called by _on_worker_finished after this completes
            worker.log_message.emit("Loading report metrics...")
            self.load_interactive_reports()

        self._run_worker(_work, "Loading local cache...")

    @Slot()
    def refresh_all_data(self):
        """Loads all data from local SQLite database."""
        if not self._cache_db:
            return

        try:
            # 1. Tag Day Analysis & Repositories
            import generate_tagday_report
            td_raw = generate_tagday_report.load_tagday_data(self._cache_db, project_id=devops_helper.AZURE_PROJECT_ID)
            self._populate_tagday_data(td_raw)
            repos_changed_map = td_raw.get("repos_with_any_changes", {})

            # Query tag markers (stable / unstable / latest)
            with self._cache_db._connection() as conn:
                tag_rows = conn.execute("""
                    SELECT r.name AS repo_name, t.name, t.commit_date, t.is_stable, t.is_unstable
                    FROM tags t
                    JOIN repositories r ON t.repo_id = r.id
                    WHERE t.name LIKE 'v%'
                    ORDER BY t.commit_date DESC, t.name DESC
                """).fetchall()

            stable_tags_map = {}
            unstable_tags_map = {}
            latest_tags_map = {}
            global_latest_stable = None
            global_latest_unstable = None

            for t in tag_rows:
                rname = t["repo_name"]
                tname = t["name"]
                tdate = (t["commit_date"] or "").split(" ")[0].split("T")[0]

                if rname not in latest_tags_map:
                    latest_tags_map[rname] = tname
                if t["is_stable"]:
                    if not global_latest_stable:
                        global_latest_stable = {"tag": tname, "repo": rname, "date": tdate}
                    if rname not in stable_tags_map:
                        stable_tags_map[rname] = tname
                if t["is_unstable"]:
                    if not global_latest_unstable:
                        global_latest_unstable = {"tag": tname, "repo": rname, "date": tdate}
                    if rname not in unstable_tags_map:
                        unstable_tags_map[rname] = tname

            repos_dict = self._cache_db.get_all_cached_repositories(devops_helper.AZURE_PROJECT_ID)
            devops_helper.addCategoriesToRepos(repos_dict, auto_save_missing=True)

            repo_list = []
            for r_id, r in repos_dict.items():
                info = r.get("info", {})
                rname = info.get("name", str(r_id))

                # Check pending changes from Tag Day dataset
                td_repo = repos_changed_map.get(rname)
                prs_after_tag_count = len(td_repo.get("prs_after_tag", [])) if td_repo else 0
                unmerged_branches_count = len(td_repo.get("unmerged_branches", [])) if td_repo else 0
                active_prs_count = len(td_repo.get("active_prs", [])) if td_repo else 0
                pending_count = prs_after_tag_count + unmerged_branches_count + active_prs_count
                has_pending = pending_count > 0

                parts = []
                if prs_after_tag_count > 0:
                    parts.append(f"{prs_after_tag_count} untagged PR{'s' if prs_after_tag_count > 1 else ''}")
                if unmerged_branches_count > 0:
                    parts.append(f"{unmerged_branches_count} unmerged branch{'es' if unmerged_branches_count > 1 else ''}")
                if active_prs_count > 0:
                    parts.append(f"{active_prs_count} active PR{'s' if active_prs_count > 1 else ''}")

                status_text = ", ".join(parts) if parts else "Up to date"

                repo_list.append({
                    "id": str(r_id),
                    "name": rname,
                    "category": r.get("category", "OTHERS"),
                    "default_branch": info.get("defaultBranch", "").replace("refs/heads/", ""),
                    "web_url": info.get("webUrl", ""),
                    "latest_tag": latest_tags_map.get(rname, "-"),
                    "stable_tag": stable_tags_map.get(rname, "-"),
                    "unstable_tag": unstable_tags_map.get(rname, "-"),
                    "branches_count": len(r.get("branches", [])),
                    "dev_prs_count": len(r.get("devPRs", [])),
                    "has_pending_changes": has_pending,
                    "pending_changes_count": pending_count,
                    "prs_after_tag_count": prs_after_tag_count,
                    "unmerged_branches_count": unmerged_branches_count,
                    "active_prs_count": active_prs_count,
                    "pending_status_text": status_text,
                })
            self._repositories = sorted(repo_list, key=lambda x: x["name"].lower())
            self.repositoriesChanged.emit()

            # 2. Work Items
            # Build WI → PR cross-reference map from PR status_str and title #NNNN mentions
            wi_to_prs = {}   # wi_id (int) -> list of {pr_id, repo_name, title}
            wi_to_repos = {} # wi_id (int) -> set of repo names
            try:
                all_prs_raw = self._cache_db.get_all_prs()
                for pr in all_prs_raw:
                    pr_id = pr.get("pr_id")
                    repo_name = pr.get("repo_name", "")
                    pr_title = pr.get("title", "") or ""
                    pr_status_str = pr.get("status_str", "") or ""
                    # Find all #NNNNN task references in title + status_str
                    combined_text = f"{pr_title} {pr_status_str}"
                    for m in re.finditer(r"#(\d{4,})", combined_text):
                        wi_id_ref = int(m.group(1))
                        if wi_id_ref not in wi_to_prs:
                            wi_to_prs[wi_id_ref] = []
                        wi_to_prs[wi_id_ref].append({
                            "pr_id": pr_id,
                            "repo_name": repo_name,
                            "title": pr_title[:60],
                        })
                        if wi_id_ref not in wi_to_repos:
                            wi_to_repos[wi_id_ref] = set()
                        wi_to_repos[wi_id_ref].add(repo_name)
            except Exception as e:
                logger.warning(f"Could not build WI→PR cross-reference map: {e}")

            # Build TFS web base URL for work item links
            tfs_base = (devops_helper.AZURE_BASE_URL or "").rstrip("/")
            tfs_col = (devops_helper.AZURE_COLLECTION or "").strip("/")
            tfs_proj = devops_helper.AZURE_PROJECT_ID or ""
            # Web URL format: {base}/{collection}/{project}/_workitems/edit/{id}
            tfs_wi_url_base = f"{tfs_base}/{tfs_col}/{tfs_proj}/_workitems/edit/" if (tfs_base and tfs_col and tfs_proj) else ""

            raw_wis = self._cache_db.get_all_work_items(include_deleted=True)
            wi_list = []
            deleted_count = 0
            for wi in raw_wis:
                is_del = bool(wi.get("deleted"))
                if is_del:
                    deleted_count += 1
                wi_id = wi.get("id")
                linked_prs = wi_to_prs.get(wi_id, [])
                linked_repos = sorted(wi_to_repos.get(wi_id, set()))
                # Prefer htmlLink from raw_json, else construct from TFS config
                html_link = wi.get("htmlLink", "") or ""
                if not html_link and tfs_wi_url_base and wi_id:
                    html_link = f"{tfs_wi_url_base}{wi_id}"
                wi_list.append({
                    "id": wi_id,
                    "title": wi.get("title") or f"Work Item #{wi_id}",
                    "type": wi.get("type") or wi.get("WorkItemType") or "Task",
                    "state": "Deleted" if is_del else (wi.get("state") or "Active"),
                    "assigned_to": wi.get("assigned_to") or "Unassigned",
                    "changed_date": wi.get("changed_date") or "",
                    "deleted": is_del,
                    "tfs_url": html_link,
                    "linked_pr_count": len(linked_prs),
                    "linked_prs": linked_prs[:10],  # cap at 10 to stay QML-friendly
                    "linked_repos": linked_repos[:8],
                    "linked_repo_count": len(linked_repos),
                })
            self._work_items = sorted(wi_list, key=lambda x: x["id"], reverse=True)
            self.workItemsChanged.emit()


            # 3. Pull Requests
            # Map PR tag information from Tag Day dataset
            pr_tag_info_map = {}
            for rname_td, r_data in td_raw.get("all_repositories", {}).items():
                for p_td in r_data.get("all_prs", []):
                    pr_tag_info_map[p_td["pr_id"]] = {
                        "is_tagged": p_td.get("is_tagged", False),
                        "tag_name": p_td.get("tag_name", ""),
                        "tag_type": p_td.get("tag_type", "")
                    }

            raw_prs = self._cache_db.get_all_prs()
            pr_list = []
            repos_with_prs = set()
            base_url = (devops_helper.AZURE_BASE_URL or "").rstrip("/")
            collection = devops_helper.AZURE_COLLECTION
            project_id = devops_helper.AZURE_PROJECT_ID

            for pr in raw_prs:
                rname = pr.get("repo_name") or "Unknown"
                repos_with_prs.add(rname)
                pr_id = pr.get("pr_id")
                raw_str = pr.get("raw_json")
                raw_dict = {}
                if raw_str and isinstance(raw_str, str):
                    try:
                        raw_dict = json.loads(raw_str)
                    except Exception:
                        pass

                closed_date = pr.get("closed_date") or ""
                creation_date = raw_dict.get("creationDate") or ""
                created_date_clean = creation_date.replace("T", " ").split(".")[0].replace("Z", "") if creation_date else ""
                
                # Normalize sort timestamp (YYYY-MM-DD HH:MM:SS)
                sort_time = closed_date if closed_date else created_date_clean

                source_branch = (pr.get("source_branch") or raw_dict.get("sourceRefName") or "").replace("refs/heads/", "")
                target_branch = (pr.get("target_branch") or raw_dict.get("targetRefName") or "").replace("refs/heads/", "")

                created_by = pr.get("created_by") or ""
                if not created_by and isinstance(raw_dict.get("createdBy"), dict):
                    created_by = raw_dict["createdBy"].get("displayName") or ""

                closed_by = pr.get("closed_by") or ""
                if not closed_by and isinstance(raw_dict.get("closedBy"), dict):
                    closed_by = raw_dict["closedBy"].get("displayName") or ""

                title = pr.get("title") or ""
                description = raw_dict.get("description") or ""
                status = (pr.get("status") or raw_dict.get("status") or "unknown").lower()

                web_url = f"{base_url}/{collection}/{project_id}/_git/{rname}/pullrequest/{pr_id}" if base_url else ""
                tasks = self._extract_pr_tasks(pr)

                # Tag association information
                tag_meta = pr_tag_info_map.get(pr_id)
                if tag_meta:
                    is_tagged = tag_meta.get("is_tagged", False)
                    tag_name = tag_meta.get("tag_name", "")
                    tag_type = tag_meta.get("tag_type", "")
                else:
                    direct_tag = pr.get("direct_tag_name")
                    is_tagged = bool(direct_tag)
                    tag_name = direct_tag or ""
                    tag_type = "direct" if direct_tag else ("untagged" if status == "completed" else status)

                pr_list.append({
                    "id": pr_id,
                    "repo_name": rname,
                    "title": title,
                    "description": description,
                    "status": status,
                    "source_branch": source_branch,
                    "target_branch": target_branch,
                    "created_by": created_by,
                    "closed_by": closed_by,
                    "closed_date": closed_date,
                    "created_date": created_date_clean,
                    "timestamp": sort_time,
                    "display_date": sort_time or "N/A",
                    "web_url": web_url,
                    "tasks": tasks,
                    "is_tagged": is_tagged,
                    "tag_name": tag_name,
                    "tag_type": tag_type,
                })

            # Sort by timestamp descending (newest first), with PR ID descending as secondary
            self._pull_requests = sorted(pr_list, key=lambda x: (x.get("timestamp") or "", x.get("id") or 0), reverse=True)
            self._pr_repositories = sorted(list(repos_with_prs), key=lambda x: x.lower())
            self.pullRequestsChanged.emit()

            # 4. Stats
            last_sync_dt = self._cache_db.get_project_last_synced(devops_helper.AZURE_PROJECT_ID)
            pending_repos_count = sum(1 for r in self._repositories if r.get("has_pending_changes"))
            prs_open_count = sum(1 for p in self._pull_requests if p.get("status") == "active")
            prs_completed_count = sum(1 for p in self._pull_requests if p.get("status") == "completed")
            prs_abandoned_count = sum(1 for p in self._pull_requests if p.get("status") == "abandoned")

            self._stats = {
                "repos_count": len(self._repositories),
                "pending_repos_count": pending_repos_count,
                "latest_stable_tag": global_latest_stable["tag"] if global_latest_stable else "-",
                "latest_stable_repo": global_latest_stable["repo"] if global_latest_stable else "",
                "latest_stable_date": global_latest_stable["date"] if global_latest_stable else "",
                "latest_unstable_tag": global_latest_unstable["tag"] if global_latest_unstable else "-",
                "latest_unstable_repo": global_latest_unstable["repo"] if global_latest_unstable else "",
                "latest_unstable_date": global_latest_unstable["date"] if global_latest_unstable else "",
                "work_items_count": len(self._work_items),
                "active_work_items_count": len(self._work_items) - deleted_count,
                "deleted_work_items_count": deleted_count,
                "prs_count": len(self._pull_requests),
                "prs_open_count": prs_open_count,
                "prs_completed_count": prs_completed_count,
                "prs_abandoned_count": prs_abandoned_count,
                "last_synced": last_sync_dt.strftime("%Y-%m-%d %H:%M:%S") if last_sync_dt else "Never",
                "project_name": devops_helper.AZURE_PROJECT_ID or "N/A",
                "db_path": self._db_path,
            }
            self.statsChanged.emit()

        except Exception as e:
            logger.error(f"Error refreshing cache data: {e}", exc_info=True)
            self.logMessage.emit(f"Error loading database: {e}")

    # Async Operations
    @Slot()
    def sync_work_items_async(self):
        """Triggers direct TFS API WIQL sync for work items."""
        if self._is_busy:
            return

        def _work(worker):
            worker.log_message.emit("Connecting to TFS API...")
            azHandler = devops_helper._getHandler()
            if not azHandler:
                raise RuntimeError("Failed to create Azure/TFS client. Check .env variables.")

            worker.log_message.emit(f"Querying all work items for project '{devops_helper.AZURE_PROJECT_ID}' via WIQL...")
            summary = azHandler.sync_work_items(self._cache_db, project_id=devops_helper.AZURE_PROJECT_ID)
            worker.log_message.emit(
                f"Sync complete: {summary.get('synced', 0)} synced, "
                f"{summary.get('deleted', 0)} deleted, {summary.get('errors', 0)} errors"
            )
            return summary

        self._run_worker(_work, "Syncing work items...")

    @Slot()
    def sync_all_async(self):
        """Triggers full sync of repos, work items, and pull requests."""
        if self._is_busy:
            return

        def _work(worker):
            worker.log_message.emit("Starting full Azure DevOps sync...")
            devops_helper.sync(force_sync=True)
            return "Full synchronization finished"

        self._run_worker(_work, "Running full sync...")

    @Slot()
    def load_interactive_reports(self):
        """Loads and parses interactive report metrics and timelines directly from the SQLite database."""
        if not self._cache_db:
            return

        try:
            # 1. Tag Day Interactive Data
            import generate_tagday_report
            td_raw = generate_tagday_report.load_tagday_data(self._cache_db, project_id=devops_helper.AZURE_PROJECT_ID)
            self._populate_tagday_data(td_raw)

            # 2. Build Artifacts & Storage Interactive Data
            import generate_artifacts_report
            artifacts = generate_artifacts_report.load_artifacts_data(self._cache_db)
            if artifacts:
                metrics = generate_artifacts_report.calculate_metrics(artifacts)
                self._storage_data = {
                    "total_builds": metrics.get("total_builds", 0),
                    "total_artifacts": metrics.get("total_artifacts", 0),
                    "active_artifacts_count": metrics.get("active_artifacts_count", 0),
                    "deleted_artifacts_count": metrics.get("deleted_artifacts_count", 0),
                    "total_size_gb": f"{metrics.get('total_size_gb', 0.0):.2f}",
                    "active_size_gb": f"{metrics.get('active_size_gb', 0.0):.2f}",
                    "deleted_size_gb": f"{metrics.get('deleted_size_gb', 0.0):.2f}",
                    "artifacts_list": artifacts[:100], # Top 100 artifacts
                }
            else:
                self._storage_data = {
                    "total_builds": 0, "total_artifacts": 0,
                    "active_artifacts_count": 0, "deleted_artifacts_count": 0,
                    "total_size_gb": "0.00", "active_size_gb": "0.00", "deleted_size_gb": "0.00",
                    "artifacts_list": []
                }
            self.storageDataChanged.emit()

        except Exception as e:
            logger.error(f"Error loading interactive reports data: {e}", exc_info=True)
            self.logMessage.emit(f"Error loading report metrics: {e}")

    @Slot()
    def generate_tagday_report_async(self):
        """Generates the Tag Day release report in background."""
        if self._is_busy:
            return

        def _work(worker):
            worker.log_message.emit("Generating Tag Day release notes report...")
            success = devops_helper.generate_tagday_report(
                db_path=self._db_path,
                output_path=os.path.join(devops_helper.BASE_FOLDER, devops_helper.TAGDAY_FILE_MD),
                project_id=devops_helper.AZURE_PROJECT_ID
            )
            if not success:
                raise RuntimeError("Tag Day report generation returned failure")
            worker.log_message.emit("Tag Day report generated successfully")
            return "Tag Day report generated"

        self._run_worker(_work, "Generating Tag Day report...")

    @Slot()
    def generate_storage_report_async(self):
        """Generates the Build Artifact Storage report in background."""
        if self._is_busy:
            return

        def _work(worker):
            worker.log_message.emit("Analyzing build artifacts and storage usage...")
            success = devops_helper.generate_artifacts_report(
                db_path=self._db_path,
                md_path=os.path.join(devops_helper.BASE_FOLDER, devops_helper.BUILD_ARTIFACTS_MD),
                csv_path=os.path.join(devops_helper.BASE_FOLDER, devops_helper.BUILD_ARTIFACTS_CSV)
            )
            if not success:
                raise RuntimeError("Storage report generation returned failure")
            worker.log_message.emit("Storage report generated successfully")
            return "Storage report generated"

        self._run_worker(_work, "Generating Storage report...")

    @Slot()
    def generate_revision_report_async(self):
        """Generates the Release Notes / REVISION.md report in background."""
        if self._is_busy:
            return

        def _work(worker):
            worker.log_message.emit("Generating Release Notes (REVISION.md & REVISION.docx)...")
            revision_md_path = os.path.join(devops_helper.BASE_FOLDER, devops_helper.REVISION_FILE_MD)
            success = devops_helper.generate_revision_report(
                db_path=self._db_path,
                revision_md_path=revision_md_path
            )
            if success is False:
                raise RuntimeError("Revision report generation returned failure")
            worker.log_message.emit(f"Release Notes updated successfully: {revision_md_path}")
            return "Release Notes generated successfully"

        self._run_worker(_work, "Generating Release Notes...")

    @Slot()
    def open_revision_file(self):
        """Opens REVISION.md in default editor or viewer."""
        path = os.path.join(devops_helper.BASE_FOLDER, devops_helper.REVISION_FILE_MD)
        if os.path.exists(path):
            self.open_path_in_explorer(path)
        else:
            self.logMessage.emit(f"File does not exist: {path}")

    @Slot()
    def open_revision_docx(self):
        """Opens REVISION.docx in Microsoft Word or default viewer."""
        md_path = os.path.join(devops_helper.BASE_FOLDER, devops_helper.REVISION_FILE_MD)
        docx_path = os.path.splitext(md_path)[0] + ".docx"
        if os.path.exists(docx_path):
            self.open_path_in_explorer(docx_path)
        else:
            self.logMessage.emit(f"File does not exist: {docx_path}")

    @Slot()
    def open_tagday_file(self):
        """Opens TAGDAY.md in default editor."""
        path = os.path.join(devops_helper.BASE_FOLDER, devops_helper.TAGDAY_FILE_MD)
        if os.path.exists(path):
            self.open_path_in_explorer(path)
        else:
            self.logMessage.emit(f"File does not exist: {path}")

    @Slot()
    def open_storage_report_file(self):
        """Opens generated storage report markdown in default editor."""
        path = os.path.join(devops_helper.BASE_FOLDER, devops_helper.BUILD_ARTIFACTS_MD)
        if not os.path.exists(path):
            path = os.path.join(devops_helper.BASE_FOLDER, "doc", "04_Development", "test_report.md")
        if not os.path.exists(path):
            path = os.path.join(devops_helper.BASE_FOLDER, "test_report.md")
        if os.path.exists(path):
            self.open_path_in_explorer(path)
        else:
            self.logMessage.emit(f"File does not exist: {path}")

    def _run_worker(self, task_func, busy_msg):
        logger.info(f"Starting background task: {busy_msg}")
        self._set_busy(True, busy_msg)
        self._worker = TaskWorker(task_func)
        self._worker.log_message.connect(self._on_worker_log)
        self._worker.finished_task.connect(self._on_worker_finished)
        self._worker.start()

    def _on_worker_log(self, msg):
        logger.info(msg)

    def _on_worker_finished(self, success, result_msg):
        self._set_busy(False, "Ready")
        self.refresh_all_data()
        if success:
            logger.info(f"[COMPLETED] {result_msg}")
        else:
            logger.error(f"[FAILED] {result_msg}")
        self._worker = None

    @Slot()
    def open_db_folder(self):
        """Opens the directory containing the SQLite database cache in Windows File Explorer."""
        if self._db_path:
            folder = os.path.dirname(os.path.abspath(self._db_path))
            self.open_path_in_explorer(folder)

    @Slot()
    def reconnect_cache(self):
        """Re-initializes the cache handler and reloads all data."""
        self.logMessage.emit("Reconnecting database cache...")
        self._init_cache()
        self.refresh_all_data()
        self.logMessage.emit(f"Database cache connected: {self._db_path}")

    @Slot(result=list)
    def get_available_databases(self):
        """Scans workspace directory for SQLite cache databases."""
        search_dirs = [devops_helper.BASE_FOLDER, os.getcwd()]
        found = {}
        for sdir in search_dirs:
            if not sdir or not os.path.exists(sdir):
                continue
            try:
                for fname in os.listdir(sdir):
                    if fname.endswith(".db"):
                        full_path = os.path.abspath(os.path.join(sdir, fname))
                        if full_path not in found:
                            size_bytes = os.path.getsize(full_path)
                            mtime = os.path.getmtime(full_path)
                            mtime_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
                            proj_name = ""
                            try:
                                temp_cache = AzureDevOpsCache(full_path)
                                with temp_cache._connection() as conn:
                                    p_row = conn.execute("SELECT name FROM projects ORDER BY last_synced_at DESC LIMIT 1").fetchone()
                                    if p_row and p_row["name"]:
                                        proj_name = p_row["name"]
                            except Exception:
                                pass

                            if not proj_name:
                                bname = os.path.splitext(fname)[0]
                                if bname.startswith("tfs_cache_"):
                                    proj_name = bname.replace("tfs_cache_", "")
                                else:
                                    proj_name = "Custom Database"

                            is_active = (os.path.abspath(self._db_path) == full_path) if self._db_path else False
                            found[full_path] = {
                                "name": fname,
                                "path": full_path,
                                "size_mb": f"{size_bytes / (1024 * 1024):.2f} MB",
                                "modified": mtime_str,
                                "project": proj_name,
                                "is_active": is_active
                            }
            except Exception as e:
                logger.warning(f"Error scanning directory {sdir} for db files: {e}")
        return list(found.values())

    @Slot(result=str)
    def browse_database_file(self):
        """Opens native file dialog to select an existing SQLite database."""
        try:
            from PySide6.QtWidgets import QFileDialog
            initial_dir = devops_helper.BASE_FOLDER if devops_helper.BASE_FOLDER and os.path.exists(devops_helper.BASE_FOLDER) else os.getcwd()
            file_path, _ = QFileDialog.getOpenFileName(
                None, "Select SQLite Database", initial_dir, "SQLite Database Files (*.db);;All Files (*.*)"
            )
            return file_path or ""
        except Exception as e:
            logger.error(f"Error opening file dialog: {e}")
            return ""

    @Slot(str, result=str)
    def browse_new_db_path(self, suggested_name=""):
        """Opens native file dialog to choose path for a new database."""
        try:
            from PySide6.QtWidgets import QFileDialog
            initial_dir = devops_helper.BASE_FOLDER if devops_helper.BASE_FOLDER and os.path.exists(devops_helper.BASE_FOLDER) else os.getcwd()
            if not suggested_name:
                suggested_name = "tfs_cache_new.db"
            elif not suggested_name.endswith(".db"):
                suggested_name += ".db"
            default_path = os.path.join(initial_dir, suggested_name)
            file_path, _ = QFileDialog.getSaveFileName(
                None, "Choose New SQLite Database Path", default_path, "SQLite Database (*.db)"
            )
            return file_path or ""
        except Exception as e:
            logger.error(f"Error opening save file dialog: {e}")
            return ""

    @Slot(str, result=bool)
    def switch_database(self, new_db_path):
        """Switches active database to selected path and reloads data."""
        if not new_db_path:
            return False
        abs_path = os.path.abspath(new_db_path)
        if not os.path.exists(abs_path):
            logger.error(f"Database file does not exist: {abs_path}")
            return False

        try:
            self._db_path = abs_path
            self._cache_db = AzureDevOpsCache(abs_path)
            self._stats["db_path"] = abs_path

            # Detect project name from database
            with self._cache_db._connection() as conn:
                p_row = conn.execute("SELECT name FROM projects ORDER BY last_synced_at DESC LIMIT 1").fetchone()
                if p_row and p_row["name"]:
                    devops_helper.AZURE_PROJECT_ID = p_row["name"]
                    self._stats["project_name"] = p_row["name"]
                else:
                    base_name = os.path.splitext(os.path.basename(abs_path))[0]
                    if base_name.startswith("tfs_cache_"):
                        p_name = base_name.replace("tfs_cache_", "")
                        devops_helper.AZURE_PROJECT_ID = p_name
                        self._stats["project_name"] = p_name

            cfg = _load_user_settings()
            cfg["db_path"] = abs_path
            cfg["project_id"] = self._stats["project_name"]
            cfg["project_name"] = self._stats["project_name"]
            recent_dbs = cfg.get("recent_databases", [])
            if abs_path in recent_dbs:
                recent_dbs.remove(abs_path)
            recent_dbs.insert(0, abs_path)
            cfg["recent_databases"] = recent_dbs[:10]
            _save_user_settings(cfg)

            self.refresh_all_data()
            self.load_interactive_reports()
            self.settingsChanged.emit()
            self.statsChanged.emit()
            logger.info(f"Switched active database to: {abs_path} (Project: {self._stats['project_name']})")
            return True
        except Exception as e:
            logger.error(f"Error switching database to {abs_path}: {e}", exc_info=True)
            return False

    @Slot(str, str, str, result=dict)
    def test_tfs_connection(self, url, collection, pat):
        """Tests TFS connection and retrieves available projects."""
        clean_url = (url or "").strip().rstrip("/")
        clean_col = (collection or "").strip().strip("/")
        clean_pat = (pat or "").strip()

        if not clean_url:
            return {"success": False, "error": "TFS Base URL cannot be empty", "projects": []}
        if not clean_col:
            clean_col = "DefaultCollection"

        full_tfs_url = f"{clean_url}/{clean_col}"
        logger.info(f"Testing TFS connection to: {full_tfs_url}")

        from azure.azure_base_client import AzureBaseClient
        try:
            client = AzureBaseClient(full_tfs_url, clean_pat)
            res, status = client._request("GET", "_apis/projects", params={"api-version": "6.0"})
            raw_projects = res.get("value", [])
            projects = []
            for p in raw_projects:
                projects.append({
                    "id": p.get("id", ""),
                    "name": p.get("name", ""),
                    "description": p.get("description", "") or "",
                    "state": p.get("state", "wellFormed")
                })
            projects.sort(key=lambda x: x["name"].lower())
            logger.info(f"TFS connection successful: found {len(projects)} projects")
            return {
                "success": True,
                "count": len(projects),
                "projects": projects,
                "message": f"Successfully connected! Found {len(projects)} projects."
            }
        except Exception as e:
            err_msg = str(e)
            logger.warning(f"TFS connection test failed: {err_msg}")
            return {
                "success": False,
                "error": f"Failed to connect to TFS: {err_msg}",
                "projects": []
            }

    @Slot(str, str, str, str, str, str, bool, bool, result=dict)
    def create_project_and_database(self, url, collection, pat, project_id, project_name, db_path, start_sync, store_pat):
        """
        Initializes a new database for the selected project, saves settings,
        and optionally kicks off full synchronization in the background.
        """
        clean_url = (url or "").strip().rstrip("/")
        clean_col = (collection or "").strip().strip("/")
        clean_pat = (pat or "").strip()
        clean_pname = (project_name or "").strip()
        clean_pid = (project_id or clean_pname).strip()

        if not clean_pname:
            return {"success": False, "error": "Project name cannot be empty"}

        if not db_path or not db_path.strip():
            db_path = os.path.join(devops_helper.BASE_FOLDER, f"tfs_cache_{clean_pname}.db")
        else:
            db_path = db_path.strip()
            if not db_path.endswith(".db"):
                db_path += ".db"

        abs_db_path = os.path.abspath(db_path)
        logger.info(f"Creating new database for project '{clean_pname}' at: {abs_db_path}")

        try:
            # 1. Update in-memory devops_helper configuration
            devops_helper.AZURE_BASE_URL = clean_url
            devops_helper.AZURE_COLLECTION = clean_col
            if clean_pat:
                devops_helper.AZURE_PERSONAL_ACCESS_TOKEN = clean_pat
            devops_helper.AZURE_PROJECT_ID = clean_pname

            # 2. Save to user_settings.json
            cfg = _load_user_settings()
            cfg["tfs_url"] = clean_url
            cfg["collection"] = clean_col
            cfg["store_pat"] = store_pat
            if store_pat and clean_pat:
                cfg["pat"] = clean_pat
            cfg["project_id"] = clean_pname
            cfg["project_name"] = clean_pname
            cfg["db_path"] = abs_db_path

            recent_dbs = cfg.get("recent_databases", [])
            if abs_db_path in recent_dbs:
                recent_dbs.remove(abs_db_path)
            recent_dbs.insert(0, abs_db_path)
            cfg["recent_databases"] = recent_dbs[:10]

            recent_projs = cfg.get("recent_projects", [])
            recent_projs = [p for p in recent_projs if p.get("name") != clean_pname]
            recent_projs.insert(0, {
                "name": clean_pname,
                "id": clean_pid,
                "url": clean_url,
                "collection": clean_col,
                "db_path": abs_db_path,
                "date": datetime.now().strftime("%Y-%m-%d %H:%M")
            })
            cfg["recent_projects"] = recent_projs[:10]
            _save_user_settings(cfg)

            # 3. Initialize SQLite Cache Database
            os.makedirs(os.path.dirname(abs_db_path), exist_ok=True)
            new_cache = AzureDevOpsCache(abs_db_path)
            with new_cache._connection() as conn:
                conn.execute("""
                INSERT INTO projects (id, name, last_synced_at)
                VALUES (?, ?, NULL)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name
                """, (clean_pid, clean_pname))

            # 4. Switch active backend cache
            self._db_path = abs_db_path
            self._cache_db = new_cache
            self._stats["db_path"] = abs_db_path
            self._stats["project_name"] = clean_pname

            # 5. Reload GUI state
            self.refresh_all_data()
            self.load_interactive_reports()
            self.settingsChanged.emit()
            self.statsChanged.emit()

            logger.info(f"Project '{clean_pname}' connected and database created successfully: {abs_db_path}")

            # 6. Kick off background sync if requested
            if start_sync:
                logger.info("Initiating automatic initial synchronization in background...")
                self.sync_all_async()

            return {
                "success": True,
                "project_name": clean_pname,
                "db_path": abs_db_path,
                "sync_started": start_sync
            }

        except Exception as e:
            err_msg = str(e)
            logger.error(f"Error creating project and database: {err_msg}", exc_info=True)
            return {"success": False, "error": err_msg}

    @Slot(str)
    def open_path_in_explorer(self, file_or_dir):
        """Opens a file or directory in Windows File Explorer or default program."""
        if not file_or_dir:
            file_or_dir = os.path.dirname(os.path.abspath(self._db_path)) if self._db_path else os.getcwd()
        
        abs_path = os.path.abspath(file_or_dir)
        if os.path.exists(abs_path):
            try:
                os.startfile(abs_path)
                self.logMessage.emit(f"Opened in Explorer: {abs_path}")
            except Exception as e:
                self.logMessage.emit(f"Failed to open path {abs_path}: {e}")
        else:
            self.logMessage.emit(f"Path does not exist: {abs_path}")

    @Slot(str)
    def open_url(self, url_str):
        """Opens a web URL in the system default browser."""
        if not url_str:
            return
        try:
            from PySide6.QtGui import QDesktopServices
            from PySide6.QtCore import QUrl
            QDesktopServices.openUrl(QUrl(url_str))
            self.logMessage.emit(f"Opened URL: {url_str}")
        except Exception as e:
            logger.error(f"Failed to open URL {url_str}: {e}")
            self.logMessage.emit(f"Failed to open URL {url_str}: {e}")

    @Slot()
    def open_tagday_markdown_report(self):
        """Opens the generated Tag Day Markdown report file in the default viewer/editor."""
        output_path = os.path.normpath(os.path.join(devops_helper.BASE_FOLDER, devops_helper.TAGDAY_FILE_MD))
        if os.path.exists(output_path):
            self.open_path_in_explorer(output_path)
            return

        # Check relative to workspace
        py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        ws_path = os.path.abspath(os.path.join(py_dir, "..", "..", devops_helper.TAGDAY_FILE_MD))
        if os.path.exists(ws_path):
            self.open_path_in_explorer(ws_path)
            return

        # Local relative fallback
        if os.path.exists(devops_helper.TAGDAY_FILE_MD):
            self.open_path_in_explorer(devops_helper.TAGDAY_FILE_MD)
            return

        self.logMessage.emit(f"Tag Day report file not found at: {output_path}")

    def _extract_pr_tasks(self, pr):
        """
        Extracts referenced work item IDs from PR title, description, and raw_json,
        then queries work_items from the SQLite cache to enrich with task details.
        """
        if not pr:
            return []

        task_id_regexes = [
            re.compile(r"#(\d{4,7})\b"),
            re.compile(r"\b(?:task|bug|wi|issue|workitem|feat|feature)\s*[:#]?\s*(\d{4,7})\b", re.IGNORECASE),
        ]
        task_ids = set()
        title = str(pr.get("title") or "")
        desc = str(pr.get("description") or "")
        text = f"{title}\n{desc}"

        for regex in task_id_regexes:
            for m in regex.finditer(text):
                task_ids.add(m.group(1))

        # Check raw_json if any
        raw_json_str = pr.get("raw_json")
        if raw_json_str and isinstance(raw_json_str, str):
            try:
                raw_obj = json.loads(raw_json_str)
                for ref in raw_obj.get("workItemRefs", []) or []:
                    if isinstance(ref, dict) and ref.get("id"):
                        task_ids.add(str(ref["id"]))
                    elif isinstance(ref, (str, int)):
                        task_ids.add(str(ref))
            except Exception:
                pass

        # Discard PR ID itself to avoid self-referencing
        pr_id = str(pr.get("pr_id") or "")
        if pr_id:
            task_ids.discard(pr_id)

        if not task_ids:
            return []

        found_map = {}
        if self._cache_db:
            try:
                with self._cache_db._connection() as conn:
                    placeholders = ",".join("?" for _ in task_ids)
                    query = f"""
                        SELECT id, title, type, state, assigned_to, deleted
                        FROM work_items
                        WHERE id IN ({placeholders})
                    """
                    rows = conn.execute(query, list(task_ids)).fetchall()
                    found_map = {str(r["id"]): dict(r) for r in rows}
            except Exception as e:
                logger.warning(f"Error querying work items for PR tasks: {e}")

        tasks = []
        base_url = (devops_helper.AZURE_BASE_URL).rstrip("/")
        collection = (devops_helper.AZURE_COLLECTION).strip("/")
        project_id = devops_helper.AZURE_PROJECT_ID
        for tid in sorted(task_ids, key=lambda x: int(x)):
            info = found_map.get(str(tid))
            url = f"{base_url}/{collection}/{project_id}/_workitems/edit/{tid}"
            if info:
                tasks.append({
                    "id": str(info["id"]),
                    "title": info.get("title") or f"Work Item #{tid}",
                    "type": info.get("type") or "Task",
                    "state": info.get("state") or "Active",
                    "assigned_to": info.get("assigned_to") or "",
                    "deleted": bool(info.get("deleted", 0)),
                    "url": url,
                    "in_cache": True,
                })
            else:
                tasks.append({
                    "id": str(tid),
                    "title": f"Task #{tid}",
                    "type": "Task",
                    "state": "Linked",
                    "assigned_to": "",
                    "deleted": False,
                    "url": url,
                    "in_cache": False,
                })
        return tasks

    def _populate_tagday_data(self, td_raw):
        """Populates _tagday_data structure and emits tagDayDataChanged."""
        if not td_raw:
            return
        timeline = td_raw.get("all_changes_timeline", [])
        repos_changed = td_raw.get("repos_with_any_changes", {})

        repos_summary = []
        for rname, rinfo in sorted(repos_changed.items()):
            latest_tag = rinfo.get("latest_tag")
            tag_name = "-"
            tag_details = None
            if isinstance(latest_tag, dict):
                tag_name = latest_tag.get("name") or latest_tag.get("tag_name") or "-"
                tag_details = {
                    "name": tag_name,
                    "commit_date": latest_tag.get("commit_date") or "",
                    "committer": latest_tag.get("committer") or "",
                    "comment": latest_tag.get("comment") or "",
                }

            prs_after_tag = rinfo.get("prs_after_tag", [])
            active_prs = rinfo.get("active_prs", [])
            all_prs = rinfo.get("all_prs", [])
            unmerged_branches = rinfo.get("unmerged_branches", [])

            # Enrich PRs with referenced tasks queried from SQLite cache
            enriched_prs_after_tag = []
            for p in prs_after_tag:
                p_copy = dict(p)
                p_copy["tasks"] = self._extract_pr_tasks(p_copy)
                enriched_prs_after_tag.append(p_copy)

            enriched_active_prs = []
            for p in active_prs:
                p_copy = dict(p)
                p_copy["tasks"] = self._extract_pr_tasks(p_copy)
                enriched_active_prs.append(p_copy)

            enriched_all_prs = []
            for p in all_prs:
                p_copy = dict(p)
                p_copy["tasks"] = self._extract_pr_tasks(p_copy)
                enriched_all_prs.append(p_copy)

            clean_branches = []
            for b in unmerged_branches:
                prep_pr_id = ""
                prep_pr_title = ""
                if b.get("prepared_pr"):
                    prep_pr_id = str(b["prepared_pr"].get("pr_id", ""))
                    prep_pr_title = str(b["prepared_pr"].get("title", ""))

                clean_branches.append({
                    "branch_name": b.get("branch_name", ""),
                    "commit_id": b.get("commit_id", ""),
                    "short_hash": b.get("short_hash", ""),
                    "commit_date": b.get("commit_date", ""),
                    "committer": b.get("committer", ""),
                    "comment": b.get("comment", ""),
                    "ahead": b.get("ahead", 0),
                    "behind": b.get("behind", 0),
                    "prepared_pr_id": prep_pr_id,
                    "prepared_pr_title": prep_pr_title,
                })

            repos_summary.append({
                "name": rname,
                "id": rinfo.get("id", ""),
                "default_branch": rinfo.get("default_branch", "main"),
                "web_url": rinfo.get("web_url", ""),
                "category": rinfo.get("category", "OTHERS"),
                "is_disabled": rinfo.get("is_disabled", False),
                "latest_tag": tag_name,
                "latest_tag_details": tag_details,
                "prs_count": len(prs_after_tag),
                "active_prs_count": len(active_prs),
                "all_prs_count": len(all_prs),
                "branches_count": len(unmerged_branches),
                "prs_after_tag": enriched_prs_after_tag,
                "active_prs": enriched_active_prs,
                "all_prs": enriched_all_prs,
                "unmerged_branches": clean_branches,
            })

        self._tagday_data = {
            "repos_analyzed": len(td_raw.get("all_repositories", {})),
            "repos_with_changes_count": len(repos_changed),
            "timeline_items_count": len(timeline),
            "timeline": timeline[:100],
            "repos_summary": repos_summary,
            "generated_at": td_raw.get("generated_at", ""),
        }
        self.tagDayDataChanged.emit()
