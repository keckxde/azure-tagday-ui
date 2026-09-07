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
    sprintReportGenerated = Signal(dict, str)  # data dict, markdown content
    workloadMatrixChanged = Signal()
    iterationShiftsChanged = Signal()
    fontSizeModeChanged = Signal(str, float)  # mode string, scale factor
    bugHierarchyModeChanged = Signal(str)     # 'like_user_story' or 'like_task'
    logRecord = Signal(str, str, str, str)  # timestamp, level, logger_name, message
    logMessage = Signal(str)                # legacy formatted string signal
    syncLogsChanged = Signal()
    busyChanged = Signal()
    statusMessageChanged = Signal()
    progressChanged = Signal(int)

    @staticmethod
    def _scale_for_font_mode(mode):
        m = (mode or "medium").lower()
        if m == "small":
            return 0.90
        elif m == "large":
            return 1.15
        elif m in ("xlarge", "xl", "extra_large"):
            return 1.30
        return 1.0

    def __init__(self, parent=None):
        super().__init__(parent)
        self._is_busy = False
        self._status_message = "Ready"
        self._progress = 0
        self._worker = None

        # Font size & UI Scaling
        user_cfg = _load_user_settings()
        self._font_size_mode = user_cfg.get("font_size_mode", "medium")
        self._ui_scale = float(user_cfg.get("ui_scale", self._scale_for_font_mode(self._font_size_mode)))
        self._bug_hierarchy_mode = user_cfg.get("bug_behavior", "like_user_story")

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
            "closed_work_items_count": 0,
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
        self._custom_deadline_field = _load_user_settings().get("custom_deadline_field", "") or utils.get_configured_deadline_field()

        # Initialize cache handler only — heavy data load happens in startup_load_async()
        self._init_cache()

    def _init_cache(self):
        try:
            cfg = _load_user_settings()
            if cfg.get("custom_deadline_field"):
                self._custom_deadline_field = cfg["custom_deadline_field"]
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

    @Property(str, notify=settingsChanged)
    def customDeadlineField(self):
        return self._custom_deadline_field or ""

    @Slot(str)
    def setCustomDeadlineField(self, field_name):
        val = (field_name or "").strip()
        if self._custom_deadline_field != val:
            self._custom_deadline_field = val
            cfg = _load_user_settings()
            cfg["custom_deadline_field"] = val
            _save_user_settings(cfg)
            self.settingsChanged.emit()
            self.refresh_all_data()

    @Property(str, notify=fontSizeModeChanged)
    def fontSizeMode(self):
        return self._font_size_mode or "medium"

    @Property(float, notify=fontSizeModeChanged)
    def uiScale(self):
        return self._ui_scale or 1.0

    @Slot(str)
    def setFontSizeMode(self, mode):
        mode_str = (mode or "medium").lower()
        if mode_str not in ("small", "medium", "large", "xlarge"):
            mode_str = "medium"
        self._font_size_mode = mode_str
        self._ui_scale = self._scale_for_font_mode(mode_str)

        cfg = _load_user_settings()
        cfg["font_size_mode"] = self._font_size_mode
        cfg["ui_scale"] = self._ui_scale
        _save_user_settings(cfg)

        self.fontSizeModeChanged.emit(self._font_size_mode, self._ui_scale)
        self.settingsChanged.emit()

    @Property(str, notify=bugHierarchyModeChanged)
    def bugHierarchyMode(self):
        return self._bug_hierarchy_mode or "like_user_story"

    @Slot(str)
    def setBugHierarchyMode(self, mode):
        mode_str = (mode or "like_user_story").lower()
        if mode_str not in ("like_user_story", "like_task"):
            mode_str = "like_user_story"
        self._bug_hierarchy_mode = mode_str
        cfg = _load_user_settings()
        cfg["bug_behavior"] = self._bug_hierarchy_mode
        _save_user_settings(cfg)
        self.bugHierarchyModeChanged.emit(self._bug_hierarchy_mode)
        self.workloadMatrixChanged.emit()
        self.settingsChanged.emit()

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

    @Property(list, notify=workItemsChanged)
    def workItemStates(self):
        """Returns the sorted unique list of work item states currently in cache."""
        preferred_order = ["Active", "In Progress", "In Planning", "Proposed", "New", "Resolved", "Closed", "Done"]
        seen = set()
        for wi in self._work_items:
            s = wi.get("state") or ""
            if s and s != "Deleted":
                seen.add(s)
        ordered = [s for s in preferred_order if s in seen]
        others = sorted([s for s in seen if s not in preferred_order])
        return ordered + others

    @Property(list, notify=workItemsChanged)
    def workItemAssignees(self):
        """Returns the sorted unique list of assignees currently in cache."""
        seen = set()
        for wi in self._work_items:
            a = wi.get("assigned_to") or ""
            if a and a != "Unassigned":
                seen.add(a)
        return sorted(seen)

    @Property(list, notify=workItemsChanged)
    def workItemIterations(self):
        """Returns the sorted unique list of planned iteration names currently in cache."""
        seen = set()
        for wi in self._work_items:
            if wi.get("is_iteration_planned") and wi.get("iteration_name"):
                seen.add(wi.get("iteration_name"))
        return sorted(seen)

    @Property(list, notify=workItemsChanged)
    def availableSprintList(self):
        """Returns the chronologically sorted list of all week-YYWW sprint names in cache."""
        seen = set()
        for wi in self._work_items:
            s_name = wi.get("sprint_week_name")
            if s_name and "week-" in s_name.lower():
                seen.add(s_name)
            else:
                y, w, b_name = utils.parse_sprint_week(wi.get("iteration_name") or wi.get("iteration_path") or "")
                if b_name:
                    seen.add(b_name)
        def sort_key(s):
            y, w, _ = utils.parse_sprint_week(s)
            return (y or 0, w or 0)
        return sorted(seen, key=sort_key, reverse=True)

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

    @Property(list, notify=iterationShiftsChanged)
    def iterationShifts(self):
        if not self._cache_db:
            return []
        try:
            return self._cache_db.get_iteration_shifts(limit=200)
        except Exception:
            return []

    @Property(dict, notify=iterationShiftsChanged)
    def shiftImpactMetrics(self):
        if not self._cache_db:
            return {
                "total_shifts": 0, "affected_work_items": 0, "total_postponed": 0,
                "total_accelerated": 0, "net_delayed_weeks": 0, "top_postponed": []
            }
        try:
            return self._cache_db.get_shift_metrics()
        except Exception:
            return {
                "total_shifts": 0, "affected_work_items": 0, "total_postponed": 0,
                "total_accelerated": 0, "net_delayed_weeks": 0, "top_postponed": []
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
            self._tfs_wi_url_base = tfs_wi_url_base

            raw_wis = self._cache_db.get_all_work_items(include_deleted=True)

            # Determine iteration hierarchy to identify planned sprint iterations vs root / backlog containers
            all_iter_paths = set()
            for wi in raw_wis:
                ipath = wi.get("iteration_path") or ""
                if not ipath:
                    raw_s = wi.get("raw_json")
                    if raw_s and isinstance(raw_s, str):
                        try:
                            raw_data = json.loads(raw_s)
                            ipath = raw_data.get("fields", {}).get("System.IterationPath") or ""
                        except Exception:
                            pass
                if ipath:
                    all_iter_paths.add(ipath)

            # Normalize paths with forward slash to check parent container relationships
            norm_iter_paths = {p.replace("\\", "/").strip("/"): p for p in all_iter_paths}
            parent_iter_paths = set()
            for np in norm_iter_paths:
                for other in norm_iter_paths:
                    if other != np and other.startswith(np + "/"):
                        parent_iter_paths.add(np)
                        break

            # Query iteration shifts summary per work item
            self._shift_summary_map = {}
            if self._cache_db:
                try:
                    with self._cache_db._connection() as conn:
                        shift_rows = conn.execute("""
                            SELECT work_item_id, COUNT(*) as shift_count, 
                                   SUM(CASE WHEN delta_weeks > 0 THEN delta_weeks ELSE 0 END) as total_delayed_weeks,
                                   SUM(delta_weeks) as net_delta_weeks,
                                   MAX(recorded_at) as last_shift_at
                            FROM iteration_shifts
                            GROUP BY work_item_id
                        """).fetchall()
                        for s_row in shift_rows:
                            self._shift_summary_map[s_row["work_item_id"]] = {
                                "shift_count": s_row["shift_count"],
                                "total_delayed_weeks": s_row["total_delayed_weeks"] or 0,
                                "net_delta_weeks": s_row["net_delta_weeks"] or 0,
                                "last_shift_at": s_row["last_shift_at"] or ""
                            }
                except Exception as e:
                    logger.debug(f"Could not query iteration shifts summary: {e}")

            wi_list = []
            deleted_count = 0
            active_wi_count = 0
            closed_wi_count = 0
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
                
                raw_state = (wi.get("state") or wi.get("State") or "").strip()
                state_val = "Deleted" if is_del else (raw_state if raw_state else "Unknown")
                
                raw_assigned = wi.get("assigned_to") or wi.get("AssignedTo") or ""
                if isinstance(raw_assigned, dict):
                    assigned_val = raw_assigned.get("displayName") or raw_assigned.get("uniqueName") or ""
                else:
                    assigned_val = str(raw_assigned).strip()
                if not assigned_val or assigned_val.lower() in ("undefined", "none", "unknown"):
                    assigned_val = "Unassigned"

                if not is_del:
                    s_lower = state_val.lower()
                    if s_lower in ("closed", "done", "resolved", "completed", "removed", "cut"):
                        closed_wi_count += 1
                    else:
                        active_wi_count += 1

                # Iteration and Deadline parsing
                iter_path = wi.get("iteration_path") or ""
                target_date = ""
                raw_fields = {}
                raw_s = wi.get("raw_json")
                if raw_s and isinstance(raw_s, str):
                    try:
                        raw_data = json.loads(raw_s)
                        raw_fields = raw_data.get("fields", {})
                        if not iter_path:
                            iter_path = raw_fields.get("System.IterationPath") or ""
                    except Exception:
                        pass

                target_date, _ = utils.extract_work_item_deadline(raw_fields, custom_field=self._custom_deadline_field)
                if not target_date:
                    target_date = wi.get("target_date") or wi.get("finish_date") or wi.get("due_date") or ""

                # Parent ID extraction
                parent_id = None
                p_val = raw_fields.get("System.Parent")
                if p_val is not None:
                    try:
                        parent_id = int(str(p_val).lstrip("#"))
                    except (ValueError, TypeError):
                        parent_id = None
                elif raw_data and isinstance(raw_data, dict) and "relations" in raw_data:
                    for rel in raw_data.get("relations") or []:
                        rel_name = rel.get("rel") or ""
                        if "Hierarchy-Reverse" in rel_name or rel_name == "Parent" or (rel.get("attributes") or {}).get("name") == "Parent":
                            url = rel.get("url", "")
                            if url:
                                try:
                                    parent_id = int(url.rstrip("/").split("/")[-1])
                                    break
                                except (ValueError, TypeError):
                                    pass

                norm_ip = iter_path.replace("\\", "/").strip("/") if iter_path else ""
                ip_parts = [p for p in norm_ip.split("/") if p]

                # An item is considered planned in an iteration if:
                # 1. It has an iteration path beyond the single project root
                # 2. It is not a parent container (e.g. project root or team area root)
                # 3. Its leaf does not contain 'backlog'
                is_planned = False
                iter_name = ""
                if ip_parts and len(ip_parts) > 1 and norm_ip not in parent_iter_paths:
                    leaf = ip_parts[-1]
                    if "backlog" not in leaf.lower():
                        is_planned = True
                        iter_name = leaf
                    else:
                        iter_name = leaf
                elif ip_parts and len(ip_parts) > 1:
                    iter_name = ip_parts[-1]
                elif ip_parts:
                    iter_name = ip_parts[0]

                # Sprint week date resolution
                sprint_y, sprint_w, base_sprint_name = utils.parse_sprint_week(iter_name or iter_path)
                sprint_end_str = ""
                if sprint_y and sprint_w:
                    _, _, _, sprint_end_str = utils.get_sprint_date_range(sprint_y, sprint_w)
                    if not target_date:
                        target_date = sprint_end_str

                is_done = s_lower in ("closed", "done", "resolved", "completed", "removed", "cut")
                urgency = utils.calculate_deadline_urgency(target_date, is_completed=is_done)

                # Query shift metrics for this item
                shift_summary_map = getattr(self, "_shift_summary_map", {})
                s_info = shift_summary_map.get(wi_id, {})
                s_count = s_info.get("shift_count", 0)
                d_weeks = s_info.get("total_delayed_weeks", 0)
                s_badge = ""
                if d_weeks > 0:
                    s_badge = f"⚠️ Shifted +{d_weeks}w"
                elif s_count > 0:
                    s_badge = f"🔄 Shifted ({s_count}x)"

                wi_list.append({
                    "id": wi_id,
                    "title": wi.get("title") or f"Work Item #{wi_id}",
                    "type": wi.get("type") or wi.get("WorkItemType") or "Task",
                    "state": state_val,
                    "assigned_to": assigned_val,
                    "parent_id": parent_id,
                    "changed_date": wi.get("changed_date") or "",
                    "iteration_path": iter_path,
                    "iteration_name": iter_name,
                    "is_iteration_planned": is_planned,
                    "sprint_week_name": base_sprint_name or (iter_name if is_planned else ""),
                    "target_date": target_date,
                    "deadline_str": urgency.get("deadline_str", ""),
                    "urgency_status": urgency.get("status", "none"),
                    "urgency_badge": urgency.get("badge_text", "—"),
                    "urgency_color": urgency.get("badge_color", "#8b949e"),
                    "days_diff": urgency.get("days_diff"),
                    "shift_count": s_count,
                    "total_delayed_weeks": d_weeks,
                    "shift_badge": s_badge,
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
                "active_work_items_count": active_wi_count,
                "closed_work_items_count": closed_wi_count,
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
            worker.log_message.emit("Checking Azure DevOps / TFS credentials...")
            azHandler = devops_helper._getHandler()
            if not azHandler:
                raise RuntimeError(
                    "Azure DevOps client could not be initialized: missing Server URL, PAT, or Project ID. "
                    "Please check your .env file or Settings view."
                )
            worker.log_message.emit("Starting full Azure DevOps sync (repositories, work items, pull requests)...")
            devops_helper.sync(force_sync=True)
            return "Full synchronization finished successfully"

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

    @Slot(int, result=dict)
    def getWorkloadMatrix(self, horizon_weeks=4):
        """
        Computes the interactive capacity and workload matrix for team members across
        the given horizon of weekly iterations (4, 8, or 12 weeks).
        """
        sprint_keys = set()
        for wi in self._work_items:
            s_name = wi.get("sprint_week_name")
            if s_name:
                y, w, b_name = utils.parse_sprint_week(s_name)
                if y and w and b_name:
                    sprint_keys.add((y, w, b_name))
            else:
                iter_n = wi.get("iteration_name") or wi.get("iteration_path") or ""
                y, w, b_name = utils.parse_sprint_week(iter_n)
                if y and w and b_name:
                    sprint_keys.add((y, w, b_name))

        # Sort sprints chronologically ascending
        sorted_sprints = sorted(list(sprint_keys), key=lambda x: (x[0], x[1]))
        
        # Take the last horizon_weeks sprints
        if horizon_weeks <= 0:
            horizon_weeks = 4
        target_sprints = sorted_sprints[-horizon_weeks:] if len(sorted_sprints) >= horizon_weeks else sorted_sprints

        sprint_columns = []
        for y, w, s_name in target_sprints:
            s_d, e_d, start_str, end_str = utils.get_sprint_date_range(y, w)
            lbl = utils.format_sprint_range_label(y, w)
            sprint_columns.append({
                "sprint_name": s_name,
                "label": lbl,
                "short_label": f"W{w:02d}",
                "start_date": start_str,
                "end_date": end_str,
                "year": y,
                "week": w,
            })

        target_sprint_names = [col["sprint_name"] for col in sprint_columns]

        # Group work items by assignee and sprint
        assignees_data = {}
        assignee_stats = {}

        total_matrix_items = 0
        total_matrix_stories = 0
        total_matrix_bugs = 0
        total_matrix_tasks = 0
        total_matrix_overdue = 0

        for wi in self._work_items:
            if wi.get("deleted"):
                continue
            wi_sprint = wi.get("sprint_week_name")
            if not wi_sprint:
                _, _, wi_sprint = utils.parse_sprint_week(wi.get("iteration_name") or wi.get("iteration_path") or "")

            if not wi_sprint or wi_sprint not in target_sprint_names:
                continue

            assignee = (wi.get("assigned_to") or "Unassigned").strip()
            if assignee not in assignees_data:
                assignees_data[assignee] = {s_name: [] for s_name in target_sprint_names}
                assignee_stats[assignee] = {
                    "total": 0, "stories": 0, "bugs": 0, "tasks": 0, "overdue": 0, "completed": 0
                }

            t_lower = (wi.get("type") or "").lower()
            is_story = t_lower in ("requirement", "user story", "story", "product backlog item")
            is_bug = t_lower in ("bug", "defect", "problem")
            is_task = t_lower in ("task",)
            is_overdue = wi.get("urgency_status") == "overdue"
            is_done = wi.get("state", "").lower() in ("closed", "done", "resolved", "completed", "cut")

            item_info = {
                "id": wi.get("id"),
                "title": wi.get("title") or f"#{wi.get('id')}",
                "type": wi.get("type") or "Task",
                "state": wi.get("state") or "Active",
                "assigned_to": assignee,
                "parent_id": wi.get("parent_id"),
                "sprint_name": wi_sprint,
                "deadline_str": wi.get("deadline_str", ""),
                "urgency_status": wi.get("urgency_status", "none"),
                "urgency_badge": wi.get("urgency_badge", "—"),
                "urgency_color": wi.get("urgency_color", "#8b949e"),
                "tfs_url": wi.get("tfs_url", ""),
                "iteration_path": wi.get("iteration_path", ""),
                "shift_count": wi.get("shift_count", 0),
                "total_delayed_weeks": wi.get("total_delayed_weeks", 0),
                "shift_badge": wi.get("shift_badge", ""),
                "is_done": is_done,
                "is_story": is_story,
                "is_bug": is_bug,
                "is_task": is_task,
            }

            assignees_data[assignee][wi_sprint].append(item_info)
            assignee_stats[assignee]["total"] += 1
            if is_story:
                assignee_stats[assignee]["stories"] += 1
                total_matrix_stories += 1
            elif is_bug:
                assignee_stats[assignee]["bugs"] += 1
                total_matrix_bugs += 1
            elif is_task:
                assignee_stats[assignee]["tasks"] += 1
                total_matrix_tasks += 1

            if is_overdue:
                assignee_stats[assignee]["overdue"] += 1
                total_matrix_overdue += 1
            if is_done:
                assignee_stats[assignee]["completed"] += 1

            total_matrix_items += 1

        all_wis_by_id = {wi["id"]: wi for wi in self._work_items if not wi.get("deleted")}

        assignee_rows = []
        for assignee, sprints_map in sorted(assignees_data.items(), key=lambda x: assignee_stats[x[0]]["total"], reverse=True):
            cells = []
            for col in sprint_columns:
                s_name = col["sprint_name"]
                items = sprints_map.get(s_name, [])
                st_count = sum(1 for it in items if it["is_story"])
                bg_count = sum(1 for it in items if it["is_bug"])
                tk_count = sum(1 for it in items if it["is_task"])
                od_count = sum(1 for it in items if it["urgency_status"] == "overdue")
                cp_count = sum(1 for it in items if it["is_done"])

                # Group items by parent containers
                grouped = self._group_items_into_containers(items, all_wis_by_id, bug_mode=self._bug_hierarchy_mode)

                cells.append({
                    "assignee": assignee,
                    "sprint_name": s_name,
                    "total_count": len(items),
                    "stories_count": st_count,
                    "bugs_count": bg_count,
                    "tasks_count": tk_count,
                    "overdue_count": od_count,
                    "completed_count": cp_count,
                    "items": sorted(items, key=lambda x: x["id"], reverse=True),
                    "grouped_containers": grouped,
                    "container_count": len(grouped),
                })

            parts = [p for p in assignee.replace(".", " ").replace("_", " ").split() if p]
            initials = "".join([p[0].upper() for p in parts[:2]]) if parts else "U"

            assignee_rows.append({
                "assignee": assignee,
                "initials": initials,
                "stats": assignee_stats[assignee],
                "cells": cells,
            })

        column_totals = []
        for col in sprint_columns:
            s_name = col["sprint_name"]
            c_items = []
            for a_name, s_map in assignees_data.items():
                c_items.extend(s_map.get(s_name, []))
            column_totals.append({
                "sprint_name": s_name,
                "total_count": len(c_items),
                "stories_count": sum(1 for it in c_items if it["is_story"]),
                "bugs_count": sum(1 for it in c_items if it["is_bug"]),
                "tasks_count": sum(1 for it in c_items if it["is_task"]),
                "overdue_count": sum(1 for it in c_items if it["urgency_status"] == "overdue"),
                "completed_count": sum(1 for it in c_items if it["is_done"]),
            })

        return {
            "horizon_weeks": horizon_weeks,
            "sprint_columns": sprint_columns,
            "column_totals": column_totals,
            "assignee_rows": assignee_rows,
            "total_items": total_matrix_items,
            "total_stories": total_matrix_stories,
            "total_bugs": total_matrix_bugs,
            "total_tasks": total_matrix_tasks,
            "total_overdue": total_matrix_overdue,
            "assignees_count": len(assignee_rows),
            "bug_hierarchy_mode": self._bug_hierarchy_mode,
        }

    def _group_items_into_containers(self, items_in_cell, all_wis_by_id, bug_mode="like_user_story"):
        """
        Groups work items in a sprint cell by parent container.
        - If bug_mode == 'like_user_story': Bugs are top-level containers that can contain tasks.
        - If bug_mode == 'like_task': Bugs are child tasks grouped under parent User Stories / Requirements.
        """
        story_types = {"requirement", "user story", "story", "product backlog item", "feature", "epic"}
        done_states = {"closed", "done", "resolved", "completed", "cut"}

        def _is_container_type(t_str):
            t = (t_str or "").lower()
            if t in story_types:
                return True
            if bug_mode == "like_user_story" and t in ("bug", "defect", "problem"):
                return True
            return False

        def _is_item_done(item_dict):
            if "is_done" in item_dict:
                return bool(item_dict["is_done"])
            st = (item_dict.get("state") or "").lower()
            return st in done_states

        cell_containers = []
        cell_children = []
        for it in items_in_cell:
            if _is_container_type(it.get("type")):
                cell_containers.append(it)
            else:
                cell_children.append(it)

        container_map = {}
        for c in cell_containers:
            cid = c["id"]
            c_done = _is_item_done(c)
            container_map[cid] = {
                "id": cid,
                "title": c.get("title") or f"#{cid}",
                "type": c.get("type") or "Story",
                "state": c.get("state") or "Active",
                "assigned_to": c.get("assigned_to") or "Unassigned",
                "is_parent_in_cell": True,
                "is_external_parent": False,
                "tfs_url": c.get("tfs_url", ""),
                "deadline_str": c.get("deadline_str", ""),
                "urgency_status": c.get("urgency_status", "none"),
                "urgency_badge": c.get("urgency_badge", "—"),
                "urgency_color": c.get("urgency_color", "#8b949e"),
                "iteration_path": c.get("iteration_path", ""),
                "is_done": c_done,
                "shift_count": c.get("shift_count", 0),
                "total_delayed_weeks": c.get("total_delayed_weeks", 0),
                "shift_badge": c.get("shift_badge", ""),
                "tasks": [],
            }

        unparented_children = []
        for ch in cell_children:
            pid = ch.get("parent_id")
            if pid and pid in container_map:
                container_map[pid]["tasks"].append(ch)
            elif pid:
                p_wi = all_wis_by_id.get(pid)
                if not p_wi and self._cache_db:
                    try:
                        db_row = self._cache_db.get_work_item(pid)
                        if db_row:
                            p_wi = {
                                "id": pid,
                                "title": db_row.get("title") or f"Parent #{pid}",
                                "type": db_row.get("type") or "User Story",
                                "state": db_row.get("state") or "Active",
                                "assigned_to": db_row.get("assigned_to") or "Unassigned",
                                "tfs_url": getattr(self, "_tfs_wi_url_base", "") + str(pid) if getattr(self, "_tfs_wi_url_base", "") else "",
                                "iteration_path": "",
                                "is_done": _is_item_done(db_row),
                            }
                    except Exception:
                        p_wi = None

                if not p_wi:
                    # Synthetic parent container so child tasks are not lost from their parent
                    p_wi = {
                        "id": pid,
                        "title": f"Parent Work Item #{pid}",
                        "type": "User Story",
                        "state": "Active",
                        "assigned_to": "External / Unassigned",
                        "tfs_url": getattr(self, "_tfs_wi_url_base", "") + str(pid) if getattr(self, "_tfs_wi_url_base", "") else "",
                        "iteration_path": "",
                        "is_done": False,
                    }

                if pid not in container_map:
                    p_done = _is_item_done(p_wi)
                    container_map[pid] = {
                        "id": pid,
                        "title": p_wi.get("title") or f"#{pid}",
                        "type": p_wi.get("type") or "User Story",
                        "state": p_wi.get("state") or "Active",
                        "assigned_to": p_wi.get("assigned_to") or "Unassigned",
                        "is_parent_in_cell": False,
                        "is_external_parent": True,
                        "tfs_url": p_wi.get("tfs_url", ""),
                        "deadline_str": p_wi.get("deadline_str", ""),
                        "urgency_status": p_wi.get("urgency_status", "none"),
                        "urgency_badge": p_wi.get("urgency_badge", "—"),
                        "urgency_color": p_wi.get("urgency_color", "#8b949e"),
                        "iteration_path": p_wi.get("iteration_path", ""),
                        "is_done": p_done,
                        "shift_count": p_wi.get("shift_count", 0),
                        "total_delayed_weeks": p_wi.get("total_delayed_weeks", 0),
                        "shift_badge": p_wi.get("shift_badge", ""),
                        "tasks": [],
                    }
                container_map[pid]["tasks"].append(ch)
            else:
                unparented_children.append(ch)

        containers_list = []
        for cid, c_obj in container_map.items():
            tsks = c_obj["tasks"]
            tot = len(tsks)
            comp = sum(1 for t in tsks if _is_item_done(t))
            pct = round((comp / tot * 100)) if tot > 0 else (100 if c_obj["is_done"] else 0)
            c_obj["total_tasks_count"] = tot
            c_obj["completed_tasks_count"] = comp
            c_obj["progress_percent"] = pct
            c_obj["progress_pct"] = pct
            containers_list.append(c_obj)

        containers_list.sort(key=lambda x: (not x["is_parent_in_cell"], -x["id"]))

        if unparented_children:
            tot_un = len(unparented_children)
            comp_un = sum(1 for t in unparented_children if _is_item_done(t))
            pct_un = round((comp_un / tot_un * 100)) if tot_un > 0 else 0
            containers_list.append({
                "id": 0,
                "title": "Direct Tasks / Standalone Items",
                "type": "Standalone",
                "state": "Active",
                "assigned_to": items_in_cell[0]["assigned_to"] if items_in_cell else "Unassigned",
                "is_parent_in_cell": True,
                "is_external_parent": False,
                "tfs_url": "",
                "deadline_str": "",
                "urgency_status": "none",
                "urgency_badge": "—",
                "urgency_color": "#8b949e",
                "iteration_path": "",
                "is_done": False,
                "shift_count": 0,
                "total_delayed_weeks": 0,
                "shift_badge": "",
                "tasks": unparented_children,
                "total_tasks_count": tot_un,
                "completed_tasks_count": comp_un,
                "progress_percent": pct_un,
                "progress_pct": pct_un,
            })

        return containers_list

    @Slot()
    @Slot(str, result=dict)
    def get_sprint_report_data(self, sprint_name=""):
        """Returns structured sprint analysis dictionary for real-time GUI preview."""
        if not self._cache_db:
            return {}
        try:
            import generate_sprint_report
            return generate_sprint_report.generate_sprint_report_data(self._cache_db, sprint_name=sprint_name)
        except Exception as e:
            logger.error(f"Error generating sprint report data: {e}", exc_info=True)
            return {"error": str(e)}

    @Slot()
    @Slot(str)
    @Slot(str, str)
    @Slot(str, str, str)
    def generate_sprint_report_async(self, sprint_name="", md_path="", csv_path=""):
        """Generates Sprint Markdown and CSV report in the background."""
        if self._is_busy:
            return

        clean_sprint = (sprint_name or "latest").strip()
        if not md_path:
            md_path = os.path.join(devops_helper.BASE_FOLDER, f"SPRINT_REPORT_{clean_sprint}.md")
        if not csv_path:
            csv_path = os.path.join(devops_helper.BASE_FOLDER, f"SPRINT_REPORT_{clean_sprint}.csv")

        def _work(worker):
            worker.log_message.emit(f"Generating Sprint Report for '{clean_sprint}'...")
            import generate_sprint_report
            data, md_text = generate_sprint_report.generate_sprint_report(
                self._cache_db,
                sprint_name=clean_sprint,
                output_md=md_path,
                output_csv=csv_path
            )
            self.sprintReportGenerated.emit(data, md_text)
            worker.log_message.emit(f"Sprint report saved: {md_path} and {csv_path}")
            return f"Sprint report for {clean_sprint} generated successfully"

        self._run_worker(_work, f"Generating Sprint Report ({clean_sprint})...")

    @Slot()
    @Slot(str)
    def open_sprint_report_file(self, sprint_name=""):
        """Opens generated sprint report markdown in default editor."""
        clean_sprint = (sprint_name or "latest").strip()
        path = os.path.join(devops_helper.BASE_FOLDER, f"SPRINT_REPORT_{clean_sprint}.md")
        if os.path.exists(path):
            self.open_path_in_explorer(path)
        else:
            self.logMessage.emit(f"File does not exist: {path}")

    @Slot(int, str, result=dict)
    def update_work_item_deadline(self, work_item_id, new_date_str):
        """
        Updates the target deadline for a work item both in local SQLite cache and via TFS REST Web API.

        Args:
            work_item_id (int): Work item ID.
            new_date_str (str): Target date (YYYY-MM-DD or empty string to clear).

        Returns:
            dict: {"success": bool, "message": str, "deadline": str, "urgency_badge": str, "urgency_color": str, "api_synced": bool}
        """
        try:
            clean_id = int(work_item_id)
        except (ValueError, TypeError):
            return {"success": False, "error": "Invalid work item ID"}

        clean_date = (new_date_str or "").strip()
        field_to_update = self._custom_deadline_field or "Microsoft.VSTS.Scheduling.TargetDate"

        logger.info(f"Updating deadline for Work Item #{clean_id} -> '{clean_date}' (Field: {field_to_update})")

        # 1. Update local SQLite DB cache
        db_ok = False
        if self._cache_db:
            db_ok = self._cache_db.update_work_item_deadline(clean_id, clean_date, field_name=field_to_update)

        # 2. Synchronize to Azure DevOps / TFS Web API (if handler available)
        api_synced = False
        api_err = None
        try:
            azHandler = devops_helper._getHandler()
            if azHandler and hasattr(azHandler, "update_work_item_field"):
                val_to_send = f"{clean_date}T17:00:00Z" if clean_date and "T" not in clean_date else (clean_date or None)
                azHandler.update_work_item_field(clean_id, field_to_update, val_to_send, project_id=devops_helper.AZURE_PROJECT_ID)
                api_synced = True
                logger.info(f"Work item #{clean_id} deadline successfully synchronized with TFS API.")
        except Exception as e:
            api_err = str(e)
            logger.warning(f"Could not push deadline update for #{clean_id} to TFS API: {e}")

        # 3. Recalculate and refresh memory cache
        self.refresh_all_data()

        # Find updated work item to return fresh urgency badge
        updated_wi = next((w for w in self._work_items if w["id"] == clean_id), None)
        badge = updated_wi.get("urgency_badge", "—") if updated_wi else "—"
        color = updated_wi.get("urgency_color", "#8b949e") if updated_wi else "#8b949e"

        msg = f"Deadline set to {clean_date or 'Cleared'}"
        if api_synced:
            msg += " (Synchronized with TFS Web API)"
        elif api_err:
            msg += f" (Cached locally; TFS API: {api_err})"
        else:
            msg += " (Cached in local SQLite database)"

        self.logMessage.emit(f"[Work Item #{clean_id}] {msg}")
        return {
            "success": True,
            "work_item_id": clean_id,
            "deadline": clean_date,
            "urgency_badge": badge,
            "urgency_color": color,
            "api_synced": api_synced,
            "message": msg
        }

    @Slot(int, str, result=dict)
    def update_work_item_iteration(self, work_item_id, new_iteration):
        """
        Updates the iteration path of a work item, logs the shift event, and syncs to TFS via REST API.

        Args:
            work_item_id (int): Work item ID.
            new_iteration (str): Target sprint name (e.g. 'week-2634') or full iteration path.

        Returns:
            dict: {"success": bool, "message": str, "iteration": str, "api_synced": bool}
        """
        try:
            clean_id = int(work_item_id)
        except (ValueError, TypeError):
            return {"success": False, "error": "Invalid work item ID"}

        clean_iter = (new_iteration or "").strip()
        full_path = clean_iter
        if clean_iter and "\\" not in clean_iter and "/" not in clean_iter:
            p_name = devops_helper.AZURE_PROJECT_ID or ""
            full_path = f"{p_name}\\{clean_iter}" if p_name else clean_iter

        logger.info(f"Rescheduling Work Item #{clean_id} -> Iteration '{full_path}'")

        # 1. Update SQLite DB & log shift event
        db_ok = False
        if self._cache_db:
            db_ok = self._cache_db.update_work_item_iteration(clean_id, full_path, source="gui_manual")

        # 2. Sync to TFS / Azure DevOps API
        api_synced = False
        api_err = None
        try:
            azHandler = devops_helper._getHandler()
            if azHandler and hasattr(azHandler, "update_work_item_field"):
                azHandler.update_work_item_field(clean_id, "System.IterationPath", full_path, project_id=devops_helper.AZURE_PROJECT_ID)
                api_synced = True
                logger.info(f"Work item #{clean_id} iteration successfully synced to TFS API.")
        except Exception as e:
            api_err = str(e)
            logger.warning(f"Could not push iteration update for #{clean_id} to TFS API: {e}")

        # 3. Refresh UI & models
        self.refresh_all_data()
        self.iterationShiftsChanged.emit()
        self.workloadMatrixChanged.emit()

        msg = f"Iteration moved to '{clean_iter or 'Unplanned'}'"
        if api_synced:
            msg += " (Synchronized with TFS Web API)"
        elif api_err:
            msg += f" (Cached locally; TFS API: {api_err})"
        else:
            msg += " (Cached in local SQLite database)"

        self.logMessage.emit(f"[Work Item #{clean_id}] {msg}")
        return {
            "success": True,
            "work_item_id": clean_id,
            "iteration": clean_iter,
            "full_path": full_path,
            "api_synced": api_synced,
            "message": msg
        }

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
