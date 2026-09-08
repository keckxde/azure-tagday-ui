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
    if myVar:
        return myVar

    # Check user_settings or DB project_config fallback
    try:
        cfg_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "user_settings.yaml")
        if not os.path.exists(cfg_path):
            cfg_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "user_settings.json")
        if os.path.exists(cfg_path):
            if cfg_path.endswith(".json"):
                with open(cfg_path, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
            else:
                import yaml
                with open(cfg_path, "r", encoding="utf-8") as f:
                    cfg = yaml.safe_load(f)
            if isinstance(cfg, dict):
                mapping = {
                    "AZURE_BASE_URL": cfg.get("tfs_url"),
                    "AZURE_COLLECTION": cfg.get("collection"),
                    "AZURE_PERSONAL_ACCESS_TOKEN": cfg.get("pat"),
                    "AZURE_PROJECT_ID": cfg.get("project_id") or cfg.get("project_name"),
                }
                if mapping.get(name):
                    return mapping[name]
                db_p = cfg.get("db_path")
                if db_p and os.path.exists(db_p):
                    from azure.azure_db import AzureDevOpsCache
                    db = AzureDevOpsCache(db_p)
                    val = db.get_config(name)
                    if val is not None and val != "":
                        return val
    except Exception:
        pass

    if default:
        log.warning(f"Optional Env-Variable missing {name} - use default {default}\nPlease add to your `.env` file:")
        log.info(f"{name}={default}")
        return default
    log.error(f"Mandatory Env-Variable missing {name}\nPlease add to your `.env` file:")
    log.info(f"{name}=value")
    return ""
        

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


def load_repo_categories(cache_db=None, custom_path=None):
    """
    Locates and loads repository category mappings from the database cache or YAML configuration.
    Falls back to safe default prefix rules if database or file is not found.

    Args:
        cache_db (AzureDevOpsCache, optional): Database instance containing repo category tables.
        custom_path (str, optional): Explicit file path to repo_categories.yaml.

    Returns:
        tuple: (config_dict, resolved_file_path)
    """
    if cache_db and hasattr(cache_db, "get_full_repo_category_config"):
        try:
            db_cfg = cache_db.get_full_repo_category_config()
            if db_cfg and db_cfg.get("category_colors"):
                return db_cfg, "database"
        except Exception:
            pass

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


def get_category_color(category, config=None, cache_db=None, config_path=None):
    """
    Returns the hex color code for a repository category from database configuration or YAML.

    Args:
        category (str): Category name (e.g. 'CORE', 'GENERIC', 'OTHERS').
        config (dict, optional): Parsed repo_categories configuration.
        cache_db (AzureDevOpsCache, optional): Cache database instance.
        config_path (str, optional): Custom path to repo_categories.yaml.

    Returns:
        str: Hex color code (e.g. '#1f6feb'). Defaults to '#6e7681' (gray).
    """
    if config is None:
        config, _ = load_repo_categories(cache_db=cache_db, custom_path=config_path)

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


def categorize_repository(repo_name, config=None, cache_db=None, config_path=None):
    """Categorizes repository using the database configuration or repo_categories configuration file.

    Evaluation order:
    1. Explicit repository mapping (`repositories: { <repo_name>: <category> }`).
    2. Prefix rules (`prefix_rules: { <prefix>: <category> }`).
    3. Default category fallback (`default_category`, defaults to 'OTHERS').
    """
    if config is None:
        config, _ = load_repo_categories(cache_db=cache_db, custom_path=config_path)

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


def get_configured_deadline_field():
    """
    Returns custom configured TFS deadline field name from environment, or default empty string.
    """
    return os.getenv("WORK_ITEM_DEADLINE_FIELD", "").strip()


def extract_work_item_deadline(fields_dict, custom_field=None):
    """
    Extracts deadline/target date from a TFS work item fields dictionary.

    Prioritizes:
    1. Explicitly configured custom_field or WORK_ITEM_DEADLINE_FIELD (if set).
    2. Microsoft.VSTS.Scheduling.TargetDate
    3. Microsoft.VSTS.Scheduling.DueDate
    4. Microsoft.VSTS.Scheduling.FinishDate

    Args:
        fields_dict (dict): The work item fields map.
        custom_field (str, optional): Custom field attribute name to check first.

    Returns:
        tuple: (deadline_date_str, matched_field_name)
    """
    if not isinstance(fields_dict, dict):
        return "", ""

    cfg_field = (custom_field or get_configured_deadline_field()).strip()
    if cfg_field and fields_dict.get(cfg_field):
        return str(fields_dict[cfg_field]).strip(), cfg_field

    standard_fields = [
        "Microsoft.VSTS.Scheduling.TargetDate",
        "Microsoft.VSTS.Scheduling.DueDate",
        "Microsoft.VSTS.Scheduling.FinishDate",
        "Custom.Deadline",
        "Custom.TargetDate",
        "Custom.MilestoneDeadline"
    ]

    for f_name in standard_fields:
        val = fields_dict.get(f_name)
        if val:
            return str(val).strip(), f_name

    return "", ""


def normalize_pbs_number(tag):
    """
    Normalizes a PBS tag string for numeric comparison by replacing wildcard 'x' or 'X'
    characters with '0' within each numeric segment.

    Rules:
    - Only 'x'/'X' characters that appear inside a numeric token are replaced.
    - Non-numeric tokens (e.g. 'PBS', 'SYS', 'A') are left unchanged.
    - Separator characters ('.', '-', '_') are preserved.

    Examples:
        "10xx"     -> "1000"
        "1.2.xx"   -> "1.2.00"
        "PBS-01"   -> "PBS-01"   (non-numeric prefix unchanged)
        "SYS-A_1x" -> "SYS-A_10"
        "10xx.xx"  -> "1000.00"

    Args:
        tag (str): Raw PBS tag string extracted from brackets.

    Returns:
        str: Normalized tag string with 'x'/'X' replaced by '0' in numeric segments.
    """
    if not tag:
        return tag

    def _normalize_token(tok):
        # A token is "numeric" if all characters are digits or x/X (e.g. "10xx", "xx", "01")
        if tok and re.match(r'^[0-9xX]+$', tok):
            return tok.replace('x', '0').replace('X', '0')
        return tok

    # Split by separators but keep them
    parts = re.split(r'([.\-_])', tag)
    return "".join(_normalize_token(p) if idx % 2 == 0 else p for idx, p in enumerate(parts))


def pbs_sort_key(tag):
    """
    Converts a PBS tag string into a comparable sort key tuple.
    'x'/'X' wildcards are first normalized to '0' via normalize_pbs_number.
    Each numeric segment becomes an int; non-numeric segments become lowercase strings.

    Examples:
        "10xx"     -> (1000,)
        "1.2.3"    -> (1, 2, 3)
        "PBS-01"   -> ("pbs", 1)
        "SYS-A_1x" -> ("sys", "a", 10)

    Args:
        tag (str): Raw or normalized PBS tag string.

    Returns:
        tuple: Mixed int/str tuple suitable for use as a sort key.
    """
    normalized = normalize_pbs_number(tag or "")
    parts = re.split(r'[.\-_]', normalized)
    key = []
    for p in parts:
        if not p:
            continue
        try:
            key.append(int(p))
        except ValueError:
            key.append(p.lower())
    return tuple(key) if key else ("",)


def parse_pbs_tag(title):
    """
    Parses a Product Breakdown Structure (PBS) tag from the start of a title.
    Expected syntax: [<PBS Number>] <Name>
    Example: "[PBS-01] Powertrain Subsystem" -> ("PBS-01", "Powertrain Subsystem", ("pbs", 1))
    Example: "[1.2.3] Engine Control"        -> ("1.2.3",  "Engine Control",       (1, 2, 3))
    Example: "[10xx] Chassis"                -> ("10xx",   "Chassis",              (1000,))

    'x'/'X' wildcards in numeric segments are treated as '0' for the sort key only;
    the original tag string is preserved unchanged for display purposes.

    Args:
        title (str): The work item title string.

    Returns:
        tuple: (pbs_tag, clean_name, sort_key)
               pbs_tag  (str)   – original tag as written in brackets
               clean_name (str) – title text after the bracket expression
               sort_key (tuple) – comparable key for sorting; x/X treated as 0
    """
    if not title:
        return "", "", ("",)
    s_title = str(title).strip()
    m = re.match(r"^\s*\[([^\]]+)\]\s*(.*)$", s_title)
    if m:
        tag = m.group(1).strip()
        name = m.group(2).strip()
        return tag, name, pbs_sort_key(tag)
    return "", s_title, ("",)


def parse_level3_priority(title):
    """
    Parses Level 3 (User Story / Requirement / Bug) strategic focus prioritization notation.
    Syntax: [<Type>_<Number>] <Name>
    Supported focus types: OI, MP, SCEN, SPEC, PA, CS, DOC.
    These are classified as Prio 1 Focus items.

    Args:
        title (str): The work item title string.

    Returns:
        dict: Priority classification metadata.
    """
    if not title:
        return {
            "is_prio1": False,
            "prio_category": "standard",
            "prio_type": "",
            "prio_number": "",
            "prio_tag": "",
            "prio_badge": "",
            "clean_title": ""
        }

    s_title = str(title).strip()
    pattern = r"^\s*\[(OI|MP|SCEN|SPEC|PA|CS|DOC)_([^\]]+)\]\s*(.*)$"
    m = re.match(pattern, s_title, re.IGNORECASE)
    if m:
        p_type = m.group(1).upper()
        p_num = m.group(2).strip()
        p_tag = f"[{p_type}_{p_num}]"
        clean = m.group(3).strip()
        return {
            "is_prio1": True,
            "prio_category": "prio1",
            "prio_type": p_type,
            "prio_number": p_num,
            "prio_tag": p_tag,
            "prio_badge": f"⭐ Prio 1 {p_tag}",
            "clean_title": clean
        }

    return {
        "is_prio1": False,
        "prio_category": "standard",
        "prio_type": "",
        "prio_number": "",
        "prio_tag": "",
        "prio_badge": "",
        "clean_title": s_title
    }


def get_work_item_level(wi_type, bug_hierarchy_mode="like_user_story"):
    """
    Determines the Backlog hierarchy level (1 to 4) of a work item type:
    Level 1: Epic (Sub-Systems)
    Level 2: Feature (Major Components)
    Level 3: User Story / Requirement / Product Backlog Item / Bug (if bug is story)
    Level 4: Task / Bug (if bug is task)

    Args:
        wi_type (str): The Work Item Type string.
        bug_hierarchy_mode (str): 'like_user_story' or 'like_task'.

    Returns:
        int: Level (1, 2, 3, or 4).
    """
    t = (wi_type or "").strip().lower()
    if t == "epic":
        return 1
    if t == "feature":
        return 2
    if t in ("user story", "requirement", "product backlog item", "story"):
        return 3
    if t in ("bug", "defect", "problem"):
        return 3 if bug_hierarchy_mode == "like_user_story" else 4
    if t in ("task",):
        return 4
    return 3


def resolve_work_item_hierarchy(wi, all_wis_by_id, bug_hierarchy_mode="like_user_story", max_depth=10):
    """
    Walks up the parent_id chain of a work item to resolve Level 1 (Epic), Level 2 (Feature),
    Level 3 (Story/Requirement/Bug), PBS tags, grouping status, and Prio 1 focus priority.

    Args:
        wi (dict): The target work item dict (must contain 'id', 'type', 'title', 'parent_id').
        all_wis_by_id (dict): Lookup map of work items by integer ID.
        bug_hierarchy_mode (str): 'like_user_story' or 'like_task'.
        max_depth (int): Max hierarchy walk depth to prevent circular link hangs.

    Returns:
        dict: Resolved hierarchy and priority metadata.
    """
    curr_id = wi.get("id")
    curr_type = wi.get("type") or "Task"
    curr_title = wi.get("title") or f"#{curr_id}"
    curr_level = get_work_item_level(curr_type, bug_hierarchy_mode=bug_hierarchy_mode)

    # Initialize hierarchy tracking
    level_items = {1: None, 2: None, 3: None, 4: None}
    level_items[curr_level] = wi

    # Walk upwards
    visited = {curr_id}
    parent_id = wi.get("parent_id")
    depth = 0

    while parent_id and depth < max_depth:
        p_item = all_wis_by_id.get(parent_id)
        if not p_item or p_item.get("id") in visited:
            break
        visited.add(p_item.get("id"))
        p_level = get_work_item_level(p_item.get("type"), bug_hierarchy_mode=bug_hierarchy_mode)
        if p_level < curr_level and not level_items[p_level]:
            level_items[p_level] = p_item
        parent_id = p_item.get("parent_id")
        depth += 1

    # Extract Level 1 info (Epic / Sub-System)
    l1_item = level_items[1]
    l1_id = l1_item.get("id") if l1_item else None
    l1_title = l1_item.get("title") if l1_item else ""
    l1_pbs, l1_name, l1_sort_key = parse_pbs_tag(l1_title) if l1_title else ("", "", ("",))
    l1_display = f"[{l1_pbs}] {l1_name}" if (l1_pbs and l1_name) else (f"#{l1_id} {l1_title}" if l1_title else "")

    # Extract Level 2 info (Feature / Major Component)
    l2_item = level_items[2]
    l2_id = l2_item.get("id") if l2_item else None
    l2_title = l2_item.get("title") if l2_item else ""
    l2_pbs, l2_name, l2_sort_key = parse_pbs_tag(l2_title) if l2_title else ("", "", ("",))
    l2_display = f"[{l2_pbs}] {l2_name}" if (l2_pbs and l2_name) else (f"#{l2_id} {l2_title}" if l2_title else "")

    # Extract Level 3 info
    l3_item = level_items[3]
    l3_id = l3_item.get("id") if l3_item else (curr_id if curr_level == 3 else None)
    l3_title = l3_item.get("title") if l3_item else (curr_title if curr_level == 3 else "")

    # Check Grouping Rule:
    # A work item is Grouped if Level 1 and Level 2 parents exist AND both have valid PBS syntax [<PBS Number>] <Name>
    is_grouped = bool(l1_pbs and l2_pbs)
    grouping_status = "grouped" if is_grouped else "ungrouped"

    # Check Level 3 Prioritization:
    # Evaluate Level 3 title for [<Type>_<Number>] (OI, MP, SCEN, SPEC, PA, CS, DOC)
    prio_info = parse_level3_priority(l3_title if l3_title else curr_title)

    return {
        "level": curr_level,
        "level1_id": l1_id,
        "level1_title": l1_title,
        "level1_pbs": l1_pbs,
        "level1_pbs_sort_key": l1_sort_key,
        "level1_name": l1_name,
        "level1_display": l1_display or "Ungrouped Sub-System",
        "level2_id": l2_id,
        "level2_title": l2_title,
        "level2_pbs": l2_pbs,
        "level2_pbs_sort_key": l2_sort_key,
        "level2_name": l2_name,
        "level2_display": l2_display or "Ungrouped Component",
        "level3_id": l3_id,
        "level3_title": l3_title,
        "is_grouped": is_grouped,
        "grouping_status": grouping_status,
        "is_prio1": prio_info["is_prio1"],
        "prio_category": prio_info["prio_category"],
        "prio_type": prio_info["prio_type"],
        "prio_number": prio_info["prio_number"],
        "prio_tag": prio_info["prio_tag"],
        "prio_badge": prio_info["prio_badge"],
        "clean_title": prio_info["clean_title"],
    }


def extract_target_milestone_tags(tags_val):
    """
    Extracts target milestone short names from work item tags formatted as Target:<TargetShortName>.
    Case-insensitive matching of the 'Target:' prefix. Semicolon and comma delimiters are supported.

    Examples:
        "Target:DDQS-01; Backend; Prio1" -> ["DDQS-01"]
        "Target:QIAV-02; Target:Release_1.0" -> ["QIAV-02", "Release_1.0"]

    Args:
        tags_val (str, list, or None): The raw tags string or list of tag strings.

    Returns:
        list of str: Unique TargetShortName strings in appearance order.
    """
    if not tags_val:
        return []
    if isinstance(tags_val, list):
        tags_list = tags_val
    else:
        tags_list = [t.strip() for t in re.split(r'[;,]', str(tags_val)) if t.strip()]

    results = []
    for tag in tags_list:
        m = re.match(r"^Target\s*:\s*(.+)$", tag, re.IGNORECASE)
        if m:
            short_name = m.group(1).strip()
            if short_name and short_name not in results:
                results.append(short_name)
    return results


def match_work_item_to_milestone(wi, all_milestones, milestones_by_date=None):
    """
    Identifies the target milestone for a work item.
    Matching precedence:
    1. Work item tags formatted as Target:<TargetShortName> matching a milestone by name.
    2. Exact date matching against the milestone target_date.

    Args:
        wi (dict): Work item dictionary.
        all_milestones (list of dict): Configured milestones list.
        milestones_by_date (dict, optional): Map of target_date (YYYY-MM-DD) -> milestone dict.

    Returns:
        dict or None: The matched milestone dictionary, or None if no match.
    """
    if not all_milestones or not wi:
        return None

    # 1. Tag-based matching
    target_tags = wi.get("target_tags")
    if target_tags is None:
        raw_tags = wi.get("tags") or ""
        if not raw_tags and wi.get("raw_json"):
            try:
                raw_data = json.loads(wi["raw_json"]) if isinstance(wi["raw_json"], str) else wi["raw_json"]
                fields = raw_data.get("fields", {}) if isinstance(raw_data, dict) else {}
                raw_tags = fields.get("System.Tags") or fields.get("Tags") or ""
            except Exception:
                raw_tags = ""
        target_tags = extract_target_milestone_tags(raw_tags)

    if target_tags:
        for t_name in target_tags:
            t_lower = t_name.lower().strip()
            # Exact name or Target: prefixed name
            for m in all_milestones:
                m_name = (m.get("name") or "").lower().strip()
                if m_name == t_lower or m_name == f"target:{t_lower}":
                    return m
                if m_name.startswith("target:") and m_name.split("target:", 1)[1].strip() == t_lower:
                    return m
            # Substring name matching
            for m in all_milestones:
                m_name = (m.get("name") or "").lower().strip()
                if t_lower in m_name or m_name in t_lower:
                    return m

    # 2. Date-based matching (fallback)
    wi_deadline = (wi.get("deadline_str") or wi.get("target_date") or "").split("T")[0].split(" ")[0].strip()
    if wi_deadline:
        if milestones_by_date is not None:
            return milestones_by_date.get(wi_deadline)
        for m in all_milestones:
            if (m.get("target_date") or "").strip() == wi_deadline:
                return m

    return None


