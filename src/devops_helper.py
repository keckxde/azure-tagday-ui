# -*- coding: UTF-8 -*-
import os
import sys
import re
import copy
import json
import logging
from datetime import datetime
from typing import Tuple, Dict, Any, List, Optional, Union
from jinja2 import Template

# Add current py directory to sys.path so we can import local modules
py_dir = os.path.dirname(os.path.realpath(__file__))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

import utils
from azure import AzureInfoHandler, AzureDevOpsCache

logger = logging.getLogger(__name__)

# Determine BASE_FOLDER based on where .env is located
cwd = os.getcwd()
BASE_FOLDER = os.getenv("BASE_FOLDER", cwd)

logger.info("Use BASE_FOLDER: %s", BASE_FOLDER)

# Load env variables using the wrapper
AZURE_BASE_URL = utils.GetEnvVariable('AZURE_BASE_URL')
AZURE_COLLECTION = utils.GetEnvVariable('AZURE_COLLECTION')
AZURE_PERSONAL_ACCESS_TOKEN = utils.GetEnvVariable('AZURE_PERSONAL_ACCESS_TOKEN')
AZURE_PROJECT_ID = utils.GetEnvVariable("AZURE_PROJECT_ID")
IGNORE_REPOS = os.getenv('IGNORE_REPOS', '')

TAGDAY_FILE_MD = utils.GetEnvVariable('TAGDAY_FILE_MD',"TAGDAY.md")
REVISION_FILE_MD = utils.GetEnvVariable('REVISION_FILE_MD',"REVISION.md")
BUILD_ARTIFACTS_MD = utils.GetEnvVariable('BUILD_ARTIFACTS_MD',"BUILD_ARTIFACTS.md")
BUILD_ARTIFACTS_CSV = utils.GetEnvVariable('BUILD_ARTIFACTS_CSV',"BUILD_ARTIFACTS.csv")   

RECENT_DELAY_raw = os.getenv('RECENT_DELAY')
RECENT_DELAY = int(RECENT_DELAY_raw) if RECENT_DELAY_raw else 60 * 24

FILTER_VERSION_TAGS_FORMAT_raw = os.getenv('FILTER_VERSION_TAGS_FORMAT', 'False')
FILTER_VERSION_TAGS_FORMAT = FILTER_VERSION_TAGS_FORMAT_raw.lower() == 'true'

FILTER_REPOS = os.getenv('FILTER_REPOS', '')

def ThroughDirectory(directory, ext=".md"):
    """
    Recursively scans a directory for files matching the specified extension,
    excluding build and VCS directories (e.g., build-*, node_modules, .git, __pycache__).

    Args:
        directory (str): Root directory path to walk.
        ext (str, optional): Target file extension. Defaults to ".md".

    Returns:
        list: Absolute or relative file paths matching the extension.
    """
    files = []
    for root, dirs, filenames in os.walk(directory):
        # Filter directories in-place to avoid searching inside them
        dirs[:] = [d for d in dirs if not (d.startswith("build-") or d in ("node_modules", ".git", "__pycache__", "pycache"))]
        for filename in filenames:
            if filename.endswith(ext):
                files.append(os.path.join(root, filename))
    return files

def ParseMarkdown(directory_name, extension=".md"):
    """
    .. deprecated::
        Deprecated: Scanning markdown files for referenced work item numbers (#\\d{6})
        and pull requests (!\\d{5,}) is replaced by direct database synchronization
        via `azHandler.sync_work_items()` using TFS API WIQL queries.

    Parses markdown files in the specified directory to extract work item IDs
    (matching #\\d{6}) and pull request IDs (matching !\\d{5,}).

    Args:
        directory_name (str): Directory containing markdown files to parse.
        extension (str, optional): File extension to scan. Defaults to ".md".

    Returns:
        dict: Dictionary with keys 'tasks' (list of work item ID strings)
              and 'prs' (list of pull request ID strings).
    """
    import warnings
    warnings.warn(
        "ParseMarkdown is deprecated. Work item sync now queries the TFS API directly via WIQL.",
        DeprecationWarning,
        stacklevel=2,
    )
    files = ThroughDirectory(directory_name, extension)
    task_ids = {}
    prs = {}
    for file in files:
        try:
            with open(file, 'r', encoding='utf-8') as f:
                contents = f.read()
        except Exception as e:
            logger.error(f"Error reading file {file}: {e}")
            continue
            
        tasks = re.findall(r"#\d{6}", contents, re.IGNORECASE)
        for t in tasks:
            id_val = t[1:]
            task_ids[id_val] = t
            
        prs_found = re.findall(r"!\d{5,}", contents, re.IGNORECASE)
        for p in prs_found:
            id_val = p[1:]
            prs[id_val] = int(id_val)
            
    result = {
        "tasks": list(task_ids.keys()),
        "prs": list(prs.keys())
    }
    logger.info(f"Parsed {len(files)} Markdown Files")
    logger.info(f"-- Found {len(result['tasks'])} workitems")
    logger.info(f"-- Found {len(result['prs'])} Pull-Requests")
    return result

def exportReposToMarkdown(aRepos, templateFile, exportFile):
    """
    .. deprecated::
        Deprecated: Direct template rendering of repository metadata to markdown
        is deprecated. Dedicated report generators (e.g., tagday, storage) are used instead.

    Renders a dictionary of repositories into a markdown file using a Jinja2 template.

    Args:
        aRepos (dict): Dictionary of repository data keyed by repository ID or name.
        templateFile (str): Path to the Jinja2 template file.
        exportFile (str): Path to write the rendered markdown output.
    """
    import warnings
    warnings.warn(
        "exportReposToMarkdown is deprecated.",
        DeprecationWarning,
        stacklevel=2,
    )
    resolved_template = templateFile
    if not os.path.exists(resolved_template):
        # Try finding relative to BASE_FOLDER / scripts
        resolved_template = os.path.join(BASE_FOLDER, "scripts", templateFile.lstrip("./"))
    if not os.path.exists(resolved_template):
        # Try finding relative to script's parent folder
        resolved_template = os.path.join(os.path.dirname(py_dir), templateFile.lstrip("./"))
        
    try:
        with open(resolved_template, "r", encoding="utf-8") as f:
            strTemplate = f.read()
        
        template = Template(strTemplate)
        keys = sorted(aRepos.keys())
        strRendered = template.render(project=AZURE_PROJECT_ID, repos=aRepos, keys=keys)
        
        with open(exportFile, "w", encoding="utf-8") as f:
            f.write(strRendered)
        logger.info(f"Rendered Template {resolved_template} -> {exportFile}")
    except Exception as err:
        logger.error(f"Could not Render Template {resolved_template} -> {exportFile}: {err}")

def addCategoriesToRepos(repos, config_path=None, cache_db=None, auto_save_missing=True):
    """
    Classifies all repositories in the provided repository dictionary and assigns a `category` attribute
    to each repository using repository categories stored in the database or `repo_categories.yaml`.

    Evaluation order:
    1. Explicit mapping in `repositories` (e.g. `repo1` -> `Group1`).
    2. Prefix rules defined in `prefix_rules` (e.g. `prefix1-` -> `Group1`, `prefix2-` -> `Group2`).
    3. Default category fallback (`default_category`, defaults to "OTHERS").

    If a repository is not listed in `repositories` in the configuration, it is automatically
    classified and added to the configuration mapping. If `auto_save_missing` is True, newly discovered
    entries are saved to the database (if cache_db is provided) or the configuration file.

    Args:
        repos (dict): Dictionary of repositories keyed by repository ID or name.
                      Each repository entry is expected to be a dict containing an "info" dict with "name",
                      or have a "name" attribute directly.
        config_path (str, optional): Explicit path to `repo_categories.yaml`. If None,
                                     searches standard configuration locations.
        cache_db (AzureDevOpsCache, optional): Cache database instance.
        auto_save_missing (bool, optional): If True, automatically persists newly discovered
                                            repositories to database / config. Defaults to True.

    Returns:
        dict: The updated `repos` dictionary with the "category" attribute populated for each repository.
    """
    # Load config: prefer DB directly, fall back to YAML only when no cache_db
    if cache_db and hasattr(cache_db, "get_full_repo_category_config"):
        try:
            config = cache_db.get_full_repo_category_config()
            resolved_path = "database"
        except Exception:
            config = None
            resolved_path = None
    else:
        config = None
        resolved_path = None

    if not config:
        config, resolved_path = utils.load_repo_categories(cache_db=cache_db, custom_path=config_path)

    default_cat = config.get("default_category", "OTHERS")
    prefix_rules = config.get("prefix_rules", {})
    repo_map = config.get("repositories", {})

    missing_repos = {}
    keys = sorted(repos.keys())

    for key in keys:
        repo = repos[key]
        repo_name = ""
        if isinstance(repo, dict):
            repo_name = repo.get("info", {}).get("name", "") if isinstance(repo.get("info"), dict) else ""
            if not repo_name:
                repo_name = repo.get("name", "")
        if not repo_name:
            repo_name = str(key)

        # Categorize using centralized categorization rule
        if repo_name in repo_map:
            category = repo_map[repo_name]
        else:
            category = utils.categorize_repository(repo_name, config=config, cache_db=cache_db)
            if repo_name not in repo_map:
                missing_repos[repo_name] = category
            logger.debug(f"Categorized repository '{repo_name}' as '{category}'")

        repos[key]["category"] = category

    # Persist newly discovered repositories
    if missing_repos and auto_save_missing:
        if cache_db and resolved_path == "database":
            # Save to DB override table — keep YAML untouched
            try:
                for rname, rcat in missing_repos.items():
                    cache_db.save_repo_category_override(rname, rcat)
                logger.debug(f"Saved {len(missing_repos)} new repo categories to database")
            except Exception as e:
                logger.warning(f"Could not save new repo categories to database: {e}")
        elif resolved_path and resolved_path != "database":
            # Legacy YAML path (CLI usage without DB)
            config["repositories"] = {**repo_map, **missing_repos}
            utils.save_repo_categories(config, resolved_path)

    return repos

def prepareReposForTagDay(aRepos, aType="unstable"):
    _repos = copy.deepcopy(aRepos)
    keys = sorted(_repos.keys())
    for key in keys:
        repo = _repos[key]
        repo_name = repo.get("info", {}).get("name", "")
        
        logger.info(f"repo {repo_name}")
        if IGNORE_REPOS and repo_name in IGNORE_REPOS:
            _repos.pop(key)
            logger.info(f"repo {repo_name} ignored")
            continue
            
        repo_has_newer_branches = False
        repo_has_dev_pushes_after_tag = False
        
        branches = repo.get("branches", [])
        for branch_idx in range(len(branches) - 1, -1, -1):
            branch = branches[branch_idx]
            stats = branch.get("stats") or branch.get("Stats")
            if stats:
                ahead_count = stats.get("aheadCount", 0)
                if ahead_count == 0:
                    branches.pop(branch_idx)
                elif ahead_count > 0:
                    if branch.get("FriendlyName") == "dev":
                        logger.warning(f" -- repo {repo_name} has a wrong default branch!!")
                    if aType == "unstable":
                        if branch.get("FriendlyName") in ("main", "dev"):
                            branches.pop(branch_idx)
                            continue
                    logger.info(f" -- branch {repo_name}/{branch.get('FriendlyName')} is still ahead by {ahead_count}!")
                    repo_has_newer_branches = True
            else:
                branches.pop(branch_idx)
                continue

        prs_after_tag = [] 
        if len(repo.get("devPRs", [])) > 0:
            latest_tag_date = repo.get("LatestTag",{}).get("CommitDateObj")
            for push_meta in repo.get("devPRs", []):
                if latest_tag_date and push_meta["creationDateStr"] > latest_tag_date:
                    prs_after_tag.append(push_meta)
            if len(prs_after_tag) >0: 
                logger.info(f" -- repo {repo_name}/dev has {len(repo['devPRs'])} pushes after last tag!")
                repo_has_dev_pushes_after_tag = True
                _repos[key]["prs_after_tag"] = prs_after_tag
            
        if not repo_has_newer_branches and not repo_has_dev_pushes_after_tag:
            _repos.pop(key)
            
    return _repos

def isFileRecent(filePath):
    if os.path.exists(filePath):
        mtime = os.path.getmtime(filePath)
        delay_seconds = RECENT_DELAY * 60
        is_newer = (datetime.now().timestamp() - mtime) < delay_seconds
        return is_newer
    return False

def _getHandler():
    global AZURE_BASE_URL, AZURE_COLLECTION, AZURE_PERSONAL_ACCESS_TOKEN, AZURE_PROJECT_ID
    base_url = AZURE_BASE_URL or os.getenv('AZURE_BASE_URL', '')
    collection = AZURE_COLLECTION or os.getenv('AZURE_COLLECTION', 'DefaultCollection')
    pat = AZURE_PERSONAL_ACCESS_TOKEN or os.getenv('AZURE_PERSONAL_ACCESS_TOKEN', '')
    project_id = AZURE_PROJECT_ID or os.getenv('AZURE_PROJECT_ID', '')

    if not base_url or not pat or not project_id:
        missing = []
        if not base_url: missing.append("AZURE_BASE_URL / TFS URL")
        if not pat: missing.append("AZURE_PERSONAL_ACCESS_TOKEN / PAT")
        if not project_id: missing.append("AZURE_PROJECT_ID / Project")
        logger.warning(f"Azure DevOps / TFS client cannot be created - missing parameters: {', '.join(missing)}")
        return None
            
    logger.info(f"get additional information from TFS {base_url}/{collection} {project_id}")
    
    azure_url = f"{base_url}/{collection}" if collection else base_url
    return AzureInfoHandler(azure_url, pat)
    
def _getDBCacheHandler() -> Tuple[str, AzureDevOpsCache]:
    """
    Create and return the database file path and AzureDevOpsCache instance.

    Returns:
        Tuple[str, AzureDevOpsCache]: Database file path and connected cache client.
    """
    global AZURE_PROJECT_ID
    project_id = AZURE_PROJECT_ID or os.getenv("AZURE_PROJECT_ID", "default")
    db_path = os.path.join(BASE_FOLDER, f"tfs_cache_{project_id}.db")
    return db_path, AzureDevOpsCache(db_path)


SCHEMATIC_BRACKETED_PATTERN: re.Pattern = re.compile(r'\[([A-Za-z]{2,15})[_\-\s](\d+)\]')
SCHEMATIC_NAMED_PATTERN: re.Pattern = re.compile(
    r'\b(OI|OIL|MP|SCENARIO|REQ|TASK|BUG|FEATURE|CR|WI)[_\-\s]?(\d+)\b',
    re.IGNORECASE
)


def extract_schematics_from_text(text: Optional[str]) -> List[str]:
    """
    Extracts [<TYPE>_<NR>] schematics from text (e.g. [OI_171], [OIL_45], [MP_01], [SCENARIO_12]).

    Matches both bracketed tags (e.g. '[OI_171]', '[MP-02]') and standard named schematics
    (e.g. 'OI-171', 'OI_171', 'OI 171', 'SCENARIO-12').

    Args:
        text (Optional[str]): Source text (title, description, or comment).

    Returns:
        List[str]: List of standardized schematic tags in '[<TYPE>_<NR>]' format.
    """
    if not text:
        return []
    schematics: List[str] = []
    # 1. Bracketed tags: [TYPE_NR], [TYPE-NR], [TYPE NR]
    for m in SCHEMATIC_BRACKETED_PATTERN.finditer(text):
        t_type = m.group(1).upper()
        t_nr = m.group(2)
        tag = f"[{t_type}_{t_nr}]"
        if tag not in schematics:
            schematics.append(tag)
    # 2. Known schematic types: OI-123, OIL_45, MP 1, SCENARIO-2
    for m in SCHEMATIC_NAMED_PATTERN.finditer(text):
        t_type = m.group(1).upper()
        t_nr = m.group(2)
        tag = f"[{t_type}_{t_nr}]"
        if tag not in schematics:
            schematics.append(tag)
    return schematics


VERSION_TITLE_PATTERN = re.compile(r'^v?\d+(?:\.\d+)+([-_\.][a-zA-Z0-9_\-\.]+)?$', re.IGNORECASE)


def is_version_title(title: Optional[str]) -> bool:
    """
    Checks if a PR title consists solely of a version reference (e.g. 'v1.02.2632',
    'v0.10.24', '1.02.2632', or TFS merge messages like 'Merged PR 27375: v0.10.24').

    Args:
        title (Optional[str]): The PR title string to evaluate.

    Returns:
        bool: True if the title represents only a version reference, False otherwise.
    """
    if not title:
        return False
    t = title.strip()
    # Strip TFS automatic merge PR prefixes if present
    t = re.sub(r'^(?:Merged\s+PR\s+\d+:\s*)+', '', t, flags=re.IGNORECASE).strip()
    return bool(VERSION_TITLE_PATTERN.match(t))


def patch_pr_title_for_release_notes(
    pr: Union[dict, Any, str],
    cache_db: Optional[AzureDevOpsCache] = None,
    default_title: Optional[str] = None
) -> str:
    """
    Patches a Pull Request title for Release Notes by enforcing [<TYPE>_<NR>] prefix schematics
    (e.g., [OI_171], [OIL_45], [MP_01], [SCENARIO_12]) discovered in referenced work items
    (titles or descriptions) or within the PR metadata itself.

    Args:
        pr (Union[dict, Any, str]): A PR dictionary/Row containing 'title', 'id'/'pr_id',
            'description', 'raw_json', or directly a PR title string.
        cache_db (Optional[AzureDevOpsCache]): Cache database instance. If None, retrieves
            via _getDBCacheHandler().
        default_title (Optional[str]): Fallback title if pr is passed without title.

    Returns:
        str: Patched PR title with enforced [<TYPE>_<NR>] prefix.
    """
    pr_dict: Dict[str, Any] = {}
    if isinstance(pr, str):
        title = pr
    elif hasattr(pr, "keys"):
        pr_dict = dict(pr)
        title = default_title or pr_dict.get("title") or ""
    else:
        title = default_title or (str(pr) if pr is not None else "")

    orig_title: str = title
    title = title.strip()
    if not title:
        return orig_title

    # Do not patch PR titles that are only version references (e.g., v1.02.2632, v0.10.24)
    if is_version_title(title):
        return orig_title

    desc: str = pr_dict.get("description") or ""
    raw_json_str = pr_dict.get("raw_json") or ""
    raw_meta: Dict[str, Any] = {}
    if raw_json_str and isinstance(raw_json_str, str):
        try:
            raw_meta = json.loads(raw_json_str)
            if not desc:
                desc = raw_meta.get("description") or ""
        except Exception:
            pass
    elif isinstance(raw_json_str, dict):
        raw_meta = raw_json_str
        if not desc:
            desc = raw_meta.get("description") or ""

    # 1. Find referenced work item IDs
    combined_text: str = f"{title} {desc}"
    wi_ids: set = set()

    for k in ("work_items", "work_item_ids", "referenced_work_items"):
        for val in pr_dict.get(k) or []:
            try:
                if isinstance(val, dict):
                    wi_ids.add(int(val.get("id") or val.get("workItemId")))
                else:
                    wi_ids.add(int(val))
            except (ValueError, TypeError):
                pass

    for m in re.findall(r'#(\d{4,7})', combined_text):
        wi_ids.add(int(m))
    for m in re.findall(r'\b(?:task|workitem|wi|issue|bug)\s*[:#]?\s*(\d{4,7})\b', combined_text, re.IGNORECASE):
        wi_ids.add(int(m))

    for k in ("workItemRefs", "workItems"):
        items = raw_meta.get(k) or []
        for item in items:
            if isinstance(item, dict) and item.get("id"):
                try:
                    wi_ids.add(int(item["id"]))
                except (ValueError, TypeError):
                    pass

    # 2. Query work items and search for schematics
    if cache_db is None:
        try:
            _, cache_db = _getDBCacheHandler()
        except Exception:
            cache_db = None

    found_schematics: List[str] = []
    if cache_db:
        for wid in sorted(wi_ids):
            wi = cache_db.get_work_item(wid)
            if wi:
                wi_title = wi.get("title") or ""
                wi_desc = ""
                wi_raw = wi.get("raw_json") or ""
                if wi_raw and isinstance(wi_raw, str):
                    try:
                        wi_meta = json.loads(wi_raw)
                        wi_desc = wi_meta.get("fields", {}).get("System.Description", "") or ""
                    except Exception:
                        pass
                found_schematics.extend(extract_schematics_from_text(wi_title))
                found_schematics.extend(extract_schematics_from_text(wi_desc))

    # Also search in the PR's own title and description
    found_schematics.extend(extract_schematics_from_text(combined_text))

    # Deduplicate while preserving order
    unique_schematics: List[str] = list(dict.fromkeys(found_schematics))
    if not unique_schematics:
        return orig_title

    # 3. Enforce [<TYPE>_<NR>] as prefix to the PR title and remove other references of <TYPE> or <NR>
    patched: str = title
    for s in unique_schematics:
        t_type, t_nr = s.strip("[]").split("_")
        patterns = [
            # In parentheses or brackets: (OI-171), [OI_171], (OI171)
            rf'\s*\([_\-\s]*{t_type}[_\-\s]?{t_nr}[_\-\s]*\)\s*',
            rf'\s*\[[_\-\s]*{t_type}[_\-\s]?{t_nr}[_\-\s]*\]\s*',
            # Standalone or prefixed: OI-171:, OI 171 -, OI_171, OI171
            rf'\b{t_type}[_\-\s]?{t_nr}\b[:\s\-]*',
            # Number references: (#171), [#171], #171
            rf'\s*\([#\s]*{t_nr}\)\s*',
            rf'\s*\[[#\s]*{t_nr}\]\s*',
            rf'(?:\b(?:task|workitem|wi|issue|bug)\s*[:#]?\s*|#){t_nr}\b[:\s\-]*',
        ]
        for p in patterns:
            patched = re.sub(p, ' ', patched, flags=re.IGNORECASE)

    # Remove references to the work item IDs that were discovered
    for wid in sorted(wi_ids, reverse=True):
        wid_str = str(wid)
        patterns = [
            rf'\s*\([#\s]*{wid_str}\)\s*',
            rf'\s*\[[#\s]*{wid_str}\]\s*',
            rf'(?:\b(?:task|workitem|wi|issue|bug)\s*[:#]?\s*|#){wid_str}\b[:\s\-]*',
        ]
        for p in patterns:
            patched = re.sub(p, ' ', patched, flags=re.IGNORECASE)

    # Clean up empty brackets and whitespace / punctuation leftovers
    patched = re.sub(r'\(\s*\)', ' ', patched)
    patched = re.sub(r'\[\s*\]', ' ', patched)
    patched = re.sub(r'\s+', ' ', patched).strip()
    patched = re.sub(r'^[:\s\-\/|,]+', '', patched).strip()
    patched = re.sub(r'[:\s\-\/|,]+$', '', patched).strip()
    patched = re.sub(r'\s*/\s*/\s*', ' / ', patched)

    if not patched and cache_db:
        # Fallback to work item title if PR title contained only the reference
        for wid in sorted(wi_ids):
            wi = cache_db.get_work_item(wid)
            if wi and wi.get("title"):
                cand = wi.get("title")
                for s in unique_schematics:
                    t_type, t_nr = s.strip("[]").split("_")
                    cand = re.sub(rf'\b{t_type}[_\-\s]?{t_nr}\b[:\s\-]*', ' ', cand, flags=re.IGNORECASE)
                cand = re.sub(r'^[:\s\-\/|,]+', '', cand.strip()).strip()
                cand = re.sub(r'[:\s\-\/|,]+$', '', cand).strip()
                if cand:
                    patched = cand
                    break

    prefix_str: str = " ".join(unique_schematics)
    final_title: str = f"{prefix_str} {patched}".strip() if patched else prefix_str
    if final_title != orig_title:
        pr_id_val = pr_dict.get("pull_request_id") or pr_dict.get("id") or pr_dict.get("pr_id")
        pr_label = f"PR #{pr_id_val}: " if pr_id_val else "PR: "
        logger.warning(f"{pr_label}title patched '{orig_title}' -> '{final_title}'")
    return final_title


def check_artifacts():
    azHandler = _getHandler()
    if not azHandler:
        logger.warning("No handler available for check_artifacts")
        return []
    db_path, cache_db = _getDBCacheHandler()
    builds = azHandler.get_all_build_artifacts(AZURE_PROJECT_ID, cache_db=cache_db)
    logger.info(f"Processed and cached {len(builds)} builds with artifacts into {db_path}")
    return builds

def check_pipelines():
    azHandler = _getHandler()
    if not azHandler:
        logger.warning("No handler available for check_pipelines")
        return []
    db_path, cache_db = _getDBCacheHandler()
    pipelines = azHandler.GetTFSPipelines(AZURE_PROJECT_ID)
    if pipelines and cache_db:
        cache_db.save_pipelines(AZURE_PROJECT_ID, pipelines)
    logger.info(f"Cached {len(pipelines)} pipelines into {db_path}")
    return pipelines    

def main(run_templates: bool = False) -> None:
    """Entry point for devops sync operations. Does not generate reports by default."""
    sync(run_templates_flag=run_templates)

def sync(force_sync=False, run_templates_flag=False, progress_callback=None):
    """
    Synchronizes repositories, branches, tags, PRs, and work items from TFS to SQLite.

    Args:
        force_sync (bool): If True, bypass file recency checks and force a full sync. Defaults to False.
        run_templates_flag (bool): If True, render Tag Day templates after sync. Defaults to False.
        progress_callback (callable, optional): Optional callback for live progress updates.
    """
    azHandler = _getHandler()
    if not azHandler:
        error_msg = (
            "Cannot perform Azure DevOps / TFS synchronization: Azure/TFS client could not be initialized. "
            "Please configure AZURE_BASE_URL, AZURE_COLLECTION, AZURE_PERSONAL_ACCESS_TOKEN, "
            "and AZURE_PROJECT_ID in your .env file or Settings."
        )
        logger.error(error_msg)
        raise RuntimeError(error_msg)

    repos_all = {}
    
    db_path, cache_db = _getDBCacheHandler()
    if not force_sync and isFileRecent(db_path):
        logger.info(f"Read Repo Details from SQLite Database Cache {db_path}")
        try:
            repos_all = cache_db.get_all_cached_repositories(AZURE_PROJECT_ID)
        except Exception as e:
            logger.error(f"Error reading from SQLite cache: {e}")
            
    if not repos_all:
        logger.info("Read Repo Details from TFS and update SQLite cache")
        repos_all = azHandler.GetTFSRepositories(
            AZURE_PROJECT_ID,
            filter_version_tags_format=FILTER_VERSION_TAGS_FORMAT,
            filter_repos=FILTER_REPOS,
            cache_db=cache_db
        )
        try:
            # Force update of DB file mtime so it is marked recent
            os.utime(db_path, None)
        except Exception:
            pass
                
    last_synced = None
    try:
        last_synced = cache_db.get_project_last_synced(AZURE_PROJECT_ID)
    except Exception as e:
        logger.error(f"Error querying last sync time: {e}")

    if not force_sync and last_synced:
        delay_seconds = RECENT_DELAY * 60
        is_newer = (datetime.now() - last_synced).total_seconds() < delay_seconds
        if is_newer:
            logger.info("TFS state was recently synced. Skipping task/PR updates.")
            return
        
    # Sync all work items with TFS API directly without needing task IDs in advance
    try:
        logger.info(f"Syncing all work items from TFS API for project {AZURE_PROJECT_ID}...")
        if azHandler:
            if hasattr(azHandler, "sync_work_items"):
                if progress_callback:
                    summary = azHandler.sync_work_items(cache_db, project_id=AZURE_PROJECT_ID, progress_callback=progress_callback)
                else:
                    summary = azHandler.sync_work_items(cache_db, project_id=AZURE_PROJECT_ID)
            else:
                wi_ids = cache_db.get_all_work_item_ids()
                summary = {"synced": 0, "deleted": 0, "errors": 0}
                for wid in wi_ids:
                    try:
                        wi = azHandler.get_work_item(wid)
                        if wi and isinstance(wi, dict) and "id" in wi:
                            fields = wi.get("fields", {})
                            assigned = fields.get("System.AssignedTo", {})
                            assigned_name = assigned.get("displayName", "") if isinstance(assigned, dict) else str(assigned or "")
                            cache_db.save_work_item(
                                wi["id"],
                                fields.get("System.Title"),
                                fields.get("System.WorkItemType"),
                                fields.get("System.State"),
                                assigned_name,
                                fields.get("System.ChangedDate"),
                                wi,
                                deleted=0
                            )
                            summary["synced"] += 1
                        else:
                            cache_db.mark_work_item_deleted(wid)
                            summary["deleted"] += 1
                    except Exception:
                        cache_db.mark_work_item_deleted(wid)
                        summary["deleted"] += 1
            logger.info(f"Work items sync completed: {summary.get('synced', 0)} synced, {summary.get('deleted', 0)} marked deleted, {summary.get('errors', 0)} errors")
    except Exception as e:
        logger.error(f"Error syncing work items to SQLite: {e}")

    # Reconcile pull request statuses (ensure active PRs closed/abandoned in TFS are updated)
    try:
        if azHandler and hasattr(azHandler, "sync_pull_requests"):
            logger.info("Synchronizing and reconciling pull request statuses with TFS...")
            azHandler.sync_pull_requests(cache_db, project_id=AZURE_PROJECT_ID)
    except Exception as e:
        logger.warning(f"Error reconciling pull request statuses: {e}")

    try:
        cache_db.update_project_last_synced(AZURE_PROJECT_ID, AZURE_PROJECT_ID)
    except Exception as e:
        logger.error(f"Error updating project last sync time in SQLite: {e}")

def export_prs(file_base_path):
    """
    Exports pull requests per repository and branch to Excel (XML) and Markdown.
    """
    db_path, cache_db = _getDBCacheHandler()
    try:
        prs = cache_db.get_all_prs()
    except Exception as e:
        logger.error(f"Error querying PRs from cache: {e}")
        return

    if not prs:
        logger.warning("No pull requests found in cache database. Please run sync first.")
        return

    # Group PRs by repository name and branch
    grouped = {}
    for pr in prs:
        pr["title"] = patch_pr_title_for_release_notes(pr, cache_db=cache_db)
        repo_name = pr["repo_name"]
        branch = pr["target_branch"].replace("refs/heads/", "") if pr["target_branch"] else "unknown"
        if repo_name not in grouped:
            grouped[repo_name] = {}
        if branch not in grouped[repo_name]:
            grouped[repo_name][branch] = []
        grouped[repo_name][branch].append(pr)

    # 1. Generate Markdown report from template
    template_file = "./templates/PR_REPORT.tmpl"
    resolved_template = template_file
    if not os.path.exists(resolved_template):
        # Try finding relative to BASE_FOLDER / scripts
        resolved_template = os.path.join(BASE_FOLDER, "scripts", template_file.lstrip("./"))
    if not os.path.exists(resolved_template):
        # Try finding relative to script's parent folder
        resolved_template = os.path.join(os.path.dirname(py_dir), template_file.lstrip("./"))


    md_path = f"{file_base_path}.md"
    try:
        with open(resolved_template, "r", encoding="utf-8") as f:
            template_str = f.read()
        
        template = Template(template_str)
        keys = sorted(grouped.keys())
        rendered_md = template.render(grouped=grouped, keys=keys)
        
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(rendered_md)
        logger.info(f"Exported PRs to Markdown report using template: {md_path}")
    except Exception as e:
        logger.error(f"Error rendering Markdown PR report template: {e}")


    # 2. Generate Excel report using openpyxl
    try:
        import openpyxl
        from openpyxl.styles import Font, PatternFill, Alignment

        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "Pull Requests"

        # Set up headers
        headers = ["Repository", "Branch", "PR ID", "Title", "Status", "Created By", "Closed Date"]
        ws.append(headers)

        # Style header row
        header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
        header_fill = PatternFill(start_color="4F81BD", end_color="4F81BD", fill_type="solid")
        header_align = Alignment(horizontal="center", vertical="center")

        for col_idx in range(1, len(headers) + 1):
            cell = ws.cell(row=1, column=col_idx)
            cell.font = header_font
            cell.fill = header_fill
            cell.alignment = header_align

        # Add data
        for repo_name in sorted(grouped.keys()):
            for branch in sorted(grouped[repo_name].keys()):
                for pr in grouped[repo_name][branch]:
                    closed_date = pr["closed_date"] or "-"
                    row_data = [
                        repo_name,
                        branch,
                        pr["pr_id"],
                        pr["title"],
                        pr["status_str"],
                        pr["created_by"],
                        closed_date
                    ]
                    ws.append(row_data)

        # Adjust column widths automatically
        for col in ws.columns:
            max_len = 0
            col_letter = col[0].column_letter
            for cell in col:
                val = str(cell.value or '')
                if len(val) > max_len:
                    max_len = len(val)
            ws.column_dimensions[col_letter].width = max(max_len + 3, 10)

        # Save to file_base_path.xlsx
        xlsx_path = f"{file_base_path}.xlsx"
        wb.save(xlsx_path)
        logger.info(f"Exported PRs to Excel spreadsheet: {xlsx_path}")
    except Exception as e:
        logger.error(f"Error writing Excel spreadsheet: {e}")


def get_tagged_prs_by_repo(repo_name):
    """
    Retrieves all tagged pull requests for a given repository from the database view.
    """
    db_path, cache_db = _getDBCacheHandler()
    with cache_db._connection() as conn:
        rows = conn.execute("""
            SELECT pr_id, repo_id, title, status, target_branch, source_branch, 
                   created_by, closed_by, closed_date, status_str, merge_commit_id, tag_name
            FROM v_pull_requests_tagged
            WHERE repo_name = ? AND is_tagged = 1
            ORDER BY pr_id DESC
        """, (repo_name,)).fetchall()
        return [dict(r) for r in rows]


def list_untagged_repos():
    """
    Lists all active repositories where the latest pull request is either not closed or untagged.
    """
    db_path, cache_db = _getDBCacheHandler()
    
    with cache_db._connection() as conn:
        repos = conn.execute("SELECT name FROM repositories WHERE is_disabled = 0 ORDER BY name").fetchall()
        repo_names = [r["name"] for r in repos]

    untagged_repos = []
    for repo in repo_names:
        with cache_db._connection() as conn:
            latest_pr = conn.execute("""
                SELECT pr_id, title, status, is_tagged, tag_name
                FROM v_pull_requests_tagged
                WHERE repo_name = ?
                ORDER BY pr_id DESC
                LIMIT 1
            """, (repo,)).fetchone()
            
        if latest_pr:
            is_active = (latest_pr["status"] == "active")
            has_no_tag = (latest_pr["is_tagged"] == 0)
            
            if is_active or has_no_tag:
                untagged_repos.append((repo, latest_pr))
                
    if untagged_repos:
        print("Repositories with untagged or active latest pull requests:")
        for r, pr in untagged_repos:
            status_desc = "active (open)" if pr["status"] == "active" else "closed (no tag)"
            print(f"- {r} (Latest PR {pr['pr_id']}: '{pr['title']}', status: {status_desc})")
            
            # Fetch all PRs for this repository ordered by ID descending
            with cache_db._connection() as conn:
                all_prs = conn.execute("""
                    SELECT pr_id, title, status, is_tagged, tag_name, closed_date
                    FROM v_pull_requests_tagged
                    WHERE repo_name = ?
                    ORDER BY pr_id DESC
                """, (r,)).fetchall()
            
            prs_since_tagged = []
            last_tagged_pr = None
            for p in all_prs:
                if p["is_tagged"] == 1:
                    last_tagged_pr = p
                    break
                prs_since_tagged.append(p)
                
            if last_tagged_pr:
                print(f"  Last tagged PR: {last_tagged_pr['pr_id']} (Tag: {last_tagged_pr['tag_name']})")
            else:
                print("  No tagged PR found in history.")
                
            print(f"  PRs since last tagged PR ({len(prs_since_tagged)}):")
            for p in prs_since_tagged:
                print(f"    * PR {p['pr_id']}: '{p['title']}' (status={p['status']}, closed={p['closed_date'] or 'N/A'})")
            print()
    else:
        print("No repositories found with untagged or active latest pull requests.")
    return [r for r, _ in untagged_repos]


def generate_tagday_report(db_path: Optional[str] = None, output_path: Optional[str] = None,
                           project_id: Optional[str] = None, config_path: Optional[str] = None,
                           template_path: Optional[str] = None) -> bool:
    """
    Standardized entrypoint to generate the enhanced Tag Day release report.
    Defaults to configured BASE_FOLDER, AZURE_PROJECT_ID, and TAGDAY_FILE_MD.
    """
    from generate_tagday_report import run_tagday_report
    if not db_path:
        db_path, _ = _getDBCacheHandler()
    if not output_path:
        output_path = os.path.join(BASE_FOLDER, TAGDAY_FILE_MD)
    if not project_id:
        project_id = AZURE_PROJECT_ID
    return run_tagday_report(
        db_path=db_path,
        output_path=output_path,
        project_id=project_id,
        config_path=config_path,
        template_path=template_path
    )


def generate_artifacts_report() -> bool:
    """
    Standardized entrypoint to generate Build Artifact & Disk Space Markdown and CSV reports.
    Defaults to configured BASE_FOLDER, AZURE_PROJECT_ID, BUILD_ARTIFACTS_MD, and BUILD_ARTIFACTS_CSV.
    """
    import generate_artifacts_report
    db_path, _ = _getDBCacheHandler()
    md_path = os.path.join(BASE_FOLDER, BUILD_ARTIFACTS_MD)
    csv_path = os.path.join(BASE_FOLDER, BUILD_ARTIFACTS_CSV)
    return generate_artifacts_report.run_reports(
        db_path=db_path,
        md_path=md_path,
        csv_path=csv_path
    )


def generate_revision_report(db_path: Optional[str] = None, revision_md_path: Optional[str] = None) -> bool:
    """
    Standardized entrypoint to generate REVISION.md and REVISION.docx release tracking documents.
    Defaults to configured BASE_FOLDER, AZURE_PROJECT_ID, and REVISION_FILE_MD.
    """
    import generate_revision
    db_path, _ = _getDBCacheHandler()
    revision_md_path = os.path.join(BASE_FOLDER, REVISION_FILE_MD)
    return generate_revision.generate_revision_md(db_path, revision_md_path)


if __name__ == "__main__":
    import argparse
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    parser = argparse.ArgumentParser(description="Azure DevOps Sync & Document Generation CLI")
    parser.add_argument("--sync", action="store_true", help="Sync pipelines, repos, and tasks from TFS to local SQLite cache.")
    parser.add_argument("--force", action="store_true", help="Force sync, bypassing file recency checks (use with --sync).")
    parser.add_argument("--templates", action="store_true", help="Render Markdown pages from cached repository data.")
    parser.add_argument("--export-prs", type=str, metavar="OUTPUT_BASE", help="Export PRs per repo and branch to OUTPUT_BASE.xlsx and OUTPUT_BASE.md.")
    parser.add_argument("--revision", action="store_true", help="Generate and update the REVISION.md release history document.")
    parser.add_argument("--check-artifacts", action="store_true", help="Check Artifacts")
    parser.add_argument("--report-artifacts", action="store_true", help="Generate Markdown and CSV reports on build artifacts and disk space usage.")
    parser.add_argument("--report-tagday", action="store_true", help="Generate enhanced Tag Day report relative to reference tag baseline.")
    parser.add_argument("--untagged-repos", action="store_true", help="List all repositories where the latest pull request is either not closed or untagged.")

    args = parser.parse_args()

    # If no arguments are provided, print help and exit
    if not any(vars(args).values()):
        parser.print_help()
        sys.exit(0)

    if args.check_artifacts:
        check_artifacts()

    if args.report_artifacts or args.check_artifacts:
        generate_artifacts_report()

    if args.report_tagday:
        generate_tagday_report()

    if args.sync:
        sync(force_sync=args.force, run_templates_flag=args.templates)

    if args.export_prs:
        export_prs(args.export_prs)

    if args.revision:
        generate_revision_report()

    if args.untagged_repos:
        list_untagged_repos()

