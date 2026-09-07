# -*- coding: UTF-8 -*-
import logging, re, os
import json
from dotenv import load_dotenv
from datetime import datetime, timedelta
load_dotenv(verbose=True)


log = logging.getLogger('azure')

# Return a list with unique values (removing double entries)
def uniqueList(list):
    output = []
    for x in list:
        x = x.strip()
        if x not in output:
            output.append(x)
    return output

def MatchUniqueRegularExpr(pattern, source):
    if source == None :
        log.error(f"no source given with pattern {pattern}")
    list = []
    try:
        list = re.findall(pattern,source)
    except:
        log.error(f"error with regex {pattern} {source}")

    return uniqueList(list)

def parseJSONFile(filename):
    try:
        log.info(f"open {filename}")
        with open(filename, encoding="utf-8") as f:
            jsonObj = json.load(f)
            keys = jsonObj.keys()
            log.info(f"   found {len(keys)} entries")
            return jsonObj
    except:
        log.error(f"error parsing JSON File {filename}")
    return None

def GetEnvVariable(name, default=None):
    myVar = os.getenv(name)
    if not myVar:
        if default:
            log.warning(f"Optional Env-Variable missing {name} - use default {default}\nPlease add to your `.env` file:")
            log.info(f"{name}={default}")
            return default
        log.error(f"Mandatory Env-Variable missing {name}\nPlease add to your `.env` file:")
        log.info(f"{name}=value")
        return ""
    return myVar
        

def parse_iso_datetime(date_str):
    """
    Parses an ISO format datetime string into a datetime object.
    Strips timezones and milliseconds for naive UTC comparison.

    Args:
        date_str (str/datetime): The input date string or datetime object.

    Returns:
        datetime: Naive datetime object or None if parsing fails.
    """
    if not date_str:
        return None
    if isinstance(date_str, datetime):
        return date_str
    try:
        # Normalize the string: remove Z, replace T with space, remove ms if any
        s = date_str.replace("Z", "").replace("T", " ")
        if "." in s:
            s = s.split(".")[0]
        # Ignore timezone offset for naive comparison in UTC
        if "+" in s:
            s = s.split("+")[0]
        return datetime.strptime(s.strip(), "%Y-%m-%d %H:%M:%S")
    except Exception:
        try:
            return datetime.fromisoformat(date_str.replace("Z", "+00:00"))
        except Exception:
            return None

def UpdateDateString(date_val):
    """
    Converts a datetime object or date string into a unified format string "%Y-%m-%d %H:%M:%S".

    Args:
        date_val (str/datetime): The input date value.

    Returns:
        str: Formatted date string, or empty string if invalid.
    """
    if not date_val:
        return ""
    dt = parse_iso_datetime(date_val) if isinstance(date_val, str) else date_val
    if not dt:
        return ""
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def parse_semver_tuple(tag_name):
    """
    Parses a tag or version string like 'v01.02.2632' or 'v1.2.3' into an integer tuple (major, minor, patch)
    for semantic sorting, comparison, and version analysis.
    Returns (0, 0, 0) if parsing fails or input is empty/None.

    Args:
        tag_name (str/tuple): The tag or version string to parse.

    Returns:
        tuple[int, int, int]: (major, minor, patch)
    """
    if not tag_name:
        return (0, 0, 0)
    if isinstance(tag_name, (tuple, list)):
        return tuple(tag_name)
    cleaned = str(tag_name).strip().lstrip("vV")
    parts = cleaned.split(".")
    nums = []
    for p in parts:
        m = re.search(r"^\d+", p)
        if m:
            nums.append(int(m.group(0)))
        else:
            nums.append(0)
    while len(nums) < 3:
        nums.append(0)
    return tuple(nums[:3])


def parseYAMLFile(filename):
    """
    Parses a YAML configuration file.

    Args:
        filename (str): Path to YAML file.

    Returns:
        dict/list: Parsed YAML data, or None if reading/parsing fails.
    """
    try:
        import yaml
        if not os.path.exists(filename):
            log.warning(f"YAML file not found: {filename}")
            return None
        with open(filename, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
            log.info(f"Loaded YAML file {filename}")
            return data
    except Exception as e:
        log.error(f"Error parsing YAML file {filename}: {e}")
        return None


def load_status_icons(section=None, custom_path=None):
    """
    Locates and loads status icon mappings from YAML configuration.
    Falls back to safe defaults if file is not found or cannot be parsed.

    Args:
        section (str, optional): Section to retrieve (e.g. 'build_status', 'artifact_status', 'tagday_status').
                                 If None, returns all sections.
        custom_path (str, optional): Explicit file path to status_icons.yaml.

    Returns:
        dict: Mapping of status names to icon strings.
    """
    default_icons = {
        "build_status": {
            "succeeded": ":octicons-check-circle-16:{ .green } Succeeded",
            "failed": ":octicons-x-circle-16:{ .red } Failed",
            "partiallySucceeded": ":octicons-alert-16:{ .yellow } Partially Succeeded",
            "canceled": ":octicons-circle-slash-16:{ .grey } Canceled",
        },
        "artifact_status": {
            "active": ":octicons-package-16: { .green } Active",
            "deleted": ":material-delete-empty: { .red } Deleted",
        },
        "tagday_status": {
            "completed_pr": ":octicons-check-circle-16:",
            "active_pr": ":octicons-git-pull-request-16:",
            "unmerged_branch": ":octicons-git-branch-16:",
        },
    }

    config = None
    if custom_path and os.path.exists(custom_path):
        config = parseYAMLFile(custom_path)

    if not config:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        candidates = [
            os.path.join(os.path.dirname(current_dir), "config", "status_icons.yaml"),
            os.path.join(os.path.dirname(current_dir), "config", "status_icons.yml"),
            os.path.join(current_dir, "config", "status_icons.yaml"),
            os.path.join(os.path.dirname(current_dir), "status_icons.yaml"),
            os.path.join(current_dir, "status_icons.yaml"),
            os.path.join(os.path.dirname(os.path.dirname(current_dir)), "scripts", "config", "status_icons.yaml"),
            os.path.join(os.path.dirname(os.path.dirname(current_dir)), "config", "status_icons.yaml"),
        ]
        for c in candidates:
            if os.path.exists(c):
                config = parseYAMLFile(c)
                if config:
                    break

    if not config or not isinstance(config, dict):
        config = default_icons

    if section:
        return config.get(section, default_icons.get(section, {}))
    return config


def load_repo_categories(custom_path=None):
    """
    Locates and loads repository category mappings from YAML configuration.
    Falls back to safe default prefix rules if file is not found.

    Args:
        custom_path (str, optional): Explicit file path to repo_categories.yaml.

    Returns:
        tuple: (config_dict, resolved_file_path)
    """
    default_config = {
        "default_category": "OTHERS",
        "prefix_rules": {
            "generic-": "GENERIC",
            "3rdparty-": "3RDPARTY",
        },
        "repositories": {},
        "category_colors": {
            "CORE": "#1f6feb",
            "CORE APPS": "#238636",
            "GENERIC": "#6e40c9",
            "3RDPARTY": "#d29922",
            "OTHERS": "#6e7681",
        },
    }

    resolved_path = None
    config = None

    if custom_path and os.path.exists(custom_path):
        resolved_path = custom_path
        config = parseYAMLFile(custom_path)

    if not config:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        candidates = [
            os.path.join(os.path.dirname(current_dir), "config", "repo_categories.yaml"),
            os.path.join(os.path.dirname(current_dir), "config", "repo_categories.yml"),
            os.path.join(current_dir, "config", "repo_categories.yaml"),
            os.path.join(os.path.dirname(current_dir), "repo_categories.yaml"),
            os.path.join(current_dir, "repo_categories.yaml"),
            os.path.join(os.path.dirname(os.path.dirname(current_dir)), "scripts", "config", "repo_categories.yaml"),
            os.path.join(os.path.dirname(os.path.dirname(current_dir)), "config", "repo_categories.yaml"),
        ]
        for c in candidates:
            if os.path.exists(c):
                config = parseYAMLFile(c)
                if config:
                    resolved_path = c
                    break

    if not config or not isinstance(config, dict):
        config = default_config
        if not resolved_path:
            # Set default target path to scripts/config/repo_categories.yaml if existing
            current_dir = os.path.dirname(os.path.abspath(__file__))
            default_target = os.path.join(os.path.dirname(current_dir), "config", "repo_categories.yaml")
            resolved_path = default_target

    if "default_category" not in config:
        config["default_category"] = "OTHERS"
    if "prefix_rules" not in config:
        config["prefix_rules"] = default_config["prefix_rules"]
    if "repositories" not in config:
        config["repositories"] = {}
    if "category_colors" not in config:
        config["category_colors"] = default_config["category_colors"]

    return config, resolved_path


def get_category_color(category, config=None, config_path=None):
    """
    Returns the hex color code for a repository category from configuration.

    Args:
        category (str): Category name (e.g. 'CORE', 'GENERIC', 'OTHERS').
        config (dict, optional): Parsed repo_categories configuration.
        config_path (str, optional): Custom path to repo_categories.yaml.

    Returns:
        str: Hex color code (e.g. '#1f6feb'). Defaults to '#6e7681' (gray).
    """
    if config is None:
        config, _ = load_repo_categories(custom_path=config_path)

    colors = config.get("category_colors", {}) if isinstance(config, dict) else {}
    if category in colors:
        return colors[category]
    return colors.get("OTHERS", "#6e7681")


def save_repo_categories(config, file_path):
    """
    Saves repository categories configuration dictionary to a YAML file.

    Args:
        config (dict): Configuration dictionary to persist.
        file_path (str): Destination file path.

    Returns:
        bool: True if save succeeded, False otherwise.
    """
    try:
        import yaml
        os.makedirs(os.path.dirname(os.path.abspath(file_path)), exist_ok=True)
        with open(file_path, "w", encoding="utf-8") as f:
            yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False)
        log.info(f"Saved repository categories to {file_path}")
        return True
    except Exception as e:
        log.error(f"Error saving YAML configuration to {file_path}: {e}")
        return False


def categorize_repository(repo_name, config=None, config_path=None):
    """Categorizes repository using the repo_categories configuration file.

    Evaluation order:
    1. Explicit repository mapping (`repositories: { <repo_name>: <category> }`).
    2. Prefix rules (`prefix_rules: { <prefix>: <category> }`).
    3. Default category fallback (`default_category`, defaults to 'OTHERS').
    """
    if config is None:
        config, _ = load_repo_categories(custom_path=config_path)

    default_cat = config.get("default_category", "OTHERS")
    repo_map = config.get("repositories", {})
    prefix_rules = config.get("prefix_rules", {})

    # 1. Explicit mapping
    if repo_name in repo_map:
        return repo_map[repo_name]

    # 2. Prefix rules
    for prefix, cat in prefix_rules.items():
        if repo_name.startswith(prefix):
            return cat

    # 3. Default category fallback
    return default_cat


def sort_categories_for_report(active_categories, known_order=None):
    """
    Sorts category names for report presentation:
    known order first, then any remaining categories alphabetically, with 'OTHERS' at the end.

    Args:
        active_categories (Iterable[str]): Categories present in the dataset.
        known_order (Optional[List[str]]): Specific priority order. Defaults to standard repository groups.

    Returns:
        List[str]: Ordered category names.
    """
    if known_order is None:
        known_order = ["CORE", "CORE APPS", "GENERIC", "BUILD & SCRIPTS", "3RDPARTY"]

    active_set = set(active_categories)
    ordered = [c for c in known_order if c in active_set]
    for c in sorted(active_set):
        if c not in ordered and c != "OTHERS":
            ordered.append(c)
    if "OTHERS" in active_set:
        ordered.append("OTHERS")
    elif not ordered:
        ordered = ["OTHERS"]
    return ordered


def parse_sprint_week(iteration_str):
    """
    Parses a sprint name or path matching 'week-YYWW' (e.g. 'week-2633', 'week-2615-stable').

    Args:
        iteration_str (str): The iteration name or path.

    Returns:
        tuple: (year (int), week (int), base_name (str)) or (None, None, None) if not matched.
    """
    if not iteration_str or not isinstance(iteration_str, str):
        return None, None, None

    # Match 4-digit year: 'sprint-2026-W30' or 'week-2026-33'
    m_full = re.search(r'\b(?:week|sprint)[-_]?(\d{4})[-_]?[wW]?(\d{1,2})\b', iteration_str, re.IGNORECASE)
    if m_full:
        yyyy = int(m_full.group(1))
        ww = int(m_full.group(2))
        if 2000 <= yyyy <= 2099 and 1 <= ww <= 53:
            return yyyy, ww, f"week-{str(yyyy)[-2:]}{ww:02d}"

    # Match 'week-YYWW' or 'week_YYWW' or 'Sprint-YYWW'
    m = re.search(r'\b(?:week|sprint)[-_]?(\d{2})(\d{2})\b', iteration_str, re.IGNORECASE)
    if m:
        yy = int(m.group(1))
        ww = int(m.group(2))
        year = 2000 + yy if yy < 100 else yy
        if 1 <= ww <= 53:
            return year, ww, f"week-{yy:02d}{ww:02d}"

    # Also match 4-digit '2633' if surrounded by word boundaries
    m2 = re.search(r'\b(\d{2})(\d{2})\b', iteration_str)
    if m2:
        yy = int(m2.group(1))
        ww = int(m2.group(2))
        if 20 <= yy <= 50 and 1 <= ww <= 53:
            year = 2000 + yy
            return year, ww, f"week-{yy:02d}{ww:02d}"

    return None, None, None


def get_sprint_date_range(year, week):
    """
    Calculates start (Monday) and end (Friday) dates for an ISO calendar sprint week.

    Args:
        year (int): Calendar year (e.g. 2026).
        week (int): Calendar week (1-53).

    Returns:
        tuple: (start_date (date), end_date (date), start_str (YYYY-MM-DD), end_str (YYYY-MM-DD))
    """
    try:
        from datetime import date
        start_d = date.fromisocalendar(year, week, 1)  # Monday
        end_d = date.fromisocalendar(year, week, 5)    # Friday
        return start_d, end_d, start_d.strftime("%Y-%m-%d"), end_d.strftime("%Y-%m-%d")
    except Exception:
        return None, None, "", ""


def format_sprint_range_label(year, week):
    """
    Formats a user-friendly label for a weekly sprint (e.g. 'week-2633 (Aug 10 – Aug 14)').
    """
    start_d, end_d, _, _ = get_sprint_date_range(year, week)
    if not start_d or not end_d:
        return f"week-{str(year)[-2:]}{week:02d}"
    
    start_fmt = start_d.strftime("%b %d")
    end_fmt = end_d.strftime("%b %d") if start_d.month == end_d.month else end_d.strftime("%b %d")
    return f"week-{str(year)[-2:]}{week:02d} ({start_fmt} – {end_fmt})"


def calculate_deadline_urgency(deadline_val, is_completed=False, now_dt=None):
    """
    Calculates urgency status, badge text, and color for a work item deadline.

    Args:
        deadline_val (str/datetime/date): The target deadline date.
        is_completed (bool): Whether the work item is resolved/closed.
        now_dt (datetime/date, optional): Reference date. Defaults to current date.

    Returns:
        dict: {
            "status": "completed"|"overdue"|"due_this_week"|"due_next_week"|"future"|"none",
            "days_diff": int or None,
            "badge_text": str,
            "badge_color": str,
            "deadline_str": str
        }
    """
    if is_completed:
        d_str = ""
        if deadline_val:
            if isinstance(deadline_val, str):
                d_str = deadline_val.split("T")[0].split(" ")[0]
            elif hasattr(deadline_val, "strftime"):
                d_str = deadline_val.strftime("%Y-%m-%d")
        return {
            "status": "completed",
            "days_diff": None,
            "badge_text": "✓ Closed",
            "badge_color": "#3fb950",
            "deadline_str": d_str
        }

    if not deadline_val:
        return {
            "status": "none",
            "days_diff": None,
            "badge_text": "—",
            "badge_color": "#8b949e",
            "deadline_str": ""
        }

    from datetime import date, datetime
    target_d = None
    if isinstance(deadline_val, date) and not isinstance(deadline_val, datetime):
        target_d = deadline_val
    elif isinstance(deadline_val, datetime):
        target_d = deadline_val.date()
    elif isinstance(deadline_val, str):
        dt = parse_iso_datetime(deadline_val)
        if dt:
            target_d = dt.date()
        else:
            try:
                target_d = datetime.strptime(deadline_val.split("T")[0].split(" ")[0], "%Y-%m-%d").date()
            except Exception:
                target_d = None

    if not target_d:
        return {
            "status": "none",
            "days_diff": None,
            "badge_text": "—",
            "badge_color": "#8b949e",
            "deadline_str": str(deadline_val)
        }

    ref_d = now_dt.date() if isinstance(now_dt, datetime) else (now_dt or date.today())
    days_diff = (target_d - ref_d).days
    deadline_str = target_d.strftime("%Y-%m-%d")

    if days_diff < 0:
        overdue_days = abs(days_diff)
        return {
            "status": "overdue",
            "days_diff": days_diff,
            "badge_text": f"🚨 {overdue_days}d Overdue" if overdue_days < 99 else "🚨 Overdue",
            "badge_color": "#f85149",
            "deadline_str": deadline_str
        }
    elif days_diff == 0:
        return {
            "status": "due_this_week",
            "days_diff": 0,
            "badge_text": "⚡ Due Today",
            "badge_color": "#d29922",
            "deadline_str": deadline_str
        }
    elif days_diff <= 7:
        return {
            "status": "due_this_week",
            "days_diff": days_diff,
            "badge_text": f"⏳ {days_diff}d left",
            "badge_color": "#d29922",
            "deadline_str": deadline_str
        }
    elif days_diff <= 14:
        return {
            "status": "due_next_week",
            "days_diff": days_diff,
            "badge_text": f"📅 Next Wk ({target_d.strftime('%b %d')})",
            "badge_color": "#388bfd",
            "deadline_str": deadline_str
        }
    else:
        return {
            "status": "future",
            "days_diff": days_diff,
            "badge_text": f"📅 {target_d.strftime('%b %d')}",
            "badge_color": "#8b949e",
            "deadline_str": deadline_str
        }

