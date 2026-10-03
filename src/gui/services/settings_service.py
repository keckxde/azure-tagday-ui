# -*- coding: UTF-8 -*-
"""
User settings and configuration persistence service.
"""
import os
import sys
import json
import fnmatch
import logging

logger = logging.getLogger("gui.services.settings")


def get_user_settings_path():
    if getattr(sys, "frozen", False):
        exe_dir = os.path.dirname(sys.executable)
        return os.path.join(exe_dir, "config", "user_settings.yaml")
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "config", "user_settings.yaml"
    )


USER_SETTINGS_PATH = get_user_settings_path()


def _resolve_user_settings_path():
    for mod_name in ("src.gui.backend", "gui.backend", "gui.services.settings_service", "src.gui.services.settings_service"):
        mod = sys.modules.get(mod_name)
        if mod and hasattr(mod, "USER_SETTINGS_PATH"):
            p = getattr(mod, "USER_SETTINGS_PATH")
            if p:
                return p
    return USER_SETTINGS_PATH


def load_user_settings():
    """Loads user configuration from YAML (with fallback to legacy JSON or .yml)."""
    active_path = _resolve_user_settings_path()
    candidates = [
        active_path,
        os.path.join(os.path.dirname(active_path), "user_settings.yml"),
        os.path.join(os.path.dirname(active_path), "user_settings.json"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "config", "user_settings.yml"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "config", "user_settings.json"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "user_settings.yaml"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "user_settings.json"),
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


def save_user_settings(settings):
    """Saves user configuration dictionary to top-level config/user_settings.yaml."""
    active_path = _resolve_user_settings_path()
    try:
        import yaml
        os.makedirs(os.path.dirname(active_path), exist_ok=True)
        with open(active_path, "w", encoding="utf-8") as f:
            yaml.safe_dump(settings, f, default_flow_style=False, sort_keys=False)
    except Exception as e:
        logger.error(f"Failed to save user settings to {active_path}: {e}")


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
    """
    for entry in (tag_categories or []):
        pattern = (entry.get("pattern") or "").strip()
        if not pattern:
            continue
        if fnmatch.fnmatch(tag, pattern):
            return (entry.get("category") or "Other").strip() or "Other"
    return "Other"


def scale_for_font_mode(mode):
    m = (mode or "medium").lower()
    if m == "small":
        return 0.90
    elif m == "large":
        return 1.15
    elif m in ("xlarge", "xl", "extra_large"):
        return 1.30
    return 1.0
