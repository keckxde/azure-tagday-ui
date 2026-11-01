#!/usr/bin/env python3
# -*- coding: UTF-8 -*-
"""
Standalone File-Mirror CLI (`file_mirror_cli.py` / `azure-tagday-mirror`) for unattended
cronjob / systemd timer execution.

Mirrors or clones all active project Git repositories (and recursive submodules) from
TFS / Azure DevOps to a local backup directory in topological order, with:
- Automatic configuration discovery from SQLite project DB (`--db-path`), `user_settings.yaml`, or `.env`
- Lockfile protection (`<target_dir>/.mirror.lock`) to prevent overlapping cron runs
- Standby delta detection (only fetches repositories with new commits unless `--force` is passed)
- Optional chained Forgejo standby push (`--also-sync-forgejo`)
- Timestamped log file output (`<target_dir>/mirror_cron.log`) and non-zero exit codes on failure
"""
import argparse
import json
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Dict, Optional

# Ensure src/ is on sys.path
py_dir = os.path.dirname(os.path.realpath(__file__))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import utils
from azure.azure_db import AzureDevOpsCache
from azure.azure_info_handler import AzureInfoHandler
from azure.migration_service import (
    ForgejoClient,
    ForgejoStandbySyncManager,
    LocalBackupManager,
)

logger = logging.getLogger("azure.file_mirror_cli")


def _is_pid_running(pid: int) -> bool:
    """Checks if a process with the given PID is currently alive."""
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


class MirrorLockFile:
    """
    Context manager managing `<target_dir>/.mirror.lock` to prevent overlapping
    cronjob executions. Automatically cleans up stale lockfiles from dead PIDs.
    """

    def __init__(self, lock_path: str):
        self.lock_path = os.path.abspath(lock_path)
        self.acquired = False

    def __enter__(self) -> "MirrorLockFile":
        os.makedirs(os.path.dirname(self.lock_path), exist_ok=True)
        if os.path.isfile(self.lock_path):
            try:
                with open(self.lock_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                old_pid = int(data.get("pid", 0))
                started = data.get("started_at", "unknown")
                if _is_pid_running(old_pid):
                    logger.warning(
                        "🔒 Another file-mirror job is already running (PID %d, started %s). Skipping this cron run.",
                        old_pid, started,
                    )
                    self.acquired = False
                    return self
                else:
                    logger.info("Removing stale lockfile from dead PID %d (%s)", old_pid, self.lock_path)
            except Exception:
                pass

        payload = {
            "pid": os.getpid(),
            "started_at": datetime.now(timezone.utc).isoformat(),
            "argv": sys.argv,
        }
        with open(self.lock_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        self.acquired = True
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.acquired and os.path.isfile(self.lock_path):
            try:
                os.remove(self.lock_path)
            except OSError:
                pass


def resolve_mirror_configuration(args: argparse.Namespace) -> Dict[str, Any]:
    """
    Resolves TFS connection settings, SQLite cache database, and backup directory
    from CLI arguments -> SQLite `project_config` -> `user_settings.yaml` -> `.env` / environment.
    """
    if getattr(args, "env_file", None):
        utils.load_env_file(args.env_file)

    user_cfg: Dict[str, Any] = {}
    try:
        from gui.services.settings_service import load_user_settings
        user_cfg = load_user_settings() or {}
    except Exception:
        user_cfg = {}

    mig_cfg = user_cfg.get("migration") if isinstance(user_cfg.get("migration"), dict) else {}

    # 1. Resolve SQLite database path
    db_path = (
        getattr(args, "db_path", None)
        or os.getenv("AZURE_DB_PATH")
        or user_cfg.get("db_path")
        or ""
    )
    cache_db: Optional[AzureDevOpsCache] = None
    db_cfg: Dict[str, str] = {}

    if db_path and os.path.isfile(db_path):
        cache_db = AzureDevOpsCache(os.path.abspath(db_path))
        try:
            db_cfg = cache_db.get_all_config() or {}
        except Exception:
            db_cfg = {}
    else:
        try:
            import devops_helper
            default_db_path, cache_db = devops_helper._getDBCacheHandler()
            if cache_db:
                db_path = default_db_path
                db_cfg = cache_db.get_all_config() or {}
        except Exception:
            pass

    # 2. Resolve TFS Base URL, Collection, Project, and PAT
    base_url = (
        getattr(args, "tfs_url", None)
        or db_cfg.get("AZURE_BASE_URL")
        or user_cfg.get("tfs_url")
        or os.getenv("AZURE_BASE_URL")
        or utils.GetEnvVariable("AZURE_BASE_URL", "")
    ).strip().rstrip("/")

    collection = (
        getattr(args, "collection", None)
        or db_cfg.get("AZURE_COLLECTION")
        or user_cfg.get("collection")
        or os.getenv("AZURE_COLLECTION")
        or utils.GetEnvVariable("AZURE_COLLECTION", "DefaultCollection")
    ).strip().strip("/")

    project_id = (
        getattr(args, "project", None)
        or db_cfg.get("PROJECT_NAME")
        or db_cfg.get("AZURE_PROJECT_ID")
        or user_cfg.get("project_id")
        or user_cfg.get("project_name")
        or os.getenv("AZURE_PROJECT_ID")
        or utils.GetEnvVariable("AZURE_PROJECT_ID", "")
    ).strip()

    pat = (
        getattr(args, "pat", None)
        or db_cfg.get("AZURE_PERSONAL_ACCESS_TOKEN")
        or user_cfg.get("pat")
        or os.getenv("AZURE_PERSONAL_ACCESS_TOKEN")
        or utils.GetEnvVariable("AZURE_PERSONAL_ACCESS_TOKEN", "")
    ).strip()

    # Construct full collection URL if collection is not already at the end of base_url
    full_tfs_url = base_url
    if base_url and collection and not base_url.lower().endswith(f"/{collection.lower()}"):
        full_tfs_url = f"{base_url}/{collection}"

    # 3. Resolve Target Directory & Backup Mode
    reports_dir = (
        db_cfg.get("REPORTS_DIR")
        or db_cfg.get("BASE_FOLDER")
        or user_cfg.get("reports_dir")
        or utils.get_reports_dir()
    )
    target_dir = (
        getattr(args, "target_dir", None)
        or os.getenv("AZURE_BACKUP_DIR")
        or mig_cfg.get("backup_target_dir")
        or os.path.join(reports_dir, "backup")
    )
    target_dir = os.path.abspath(target_dir)

    mode = (
        getattr(args, "mode", None)
        or os.getenv("AZURE_BACKUP_MODE")
        or mig_cfg.get("backup_mode")
        or "mirror"
    ).strip().lower()
    if mode not in ("mirror", "worktree", "both"):
        mode = "mirror"

    # 4. Optional Forgejo settings
    forgejo_url = (
        getattr(args, "forgejo_url", None)
        or os.getenv("FORGEJO_URL")
        or mig_cfg.get("forgejo_url")
        or ""
    ).strip().rstrip("/")
    forgejo_token = (
        getattr(args, "forgejo_token", None)
        or os.getenv("FORGEJO_TOKEN")
        or mig_cfg.get("forgejo_token")
        or ""
    ).strip()
    forgejo_org = (
        getattr(args, "forgejo_org", None)
        or os.getenv("FORGEJO_ORG")
        or mig_cfg.get("forgejo_org")
        or project_id
    ).strip()
    forgejo_strategy = (
        getattr(args, "forgejo_strategy", None)
        or mig_cfg.get("forgejo_strategy")
        or "push"
    ).strip().lower()

    raw_timeout = (
        getattr(args, "git_timeout_minutes", None)
        if getattr(args, "git_timeout_minutes", None) is not None
        else mig_cfg.get("git_timeout_minutes", 60)
    )
    try:
        git_timeout_minutes = max(0, int(raw_timeout))
    except (ValueError, TypeError):
        git_timeout_minutes = 60

    return {
        "db_path": db_path,
        "cache_db": cache_db,
        "full_tfs_url": full_tfs_url,
        "project_id": project_id,
        "pat": pat,
        "target_dir": target_dir,
        "mode": mode,
        "git_timeout_minutes": git_timeout_minutes,
        "forgejo_url": forgejo_url,
        "forgejo_token": forgejo_token,
        "forgejo_org": forgejo_org,
        "forgejo_strategy": forgejo_strategy,
    }


def setup_logging(log_file: Optional[str] = None, verbose: bool = False) -> list:
    """Configures console and optional file logging for cron execution."""
    level = logging.DEBUG if verbose else logging.INFO
    fmt = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    handlers: list = [logging.StreamHandler(sys.stdout)]
    if log_file:
        os.makedirs(os.path.dirname(os.path.abspath(log_file)), exist_ok=True)
        handlers.append(logging.FileHandler(log_file, encoding="utf-8"))
    logging.basicConfig(level=level, format=fmt, handlers=handlers, force=True)
    return handlers


def _close_file_handlers(handlers: list) -> None:
    """Closes and detaches any FileHandler instances so log files are not locked on Windows."""
    root_logger = logging.getLogger()
    for h in list(handlers or []):
        if isinstance(h, logging.FileHandler):
            try:
                h.flush()
            except Exception:
                pass
            try:
                root_logger.removeHandler(h)
            except Exception:
                pass
            try:
                h.close()
            except Exception:
                pass


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="file_mirror_cli.py",
        description="Unattended TFS / Azure DevOps Repository File-Mirror CLI (designed for cronjobs & systemd timers).",
    )
    parser.add_argument(
        "--target-dir", "-o",
        type=str,
        default=None,
        help="Target local directory for mirrors/worktrees (default: configured backup_target_dir or <reports_dir>/backup).",
    )
    parser.add_argument(
        "--mode", "-m",
        type=str,
        choices=["mirror", "worktree", "both"],
        default=None,
        help="Backup format mode: 'mirror' (bare git clone --mirror), 'worktree' (checkout + recursive submodules), or 'both' (default: 'mirror' or configured setting).",
    )
    parser.add_argument(
        "--db-path", "-d",
        type=str,
        default=None,
        help="Path to the project SQLite cache DB (e.g. tfs_cache_CH_ELSA.db) to read credentials, repo list, and store migration status.",
    )
    parser.add_argument(
        "--project", "-p",
        type=str,
        default=None,
        help="Override TFS/Azure DevOps Project name (e.g. CH_ELSA).",
    )
    parser.add_argument(
        "--tfs-url",
        type=str,
        default=None,
        help="Override TFS Base URL (e.g. https://tfs.company.com/tfs).",
    )
    parser.add_argument(
        "--collection",
        type=str,
        default=None,
        help="Override TFS Collection name (default: DefaultCollection).",
    )
    parser.add_argument(
        "--pat",
        type=str,
        default=None,
        help="Override TFS Personal Access Token.",
    )
    parser.add_argument(
        "--env-file", "-e",
        type=str,
        default=None,
        help="Optional path to a .env file to load before running.",
    )
    parser.add_argument(
        "--force", "-f",
        action="store_true",
        help="Force git remote update/fetch on all repositories even if last_push_id has not changed.",
    )
    parser.add_argument(
        "--offline-cache",
        action="store_true",
        help="Use cached repository list from SQLite without querying TFS REST API for new repositories.",
    )
    parser.add_argument(
        "--also-sync-forgejo",
        action="store_true",
        help="Also push/sync all mirrored repositories to the configured local Forgejo instance after local backup.",
    )
    parser.add_argument(
        "--forgejo-url",
        type=str,
        default=None,
        help="Override Forgejo base URL when using --also-sync-forgejo.",
    )
    parser.add_argument(
        "--forgejo-token",
        type=str,
        default=None,
        help="Override Forgejo API token when using --also-sync-forgejo.",
    )
    parser.add_argument(
        "--forgejo-org",
        type=str,
        default=None,
        help="Override Forgejo Organization name when using --also-sync-forgejo.",
    )
    parser.add_argument(
        "--forgejo-strategy",
        type=str,
        choices=["push", "pull_mirror"],
        default=None,
        help="Forgejo sync strategy ('push' or 'pull_mirror').",
    )
    parser.add_argument(
        "--log-file", "-l",
        type=str,
        default=None,
        help="Path to append log output (defaults to <target-dir>/mirror_cron.log unless --no-log-file is set).",
    )
    parser.add_argument(
        "--no-log-file",
        action="store_true",
        help="Log only to stdout/stderr without creating <target-dir>/mirror_cron.log.",
    )
    parser.add_argument(
        "--lock-file",
        type=str,
        default=None,
        help="Custom lockfile path (defaults to <target-dir>/.mirror.lock).",
    )
    parser.add_argument(
        "--git-timeout-minutes",
        type=int,
        default=None,
        help="Per-step Git timeout in minutes (0 = unlimited, default: 60).",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable debug-level logging.",
    )
    return parser


def run_mirror_job(args: argparse.Namespace) -> int:
    """
    Executes the file-mirror job and returns an OS exit code:
    - `0`: Success (or skipped because another instance holds the lock)
    - `1`: Configuration error or one or more repositories failed to mirror
    """
    cfg = resolve_mirror_configuration(args)
    target_dir = cfg["target_dir"]
    os.makedirs(target_dir, exist_ok=True)

    log_file = None
    if not getattr(args, "no_log_file", False):
        log_file = getattr(args, "log_file", None) or os.path.join(target_dir, "mirror_cron.log")
    active_handlers = setup_logging(log_file=log_file, verbose=getattr(args, "verbose", False))

    try:
        lock_path = getattr(args, "lock_file", None) or os.path.join(target_dir, ".mirror.lock")
        with MirrorLockFile(lock_path) as lock:
            if not lock.acquired:
                return 0

            project_id = cfg["project_id"]
            full_tfs_url = cfg["full_tfs_url"]
            pat = cfg["pat"]
            cache_db = cfg["cache_db"]
            mode = cfg["mode"]

            if not project_id:
                logger.error("No project_id configured. Pass --project <NAME> or --db-path <DB>.")
                return 1

            info_handler: Optional[AzureInfoHandler] = None
            if full_tfs_url and pat and not getattr(args, "offline_cache", False):
                info_handler = AzureInfoHandler(full_tfs_url, pat)

            logger.info(
                "=== TFS File-Mirror Job Started [project=%s, mode=%s, target=%s, db=%s] ===",
                project_id, mode, target_dir, cfg["db_path"] or "none",
            )

            timeout_min = cfg.get("git_timeout_minutes", 60)
            timeout_sec = timeout_min * 60 if timeout_min > 0 else 0

            mgr = LocalBackupManager(
                target_dir=target_dir,
                mode=mode,
                info_handler=info_handler,
                project_id=project_id,
                pat=pat,
                cache_db=cache_db,
                git_timeout_seconds=timeout_sec,
            )
            manifest = mgr.backup_all_repositories(force=bool(getattr(args, "force", False)))

            exit_code = 0 if manifest.get("failed_count", 0) == 0 else 1

            if getattr(args, "also_sync_forgejo", False):
                fg_url = cfg["forgejo_url"]
                fg_token = cfg["forgejo_token"]
                fg_org = cfg["forgejo_org"] or project_id
                fg_strat = cfg["forgejo_strategy"] or "push"
                if not fg_url:
                    logger.error("--also-sync-forgejo requested, but no Forgejo URL is configured.")
                    return 1
                fg_client = ForgejoClient(url=fg_url, token=fg_token)
                sync_mgr = ForgejoStandbySyncManager(
                    forgejo_client=fg_client,
                    org_name=fg_org,
                    strategy=fg_strat,
                    backup_dir=target_dir,
                    info_handler=info_handler,
                    project_id=project_id,
                    tfs_pat=pat,
                    cache_db=cache_db,
                )
                fg_res = sync_mgr.sync_all_repositories(force=bool(getattr(args, "force", False)))
                if fg_res.get("failed_count", 0) > 0:
                    exit_code = 1

            logger.info("=== TFS File-Mirror Job Finished (exit_code=%d) ===", exit_code)
            return exit_code
    finally:
        _close_file_handlers(active_handlers)


def main():
    parser = build_arg_parser()
    args = parser.parse_args()
    sys.exit(run_mirror_job(args))


if __name__ == "__main__":
    main()

