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
