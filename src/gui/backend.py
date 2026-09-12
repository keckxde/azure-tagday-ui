# -*- coding: UTF-8 -*-
"""
QObject backend bridge connecting Python DevOps and SQLite caching services to Qt Quick / QML.
"""
import os
import sys
import json
import logging
import re
import threading
import urllib.parse
from datetime import datetime, date
from PySide6.QtCore import QObject, Signal, Slot, Property, QTimer

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


# ---------------------------------------------------------------------------
# Tag-category helpers (module level so they can be tested independently)
# ---------------------------------------------------------------------------

#: Default tag-category rules shipped with the application.
#: Users can override / extend these in Settings → Tag Categories.
DEFAULT_TAG_CATEGORIES = [
    {"pattern": "Target:*",    "category": "Milestone"},
    {"pattern": "Subsystem:*", "category": "PBS"},
    {"pattern": "v*.*.*",      "category": "Software Revision"},
    {"pattern": "OI",          "category": "Open Item"},
    {"pattern": "MP",          "category": "Merkpunkt"},
]


def classify_tag(tag, tag_categories):
    """
    Returns the category name for *tag* by testing it against the ordered
    *tag_categories* list (each entry is ``{"pattern": str, "category": str}``).

    Matching is done with :func:`fnmatch.fnmatch` which supports ``*`` and ``?``
    wildcards.  The first matching rule wins.  If no rule matches, ``"Other"``
    is returned.

    Args:
        tag (str): The raw tag string from a work item.
        tag_categories (list): Ordered list of ``{pattern, category}`` dicts.

    Returns:
        str: Category name, or ``"Other"`` when no rule matches.
    """
    import fnmatch
    for entry in (tag_categories or []):
        pattern = (entry.get("pattern") or "").strip()
        if not pattern:
            continue
        if fnmatch.fnmatch(tag, pattern):
            return (entry.get("category") or "Other").strip() or "Other"
    return "Other"


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
    milestonesChanged = Signal()
    milestoneCategoriesChanged = Signal()
    repoCategoriesChanged = Signal()
    iterationShiftsChanged = Signal()
    tagCategoriesChanged = Signal()
    fontSizeModeChanged = Signal(str, float)  # mode string, scale factor
    bugHierarchyModeChanged = Signal(str)     # 'like_user_story' or 'like_task'
    autoSyncChanged = Signal()
    logRecord = Signal(str, str, str, str)  # timestamp, level, logger_name, message
    logMessage = Signal(str)                # legacy formatted string signal
    syncLogsChanged = Signal()
    busyChanged = Signal()
    statusMessageChanged = Signal()
    progressChanged = Signal()

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
        self._tfs_team_name = user_cfg.get("tfs_team_name", "")

        # Auto-Sync / Scheduled Synchronization settings
        self._auto_sync_enabled = bool(user_cfg.get("auto_sync_enabled", False))
        self._auto_sync_interval_minutes = int(user_cfg.get("auto_sync_interval_minutes", 5))
        if self._auto_sync_interval_minutes < 1:
            self._auto_sync_interval_minutes = 5
        self._auto_sync_scope = str(user_cfg.get("auto_sync_scope", "all"))
        self._seconds_until_next_sync = self._auto_sync_interval_minutes * 60

        self._auto_sync_timer = QTimer(self)
        self._auto_sync_timer.setInterval(1000)
        self._auto_sync_timer.timeout.connect(self._on_auto_sync_timer_tick)
        self._auto_sync_timer.start()

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
        self._is_pr_titles_patched = False
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

            # Load project configuration stored inside the SQLite database if available
            if self._cache_db:
                self._load_project_config_from_db(self._cache_db)

        except Exception as e:
            logger.error(f"Error initializing SQLite cache: {e}")
            self._db_path = ""
            self._cache_db = None

    def _load_project_config_from_db(self, cache_db):
        """Loads and applies configuration keys stored in the database's project_config table."""
        if not cache_db:
            return
        try:
            db_cfg = cache_db.get_all_config()
            if not db_cfg:
                # Fallback to check projects table for project name if no config table yet
                with cache_db._connection() as conn:
                    p_row = conn.execute("SELECT name FROM projects ORDER BY last_synced_at DESC LIMIT 1").fetchone()
                    if p_row and p_row["name"]:
                        devops_helper.AZURE_PROJECT_ID = p_row["name"]
                        self._stats["project_name"] = p_row["name"]
                return

            if db_cfg.get("AZURE_BASE_URL"):
                devops_helper.AZURE_BASE_URL = db_cfg["AZURE_BASE_URL"]
            if db_cfg.get("AZURE_COLLECTION"):
                devops_helper.AZURE_COLLECTION = db_cfg["AZURE_COLLECTION"]
            if db_cfg.get("AZURE_PROJECT_ID") or db_cfg.get("PROJECT_NAME"):
                p_name = db_cfg.get("PROJECT_NAME") or db_cfg.get("AZURE_PROJECT_ID")
                devops_helper.AZURE_PROJECT_ID = p_name
                self._stats["project_name"] = p_name
            if db_cfg.get("AZURE_PERSONAL_ACCESS_TOKEN"):
                devops_helper.AZURE_PERSONAL_ACCESS_TOKEN = db_cfg["AZURE_PERSONAL_ACCESS_TOKEN"]
            if db_cfg.get("WORK_ITEM_DEADLINE_FIELD"):
                self._custom_deadline_field = db_cfg["WORK_ITEM_DEADLINE_FIELD"]
            if db_cfg.get("bug_behavior"):
                self._bug_hierarchy_mode = db_cfg["bug_behavior"]
            if db_cfg.get("AZURE_TEAM"):
                self._tfs_team_name = db_cfg["AZURE_TEAM"]
            if "AUTO_SYNC_ENABLED" in db_cfg:
                self._auto_sync_enabled = str(db_cfg["AUTO_SYNC_ENABLED"]).lower() in ("true", "1", "yes")
            if "AUTO_SYNC_INTERVAL_MINUTES" in db_cfg:
                try:
                    self._auto_sync_interval_minutes = max(1, int(db_cfg["AUTO_SYNC_INTERVAL_MINUTES"]))
                except Exception:
                    pass
            if "AUTO_SYNC_SCOPE" in db_cfg:
                self._auto_sync_scope = db_cfg["AUTO_SYNC_SCOPE"]
            if "IGNORE_REPOS" in db_cfg:
                devops_helper.IGNORE_REPOS = db_cfg["IGNORE_REPOS"]
            if "FILTER_REPOS" in db_cfg:
                devops_helper.FILTER_REPOS = db_cfg["FILTER_REPOS"]
            if "TAGDAY_FILE_MD" in db_cfg:
                devops_helper.TAGDAY_FILE_MD = db_cfg["TAGDAY_FILE_MD"]
            if "REVISION_FILE_MD" in db_cfg:
                devops_helper.REVISION_FILE_MD = db_cfg["REVISION_FILE_MD"]
            if "BUILD_ARTIFACTS_MD" in db_cfg:
                devops_helper.BUILD_ARTIFACTS_MD = db_cfg["BUILD_ARTIFACTS_MD"]
            if "BUILD_ARTIFACTS_CSV" in db_cfg:
                devops_helper.BUILD_ARTIFACTS_CSV = db_cfg["BUILD_ARTIFACTS_CSV"]
            if "RECENT_DELAY" in db_cfg:
                try:
                    devops_helper.RECENT_DELAY = int(db_cfg["RECENT_DELAY"])
                except Exception:
                    pass
            if "FILTER_VERSION_TAGS_FORMAT" in db_cfg:
                devops_helper.FILTER_VERSION_TAGS_FORMAT = str(db_cfg["FILTER_VERSION_TAGS_FORMAT"]).lower() == "true"
        except Exception as e:
            logger.warning(f"Error reading project config from database: {e}")

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
    def tfsTeamName(self):
        """Returns the configured TFS / Azure DevOps team name used for sprint URLs."""
        return self._tfs_team_name or ""

    @Slot(str)
    def setTfsTeamName(self, team_name):
        """Persists the TFS team name used to build sprint taskboard URLs."""
        val = (team_name or "").strip()
        if self._tfs_team_name != val:
            self._tfs_team_name = val
            cfg = _load_user_settings()
            cfg["tfs_team_name"] = val
            _save_user_settings(cfg)
            if self._cache_db:
                try:
                    self._cache_db.set_config("AZURE_TEAM", val)
                except Exception:
                    pass
            self.settingsChanged.emit()

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

    @Property(bool, notify=autoSyncChanged)
    def autoSyncEnabled(self):
        return self._auto_sync_enabled

    @Slot(bool)
    def setAutoSyncEnabled(self, enabled):
        self._auto_sync_enabled = bool(enabled)
        self._seconds_until_next_sync = self._auto_sync_interval_minutes * 60
        cfg = _load_user_settings()
        cfg["auto_sync_enabled"] = self._auto_sync_enabled
        _save_user_settings(cfg)
        if self._cache_db:
            try:
                self._cache_db.set_config("AUTO_SYNC_ENABLED", str(self._auto_sync_enabled))
            except Exception:
                pass
        self.autoSyncChanged.emit()
        self.settingsChanged.emit()

    @Property(int, notify=autoSyncChanged)
    def autoSyncIntervalMinutes(self):
        return self._auto_sync_interval_minutes

    @Slot(int)
    def setAutoSyncInterval(self, minutes):
        val = max(1, int(minutes)) if minutes > 0 else 5
        self._auto_sync_interval_minutes = val
        self._seconds_until_next_sync = self._auto_sync_interval_minutes * 60
        cfg = _load_user_settings()
        cfg["auto_sync_interval_minutes"] = self._auto_sync_interval_minutes
        _save_user_settings(cfg)
        if self._cache_db:
            try:
                self._cache_db.set_config("AUTO_SYNC_INTERVAL_MINUTES", str(self._auto_sync_interval_minutes))
            except Exception:
                pass
        self.autoSyncChanged.emit()
        self.settingsChanged.emit()

    @Property(str, notify=autoSyncChanged)
    def autoSyncScope(self):
        return self._auto_sync_scope or "all"

    @Slot(str)
    def setAutoSyncScope(self, scope):
        val = (scope or "all").lower()
        if val not in ("all", "work_items", "pull_requests"):
            val = "all"
        self._auto_sync_scope = val
        cfg = _load_user_settings()
        cfg["auto_sync_scope"] = self._auto_sync_scope
        _save_user_settings(cfg)
        if self._cache_db:
            try:
                self._cache_db.set_config("AUTO_SYNC_SCOPE", self._auto_sync_scope)
            except Exception:
                pass
        self.autoSyncChanged.emit()
        self.settingsChanged.emit()

    @Property(int, notify=autoSyncChanged)
    def nextAutoSyncSeconds(self):
        return max(0, self._seconds_until_next_sync)

    @Property(str, notify=autoSyncChanged)
    def nextAutoSyncText(self):
        if not self._auto_sync_enabled:
            return "Off"
        if self._is_busy:
            return "Syncing"
        mm = self._seconds_until_next_sync // 60
        ss = self._seconds_until_next_sync % 60
        return f"{mm:02d}:{ss:02d}"

    @Property(str, notify=autoSyncChanged)
    def autoSyncStatusText(self):
        if not self._auto_sync_enabled:
            return "Auto-sync: Off"
        if self._is_busy:
            return "Syncing in progress..."
        mm = self._seconds_until_next_sync // 60
        ss = self._seconds_until_next_sync % 60
        if mm > 0:
            return f"Auto-sync in {mm}m {ss:02d}s (every {self._auto_sync_interval_minutes}m)"
        return f"Auto-sync in {ss}s (every {self._auto_sync_interval_minutes}m)"

    @Slot()
    def triggerAutoSyncNow(self):
        """Immediately triggers synchronization and resets the auto-sync timer."""
        self.reset_auto_sync_timer()
        if self._auto_sync_scope == "work_items":
            self.sync_work_items_async()
        elif self._auto_sync_scope == "pull_requests":
            self.sync_pull_requests_async()
        else:
            self.sync_all_async()

    def reset_auto_sync_timer(self):
        """Resets the countdown timer to the full interval duration."""
        self._seconds_until_next_sync = self._auto_sync_interval_minutes * 60
        self.autoSyncChanged.emit()

    def _on_auto_sync_timer_tick(self):
        """Periodic 1s tick for auto-sync countdown and scheduled execution."""
        if not self._auto_sync_enabled or self._auto_sync_interval_minutes <= 0:
            return

        # If currently busy with a sync or task, don't tick countdown past 0; defer
        if self._is_busy:
            if self._seconds_until_next_sync <= 0:
                self._seconds_until_next_sync = 30
            self.autoSyncChanged.emit()
            return

        self._seconds_until_next_sync -= 1

        if self._seconds_until_next_sync <= 0:
            logger.info(
                f"[Auto-Sync] Interval reached ({self._auto_sync_interval_minutes}m). "
                f"Starting scheduled synchronization (scope: {self._auto_sync_scope})..."
            )
            self._seconds_until_next_sync = self._auto_sync_interval_minutes * 60
            self.autoSyncChanged.emit()
            if self._auto_sync_scope == "work_items":
                self.sync_work_items_async()
            elif self._auto_sync_scope == "pull_requests":
                self.sync_pull_requests_async()
            else:
                self.sync_all_async()
        else:
            self.autoSyncChanged.emit()

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
    def workItemLevel1List(self):
        """Returns the sorted unique list of Level 1 (Epic / Sub-System) display names, with [<NR>] <Name> complying items first."""
        seen = set()
        for wi in self._work_items:
            disp = wi.get("level1_display") or ""
            if disp and disp != "Ungrouped Sub-System":
                seen.add(disp)
        
        def sort_key(s):
            tag, name, sk = utils.parse_pbs_tag(str(s).strip())
            if tag:
                return (0, sk, name.lower())
            return (1, (0,), str(s).lower())

        return sorted(seen, key=sort_key)

    @Property(list, notify=workItemsChanged)
    def workItemLevel2List(self):
        """Returns the sorted unique list of Level 2 (Feature / Major Component) display names, with [<NR>] <Name> complying items first."""
        seen = set()
        for wi in self._work_items:
            disp = wi.get("level2_display") or ""
            if disp and disp != "Ungrouped Component":
                seen.add(disp)
        
        def sort_key(s):
            tag, name, sk = utils.parse_pbs_tag(str(s).strip())
            if tag:
                return (0, sk, name.lower())
            return (1, (0,), str(s).lower())

        return sorted(seen, key=sort_key)

    @Property(list, notify=workItemsChanged)
    def workItemTags(self):
        """Returns the sorted unique list of all tags currently present on work items in cache."""
        seen = set()
        for wi in self._work_items:
            for t in wi.get("tag_list") or []:
                if t:
                    seen.add(t)
        return sorted(seen, key=lambda s: s.lower())

    @Property(list, notify=workItemsChanged)
    def workItemTargetTags(self):
        """Returns the sorted unique list of Target:<Name> milestone tags present on work items."""
        seen = set()
        for wi in self._work_items:
            for t in wi.get("target_tags") or []:
                if t:
                    seen.add(t)
        return sorted(seen, key=lambda s: s.lower())

    @Property(dict, notify=workItemsChanged)
    def workItemTagCounts(self):
        """Returns a dict mapping tag name -> count of work items having that tag."""
        counts = {}
        for wi in self._work_items:
            for t in wi.get("tag_list") or []:
                if t:
                    counts[t] = counts.get(t, 0) + 1
        return counts

    @Slot(result=list)
    def get_work_item_tags_summary(self):
        """Returns structured list of unique tags with item counts and Target milestone indicator."""
        counts = self.workItemTagCounts
        results = []
        for tag, count in counts.items():
            is_target = tag.lower().startswith("target:")
            results.append({
                "tag": tag,
                "count": count,
                "is_target": is_target,
                "target_short_name": tag.split(":", 1)[1].strip() if is_target else ""
            })
        return sorted(results, key=lambda x: (-x["count"], x["tag"].lower()))

    # ------------------------------------------------------------------
    # Tag-category configuration
    # ------------------------------------------------------------------

    @Property(list, notify=tagCategoriesChanged)
    def tagCategories(self):
        """
        Returns the ordered list of tag-category mapping rules.

        Each item is a dict ``{"pattern": str, "category": str}``.
        Rules are evaluated in order; the first match wins.
        Falls back to :data:`DEFAULT_TAG_CATEGORIES` when nothing is configured.
        """
        cfg = _load_user_settings()
        cats = cfg.get("tag_categories")
        if cats and isinstance(cats, list):
            return cats
        return list(DEFAULT_TAG_CATEGORIES)

    @Slot(str)
    def save_tag_categories(self, categories_json):
        """
        Persists a JSON-encoded list of ``{"pattern", "category"}`` dicts to
        ``user_settings.yaml`` and notifies QML.

        Args:
            categories_json (str): JSON string of the list.
        """
        try:
            cats = json.loads(categories_json)
            if not isinstance(cats, list):
                logger.warning("save_tag_categories: expected a JSON list, got %s", type(cats))
                return
            # Sanitise entries
            cleaned = [
                {"pattern": str(e.get("pattern", "")).strip(),
                 "category": str(e.get("category", "")).strip()}
                for e in cats
                if isinstance(e, dict) and e.get("pattern", "").strip()
            ]
            cfg = _load_user_settings()
            cfg["tag_categories"] = cleaned
            _save_user_settings(cfg)
            self.tagCategoriesChanged.emit()
            self.workItemsChanged.emit()   # refresh tag-by-category derived data
            logger.info("Tag categories saved (%d rules)", len(cleaned))
        except Exception as e:
            logger.error("save_tag_categories failed: %s", e)

    @Slot(result=str)
    def get_tags_by_category(self):
        """
        Returns a JSON string mapping category name → sorted list of tags
        for all tags currently present in work items.

        Used by QML to populate the two-step Category → Tag filter.
        The special category ``"All"`` contains every tag.

        Returns:
            str: JSON-encoded ``{category: [tag, ...], ...}``.
        """
        cats = self.tagCategories
        result = {}
        for tag in self.workItemTags:
            cat = classify_tag(tag, cats)
            result.setdefault(cat, []).append(tag)
        # Sort each bucket
        for key in result:
            result[key] = sorted(result[key], key=lambda s: s.lower())
        return json.dumps(result, ensure_ascii=False)

    @Slot(result=list)
    def get_tag_category_names(self):
        """
        Returns a sorted list of category names that currently have at least
        one matching tag in the work item cache.

        Returns:
            list: Sorted list of category name strings.
        """
        try:
            raw = json.loads(self.get_tags_by_category())
            return sorted(raw.keys())
        except Exception:
            return []

    @Property(list, notify=milestonesChanged)
    def workItemMilestones(self):
        """Returns the sorted list of unique milestone names from configured milestones and work items."""
        seen = set()
        try:
            if self._cache_db:
                for m in self._cache_db.get_milestones():
                    name = (m.get("name") or "").strip()
                    if name:
                        seen.add(name)
        except Exception:
            pass
        for wi in self._work_items:
            m_name = (wi.get("milestone_name") or wi.get("effective_milestone_name") or "").strip()
            if m_name:
                seen.add(m_name)
            for tt in wi.get("target_tags") or []:
                if tt:
                    seen.add(tt)
        return sorted(seen)

    @Property(list, notify=workItemsChanged)
    def availableSprintList(self):
        """Returns the chronologically sorted list of all week-YYWW sprint names in cache and advance prepared iterations."""
        seen = set()
        for wi in self._work_items:
            s_name = wi.get("sprint_week_name")
            if s_name and "week-" in s_name.lower():
                seen.add(s_name)
            else:
                y, w, b_name = utils.parse_sprint_week(wi.get("iteration_name") or wi.get("iteration_path") or "")
                if b_name:
                    seen.add(b_name)
        if self._cache_db:
            try:
                cached_iters = self._cache_db.get_cached_iterations(project=self.selectedProject)
                for ci in cached_iters:
                    cname = ci.get("iteration_name")
                    if cname:
                        seen.add(cname)
            except Exception:
                pass
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

    @Property(bool, notify=pullRequestsChanged)
    def isPrTitlesPatched(self):
        return self._is_pr_titles_patched

    @Slot(result=int)
    def patch_pr_titles(self):
        """
        On user request (e.g. from PR View), patches PR titles by enforcing
        [<TYPE>_<NR>] prefixes from referenced work items.
        Returns the number of patched PR titles.
        """
        if not self._cache_db:
            return 0
        patched_count = 0
        for pr in self._pull_requests:
            orig = pr.get("title") or ""
            patched = devops_helper.patch_pr_title_for_release_notes(pr, cache_db=self._cache_db)
            if patched != orig:
                pr["title"] = patched
                patched_count += 1
        self._is_pr_titles_patched = True
        logger.info(f"PR Title Patcher: Patched {patched_count} pull request titles on request.")
        self.pullRequestsChanged.emit()
        return patched_count

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

    @Property(dict, notify=repoCategoriesChanged)
    def categoryColors(self):
        try:
            if self._cache_db:
                cfg = self._cache_db.get_full_repo_category_config()
                if cfg and cfg.get("category_colors"):
                    return cfg["category_colors"]
        except Exception:
            pass
        return {}

    @Slot(str, result=str)
    def get_category_color(self, category):
        try:
            if self._cache_db:
                cfg = self._cache_db.get_full_repo_category_config()
                colors = cfg.get("category_colors", {}) if cfg else {}
                return colors.get(category, colors.get("OTHERS", "#6e7681"))
        except Exception:
            pass
        return "#6e7681"

    @Property(list, notify=repoCategoriesChanged)
    def repoCategories(self):
        if not self._cache_db:
            return []
        try:
            return self._cache_db.get_repo_categories()
        except Exception:
            return []

    @Property(list, notify=repoCategoriesChanged)
    def repoPrefixRules(self):
        if not self._cache_db:
            return []
        try:
            return self._cache_db.get_repo_prefix_rules()
        except Exception:
            return []

    @Property(list, notify=repoCategoriesChanged)
    def repoCategoryOverrides(self):
        if not self._cache_db:
            return []
        try:
            overrides = self._cache_db.get_repo_category_overrides()
            return [{"repo_name": k, "category": v} for k, v in overrides.items()]
        except Exception:
            return []

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

    @Property(list, notify=milestonesChanged)
    def milestones(self):
        return self.get_milestones()

    @Property(list, notify=milestoneCategoriesChanged)
    def milestoneCategories(self):
        return self.get_milestone_categories()

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
    def _compute_all_cache_data(self, worker=None):
        """
        Computes and structures all cache datasets in a single fast pass.
        Designed to run safely in background threads or on demand without modifying GUI state.
        """
        if not self._cache_db:
            return {}

        if worker:
            worker.report_progress(5, "Analyzing repositories and version tags...")

        # 1. Tag Day Analysis & Repositories
        import generate_tagday_report
        td_raw = generate_tagday_report.load_tagday_data(self._cache_db, project_id=devops_helper.AZURE_PROJECT_ID, patch_titles=False)
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
        devops_helper.addCategoriesToRepos(repos_dict, cache_db=self._cache_db, auto_save_missing=True)

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
        sorted_repos = sorted(repo_list, key=lambda x: x["name"].lower())

        if worker:
            worker.report_progress(25, "Processing work items and hierarchy...")

        # 2. Work Items
        # Build WI -> PR cross-reference map from PR status_str and title #NNNN mentions
        all_prs_raw = self._cache_db.get_all_prs()
        wi_to_prs = {}   # wi_id (int) -> list of {pr_id, repo_name, title}
        wi_to_repos = {} # wi_id (int) -> set of repo names
        try:
            for pr in all_prs_raw:
                pr_id = pr.get("pr_id")
                repo_name = pr.get("repo_name", "")
                pr_title = pr.get("title", "") or ""
                pr_status_str = pr.get("status_str", "") or ""
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
            logger.warning(f"Could not build WI->PR cross-reference map: {e}")

        # Build TFS web base URL for work item links
        tfs_base = (devops_helper.AZURE_BASE_URL or "").rstrip("/")
        tfs_col = (devops_helper.AZURE_COLLECTION or "").strip("/")
        tfs_proj = devops_helper.AZURE_PROJECT_ID or ""
        tfs_wi_url_base = f"{tfs_base}/{tfs_col}/{tfs_proj}/_workitems/edit/" if (tfs_base and tfs_col and tfs_proj) else ""

        raw_wis = self._cache_db.get_all_work_items(include_deleted=True)

        # Determine iteration hierarchy to identify planned sprint iterations vs root / backlog containers
        all_iter_paths = set()
        for wi in raw_wis:
            ipath = wi.get("iteration_path") or ""
            if not ipath:
                raw_fields = wi.get("fields")
                if raw_fields and isinstance(raw_fields, dict):
                    ipath = raw_fields.get("System.IterationPath") or ""
                else:
                    raw_s = wi.get("raw_json")
                    if raw_s and isinstance(raw_s, str):
                        try:
                            raw_data = json.loads(raw_s)
                            ipath = raw_data.get("fields", {}).get("System.IterationPath") or ""
                        except Exception:
                            pass
            if ipath:
                all_iter_paths.add(ipath)

        norm_iter_paths = {p.replace("\\", "/").strip("/"): p for p in all_iter_paths}
        parent_iter_paths = set()
        for np in norm_iter_paths:
            for other in norm_iter_paths:
                if other != np and other.startswith(np + "/"):
                    parent_iter_paths.add(np)
                    break

        shift_summary_map = {}
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
                    shift_summary_map[s_row["work_item_id"]] = {
                        "shift_count": s_row["shift_count"],
                        "total_delayed_weeks": s_row["total_delayed_weeks"] or 0,
                        "net_delta_weeks": s_row["net_delta_weeks"] or 0,
                        "last_shift_at": s_row["last_shift_at"] or ""
                    }
        except Exception as e:
            logger.debug(f"Could not query iteration shifts summary: {e}")

        deadline_field_setting = self._custom_deadline_field or ""

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
            raw_fields = wi.get("fields")
            raw_data = wi.get("raw_dict")
            if raw_fields is None or raw_data is None:
                raw_s = wi.get("raw_json")
                if raw_s and isinstance(raw_s, str):
                    try:
                        raw_data = json.loads(raw_s)
                        raw_fields = raw_data.get("fields", {})
                    except Exception:
                        raw_fields = {}
                        raw_data = {}
                else:
                    raw_fields = {}
                    raw_data = {}

            if not iter_path:
                iter_path = raw_fields.get("System.IterationPath") or ""

            target_date, _ = utils.extract_work_item_deadline(raw_fields, custom_field=deadline_field_setting)
            if not target_date:
                target_date = wi.get("target_date") or wi.get("finish_date") or wi.get("due_date") or ""

            raw_tags = raw_fields.get("System.Tags") or raw_fields.get("Tags") or wi.get("tags") or ""
            if isinstance(raw_tags, list):
                tag_list = [str(t).strip() for t in raw_tags if str(t).strip()]
                raw_tags = "; ".join(tag_list)
            else:
                tag_list = [t.strip() for t in re.split(r'[;,]', str(raw_tags)) if t.strip()]
            target_tags = utils.extract_target_milestone_tags(raw_tags)

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

            sprint_y, sprint_w, base_sprint_name = utils.parse_sprint_week(iter_name or iter_path)
            sprint_end_str = ""
            if sprint_y and sprint_w:
                _, _, _, sprint_end_str = utils.get_sprint_date_range(sprint_y, sprint_w)
                if not target_date:
                    target_date = sprint_end_str

            s_lower = state_val.lower()
            is_done = s_lower in ("closed", "done", "resolved", "completed", "removed", "cut")
            urgency = utils.calculate_deadline_urgency(target_date, is_completed=is_done)

            s_info = shift_summary_map.get(wi_id, {})
            s_count = s_info.get("shift_count", 0)
            d_weeks = s_info.get("total_delayed_weeks", 0)
            s_badge = ""
            if d_weeks > 0:
                s_badge = f"⚠️ Shifted +{d_weeks}w"
            elif s_count > 0:
                s_badge = f"🔄 Shifted ({s_count}x)"

            # Area Path & Team resolution
            area_path = raw_fields.get("System.AreaPath") or wi.get("area_path") or ""
            norm_ap = area_path.replace("\\", "/").strip("/") if area_path else ""
            ap_parts = [p for p in norm_ap.split("/") if p]
            team_name = ""
            if self._tfs_team_name:
                team_name = self._tfs_team_name
            elif len(ap_parts) > 1:
                team_name = ap_parts[-1]
            elif len(ip_parts) > 2:
                team_name = ip_parts[1]
            else:
                team_name = f"{tfs_proj} Team"

            sprint_leaf = (base_sprint_name or iter_name or "").strip()
            
            # Fast sprint URL construction
            if tfs_base and tfs_col and tfs_proj and team_name:
                encoded_team = urllib.parse.quote(team_name, safe="")
                has_sprint = (
                    sprint_leaf
                    and sprint_leaf.lower() not in ("unplanned", "none", "backlog", "default", "root", "current", "")
                    and sprint_leaf.lower() != tfs_proj.lower()
                )
                # Keep full project-prefixed iteration path parts
                full_ip_parts = ip_parts if (ip_parts and ip_parts[0].lower() == tfs_proj.lower()) else ([tfs_proj] + ip_parts if ip_parts else [])
                if has_sprint and full_ip_parts:
                    encoded_sprint_path = "/".join(urllib.parse.quote(p, safe="") for p in full_ip_parts)
                    tfs_sprint_url = f"{tfs_base}/{tfs_col}/{tfs_proj}/_sprints/taskboard/{encoded_team}/{encoded_sprint_path}?workitem={wi_id}"
                elif has_sprint and sprint_leaf:
                    tfs_sprint_url = f"{tfs_base}/{tfs_col}/{tfs_proj}/_sprints/taskboard/{encoded_team}/{urllib.parse.quote(tfs_proj, safe='')}/{urllib.parse.quote(sprint_leaf, safe='')}?workitem={wi_id}"
                else:
                    tfs_sprint_url = f"{tfs_base}/{tfs_col}/{tfs_proj}/_sprints/taskboard/{encoded_team}?workitem={wi_id}"
            else:
                tfs_sprint_url = ""

            wi_list.append({
                "id": wi_id,
                "title": wi.get("title") or f"Work Item #{wi_id}",
                "type": wi.get("type") or wi.get("WorkItemType") or "Task",
                "state": state_val,
                "assigned_to": assigned_val,
                "parent_id": parent_id,
                "tags": raw_tags,
                "tag_list": tag_list,
                "target_tags": target_tags,
                "changed_date": wi.get("changed_date") or "",
                "iteration_path": iter_path,
                "iteration_name": iter_name,
                "is_iteration_planned": is_planned,
                "sprint_week_name": base_sprint_name or (iter_name if is_planned else ""),
                "area_path": area_path,
                "team_name": team_name,
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
                "tfs_sprint_url": tfs_sprint_url,
                "linked_pr_count": len(linked_prs),
                "linked_prs": linked_prs[:10],
                "linked_repos": linked_repos[:8],
                "linked_repo_count": len(linked_repos),
            })

        # Resolve Backlog Hierarchy (Level 1-4), PBS Syntax Grouping, and Level 3 Prio 1 Priorities
        all_wis_map = {w["id"]: w for w in wi_list}
        for item in wi_list:
            h_info = utils.resolve_work_item_hierarchy(
                item, all_wis_map, bug_hierarchy_mode=self._bug_hierarchy_mode
            )
            item.update(h_info)

        sorted_wis = sorted(wi_list, key=lambda x: x["id"], reverse=True)
        self._enrich_work_items_with_milestones(items=sorted_wis, all_wis_map=all_wis_map)

        if worker:
            worker.report_progress(60, "Processing pull requests and links...")

        # 3. Pull Requests
        pr_tag_info_map = {}
        for rname_td, r_data in td_raw.get("all_repositories", {}).items():
            for p_td in r_data.get("all_prs", []):
                pr_tag_info_map[p_td["pr_id"]] = {
                    "is_tagged": p_td.get("is_tagged", False),
                    "tag_name": p_td.get("tag_name", ""),
                    "tag_type": p_td.get("tag_type", "")
                }

        pr_list = []
        repos_with_prs = set()
        for pr in all_prs_raw:
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

            title = pr.get("title") or ""
            description = raw_dict.get("description") or ""
            status = utils.normalize_pr_status(pr.get("status") or raw_dict.get("status") or "unknown")

            closed_date = pr.get("closed_date") or ""
            if not closed_date and raw_dict.get("closedDate"):
                closed_date = utils.UpdateDateString(raw_dict.get("closedDate"))

            creation_date = raw_dict.get("creationDate") or pr.get("creation_date") or ""
            created_date_clean = utils.UpdateDateString(creation_date) if creation_date else ""
            sort_time = closed_date if (status != "active" and closed_date) else (created_date_clean or closed_date)

            source_branch = (pr.get("source_branch") or raw_dict.get("sourceRefName") or "").replace("refs/heads/", "")
            target_branch = (pr.get("target_branch") or raw_dict.get("targetRefName") or "").replace("refs/heads/", "")

            created_by = pr.get("created_by") or ""
            if not created_by and isinstance(raw_dict.get("createdBy"), dict):
                created_by = raw_dict["createdBy"].get("displayName") or ""

            closed_by = pr.get("closed_by") or ""
            if not closed_by and isinstance(raw_dict.get("closedBy"), dict):
                closed_by = raw_dict["closedBy"].get("displayName") or ""

            web_url = f"{tfs_base}/{tfs_col}/{tfs_proj}/_git/{rname}/pullrequest/{pr_id}" if tfs_base else ""
            tasks = self._extract_pr_tasks(pr, work_items_map=all_wis_map)

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

        sorted_prs = sorted(pr_list, key=lambda x: (x.get("timestamp") or "", x.get("id") or 0), reverse=True)
        pr_repositories = sorted(list(repos_with_prs), key=lambda x: x.lower())

        if worker:
            worker.report_progress(80, "Building storage metrics and report timelines...")

        # 4. Storage / Artifacts Data
        import generate_artifacts_report
        artifacts = generate_artifacts_report.load_artifacts_data(self._cache_db)
        if artifacts:
            storage_metrics = generate_artifacts_report.calculate_metrics(artifacts)
            storage_data = {
                "total_builds": storage_metrics.get("total_builds", 0),
                "total_artifacts": storage_metrics.get("total_artifacts", 0),
                "active_artifacts_count": storage_metrics.get("active_artifacts_count", 0),
                "deleted_artifacts_count": storage_metrics.get("deleted_artifacts_count", 0),
                "total_size_gb": f"{storage_metrics.get('total_size_gb', 0.0):.2f}",
                "active_size_gb": f"{storage_metrics.get('active_size_gb', 0.0):.2f}",
                "deleted_size_gb": f"{storage_metrics.get('deleted_size_gb', 0.0):.2f}",
                "artifacts_list": artifacts[:100],
            }
        else:
            storage_data = {
                "total_builds": 0, "total_artifacts": 0,
                "active_artifacts_count": 0, "deleted_artifacts_count": 0,
                "total_size_gb": "0.00", "active_size_gb": "0.00", "deleted_size_gb": "0.00",
                "artifacts_list": []
            }

        # 5. Tag Day Structure
        timeline = td_raw.get("all_changes_timeline", [])
        repos_summary = []
        for rname, rinfo in sorted(repos_changed_map.items()):
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

            enriched_prs_after_tag = []
            for p in prs_after_tag:
                p_copy = dict(p)
                p_copy["tasks"] = self._extract_pr_tasks(p_copy, work_items_map=all_wis_map)
                enriched_prs_after_tag.append(p_copy)

            enriched_active_prs = []
            for p in active_prs:
                p_copy = dict(p)
                p_copy["tasks"] = self._extract_pr_tasks(p_copy, work_items_map=all_wis_map)
                enriched_active_prs.append(p_copy)

            enriched_all_prs = []
            for p in all_prs:
                p_copy = dict(p)
                p_copy["tasks"] = self._extract_pr_tasks(p_copy, work_items_map=all_wis_map)
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

        tagday_data = {
            "repos_analyzed": len(td_raw.get("all_repositories", {})),
            "repos_with_changes_count": len(repos_changed_map),
            "timeline_items_count": len(timeline),
            "timeline": timeline[:100],
            "repos_summary": repos_summary,
            "generated_at": td_raw.get("generated_at", ""),
        }

        # 6. Stats Summary
        last_sync_dt = self._cache_db.get_project_last_synced(devops_helper.AZURE_PROJECT_ID)
        pending_repos_count = sum(1 for r in sorted_repos if r.get("has_pending_changes"))
        prs_open_count = sum(1 for p in sorted_prs if p.get("status") == "active")
        prs_completed_count = sum(1 for p in sorted_prs if p.get("status") == "completed")
        prs_abandoned_count = sum(1 for p in sorted_prs if p.get("status") == "abandoned")

        stats = {
            "repos_count": len(sorted_repos),
            "pending_repos_count": pending_repos_count,
            "latest_stable_tag": global_latest_stable["tag"] if global_latest_stable else "-",
            "latest_stable_repo": global_latest_stable["repo"] if global_latest_stable else "",
            "latest_stable_date": global_latest_stable["date"] if global_latest_stable else "",
            "latest_unstable_tag": global_latest_unstable["tag"] if global_latest_unstable else "-",
            "latest_unstable_repo": global_latest_unstable["repo"] if global_latest_unstable else "",
            "latest_unstable_date": global_latest_unstable["date"] if global_latest_unstable else "",
            "work_items_count": len(sorted_wis),
            "active_work_items_count": active_wi_count,
            "closed_work_items_count": closed_wi_count,
            "deleted_work_items_count": deleted_count,
            "prs_count": len(sorted_prs),
            "prs_open_count": prs_open_count,
            "prs_completed_count": prs_completed_count,
            "prs_abandoned_count": prs_abandoned_count,
            "project_name": devops_helper.AZURE_PROJECT_ID or self._stats.get("project_name", "TFS Project"),
            "db_path": self._db_path or "tfs_cache.db",
            "last_synced_at": last_sync_dt.strftime("%Y-%m-%d %H:%M:%S") if last_sync_dt else "Never",
        }

        return {
            "repositories": sorted_repos,
            "work_items": sorted_wis,
            "work_items_map": all_wis_map,
            "pull_requests": sorted_prs,
            "pr_repositories": pr_repositories,
            "tagday_data": tagday_data,
            "storage_data": storage_data,
            "stats": stats,
            "shift_summary_map": shift_summary_map,
        }

    def _apply_computed_cache_data(self, data):
        """Applies pre-computed cache datasets and emits all changed signals on the main GUI thread."""
        if not data:
            return
        self._repositories = data.get("repositories", [])
        self._work_items = data.get("work_items", [])
        self._work_items_map = data.get("work_items_map", {w["id"]: w for w in self._work_items})
        self._pull_requests = data.get("pull_requests", [])
        self._pr_repositories = data.get("pr_repositories", [])
        self._tagday_data = data.get("tagday_data", {})
        self._storage_data = data.get("storage_data", {})
        self._shift_summary_map = data.get("shift_summary_map", {})
        if "stats" in data:
            self._stats = data["stats"]

        self.repositoriesChanged.emit()
        self.workItemsChanged.emit()
        self.pullRequestsChanged.emit()
        self.statsChanged.emit()
        self.tagDayDataChanged.emit()
        self.storageDataChanged.emit()
        self.iterationShiftsChanged.emit()
        self.workloadMatrixChanged.emit()

    @Slot()
    def startup_load_async(self):
        """Deferred startup: loads all local cache data in a background thread after the GUI is shown."""
        logger.info("Starting initial data load from local cache...")

        def _work(worker):
            worker.log_message.emit("Loading and analyzing database cache in background...")
            data = self._compute_all_cache_data(worker=worker)
            worker.log_message.emit("Local database cache loaded successfully")
            return data

        self._run_worker(_work, "Loading local cache...")

    @Slot()
    def refresh_all_data(self):
        """Loads all data from local SQLite database."""
        if not self._cache_db:
            return

        self._is_pr_titles_patched = False
        try:
            data = self._compute_all_cache_data()
            self._apply_computed_cache_data(data)
        except Exception as e:
            logger.error(f"Error refreshing cache data: {e}", exc_info=True)
            self.logMessage.emit(f"Error loading database: {e}")

    # Async Operations
    @Slot()
    def sync_work_items_async(self):
        """Triggers direct TFS API WIQL sync for work items with real-time progress logging."""
        if self._is_busy:
            return

        def _work(worker):
            worker.log_message.emit("Connecting to TFS API...")
            azHandler = devops_helper._getHandler()
            if not azHandler:
                raise RuntimeError("Failed to create Azure/TFS client. Check .env variables.")

            def _progress_cb(msg, current=0, total=0):
                worker.log_message.emit(msg)
                if total > 0:
                    worker.report_progress(int((current / total) * 100), msg)

            summary = azHandler.sync_work_items(
                self._cache_db,
                project_id=devops_helper.AZURE_PROJECT_ID,
                progress_callback=_progress_cb
            )
            return summary

        self._run_worker(_work, "Syncing work items...")

    @Slot()
    def sync_pull_requests_async(self):
        """Directly reconciles pull request statuses with TFS API (updates closed/abandoned PRs)."""
        if self._is_busy:
            return

        def _work(worker):
            worker.log_message.emit("Connecting to TFS API for Pull Request reconciliation...")
            azHandler = devops_helper._getHandler()
            if not azHandler:
                raise RuntimeError("Failed to create Azure/TFS client. Check .env variables.")

            worker.log_message.emit("Reconciling active and new pull requests with TFS...")

            def _progress_cb(pct_or_msg, msg=""):
                if isinstance(pct_or_msg, int):
                    worker.report_progress(pct_or_msg, msg)
                    if msg:
                        worker.log_message.emit(msg)
                else:
                    worker.log_message.emit(str(pct_or_msg))

            summary = azHandler.sync_pull_requests(
                self._cache_db,
                project_id=devops_helper.AZURE_PROJECT_ID,
                progress_callback=_progress_cb,
                cancel_token=worker.is_cancelled
            )
            tags_synced = summary.get('tags_synced', 0)
            tag_msg = f", {tags_synced} tag references updated" if tags_synced > 0 else ""
            worker.log_message.emit(
                f"PR sync complete: {summary.get('synced', 0)} verified, "
                f"{summary.get('updated', 0)} status updated, {summary.get('new', 0)} new{tag_msg}, {summary.get('errors', 0)} errors"
            )
            return summary

        self._run_worker(_work, "Syncing pull requests...")

    @Slot()
    def sync_all_async(self):
        """Triggers full sync of repos, work items, and pull requests with live progress reporting."""
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

            def _progress_cb(pct_or_msg, msg=""):
                if isinstance(pct_or_msg, int):
                    worker.report_progress(pct_or_msg, msg)
                    if msg:
                        worker.log_message.emit(msg)
                else:
                    worker.log_message.emit(str(pct_or_msg))

            devops_helper.sync(
                force_sync=True,
                progress_callback=_progress_cb,
                cancel_token=worker.is_cancelled
            )
            return "Full synchronization finished successfully"

        self._run_worker(_work, "Running full sync...")

    @Slot()
    def load_interactive_reports(self, td_raw=None):
        """Loads and parses interactive report metrics and timelines directly from the SQLite database."""
        if not self._cache_db:
            return

        try:
            # 1. Tag Day Interactive Data
            if td_raw is None:
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
            self.iterationShiftsChanged.emit()

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
            if not success:
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
            self.logMessage.emit(f"File does not exist: {path}. Please click 'Generate Release Notes' first.")

    @Slot()
    def open_revision_docx(self):
        """Opens REVISION.docx in Microsoft Word or default viewer."""
        md_path = os.path.join(devops_helper.BASE_FOLDER, devops_helper.REVISION_FILE_MD)
        docx_path = os.path.splitext(md_path)[0] + ".docx"
        if os.path.exists(docx_path):
            self.open_path_in_explorer(docx_path)
        else:
            self.logMessage.emit(f"File does not exist: {docx_path}. Please click 'Generate Release Notes' first.")


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
    @Slot(int, str, str, bool, bool, bool, str, int, str, bool, result="QVariantMap")
    @Slot(int, str, str, bool, bool, bool, str, int, str, result="QVariantMap")
    @Slot(result="QVariantMap")
    def getCurrentDateInfo(self):
        """
        Returns current calendar date, ISO week, and formatted sprint name metadata.
        """
        today_obj = date.today()
        curr_y, curr_w, curr_wd = today_obj.isocalendar()
        curr_date_str = today_obj.strftime("%Y-%m-%d")
        curr_date_label = today_obj.strftime("%a, %b %d, %Y")
        curr_date_full = today_obj.strftime("%A, %B %d, %Y")
        curr_sprint_name = f"week-{str(curr_y)[-2:]}{curr_w:02d}"
        curr_sprint_label = utils.format_sprint_range_label(curr_y, curr_w)
        return {
            "current_date": curr_date_str,
            "current_date_label": curr_date_label,
            "current_date_full": curr_date_full,
            "current_year": curr_y,
            "current_week": curr_w,
            "current_weekday": curr_wd,
            "current_sprint_name": curr_sprint_name,
            "current_sprint_label": curr_sprint_label,
        }

    @Slot(int, str, str, bool, bool, bool, str, int, str, bool, result="QVariantMap")
    @Slot(int, str, str, bool, bool, bool, str, int, str, result="QVariantMap")
    @Slot(int, str, str, bool, bool, bool, str, int, result="QVariantMap")
    @Slot(int, str, str, bool, bool, bool, str, result="QVariantMap")
    @Slot(int, str, str, bool, bool, bool, result="QVariantMap")
    @Slot(int, str, str, bool, bool, result="QVariantMap")
    @Slot(int, str, str, result="QVariantMap")
    @Slot(int, str, result="QVariantMap")
    @Slot(int, result="QVariantMap")
    @Slot(result="QVariantMap")
    def getWorkloadMatrix(
        self,
        horizon_weeks: int = 4,
        filter_level1: str = "ALL",
        filter_level2: str = "ALL",
        prio1_only: bool = False,
        grouped_only: bool = False,
        hide_closed: bool = False,
        search_query: str = "",
        lookback_weeks: int = 0,
        filter_milestone: str = "ALL",
        overdue_only: bool = False,
    ):
        """
        Computes the interactive capacity and workload matrix for team members across
        the given horizon of weekly iterations (4, 8, or 12 weeks), filtered by
        Level 1, Level 2, priority, grouping, completion status, search query, or milestone.
        lookback_weeks > 0 shifts the window into the past so historic sprints are shown.
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

        if self._cache_db:
            try:
                cached_iters = self._cache_db.get_cached_iterations(project=self.selectedProject)
                for ci in cached_iters:
                    cname = ci.get("iteration_name")
                    if cname:
                        y, w, b_name = utils.parse_sprint_week(cname)
                        if y and w and b_name:
                            sprint_keys.add((y, w, b_name))
            except Exception:
                pass

        if not sprint_keys:
            adv = utils.generate_weekly_iterations_advance(weeks_count=horizon_weeks)
            for it in adv:
                sprint_keys.add((it["year"], it["week"], it["sprint_name"]))

        # Sort sprints chronologically ascending
        sorted_sprints = sorted(list(sprint_keys), key=lambda x: (x[0], x[1]))

        # Select the window: take last horizon_weeks sprints, then shift left by lookback_weeks
        if horizon_weeks <= 0:
            horizon_weeks = 4
        lookback_weeks = max(0, int(lookback_weeks or 0))
        end_idx = len(sorted_sprints) - lookback_weeks
        start_idx = max(0, end_idx - horizon_weeks)
        end_idx = max(start_idx, end_idx)  # guard
        target_sprints = sorted_sprints[start_idx:end_idx]

        # Current date and ISO week determination
        today_obj = date.today()
        curr_y, curr_w, curr_wd = today_obj.isocalendar()
        curr_date_str = today_obj.strftime("%Y-%m-%d")
        curr_date_label = today_obj.strftime("%a, %b %d, %Y")
        curr_date_full = today_obj.strftime("%A, %B %d, %Y")
        curr_sprint_name = f"week-{str(curr_y)[-2:]}{curr_w:02d}"
        curr_sprint_label = utils.format_sprint_range_label(curr_y, curr_w)

        # Load configured milestones for sprint header and work item alignment
        all_milestones = self.get_milestones()
        milestones_by_date = {m.get("target_date"): m for m in all_milestones if m.get("target_date")}

        sprint_columns = []
        for y, w, s_name in target_sprints:
            s_d, e_d, start_str, end_str = utils.get_sprint_date_range(y, w)
            lbl = utils.format_sprint_range_label(y, w)
            is_cur = (y, w) == (curr_y, curr_w)
            is_past = (y, w) < (curr_y, curr_w)
            is_future = (y, w) > (curr_y, curr_w)
            day_prog = round(min(1.0, max(0.0, curr_wd / 5.0)), 2) if is_cur else (1.0 if is_past else 0.0)

            col_milestones = []
            for m in all_milestones:
                m_start = (m.get("target_date") or m.get("start_date") or "").split("T")[0].split(" ")[0].strip()
                m_end = (m.get("end_date") or m_start).split("T")[0].split(" ")[0].strip()
                in_col = False
                if start_str and end_str and m_start and m_end:
                    if m_start <= end_str and m_end >= start_str:
                        in_col = True
                if not in_col and m_start:
                    try:
                        s_obj = datetime.strptime(m_start, "%Y-%m-%d").date()
                        sy, sw, _ = s_obj.isocalendar()
                        e_obj = datetime.strptime(m_end, "%Y-%m-%d").date()
                        ey, ew, _ = e_obj.isocalendar()
                        if (sy, sw) <= (y, w) <= (ey, ew):
                            in_col = True
                    except Exception:
                        pass
                if not in_col and m_start:
                    sy, sw, _ = utils.parse_sprint_week(m_start)
                    ey, ew, _ = utils.parse_sprint_week(m_end)
                    if sy and ey and (sy, sw) <= (y, w) <= (ey, ew):
                        in_col = True
                    elif sy and (sy, sw) == (y, w):
                        in_col = True
                if in_col:
                    col_milestones.append(m)

            sprint_columns.append({
                "sprint_name": s_name,
                "label": lbl,
                "short_label": f"W{w:02d}",
                "start_date": start_str,
                "end_date": end_str,
                "year": y,
                "week": w,
                "is_current": is_cur,
                "is_past": is_past,
                "is_future": is_future,
                "day_progress": day_prog,
                "milestones": col_milestones,
                "milestone_count": len(col_milestones),
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
        total_tasks_not_started = 0
        total_tasks_active = 0
        total_tasks_closed = 0
        total_not_started = 0
        total_active = 0
        total_completed = 0

        f_l1_raw = (filter_level1 or "ALL").strip()
        f_l2_raw = (filter_level2 or "ALL").strip()
        f_m_raw = (filter_milestone or "ALL").strip()
        sq_raw = (search_query or "").strip().lower()

        for wi in self._work_items:
            if wi.get("deleted"):
                continue
            wi_sprint = wi.get("sprint_week_name")
            if not wi_sprint:
                _, _, wi_sprint = utils.parse_sprint_week(wi.get("iteration_name") or wi.get("iteration_path") or "")

            if not wi_sprint or wi_sprint not in target_sprint_names:
                continue

            t_lower = (wi.get("type") or "").lower()
            is_story = t_lower in ("requirement", "user story", "story", "product backlog item")
            is_bug = t_lower in ("bug", "defect", "problem")
            is_task = t_lower in ("task",)
            is_done = wi.get("state", "").lower() in ("closed", "done", "resolved", "completed", "cut")
            wi_urgency = wi.get("urgency_status")
            if not wi_urgency:
                deadline_val = wi.get("deadline_str") or wi.get("target_date")
                urg_calc = utils.calculate_deadline_urgency(deadline_val, is_done)
                wi_urgency = urg_calc.get("status")
            is_overdue = (wi_urgency == "overdue")

            # --- Filter Criteria Evaluation ---
            # 0. Overdue Deadlines Filter
            if overdue_only and not is_overdue:
                continue
            # 1. Level 1 Filter (Exact, Substring, or Ungrouped / Without [<NR>] Syntax)
            if f_l1_raw and f_l1_raw.upper() != "ALL":
                f1_upper = f_l1_raw.upper()
                if (
                    f1_upper in ("UNGROUPED", "[ UNGROUPED ]", "WITHOUT [<NR>] SYNTAX", "[ WITHOUT [<NR>] SYNTAX ]", "NO_PBS", "WITHOUT_SYNTAX", "NO PBS", "!PBS", "NO [<NR>]", "!SYNTAX", "NON_PBS")
                    or "WITHOUT" in f1_upper
                    or "NO PBS" in f1_upper
                    or "NO_PBS" in f1_upper
                    or "!PBS" in f1_upper
                    or "UNGROUPED" in f1_upper
                ):
                    if wi.get("level1_pbs"):
                        continue
                else:
                    l1_target = f_l1_raw.lower()
                    l1_disp = (wi.get("level1_display") or "").lower()
                    l1_title = (wi.get("level1_title") or "").lower()
                    l1_pbs = (wi.get("level1_pbs") or "").lower()
                    l1_name = (wi.get("level1_name") or "").lower()
                    if (l1_target not in l1_disp) and (l1_target not in l1_title) and (l1_target not in l1_pbs) and (l1_target not in l1_name):
                        continue

            # 2. Level 2 Filter (Exact, Substring, or Ungrouped / Without [<NR>] Syntax)
            if f_l2_raw and f_l2_raw.upper() != "ALL":
                f2_upper = f_l2_raw.upper()
                if (
                    f2_upper in ("UNGROUPED", "[ UNGROUPED ]", "WITHOUT [<NR>] SYNTAX", "[ WITHOUT [<NR>] SYNTAX ]", "NO_PBS", "WITHOUT_SYNTAX", "NO PBS", "!PBS", "NO [<NR>]", "!SYNTAX", "NON_PBS")
                    or "WITHOUT" in f2_upper
                    or "NO PBS" in f2_upper
                    or "NO_PBS" in f2_upper
                    or "!PBS" in f2_upper
                    or "UNGROUPED" in f2_upper
                ):
                    if wi.get("level2_pbs"):
                        continue
                else:
                    l2_target = f_l2_raw.lower()
                    l2_disp = (wi.get("level2_display") or "").lower()
                    l2_title = (wi.get("level2_title") or "").lower()
                    l2_pbs = (wi.get("level2_pbs") or "").lower()
                    l2_name = (wi.get("level2_name") or "").lower()
                    if (l2_target not in l2_disp) and (l2_target not in l2_title) and (l2_target not in l2_pbs) and (l2_target not in l2_name):
                        continue

            # 3. Prio 1 Focus Filter
            if prio1_only and not wi.get("is_prio1"):
                continue

            # 4. PBS Grouped Only Filter
            if grouped_only and not wi.get("is_grouped"):
                continue

            # 5. Hide Closed Tasks Filter
            if hide_closed and is_done:
                continue

            matched_m = utils.match_work_item_to_milestone(wi, all_milestones, milestones_by_date)
            has_ms = bool(wi.get("has_milestone") or matched_m)
            m_name = (wi.get("milestone_name") or wi.get("effective_milestone_name") or (matched_m.get("name") if matched_m else "")).strip()
            m_cat = (wi.get("milestone_category") or (matched_m.get("category_name") if matched_m else "")).strip()

            # 6. Milestone Filter
            if f_m_raw and f_m_raw.upper() != "ALL":
                f_m_upper = f_m_raw.upper()
                if f_m_upper in ("PLANNED", "WITH_MILESTONE", "HAS_MILESTONE"):
                    if not has_ms:
                        continue
                elif f_m_upper in ("UNPLANNED", "NO_MILESTONE", "WITHOUT_MILESTONE"):
                    if has_ms:
                        continue
                else:
                    target_m = f_m_raw.lower()
                    target_tags_lower = [t.lower() for t in (wi.get("target_tags") or [])]
                    raw_tags_lower = (wi.get("tags") or "").lower()
                    matches_m = (
                        (target_m in m_name.lower())
                        or (target_m in m_cat.lower())
                        or any(target_m in tt for tt in target_tags_lower)
                        or (f"target:{target_m}" in raw_tags_lower)
                        or (target_m in raw_tags_lower)
                    )
                    if not matches_m:
                        continue

            assignee = (wi.get("assigned_to") or "Unassigned").strip()

            # 7. Search Query Filter
            if sq_raw:
                stext = wi.get("_search_text")
                if stext is not None:
                    matches_search = sq_raw in stext
                else:
                    matches_search = (
                        sq_raw in assignee.lower()
                        or sq_raw in (wi.get("title") or "").lower()
                        or sq_raw in str(wi.get("id") or "")
                        or sq_raw in (wi.get("type") or "").lower()
                        or sq_raw in (wi.get("prio_tag") or "").lower()
                        or sq_raw in (wi.get("tags") or "").lower()
                        or sq_raw in m_name.lower()
                        or sq_raw in m_cat.lower()
                    )
                if not matches_search:
                    continue

            def _categorize_state(st_str):
                s = (st_str or "").lower().strip()
                if s in ("closed", "done", "resolved", "completed", "cut", "removed"):
                    return "closed"
                elif s in ("active", "in progress", "in_progress", "doing", "committed", "in development", "in review", "investigating", "testing"):
                    return "active"
                else:
                    return "not_started"

            state_cat = _categorize_state(wi.get("state"))

            if assignee not in assignees_data:
                assignees_data[assignee] = {s_name: [] for s_name in target_sprint_names}
                assignee_stats[assignee] = {
                    "total": 0, "stories": 0, "bugs": 0, "tasks": 0, "overdue": 0, "completed": 0,
                    "tasks_not_started": 0, "tasks_active": 0, "tasks_closed": 0,
                    "total_not_started": 0, "total_active": 0, "total_closed": 0
                }

            item_info = {
                "id": wi.get("id"),
                "title": wi.get("title") or f"#{wi.get('id')}",
                "type": wi.get("type") or "Task",
                "state": wi.get("state") or "Active",
                "state_category": state_cat,
                "assigned_to": assignee,
                "parent_id": wi.get("parent_id"),
                "sprint_name": wi_sprint,
                "deadline_str": wi.get("deadline_str") or wi.get("target_date") or "",
                "milestone_name": matched_m.get("name", "") if matched_m else "",
                "milestone_icon": matched_m.get("category_icon", "") if matched_m else "",
                "milestone_color": matched_m.get("category_color", "") if matched_m else "",
                "milestone_bg": matched_m.get("category_bg_color", "") if matched_m else "",
                "milestone_category": matched_m.get("category_name", "") if matched_m else "",
                "tags": wi.get("tags", ""),
                "tag_list": wi.get("tag_list", []),
                "target_tags": wi.get("target_tags", []),
                "urgency_status": wi.get("urgency_status", "none"),
                "urgency_badge": wi.get("urgency_badge", "—"),
                "urgency_color": wi.get("urgency_color", "#8b949e"),
                "tfs_url": wi.get("tfs_url", ""),
                "iteration_path": wi.get("iteration_path", ""),
                "shift_count": wi.get("shift_count", 0),
                "total_delayed_weeks": wi.get("total_delayed_weeks", 0),
                "shift_badge": wi.get("shift_badge", ""),
                "level": wi.get("level", 4),
                "level1_id": wi.get("level1_id"),
                "level1_title": wi.get("level1_title", ""),
                "level1_pbs": wi.get("level1_pbs", ""),
                "level1_name": wi.get("level1_name", ""),
                "level1_display": wi.get("level1_display", ""),
                "level2_id": wi.get("level2_id"),
                "level2_title": wi.get("level2_title", ""),
                "level2_pbs": wi.get("level2_pbs", ""),
                "level2_name": wi.get("level2_name", ""),
                "level2_display": wi.get("level2_display", ""),
                "is_grouped": wi.get("is_grouped", False),
                "grouping_status": wi.get("grouping_status", "ungrouped"),
                "is_prio1": wi.get("is_prio1", False),
                "prio_category": wi.get("prio_category", "standard"),
                "prio_type": wi.get("prio_type", ""),
                "prio_number": wi.get("prio_number", ""),
                "prio_tag": wi.get("prio_tag", ""),
                "prio_badge": wi.get("prio_badge", ""),
                "is_done": is_done,
                "is_story": is_story,
                "is_bug": is_bug,
                "is_task": is_task,
            }

            assignees_data[assignee][wi_sprint].append(item_info)

            # Update stats
            st = assignee_stats[assignee]
            st["total"] += 1
            if is_story:
                st["stories"] += 1
            elif is_bug:
                st["bugs"] += 1
            elif is_task:
                st["tasks"] += 1
                if state_cat == "not_started":
                    st["tasks_not_started"] += 1
                elif state_cat == "active":
                    st["tasks_active"] += 1
                elif state_cat == "closed":
                    st["tasks_closed"] += 1

            if state_cat == "not_started":
                st["total_not_started"] += 1
            elif state_cat == "active":
                st["total_active"] += 1
            elif state_cat == "closed":
                st["total_closed"] += 1

            if is_overdue:
                st["overdue"] += 1
            if is_done:
                st["completed"] += 1

            total_matrix_items += 1
            if is_story:
                total_matrix_stories += 1
            elif is_bug:
                total_matrix_bugs += 1
            elif is_task:
                total_matrix_tasks += 1
                if state_cat == "not_started":
                    total_tasks_not_started += 1
                elif state_cat == "active":
                    total_tasks_active += 1
                elif state_cat == "closed":
                    total_tasks_closed += 1

            if state_cat == "not_started":
                total_not_started += 1
            elif state_cat == "active":
                total_active += 1
            elif state_cat == "closed":
                total_completed += 1

            if is_overdue:
                total_matrix_overdue += 1

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

                tk_not_started = sum(1 for it in items if it["is_task"] and it.get("state_category") == "not_started")
                tk_active = sum(1 for it in items if it["is_task"] and it.get("state_category") == "active")
                tk_closed = sum(1 for it in items if it["is_task"] and it.get("state_category") == "closed")

                all_not_started = sum(1 for it in items if it.get("state_category") == "not_started")
                all_active = sum(1 for it in items if it.get("state_category") == "active")

                # Group items by parent containers
                grouped = self._group_items_into_containers(
                    items, all_wis_by_id, bug_mode=self._bug_hierarchy_mode,
                    milestones_by_date=milestones_by_date, all_milestones=all_milestones
                )

                tk_closed_percent = round((tk_closed / max(1, tk_count)) * 100) if tk_count > 0 else 0

                cells.append({
                    "assignee": assignee,
                    "sprint_name": s_name,
                    "is_current": col.get("is_current", False),
                    "is_past": col.get("is_past", False),
                    "is_future": col.get("is_future", False),
                    "total_count": len(items),
                    "stories_count": st_count,
                    "bugs_count": bg_count,
                    "tasks_count": tk_count,
                    "tasks_not_started_count": tk_not_started,
                    "tasks_active_count": tk_active,
                    "tasks_closed_count": tk_closed,
                    "tasks_closed_percent": tk_closed_percent,
                    "not_started_count": all_not_started,
                    "active_count": all_active,
                    "overdue_count": od_count,
                    "completed_count": cp_count,
                    "items": sorted(items, key=lambda x: x["id"], reverse=True),
                    "grouped_containers": grouped,
                    "container_count": len(grouped),
                })

            parts = [p for p in assignee.replace(".", " ").replace("_", " ").split() if p]
            initials = "".join([p[0].upper() for p in parts[:2]]) if parts else "U"

            st = assignee_stats[assignee]
            st["tasks_closed_percent"] = round((st["tasks_closed"] / max(1, st["tasks"])) * 100) if st["tasks"] > 0 else 0

            assignee_rows.append({
                "assignee": assignee,
                "initials": initials,
                "stats": st,
                "cells": cells,
            })

        column_totals = []
        for col in sprint_columns:
            s_name = col["sprint_name"]
            c_items = []
            for a_name, s_map in assignees_data.items():
                c_items.extend(s_map.get(s_name, []))
            c_tk_count = sum(1 for it in c_items if it["is_task"])
            c_tk_closed = sum(1 for it in c_items if it["is_task"] and it.get("state_category") == "closed")
            c_tk_closed_pct = round((c_tk_closed / max(1, c_tk_count)) * 100) if c_tk_count > 0 else 0
            column_totals.append({
                "sprint_name": s_name,
                "is_current": col.get("is_current", False),
                "is_past": col.get("is_past", False),
                "is_future": col.get("is_future", False),
                "total_count": len(c_items),
                "stories_count": sum(1 for it in c_items if it["is_story"]),
                "bugs_count": sum(1 for it in c_items if it["is_bug"]),
                "tasks_count": c_tk_count,
                "tasks_not_started_count": sum(1 for it in c_items if it["is_task"] and it.get("state_category") == "not_started"),
                "tasks_active_count": sum(1 for it in c_items if it["is_task"] and it.get("state_category") == "active"),
                "tasks_closed_count": c_tk_closed,
                "tasks_closed_percent": c_tk_closed_pct,
                "not_started_count": sum(1 for it in c_items if it.get("state_category") == "not_started"),
                "active_count": sum(1 for it in c_items if it.get("state_category") == "active"),
                "overdue_count": sum(1 for it in c_items if it["urgency_status"] == "overdue"),
                "completed_count": sum(1 for it in c_items if it["is_done"]),
            })

        total_tasks_closed_pct = round((total_tasks_closed / max(1, total_matrix_tasks)) * 100) if total_matrix_tasks > 0 else 0

        current_sprint_idx = -1
        for idx, col in enumerate(sprint_columns):
            if col.get("is_current"):
                current_sprint_idx = idx
                break

        return {
            "horizon_weeks": horizon_weeks,
            "sprint_columns": sprint_columns,
            "column_totals": column_totals,
            "assignee_rows": assignee_rows,
            "current_date": curr_date_str,
            "current_date_label": curr_date_label,
            "current_date_full": curr_date_full,
            "current_year": curr_y,
            "current_week": curr_w,
            "current_weekday": curr_wd,
            "current_sprint_name": curr_sprint_name,
            "current_sprint_label": curr_sprint_label,
            "has_current_sprint_in_view": (current_sprint_idx >= 0),
            "current_sprint_index": current_sprint_idx,
            "total_items": total_matrix_items,
            "total_stories": total_matrix_stories,
            "total_bugs": total_matrix_bugs,
            "total_tasks": total_matrix_tasks,
            "total_tasks_not_started": total_tasks_not_started,
            "total_tasks_active": total_tasks_active,
            "total_tasks_closed": total_tasks_closed,
            "total_tasks_closed_percent": total_tasks_closed_pct,
            "total_not_started": total_not_started,
            "total_active": total_active,
            "total_completed": total_completed,
            "total_overdue": total_matrix_overdue,
            "assignees_count": len(assignee_rows),
            "bug_hierarchy_mode": self._bug_hierarchy_mode,
            "lookback_weeks": lookback_weeks,
        }

    def _group_items_into_containers(self, items_in_cell, all_wis_by_id, bug_mode="like_user_story", milestones_by_date=None, all_milestones=None):
        """
        Groups work items in a sprint cell by parent container.
        - If bug_mode == 'like_user_story': Bugs are top-level containers that can contain tasks.
        - If bug_mode == 'like_task': Bugs are child tasks grouped under parent User Stories / Requirements.
        """
        story_types = {"requirement", "user story", "story", "product backlog item", "feature", "epic"}
        done_states = {"closed", "done", "resolved", "completed", "cut"}
        m_map = milestones_by_date or {}

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
            matched_c_m = utils.match_work_item_to_milestone(c, all_milestones, m_map)
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
                "milestone_name": matched_c_m.get("name", "") if matched_c_m else "",
                "milestone_icon": matched_c_m.get("category_icon", "") if matched_c_m else "",
                "milestone_color": matched_c_m.get("category_color", "") if matched_c_m else "",
                "milestone_bg": matched_c_m.get("category_bg_color", "") if matched_c_m else "",
                "milestone_category": matched_c_m.get("category_name", "") if matched_c_m else "",
                "urgency_status": c.get("urgency_status", "none"),
                "urgency_badge": c.get("urgency_badge", "—"),
                "urgency_color": c.get("urgency_color", "#8b949e"),
                "iteration_path": c.get("iteration_path", ""),
                "is_done": c_done,
                "shift_count": c.get("shift_count", 0),
                "total_delayed_weeks": c.get("total_delayed_weeks", 0),
                "shift_badge": c.get("shift_badge", ""),
                "level": c.get("level", 3),
                "level1_id": c.get("level1_id"),
                "level1_title": c.get("level1_title", ""),
                "level1_pbs": c.get("level1_pbs", ""),
                "level1_name": c.get("level1_name", ""),
                "level1_display": c.get("level1_display", ""),
                "level2_id": c.get("level2_id"),
                "level2_title": c.get("level2_title", ""),
                "level2_pbs": c.get("level2_pbs", ""),
                "level2_name": c.get("level2_name", ""),
                "level2_display": c.get("level2_display", ""),
                "is_grouped": c.get("is_grouped", False),
                "grouping_status": c.get("grouping_status", "ungrouped"),
                "is_prio1": c.get("is_prio1", False),
                "prio_category": c.get("prio_category", "standard"),
                "prio_type": c.get("prio_type", ""),
                "prio_number": c.get("prio_number", ""),
                "prio_tag": c.get("prio_tag", ""),
                "prio_badge": c.get("prio_badge", ""),
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

                # Ensure hierarchy info on parent
                if "level1_display" not in p_wi:
                    p_h = utils.resolve_work_item_hierarchy(p_wi, all_wis_by_id, bug_hierarchy_mode=bug_mode)
                    p_wi.update(p_h)

                if pid not in container_map:
                    p_done = _is_item_done(p_wi)
                    matched_p_m = utils.match_work_item_to_milestone(p_wi, all_milestones, m_map)
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
                        "milestone_name": matched_p_m.get("name", "") if matched_p_m else "",
                        "milestone_icon": matched_p_m.get("category_icon", "") if matched_p_m else "",
                        "milestone_color": matched_p_m.get("category_color", "") if matched_p_m else "",
                        "milestone_bg": matched_p_m.get("category_bg_color", "") if matched_p_m else "",
                        "milestone_category": matched_p_m.get("category_name", "") if matched_p_m else "",
                        "urgency_status": p_wi.get("urgency_status", "none"),
                        "urgency_badge": p_wi.get("urgency_badge", "—"),
                        "urgency_color": p_wi.get("urgency_color", "#8b949e"),
                        "iteration_path": p_wi.get("iteration_path", ""),
                        "is_done": p_done,
                        "shift_count": p_wi.get("shift_count", 0),
                        "total_delayed_weeks": p_wi.get("total_delayed_weeks", 0),
                        "shift_badge": p_wi.get("shift_badge", ""),
                        "level": p_wi.get("level", 3),
                        "level1_id": p_wi.get("level1_id"),
                        "level1_title": p_wi.get("level1_title", ""),
                        "level1_pbs": p_wi.get("level1_pbs", ""),
                        "level1_name": p_wi.get("level1_name", ""),
                        "level1_display": p_wi.get("level1_display", ""),
                        "level2_id": p_wi.get("level2_id"),
                        "level2_title": p_wi.get("level2_title", ""),
                        "level2_pbs": p_wi.get("level2_pbs", ""),
                        "level2_name": p_wi.get("level2_name", ""),
                        "level2_display": p_wi.get("level2_display", ""),
                        "is_grouped": p_wi.get("is_grouped", False),
                        "grouping_status": p_wi.get("grouping_status", "ungrouped"),
                        "is_prio1": p_wi.get("is_prio1", False),
                        "prio_category": p_wi.get("prio_category", "standard"),
                        "prio_type": p_wi.get("prio_type", ""),
                        "prio_number": p_wi.get("prio_number", ""),
                        "prio_tag": p_wi.get("prio_tag", ""),
                        "prio_badge": p_wi.get("prio_badge", ""),
                        "tasks": [],
                    }
                container_map[pid]["tasks"].append(ch)
            else:
                unparented_children.append(ch)

        def _get_state_category(st_str):
            s = (st_str or "").lower().strip()
            if s in ("closed", "done", "resolved", "completed", "cut", "removed"):
                return "closed"
            elif s in ("active", "in progress", "in_progress", "doing", "committed", "in development", "in review", "investigating", "testing"):
                return "active"
            else:
                return "not_started"

        containers_list = []
        for cid, c_obj in container_map.items():
            tsks = c_obj["tasks"]
            tot = len(tsks)
            comp = sum(1 for t in tsks if _is_item_done(t))
            pct = round((comp / tot * 100)) if tot > 0 else (100 if c_obj["is_done"] else 0)
            c_obj["total_tasks_count"] = tot
            c_obj["completed_tasks_count"] = comp
            c_obj["tasks_not_started_count"] = sum(1 for t in tsks if _get_state_category(t.get("state")) == "not_started")
            c_obj["tasks_active_count"] = sum(1 for t in tsks if _get_state_category(t.get("state")) == "active")
            c_obj["tasks_closed_count"] = comp
            c_obj["state_category"] = _get_state_category(c_obj.get("state"))
            c_obj["progress_percent"] = pct
            c_obj["progress_pct"] = pct
            containers_list.append(c_obj)

        # Prioritize complying [<NR>] <Name> containers first, then Prio 1 focus items, then cell parents, then ID
        containers_list.sort(key=lambda x: (
            0 if x.get("is_grouped") else 1,
            0 if x.get("is_prio1") else 1,
            not x.get("is_parent_in_cell", False),
            -x.get("id", 0)
        ))

        if unparented_children:
            tot_un = len(unparented_children)
            comp_un = sum(1 for t in unparented_children if _is_item_done(t))
            pct_un = round((comp_un / tot_un * 100)) if tot_un > 0 else 0
            un_not_started = sum(1 for t in unparented_children if _get_state_category(t.get("state")) == "not_started")
            un_active = sum(1 for t in unparented_children if _get_state_category(t.get("state")) == "active")

            containers_list.append({
                "id": 0,
                "title": "Direct Tasks / Standalone Items",
                "type": "Standalone",
                "state": "Active",
                "state_category": "active",
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
                "total_tasks_count": tot_un,
                "completed_tasks_count": comp_un,
                "tasks_not_started_count": un_not_started,
                "tasks_active_count": un_active,
                "tasks_closed_count": comp_un,
                "progress_percent": pct_un,
                "progress_pct": pct_un,
                "shift_badge": "",
                "level": 4,
                "level1_id": None,
                "level1_title": "",
                "level1_pbs": "",
                "level1_name": "",
                "level1_display": "Ungrouped Sub-System",
                "level2_id": None,
                "level2_title": "",
                "level2_pbs": "",
                "level2_name": "",
                "level2_display": "Ungrouped Component",
                "is_grouped": False,
                "grouping_status": "ungrouped",
                "is_prio1": False,
                "prio_category": "standard",
                "prio_type": "",
                "prio_number": "",
                "prio_tag": "",
                "prio_badge": "",
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
            clean_sprint = (sprint_name or "").strip()
            if (not clean_sprint or clean_sprint.lower() == "latest") and self.availableSprintList:
                clean_sprint = self.availableSprintList[0]
            work_items = self._work_items if self._work_items else None
            return generate_sprint_report.generate_sprint_report_data(
                self._cache_db, sprint_name=clean_sprint, work_items=work_items
            )
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

        clean_sprint = (sprint_name or "").strip()
        if (not clean_sprint or clean_sprint.lower() == "latest") and self.availableSprintList:
            clean_sprint = self.availableSprintList[0]
        elif not clean_sprint:
            clean_sprint = "latest"

        if not md_path:
            md_path = os.path.join(devops_helper.BASE_FOLDER, f"SPRINT_REPORT_{clean_sprint}.md")
        if not csv_path:
            csv_path = os.path.join(devops_helper.BASE_FOLDER, f"SPRINT_REPORT_{clean_sprint}.csv")

        def _work(worker):
            worker.log_message.emit(f"Generating Sprint Report for '{clean_sprint}'...")
            import generate_sprint_report
            work_items = self._work_items if self._work_items else None
            data, md_text = generate_sprint_report.generate_sprint_report(
                self._cache_db,
                sprint_name=clean_sprint,
                output_md=md_path,
                output_csv=csv_path,
                work_items=work_items
            )
            self.sprintReportGenerated.emit(data, md_text)
            worker.log_message.emit(f"Sprint report saved: {md_path} and {csv_path}")
            return f"Sprint report for {clean_sprint} generated successfully"

        self._run_worker(_work, f"Generating Sprint Report ({clean_sprint})...")

    @Slot()
    @Slot(str)
    def open_sprint_report_file(self, sprint_name=""):
        """Opens generated sprint report markdown in default editor."""
        clean_sprint = (sprint_name or "").strip()
        if (not clean_sprint or clean_sprint.lower() == "latest") and self.availableSprintList:
            clean_sprint = self.availableSprintList[0]
        elif not clean_sprint:
            clean_sprint = "latest"
        path = os.path.join(devops_helper.BASE_FOLDER, f"SPRINT_REPORT_{clean_sprint}.md")
        if os.path.exists(path):
            self.open_path_in_explorer(path)
        else:
            self.logMessage.emit(f"File does not exist: {path}")

    @Slot(int, str, result=dict)
    def update_work_item_deadline(self, work_item_id, new_date_str):
        """
        Updates the target deadline for a work item immediately in local SQLite cache & memory,
        and asynchronously synchronizes via TFS REST Web API in a background thread to prevent UI blocking.

        Args:
            work_item_id (int): Work item ID.
            new_date_str (str): Target date (YYYY-MM-DD or empty string to clear).

        Returns:
            dict: {"success": bool, "message": str, "deadline": str, "urgency_badge": str, "urgency_color": str, "api_synced": bool, "syncing": bool}
        """
        try:
            clean_id = int(work_item_id)
        except (ValueError, TypeError):
            return {"success": False, "error": "Invalid work item ID"}

        clean_date = (new_date_str or "").strip()
        field_to_update = self._custom_deadline_field or "Microsoft.VSTS.Scheduling.TargetDate"

        logger.info(f"Updating deadline for Work Item #{clean_id} -> '{clean_date}' (Field: {field_to_update})")

        # 1. Update local SQLite DB cache immediately
        db_ok = False
        if self._cache_db:
            db_ok = self._cache_db.update_work_item_deadline(clean_id, clean_date, field_name=field_to_update)

        # 2. Recalculate and refresh memory cache immediately for instantaneous UI response
        self.refresh_all_data()

        # Find updated work item to return fresh urgency badge
        updated_wi = next((w for w in self._work_items if w["id"] == clean_id), None)
        badge = updated_wi.get("urgency_badge", "—") if updated_wi else "—"
        color = updated_wi.get("urgency_color", "#8b949e") if updated_wi else "#8b949e"

        # 3. Synchronize to Azure DevOps / TFS Web API asynchronously in background thread
        def _sync_deadline_to_tfs_async(item_id, field_name, date_val):
            try:
                azHandler = devops_helper._getHandler()
                if azHandler and hasattr(azHandler, "update_work_item_field"):
                    val_to_send = f"{date_val}T17:00:00Z" if date_val and "T" not in date_val else (date_val or None)
                    azHandler.update_work_item_field(item_id, field_name, val_to_send, project_id=devops_helper.AZURE_PROJECT_ID)
                    msg_ok = f"✅ [Work Item #{item_id}] Deadline successfully synchronized with TFS API ({field_name}={date_val or 'Cleared'})"
                    logger.info(msg_ok)
                    self.logMessage.emit(msg_ok)
                else:
                    logger.warning(f"TFS API handler not available for work item #{item_id} deadline sync.")
            except Exception as e:
                err_msg = f"⚠️ [Work Item #{item_id}] Could not push deadline update to TFS API: {e}"
                logger.warning(err_msg)
                self.logMessage.emit(err_msg)

        threading.Thread(
            target=_sync_deadline_to_tfs_async,
            args=(clean_id, field_to_update, clean_date),
            daemon=True,
            name=f"TFS-DeadlineSync-#{clean_id}"
        ).start()

        msg = f"Deadline set to {clean_date or 'Cleared'} (Saved locally; syncing with TFS in background...)"
        self.logMessage.emit(f"[Work Item #{clean_id}] {msg}")
        return {
            "success": True,
            "work_item_id": clean_id,
            "deadline": clean_date,
            "urgency_badge": badge,
            "urgency_color": color,
            "api_synced": False,
            "syncing": True,
            "message": msg
        }

    @Slot(int, str, result=dict)
    def update_work_item_iteration(self, work_item_id, new_iteration):
        """
        Updates the iteration path of a work item immediately in local SQLite cache & memory,
        logs the shift event, and asynchronously syncs to TFS via REST API in background.

        Args:
            work_item_id (int): Work item ID.
            new_iteration (str): Target sprint name (e.g. 'week-2634') or full iteration path.

        Returns:
            dict: {"success": bool, "message": str, "iteration": str, "full_path": str, "api_synced": bool, "syncing": bool}
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

        # 1. Update SQLite DB & log shift event immediately
        db_ok = False
        if self._cache_db:
            db_ok = self._cache_db.update_work_item_iteration(clean_id, full_path, source="gui_manual")

        # 2. Refresh UI & models immediately for instant user feedback
        self.refresh_all_data()
        self.iterationShiftsChanged.emit()
        self.workloadMatrixChanged.emit()

        # 3. Synchronize to Azure DevOps / TFS API asynchronously in background thread
        def _sync_iteration_to_tfs_async(item_id, iter_path):
            try:
                azHandler = devops_helper._getHandler()
                if azHandler and hasattr(azHandler, "update_work_item_field"):
                    azHandler.update_work_item_field(item_id, "System.IterationPath", iter_path, project_id=devops_helper.AZURE_PROJECT_ID)
                    msg_ok = f"✅ [Work Item #{item_id}] Iteration successfully synchronized with TFS API ({iter_path})"
                    logger.info(msg_ok)
                    self.logMessage.emit(msg_ok)
                else:
                    logger.warning(f"TFS API handler not available for work item #{item_id} iteration sync.")
            except Exception as e:
                err_msg = f"⚠️ [Work Item #{item_id}] Could not push iteration update to TFS API: {e}"
                logger.warning(err_msg)
                self.logMessage.emit(err_msg)

        threading.Thread(
            target=_sync_iteration_to_tfs_async,
            args=(clean_id, full_path),
            daemon=True,
            name=f"TFS-IterationSync-#{clean_id}"
        ).start()

        msg = f"Iteration moved to '{clean_iter or 'Unplanned'}' (Saved locally; syncing with TFS in background...)"
        self.logMessage.emit(f"[Work Item #{clean_id}] {msg}")
        return {
            "success": True,
            "work_item_id": clean_id,
            "iteration": clean_iter,
            "full_path": full_path,
            "api_synced": False,
            "syncing": True,
            "message": msg
        }

    @Slot(str, str, bool, result="QVariantMap")
    @Slot(str, str, result="QVariantMap")
    @Slot(str, result="QVariantMap")
    @Slot(result="QVariantMap")
    def prepareWeeklyIterations(self, deadline: str = "", start_from: str = "", sync_to_tfs: bool = False):
        """
        Prepares weekly iterations following the 'week-YYWW' schematic in advance up until
        a given deadline or milestone date. Saves them to local cache and optionally syncs with TFS.
        """
        proj = self.selectedProject or devops_helper.AZURE_PROJECT_ID or ""
        tfs_client = None
        if sync_to_tfs and self.tfsUrl and self.tfsToken:
            try:
                from azure.azure_info_handler import AzureInfoHandler
                tfs_client = AzureInfoHandler(self.tfsUrl, self.tfsToken)
            except Exception as e:
                self.logMessage.emit(f"Warning: Failed to initialize TFS client for iteration sync: {e}")

        # If deadline is not given, check if there is an active milestone deadline
        dl = deadline.strip() if deadline else ""
        if not dl:
            milestones = self.get_milestones()
            future_ms = [m.get("target_date") for m in milestones if m.get("target_date")]
            if future_ms:
                dl = max(future_ms)

        if tfs_client:
            res = tfs_client.prepare_weekly_iterations(
                project_id=proj,
                deadline=dl or None,
                start_from=start_from.strip() or None,
                sync_to_tfs=True,
                cache_db=self._cache_db
            )
        else:
            generated = utils.generate_weekly_iterations_advance(
                start_date_or_week=start_from.strip() or None,
                deadline=dl or None
            )
            for item in generated:
                full_path = f"{proj}\\{item['sprint_name']}" if proj else item['sprint_name']
                item["iteration_path"] = full_path
                item["is_server_synced"] = 0
                if self._cache_db:
                    try:
                        self._cache_db.save_cached_iteration(
                            project=proj,
                            name=item["sprint_name"],
                            path=full_path,
                            start_date=item["start_date"],
                            end_date=item["end_date"],
                            year=item["year"],
                            week=item["week"],
                            is_synced=0
                        )
                    except Exception as e:
                        self.logMessage.emit(f"Error saving cached iteration {item['sprint_name']}: {e}")
            res = {
                "total_generated": len(generated),
                "created_on_server": 0,
                "iterations": generated
            }

        self.workItemsChanged.emit()
        self.workloadMatrixChanged.emit()
        self.logMessage.emit(f"Prepared {res['total_generated']} weekly iterations up to deadline {dl or 'default'} (created {res['created_on_server']} on server).")
        return res

    @Slot(str, str, result=list)
    @Slot(str, result=list)
    @Slot(result=list)
    def getProjectedWeeklyIterations(self, deadline: str = "", start_from: str = ""):
        """
        Returns projected weekly iterations list up to the deadline for UI preview.
        """
        dl = deadline.strip() if deadline else ""
        if not dl:
            milestones = self.get_milestones()
            future_ms = [m.get("target_date") for m in milestones if m.get("target_date")]
            if future_ms:
                dl = max(future_ms)
        return utils.generate_weekly_iterations_advance(
            start_date_or_week=start_from.strip() or None,
            deadline=dl or None
        )

    @Slot(int)
    @Slot(str)
    def open_work_item_in_browser(self, work_item_id):
        """
        Opens a work item in the system web browser pointing to Azure DevOps / TFS.
        """
        try:
            clean_id = int(str(work_item_id).lstrip("#"))
        except (ValueError, TypeError):
            self.logMessage.emit(f"Invalid work item ID: {work_item_id}")
            return

        url = ""
        # Try to find cached work item URL
        if self._cache_db:
            try:
                wi = self._cache_db.get_work_item(clean_id)
                if wi and isinstance(wi, dict):
                    raw_s = wi.get("raw_json")
                    if raw_s:
                        raw = json.loads(raw_s)
                        url = raw.get("_links", {}).get("html", {}).get("href", "")
            except Exception:
                pass

        if not url:
            # Construct standard ADO/TFS work item URL
            base_url = (getattr(devops_helper, "AZURE_BASE_URL", "") or "").rstrip("/")
            col = (getattr(devops_helper, "DEFAULT_COLLECTION", "") or "").strip("/")
            proj = (getattr(devops_helper, "DEFAULT_PROJECT", "") or "").strip("/")
            if base_url:
                parts = [base_url]
                if col:
                    parts.append(col)
                if proj:
                    parts.append(proj)
                parts.append(f"_workitems/edit/{clean_id}")
                url = "/".join(parts)

        if url:
            self.open_url(url)
        else:
            self.logMessage.emit(f"Could not construct Azure DevOps URL for Work Item #{clean_id}")

    @Slot(str, result=str)
    @Slot(result=str)
    @Slot(int, result=str)
    @Slot(str, str, result=str)
    @Slot(int, str, result=str)
    @Slot(str, str, str, result=str)
    @Slot(int, str, str, result=str)
    @Slot(str, str, str, str, result=str)
    @Slot(int, str, str, str, result=str)
    def get_sprint_taskboard_url(self, target="", sprint_name="", team_name="", view_mode="taskboard"):
        """
        Constructs the TFS / Azure DevOps Sprint Taskboard URL for a work item, sprint name, or current sprint.

        The URL format requires a team name:
          {base_url}/{collection}/{project}/_sprints/{view_mode}/{team}/{iteration_path}?workitem={id}
        or for current sprint:
          {base_url}/{collection}/{project}/_sprints/{view_mode}/{team}?workitem={id}

        The team name is determined by:
          1. Explicitly passed `team_name`
          2. Configured TFS Team Name in settings/project config (`self._tfs_team_name`)
          3. Extracted team segment from the work item's area path (e.g. 'Project\\Team')
          4. Extracted team segment from the iteration path (e.g. 'Project\\Team\\Sprint')
          5. Default Azure DevOps team convention: '{project} Team'
        """
        import urllib.parse
        base_url = (getattr(devops_helper, "AZURE_BASE_URL", "") or "").rstrip("/")
        col = (getattr(devops_helper, "AZURE_COLLECTION", "") or getattr(devops_helper, "DEFAULT_COLLECTION", "") or "").strip("/")
        proj = (getattr(devops_helper, "AZURE_PROJECT_ID", "") or getattr(devops_helper, "DEFAULT_PROJECT", "") or "").strip("/")
        if not (base_url and col and proj):
            return ""

        team = (team_name or self._tfs_team_name or "").strip()
        extracted_team = ""
        sprint_leaf = ""
        iteration_subpath_parts = []
        clean_id = None

        if target is not None and str(target).strip() != "":
            try:
                clean_id = int(str(target).lstrip("#"))
                if self._cache_db:
                    wi = self._cache_db.get_work_item(clean_id)
                    if wi and isinstance(wi, dict):
                        ipath = wi.get("iteration_path") or ""
                        apath = wi.get("area_path") or ""
                        raw_s = wi.get("raw_json")
                        if (not ipath or not apath) and raw_s and isinstance(raw_s, str):
                            try:
                                raw = json.loads(raw_s)
                                fields = raw.get("fields", {})
                                if not ipath:
                                    ipath = fields.get("System.IterationPath") or ""
                                if not apath:
                                    apath = fields.get("System.AreaPath") or ""
                            except Exception:
                                pass
                        if apath:
                            a_parts = [p for p in apath.replace("\\", "/").strip("/").split("/") if p]
                            if len(a_parts) >= 2:
                                extracted_team = a_parts[-1]
                        if ipath:
                            i_parts = [p for p in ipath.replace("\\", "/").strip("/").split("/") if p]
                            if i_parts:
                                sprint_leaf = i_parts[-1]
                                iteration_subpath_parts = i_parts if i_parts[0].lower() == proj.lower() else [proj] + i_parts
                            if not extracted_team and len(i_parts) >= 3 and i_parts[1].lower() not in ("sprints", "iterations", "iteration", "sprint"):
                                extracted_team = i_parts[1]
            except (ValueError, TypeError):
                t_parts = [p for p in str(target).replace("\\", "/").strip("/").split("/") if p]
                if t_parts:
                    sprint_leaf = t_parts[-1]
                    iteration_subpath_parts = t_parts if t_parts[0].lower() == proj.lower() else [proj] + t_parts
                if len(t_parts) >= 3 and t_parts[0].lower() == proj.lower() and t_parts[1].lower() not in ("sprints", "iterations", "iteration", "sprint"):
                    extracted_team = t_parts[1]

        if sprint_name:
            s_parts = [p for p in str(sprint_name).replace("\\", "/").strip("/").split("/") if p]
            if s_parts:
                sprint_leaf = s_parts[-1]
                if not iteration_subpath_parts:
                    iteration_subpath_parts = s_parts if s_parts[0].lower() == proj.lower() else [proj] + s_parts
            if len(s_parts) >= 3 and s_parts[0].lower() == proj.lower() and not extracted_team and s_parts[1].lower() not in ("sprints", "iterations", "iteration", "sprint"):
                extracted_team = s_parts[1]

        if not team:
            team = extracted_team or f"{proj} Team"

        encoded_team = urllib.parse.quote(team, safe="")
        v_mode = view_mode if view_mode in ("taskboard", "backlog", "iteration") else "taskboard"

        has_specific_sprint = (
            sprint_leaf
            and sprint_leaf.lower() not in ("unplanned", "none", "backlog", "default", "root", "current", "")
            and sprint_leaf.lower() != proj.lower()
        )

        if has_specific_sprint and iteration_subpath_parts:
            encoded_sprint_path = "/".join(urllib.parse.quote(p, safe="") for p in iteration_subpath_parts)
            base_sprint_url = f"{base_url}/{col}/{proj}/_sprints/{v_mode}/{encoded_team}/{encoded_sprint_path}"
        elif has_specific_sprint and sprint_leaf:
            base_sprint_url = f"{base_url}/{col}/{proj}/_sprints/{v_mode}/{encoded_team}/{urllib.parse.quote(proj, safe='')}/{urllib.parse.quote(sprint_leaf, safe='')}"
        else:
            base_sprint_url = f"{base_url}/{col}/{proj}/_sprints/{v_mode}/{encoded_team}"

        if clean_id is not None:
            return f"{base_sprint_url}?workitem={clean_id}"
        return base_sprint_url

    @Slot(str)
    @Slot(int)
    @Slot(str, str)
    @Slot(int, str)
    @Slot(str, str, str)
    @Slot(int, str, str)
    def open_sprint_in_browser(self, target="", sprint_name="", team_name=""):
        """
        Opens the TFS / Azure DevOps Sprint Taskboard page in the system web browser.
        """
        url = self.get_sprint_taskboard_url(target, sprint_name, team_name)
        if url:
            s_label = sprint_name or str(target)
            logger.info(f"Opening Sprint Taskboard in browser: {url}")
            self.logMessage.emit(f"Opening Sprint Taskboard in browser ({s_label})...")
            self.open_url(url)
        else:
            self.logMessage.emit("Could not construct Azure DevOps Sprint URL (check Server URL and Project settings).")

    @Slot(int, str, result=bool)
    @Slot(int, result=bool)
    def set_shift_review_status(self, shift_id, status="accepted"):
        """Updates the review policy status of a single shift event."""
        if not self._cache_db:
            return False
        ok = self._cache_db.update_shift_review_status(shift_id, status=status)
        if ok:
            self.iterationShiftsChanged.emit()
            self.logMessage.emit(f"Shift #{shift_id} marked as {status}.")
        return ok

    @Slot(int, str, result=bool)
    @Slot(int, result=bool)
    def set_work_item_shifts_review_status(self, work_item_id, status="accepted"):
        """Updates review status for all shift events of a work item."""
        if not self._cache_db:
            return False
        ok = self._cache_db.update_work_item_shifts_review_status(work_item_id, status=status)
        if ok:
            self.iterationShiftsChanged.emit()
            self.logMessage.emit(f"All shifts for Work Item #{work_item_id} marked as {status}.")
        return ok

    @Slot(str, result=int)
    @Slot(result=int)
    def bulk_set_all_shifts_review_status(self, status="accepted"):
        """Bulk updates all shifts to the specified review status."""
        if not self._cache_db:
            return 0
        count = self._cache_db.update_all_shifts_review_status(status=status)
        self.iterationShiftsChanged.emit()
        self.logMessage.emit(f"Bulk updated {count} shift(s) to '{status}'.")
        return count

    @Slot()
    @Slot(str)
    def generate_rescheduling_report_async(self, review_filter=""):
        """Generates Sprint Rescheduling and Moved Items Markdown & CSV report asynchronously."""
        if self._is_busy:
            return

        r_stat = None if review_filter in ("", "all") else review_filter.strip().lower()
        md_path = os.path.join(devops_helper.BASE_FOLDER, "RESCHEDULING_REPORT.md")
        csv_path = os.path.join(devops_helper.BASE_FOLDER, "RESCHEDULING_REPORT.csv")

        def _work(worker):
            worker.log_message.emit("Generating Sprint Rescheduling & Moved Items Report...")
            import generate_rescheduling_report
            res = generate_rescheduling_report.generate_rescheduling_report(
                self._cache_db,
                output_md=md_path,
                output_csv=csv_path,
                review_status=r_stat
            )
            worker.log_message.emit(f"Rescheduling Report saved: {md_path} and {csv_path}")
            return f"Rescheduling report generated successfully ({res['total_moved_items']} moved items)"

        self._run_worker(_work, "Generating Rescheduling Report...")

    @Slot()
    def open_rescheduling_report_markdown(self):
        """Opens generated rescheduling report markdown file."""
        path = os.path.join(devops_helper.BASE_FOLDER, "RESCHEDULING_REPORT.md")
        if os.path.exists(path):
            self.open_path_in_explorer(path)
        else:
            self.logMessage.emit(f"Report file does not exist: {path}. Please generate it first.")

    @Slot()
    def open_rescheduling_report_csv(self):
        """Opens generated rescheduling report CSV file."""
        path = os.path.join(devops_helper.BASE_FOLDER, "RESCHEDULING_REPORT.csv")
        if os.path.exists(path):
            self.open_path_in_explorer(path)
        else:
            self.logMessage.emit(f"Report file does not exist: {path}. Please generate it first.")

    def _run_worker(self, task_func, busy_msg):
        logger.info(f"Starting background task: {busy_msg}")
        self.reset_auto_sync_timer()
        self._progress = 0
        self.progressChanged.emit()
        self._set_busy(True, busy_msg)
        self._worker = TaskWorker(task_func)
        self._worker.progress.connect(self._on_worker_progress)
        self._worker.log_message.connect(self._on_worker_log)
        self._worker.finished_task.connect(self._on_worker_finished)
        self._worker.start()

    def _on_worker_progress(self, percent, message):
        self._progress = percent
        self.progressChanged.emit()
        if message:
            self._status_message = message
            self.statusMessageChanged.emit()

    def _on_worker_log(self, msg):
        logger.info(msg)

    def _on_worker_finished(self, success, result_msg):
        self._progress = 100 if success else 0
        self.progressChanged.emit()
        self._set_busy(False, "Ready")
        self.reset_auto_sync_timer()

        if isinstance(result_msg, dict) and "work_items" in result_msg:
            self._apply_computed_cache_data(result_msg)
        else:
            self.refresh_all_data()

        if success:
            log_text = result_msg if isinstance(result_msg, str) else "Completed successfully"
            logger.info(f"[COMPLETED] {log_text}")
        else:
            logger.error(f"[FAILED] {result_msg}")
        self._worker = None

    @Slot()
    def abort_sync(self):
        """Cancels the currently running background synchronization or task."""
        if self._worker and self._worker.isRunning():
            logger.info("User requested task cancellation via GUI.")
            self._worker.cancel()
            self._status_message = "⏹️ Aborting sync..."
            self.statusMessageChanged.emit()

    @Slot()
    def cancel_active_task(self):
        """Alias for abort_sync."""
        self.abort_sync()

    @Slot()
    def open_db_folder(self):
        """Opens the directory containing the SQLite database cache in Windows File Explorer."""
        if self._db_path:
            folder = os.path.dirname(os.path.abspath(self._db_path))
            self.open_path_in_explorer(folder)

    @Slot()
    def reconnect_cache(self):
        """Re-initializes the cache handler and reloads all data asynchronously."""
        self.logMessage.emit("Reconnecting database cache...")
        self._init_cache()
        self.startup_load_async()
        self.logMessage.emit(f"Database cache connected: {self._db_path}")

    @Slot(result=list)
    def get_available_databases(self):
        """Scans workspace directory for SQLite cache databases quickly."""
        if not hasattr(self, "_db_scan_cache"):
            self._db_scan_cache = {}

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
                            try:
                                size_bytes = os.path.getsize(full_path)
                                mtime = os.path.getmtime(full_path)
                            except OSError:
                                continue

                            mtime_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
                            cache_key = (full_path, mtime, size_bytes)
                            
                            if cache_key in self._db_scan_cache:
                                proj_name = self._db_scan_cache[cache_key]
                            else:
                                proj_name = ""
                                try:
                                    import sqlite3
                                    conn = sqlite3.connect(full_path, timeout=0.5)
                                    conn.row_factory = sqlite3.Row
                                    cur = conn.cursor()
                                    cur.execute("PRAGMA busy_timeout=500")
                                    # Try to fetch project name from projects or project_config table
                                    try:
                                        p_row = cur.execute("SELECT name FROM projects ORDER BY last_synced_at DESC LIMIT 1").fetchone()
                                        if p_row and p_row["name"]:
                                            proj_name = p_row["name"]
                                    except sqlite3.OperationalError:
                                        pass
                                    if not proj_name:
                                        try:
                                            cfg_row = cur.execute("SELECT value FROM project_config WHERE key = 'project_name' LIMIT 1").fetchone()
                                            if cfg_row and cfg_row["value"]:
                                                proj_name = cfg_row["value"]
                                        except sqlite3.OperationalError:
                                            pass
                                    conn.close()
                                except Exception:
                                    pass

                                if not proj_name:
                                    bname = os.path.splitext(fname)[0]
                                    if bname.startswith("tfs_cache_"):
                                        proj_name = bname.replace("tfs_cache_", "")
                                    else:
                                        proj_name = "Custom Database"

                                self._db_scan_cache[cache_key] = proj_name

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

    @Slot(result=str)
    def browse_milestone_import_file(self):
        """Opens native file dialog to select an Excel/CSV/JSON milestone file to import."""
        try:
            from PySide6.QtWidgets import QFileDialog
            initial_dir = devops_helper.BASE_FOLDER if devops_helper.BASE_FOLDER and os.path.exists(devops_helper.BASE_FOLDER) else os.getcwd()
            file_path, _ = QFileDialog.getOpenFileName(
                None, "Select Milestones File to Import", initial_dir,
                "Milestones Files (*.xlsx *.xls *.csv *.json);;Excel Spreadsheets (*.xlsx *.xls);;CSV Files (*.csv);;JSON Files (*.json);;All Files (*.*)"
            )
            return file_path or ""
        except Exception as e:
            logger.error(f"Error opening import file dialog: {e}")
            return ""

    @Slot(result=str)
    def browseMilestoneImportFile(self):
        """CamelCase alias for browse_milestone_import_file."""
        return self.browse_milestone_import_file()

    @Slot(result=str)
    def browse_milestone_export_path(self):
        """Opens native file dialog to select save destination for Excel milestone export."""
        try:
            from PySide6.QtWidgets import QFileDialog
            initial_dir = devops_helper.BASE_FOLDER if devops_helper.BASE_FOLDER and os.path.exists(devops_helper.BASE_FOLDER) else os.getcwd()
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            default_path = os.path.join(initial_dir, f"MILESTONES_EXPORT_{timestamp}.xlsx")
            file_path, _ = QFileDialog.getSaveFileName(
                None, "Export Milestones to Excel", default_path,
                "Excel Spreadsheet (*.xlsx);;All Files (*.*)"
            )
            return file_path or ""
        except Exception as e:
            logger.error(f"Error opening export file dialog: {e}")
            return ""

    @Slot(result=str)
    def browseMilestoneExportPath(self):
        """CamelCase alias for browse_milestone_export_path."""
        return self.browse_milestone_export_path()

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

            # Load project configuration stored in the database if available
            self._load_project_config_from_db(self._cache_db)

            # Detect project name from database
            with self._cache_db._connection() as conn:
                p_row = conn.execute("SELECT name FROM projects ORDER BY last_synced_at DESC LIMIT 1").fetchone()
                if p_row and p_row["name"]:
                    devops_helper.AZURE_PROJECT_ID = p_row["name"]
                    self._stats["project_name"] = p_row["name"]
                elif not self._stats.get("project_name"):
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

            self.startup_load_async()
            self.settingsChanged.emit()
            self.statsChanged.emit()
            logger.info(f"Switched active database to: {abs_path} (Project: {self._stats['project_name']})")
            return True
        except Exception as e:
            logger.error(f"Error switching database to {abs_path}: {e}", exc_info=True)
            return False

    @Slot(result="QVariantMap")
    def get_project_config(self):
        """Returns all configuration key-values stored in the active project database."""
        if self._cache_db:
            return self._cache_db.get_all_config()
        return {}

    @Slot(str, str, result=bool)
    def set_project_config(self, key, value):
        """Updates a configuration key-value in the active project database."""
        if not self._cache_db or not key:
            return False
        try:
            self._cache_db.set_config(key, value)
            self._load_project_config_from_db(self._cache_db)
            self.settingsChanged.emit()
            return True
        except Exception as e:
            logger.error(f"Error setting project config '{key}': {e}")
            return False

    def _enrich_work_items_with_milestones(self, items=None, all_wis_map=None):
        """Enriches self._work_items with direct and inherited milestone associations."""
        target_items = items if items is not None else self._work_items
        if not target_items:
            return
        all_milestones = self.get_milestones()
        milestones_by_date = {m.get("target_date"): m for m in all_milestones if m.get("target_date")}
        if all_wis_map is None:
            all_wis_map = {w["id"]: w for w in target_items}

        # First pass: direct milestone match
        for item in target_items:
            matched_m = utils.match_work_item_to_milestone(item, all_milestones, milestones_by_date)
            if matched_m:
                item["milestone_name"] = matched_m.get("name", "")
                item["milestone_icon"] = matched_m.get("category_icon", "")
                item["milestone_color"] = matched_m.get("category_color", "")
                item["milestone_bg"] = matched_m.get("category_bg_color", "")
                item["milestone_category"] = matched_m.get("category_name", "")
                item["milestone_start_date"] = matched_m.get("start_date") or matched_m.get("target_date") or ""
                item["milestone_end_date"] = matched_m.get("end_date") or item["milestone_start_date"]
                item["milestone_date_display"] = matched_m.get("date_display") or item["milestone_start_date"]
                item["milestone_is_multi_day"] = matched_m.get("is_multi_day", False)
                item["has_direct_milestone"] = True
                item["has_milestone"] = True
                item["effective_milestone_name"] = matched_m.get("name", "")
                item["is_milestone_inherited"] = False
            else:
                item["milestone_name"] = ""
                item["milestone_icon"] = ""
                item["milestone_color"] = ""
                item["milestone_bg"] = ""
                item["milestone_category"] = ""
                item["milestone_start_date"] = ""
                item["milestone_end_date"] = ""
                item["milestone_date_display"] = ""
                item["milestone_is_multi_day"] = False
                item["has_direct_milestone"] = False
                item["has_milestone"] = False
                item["effective_milestone_name"] = ""
                item["is_milestone_inherited"] = False

        # Second pass: inherit milestone from parent/ancestor container if child has no direct milestone
        for item in target_items:
            if not item["has_milestone"]:
                curr_pid = item.get("parent_id")
                visited = set()
                while curr_pid and curr_pid in all_wis_map and curr_pid not in visited:
                    visited.add(curr_pid)
                    p_item = all_wis_map[curr_pid]
                    if p_item.get("has_direct_milestone") or p_item.get("has_milestone"):
                        item["milestone_name"] = p_item.get("milestone_name", "")
                        item["milestone_icon"] = p_item.get("milestone_icon", "")
                        item["milestone_color"] = p_item.get("milestone_color", "")
                        item["milestone_bg"] = p_item.get("milestone_bg", "")
                        item["milestone_category"] = p_item.get("milestone_category", "")
                        item["milestone_start_date"] = p_item.get("milestone_start_date", "")
                        item["milestone_end_date"] = p_item.get("milestone_end_date", "")
                        item["milestone_date_display"] = p_item.get("milestone_date_display", "")
                        item["milestone_is_multi_day"] = p_item.get("milestone_is_multi_day", False)
                        item["has_direct_milestone"] = False
                        item["has_milestone"] = True
                        item["effective_milestone_name"] = p_item.get("effective_milestone_name", "") or p_item.get("milestone_name", "")
                        item["is_milestone_inherited"] = True
                        break
                    curr_pid = p_item.get("parent_id")

        # Third pass: precalculate lowercase search text index for fast QML and backend filtering
        for item in target_items:
            search_parts = [
                str(item.get("id") or ""),
                item.get("title") or "",
                item.get("state") or "",
                item.get("type") or "",
                item.get("assigned_to") or "",
                item.get("tags") or "",
                item.get("iteration_name") or "",
                item.get("iteration_path") or "",
                item.get("area_path") or "",
                item.get("team_name") or "",
                item.get("milestone_name") or "",
                item.get("effective_milestone_name") or "",
                item.get("milestone_category") or "",
                item.get("pbs_code") or "",
                item.get("pbs_category") or "",
                item.get("level1_display") or "",
                item.get("level2_display") or "",
                item.get("prio_tag") or "",
                item.get("target_date") or "",
                item.get("parent_title") or "",
                str(item.get("parent_id") or "")
            ]
            item["_search_text"] = " ".join(p for p in search_parts if p).lower()

    @Slot(result=list)
    def get_milestones(self):
        """Returns all configured milestones."""
        if self._cache_db:
            return self._cache_db.get_milestones()
        return []

    @Slot(result=list)
    def getAvailableTeams(self):
        """Returns a sorted list of unique team names across work items, config, and milestones."""
        teams = set()
        if self._tfs_team_name:
            teams.add(self._tfs_team_name.strip())
        if self._work_items:
            for wi in self._work_items:
                t = (wi.get("team_name") or "").strip()
                if t:
                    teams.add(t)
        if self._cache_db:
            for m in self._cache_db.get_milestones():
                t = (m.get("team") or "").strip()
                if t:
                    teams.add(t)
        return sorted([t for t in teams if t])

    @Slot(result=list)
    def get_available_teams(self):
        """Snake_case alias for getAvailableTeams."""
        return self.getAvailableTeams()

    @Slot(str, str, str, str, int, str, str, result=dict)
    @Slot(str, str, str, str, int, str, result=dict)
    @Slot(str, str, str, str, int, result=dict)
    @Slot(str, str, str, str, result=dict)
    def save_milestone(self, name, target_date, category_id, description="", milestone_id=0, end_date="", team=""):
        """Creates or updates a milestone, supporting single-day or multi-day date ranges and team assignment."""
        if not self._cache_db:
            return {"success": False, "error": "No database connected"}
        clean_name = (name or "").strip()
        clean_date = (target_date or "").strip()
        clean_end_date = (end_date or "").strip()
        clean_team = (team or "").strip()
        if not clean_name:
            return {"success": False, "error": "Milestone name is required"}
        if not clean_date:
            return {"success": False, "error": "Target date is required"}

        try:
            m_id = self._cache_db.save_milestone(clean_name, clean_date, category_id, description, milestone_id, clean_end_date, clean_team)
            self._enrich_work_items_with_milestones()
            self.milestonesChanged.emit()
            self.workloadMatrixChanged.emit()
            self.workItemsChanged.emit()
            return {"success": True, "id": m_id}
        except Exception as e:
            logger.error(f"Error saving milestone: {e}")
            return {"success": False, "error": str(e)}

    @Slot(int, result=bool)
    def delete_milestone(self, milestone_id):
        """Deletes a milestone."""
        if not self._cache_db:
            return False
        res = self._cache_db.delete_milestone(milestone_id)
        if res:
            self._enrich_work_items_with_milestones()
            self.milestonesChanged.emit()
            self.workloadMatrixChanged.emit()
            self.workItemsChanged.emit()
        return res

    @Slot(result=int)
    def prefillMilestonesFromWorkItems(self):
        """Scans all work items in the database for Target:<TargetShortName> tags and pre-fills milestones."""
        if not self._cache_db:
            return 0
        try:
            new_milestones = self._cache_db.discover_and_prefill_milestones_from_work_items()
            if new_milestones:
                self._enrich_work_items_with_milestones()
                self.milestonesChanged.emit()
                self.workloadMatrixChanged.emit()
                self.workItemsChanged.emit()
            return len(new_milestones) if isinstance(new_milestones, list) else 0
        except Exception as e:
            logger.error(f"Error prefilling milestones from work items: {e}")
            return 0

    @Slot(result=int)
    def prefill_milestones_from_work_items(self):
        """Snake_case alias for prefillMilestonesFromWorkItems."""
        return self.prefillMilestonesFromWorkItems()

    @Slot(str, result="QVariantMap")
    @Slot(result="QVariantMap")
    def exportMilestonesToExcel(self, file_path=""):
        """
        Exports all project milestones (with Team, Category, Start/End Dates, and Week Range) to an Excel (.xlsx) file.
        """
        try:
            import openpyxl
            from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
            from openpyxl.utils import get_column_letter

            milestones = self.get_milestones() or []
            target_path = file_path or ""
            if target_path.startswith("file:///"):
                target_path = target_path.replace("file:///", "")
                if os.name == "nt" and target_path.startswith("/"):
                    target_path = target_path[1:]

            if not target_path:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                target_dir = devops_helper.BASE_FOLDER if os.path.exists(devops_helper.BASE_FOLDER) else os.getcwd()
                target_path = os.path.join(target_dir, f"MILESTONES_EXPORT_{timestamp}.xlsx")

            target_path = os.path.abspath(target_path)
            os.makedirs(os.path.dirname(target_path), exist_ok=True)

            wb = openpyxl.Workbook()
            ws = wb.active
            ws.title = "Milestones"
            ws.views.sheetView[0].showGridLines = True

            headers = [
                "ID",
                "Milestone Name",
                "Team",
                "Category",
                "Start Date",
                "End Date",
                "Start Week",
                "End Week",
                "Week Range",
                "Duration (Days)",
                "Description"
            ]
            ws.append(headers)

            # Header styling
            header_font = Font(name="Segoe UI", size=11, bold=True, color="FFFFFF")
            header_fill = PatternFill(start_color="1F4E79", end_color="1F4E79", fill_type="solid")
            header_align = Alignment(horizontal="center", vertical="center", wrap_text=False)
            thin_border = Border(
                left=Side(style="thin", color="D0D7DE"),
                right=Side(style="thin", color="D0D7DE"),
                top=Side(style="thin", color="D0D7DE"),
                bottom=Side(style="thin", color="D0D7DE")
            )

            for col_idx in range(1, len(headers) + 1):
                cell = ws.cell(row=1, column=col_idx)
                cell.font = header_font
                cell.fill = header_fill
                cell.alignment = header_align
                cell.border = thin_border
            ws.row_dimensions[1].height = 28

            data_font = Font(name="Segoe UI", size=10)
            id_font = Font(name="Segoe UI", size=10, bold=True, color="0969DA")
            zebra_fill = PatternFill(start_color="F8FAFC", end_color="F8FAFC", fill_type="solid")

            for row_idx, m in enumerate(milestones, start=2):
                m_id = m.get("id") or ""
                m_name = m.get("name") or ""
                m_team = m.get("team") or m.get("team_name") or ""
                m_cat = m.get("category_name") or m.get("category_id") or "General"
                m_start = m.get("start_date") or m.get("target_date") or ""
                m_end = m.get("end_date") or m_start
                m_start_w = m.get("start_week") or ""
                m_end_w = m.get("end_week") or m_start_w
                m_week_range = m.get("week_range") or m_start_w
                m_duration = m.get("duration_days") or 1
                m_desc = m.get("description") or ""

                row_vals = [
                    m_id,
                    m_name,
                    m_team,
                    m_cat,
                    m_start,
                    m_end,
                    m_start_w,
                    m_end_w,
                    m_week_range,
                    m_duration,
                    m_desc
                ]
                ws.append(row_vals)

                is_even = (row_idx % 2 == 0)
                row_fill = zebra_fill if is_even else None

                for col_idx in range(1, len(row_vals) + 1):
                    c = ws.cell(row=row_idx, column=col_idx)
                    c.font = id_font if col_idx == 1 else data_font
                    c.border = thin_border
                    if row_fill:
                        c.fill = row_fill

                    # Alignment
                    if col_idx == 1:
                        c.alignment = Alignment(horizontal="center")
                    elif col_idx in [3, 4, 5, 6, 7, 8, 9, 10]:
                        c.alignment = Alignment(horizontal="center")
                    else:
                        c.alignment = Alignment(horizontal="left")

                ws.row_dimensions[row_idx].height = 22

            # Auto-fit columns
            for col in ws.columns:
                max_len = 0
                col_letter = get_column_letter(col[0].column)
                for cell in col:
                    val_str = str(cell.value or "")
                    if len(val_str) > max_len:
                        max_len = len(val_str)
                ws.column_dimensions[col_letter].width = max(max_len + 4, 12)

            wb.save(target_path)
            logger.info(f"Exported {len(milestones)} milestones to Excel: {target_path}")
            return {
                "success": True,
                "file_path": target_path,
                "count": len(milestones),
                "message": f"Successfully exported {len(milestones)} milestone(s) to Excel."
            }
        except Exception as e:
            logger.error(f"Error exporting milestones to Excel: {e}")
            return {
                "success": False,
                "error": str(e),
                "message": f"Failed to export milestones: {str(e)}"
            }

    @Slot(str, result="QVariantMap")
    @Slot(result="QVariantMap")
    def export_milestones_to_excel(self, file_path=""):
        """Snake_case alias for exportMilestonesToExcel."""
        return self.exportMilestonesToExcel(file_path)

    def _normalize_date_str(self, raw_val, is_end=False):
        """Normalizes an import value (date, ISO week, or date string) to YYYY-MM-DD format."""
        if not raw_val:
            return ""
        if isinstance(raw_val, (datetime, date)):
            return raw_val.strftime("%Y-%m-%d")
        
        s = str(raw_val).strip()
        if not s:
            return ""

        # Check if already YYYY-MM-DD
        if re.match(r'^\d{4}-\d{2}-\d{2}$', s):
            return s

        # Try ISO week e.g. week-2630 or week-2026-30
        y, w, _ = utils.parse_sprint_week(s)
        if y and w:
            start_d, end_d, s_str, e_str = utils.get_sprint_date_range(y, w)
            return e_str if is_end else s_str

        # Try common date formats
        for fmt in ["%Y/%m/%d", "%d.%m.%Y", "%m/%d/%Y", "%d/%m/%Y", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S"]:
            try:
                dt = datetime.strptime(s.split(".")[0], fmt)
                return dt.strftime("%Y-%m-%d")
            except Exception:
                continue

        # Try ISO datetime parse
        dt = utils.parse_iso_datetime(s)
        if dt:
            return dt.strftime("%Y-%m-%d")

        return s

    def _parse_milestone_import_dict(self, d):
        """Extracts and normalizes milestone fields from an imported row dictionary."""
        # Name
        name = ""
        for k in ["name", "milestonename", "milestone", "title", "milestonetitle", "item"]:
            if k in d and d[k]:
                name = str(d[k]).strip()
                break

        # Team
        team = ""
        for k in ["team", "teamname", "assignedteam", "group"]:
            if k in d and d[k]:
                team = str(d[k]).strip()
                if team.lower() == "all teams":
                    team = ""
                break

        # Category
        cat = "general"
        for k in ["category", "categoryname", "categoryid", "cat", "type"]:
            if k in d and d[k]:
                cat = str(d[k]).strip()
                break

        # Description
        desc = ""
        for k in ["description", "desc", "details", "notes", "scope", "comment"]:
            if k in d and d[k]:
                desc = str(d[k]).strip()
                break

        # ID
        m_id = 0
        for k in ["id", "milestoneid", "key"]:
            if k in d and d[k]:
                try:
                    m_id = int(d[k])
                except Exception:
                    pass
                break

        # Start Date / End Date / Week Range
        start_d = ""
        end_d = ""
        for k in ["startdate", "start", "targetdate", "target", "date", "startday", "from"]:
            if k in d and d[k]:
                start_d = self._normalize_date_str(d[k], is_end=False)
                break

        for k in ["enddate", "end", "targetenddate", "targetend", "to", "until"]:
            if k in d and d[k]:
                end_d = self._normalize_date_str(d[k], is_end=True)
                break

        # Check Week Range if dates are missing
        if not start_d or not end_d:
            week_val = ""
            for k in ["weekrange", "week", "sprintrange", "sprint", "sprints", "weeks", "iterationrange", "iteration"]:
                if k in d and d[k]:
                    week_val = str(d[k]).strip()
                    break

            if week_val:
                # Find all sprint weeks or dates in the week_val (e.g. "week-2630 – week-2633")
                found_sprints = re.findall(r'(?:week|sprint)[-_]?\d{2,4}[-_]?[wW]?\d{1,2}|\b\d{4}[-_]\d{2}[-_]\d{2}\b|\b\d{4}\b', week_val, re.IGNORECASE)
                if len(found_sprints) >= 2:
                    if not start_d:
                        start_d = self._normalize_date_str(found_sprints[0], is_end=False)
                    if not end_d:
                        end_d = self._normalize_date_str(found_sprints[1], is_end=True)
                elif len(found_sprints) == 1:
                    if not start_d:
                        start_d = self._normalize_date_str(found_sprints[0], is_end=False)
                    if not end_d:
                        end_d = self._normalize_date_str(found_sprints[0], is_end=True)
                else:
                    parts = re.split(r'\s+(?:–|-|to|->|→|until)\s+|\s*–\s*', week_val)
                    if len(parts) >= 2:
                        s_w = parts[0].strip()
                        e_w = parts[1].strip()
                        if not start_d:
                            start_d = self._normalize_date_str(s_w, is_end=False)
                        if not end_d:
                            end_d = self._normalize_date_str(e_w, is_end=True)
                    elif len(parts) == 1 and not start_d:
                        start_d = self._normalize_date_str(parts[0].strip(), is_end=False)
                        if not end_d:
                            end_d = self._normalize_date_str(parts[0].strip(), is_end=True)

        if not end_d:
            end_d = start_d
        if not start_d:
            start_d = end_d

        return {
            "id": m_id,
            "name": name,
            "team": team,
            "category": cat,
            "category_id": cat,
            "start_date": start_d,
            "target_date": start_d,
            "end_date": end_d,
            "description": desc
        }

    @Slot(str, bool, result="QVariantMap")
    @Slot(str, result="QVariantMap")
    def importMilestonesFromExcel(self, file_path, clear_existing=False):
        """
        Imports milestones from an Excel (.xlsx/.xls), CSV (.csv), or JSON (.json) file.
        Supports Team and Week-Range (e.g. week-2630 – week-2633).
        """
        if not self._cache_db:
            return {"success": False, "error": "No database connected", "message": "Database not connected."}

        clean_path = (file_path or "").strip()
        if clean_path.startswith("file:///"):
            clean_path = clean_path.replace("file:///", "")
            if os.name == "nt" and clean_path.startswith("/"):
                clean_path = clean_path[1:]

        if not os.path.exists(clean_path):
            return {"success": False, "error": f"File not found: {clean_path}", "message": f"File not found: {clean_path}"}

        parsed_milestones = []
        ext = os.path.splitext(clean_path)[1].lower()

        try:
            if ext in [".xlsx", ".xls"]:
                import openpyxl
                wb = openpyxl.load_workbook(clean_path, data_only=True)
                ws = wb.active
                rows = list(ws.iter_rows(values_only=True))
                if not rows:
                    return {"success": False, "error": "Empty Excel sheet", "message": "Excel file is empty."}

                header_row = [str(h or "").strip().lower().replace(" ", "").replace("_", "").replace("-", "") for h in rows[0]]
                for r in rows[1:]:
                    if not any(r):
                        continue
                    row_dict = {}
                    for col_idx, h in enumerate(header_row):
                        if col_idx < len(r):
                            row_dict[h] = r[col_idx]
                    parsed_milestones.append(self._parse_milestone_import_dict(row_dict))

            elif ext == ".csv":
                import csv
                raw_rows = []
                for enc in ["utf-8-sig", "utf-8", "latin-1"]:
                    try:
                        with open(clean_path, mode="r", encoding=enc, newline="") as f:
                            reader = csv.DictReader(f)
                            for r in reader:
                                norm_dict = {
                                    k.strip().lower().replace(" ", "").replace("_", "").replace("-", ""): v
                                    for k, v in r.items() if k
                                }
                                raw_rows.append(norm_dict)
                        break
                    except UnicodeDecodeError:
                        continue
                for rd in raw_rows:
                    parsed_milestones.append(self._parse_milestone_import_dict(rd))

            elif ext == ".json":
                with open(clean_path, mode="r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        for item in data:
                            if isinstance(item, dict):
                                norm_dict = {
                                    k.strip().lower().replace(" ", "").replace("_", "").replace("-", ""): v
                                    for k, v in item.items() if k
                                }
                                parsed_milestones.append(self._parse_milestone_import_dict(norm_dict))
                    elif isinstance(data, dict):
                        norm_dict = {
                            k.strip().lower().replace(" ", "").replace("_", "").replace("-", ""): v
                            for k, v in data.items() if k
                        }
                        parsed_milestones.append(self._parse_milestone_import_dict(norm_dict))
            else:
                return {"success": False, "error": f"Unsupported file type: {ext}", "message": f"Unsupported file extension '{ext}'."}

            # Filter valid milestone items
            valid_milestones = [m for m in parsed_milestones if m.get("name") and (m.get("target_date") or m.get("start_date"))]
            if not valid_milestones:
                return {
                    "success": False,
                    "error": "No valid milestones found in file",
                    "message": "No valid milestones found. Ensure rows have at least a Name and a Date or Sprint/Week range."
                }

            res = self._cache_db.bulk_import_milestones(valid_milestones, clear_existing=clear_existing)
            self._enrich_work_items_with_milestones()
            self.milestonesChanged.emit()
            self.workloadMatrixChanged.emit()
            self.workItemsChanged.emit()

            msg = f"Successfully imported {res['total']} milestone(s) ({res['created']} created, {res['updated']} updated)."
            logger.info(f"Imported milestones from {clean_path}: {res}")
            return {
                "success": True,
                "created": res["created"],
                "updated": res["updated"],
                "total": res["total"],
                "message": msg
            }
        except Exception as e:
            logger.error(f"Error importing milestones from {clean_path}: {e}")
            return {
                "success": False,
                "error": str(e),
                "message": f"Failed to import milestones: {str(e)}"
            }

    @Slot(str, bool, result="QVariantMap")
    @Slot(str, result="QVariantMap")
    def import_milestones_from_excel(self, file_path, clear_existing=False):
        """Snake_case alias for importMilestonesFromExcel."""
        return self.importMilestonesFromExcel(file_path, clear_existing)

    @Slot(list, str, result="QVariantMap")
    @Slot(list, result="QVariantMap")
    @Slot(str, result="QVariantMap")
    @Slot(result="QVariantMap")
    def exportWorkItemsToExcel(self, items_or_file_path=None, file_path=""):
        """
        Exports work items to an Excel (.xlsx) spreadsheet with professional formatting.
        Accepts either a list of work item dicts (e.g. filtered items from QML) or defaults to all cached items.
        """
        try:
            import openpyxl
            from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
            from openpyxl.utils import get_column_letter

            items_to_export = []
            target_path = ""

            if isinstance(items_or_file_path, list):
                items_to_export = items_or_file_path
                target_path = file_path
            elif isinstance(items_or_file_path, str):
                target_path = items_or_file_path
                items_to_export = self._work_items
            else:
                items_to_export = self._work_items
                target_path = file_path

            if not items_to_export:
                items_to_export = self._work_items or []

            if not target_path:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                target_dir = devops_helper.BASE_FOLDER if os.path.exists(devops_helper.BASE_FOLDER) else os.getcwd()
                target_path = os.path.join(target_dir, f"WORK_ITEMS_EXPORT_{timestamp}.xlsx")

            target_path = os.path.abspath(target_path)
            os.makedirs(os.path.dirname(target_path), exist_ok=True)

            wb = openpyxl.Workbook()
            ws = wb.active
            ws.title = "Work Items"
            ws.views.sheetView[0].showGridLines = True

            headers = [
                "ID",
                "Type",
                "Title",
                "State",
                "Assigned To",
                "Sprint / Iteration",
                "Iteration Path",
                "Deadline / Target Date",
                "Urgency Status",
                "Milestone",
                "Milestone Category",
                "Sub-System (L1)",
                "L1 PBS",
                "Component (L2)",
                "L2 PBS",
                "Priority Focus",
                "PBS Grouped",
                "Remaining Work (h)",
                "Completed Work (h)",
                "Changed Date",
                "TFS URL"
            ]
            ws.append(headers)

            # Styling definitions
            header_font = Font(name="Segoe UI", size=11, bold=True, color="FFFFFF")
            header_fill = PatternFill(start_color="1F4E79", end_color="1F4E79", fill_type="solid")
            header_align = Alignment(horizontal="center", vertical="center", wrap_text=False)

            thin_border = Border(
                left=Side(style="thin", color="D0D7DE"),
                right=Side(style="thin", color="D0D7DE"),
                top=Side(style="thin", color="D0D7DE"),
                bottom=Side(style="thin", color="D0D7DE")
            )

            for col_idx in range(1, len(headers) + 1):
                cell = ws.cell(row=1, column=col_idx)
                cell.font = header_font
                cell.fill = header_fill
                cell.alignment = header_align
                cell.border = thin_border
            ws.row_dimensions[1].height = 28

            data_font = Font(name="Segoe UI", size=10)
            id_font = Font(name="Segoe UI", size=10, bold=True, color="0969DA")
            link_font = Font(name="Segoe UI", size=10, color="0969DA", underline="single")

            zebra_fill = PatternFill(start_color="F8FAFC", end_color="F8FAFC", fill_type="solid")
            overdue_fill = PatternFill(start_color="FFDCE0", end_color="FFDCE0", fill_type="solid")
            due_soon_fill = PatternFill(start_color="FFF3C4", end_color="FFF3C4", fill_type="solid")
            closed_fill = PatternFill(start_color="DCFFE4", end_color="DCFFE4", fill_type="solid")

            for row_idx, item in enumerate(items_to_export, start=2):
                wi_id = item.get("id") or ""
                wi_type = item.get("type") or ""
                wi_title = item.get("title") or ""
                wi_state = item.get("state") or ""
                wi_assigned = item.get("assigned_to") or "Unassigned"
                wi_sprint = item.get("sprint_week_name") or item.get("iteration_name") or ""
                wi_iter_path = item.get("iteration_path") or ""
                wi_deadline = item.get("deadline_str") or item.get("target_date") or ""
                wi_urgency = (item.get("urgency_status") or "").lower()
                wi_ms_name = item.get("milestone_name") or item.get("effective_milestone_name") or ""
                wi_ms_cat = item.get("milestone_category") or ""
                wi_l1 = item.get("level1_display") or item.get("level1_title") or ""
                wi_l1_pbs = item.get("level1_pbs") or ""
                wi_l2 = item.get("level2_display") or item.get("level2_title") or ""
                wi_l2_pbs = item.get("level2_pbs") or ""
                wi_prio = item.get("prio_badge") or ("Prio 1" if item.get("is_prio1") else "Standard")
                wi_grouped = "Grouped" if item.get("is_grouped") else "Ungrouped"
                wi_rem = item.get("remaining_work") or 0.0
                wi_comp = item.get("completed_work") or 0.0
                wi_changed = (item.get("changed_date") or "").split("T")[0]
                wi_tfs_url = item.get("tfs_url") or ""

                row_vals = [
                    wi_id,
                    wi_type,
                    wi_title,
                    wi_state,
                    wi_assigned,
                    wi_sprint,
                    wi_iter_path,
                    wi_deadline,
                    wi_urgency.replace("_", " ").title() if wi_urgency else "—",
                    wi_ms_name,
                    wi_ms_cat,
                    wi_l1,
                    wi_l1_pbs,
                    wi_l2,
                    wi_l2_pbs,
                    wi_prio,
                    wi_grouped,
                    wi_rem,
                    wi_comp,
                    wi_changed,
                    wi_tfs_url
                ]
                ws.append(row_vals)
                ws.row_dimensions[row_idx].height = 20

                is_even = (row_idx % 2 == 0)
                for col_idx in range(1, len(headers) + 1):
                    c = ws.cell(row=row_idx, column=col_idx)
                    c.font = data_font
                    c.border = thin_border
                    if is_even:
                        c.fill = zebra_fill

                    if col_idx in (1, 2, 4, 6, 8, 9, 13, 15, 16, 17, 20):
                        c.alignment = Alignment(horizontal="center", vertical="center")
                    elif col_idx in (18, 19):
                        c.alignment = Alignment(horizontal="right", vertical="center")
                    else:
                        c.alignment = Alignment(horizontal="left", vertical="center")

                    if col_idx == 9:
                        if wi_urgency == "overdue":
                            c.fill = overdue_fill
                            c.font = Font(name="Segoe UI", size=10, bold=True, color="9E1C23")
                        elif "due" in wi_urgency:
                            c.fill = due_soon_fill
                            c.font = Font(name="Segoe UI", size=10, bold=True, color="8A6D3B")
                        elif wi_urgency == "completed":
                            c.fill = closed_fill
                            c.font = Font(name="Segoe UI", size=10, color="1B5E20")

                    if col_idx == 21 and wi_tfs_url:
                        c.hyperlink = wi_tfs_url
                        c.font = link_font
                        c.value = "Open TFS"

                ws.cell(row=row_idx, column=1).font = id_font

            for col in ws.columns:
                max_len = 0
                col_letter = get_column_letter(col[0].column)
                for cell in col:
                    val_str = str(cell.value or '')
                    if len(val_str) > max_len:
                        max_len = len(val_str)
                ws.column_dimensions[col_letter].width = min(max(max_len + 4, 11), 60)

            ws.auto_filter.ref = ws.dimensions
            ws.freeze_panes = "A2"

            wb.save(target_path)
            msg = f"Exported {len(items_to_export)} work items to Excel: {target_path}"
            logger.info(msg)
            self.logMessage.emit(f"✅ {msg}")
            return {
                "success": True,
                "file_path": target_path,
                "item_count": len(items_to_export)
            }
        except Exception as e:
            err = f"Failed to export work items to Excel: {e}"
            logger.error(err)
            self.logMessage.emit(f"❌ {err}")
            return {"success": False, "error": str(e)}

    @Slot(list, str, result="QVariantMap")
    @Slot(list, result="QVariantMap")
    @Slot(str, result="QVariantMap")
    @Slot(result="QVariantMap")
    def export_work_items_to_excel(self, items_or_file_path=None, file_path=""):
        """Snake_case alias for exportWorkItemsToExcel."""
        return self.exportWorkItemsToExcel(items_or_file_path, file_path)

    @Slot(result=list)
    def get_milestone_categories(self):
        """Returns all milestone categories."""
        if self._cache_db:
            return self._cache_db.get_milestone_categories()
        return []

    @Slot(str, str, str, str, str, int, result=dict)
    def save_milestone_category(self, cat_id, name, color, bg_color, icon, sort_order=0):
        """Creates or updates a milestone category."""
        if not self._cache_db:
            return {"success": False, "error": "No database connected"}
        clean_name = (name or "").strip()
        if not clean_name:
            return {"success": False, "error": "Category name is required"}
        try:
            c_id = self._cache_db.save_milestone_category(cat_id, clean_name, color, bg_color, icon, sort_order)
            self.milestoneCategoriesChanged.emit()
            self.milestonesChanged.emit()
            self.workloadMatrixChanged.emit()
            return {"success": True, "id": c_id}
        except Exception as e:
            logger.error(f"Error saving milestone category: {e}")
            return {"success": False, "error": str(e)}

    @Slot(str, result=bool)
    def delete_milestone_category(self, cat_id):
        """Deletes a milestone category."""
        if not self._cache_db:
            return False
        res = self._cache_db.delete_milestone_category(cat_id)
        if res:
            self.milestoneCategoriesChanged.emit()
            self.milestonesChanged.emit()
            self.workloadMatrixChanged.emit()
        return res

    @Slot(result=list)
    def get_repo_categories(self):
        """Returns all repo categories from database."""
        if self._cache_db:
            return self._cache_db.get_repo_categories()
        return []

    @Slot(str, str, str, int, bool, result=dict)
    def save_repo_category(self, name, color, bg_color="", sort_order=0, is_default=False):
        """Creates or updates a repository category in the database."""
        if not self._cache_db:
            return {"success": False, "error": "No database connected"}
        clean_name = (name or "").strip()
        if not clean_name:
            return {"success": False, "error": "Category name is required"}
        try:
            res = self._cache_db.save_repo_category(clean_name, color, bg_color, sort_order, is_default)
            if res:
                self.repoCategoriesChanged.emit()
                self._recalculate_repo_categories()
                return {"success": True, "name": clean_name}
            return {"success": False, "error": "Failed to save category"}
        except Exception as e:
            logger.error(f"Error saving repo category: {e}")
            return {"success": False, "error": str(e)}

    @Slot(str, result=bool)
    def delete_repo_category(self, name):
        """Deletes a repository category from database."""
        if not self._cache_db:
            return False
        res = self._cache_db.delete_repo_category(name)
        if res:
            self.repoCategoriesChanged.emit()
            self._recalculate_repo_categories()
        return res

    @Slot(result=list)
    def get_repo_prefix_rules(self):
        """Returns all repo prefix rules."""
        if self._cache_db:
            return self._cache_db.get_repo_prefix_rules()
        return []

    @Slot(str, str, result=dict)
    def save_repo_prefix_rule(self, prefix, category):
        """Creates or updates a repository prefix rule."""
        if not self._cache_db:
            return {"success": False, "error": "No database connected"}
        clean_prefix = (prefix or "").strip()
        clean_cat = (category or "").strip()
        if not clean_prefix or not clean_cat:
            return {"success": False, "error": "Prefix and Category are required"}
        try:
            res = self._cache_db.save_repo_prefix_rule(clean_prefix, clean_cat)
            if res:
                self.repoCategoriesChanged.emit()
                self._recalculate_repo_categories()
                return {"success": True}
            return {"success": False, "error": "Failed to save prefix rule"}
        except Exception as e:
            logger.error(f"Error saving prefix rule: {e}")
            return {"success": False, "error": str(e)}

    @Slot(str, result=bool)
    def delete_repo_prefix_rule(self, prefix):
        """Deletes a repository prefix rule."""
        if not self._cache_db:
            return False
        res = self._cache_db.delete_repo_prefix_rule(prefix)
        if res:
            self.repoCategoriesChanged.emit()
            self._recalculate_repo_categories()
        return res

    @Slot(result=list)
    def get_repo_category_overrides(self):
        """Returns all explicit repo category overrides."""
        if self._cache_db:
            overrides = self._cache_db.get_repo_category_overrides()
            return [{"repo_name": k, "category": v} for k, v in overrides.items()]
        return []

    @Slot(str, str, result=bool)
    def set_repo_category(self, repo_name, category):
        """Sets or updates the category of a specific repository."""
        if not self._cache_db or not repo_name or not category:
            return False
        res = self._cache_db.save_repo_category_override(repo_name, category)
        if res:
            for r in self._repositories:
                if r.get("name") == repo_name:
                    r["category"] = category
            self.repositoriesChanged.emit()
            self.repoCategoriesChanged.emit()
        return res

    @Slot(str, result=bool)
    def delete_repo_category_override(self, repo_name):
        """Removes the explicit category assignment of a repository."""
        if not self._cache_db or not repo_name:
            return False
        res = self._cache_db.delete_repo_category_override(repo_name)
        if res:
            self._recalculate_repo_categories()
            self.repositoriesChanged.emit()
            self.repoCategoriesChanged.emit()
        return res

    @Slot(result=dict)
    def rematch_repo_categories(self):
        """Re-runs repository category matching against database rules for all repositories."""
        if not self._cache_db:
            return {"success": False, "error": "No database connected", "total": 0, "updated": 0}
        try:
            cfg = self._cache_db.get_full_repo_category_config()
            count_updated = 0
            counts_by_cat = {}
            for r in self._repositories:
                rname = r.get("name", "")
                old_cat = r.get("category", "")
                new_cat = utils.categorize_repository(rname, config=cfg, cache_db=self._cache_db)
                if new_cat != old_cat:
                    count_updated += 1
                r["category"] = new_cat
                counts_by_cat[new_cat] = counts_by_cat.get(new_cat, 0) + 1

            self.repositoriesChanged.emit()
            self.repoCategoriesChanged.emit()
            logger.info(f"Rematched {len(self._repositories)} repositories: {count_updated} updated across categories {counts_by_cat}")
            return {
                "success": True,
                "total": len(self._repositories),
                "updated": count_updated,
                "counts": counts_by_cat,
            }
        except Exception as e:
            logger.error(f"Error executing repo category matching: {e}")
            return {"success": False, "error": str(e), "total": 0, "updated": 0}

    def _recalculate_repo_categories(self):
        """Recalculates category property on all cached repositories in memory using current rules."""
        if not self._repositories or not self._cache_db:
            return
        try:
            cfg = self._cache_db.get_full_repo_category_config()
            for r in self._repositories:
                rname = r.get("name", "")
                r["category"] = utils.categorize_repository(rname, config=cfg, cache_db=self._cache_db)
            self.repositoriesChanged.emit()
        except Exception as e:
            logger.error(f"Error recalculating repo categories: {e}")

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

            # 3. Initialize SQLite Cache Database and store project & env configuration
            os.makedirs(os.path.dirname(abs_db_path), exist_ok=True)
            new_cache = AzureDevOpsCache(abs_db_path)
            with new_cache._connection() as conn:
                conn.execute("""
                INSERT INTO projects (id, name, last_synced_at)
                VALUES (?, ?, NULL)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name
                """, (clean_pid, clean_pname))

            base_folder = devops_helper.BASE_FOLDER or os.getcwd()
            deadline_field = self._custom_deadline_field or utils.get_configured_deadline_field() or "Microsoft.VSTS.Scheduling.TargetDate"
            tagday_md = getattr(devops_helper, "TAGDAY_FILE_MD", "TAGDAY.md") or "TAGDAY.md"
            revision_md = getattr(devops_helper, "REVISION_FILE_MD", "REVISION.md") or "REVISION.md"
            artifacts_md = getattr(devops_helper, "BUILD_ARTIFACTS_MD", "BUILD_ARTIFACTS.md") or "BUILD_ARTIFACTS.md"
            artifacts_csv = getattr(devops_helper, "BUILD_ARTIFACTS_CSV", "BUILD_ARTIFACTS.csv") or "BUILD_ARTIFACTS.csv"
            ignore_repos = getattr(devops_helper, "IGNORE_REPOS", "") or ""
            filter_repos = getattr(devops_helper, "FILTER_REPOS", "") or ""
            recent_delay = str(getattr(devops_helper, "RECENT_DELAY", 1440))
            filter_version_tags = str(getattr(devops_helper, "FILTER_VERSION_TAGS_FORMAT", False))

            db_config = {
                "AZURE_BASE_URL": clean_url,
                "AZURE_COLLECTION": clean_col,
                "AZURE_PERSONAL_ACCESS_TOKEN": clean_pat if store_pat else "",
                "AZURE_PROJECT_ID": clean_pid,
                "PROJECT_NAME": clean_pname,
                "AZURE_TEAM": self._tfs_team_name or "",
                "BASE_FOLDER": base_folder,
                "WORK_ITEM_DEADLINE_FIELD": deadline_field,
                "TAGDAY_FILE_MD": tagday_md,
                "REVISION_FILE_MD": revision_md,
                "BUILD_ARTIFACTS_MD": artifacts_md,
                "BUILD_ARTIFACTS_CSV": artifacts_csv,
                "IGNORE_REPOS": ignore_repos,
                "FILTER_REPOS": filter_repos,
                "RECENT_DELAY": recent_delay,
                "FILTER_VERSION_TAGS_FORMAT": filter_version_tags,
                "bug_behavior": self._bug_hierarchy_mode,
            }
            new_cache.set_many_config(db_config)

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

            logger.info(f"Project '{clean_pname}' connected, configuration persisted in DB, and database created successfully: {abs_db_path}")

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
    def _extract_pr_tasks(self, pr, work_items_map=None):
        """Extracts referenced work item tasks from PR title, description, and status_str."""
        if not pr:
            return []

        title = pr.get("title") or ""
        description = pr.get("description") or ""
        status_str = pr.get("status_str") or ""
        raw_json_str = pr.get("raw_json") or ""

        task_ids = set()
        for m in re.finditer(r"#(\d{4,})", f"{title} {description} {status_str}"):
            task_ids.add(int(m.group(1)))

        if raw_json_str and isinstance(raw_json_str, str):
            try:
                raw_meta = json.loads(raw_json_str)
                raw_desc = raw_meta.get("description") or ""
                for m in re.finditer(r"#(\d{4,})", raw_desc):
                    task_ids.add(int(m.group(1)))
            except Exception:
                pass

        # Discard PR ID itself to avoid self-referencing
        pr_id = str(pr.get("pr_id") or "")
        if pr_id and pr_id.isdigit():
            task_ids.discard(int(pr_id))

        if not task_ids:
            return []

        found_map = {}
        wis_map = work_items_map if work_items_map is not None else getattr(self, "_work_items_map", None)
        if wis_map:
            for tid in task_ids:
                if tid in wis_map:
                    found_map[str(tid)] = wis_map[tid]
        elif self._cache_db:
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
        base_url = (devops_helper.AZURE_BASE_URL or "").rstrip("/")
        collection = (devops_helper.AZURE_COLLECTION or "").strip("/")
        project_id = devops_helper.AZURE_PROJECT_ID or ""
        for tid in sorted(task_ids):
            info = found_map.get(str(tid))
            url = f"{base_url}/{collection}/{project_id}/_workitems/edit/{tid}" if (base_url and collection and project_id) else ""
            if info:
                tasks.append({
                    "id": str(info.get("id", tid)),
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

    def _populate_tagday_data(self, td_raw, work_items_map=None):
        """Populates _tagday_data structure and emits tagDayDataChanged."""
        if not td_raw:
            return
        timeline = td_raw.get("all_changes_timeline", [])
        repos_changed = td_raw.get("repos_with_any_changes", {})

        wis_map = work_items_map if work_items_map is not None else getattr(self, "_work_items_map", None)

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

            # Enrich PRs with referenced tasks queried from memory cache or DB
            enriched_prs_after_tag = []
            for p in prs_after_tag:
                p_copy = dict(p)
                p_copy["tasks"] = self._extract_pr_tasks(p_copy, work_items_map=wis_map)
                enriched_prs_after_tag.append(p_copy)

            enriched_active_prs = []
            for p in active_prs:
                p_copy = dict(p)
                p_copy["tasks"] = self._extract_pr_tasks(p_copy, work_items_map=wis_map)
                enriched_active_prs.append(p_copy)

            enriched_all_prs = []
            for p in all_prs:
                p_copy = dict(p)
                p_copy["tasks"] = self._extract_pr_tasks(p_copy, work_items_map=wis_map)
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
        return self._tagday_data
