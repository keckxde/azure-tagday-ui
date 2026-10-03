# -*- coding: UTF-8 -*-
"""
Team Motivation, Gamification & Sprint Leaderboard Engine
Computes weekly and sprint-based team activity metrics, gamified badges,
consecutive activity streaks, and competitive leaderboards from cached Azure DevOps data.
Includes commits, feature branches, tags, PRs, work items, and CI build health.
"""

import os
import json
import logging
from datetime import datetime, date, timedelta
import re
import utils
from utils import parse_iso_datetime, parse_sprint_week, get_sprint_date_range

try:
    from azure.azure_db import is_work_item_in_area_path
except ImportError:
    try:
        from azure_db import is_work_item_in_area_path
    except ImportError:
        def is_work_item_in_area_path(area_path, rules):
            return True

def _extract_wi_area_path(wi):
    """Extracts area path from work item dictionary."""
    if not isinstance(wi, dict):
        return ""
    ap = wi.get("area_path") or wi.get("AreaPath")
    if not ap:
        raw = wi.get("raw_dict") or wi.get("raw_json")
        if isinstance(raw, str):
            try:
                raw = json.loads(raw)
            except Exception:
                raw = {}
        if isinstance(raw, dict):
            ap = raw.get("fields", {}).get("System.AreaPath")
    if not ap and isinstance(wi.get("fields"), dict):
        ap = wi["fields"].get("System.AreaPath")
    return ap or ""

logger = logging.getLogger("team_motivation")

# Badge Definitions with rules and visual metadata
# Badge Categories definition
BADGE_CATEGORIES = {
    "prs_reviews": {
        "id": "prs_reviews",
        "name": "Pull Requests & Code Reviews",
        "icon": "🔀",
        "description": "Contributions to code collaboration, PR creation, turnaround velocity, and peer reviews."
    },
    "work_items": {
        "id": "work_items",
        "name": "Work Items & Agile Tasks",
        "icon": "📋",
        "description": "Completion of user stories, bug fixes, on-time task delivery, and backlog architecture."
    },
    "commits_code": {
        "id": "commits_code",
        "name": "Code & Branching",
        "icon": "💻",
        "description": "Direct repository commits, branch creation, and adherence to structured PBS/syntax conventions."
    },
    "cicd_releases": {
        "id": "cicd_releases",
        "name": "CI/CD & Releases",
        "icon": "🚀",
        "description": "Pipeline execution stability, automated build success, and release tag publishing."
    },
    "grooming_quality": {
        "id": "grooming_quality",
        "name": "Quality & Grooming",
        "icon": "🛡️",
        "description": "Lifecycle state transitions, rigorous quality gatekeeping/pushbacks, and traceable evidence links."
    },
    "habits_time": {
        "id": "habits_time",
        "name": "Working Habits & Rhythm",
        "icon": "⏰",
        "description": "Activity distribution across core daytime, early morning, late night, and sprint end timing."
    },
    "streaks_mvp": {
        "id": "streaks_mvp",
        "name": "Streaks & Hall of Fame",
        "icon": "👑",
        "description": "Multi-week active contribution consistency and overall sprint composite score leadership."
    }
}

# Badge Definitions with 3-tier structure (Bronze, Silver, Gold) where Silver and Gold are harder
BADGE_DEFINITIONS = {
    # 1. Pull Requests & Code Reviews
    "pr_dynamo": {
        "id": "pr_dynamo",
        "base_name": "PR Pioneer",
        "name": "PR Pioneer",
        "icon": "🚀",
        "category": "prs_reviews",
        "category_name": "Pull Requests & Code Reviews",
        "category_icon": "🔀",
        "color": "#58a6ff",
        "bg_color": "#0d2344",
        "description": "Initiated pull requests to propose new features or fixes.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "PR Pioneer (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Created 1+ PR", "threshold": 1, "points": 5},
            "silver": {"tier": "silver", "name": "PR Pioneer (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Created 3+ PRs", "threshold": 3, "points": 12},
            "gold":   {"tier": "gold",   "name": "PR Pioneer (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Created 6+ PRs", "threshold": 6, "points": 25}
        }
    },
    "the_closer": {
        "id": "the_closer",
        "base_name": "The Closer",
        "name": "The Closer",
        "icon": "🏁",
        "category": "prs_reviews",
        "category_name": "Pull Requests & Code Reviews",
        "category_icon": "🔀",
        "color": "#3fb950",
        "bg_color": "#162b20",
        "description": "Successfully merged and integrated peer pull requests into main branches.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "The Closer (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Merged 1+ PR", "threshold": 1, "points": 6},
            "silver": {"tier": "silver", "name": "The Closer (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Merged 3+ PRs", "threshold": 3, "points": 15},
            "gold":   {"tier": "gold",   "name": "The Closer (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Merged 6+ PRs", "threshold": 6, "points": 30}
        }
    },
    "eagle_eye": {
        "id": "eagle_eye",
        "base_name": "Eagle Eye Reviewer",
        "name": "Eagle Eye Reviewer",
        "icon": "🔍",
        "category": "prs_reviews",
        "category_name": "Pull Requests & Code Reviews",
        "category_icon": "🔀",
        "color": "#39c5cf",
        "bg_color": "#0d2d30",
        "description": "Actively reviewed code, gave feedback, and approved peer pull requests.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Eagle Eye (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Reviewed 1+ peer PR", "threshold": 1, "points": 5},
            "silver": {"tier": "silver", "name": "Eagle Eye (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Reviewed 3+ peer PRs", "threshold": 3, "points": 14},
            "gold":   {"tier": "gold",   "name": "Eagle Eye (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Reviewed 8+ peer PRs & approved", "threshold": 8, "points": 28}
        }
    },
    "speed_demon": {
        "id": "speed_demon",
        "base_name": "Speed Demon",
        "name": "Speed Demon",
        "icon": "⚡",
        "category": "prs_reviews",
        "category_name": "Pull Requests & Code Reviews",
        "category_icon": "🔀",
        "color": "#e3b341",
        "bg_color": "#3d2800",
        "description": "Turned around, reviewed, and merged PRs with high velocity.",
        "tier": "silver",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Speed Demon (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Merged PR within 24 hours", "threshold": 1, "points": 8},
            "silver": {"tier": "silver", "name": "Speed Demon (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Merged 2+ PRs within 24 hours", "threshold": 2, "points": 18},
            "gold":   {"tier": "gold",   "name": "Speed Demon (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Merged 4+ PRs within 12 hours", "threshold": 4, "points": 35}
        }
    },

    # 2. Work Items & Agile Tasks
    "task_crusher": {
        "id": "task_crusher",
        "base_name": "Task Crusher",
        "name": "Task Crusher",
        "icon": "🔨",
        "category": "work_items",
        "category_name": "Work Items & Agile Tasks",
        "category_icon": "📋",
        "color": "#a371f7",
        "bg_color": "#271052",
        "description": "Completed work items and user stories to drive sprint deliverables.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Task Crusher (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Completed 1+ work item", "threshold": 1, "points": 5},
            "silver": {"tier": "silver", "name": "Task Crusher (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Completed 5+ work items", "threshold": 5, "points": 15},
            "gold":   {"tier": "gold",   "name": "Task Crusher (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Completed 10+ work items", "threshold": 10, "points": 30}
        }
    },
    "bug_slayer": {
        "id": "bug_slayer",
        "base_name": "Bug Slayer",
        "name": "Bug Slayer",
        "icon": "🛡️",
        "category": "work_items",
        "category_name": "Work Items & Agile Tasks",
        "category_icon": "📋",
        "color": "#f85149",
        "bg_color": "#3d1418",
        "description": "Smashed defects and resolved critical bugs to ensure software stability.",
        "tier": "silver",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Bug Slayer (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Resolved 1+ bug", "threshold": 1, "points": 8},
            "silver": {"tier": "silver", "name": "Bug Slayer (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Resolved 3+ bugs", "threshold": 3, "points": 20},
            "gold":   {"tier": "gold",   "name": "Bug Slayer (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Resolved 6+ bugs", "threshold": 6, "points": 40}
        }
    },
    "task_architect": {
        "id": "task_architect",
        "base_name": "Task Architect",
        "name": "Task Architect",
        "icon": "📐",
        "category": "work_items",
        "category_name": "Work Items & Agile Tasks",
        "category_icon": "📋",
        "color": "#79c0ff",
        "bg_color": "#16243b",
        "description": "Authored and refined structured work items to define team scope.",
        "tier": "bronze",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Task Architect (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Created 2+ tasks", "threshold": 2, "points": 5},
            "silver": {"tier": "silver", "name": "Task Architect (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Created 5+ tasks", "threshold": 5, "points": 14},
            "gold":   {"tier": "gold",   "name": "Task Architect (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Created 10+ tasks", "threshold": 10, "points": 28}
        }
    },
    "sprint_sniper": {
        "id": "sprint_sniper",
        "base_name": "Sprint Sniper",
        "name": "Sprint Sniper",
        "icon": "🎯",
        "category": "work_items",
        "category_name": "Work Items & Agile Tasks",
        "category_icon": "📋",
        "color": "#2ea043",
        "bg_color": "#162b20",
        "description": "Punctual delivery: finished assigned items with zero delay shifts.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Sprint Sniper (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "1+ task on-time with 0 delays", "threshold": 1, "points": 8},
            "silver": {"tier": "silver", "name": "Sprint Sniper (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "3+ tasks on-time with 0 delays", "threshold": 3, "points": 20},
            "gold":   {"tier": "gold",   "name": "Sprint Sniper (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "6+ tasks on-time with 0 delays", "threshold": 6, "points": 40}
        }
    },
    "speedy_task_closer": {
        "id": "speedy_task_closer",
        "base_name": "Lightning Finisher",
        "name": "Lightning Finisher ⚡",
        "icon": "⚡",
        "category": "work_items",
        "category_name": "Work Items & Agile Tasks",
        "category_icon": "📋",
        "color": "#f0883e",
        "bg_color": "#381a08",
        "description": "High velocity task closure from activation to resolved state.",
        "tier": "silver",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Lightning Finisher (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "1+ task closed < 24h", "threshold": 1, "points": 6},
            "silver": {"tier": "silver", "name": "Lightning Finisher (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "3+ tasks closed < 24h", "threshold": 3, "points": 18},
            "gold":   {"tier": "gold",   "name": "Lightning Finisher (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "6+ tasks closed < 12h", "threshold": 6, "points": 35}
        }
    },

    # 3. Code & Branching
    "commit_machine": {
        "id": "commit_machine",
        "base_name": "Code Machine",
        "name": "Code Machine",
        "icon": "💻",
        "category": "commits_code",
        "category_name": "Code & Branching",
        "category_icon": "💻",
        "color": "#7ee787",
        "bg_color": "#122a18",
        "description": "Authored and pushed code commits to project repositories.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Code Machine (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Pushed 2+ commits", "threshold": 2, "points": 5},
            "silver": {"tier": "silver", "name": "Code Machine (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Pushed 6+ commits", "threshold": 6, "points": 15},
            "gold":   {"tier": "gold",   "name": "Code Machine (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Pushed 15+ commits", "threshold": 15, "points": 32}
        }
    },
    "branch_architect": {
        "id": "branch_architect",
        "base_name": "Feature Pioneer",
        "name": "Feature Pioneer",
        "icon": "🌳",
        "category": "commits_code",
        "category_name": "Code & Branching",
        "category_icon": "💻",
        "color": "#79c0ff",
        "bg_color": "#16243b",
        "description": "Created dedicated feature or bugfix branches for clean development.",
        "tier": "silver",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Feature Pioneer (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Started 1+ feature branch", "threshold": 1, "points": 5},
            "silver": {"tier": "silver", "name": "Feature Pioneer (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Started 3+ feature branches", "threshold": 3, "points": 14},
            "gold":   {"tier": "gold",   "name": "Feature Pioneer (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Started 6+ feature branches", "threshold": 6, "points": 28}
        }
    },
    "syntax_master": {
        "id": "syntax_master",
        "base_name": "Syntax Champion",
        "name": "Syntax Champion 🏷️",
        "icon": "🏷️",
        "category": "commits_code",
        "category_name": "Code & Branching",
        "category_icon": "💻",
        "color": "#7ee787",
        "bg_color": "#122a18",
        "description": "Standard Bearer: resolved items formatted with [<Type>_<nr>] naming standard.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Syntax Master (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "1+ item with structured [<Type>_<nr>]", "threshold": 1, "points": 6},
            "silver": {"tier": "silver", "name": "Syntax Master (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "3+ items with structured [<Type>_<nr>]", "threshold": 3, "points": 18},
            "gold":   {"tier": "gold",   "name": "Syntax Master (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "6+ items with structured [<Type>_<nr>]", "threshold": 6, "points": 35}
        }
    },

    # 4. CI/CD & Releases
    "ci_hero": {
        "id": "ci_hero",
        "base_name": "CI / Build Champion",
        "name": "CI / Build Champion",
        "icon": "🏗️",
        "category": "cicd_releases",
        "category_name": "CI/CD & Releases",
        "category_icon": "🚀",
        "color": "#56d364",
        "bg_color": "#142d1b",
        "description": "Triggered and executed green CI pipeline builds without failures.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "CI Champion (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "1+ successful build (0 failed)", "threshold": 1, "points": 6},
            "silver": {"tier": "silver", "name": "CI Champion (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "2+ successful builds (0 failed)", "threshold": 2, "points": 16},
            "gold":   {"tier": "gold",   "name": "CI Champion (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "5+ successful builds (0 failed)", "threshold": 5, "points": 35}
        }
    },
    "tag_hero": {
        "id": "tag_hero",
        "base_name": "Release Hero",
        "name": "Release Hero",
        "icon": "🏷️",
        "category": "cicd_releases",
        "category_name": "CI/CD & Releases",
        "category_icon": "🚀",
        "color": "#d2a8ff",
        "bg_color": "#2c1b4d",
        "description": "Pushed or authored official release version tags.",
        "tier": "silver",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Release Hero (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Authored 1+ release tag", "threshold": 1, "points": 10},
            "silver": {"tier": "silver", "name": "Release Hero (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Authored 2+ release tags", "threshold": 2, "points": 24},
            "gold":   {"tier": "gold",   "name": "Release Hero (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Authored 4+ release tags", "threshold": 4, "points": 45}
        }
    },

    # 5. Quality & Grooming
    "the_cleaner": {
        "id": "the_cleaner",
        "base_name": "The Cleaner",
        "name": "The Cleaner 🧹",
        "icon": "🧹",
        "category": "grooming_quality",
        "category_name": "Quality & Grooming",
        "category_icon": "🛡️",
        "color": "#388bfd",
        "bg_color": "#0c2d6b",
        "description": "Backlog Grooming Master: actively kept work item states accurate.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "The Cleaner (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Groomed 1+ work item state", "threshold": 1, "points": 5},
            "silver": {"tier": "silver", "name": "The Cleaner (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Groomed 3+ work item states", "threshold": 3, "points": 15},
            "gold":   {"tier": "gold",   "name": "The Cleaner (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Groomed 8+ work item states", "threshold": 8, "points": 30}
        }
    },
    "the_decliner": {
        "id": "the_decliner",
        "base_name": "The Gatekeeper",
        "name": "The Gatekeeper / Decliner 🛡️",
        "icon": "🛡️",
        "category": "grooming_quality",
        "category_name": "Quality & Grooming",
        "category_icon": "🛡️",
        "color": "#e3b341",
        "bg_color": "#3d2800",
        "description": "Quality Gatekeeper: pushed back items to Active or To Do for rigorous fixes.",
        "tier": "silver",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Gatekeeper (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "1+ quality pushback", "threshold": 1, "points": 6},
            "silver": {"tier": "silver", "name": "Gatekeeper (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "2+ quality pushbacks", "threshold": 2, "points": 16},
            "gold":   {"tier": "gold",   "name": "Gatekeeper (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "5+ quality pushbacks", "threshold": 5, "points": 35}
        }
    },
    "state_mover": {
        "id": "state_mover",
        "base_name": "State Driver",
        "name": "State Driver 🚀",
        "icon": "🚀",
        "category": "grooming_quality",
        "category_name": "Quality & Grooming",
        "category_icon": "🛡️",
        "color": "#56d364",
        "bg_color": "#142d1b",
        "description": "High flow velocity: progressed work items across multiple lifecycle stages.",
        "tier": "silver",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "State Driver (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "2+ state transitions", "threshold": 2, "points": 5},
            "silver": {"tier": "silver", "name": "State Driver (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "5+ state transitions", "threshold": 5, "points": 14},
            "gold":   {"tier": "gold",   "name": "State Driver (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "10+ state transitions", "threshold": 10, "points": 30}
        }
    },
    "evidence_master": {
        "id": "evidence_master",
        "base_name": "Proof Master",
        "name": "Proof Master 🧾",
        "icon": "🧾",
        "category": "grooming_quality",
        "category_name": "Quality & Grooming",
        "category_icon": "🛡️",
        "color": "#39c5cf",
        "bg_color": "#0d2d30",
        "description": "High Traceability: backed up tasks with commit, PR, and artifact links.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Proof Master (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "2+ task evidence links", "threshold": 2, "points": 5},
            "silver": {"tier": "silver", "name": "Proof Master (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "5+ task evidence links", "threshold": 5, "points": 15},
            "gold":   {"tier": "gold",   "name": "Proof Master (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "10+ task evidence links", "threshold": 10, "points": 30}
        }
    },
    "stale_sheriff": {
        "id": "stale_sheriff",
        "base_name": "Stale Task Sheriff",
        "name": "Stale Task Sheriff 🤠",
        "icon": "🤠",
        "category": "grooming_quality",
        "category_name": "Quality & Grooming",
        "category_icon": "🛡️",
        "color": "#f0883e",
        "bg_color": "#3e1e0d",
        "description": "Clean desk policy: 0 stale tasks while actively carrying assigned work.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Stale Sheriff (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "0 stale tasks (1+ assigned)", "threshold": 1, "points": 6},
            "silver": {"tier": "silver", "name": "Stale Sheriff (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "0 stale tasks (3+ assigned)", "threshold": 3, "points": 16},
            "gold":   {"tier": "gold",   "name": "Stale Sheriff (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "0 stale tasks (5+ assigned)", "threshold": 5, "points": 35}
        }
    },
    "relic_keeper": {
        "id": "relic_keeper",
        "base_name": "Backlog Archaeologist",
        "name": "Backlog Archaeologist ⏳",
        "icon": "⏳",
        "category": "grooming_quality",
        "category_name": "Quality & Grooming",
        "category_icon": "🛡️",
        "color": "#e3b341",
        "bg_color": "#3d2800",
        "description": "Custodian of Ancient Lore: managing active tickets open across long cycles.",
        "tier": "bronze",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Archaeologist (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Managing open task >= 30 days", "threshold": 30, "points": 5},
            "silver": {"tier": "silver", "name": "Archaeologist (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "Managing open task >= 60 days", "threshold": 60, "points": 12},
            "gold":   {"tier": "gold",   "name": "Archaeologist (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "Managing open task >= 90 days", "threshold": 90, "points": 25}
        }
    },

    # 6. Working Habits & Rhythm
    "night_owl": {
        "id": "night_owl",
        "base_name": "Night Owl",
        "name": "Night Owl",
        "icon": "🦉",
        "category": "habits_time",
        "category_name": "Working Habits & Rhythm",
        "category_icon": "⏰",
        "color": "#a371f7",
        "bg_color": "#2d164d",
        "description": "Active in late night hours (9 PM – 5 AM) delivering commits or PRs.",
        "tier": "silver",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Night Owl (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "1+ night action (21h-5h)", "threshold": 1, "points": 5},
            "silver": {"tier": "silver", "name": "Night Owl (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "3+ night actions (21h-5h)", "threshold": 3, "points": 12},
            "gold":   {"tier": "gold",   "name": "Night Owl (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "6+ night actions (21h-5h)", "threshold": 6, "points": 25}
        }
    },
    "early_bird": {
        "id": "early_bird",
        "base_name": "Early Bird",
        "name": "Early Bird",
        "icon": "🌅",
        "category": "habits_time",
        "category_name": "Working Habits & Rhythm",
        "category_icon": "⏰",
        "color": "#f0883e",
        "bg_color": "#3e1e0d",
        "description": "Delivering contributions early before core hours (5 AM – 9 AM).",
        "tier": "bronze",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Early Bird (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "1+ early action (5h-9h)", "threshold": 1, "points": 5},
            "silver": {"tier": "silver", "name": "Early Bird (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "3+ early actions (5h-9h)", "threshold": 3, "points": 12},
            "gold":   {"tier": "gold",   "name": "Early Bird (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "6+ early actions (5h-9h)", "threshold": 6, "points": 25}
        }
    },
    "weekend_warrior": {
        "id": "weekend_warrior",
        "base_name": "The Week-ender",
        "name": "The Week-ender",
        "icon": "⚡",
        "category": "habits_time",
        "category_name": "Working Habits & Rhythm",
        "category_icon": "⏰",
        "color": "#d29922",
        "bg_color": "#382900",
        "description": "Unstoppable dedication: coded, reviewed, or shipped work on weekends.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Week-ender (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "1+ weekend action", "threshold": 1, "points": 6},
            "silver": {"tier": "silver", "name": "Week-ender (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "3+ weekend actions", "threshold": 3, "points": 15},
            "gold":   {"tier": "gold",   "name": "Week-ender (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "6+ weekend actions", "threshold": 6, "points": 30}
        }
    },
    "zen_balancer": {
        "id": "zen_balancer",
        "base_name": "Zen Work-Life Balancer",
        "name": "Zen Work-Life Balancer",
        "icon": "🧘",
        "category": "habits_time",
        "category_name": "Working Habits & Rhythm",
        "category_icon": "⏰",
        "color": "#3fb950",
        "bg_color": "#102a18",
        "description": "Disciplined focus: delivers 85%+ work during daytime with 0 weekend overtime.",
        "tier": "silver",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Zen Balancer (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "75%+ daytime actions, 0 weekend", "threshold": 75, "points": 6},
            "silver": {"tier": "silver", "name": "Zen Balancer (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "85%+ daytime actions, 0 weekend (min 3 actions)", "threshold": 85, "points": 15},
            "gold":   {"tier": "gold",   "name": "Zen Balancer (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "95%+ daytime actions, 0 weekend (min 6 actions)", "threshold": 95, "points": 30}
        }
    },
    "friday_hero": {
        "id": "friday_hero",
        "base_name": "Friday Finisher",
        "name": "Friday Finisher",
        "icon": "🚀",
        "category": "habits_time",
        "category_name": "Working Habits & Rhythm",
        "category_icon": "⏰",
        "color": "#58a6ff",
        "bg_color": "#0d2344",
        "description": "Shipped and closed PRs or tasks on Friday afternoon before sprint close.",
        "tier": "bronze",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Friday Hero (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "1+ Friday PM delivery", "threshold": 1, "points": 5},
            "silver": {"tier": "silver", "name": "Friday Hero (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "2+ Friday PM deliveries", "threshold": 2, "points": 14},
            "gold":   {"tier": "gold",   "name": "Friday Hero (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "4+ Friday PM deliveries", "threshold": 4, "points": 28}
        }
    },

    # 7. Streaks & MVP
    "streak_master": {
        "id": "streak_master",
        "base_name": "On Fire Streak",
        "name": "On Fire Streak 🔥",
        "icon": "🔥",
        "category": "streaks_mvp",
        "category_name": "Streaks & Hall of Fame",
        "category_icon": "👑",
        "color": "#ff7b72",
        "bg_color": "#3f1a18",
        "description": "Maintained an active contribution streak across consecutive sprint weeks.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Streak Master (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "2+ consecutive active weeks", "threshold": 2, "points": 10},
            "silver": {"tier": "silver", "name": "Streak Master (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "4+ consecutive active weeks", "threshold": 4, "points": 25},
            "gold":   {"tier": "gold",   "name": "Streak Master (Gold)",   "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "8+ consecutive active weeks", "threshold": 8, "points": 50}
        }
    },
    "sprint_mvp": {
        "id": "sprint_mvp",
        "base_name": "Sprint MVP",
        "name": "Sprint MVP",
        "icon": "👑",
        "category": "streaks_mvp",
        "category_name": "Streaks & Hall of Fame",
        "category_icon": "👑",
        "color": "#ffd700",
        "bg_color": "#3b2d00",
        "description": "Highest overall composite contribution score in the sprint cycle.",
        "tier": "gold",
        "tiers": {
            "bronze": {"tier": "bronze", "name": "Sprint Podium (Bronze)", "icon": "🥉", "color": "#cd7f32", "bg_color": "#2c1a0e", "criteria": "Top 3 composite sprint score", "threshold": 3, "points": 15},
            "silver": {"tier": "silver", "name": "Sprint Runner-Up (Silver)", "icon": "🥈", "color": "#c0c0c0", "bg_color": "#21262d", "criteria": "#2 composite sprint score", "threshold": 2, "points": 30},
            "gold":   {"tier": "gold",   "name": "Sprint MVP (Gold)", "icon": "🥇", "color": "#ffd700", "bg_color": "#3b2d00", "criteria": "#1 composite sprint score", "threshold": 1, "points": 60}
        }
    }
}

# ---------------------------------------------------------------------------
# Default Motivation Score Weights Configuration & Presets
# ---------------------------------------------------------------------------
DEFAULT_SCORE_CONFIG = {
    # Pull Requests & Code Reviews
    "prs_closed": 15,
    "prs_created": 10,
    "prs_approved": 8,
    "prs_reviewed": 6,
    "commits_count": 3,
    "branches_closed": 5,
    "tags_pushed": 12,

    # Work Items & Quality
    "tasks_completed": 8,
    "tasks_created": 3,
    "bugs_resolved": 10,
    "stories_completed": 10,
    "tasks_cleaned": 3,
    "pushbacks_count": 4,
    "tasks_fast_closed": 4,
    "task_evidences_count": 2,
    "structured_syntax_completed": 7,

    # CI/CD & Builds
    "builds_succeeded": 4,

    # Streaks & Badges
    "badge_bonus": 5,
    "streak_week_bonus": 4,

    # Penalties & Deductions
    "delay_week_penalty": 3,
    "build_failed_penalty": 2,
    "stale_task_penalty": 2,
}

SCORE_PRESETS = {
    "balanced": {
        "id": "balanced",
        "name": "Balanced (Default)",
        "icon": "⚖️",
        "description": "Standard balanced distribution rewarding PRs, code commits, agile delivery, quality reviews, and consistency.",
        "config": dict(DEFAULT_SCORE_CONFIG)
    },
    "code_pr_focused": {
        "id": "code_pr_focused",
        "name": "Code & PR Focused",
        "icon": "💻",
        "description": "Amplified points for pull requests, thorough code reviews, branches, commits, release tags, and CI builds.",
        "config": {
            "prs_closed": 25,
            "prs_created": 15,
            "prs_approved": 12,
            "prs_reviewed": 10,
            "commits_count": 5,
            "branches_closed": 8,
            "tags_pushed": 20,
            "tasks_completed": 5,
            "tasks_created": 2,
            "bugs_resolved": 8,
            "stories_completed": 8,
            "tasks_cleaned": 2,
            "pushbacks_count": 3,
            "tasks_fast_closed": 3,
            "task_evidences_count": 1,
            "structured_syntax_completed": 5,
            "builds_succeeded": 6,
            "badge_bonus": 5,
            "streak_week_bonus": 5,
            "delay_week_penalty": 2,
            "build_failed_penalty": 4,
            "stale_task_penalty": 1,
        }
    },
    "agile_quality_focused": {
        "id": "agile_quality_focused",
        "name": "Agile & Quality Focused",
        "icon": "🎯",
        "description": "Emphasizes stories delivered, bugs fixed, fast turnaround, structured PBS syntax, and traceability.",
        "config": {
            "prs_closed": 10,
            "prs_created": 8,
            "prs_approved": 8,
            "prs_reviewed": 6,
            "commits_count": 2,
            "branches_closed": 4,
            "tags_pushed": 8,
            "tasks_completed": 12,
            "tasks_created": 4,
            "bugs_resolved": 20,
            "stories_completed": 20,
            "tasks_cleaned": 6,
            "pushbacks_count": 6,
            "tasks_fast_closed": 8,
            "task_evidences_count": 4,
            "structured_syntax_completed": 12,
            "builds_succeeded": 4,
            "badge_bonus": 8,
            "streak_week_bonus": 6,
            "delay_week_penalty": 5,
            "build_failed_penalty": 2,
            "stale_task_penalty": 4,
        }
    },
    "high_velocity": {
        "id": "high_velocity",
        "name": "High Velocity & Turnaround",
        "icon": "🚀",
        "description": "Maximizes points for rapid sprint task completion, long-running streaks, and quick turnarounds.",
        "config": {
            "prs_closed": 20,
            "prs_created": 12,
            "prs_approved": 10,
            "prs_reviewed": 8,
            "commits_count": 4,
            "branches_closed": 6,
            "tags_pushed": 15,
            "tasks_completed": 15,
            "tasks_created": 5,
            "bugs_resolved": 15,
            "stories_completed": 15,
            "tasks_cleaned": 4,
            "pushbacks_count": 5,
            "tasks_fast_closed": 10,
            "task_evidences_count": 3,
            "structured_syntax_completed": 8,
            "builds_succeeded": 5,
            "badge_bonus": 6,
            "streak_week_bonus": 8,
            "delay_week_penalty": 4,
            "build_failed_penalty": 3,
            "stale_task_penalty": 3,
        }
    }
}


def get_default_score_config():
    """Returns a fresh copy of the default motivation score configuration."""
    return dict(DEFAULT_SCORE_CONFIG)


def get_score_presets():
    """Returns all built-in scoring preset profiles."""
    return dict(SCORE_PRESETS)




def _clean_user_name(user_obj_or_str):
    """Normalizes user identity into a readable display name string."""
    if not user_obj_or_str:
        return ""
    if isinstance(user_obj_or_str, dict):
        return (
            user_obj_or_str.get("displayName")
            or user_obj_or_str.get("uniqueName")
            or user_obj_or_str.get("name")
            or ""
        ).strip()
    return str(user_obj_or_str).strip()


DEFAULT_SYSTEM_USERS = [
    "unassigned",
    "undefined",
    "none",
    "unknown",
    "system",
    "[deleted]",
    "github-actions[bot]",
    "tfs build service",
    "azure pipelines",
    "dependabot[bot]",
]


def normalize_system_users(system_users_config):
    """
    Normalizes configured system users into:
    - system_users_set: set of lowercase names/identifiers to exclude from Hall of Fame.
    - system_users_list: list of dicts [{"name": str, "is_builtin": bool, "note": str}] for UI display.
    """
    system_users_set = {u.lower() for u in DEFAULT_SYSTEM_USERS}
    system_users_list = []
    for u in DEFAULT_SYSTEM_USERS:
        system_users_list.append({"name": u, "is_builtin": True, "note": "Built-in system account"})

    if not system_users_config:
        return system_users_set, system_users_list

    items = []
    if isinstance(system_users_config, (list, tuple, set)):
        for entry in system_users_config:
            if isinstance(entry, dict):
                items.append((entry.get("name", ""), entry.get("note", "")))
            elif isinstance(entry, str):
                items.append((entry, ""))
    elif isinstance(system_users_config, dict):
        for k, v in system_users_config.items():
            items.append((k, str(v) if not isinstance(v, bool) else ""))
    elif isinstance(system_users_config, str):
        for part in system_users_config.split(","):
            items.append((part.strip(), ""))

    for name, note in items:
        name_clean = str(name).strip()
        if not name_clean:
            continue
        low = name_clean.lower()
        system_users_set.add(low)
        if "<" in name_clean and ">" in name_clean:
            email_match = re.search(r"<([^>]+)>", name_clean)
            if email_match:
                system_users_set.add(email_match.group(1).lower().strip())
            name_part = name_clean.split("<")[0].strip().lower()
            if name_part:
                system_users_set.add(name_part)

        if not any(item["name"].lower() == low for item in system_users_list):
            system_users_list.append({"name": name_clean, "is_builtin": False, "note": note or "Custom system user"})

    return system_users_set, system_users_list


def _is_valid_member(name, system_users_set=None):
    """Filters out empty or system placeholder names and configured system users."""
    if not name:
        return False
    clean = _clean_user_name(name) if isinstance(name, dict) else str(name).strip()
    if not clean:
        return False
    low = clean.lower()

    if system_users_set is not None:
        if low in system_users_set:
            return False
        if "<" in clean and ">" in clean:
            email_match = re.search(r"<([^>]+)>", clean)
            if email_match and email_match.group(1).lower().strip() in system_users_set:
                return False
            name_part = clean.split("<")[0].strip().lower()
            if name_part in system_users_set:
                return False
    else:
        if low in ("unassigned", "undefined", "none", "unknown", "system", "[deleted]", "github-actions[bot]", "tfs build service", "azure pipelines", "dependabot[bot]"):
            return False
        if "<" in clean and ">" in clean:
            name_part = clean.split("<")[0].strip().lower()
            if name_part in ("unassigned", "undefined", "none", "unknown", "system", "[deleted]", "github-actions[bot]", "tfs build service", "azure pipelines", "dependabot[bot]"):
                return False
    return True



def normalize_user_aliases(aliases_config):
    """
    Normalizes user aliases configuration into:
    - alias_lookup (dict mapping lowercase alias/name -> canonical name)
    - canonical_to_aliases (dict mapping canonical name -> list of alias strings)

    Supports both dict format { "Alice Smith": ["asmith", "alice@corp.com"] }
    and list format [ { "canonical": "Alice Smith", "aliases": [...] } ].
    """
    alias_lookup = {}
    canonical_to_aliases = {}

    if not aliases_config:
        return alias_lookup, canonical_to_aliases

    items = []
    if isinstance(aliases_config, dict):
        items = aliases_config.items()
    elif isinstance(aliases_config, list):
        for entry in aliases_config:
            if isinstance(entry, dict) and "canonical" in entry:
                items.append((entry["canonical"], entry.get("aliases", [])))

    for canon, aliases in items:
        canon_clean = str(canon).strip()
        if not canon_clean:
            continue
        canonical_to_aliases.setdefault(canon_clean, set())
        alias_lookup[canon_clean.lower()] = canon_clean
        if isinstance(aliases, (list, tuple, set)):
            for a in aliases:
                a_clean = str(a).strip()
                if a_clean:
                    canonical_to_aliases[canon_clean].add(a_clean)
                    alias_lookup[a_clean.lower()] = canon_clean
        elif isinstance(aliases, str) and aliases.strip():
            a_clean = aliases.strip()
            canonical_to_aliases[canon_clean].add(a_clean)
            alias_lookup[a_clean.lower()] = canon_clean

    canonical_to_aliases = {k: sorted(list(v)) for k, v in canonical_to_aliases.items()}
    return alias_lookup, canonical_to_aliases


def resolve_canonical_user(user_obj_or_str, alias_lookup=None):
    """
    Resolves raw user input (dict, string, username, email) to a canonical user display name
    using the provided alias lookup dictionary (or tuple from normalize_user_aliases).
    """
    if isinstance(alias_lookup, (tuple, list)) and len(alias_lookup) > 0 and isinstance(alias_lookup[0], dict):
        alias_lookup = alias_lookup[0]
    raw_name = _clean_user_name(user_obj_or_str)
    if not raw_name:
        return "Unassigned"
    if alias_lookup and isinstance(alias_lookup, dict):
        low = raw_name.lower()
        if low in alias_lookup:
            return alias_lookup[low]
        if "<" in raw_name and ">" in raw_name:
            email_match = re.search(r"<([^>]+)>", raw_name)
            if email_match:
                em = email_match.group(1).strip().lower()
                if em in alias_lookup:
                    return alias_lookup[em]
        if isinstance(user_obj_or_str, dict):
            for email_k in ("uniqueName", "email", "mail", "principalName"):
                em = str(user_obj_or_str.get(email_k) or "").strip().lower()
                if em and em in alias_lookup:
                    return alias_lookup[em]
    return raw_name


def format_relative_time(dt_or_str, now=None):
    """Formats a datetime or ISO string into a human-friendly relative time string."""
    if not dt_or_str:
        return "No recorded activity"
    dt = parse_iso_datetime(dt_or_str) if isinstance(dt_or_str, str) else dt_or_str
    if not dt or not isinstance(dt, datetime):
        return str(dt_or_str)[:16]
    now = now or datetime.now()
    diff = now - dt
    total_seconds = int(diff.total_seconds())
    if total_seconds < 0:
        return "Just now"
    if total_seconds < 60:
        return f"{total_seconds}s ago"
    minutes = total_seconds // 60
    if minutes < 60:
        return f"{minutes}m ago"
    hours = minutes // 60
    if hours < 24:
        return f"{hours}h ago"
    days = hours // 24
    if days == 1:
        return f"Yesterday at {dt.strftime('%H:%M')}"
    if days < 7:
        return f"{days}d ago"
    if days < 30:
        weeks = days // 7
        return f"{weeks}w ago"
    return dt.strftime("%b %d, %Y")


def detect_potential_user_aliases(cache_db, existing_aliases=None, system_users=None):
    """
    Analyzes Git commits, PRs, Work Items, and TFS metadata in the cache database
    to automatically identify potential user alias candidates (e.g. Git author email/username
    matching TFS display names).

    Returns:
        list of dict: [{"canonical": str, "alias": str, "source": str, "reason": str, "confidence": str, "activity_count": int}]
    """
    if not cache_db:
        return []

    system_users_set, _ = normalize_system_users(system_users)
    existing_lookup, _ = normalize_user_aliases(existing_aliases)
    canonical_candidates = set()
    raw_candidates = {}

    def _is_valid(n):
        return _is_valid_member(n, system_users_set)

    try:
        with cache_db._connection() as conn:
            # Query work items assignees & closers
            wi_rows = conn.execute("SELECT assigned_to, raw_json FROM work_items WHERE deleted = 0").fetchall()
            for r in wi_rows:
                a_name = _clean_user_name(r["assigned_to"])
                if _is_valid(a_name):
                    if " " in a_name and len(a_name.split()) >= 2:
                        canonical_candidates.add(a_name)
                    raw_candidates.setdefault(a_name, {"sources": set(), "activity_count": 0, "emails": set()})
                    raw_candidates[a_name]["sources"].add("Work Item Assignee")
                    raw_candidates[a_name]["activity_count"] += 1

            # Query commits authors & emails
            c_rows = conn.execute("SELECT author_name, author_email, committer_name, committer_email FROM commits LIMIT 10000").fetchall()
            for cr in c_rows:
                for n_k, e_k in (("author_name", "author_email"), ("committer_name", "committer_email")):
                    c_name = _clean_user_name(cr[n_k])
                    c_email = str(cr[e_k] or "").strip()
                    if _is_valid(c_name):
                        if " " in c_name and len(c_name.split()) >= 2:
                            canonical_candidates.add(c_name)
                        raw_candidates.setdefault(c_name, {"sources": set(), "activity_count": 0, "emails": set()})
                        raw_candidates[c_name]["sources"].add("Git Commit Author")
                        raw_candidates[c_name]["activity_count"] += 1
                        if c_email and "@" in c_email:
                            raw_candidates[c_name]["emails"].add(c_email.lower())
                    if c_email and "@" in c_email:
                        email_user = c_email.split("@")[0].strip()
                        if _is_valid(email_user):
                            raw_candidates.setdefault(email_user, {"sources": set(), "activity_count": 0, "emails": set()})
                            raw_candidates[email_user]["sources"].add("Git Email")
                            raw_candidates[email_user]["activity_count"] += 1
                            raw_candidates[email_user]["emails"].add(c_email.lower())

            # Query PR creators & reviewers
            pr_rows = conn.execute("SELECT created_by, closed_by, raw_json FROM pull_requests").fetchall()
            for pr_r in pr_rows:
                for u_k in ("created_by", "closed_by"):
                    u_name = _clean_user_name(pr_r[u_k])
                    if _is_valid(u_name):
                        if " " in u_name and len(u_name.split()) >= 2:
                            canonical_candidates.add(u_name)
                        raw_candidates.setdefault(u_name, {"sources": set(), "activity_count": 0, "emails": set()})
                        raw_candidates[u_name]["sources"].add("Pull Request")
                        raw_candidates[u_name]["activity_count"] += 1
    except Exception as e:
        logger.debug(f"Error analyzing database for aliases: {e}")

    suggestions = []
    seen_pairs = set()

    for canon in sorted(canonical_candidates):
        canon_lower = canon.lower()
        parts = [p.lower() for p in canon.split() if p.strip()]
        if len(parts) < 2:
            continue
        first_name = parts[0]
        last_name = parts[-1]
        first_initial = first_name[0]
        last_initial = last_name[0]

        expected_patterns = {
            f"{first_initial}{last_name}": ("Matches First Initial + Last Name (e.g. jdoe)", "high"),
            f"{first_name}.{last_name}": ("Matches First.Last format", "high"),
            f"{first_name}_{last_name}": ("Matches First_Last format", "high"),
            f"{first_name}-{last_name}": ("Matches First-Last format", "high"),
            f"{first_name}{last_name}": ("Matches First+Last concatenated", "high"),
            f"{first_name}{last_initial}": ("Matches First Name + Last Initial", "medium"),
            f"{last_name}{first_initial}": ("Matches Last Name + First Initial", "medium"),
            f"{last_name}.{first_name}": ("Matches Last.First format", "medium"),
        }

        for cand_name, cand_info in raw_candidates.items():
            cand_clean = cand_name.strip()
            cand_lower = cand_clean.lower()

            if cand_lower == canon_lower:
                continue

            if cand_lower in existing_lookup and existing_lookup[cand_lower].lower() == canon_lower:
                continue
            if (canon, cand_clean) in seen_pairs:
                continue

            matched_reason = None
            matched_conf = "low"

            if cand_lower in expected_patterns:
                matched_reason, matched_conf = expected_patterns[cand_lower]
            elif cand_lower == first_name and len(canonical_candidates) > 0:
                same_first = [c for c in canonical_candidates if c.lower().startswith(first_name + " ")]
                if len(same_first) == 1:
                    matched_reason = f"Unique First Name ('{first_name}') in team"
                    matched_conf = "medium"
            elif cand_lower == last_name and len(canonical_candidates) > 0:
                same_last = [c for c in canonical_candidates if c.lower().endswith(" " + last_name)]
                if len(same_last) == 1:
                    matched_reason = f"Unique Last Name ('{last_name}') in team"
                    matched_conf = "medium"
            else:
                for em in cand_info.get("emails", []):
                    em_user = em.split("@")[0].lower()
                    if em_user in expected_patterns:
                        matched_reason, matched_conf = f"Email username '{em_user}' matches {expected_patterns[em_user][0]}", "high"
                        break
                    elif em_user == f"{first_name}.{last_name}" or em_user == f"{first_initial}{last_name}":
                        matched_reason, matched_conf = f"Email '{em}' matches name structure", "high"
                        break

            if matched_reason:
                seen_pairs.add((canon, cand_clean))
                src_list = ", ".join(sorted(cand_info.get("sources", ["Activity"])))
                suggestions.append({
                    "canonical": canon,
                    "alias": cand_clean,
                    "reason": matched_reason,
                    "source": src_list,
                    "confidence": matched_conf,
                    "activity_count": cand_info.get("activity_count", 0),
                })

    conf_order = {"high": 0, "medium": 1, "low": 2}
    return sorted(suggestions, key=lambda s: (conf_order.get(s["confidence"], 3), -s["activity_count"], s["canonical"]))


def detect_potential_system_users(cache_db, existing_system_users=None):
    """
    Analyzes Git commits, PRs, Work Items, and builds in the cache database
    to automatically identify potential bot, CI, automation, or service accounts
    that should be excluded from the Hall of Fame.

    Returns:
        list of dict: [{"name": str, "activity_count": int, "sources": list, "reason": str, "confidence": str}]
    """
    if not cache_db:
        return []

    system_users_set, _ = normalize_system_users(existing_system_users)
    detected = {}

    SYSTEM_PATTERNS = [
        (re.compile(r"(\bbot\b|\[bot\]|_bot|-bot)", re.I), "Identified as bot account"),
        (re.compile(r"(\bservice\b|\bsvc\b|\bsvc_|svc-)", re.I), "Service account naming pattern"),
        (re.compile(r"(\bagent\b|\bpipeline\b|\bci\b|\bcd\b|\bbuild\b|\brelease\b)", re.I), "CI/CD or build pipeline agent"),
        (re.compile(r"(\badmin\b|\badministrator\b|\broot\b|\bsystem\b)", re.I), "System administrator identity"),
        (re.compile(r"(\bautomation\b|\bdaemon\b|\bsync\b|\bwebhook\b)", re.I), "Automated integration service"),
        (re.compile(r"(\bdevops\b|\btfs\b|\bazure\b|\bgithub\b)", re.I), "Platform automation account"),
    ]

    def _check_name(name, src):
        if not name:
            return
        c_name = _clean_user_name(name)
        if not c_name:
            return
        low = c_name.lower()
        if low in system_users_set:
            return

        for pattern, reason in SYSTEM_PATTERNS:
            if pattern.search(low):
                if c_name not in detected:
                    detected[c_name] = {
                        "name": c_name,
                        "activity_count": 0,
                        "sources": set(),
                        "reason": reason,
                        "confidence": "high" if ("[bot]" in low or "service" in low or "pipeline" in low or "agent" in low) else "medium"
                    }
                detected[c_name]["activity_count"] += 1
                detected[c_name]["sources"].add(src)
                break

    try:
        with cache_db._connection() as conn:
            # Check work items
            wi_rows = conn.execute("SELECT assigned_to, created_by, changed_by, closed_by FROM work_items WHERE deleted = 0").fetchall()
            for r in wi_rows:
                for k, src in (("assigned_to", "Work Item Assignee"), ("created_by", "Work Item Creator"), ("changed_by", "Work Item Modifier"), ("closed_by", "Work Item Closer")):
                    _check_name(r[k], src)

            # Check commits
            c_rows = conn.execute("SELECT author_name, author_email, committer_name, committer_email FROM commits LIMIT 10000").fetchall()
            for cr in c_rows:
                for n_k, src in (("author_name", "Git Commit Author"), ("committer_name", "Git Committer")):
                    _check_name(cr[n_k], src)
                for e_k in ("author_email", "committer_email"):
                    email = str(cr[e_k] or "").strip()
                    if email and "@" in email:
                        prefix = email.split("@")[0]
                        _check_name(prefix, "Git Commit Email")

            # Check PRs
            pr_rows = conn.execute("SELECT created_by, closed_by FROM pull_requests").fetchall()
            for pr_r in pr_rows:
                for u_k, src in (("created_by", "Pull Request Creator"), ("closed_by", "Pull Request Closer")):
                    _check_name(pr_r[u_k], src)
    except Exception as e:
        logger.debug(f"Error scanning for potential system users: {e}")

    results = []
    for item in detected.values():
        item["sources"] = sorted(list(item["sources"]))
        results.append(item)

    return sorted(results, key=lambda x: (0 if x["confidence"] == "high" else 1, -x["activity_count"], x["name"].lower()))


def compute_team_motivation_data(cache_db, timeframe="last_week", custom_sprint="", work_items=None, pull_requests=None, user_aliases=None, score_config=None, system_users=None):
    """
    Computes team activity, leaderboards, streaks, badges, user profiles, and team pulse stats.

    Args:
        cache_db (AzureDevOpsCache): Active SQLite cache database.
        timeframe (str): 'last_week', 'current_week', 'last_4_weeks', 'all_time', or 'sprint'.
        custom_sprint (str): Sprint identifier (e.g. 'week-2639') if timeframe is 'sprint' or override.
        work_items (list): Optional pre-fetched work items list.
        pull_requests (list): Optional pre-fetched pull requests list.
        user_aliases (dict/list): Optional user aliases mapping to combine identities.
        score_config (dict): Optional custom point weights dictionary.
        system_users (list/dict): Optional list of system users / bots to exclude from Hall of Fame.

    Returns:
        dict: Full motivational analysis payload ready for QML UI consumption.
    """
    if not cache_db:
        return {}

    # Normalize system users (excluded from Hall of Fame & motivation metrics)
    if system_users is None:
        try:
            from utils import _load_active_user_settings
            system_users = _load_active_user_settings().get("system_users")
        except Exception:
            system_users = None

    system_users_set, system_users_list = normalize_system_users(system_users)

    def _is_valid(name):
        return _is_valid_member(name, system_users_set)

    # Normalize user aliases
    if user_aliases is None:
        try:
            from utils import _load_active_user_settings
            user_aliases = _load_active_user_settings().get("user_aliases")
        except Exception:
            user_aliases = None

    alias_lookup, canonical_to_aliases = normalize_user_aliases(user_aliases)

    # Normalize score configuration
    active_score_config = dict(DEFAULT_SCORE_CONFIG)
    if score_config is None:
        try:
            from utils import _load_active_user_settings
            cfg_scores = _load_active_user_settings().get("team_motivation_score_config")
            if cfg_scores and isinstance(cfg_scores, dict):
                score_config = cfg_scores
        except Exception:
            pass

    if score_config and isinstance(score_config, dict):
        for k, v in score_config.items():
            if k in active_score_config:
                try:
                    active_score_config[k] = int(v)
                except (ValueError, TypeError):
                    pass



    now = datetime.now()
    cur_year, cur_week_num, _ = now.isocalendar()
    cur_sprint_name = f"week-{str(cur_year)[-2:]}{cur_week_num:02d}"

    # Determine date range & sprint labels
    last_week_dt = now - timedelta(days=7)
    last_year, last_week_num, _ = last_week_dt.isocalendar()
    last_sprint_name = f"week-{str(last_year)[-2:]}{last_week_num:02d}"

    # Compute bounds for timeframes
    cur_start_dt, cur_end_dt, cur_start_str, cur_end_str = get_sprint_date_range(cur_year, cur_week_num)
    last_start_dt, last_end_dt, last_start_str, last_end_str = get_sprint_date_range(last_year, last_week_num)

    target_sprint = ""
    range_label = ""
    filter_start_str = ""
    filter_end_str = ""

    if timeframe == "last_week":
        target_sprint = last_sprint_name
        range_label = f"Last Week ({last_sprint_name} • {last_start_str} to {last_end_str})"
        filter_start_str = last_start_str
        filter_end_str = cur_start_str  # up to current week start
    elif timeframe == "current_week":
        target_sprint = cur_sprint_name
        range_label = f"Current Sprint ({cur_sprint_name} • {cur_start_str} to {cur_end_str})"
        filter_start_str = cur_start_str
        filter_end_str = (cur_end_dt + timedelta(days=3)).strftime("%Y-%m-%d")
    elif timeframe == "last_4_weeks":
        four_wks_ago = now - timedelta(days=28)
        filter_start_str = four_wks_ago.strftime("%Y-%m-%d")
        filter_end_str = (now + timedelta(days=1)).strftime("%Y-%m-%d")
        range_label = f"Past 4 Weeks ({filter_start_str} to {now.strftime('%Y-%m-%d')})"
    elif timeframe == "all_time":
        range_label = "All-Time Hall of Fame"
        filter_start_str = "1970-01-01"
        filter_end_str = "2099-12-31"
    elif timeframe == "sprint" or custom_sprint:
        clean_s = custom_sprint.strip() if custom_sprint else last_sprint_name
        target_sprint = clean_s
        sy, sw, _ = parse_sprint_week(clean_s)
        if sy and sw:
            s_dt, e_dt, s_str, e_str = get_sprint_date_range(sy, sw)
            filter_start_str = s_str
            filter_end_str = (e_dt + timedelta(days=3)).strftime("%Y-%m-%d")
            range_label = f"Sprint {clean_s} ({s_str} to {e_str})"
        else:
            filter_start_str = "1970-01-01"
            filter_end_str = "2099-12-31"
            range_label = f"Sprint {clean_s}"
    else:
        # Default fallback to last week
        target_sprint = last_sprint_name
        range_label = f"Last Week ({last_sprint_name} • {last_start_str} to {last_end_str})"
        filter_start_str = last_start_str
        filter_end_str = cur_start_str

    # Check Area Path filter rules configuration
    area_cfg = {}
    if hasattr(cache_db, "get_area_path_settings"):
        try:
            area_cfg = cache_db.get_area_path_settings() or {}
        except Exception:
            area_cfg = {}
    area_filter_enabled = bool(area_cfg.get("filter_enabled") or area_cfg.get("enabled"))
    area_rules = area_cfg.get("rules", [])

    # Fetch raw datasets if not provided (honoring Area Path filter if active)
    if work_items is not None:
        all_wis = list(work_items)
        if area_filter_enabled and area_rules:
            all_wis = [w for w in all_wis if is_work_item_in_area_path(_extract_wi_area_path(w), area_rules)]
    else:
        all_wis = cache_db.get_all_work_items(filter_area_paths=True)
        if area_filter_enabled and area_rules:
            all_wis = [w for w in all_wis if is_work_item_in_area_path(_extract_wi_area_path(w), area_rules)]

    # Build set of allowed work item IDs within the active Team Area Filter
    allowed_wi_ids = set()
    for w in all_wis:
        wid = w.get("id")
        if wid is not None:
            allowed_wi_ids.add(wid)
            try:
                allowed_wi_ids.add(int(wid))
            except Exception:
                pass

    all_prs = []
    if pull_requests is not None:
        all_prs = pull_requests
    else:
        try:
            with cache_db._connection() as conn:
                rows = conn.execute("SELECT id, repo_id, title, status, target_branch, source_branch, created_by, closed_by, closed_date, status_str, raw_json FROM pull_requests").fetchall()
                for r in rows:
                    pr_obj = {}
                    if r["raw_json"]:
                        try:
                            pr_obj = json.loads(r["raw_json"]) if isinstance(r["raw_json"], str) else r["raw_json"]
                        except Exception:
                            pass
                    if not isinstance(pr_obj, dict):
                        pr_obj = {}
                    if "createdBy" not in pr_obj and r["created_by"]:
                        pr_obj["createdBy"] = r["created_by"]
                    if "closedBy" not in pr_obj and r["closed_by"]:
                        pr_obj["closedBy"] = r["closed_by"]
                    if "closedDate" not in pr_obj and r["closed_date"]:
                        pr_obj["closedDate"] = r["closed_date"]
                    if "status" not in pr_obj and r["status"]:
                        pr_obj["status"] = r["status"]
                    if "status_str" not in pr_obj and r["status_str"]:
                        pr_obj["status_str"] = r["status_str"]
                    if "title" not in pr_obj and r["title"]:
                        pr_obj["title"] = r["title"]
                    all_prs.append(pr_obj)
        except Exception as e:
            logger.debug(f"Error reading PRs from cache: {e}")

    # Fetch tags
    all_tags = []
    try:
        with cache_db._connection() as conn:
            t_rows = conn.execute("""
                SELECT t.name as tag_name, t.commit_date, t.committer_name, COALESCE(r.name, t.repo_id) as repo_name, t.is_stable, t.is_unstable
                FROM tags t
                LEFT JOIN repositories r ON t.repo_id = r.id
                ORDER BY t.commit_date DESC
            """).fetchall()
            for tr in t_rows:
                all_tags.append({
                    "tag_name": tr["tag_name"],
                    "commit_date": tr["commit_date"] or "",
                    "committer": tr["committer_name"] or "",
                    "repo_name": tr["repo_name"] or "",
                    "is_stable": tr["is_stable"],
                    "is_unstable": tr["is_unstable"]
                })
    except Exception as e:
        logger.debug(f"Error reading tags: {e}")

    # Fetch branches
    all_branches = []
    try:
        with cache_db._connection() as conn:
            b_rows = conn.execute("""
                SELECT b.name as branch_name, b.commit_date, b.committer_name, COALESCE(r.name, b.repo_id) as repo_name, b.raw_json
                FROM branches b
                LEFT JOIN repositories r ON b.repo_id = r.id
                ORDER BY b.commit_date DESC
            """).fetchall()
            for br in b_rows:
                all_branches.append({
                    "branch_name": br["branch_name"],
                    "commit_date": br["commit_date"] or "",
                    "committer": br["committer_name"] or "",
                    "repo_name": br["repo_name"] or "",
                    "raw_json": br["raw_json"]
                })
    except Exception as e:
        logger.debug(f"Error reading branches: {e}")

    # Fetch builds
    all_builds = []
    try:
        with cache_db._connection() as conn:
            build_rows = conn.execute("""
                SELECT id, pipeline_name, status, result, finish_time, start_time, requested_by, source_branch
                FROM builds
                ORDER BY finish_time DESC
            """).fetchall()
            for b in build_rows:
                all_builds.append({
                    "id": b["id"],
                    "pipeline_name": b["pipeline_name"] or "",
                    "status": (b["status"] or "").lower(),
                    "result": (b["result"] or "").lower(),
                    "finish_time": b["finish_time"] or b["start_time"] or "",
                    "requested_by": _clean_user_name(b["requested_by"]),
                    "source_branch": b["source_branch"] or ""
                })
    except Exception as e:
        logger.debug(f"Error reading builds: {e}")

    # Fetch commits
    all_commits = []
    try:
        if hasattr(cache_db, "get_all_commits"):
            all_commits = cache_db.get_all_commits(limit=25000)
        else:
            with cache_db._connection() as conn:
                c_rows = conn.execute("""
                    SELECT c.repo_id, c.commit_id, c.author_name, c.author_date,
                           c.committer_name, c.committer_date, c.comment,
                           COALESCE(r.name, c.repo_id) as repo_name
                    FROM commits c
                    LEFT JOIN repositories r ON c.repo_id = r.id
                    ORDER BY COALESCE(c.committer_date, c.author_date) DESC
                    LIMIT 25000
                """).fetchall()
                for cr in c_rows:
                    all_commits.append(dict(cr))
    except Exception as e:
        logger.debug(f"Error reading commits: {e}")

    # Fetch state transition events (filtered by area path if enabled)
    all_state_events = []
    try:
        if hasattr(cache_db, "get_state_events"):
            raw_state_events = cache_db.get_state_events(limit=5000)
            if area_filter_enabled and area_rules and raw_state_events:
                all_state_events = [
                    ev for ev in raw_state_events
                    if ev.get("work_item_id") in allowed_wi_ids or (str(ev.get("work_item_id", "")).isdigit() and int(ev.get("work_item_id")) in allowed_wi_ids)
                ]
            else:
                all_state_events = raw_state_events
    except Exception as e:
        logger.debug(f"Error reading state events: {e}")

    # Fetch iteration shifts to measure delay/sprint predictability (filtered by area path if enabled)
    shifts_by_user = {}
    try:
        shifts = cache_db.get_iteration_shifts(limit=2000)
        for s in shifts:
            s_wid = s.get("work_item_id") or s.get("id")
            if area_filter_enabled and area_rules and s_wid is not None:
                if s_wid not in allowed_wi_ids and (str(s_wid).isdigit() and int(s_wid) not in allowed_wi_ids):
                    continue
            user = _clean_user_name(s.get("assigned_to"))
            if _is_valid(user):
                shifts_by_user.setdefault(user, []).append(s)
    except Exception as e:
        logger.debug(f"Error reading shifts: {e}")

    # Team-level time analytics accumulator
    team_time_agg = {
        "total_samples": 0,
        "daytime_count": 0,
        "early_bird_count": 0,
        "evening_count": 0,
        "night_count": 0,
        "weekend_count": 0,
        "friday_pm_count": 0,
        "commits_count": 0,
        "prs_count": 0,
        "tasks_count": 0,
        "builds_count": 0,
        "hourly_distribution": [0] * 24,
        "daily_distribution": [0] * 7,  # Mon(0)..Sun(6)
        "hourly_commits": [0] * 24,
        "hourly_prs": [0] * 24,
        "hourly_tasks": [0] * 24,
        "hourly_builds": [0] * 24,
        "daily_commits": [0] * 7,
        "daily_prs": [0] * 7,
        "daily_tasks": [0] * 7,
        "daily_builds": [0] * 7,
        "daytime_breakdown": {"commits": 0, "prs": 0, "tasks": 0, "builds": 0},
        "night_breakdown": {"commits": 0, "prs": 0, "tasks": 0, "builds": 0},
        "early_bird_breakdown": {"commits": 0, "prs": 0, "tasks": 0, "builds": 0},
        "weekend_breakdown": {"commits": 0, "prs": 0, "tasks": 0, "builds": 0},
    }

    # Stale tasks radar accumulator
    stale_radar = []

    # Initialize Per-Member Aggregation dictionary
    members = {}

    def _get_or_create_member(name):
        cname = resolve_canonical_user(name, alias_lookup)
        cname = _clean_user_name(cname)
        if not _is_valid(cname):
            return None
        if cname not in members:
            # Generate initials
            parts = cname.split()
            initials = (parts[0][0] + (parts[-1][0] if len(parts) > 1 else "")).upper() if parts else "??"
            known_aliases = canonical_to_aliases.get(cname, [])
            members[cname] = {
                "name": cname,
                "initials": initials,
                "aliases": list(known_aliases),
                "is_aliased": False,
                "aliased_to": None,
                "last_active_date": "",
                "last_activity": None,
                "recent_activities": [],
                "assigned_work_items": [],
                "recent_prs": [],
                "recent_commits": [],
                "_last_activity_dt": None,
                "prs_created": 0,
                "prs_closed": 0,
                "prs_fast_merged": 0,
                "prs_reviewed": 0,
                "prs_approved": 0,
                "tasks_created": 0,
                "tasks_completed": 0,
                "bugs_resolved": 0,
                "stories_completed": 0,
                "commits_count": 0,
                "branches_started": 0,
                "branches_closed": 0,
                "tags_pushed": 0,
                "builds_total": 0,
                "builds_succeeded": 0,
                "builds_failed": 0,
                "build_success_rate": 100.0,
                "total_shifts": 0,
                "total_delay_weeks": 0,
                "avg_pr_hours": 0.0,
                "state_changes_count": 0,
                "pushbacks_count": 0,
                "tasks_cleaned": 0,
                "stale_tasks_count": 0,
                "open_tasks_assigned": 0,
                "oldest_open_task_days": 0,
                "oldest_open_task": None,
                "tasks_fast_closed": 0,
                "avg_task_turnaround_hours": 0.0,
                "fastest_task_hours": 0.0,
                "task_evidences_count": 0,
                "structured_syntax_completed": 0,
                "is_cleaner": False,
                "is_decliner": False,
                "is_ignorer": False,
                "night_activities": 0,
                "early_bird_activities": 0,
                "weekend_activities": 0,
                "daytime_activities": 0,
                "evening_activities": 0,
                "friday_afternoon_activities": 0,
                "time_stats": {
                    "total_actions": 0,
                    "daytime_count": 0,
                    "early_bird_count": 0,
                    "evening_count": 0,
                    "night_count": 0,
                    "weekend_count": 0,
                    "friday_pm_count": 0,
                    "daytime_pct": 0.0,
                    "night_pct": 0.0,
                    "weekend_pct": 0.0,
                    "early_bird_pct": 0.0,
                    "hourly_distribution": [0] * 24,
                    "daily_distribution": [0] * 7,
                    "peak_hour": 14,
                    "peak_hour_label": "14:00",
                    "peak_day": "Wednesday",
                    "persona": "☀️ Daytime Core",
                },
                "_pr_durations": [],
                "_task_durations": [],
                "recent_achievements": [],
                "badges": [],
                "badges_count": 0,
                "score": 0,
                "weekly_activity_history": {},  # sprint_week -> activity count
                "current_streak_weeks": 0,
                "best_streak_weeks": 0,
            }
        return members[cname]

    def _track_activity_time(member_dict, ts_str, act_type="other", title="", repo_or_id="", meta=None):
        """Categorizes when work happened and records last/recent activity timeline for user."""
        if not member_dict or not ts_str:
            return
        dt = parse_iso_datetime(ts_str) if isinstance(ts_str, str) else ts_str
        if not dt or not isinstance(dt, datetime):
            return

        hour = dt.hour
        weekday = dt.weekday()  # 0=Mon .. 6=Sun

        ts = member_dict["time_stats"]
        ts["total_actions"] += 1
        ts["hourly_distribution"][hour] += 1
        ts["daily_distribution"][weekday] += 1

        team_time_agg["total_samples"] += 1
        team_time_agg["hourly_distribution"][hour] += 1
        team_time_agg["daily_distribution"][weekday] += 1

        # Track typed activity breakdown
        category = "other"
        if act_type == "commit":
            category = "commits"
            team_time_agg["commits_count"] += 1
            team_time_agg["hourly_commits"][hour] += 1
            team_time_agg["daily_commits"][weekday] += 1
        elif act_type in ("pr_merge", "pr_create", "pr_review"):
            category = "prs"
            team_time_agg["prs_count"] += 1
            team_time_agg["hourly_prs"][hour] += 1
            team_time_agg["daily_prs"][weekday] += 1
        elif act_type in ("task_close", "task_create", "state_change"):
            category = "tasks"
            team_time_agg["tasks_count"] += 1
            team_time_agg["hourly_tasks"][hour] += 1
            team_time_agg["daily_tasks"][weekday] += 1
        elif act_type in ("build", "tag"):
            category = "builds"
            team_time_agg["builds_count"] += 1
            team_time_agg["hourly_builds"][hour] += 1
            team_time_agg["daily_builds"][weekday] += 1

        # Activity icons & last activity tracking
        act_icons = {
            "commit": "💻",
            "pr_create": "🔀",
            "pr_merge": "🚀",
            "pr_review": "👁️",
            "task_create": "➕",
            "task_close": "✅",
            "state_change": "🔄",
            "tag": "🏷️",
            "build": "⚡",
        }
        icon = act_icons.get(act_type, "📌")
        iso_ts = dt.strftime("%Y-%m-%d %H:%M:%S")

        cur_last_dt = member_dict.get("_last_activity_dt")
        if cur_last_dt is None or dt > cur_last_dt:
            member_dict["_last_activity_dt"] = dt
            member_dict["last_active_date"] = iso_ts
            member_dict["last_active_relative"] = format_relative_time(dt)
            member_dict["last_activity"] = {
                "timestamp": iso_ts,
                "relative": format_relative_time(dt),
                "type": act_type,
                "title": title or f"Activity in {act_type}",
                "repo_or_id": repo_or_id,
                "icon": icon,
                "meta": meta or {}
            }

        if title:
            member_dict["recent_activities"].append({
                "timestamp": iso_ts,
                "relative": format_relative_time(dt),
                "type": act_type,
                "title": title,
                "repo_or_id": repo_or_id,
                "icon": icon,
                "meta": meta or {}
            })

        if weekday in (5, 6):
            ts["weekend_count"] += 1
            member_dict["weekend_activities"] += 1
            team_time_agg["weekend_count"] += 1
            if category in team_time_agg["weekend_breakdown"]:
                team_time_agg["weekend_breakdown"][category] += 1
            if hour >= 21 or hour < 5:
                ts["night_count"] += 1
                member_dict["night_activities"] += 1
                team_time_agg["night_count"] += 1
                if category in team_time_agg["night_breakdown"]:
                    team_time_agg["night_breakdown"][category] += 1
        else:
            if hour >= 21 or hour < 5:
                ts["night_count"] += 1
                member_dict["night_activities"] += 1
                team_time_agg["night_count"] += 1
                if category in team_time_agg["night_breakdown"]:
                    team_time_agg["night_breakdown"][category] += 1
            elif 5 <= hour < 9:
                ts["early_bird_count"] += 1
                member_dict["early_bird_activities"] += 1
                team_time_agg["early_bird_count"] += 1
                if category in team_time_agg["early_bird_breakdown"]:
                    team_time_agg["early_bird_breakdown"][category] += 1
            elif 9 <= hour < 18:
                ts["daytime_count"] += 1
                member_dict["daytime_activities"] += 1
                team_time_agg["daytime_count"] += 1
                if category in team_time_agg["daytime_breakdown"]:
                    team_time_agg["daytime_breakdown"][category] += 1
            else:
                ts["evening_count"] += 1
                member_dict["evening_activities"] += 1
                team_time_agg["evening_count"] += 1

            if weekday == 4 and hour >= 14:
                ts["friday_pm_count"] += 1
                member_dict["friday_afternoon_activities"] += 1
                team_time_agg["friday_pm_count"] += 1

    # Build cross-reference evidence map for work items (mentions in commits & PRs)
    wi_evidence_map = {}
    for c in all_commits:
        c_msg = c.get("comment", "") or ""
        for m_id in re.finditer(r"#(\d{3,})", c_msg):
            try:
                wid_ref = int(m_id.group(1))
                wi_evidence_map[wid_ref] = wi_evidence_map.get(wid_ref, 0) + 1
            except Exception:
                pass
    for pr in all_prs:
        pr_text = f"{pr.get('title', '')} {pr.get('status_str', '')} {pr.get('description', '')}"
        for m_id in re.finditer(r"#(\d{3,})", pr_text):
            try:
                wid_ref = int(m_id.group(1))
                wi_evidence_map[wid_ref] = wi_evidence_map.get(wid_ref, 0) + 1
            except Exception:
                pass

    # 1. Process Work Items
    for wi in all_wis:
        if wi.get("deleted") or wi.get("is_deleted"):
            continue

        raw = {}
        if wi.get("raw_json"):
            try:
                raw = json.loads(wi["raw_json"]) if isinstance(wi["raw_json"], str) else wi["raw_json"]
            except Exception:
                pass
        fields = raw.get("fields", {}) if isinstance(raw, dict) else {}

        assigned_name = _clean_user_name(wi.get("assigned_to") or fields.get("System.AssignedTo"))
        created_by = _clean_user_name(wi.get("CreatedBy") or fields.get("System.CreatedBy") or wi.get("created_by"))
        changed_by = _clean_user_name(wi.get("ChangedBy") or fields.get("System.ChangedBy") or wi.get("changed_by"))
        closed_by = _clean_user_name(
            fields.get("Microsoft.VSTS.Common.ClosedBy") or
            fields.get("Microsoft.VSTS.Common.ResolvedBy") or
            wi.get("ClosedBy") or
            wi.get("closed_by") or
            wi.get("ResolvedBy") or
            wi.get("resolved_by")
        )

        changed_date_raw = wi.get("changed_date") or fields.get("System.ChangedDate") or ""
        created_date_raw = wi.get("CreatedDate") or fields.get("System.CreatedDate") or wi.get("created_date") or ""
        closed_date_raw = (
            fields.get("Microsoft.VSTS.Common.ClosedDate") or
            fields.get("Microsoft.VSTS.Common.ResolvedDate") or
            wi.get("ClosedDate") or
            wi.get("closed_date") or
            wi.get("ResolvedDate") or
            wi.get("resolved_date") or
            ""
        )
        changed_date_str = str(changed_date_raw)[:10] if changed_date_raw else ""
        created_date_str = str(created_date_raw)[:10] if created_date_raw else ""
        closed_date_str = str(closed_date_raw)[:10] if closed_date_raw else ""

        state = str(wi.get("state") or fields.get("System.State") or "").capitalize()
        wi_type = str(wi.get("type") or fields.get("System.WorkItemType") or "").lower()
        wi_title = str(wi.get("title") or fields.get("System.Title") or "")
        is_closed_state = state in ("Closed", "Resolved", "Done", "Completed")

        # Track Task Evidences & Traceability Links (Relations, Commits, PRs, Hyperlinks)
        wid = wi.get("id")
        relations = raw.get("relations") or []
        rel_count = len(relations) if isinstance(relations, list) else 0
        ext_evidence = wi_evidence_map.get(wid, 0)
        desc_str = f"{fields.get('System.Description', '')} {fields.get('System.History', '')}"
        hash_refs = min(len(re.findall(r"\b[0-9a-f]{7,40}\b", desc_str)), 3)
        url_refs = min(len(re.findall(r"https?://", desc_str)), 3)
        wi_evidences = rel_count + ext_evidence + hash_refs + url_refs

        # Only attribute evidences if the work item was active, closed, or created within timeframe
        wi_in_timeframe = (timeframe == "all_time")
        if not wi_in_timeframe and filter_start_str and filter_end_str:
            for d_str in (closed_date_str, changed_date_str, created_date_str):
                if d_str and filter_start_str <= d_str < filter_end_str:
                    wi_in_timeframe = True
                    break

        if wi_evidences > 0 and wi_in_timeframe:
            evidence_owner = assigned_name or closed_by or created_by
            if _is_valid(evidence_owner):
                m_ev = _get_or_create_member(evidence_owner)
                if m_ev:
                    m_ev["task_evidences_count"] += wi_evidences

        # Track historical activity across weeks for streak calculation based on actual event dates
        if is_closed_state:
            effective_close_raw = closed_date_raw or changed_date_raw
            effective_close_str = closed_date_str or changed_date_str
            effective_closer = closed_by or assigned_name or changed_by
            if effective_close_str and _is_valid(effective_closer):
                dt = parse_iso_datetime(effective_close_str)
                if dt:
                    y, w, _ = dt.isocalendar()
                    c_sprint = f"week-{str(y)[-2:]}{w:02d}"
                    m = _get_or_create_member(effective_closer)
                    if m:
                        m["weekly_activity_history"][c_sprint] = m["weekly_activity_history"].get(c_sprint, 0) + 1

        if created_date_str:
            effective_creator = created_by or assigned_name
            if _is_valid(effective_creator):
                dt = parse_iso_datetime(created_date_str)
                if dt:
                    y, w, _ = dt.isocalendar()
                    cr_sprint = f"week-{str(y)[-2:]}{w:02d}"
                    m = _get_or_create_member(effective_creator)
                    if m:
                        m["weekly_activity_history"][cr_sprint] = m["weekly_activity_history"].get(cr_sprint, 0) + 1

        # Track Open, Stale, and Oldest Work Items for Assignee
        if not is_closed_state and not wi.get("deleted") and not wi.get("is_deleted"):
            created_dt = parse_iso_datetime(created_date_raw) if created_date_raw else None
            age_days = max(0, (now - created_dt).days) if created_dt else 0

            if _is_valid(assigned_name):
                m_as = _get_or_create_member(assigned_name)
                if m_as:
                    m_as["open_tasks_assigned"] += 1
                    if len(m_as["assigned_work_items"]) < 25:
                        m_as["assigned_work_items"].append({
                            "id": wid,
                            "title": wi_title or f"#{wid}",
                            "type": wi_type.capitalize() or "Task",
                            "state": state or "Active",
                            "changed_date": changed_date_str or "",
                            "days_old": age_days,
                        })
                    if age_days > m_as["oldest_open_task_days"]:
                        m_as["oldest_open_task_days"] = age_days
                        m_as["oldest_open_task"] = {
                            "id": wi.get("id"),
                            "title": wi.get("title") or fields.get("System.Title") or f"#{wi.get('id')}",
                            "type": wi_type.capitalize() or "Task",
                            "state": state or "Active",
                            "days_old": age_days,
                            "created_date": created_date_str or "Unknown",
                        }
                    days_idle = 0
                    if changed_date_raw:
                        dt_ch = parse_iso_datetime(changed_date_raw)
                        if dt_ch:
                            days_idle = max(0, (now - dt_ch).days)
                    else:
                        days_idle = 30
                    if days_idle >= 14:
                        m_as["stale_tasks_count"] += 1
                        stale_radar.append({
                            "id": wi.get("id"),
                            "title": wi.get("title") or fields.get("System.Title") or f"#{wi.get('id')}",
                            "type": wi_type.capitalize() or "Task",
                            "state": state or "Active",
                            "assigned_to": assigned_name,
                            "days_idle": days_idle,
                            "last_changed": changed_date_str or "Unknown",
                        })

        # Track Task Activation in timeframe
        activated_by = _clean_user_name(fields.get("Microsoft.VSTS.Common.ActivatedBy"))
        activated_date_raw = fields.get("Microsoft.VSTS.Common.ActivatedDate") or ""
        activated_date_str = str(activated_date_raw)[:10] if activated_date_raw else ""
        if activated_date_str and (filter_start_str <= activated_date_str < filter_end_str or timeframe == "all_time"):
            if _is_valid(activated_by):
                m_act = _get_or_create_member(activated_by)
                if m_act:
                    m_act["state_changes_count"] += 1
                    _track_activity_time(m_act, activated_date_raw, "state_change", f"Activated {wi_type.capitalize()} #{wid}: {wi_title[:60]}", repo_or_id=f"#{wid}")

        # Evaluate Completed Work Items within timeframe
        if is_closed_state:
            # If ClosedDate is recorded, strictly check ClosedDate; otherwise fall back to ChangedDate
            effective_close_raw = closed_date_raw or changed_date_raw
            effective_close_str = closed_date_str or changed_date_str

            is_completed_in_timeframe = False
            if filter_start_str and filter_end_str and effective_close_str:
                if filter_start_str <= effective_close_str < filter_end_str:
                    is_completed_in_timeframe = True
            elif timeframe == "all_time":
                is_completed_in_timeframe = True

            if is_completed_in_timeframe:
                effective_closer = closed_by or assigned_name or changed_by
                if _is_valid(effective_closer):
                    m = _get_or_create_member(effective_closer)
                    if m:
                        m["tasks_completed"] += 1
                        m["tasks_cleaned"] += 1
                        m["state_changes_count"] += 1
                        _track_activity_time(m, effective_close_raw, "task_close", f"Closed {wi_type.capitalize()} #{wid}: {wi_title[:60]}", repo_or_id=f"#{wid}")
                        if "bug" in wi_type or "defect" in wi_type or "problem" in wi_type:
                            m["bugs_resolved"] += 1
                        elif "story" in wi_type or "requirement" in wi_type or "pbi" in wi_type:
                            m["stories_completed"] += 1

                        # Track [<Type>_<nr>] structured syntax convention in title
                        if re.search(r"\[[A-Za-z0-9_<>-]+_\d+\]", wi_title, re.IGNORECASE):
                            m["structured_syntax_completed"] += 1

                        # Task turnaround speed
                        start_raw = activated_date_raw or created_date_raw
                        if start_raw and effective_close_raw:
                            try:
                                dt_s = parse_iso_datetime(start_raw)
                                dt_e = parse_iso_datetime(effective_close_raw)
                                if dt_s and dt_e and dt_e >= dt_s:
                                    t_hours = (dt_e - dt_s).total_seconds() / 3600.0
                                    m["_task_durations"].append(t_hours)
                                    if t_hours <= 24.0:
                                        m["tasks_fast_closed"] += 1
                            except Exception:
                                pass

        # Evaluate Created Work Items within timeframe
        if created_date_str and filter_start_str and filter_end_str:
            if filter_start_str <= created_date_str < filter_end_str or timeframe == "all_time":
                effective_creator = created_by or assigned_name
                if _is_valid(effective_creator):
                    m = _get_or_create_member(effective_creator)
                    if m:
                        m["tasks_created"] += 1
                        _track_activity_time(m, created_date_raw, "task_create", f"Created {wi_type.capitalize()} #{wid}: {wi_title[:60]}", repo_or_id=f"#{wid}")

    # 2. Process Recorded State Transition Events (Pushbacks, Reopenings & State Transitions)
    for ev in all_state_events:
        ev_date_raw = ev.get("recorded_at") or ""
        ev_date_str = ev_date_raw[:10]
        changer = _clean_user_name(ev.get("changed_by"))
        is_pushback = bool(ev.get("is_pushback", 0))

        if ev_date_str and (filter_start_str <= ev_date_str < filter_end_str or timeframe == "all_time"):
            if _is_valid(changer):
                m = _get_or_create_member(changer)
                if m:
                    m["state_changes_count"] += 1
                    if is_pushback:
                        m["pushbacks_count"] += 1
                    else:
                        m["tasks_cleaned"] += 1
                    _track_activity_time(m, ev_date_raw, "state_change", f"State transition #{ev.get('work_item_id')}", repo_or_id=f"#{ev.get('work_item_id')}")

    # 3. Process Pull Requests, Merges, Reviews & Approvals
    for pr in all_prs:
        raw = pr
        if isinstance(pr, dict) and "raw_json" in pr and isinstance(pr["raw_json"], str):
            try:
                raw = json.loads(pr["raw_json"])
            except Exception:
                raw = pr
        if not isinstance(raw, dict):
            raw = {}

        pr_id = raw.get("pullRequestId") or raw.get("id") or pr.get("id") or ""
        pr_title = str(raw.get("title") or pr.get("title") or "")
        pr_repo = str(raw.get("repository", {}).get("name") if isinstance(raw.get("repository"), dict) else pr.get("repo_id") or "")

        cb = _clean_user_name(
            raw.get("createdBy") or
            raw.get("created_by") or
            pr.get("created_by") or
            pr.get("createdBy")
        )

        clb = _clean_user_name(
            raw.get("closedBy") or
            raw.get("closed_by") or
            raw.get("autoCompleteSetBy") or
            (raw.get("lastMergeCommit", {}).get("author", {}).get("name") if isinstance(raw.get("lastMergeCommit"), dict) else None) or
            (raw.get("lastMergeCommit", {}).get("committer", {}).get("name") if isinstance(raw.get("lastMergeCommit"), dict) else None) or
            pr.get("closed_by") or
            pr.get("closedBy")
        )

        c_date_raw = (
            raw.get("creationDate") or
            raw.get("creationDateStr") or
            raw.get("creation_date") or
            raw.get("created_date") or
            pr.get("creationDate") or
            pr.get("creation_date") or
            pr.get("created_date") or
            ""
        )
        cl_date_raw = (
            raw.get("closedDate") or
            raw.get("closedDateStr") or
            raw.get("closed_date") or
            pr.get("closedDate") or
            pr.get("closed_date") or
            ""
        )

        if not cl_date_raw:
            st_text = str(raw.get("statusStr") or raw.get("status_str") or pr.get("status_str") or "")
            m_cl = re.search(r"\b(DON|COMPLETED|ABANDONED|CLOSED)\s+(\d{4}-\d{2}-\d{2})", st_text, re.I)
            if m_cl:
                cl_date_raw = m_cl.group(2)

        c_date_str = str(c_date_raw)[:10] if c_date_raw else ""
        cl_date_str = str(cl_date_raw)[:10] if cl_date_raw else ""

        status = str(
            raw.get("status") or
            raw.get("statusStr") or
            raw.get("norm_status") or
            pr.get("status") or
            pr.get("status_str") or
            ""
        ).lower()

        is_completed = (
            status in ("completed", "closed", "3", "don", "done") or
            "don " in status or
            "completed" in status or
            bool(cl_date_str and status not in ("abandoned", "active", "open", "1", "2"))
        )

        # Track weekly activity for streaks
        if cl_date_str:
            dt = parse_iso_datetime(cl_date_str)
            if dt:
                y, w, _ = dt.isocalendar()
                pr_sprint = f"week-{str(y)[-2:]}{w:02d}"
                if _is_valid(cb):
                    m = _get_or_create_member(cb)
                    if m:
                        m["weekly_activity_history"][pr_sprint] = m["weekly_activity_history"].get(pr_sprint, 0) + 1
                if _is_valid(clb) and clb != cb:
                    m = _get_or_create_member(clb)
                    if m:
                        m["weekly_activity_history"][pr_sprint] = m["weekly_activity_history"].get(pr_sprint, 0) + 1

        # Check PR creation timeframe (Feature branch started)
        if c_date_str and (filter_start_str <= c_date_str < filter_end_str or timeframe == "all_time"):
            if _is_valid(cb):
                m = _get_or_create_member(cb)
                if m:
                    m["prs_created"] += 1
                    m["branches_started"] += 1
                    m["commits_count"] += 1  # PR branch initiation commit
                    _track_activity_time(m, c_date_raw, "pr_create", f"Opened PR #{pr_id}: {pr_title[:60]}", repo_or_id=pr_repo)
                    if len(m["recent_prs"]) < 20:
                        m["recent_prs"].append({
                            "id": pr_id,
                            "title": pr_title,
                            "role": "Author",
                            "status": "Opened",
                            "date": c_date_str,
                            "repo": pr_repo
                        })

        # Extract Reviewers & Approvers list
        reviewers_list = raw.get("reviewers") or pr.get("reviewers") or []
        if isinstance(reviewers_list, str):
            try:
                reviewers_list = json.loads(reviewers_list)
            except Exception:
                reviewers_list = []

        approver_names = []
        for rev in reviewers_list:
            rev_name = _clean_user_name(rev)
            vote = 0
            if isinstance(rev, dict):
                vote = rev.get("vote", 0) or 0
                if rev.get("hasDeclined"):
                    vote = -10
            elif isinstance(rev, str):
                vote = 10

            if vote > 0 and _is_valid(rev_name):
                approver_names.append(rev_name)

            if _is_valid(rev_name) and rev_name != cb:
                rev_date_raw = cl_date_raw or c_date_raw
                rev_date_str = str(rev_date_raw)[:10] if rev_date_raw else ""

                if rev_date_str:
                    dt_rev = parse_iso_datetime(rev_date_str)
                    if dt_rev:
                        y_r, w_r, _ = dt_rev.isocalendar()
                        rev_sprint = f"week-{str(y_r)[-2:]}{w_r:02d}"
                        m_rev = _get_or_create_member(rev_name)
                        if m_rev:
                            m_rev["weekly_activity_history"][rev_sprint] = m_rev["weekly_activity_history"].get(rev_sprint, 0) + 1

                in_tf = False
                if rev_date_str:
                    in_tf = (filter_start_str <= rev_date_str < filter_end_str or timeframe == "all_time")
                else:
                    in_tf = (timeframe == "all_time")

                if in_tf:
                    m_rev = _get_or_create_member(rev_name)
                    if m_rev:
                        m_rev["prs_reviewed"] += 1
                        if vote > 0:
                            m_rev["prs_approved"] += 1
                        _track_activity_time(m_rev, rev_date_raw, "pr_review", f"Reviewed PR #{pr_id}: {pr_title[:60]}", repo_or_id=pr_repo)
                        if len(m_rev["recent_prs"]) < 20:
                            m_rev["recent_prs"].append({
                                "id": pr_id,
                                "title": pr_title,
                                "role": "Reviewer",
                                "status": "Approved" if vote > 0 else "Reviewed",
                                "date": rev_date_str,
                                "repo": pr_repo
                            })

        # Check PR closed timeframe (Feature branch closed/merged)
        if is_completed and cl_date_str and (filter_start_str <= cl_date_str < filter_end_str or timeframe == "all_time"):
            closer = clb
            if not _is_valid(closer):
                if approver_names:
                    closer = approver_names[0]
                elif _is_valid(cb):
                    closer = cb

            if _is_valid(closer):
                m = _get_or_create_member(closer)
                if m:
                    m["prs_closed"] += 1
                    m["branches_closed"] += 1
                    m["commits_count"] += 1  # Merge commit
                    _track_activity_time(m, cl_date_raw, "pr_merge", f"Merged PR #{pr_id}: {pr_title[:60]}", repo_or_id=pr_repo)
                    if len(m["recent_prs"]) < 20:
                        m["recent_prs"].append({
                            "id": pr_id,
                            "title": pr_title,
                            "role": "Closer",
                            "status": "Completed",
                            "date": cl_date_str,
                            "repo": pr_repo
                        })

            # Check PR turnaround speed
            if c_date_raw and cl_date_raw:
                try:
                    dt_c = parse_iso_datetime(c_date_raw)
                    dt_cl = parse_iso_datetime(cl_date_raw)
                    if dt_c and dt_cl and dt_cl >= dt_c:
                        diff_hours = (dt_cl - dt_c).total_seconds() / 3600.0
                        if diff_hours <= 24.0:
                            if _is_valid(cb):
                                m_cb = _get_or_create_member(cb)
                                if m_cb:
                                    m_cb["prs_fast_merged"] += 1
                        if _is_valid(closer):
                            m_cl = _get_or_create_member(closer)
                            if m_cl:
                                m_cl["_pr_durations"].append(diff_hours)
                except Exception:
                    pass

    # 3. Process Code Commits & Feature Branch Tips
    processed_commit_ids = set()
    if all_commits:
        for c in all_commits:
            c_id = c.get("commit_id") or c.get("commitId") or ""
            if c_id:
                processed_commit_ids.add(c_id)
            c_date_raw = c.get("committer_date") or c.get("author_date") or ""
            c_date_str = c_date_raw[:10]
            c_msg = str(c.get("comment") or "")
            c_repo = str(c.get("repo_name") or c.get("repo_id") or "")
            committer = _clean_user_name(c.get("committer_name") or c.get("author_name") or c.get("committer_email") or c.get("author_email"))

            # Track weekly activity for streaks
            if c_date_str and _is_valid(committer):
                dt = parse_iso_datetime(c_date_raw or c_date_str)
                if dt:
                    y, w, _ = dt.isocalendar()
                    cm_sprint = f"week-{str(y)[-2:]}{w:02d}"
                    m = _get_or_create_member(committer)
                    if m:
                        m["weekly_activity_history"][cm_sprint] = m["weekly_activity_history"].get(cm_sprint, 0) + 1

            # Timeframe evaluation
            if c_date_str and (filter_start_str <= c_date_str < filter_end_str or timeframe == "all_time"):
                if _is_valid(committer):
                    m = _get_or_create_member(committer)
                    if m:
                        m["commits_count"] += 1
                        _track_activity_time(m, c_date_raw, "commit", f"Commit {str(c_id)[:8]}: {c_msg[:60]}", repo_or_id=c_repo)
                        if len(m["recent_commits"]) < 20:
                            m["recent_commits"].append({
                                "id": str(c_id)[:8],
                                "comment": c_msg[:80],
                                "repo": c_repo,
                                "date": c_date_str
                            })

    # Process branch tips from all_branches that may not be in commits table yet
    for br in all_branches:
        b_cid = br.get("commit_id") or ""
        if b_cid and b_cid in processed_commit_ids:
            continue
        b_date_raw = br.get("commit_date", "")
        b_date = b_date_raw[:10]
        committer = _clean_user_name(br.get("committer"))
        if b_date and _is_valid(committer):
            dt = parse_iso_datetime(b_date_raw or b_date)
            if dt:
                y, w, _ = dt.isocalendar()
                br_sprint = f"week-{str(y)[-2:]}{w:02d}"
                m = _get_or_create_member(committer)
                if m:
                    m["weekly_activity_history"][br_sprint] = m["weekly_activity_history"].get(br_sprint, 0) + 1

        if b_date and (filter_start_str <= b_date < filter_end_str or timeframe == "all_time"):
            if _is_valid(committer):
                m = _get_or_create_member(committer)
                if m:
                    m["commits_count"] += 1
                    _track_activity_time(m, b_date_raw, "commit", f"Branch tip {br.get('branch_name')}", repo_or_id=br.get("repo_name"))

    # 4. Process Tags
    for tag in all_tags:
        t_date_raw = tag.get("commit_date", "")
        t_date = t_date_raw[:10]
        committer = _clean_user_name(tag.get("committer"))
        if t_date and (filter_start_str <= t_date < filter_end_str or timeframe == "all_time"):
            if _is_valid(committer):
                m = _get_or_create_member(committer)
                if m:
                    m["tags_pushed"] += 1
                    if not all_commits:
                        m["commits_count"] += 1
                    _track_activity_time(m, t_date_raw, "tag", f"Pushed tag {tag.get('tag_name')}", repo_or_id=tag.get("repo_name"))

    # 5. Process CI Builds & Pipeline Executions
    for b in all_builds:
        build_date_raw = b.get("finish_time") or b.get("start_time") or ""
        b_date = build_date_raw[:10]
        requester = b.get("requested_by")
        if b_date and filter_start_str <= b_date < filter_end_str:
            is_succ = b["result"] == "succeeded"
            is_fail = b["result"] in ("failed", "partiallysucceeded")
            if _is_valid(requester):
                m = _get_or_create_member(requester)
                if m:
                    m["builds_total"] += 1
                    if is_succ:
                        m["builds_succeeded"] += 1
                    if is_fail:
                        m["builds_failed"] += 1
                    _track_activity_time(m, build_date_raw, "build", f"Ran build {b.get('pipeline_name')} ({b.get('result')})", repo_or_id=b.get("pipeline_name"))


    # 6. Process Shifts & Predictability
    for user, shift_list in shifts_by_user.items():
        if user in members:
            # Count shifts in this timeframe
            relevant_shifts = [
                s for s in shift_list
                if (s.get("recorded_at") or "")[:10] >= filter_start_str and (s.get("recorded_at") or "")[:10] < filter_end_str
            ]
            members[user]["total_shifts"] = len(relevant_shifts)
            members[user]["total_delay_weeks"] = sum((s.get("delta_weeks") or 0) for s in relevant_shifts if (s.get("delta_weeks") or 0) > 0)

    # 7. Compute Streaks, Build Rates, Badges & Composite Scores
    # Prepare chronological list of past 12 sprint weeks
    recent_sprint_weeks = []
    base_dt = now
    for i in range(12):
        w_dt = base_dt - timedelta(days=i * 7)
        y, w, _ = w_dt.isocalendar()
        s_code = f"week-{str(y)[-2:]}{w:02d}"
        if s_code not in recent_sprint_weeks:
            recent_sprint_weeks.append(s_code)

    # Inject all configured alias profiles as distinct entries (greyed out / linked)
    for canon_name, aliases in canonical_to_aliases.items():
        for alias_name in aliases:
            a_clean = _clean_user_name(alias_name)
            if not a_clean or a_clean.lower() == canon_name.lower():
                continue
            if a_clean not in members:
                parts = a_clean.split()
                initials = (parts[0][0] + (parts[-1][0] if len(parts) > 1 else "")).upper() if parts else "??"
                members[a_clean] = {
                    "name": a_clean,
                    "initials": initials,
                    "aliases": [],
                    "is_aliased": True,
                    "aliased_to": canon_name,
                    "last_active_date": "",
                    "last_activity": None,
                    "recent_activities": [],
                    "assigned_work_items": [],
                    "recent_prs": [],
                    "recent_commits": [],
                    "_last_activity_dt": None,
                    "prs_created": 0,
                    "prs_closed": 0,
                    "prs_fast_merged": 0,
                    "prs_reviewed": 0,
                    "prs_approved": 0,
                    "tasks_created": 0,
                    "tasks_completed": 0,
                    "bugs_resolved": 0,
                    "stories_completed": 0,
                    "commits_count": 0,
                    "branches_started": 0,
                    "branches_closed": 0,
                    "tags_pushed": 0,
                    "builds_total": 0,
                    "builds_succeeded": 0,
                    "builds_failed": 0,
                    "build_success_rate": 100.0,
                    "total_shifts": 0,
                    "total_delay_weeks": 0,
                    "avg_pr_hours": 0.0,
                    "state_changes_count": 0,
                    "pushbacks_count": 0,
                    "tasks_cleaned": 0,
                    "stale_tasks_count": 0,
                    "open_tasks_assigned": 0,
                    "oldest_open_task_days": 0,
                    "oldest_open_task": None,
                    "tasks_fast_closed": 0,
                    "avg_task_turnaround_hours": 0.0,
                    "fastest_task_hours": 0.0,
                    "task_evidences_count": 0,
                    "structured_syntax_completed": 0,
                    "is_cleaner": False,
                    "is_decliner": False,
                    "is_ignorer": False,
                    "night_activities": 0,
                    "early_bird_activities": 0,
                    "weekend_activities": 0,
                    "daytime_activities": 0,
                    "evening_activities": 0,
                    "friday_afternoon_activities": 0,
                    "time_stats": {
                        "total_actions": 0,
                        "daytime_count": 0,
                        "early_bird_count": 0,
                        "evening_count": 0,
                        "night_count": 0,
                        "weekend_count": 0,
                        "friday_pm_count": 0,
                        "daytime_pct": 0.0,
                        "night_pct": 0.0,
                        "weekend_pct": 0.0,
                        "early_bird_pct": 0.0,
                        "hourly_distribution": [0] * 24,
                        "daily_distribution": [0] * 7,
                        "peak_hour": 14,
                        "peak_hour_label": "14:00",
                        "peak_day": "Monday",
                        "persona": f"🔗 Alias of {canon_name}",
                    },
                    "_pr_durations": [],
                    "_task_durations": [],
                    "recent_achievements": [],
                    "weekly_activity_history": {},
                    "current_streak_weeks": 0,
                    "best_streak_weeks": 0,
                    "score": 0,
                    "badges": [],
                    "badges_count": 0,
                    "rank": None,
                }
            else:
                members[a_clean]["is_aliased"] = True
                members[a_clean]["aliased_to"] = canon_name
                members[a_clean]["score"] = 0
                members[a_clean]["badges"] = []
                members[a_clean]["badges_count"] = 0
                members[a_clean]["rank"] = None
                members[a_clean]["current_streak_weeks"] = 0
                members[a_clean]["best_streak_weeks"] = 0

    member_list = list(members.values())

    for m in member_list:
        if m.get("is_aliased"):
            continue
        # Calculate Average PR Turnaround
        if m["_pr_durations"]:
            m["avg_pr_hours"] = round(sum(m["_pr_durations"]) / len(m["_pr_durations"]), 1)

        # Calculate Task Turnaround Metrics
        if m["_task_durations"]:
            m["avg_task_turnaround_hours"] = round(sum(m["_task_durations"]) / len(m["_task_durations"]), 1)
            m["fastest_task_hours"] = round(min(m["_task_durations"]), 1)

        # Calculate Build Success Rate
        if m["builds_total"] > 0:
            m["build_success_rate"] = round((m["builds_succeeded"] / m["builds_total"]) * 100.0, 1)

        # Calculate Weekly Streak
        cur_streak = 0
        for s_code in recent_sprint_weeks:
            if m["weekly_activity_history"].get(s_code, 0) > 0:
                cur_streak += 1
            else:
                break
        m["current_streak_weeks"] = cur_streak

        # Compute Time Profile & Persona
        tot_act = m["time_stats"]["total_actions"]
        if tot_act > 0:
            m["time_stats"]["daytime_pct"] = round((m["time_stats"]["daytime_count"] / tot_act) * 100.0, 1)
            m["time_stats"]["night_pct"] = round((m["time_stats"]["night_count"] / tot_act) * 100.0, 1)
            m["time_stats"]["weekend_pct"] = round((m["time_stats"]["weekend_count"] / tot_act) * 100.0, 1)
            m["time_stats"]["early_bird_pct"] = round((m["time_stats"]["early_bird_count"] / tot_act) * 100.0, 1)

            # Peak hour
            peak_h = max(range(24), key=lambda h: m["time_stats"]["hourly_distribution"][h])
            m["time_stats"]["peak_hour"] = peak_h
            m["time_stats"]["peak_hour_label"] = f"{peak_h:02d}:00"

            # Peak day
            day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            peak_d = max(range(7), key=lambda d: m["time_stats"]["daily_distribution"][d])
            m["time_stats"]["peak_day"] = day_names[peak_d]

            # Persona determination
            if m["night_activities"] >= 3 and m["night_activities"] >= m["daytime_activities"] * 0.4:
                m["time_stats"]["persona"] = "🦉 Night Owl"
            elif m["weekend_activities"] >= 2 and m["weekend_activities"] >= tot_act * 0.25:
                m["time_stats"]["persona"] = "⚡ Weekend Warrior"
            elif m["early_bird_activities"] >= 3 and m["early_bird_activities"] >= m["daytime_activities"] * 0.4:
                m["time_stats"]["persona"] = "🌅 Early Bird"
            elif tot_act >= 5 and (m["daytime_activities"] / tot_act) >= 0.85 and m["weekend_activities"] == 0 and m["night_activities"] == 0:
                m["time_stats"]["persona"] = "🧘 Zen Balanced"
            elif m["friday_afternoon_activities"] >= 2:
                m["time_stats"]["persona"] = "🚀 Friday Finisher"
            else:
                m["time_stats"]["persona"] = "☀️ Daytime Core"

        # Check if member had actual contribution activity within the selected timeframe
        has_current_activity = (
            m["prs_closed"] > 0
            or m["prs_created"] > 0
            or m["commits_count"] > 0
            or m["branches_started"] > 0
            or m["branches_closed"] > 0
            or m["tasks_completed"] > 0
            or m["tasks_created"] > 0
            or m["bugs_resolved"] > 0
            or m["stories_completed"] > 0
            or m["prs_reviewed"] > 0
            or m["prs_approved"] > 0
            or m["tags_pushed"] > 0
            or m["builds_total"] > 0
            or m["state_changes_count"] > 0
            or m["pushbacks_count"] > 0
            or m["tasks_cleaned"] > 0
            or m["tasks_fast_closed"] > 0
            or m["task_evidences_count"] > 0
            or m["structured_syntax_completed"] > 0
        )

        def _build_awarded_badge(b_key, tier, times=1, metric_label=""):
            b_def = BADGE_DEFINITIONS.get(b_key, {})
            if not b_def:
                return None
            tiers_dict = b_def.get("tiers", {})
            t_info = tiers_dict.get(tier, {})
            tier_icon = "🥇" if tier == "gold" else ("🥈" if tier == "silver" else "🥉")
            return {
                "id": b_def["id"],
                "base_id": b_def["id"],
                "name": t_info.get("name", b_def.get("name", b_key)),
                "base_name": b_def.get("base_name", b_def.get("name", b_key)),
                "icon": b_def.get("icon", "🎖️"),
                "category": b_def.get("category", "other"),
                "category_name": b_def.get("category_name", ""),
                "category_icon": b_def.get("category_icon", "🎖️"),
                "tier": tier,
                "tier_label": tier.capitalize(),
                "tier_icon": tier_icon,
                "color": t_info.get("color", b_def.get("color", "#ffd700")),
                "bg_color": t_info.get("bg_color", b_def.get("bg_color", "#21262d")),
                "description": t_info.get("criteria", b_def.get("description", "")),
                "times_achieved": times,
                "metric_label": metric_label or str(times),
                "points": t_info.get("points", 10)
            }

        # Compute Badges - strictly only awarded if member had actual activity in the timeframe
        badges = []
        if has_current_activity:
            # 1. PRs & Reviews
            if m["prs_created"] >= 6:
                badges.append(_build_awarded_badge("pr_dynamo", "gold", times=m["prs_created"], metric_label=f"{m['prs_created']} PRs"))
            elif m["prs_created"] >= 3:
                badges.append(_build_awarded_badge("pr_dynamo", "silver", times=m["prs_created"], metric_label=f"{m['prs_created']} PRs"))
            elif m["prs_created"] >= 1:
                badges.append(_build_awarded_badge("pr_dynamo", "bronze", times=m["prs_created"], metric_label=f"{m['prs_created']} PR"))

            if m["prs_closed"] >= 6:
                badges.append(_build_awarded_badge("the_closer", "gold", times=m["prs_closed"], metric_label=f"{m['prs_closed']} PRs merged"))
            elif m["prs_closed"] >= 3:
                badges.append(_build_awarded_badge("the_closer", "silver", times=m["prs_closed"], metric_label=f"{m['prs_closed']} PRs merged"))
            elif m["prs_closed"] >= 1:
                badges.append(_build_awarded_badge("the_closer", "bronze", times=m["prs_closed"], metric_label=f"{m['prs_closed']} PR merged"))

            if m["prs_reviewed"] >= 8 and m["prs_approved"] >= 4:
                badges.append(_build_awarded_badge("eagle_eye", "gold", times=m["prs_reviewed"], metric_label=f"{m['prs_reviewed']} reviews"))
            elif m["prs_reviewed"] >= 3:
                badges.append(_build_awarded_badge("eagle_eye", "silver", times=m["prs_reviewed"], metric_label=f"{m['prs_reviewed']} reviews"))
            elif m["prs_reviewed"] >= 1:
                badges.append(_build_awarded_badge("eagle_eye", "bronze", times=m["prs_reviewed"], metric_label=f"{m['prs_reviewed']} review"))

            if m["prs_fast_merged"] >= 4:
                badges.append(_build_awarded_badge("speed_demon", "gold", times=m["prs_fast_merged"], metric_label=f"{m['prs_fast_merged']} fast PRs (<12h)"))
            elif m["prs_fast_merged"] >= 2:
                badges.append(_build_awarded_badge("speed_demon", "silver", times=m["prs_fast_merged"], metric_label=f"{m['prs_fast_merged']} fast PRs (<24h)"))
            elif m["prs_fast_merged"] >= 1:
                badges.append(_build_awarded_badge("speed_demon", "bronze", times=m["prs_fast_merged"], metric_label=f"{m['prs_fast_merged']} fast PR (<24h)"))

            # 2. Work Items
            if m["tasks_completed"] >= 10:
                badges.append(_build_awarded_badge("task_crusher", "gold", times=m["tasks_completed"], metric_label=f"{m['tasks_completed']} items"))
            elif m["tasks_completed"] >= 5:
                badges.append(_build_awarded_badge("task_crusher", "silver", times=m["tasks_completed"], metric_label=f"{m['tasks_completed']} items"))
            elif m["tasks_completed"] >= 1:
                badges.append(_build_awarded_badge("task_crusher", "bronze", times=m["tasks_completed"], metric_label=f"{m['tasks_completed']} item"))

            if m["bugs_resolved"] >= 6:
                badges.append(_build_awarded_badge("bug_slayer", "gold", times=m["bugs_resolved"], metric_label=f"{m['bugs_resolved']} bugs"))
            elif m["bugs_resolved"] >= 3:
                badges.append(_build_awarded_badge("bug_slayer", "silver", times=m["bugs_resolved"], metric_label=f"{m['bugs_resolved']} bugs"))
            elif m["bugs_resolved"] >= 1:
                badges.append(_build_awarded_badge("bug_slayer", "bronze", times=m["bugs_resolved"], metric_label=f"{m['bugs_resolved']} bug"))

            if m["tasks_created"] >= 10:
                badges.append(_build_awarded_badge("task_architect", "gold", times=m["tasks_created"], metric_label=f"{m['tasks_created']} created"))
            elif m["tasks_created"] >= 5:
                badges.append(_build_awarded_badge("task_architect", "silver", times=m["tasks_created"], metric_label=f"{m['tasks_created']} created"))
            elif m["tasks_created"] >= 2:
                badges.append(_build_awarded_badge("task_architect", "bronze", times=m["tasks_created"], metric_label=f"{m['tasks_created']} created"))

            if m["tasks_completed"] >= 6 and m["total_delay_weeks"] == 0:
                badges.append(_build_awarded_badge("sprint_sniper", "gold", times=m["tasks_completed"], metric_label=f"{m['tasks_completed']} on-time"))
            elif m["tasks_completed"] >= 3 and m["total_delay_weeks"] == 0:
                badges.append(_build_awarded_badge("sprint_sniper", "silver", times=m["tasks_completed"], metric_label=f"{m['tasks_completed']} on-time"))
            elif m["tasks_completed"] >= 1 and m["total_delay_weeks"] == 0:
                badges.append(_build_awarded_badge("sprint_sniper", "bronze", times=m["tasks_completed"], metric_label=f"{m['tasks_completed']} on-time"))

            if m["tasks_fast_closed"] >= 6:
                badges.append(_build_awarded_badge("speedy_task_closer", "gold", times=m["tasks_fast_closed"], metric_label=f"{m['tasks_fast_closed']} fast closes (<12h)"))
            elif m["tasks_fast_closed"] >= 2 or (m["tasks_completed"] >= 2 and m["avg_task_turnaround_hours"] > 0 and m["avg_task_turnaround_hours"] <= 24.0):
                badges.append(_build_awarded_badge("speedy_task_closer", "silver", times=m["tasks_fast_closed"] or m["tasks_completed"], metric_label=f"{m['tasks_fast_closed'] or m['tasks_completed']} fast closes (<24h)"))
            elif m["tasks_fast_closed"] >= 1:
                badges.append(_build_awarded_badge("speedy_task_closer", "bronze", times=m["tasks_fast_closed"], metric_label=f"{m['tasks_fast_closed']} fast close (<24h)"))

            # 3. Code & Branching
            if m["commits_count"] >= 15:
                badges.append(_build_awarded_badge("commit_machine", "gold", times=m["commits_count"], metric_label=f"{m['commits_count']} commits"))
            elif m["commits_count"] >= 6:
                badges.append(_build_awarded_badge("commit_machine", "silver", times=m["commits_count"], metric_label=f"{m['commits_count']} commits"))
            elif m["commits_count"] >= 2:
                badges.append(_build_awarded_badge("commit_machine", "bronze", times=m["commits_count"], metric_label=f"{m['commits_count']} commits"))

            if m["branches_started"] >= 6:
                badges.append(_build_awarded_badge("branch_architect", "gold", times=m["branches_started"], metric_label=f"{m['branches_started']} branches"))
            elif m["branches_started"] >= 3:
                badges.append(_build_awarded_badge("branch_architect", "silver", times=m["branches_started"], metric_label=f"{m['branches_started']} branches"))
            elif m["branches_started"] >= 1:
                badges.append(_build_awarded_badge("branch_architect", "bronze", times=m["branches_started"], metric_label=f"{m['branches_started']} branch"))

            if m["structured_syntax_completed"] >= 6:
                badges.append(_build_awarded_badge("syntax_master", "gold", times=m["structured_syntax_completed"], metric_label=f"{m['structured_syntax_completed']} items"))
            elif m["structured_syntax_completed"] >= 3:
                badges.append(_build_awarded_badge("syntax_master", "silver", times=m["structured_syntax_completed"], metric_label=f"{m['structured_syntax_completed']} items"))
            elif m["structured_syntax_completed"] >= 1:
                badges.append(_build_awarded_badge("syntax_master", "bronze", times=m["structured_syntax_completed"], metric_label=f"{m['structured_syntax_completed']} item"))

            # 4. CI/CD & Releases
            if m["builds_succeeded"] >= 5 and m["builds_failed"] == 0:
                badges.append(_build_awarded_badge("ci_hero", "gold", times=m["builds_succeeded"], metric_label=f"{m['builds_succeeded']} builds"))
            elif m["builds_succeeded"] >= 2 and m["builds_failed"] == 0:
                badges.append(_build_awarded_badge("ci_hero", "silver", times=m["builds_succeeded"], metric_label=f"{m['builds_succeeded']} builds"))
            elif m["builds_succeeded"] >= 1 and m["builds_failed"] == 0:
                badges.append(_build_awarded_badge("ci_hero", "bronze", times=m["builds_succeeded"], metric_label=f"{m['builds_succeeded']} build"))

            if m["tags_pushed"] >= 4:
                badges.append(_build_awarded_badge("tag_hero", "gold", times=m["tags_pushed"], metric_label=f"{m['tags_pushed']} tags"))
            elif m["tags_pushed"] >= 2:
                badges.append(_build_awarded_badge("tag_hero", "silver", times=m["tags_pushed"], metric_label=f"{m['tags_pushed']} tags"))
            elif m["tags_pushed"] >= 1:
                badges.append(_build_awarded_badge("tag_hero", "bronze", times=m["tags_pushed"], metric_label=f"{m['tags_pushed']} tag"))

            # 5. Quality & Grooming
            if m["tasks_cleaned"] >= 8 or m["state_changes_count"] >= 10:
                badges.append(_build_awarded_badge("the_cleaner", "gold", times=m["tasks_cleaned"], metric_label=f"{m['tasks_cleaned']} groomed"))
                m["is_cleaner"] = True
            elif m["tasks_cleaned"] >= 3 or m["state_changes_count"] >= 4:
                badges.append(_build_awarded_badge("the_cleaner", "silver", times=m["tasks_cleaned"], metric_label=f"{m['tasks_cleaned']} groomed"))
                m["is_cleaner"] = True
            elif m["tasks_cleaned"] >= 1 or m["state_changes_count"] >= 1:
                badges.append(_build_awarded_badge("the_cleaner", "bronze", times=m["tasks_cleaned"], metric_label=f"{m['tasks_cleaned']} groomed"))

            if m["pushbacks_count"] >= 5:
                badges.append(_build_awarded_badge("the_decliner", "gold", times=m["pushbacks_count"], metric_label=f"{m['pushbacks_count']} pushbacks"))
                m["is_decliner"] = True
            elif m["pushbacks_count"] >= 2:
                badges.append(_build_awarded_badge("the_decliner", "silver", times=m["pushbacks_count"], metric_label=f"{m['pushbacks_count']} pushbacks"))
                m["is_decliner"] = True
            elif m["pushbacks_count"] >= 1:
                badges.append(_build_awarded_badge("the_decliner", "bronze", times=m["pushbacks_count"], metric_label=f"{m['pushbacks_count']} pushback"))
                m["is_decliner"] = True

            if m["state_changes_count"] >= 10:
                badges.append(_build_awarded_badge("state_mover", "gold", times=m["state_changes_count"], metric_label=f"{m['state_changes_count']} transitions"))
            elif m["state_changes_count"] >= 5:
                badges.append(_build_awarded_badge("state_mover", "silver", times=m["state_changes_count"], metric_label=f"{m['state_changes_count']} transitions"))
            elif m["state_changes_count"] >= 2:
                badges.append(_build_awarded_badge("state_mover", "bronze", times=m["state_changes_count"], metric_label=f"{m['state_changes_count']} transitions"))

            if m["stale_tasks_count"] == 0 and m["open_tasks_assigned"] >= 5:
                badges.append(_build_awarded_badge("stale_sheriff", "gold", times=m["open_tasks_assigned"], metric_label=f"{m['open_tasks_assigned']} active items"))
            elif m["stale_tasks_count"] == 0 and m["open_tasks_assigned"] >= 3:
                badges.append(_build_awarded_badge("stale_sheriff", "silver", times=m["open_tasks_assigned"], metric_label=f"{m['open_tasks_assigned']} active items"))
            elif m["stale_tasks_count"] == 0 and m["open_tasks_assigned"] >= 1:
                badges.append(_build_awarded_badge("stale_sheriff", "bronze", times=m["open_tasks_assigned"], metric_label=f"{m['open_tasks_assigned']} active items"))

            if m["task_evidences_count"] >= 10:
                badges.append(_build_awarded_badge("evidence_master", "gold", times=m["task_evidences_count"], metric_label=f"{m['task_evidences_count']} links"))
            elif m["task_evidences_count"] >= 5:
                badges.append(_build_awarded_badge("evidence_master", "silver", times=m["task_evidences_count"], metric_label=f"{m['task_evidences_count']} links"))
            elif m["task_evidences_count"] >= 2:
                badges.append(_build_awarded_badge("evidence_master", "bronze", times=m["task_evidences_count"], metric_label=f"{m['task_evidences_count']} links"))

            if m["oldest_open_task_days"] >= 90:
                badges.append(_build_awarded_badge("relic_keeper", "gold", times=m["oldest_open_task_days"], metric_label=f"{m['oldest_open_task_days']}d idle"))
            elif m["oldest_open_task_days"] >= 60:
                badges.append(_build_awarded_badge("relic_keeper", "silver", times=m["oldest_open_task_days"], metric_label=f"{m['oldest_open_task_days']}d idle"))
            elif m["oldest_open_task_days"] >= 30:
                badges.append(_build_awarded_badge("relic_keeper", "bronze", times=m["oldest_open_task_days"], metric_label=f"{m['oldest_open_task_days']}d idle"))

            # 6. Working Habits & Rhythm
            if m["night_activities"] >= 6:
                badges.append(_build_awarded_badge("night_owl", "gold", times=m["night_activities"], metric_label=f"{m['night_activities']} acts"))
            elif m["night_activities"] >= 3:
                badges.append(_build_awarded_badge("night_owl", "silver", times=m["night_activities"], metric_label=f"{m['night_activities']} acts"))
            elif m["night_activities"] >= 1:
                badges.append(_build_awarded_badge("night_owl", "bronze", times=m["night_activities"], metric_label=f"{m['night_activities']} act"))

            if m["early_bird_activities"] >= 6:
                badges.append(_build_awarded_badge("early_bird", "gold", times=m["early_bird_activities"], metric_label=f"{m['early_bird_activities']} acts"))
            elif m["early_bird_activities"] >= 3:
                badges.append(_build_awarded_badge("early_bird", "silver", times=m["early_bird_activities"], metric_label=f"{m['early_bird_activities']} acts"))
            elif m["early_bird_activities"] >= 1:
                badges.append(_build_awarded_badge("early_bird", "bronze", times=m["early_bird_activities"], metric_label=f"{m['early_bird_activities']} act"))

            if m["weekend_activities"] >= 6:
                badges.append(_build_awarded_badge("weekend_warrior", "gold", times=m["weekend_activities"], metric_label=f"{m['weekend_activities']} acts"))
            elif m["weekend_activities"] >= 3:
                badges.append(_build_awarded_badge("weekend_warrior", "silver", times=m["weekend_activities"], metric_label=f"{m['weekend_activities']} acts"))
            elif m["weekend_activities"] >= 1:
                badges.append(_build_awarded_badge("weekend_warrior", "bronze", times=m["weekend_activities"], metric_label=f"{m['weekend_activities']} act"))

            if tot_act >= 6 and (m["daytime_activities"] / tot_act) >= 0.95 and m["weekend_activities"] == 0 and m["night_activities"] == 0:
                badges.append(_build_awarded_badge("zen_balancer", "gold", times=m["daytime_activities"], metric_label=f"{m['daytime_activities']} day acts"))
            elif tot_act >= 3 and (m["daytime_activities"] / tot_act) >= 0.85 and m["weekend_activities"] == 0 and m["night_activities"] == 0:
                badges.append(_build_awarded_badge("zen_balancer", "silver", times=m["daytime_activities"], metric_label=f"{m['daytime_activities']} day acts"))
            elif tot_act >= 2 and (m["daytime_activities"] / tot_act) >= 0.75 and m["weekend_activities"] == 0:
                badges.append(_build_awarded_badge("zen_balancer", "bronze", times=m["daytime_activities"], metric_label=f"{m['daytime_activities']} day acts"))

            if m["friday_afternoon_activities"] >= 4:
                badges.append(_build_awarded_badge("friday_hero", "gold", times=m["friday_afternoon_activities"], metric_label=f"{m['friday_afternoon_activities']} deliveries"))
            elif m["friday_afternoon_activities"] >= 2:
                badges.append(_build_awarded_badge("friday_hero", "silver", times=m["friday_afternoon_activities"], metric_label=f"{m['friday_afternoon_activities']} deliveries"))
            elif m["friday_afternoon_activities"] >= 1:
                badges.append(_build_awarded_badge("friday_hero", "bronze", times=m["friday_afternoon_activities"], metric_label=f"{m['friday_afternoon_activities']} delivery"))

            # 7. Streaks
            if m["current_streak_weeks"] >= 8:
                badges.append(_build_awarded_badge("streak_master", "gold", times=m["current_streak_weeks"], metric_label=f"{m['current_streak_weeks']} wks"))
            elif m["current_streak_weeks"] >= 4:
                badges.append(_build_awarded_badge("streak_master", "silver", times=m["current_streak_weeks"], metric_label=f"{m['current_streak_weeks']} wks"))
            elif m["current_streak_weeks"] >= 2:
                badges.append(_build_awarded_badge("streak_master", "bronze", times=m["current_streak_weeks"], metric_label=f"{m['current_streak_weeks']} wks"))

        # Determine Ignorer / Stasher persona
        if m["stale_tasks_count"] >= 2 and m["state_changes_count"] == 0:
            m["is_ignorer"] = True
            m["time_stats"]["persona"] = "💤 Backlog Stasher"
        elif m["pushbacks_count"] >= 2:
            m["time_stats"]["persona"] = "🛡️ The Gatekeeper"
        elif m["tasks_cleaned"] >= 4:
            m["time_stats"]["persona"] = "🧹 The Cleaner"

        m["badges"] = badges
        m["badges_count"] = len(badges)
        if not m.get("last_active_relative") and m.get("_last_activity_dt"):
            m["last_active_relative"] = format_relative_time(m["_last_activity_dt"])
        m.pop("_last_activity_dt", None)

        # Composite Motivation Score Formula:
        # Strictly only calculated if member has actual activity in timeframe
        if has_current_activity:
            m["has_activity"] = True
            pos_score = (
                m["prs_closed"] * active_score_config["prs_closed"]
                + m["prs_created"] * active_score_config["prs_created"]
                + m["commits_count"] * active_score_config["commits_count"]
                + m["branches_closed"] * active_score_config["branches_closed"]
                + m["tasks_completed"] * active_score_config["tasks_completed"]
                + m["tasks_created"] * active_score_config["tasks_created"]
                + m["bugs_resolved"] * active_score_config["bugs_resolved"]
                + m["stories_completed"] * active_score_config["stories_completed"]
                + m["prs_approved"] * active_score_config["prs_approved"]
                + m["prs_reviewed"] * active_score_config["prs_reviewed"]
                + m["tags_pushed"] * active_score_config["tags_pushed"]
                + m["builds_succeeded"] * active_score_config["builds_succeeded"]
                + m["tasks_cleaned"] * active_score_config["tasks_cleaned"]
                + m["pushbacks_count"] * active_score_config["pushbacks_count"]
                + m["tasks_fast_closed"] * active_score_config["tasks_fast_closed"]
                + min(m["task_evidences_count"], 25) * active_score_config["task_evidences_count"]
                + (m["structured_syntax_completed"] * active_score_config["structured_syntax_completed"])
                + len(badges) * active_score_config["badge_bonus"]
                + m["current_streak_weeks"] * active_score_config["streak_week_bonus"]
            )
            neg_score = (
                (m["total_delay_weeks"] * active_score_config["delay_week_penalty"])
                + (m["builds_failed"] * active_score_config["build_failed_penalty"])
                + (min(m["stale_tasks_count"], 4) * active_score_config["stale_task_penalty"])
            )
            raw_final = pos_score - neg_score
            m["score"] = max(0, raw_final)
        else:
            m["has_activity"] = False
            m["score"] = 0
            m["badges"] = []
            m["badges_count"] = 0

    # Award Sprint MVP badges to podium scorers (strictly only members with score > 0 and activity)
    sorted_by_score = [m for m in member_list if not m.get("is_aliased") and m.get("has_activity") and m.get("score", 0) > 0]
    sorted_by_score.sort(key=lambda x: x["score"], reverse=True)
    if sorted_by_score:
        if len(sorted_by_score) > 0:
            mvp1 = sorted_by_score[0]
            if not any(b["id"] == "sprint_mvp" for b in mvp1["badges"]):
                mvp1["badges"].insert(0, _build_awarded_badge("sprint_mvp", "gold", times=1, metric_label=f"Rank #1 ({mvp1['score']} pts)"))
                mvp1["badges_count"] = len(mvp1["badges"])
        if len(sorted_by_score) > 1:
            mvp2 = sorted_by_score[1]
            if not any(b["id"] == "sprint_mvp" for b in mvp2["badges"]):
                mvp2["badges"].insert(0, _build_awarded_badge("sprint_mvp", "silver", times=1, metric_label=f"Rank #2 ({mvp2['score']} pts)"))
                mvp2["badges_count"] = len(mvp2["badges"])
        if len(sorted_by_score) > 2:
            mvp3 = sorted_by_score[2]
            if not any(b["id"] == "sprint_mvp" for b in mvp3["badges"]):
                mvp3["badges"].insert(0, _build_awarded_badge("sprint_mvp", "bronze", times=1, metric_label=f"Rank #3 ({mvp3['score']} pts)"))
                mvp3["badges_count"] = len(mvp3["badges"])

    # Build cross-lookup of badge achievers and enrich all_badges
    badge_achievers_map = {}
    for m in member_list:
        for b in m.get("badges", []):
            b_id = b.get("id") or b.get("base_id")
            if b_id:
                badge_achievers_map.setdefault(b_id, []).append({
                    "name": m["name"],
                    "initials": m["initials"],
                    "tier": b.get("tier", "bronze"),
                    "tier_label": (b.get("tier") or "bronze").capitalize(),
                    "tier_icon": "🥇" if b.get("tier") == "gold" else ("🥈" if b.get("tier") == "silver" else "🥉"),
                    "badge_name": b.get("name", ""),
                    "color": b.get("color", "#ffd700"),
                    "bg_color": b.get("bg_color", "#21262d"),
                    "times_achieved": b.get("times_achieved", 1),
                    "metric_label": b.get("metric_label", ""),
                    "score": m["score"],
                    "last_active": m.get("last_active_date", "")
                })

    all_badges_enriched = []
    tier_weight = {"gold": 3, "silver": 2, "bronze": 1}
    for b_key, b_def in BADGE_DEFINITIONS.items():
        b_copy = dict(b_def)
        achievers = badge_achievers_map.get(b_key, [])
        achievers_sorted = sorted(achievers, key=lambda a: (tier_weight.get(a["tier"], 0), a["score"]), reverse=True)
        b_copy["achievers"] = achievers_sorted
        b_copy["achievers_count"] = len(achievers)
        b_copy["gold_count"] = sum(1 for a in achievers if a["tier"] == "gold")
        b_copy["silver_count"] = sum(1 for a in achievers if a["tier"] == "silver")
        b_copy["bronze_count"] = sum(1 for a in achievers if a["tier"] == "bronze")
        all_badges_enriched.append(b_copy)

    # Group into sorted categories
    badge_categories = []
    for cat_id, cat_meta in BADGE_CATEGORIES.items():
        cat_badges = [b for b in all_badges_enriched if b.get("category") == cat_id]
        unique_members_in_cat = set()
        for b in cat_badges:
            for a in b.get("achievers", []):
                unique_members_in_cat.add(a["name"])
        badge_categories.append({
            "id": cat_id,
            "name": cat_meta["name"],
            "icon": cat_meta["icon"],
            "description": cat_meta["description"],
            "badges": cat_badges,
            "total_badges": len(cat_badges),
            "total_achievers": len(unique_members_in_cat),
            "achievers_count": len(unique_members_in_cat)
        })

    # 8. Generate Category Leaderboards (Top performers per category - excluding aliased profiles)
    def _make_leaderboard(key, title, icon, unit="items", reverse_sort=True):
        filtered = [m for m in member_list if not m.get("is_aliased") and m.get(key, 0) > 0 and (m.get("has_activity") if key == "score" else True)]
        sorted_m = sorted(filtered, key=lambda x: x.get(key, 0), reverse=reverse_sort)
        entries = []
        for rank, item in enumerate(sorted_m[:10], start=1):
            entries.append({
                "rank": rank,
                "name": item["name"],
                "initials": item["initials"],
                "value": item[key],
                "unit": unit,
                "score": item["score"],
                "badges_count": item["badges_count"],
                "streak": item["current_streak_weeks"],
                "is_top_3": rank <= 3,
                "medal": "🥇" if rank == 1 else ("🥈" if rank == 2 else ("🥉" if rank == 3 else f"#{rank}"))
            })
        return {
            "category_id": key,
            "title": title,
            "icon": icon,
            "leader": entries[0] if entries else None,
            "entries": entries,
            "total_contributors": len(entries)
        }


    leaderboard_prs_closed = _make_leaderboard("prs_closed", "The Closer (PRs Merged)", "🏁", "PRs")
    leaderboard_prs_created = _make_leaderboard("prs_created", "PR Pioneer (PRs Started)", "🔀", "PRs")
    leaderboard_commits = _make_leaderboard("commits_count", "Code Committer (Commits)", "💻", "commits")
    leaderboard_branches_started = _make_leaderboard("branches_started", "Branch Pioneer (Branches Started)", "🌳", "branches")
    leaderboard_branches_closed = _make_leaderboard("branches_closed", "Branch Closer (Branches Merged)", "🌿", "branches")
    leaderboard_tasks_completed = _make_leaderboard("tasks_completed", "Task Crusher (Tasks Done)", "🔨", "tasks")
    leaderboard_bugs_resolved = _make_leaderboard("bugs_resolved", "Bug Hunter (Defects Fixed)", "🛡️", "bugs")
    leaderboard_prs_reviewed = _make_leaderboard("prs_reviewed", "Review Rockstar (Code Reviews)", "🔍", "reviews")
    leaderboard_prs_approved = _make_leaderboard("prs_approved", "PR Accepter (PRs Approved)", "✅", "approved")
    leaderboard_tags = _make_leaderboard("tags_pushed", "Release Titan (Tags Pushed)", "🏷️", "tags")
    leaderboard_builds = _make_leaderboard("builds_succeeded", "Build Master (Successful Builds)", "🏗️", "builds")
    leaderboard_streaks = _make_leaderboard("current_streak_weeks", "Streak Champion (Weekly Streak)", "🔥", "wks")
    leaderboard_cleaners = _make_leaderboard("tasks_cleaned", "The Cleaner (State Grooming)", "🧹", "groomed")
    leaderboard_decliners = _make_leaderboard("pushbacks_count", "The Gatekeeper (Reopened / Pushed Back)", "🛡️", "pushbacks")
    leaderboard_state_movers = _make_leaderboard("state_changes_count", "State Drivers (Transitions)", "🚀", "changes")
    leaderboard_oldest_task = _make_leaderboard("oldest_open_task_days", "Ancient Relic Keeper (Oldest Open Task)", "⏳", "days")
    leaderboard_fast_closer = _make_leaderboard("tasks_fast_closed", "Lightning Finisher (Tasks Closed <24h)", "⚡", "fast tasks")
    leaderboard_evidences = _make_leaderboard("task_evidences_count", "Traceability Champion (Evidences & Links)", "🧾", "evidences")
    leaderboard_syntax = _make_leaderboard("structured_syntax_completed", "Syntax Master ([Type_#] Standard)", "🏷️", "structured")
    leaderboard_night_owls = _make_leaderboard("night_activities", "Night Owls (9PM – 5AM)", "🦉", "night acts")
    leaderboard_early_birds = _make_leaderboard("early_bird_activities", "Early Birds (5AM – 9AM)", "🌅", "early acts")
    leaderboard_weekend_warriors = _make_leaderboard("weekend_activities", "The Week-enders (Sat/Sun)", "⚡", "wknd acts")
    leaderboard_daytime = _make_leaderboard("daytime_activities", "Daytime Champions (9AM – 6PM)", "☀️", "core acts")
    leaderboard_overall = _make_leaderboard("score", "Sprint MVP (Overall Hall of Fame)", "👑", "pts")

    # Team Overview Summary (calculated from active canonical members only)
    active_members = [m for m in member_list if not m.get("is_aliased")]
    aliased_members = [m for m in member_list if m.get("is_aliased")]

    team_total_prs_created = sum(m["prs_created"] for m in active_members)
    team_total_prs_closed = sum(m["prs_closed"] for m in active_members)
    team_total_commits = sum(m["commits_count"] for m in active_members)
    team_total_branches_started = sum(m["branches_started"] for m in active_members)
    team_total_branches_closed = sum(m["branches_closed"] for m in active_members)
    team_total_tasks_completed = sum(m["tasks_completed"] for m in active_members)
    team_total_bugs_resolved = sum(m["bugs_resolved"] for m in active_members)
    team_total_reviews = sum(m["prs_reviewed"] for m in active_members)
    team_total_approvals = sum(m["prs_approved"] for m in active_members)
    team_total_tags = sum(m["tags_pushed"] for m in active_members)
    team_total_builds = sum(m["builds_total"] for m in active_members)
    team_total_builds_succeeded = sum(m["builds_succeeded"] for m in active_members)
    team_total_builds_failed = sum(m["builds_failed"] for m in active_members)
    team_total_state_changes = sum(m["state_changes_count"] for m in active_members)
    team_total_pushbacks = sum(m["pushbacks_count"] for m in active_members)
    team_total_stale_tasks = sum(m["stale_tasks_count"] for m in active_members)
    team_total_fast_closed = sum(m["tasks_fast_closed"] for m in active_members)
    team_total_evidences = sum(m["task_evidences_count"] for m in active_members)
    team_oldest_task_days = max((m["oldest_open_task_days"] for m in active_members), default=0)
    team_build_success_rate = round((team_total_builds_succeeded / team_total_builds * 100.0), 1) if team_total_builds > 0 else 100.0
    active_contributors_count = sum(1 for m in active_members if m.get("has_activity") and m.get("score", 0) > 0)
    team_total_score_sum = sum(m["score"] for m in active_members if m.get("has_activity"))

    # Compute Team Time Analytics
    def _format_breakdown_label(commits, prs, tasks, builds):
        parts = []
        if commits > 0:
            parts.append(f"{commits} commit{'s' if commits > 1 else ''}")
        if prs > 0:
            parts.append(f"{prs} PR{'s' if prs > 1 else ''}")
        if tasks > 0:
            parts.append(f"{tasks} task{'s' if tasks > 1 else ''}")
        if builds > 0:
            parts.append(f"{builds} build{'s' if builds > 1 else ''}")
        return " • ".join(parts) if parts else "0 actions"

    team_tot_samples = team_time_agg["total_samples"]
    day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    day_shorts = ["M", "T", "W", "T", "F", "S", "S"]
    peak_h_team = max(range(24), key=lambda h: team_time_agg["hourly_distribution"][h]) if team_tot_samples > 0 else 14
    peak_d_idx = max(range(7), key=lambda d: team_time_agg["daily_distribution"][d]) if team_tot_samples > 0 else 2
    peak_d_team = day_names[peak_d_idx]

    hourly_details = []
    for h in range(24):
        tot = team_time_agg["hourly_distribution"][h]
        c = team_time_agg["hourly_commits"][h]
        p = team_time_agg["hourly_prs"][h]
        t = team_time_agg["hourly_tasks"][h]
        b = team_time_agg["hourly_builds"][h]
        hourly_details.append({
            "hour": h,
            "label": f"{h:02d}:00",
            "count": tot,
            "commits": c,
            "prs": p,
            "tasks": t,
            "builds": b,
            "breakdown": _format_breakdown_label(c, p, t, b)
        })

    daily_details = []
    for d in range(7):
        tot = team_time_agg["daily_distribution"][d]
        c = team_time_agg["daily_commits"][d]
        p = team_time_agg["daily_prs"][d]
        t = team_time_agg["daily_tasks"][d]
        b = team_time_agg["daily_builds"][d]
        daily_details.append({
            "day": day_names[d][:3],
            "full_day": day_names[d],
            "short": day_shorts[d],
            "count": tot,
            "commits": c,
            "prs": p,
            "tasks": t,
            "builds": b,
            "breakdown": _format_breakdown_label(c, p, t, b)
        })

    team_time_analytics = {
        "total_samples": team_tot_samples,
        "daytime_count": team_time_agg["daytime_count"],
        "daytime_pct": round((team_time_agg["daytime_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "daytime_breakdown": _format_breakdown_label(
            team_time_agg["daytime_breakdown"]["commits"],
            team_time_agg["daytime_breakdown"]["prs"],
            team_time_agg["daytime_breakdown"]["tasks"],
            team_time_agg["daytime_breakdown"]["builds"]
        ),
        "night_count": team_time_agg["night_count"],
        "night_pct": round((team_time_agg["night_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "night_breakdown": _format_breakdown_label(
            team_time_agg["night_breakdown"]["commits"],
            team_time_agg["night_breakdown"]["prs"],
            team_time_agg["night_breakdown"]["tasks"],
            team_time_agg["night_breakdown"]["builds"]
        ),
        "weekend_count": team_time_agg["weekend_count"],
        "weekend_pct": round((team_time_agg["weekend_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "weekend_breakdown": _format_breakdown_label(
            team_time_agg["weekend_breakdown"]["commits"],
            team_time_agg["weekend_breakdown"]["prs"],
            team_time_agg["weekend_breakdown"]["tasks"],
            team_time_agg["weekend_breakdown"]["builds"]
        ),
        "early_bird_count": team_time_agg["early_bird_count"],
        "early_bird_pct": round((team_time_agg["early_bird_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "early_bird_breakdown": _format_breakdown_label(
            team_time_agg["early_bird_breakdown"]["commits"],
            team_time_agg["early_bird_breakdown"]["prs"],
            team_time_agg["early_bird_breakdown"]["tasks"],
            team_time_agg["early_bird_breakdown"]["builds"]
        ),
        "evening_count": team_time_agg["evening_count"],
        "evening_pct": round((team_time_agg["evening_count"] / team_tot_samples * 100.0), 1) if team_tot_samples > 0 else 0.0,
        "friday_pm_count": team_time_agg["friday_pm_count"],
        "peak_hour": peak_h_team,
        "peak_hour_label": f"{peak_h_team:02d}:00",
        "peak_day": peak_d_team,
        "hourly_distribution": team_time_agg["hourly_distribution"],
        "hourly_details": hourly_details,
        "daily_distribution": daily_details,
    }

    # Dynamic Motivational Quotes / Pulse
    motivational_quotes = [
        "🔥 Incredible momentum! Every commit, merged PR, and green build drives the team forward.",
        "⚡ Velocity Surge: High code review participation and clean CI builds this cycle!",
        "🎯 Focus & Quality: Smashing bugs, delivering on commitments, and hitting milestones.",
        "🚀 High Performance: Smooth branch integration and automated builds keep us shipping fast.",
        "🛡️ Zero Regressions: Thorough peer reviews and solid test builds maintain top stability."
    ]
    pulse_index = (cur_week_num + len(member_list)) % len(motivational_quotes)
    motivational_pulse = motivational_quotes[pulse_index]

    # Clean member list for JSON serialization (remove internal helpers & sort activities)
    for m in member_list:
        m.pop("_pr_durations", None)
        m.pop("_task_durations", None)
        m.pop("_last_activity_dt", None)

        # Sort recent activities newest first and limit to 30 items
        if m.get("recent_activities"):
            m["recent_activities"] = sorted(m["recent_activities"], key=lambda a: a.get("timestamp", ""), reverse=True)[:30]
            if not m.get("last_activity"):
                m["last_activity"] = m["recent_activities"][0]
                m["last_active_date"] = m["last_activity"].get("timestamp", "")

        # Format recent highlights
        if m.get("is_aliased"):
            m["recent_achievements"] = [f"🔗 Linked to {m.get('aliased_to')}"]
            continue

        highlights = []
        if m["prs_closed"] > 0:
            highlights.append(f"Merged {m['prs_closed']} PR{'s' if m['prs_closed'] > 1 else ''}")
        if m["commits_count"] > 0:
            highlights.append(f"{m['commits_count']} commits")
        if m["branches_started"] > 0:
            highlights.append(f"{m['branches_started']} branch{'es' if m['branches_started'] > 1 else ''}")
        if m["tasks_completed"] > 0:
            highlights.append(f"Completed {m['tasks_completed']} item{'s' if m['tasks_completed'] > 1 else ''}")
        if m["tasks_cleaned"] > 0:
            highlights.append(f"Groomed {m['tasks_cleaned']} states 🧹")
        if m["pushbacks_count"] > 0:
            highlights.append(f"Pushed back {m['pushbacks_count']} items 🛡️")
        if m["tasks_fast_closed"] > 0:
            highlights.append(f"{m['tasks_fast_closed']} fast closes (<24h) ⚡")
        if m["structured_syntax_completed"] > 0:
            highlights.append(f"{m['structured_syntax_completed']} syntax standard items 🏷️")
        if m["task_evidences_count"] >= 3:
            highlights.append(f"{m['task_evidences_count']} evidences linked 🧾")
        if m["oldest_open_task_days"] >= 60:
            highlights.append(f"Open item {m['oldest_open_task_days']}d old ⏳")
        if m["bugs_resolved"] > 0:
            highlights.append(f"Fixed {m['bugs_resolved']} bug{'s' if m['bugs_resolved'] > 1 else ''}")
        if m["builds_succeeded"] > 0:
            highlights.append(f"{m['builds_succeeded']} green builds")
        if m["tags_pushed"] > 0:
            highlights.append(f"{m['tags_pushed']} tags")
        if m["prs_reviewed"] > 0:
            highlights.append(f"Reviewed {m['prs_reviewed']} PR{'s' if m['prs_reviewed'] > 1 else ''}")
        if m["stale_tasks_count"] > 0:
            highlights.append(f"⚠️ {m['stale_tasks_count']} stale items")
        if m["night_activities"] >= 3:
            highlights.append(f"🦉 Night Owl ({m['night_activities']} late acts)")
        if m["weekend_activities"] >= 2:
            highlights.append(f"⚡ Weekend Warrior ({m['weekend_activities']} wknd acts)")
        if m["current_streak_weeks"] >= 2:
            highlights.append(f"🔥 {m['current_streak_weeks']}-week streak")
        m["recent_achievements"] = highlights

    # Top 3 Podium and overall rankings (active canonical members only)
    sorted_active = sorted(
        active_members,
        key=lambda x: (
            1 if (x.get("has_activity") and x.get("score", 0) > 0) else 0,
            x.get("score", 0),
            x.get("commits_count", 0) + x.get("prs_closed", 0) + x.get("tasks_completed", 0)
        ),
        reverse=True
    )

    rank = 1
    for m in sorted_active:
        if m.get("has_activity") and m.get("score", 0) > 0:
            m["rank"] = rank
            rank += 1
        else:
            m["rank"] = None

    for m in aliased_members:
        m["rank"] = None
        m["score"] = 0
        m["has_activity"] = False

    podium = []
    active_scorers = [m for m in sorted_active if m.get("has_activity") and m.get("score", 0) > 0]
    if len(active_scorers) >= 1:
        podium.append({"rank": 1, "medal": "🥇", "title": "1st Place", "member": active_scorers[0]})
    if len(active_scorers) >= 2:
        podium.append({"rank": 2, "medal": "🥈", "title": "2nd Place", "member": active_scorers[1]})
    if len(active_scorers) >= 3:
        podium.append({"rank": 3, "medal": "🥉", "title": "3rd Place", "member": active_scorers[2]})

    sorted_all = sorted_active + sorted(aliased_members, key=lambda x: x["name"].lower())


    return {
        "timeframe": timeframe,
        "custom_sprint": custom_sprint,
        "target_sprint": target_sprint,
        "range_label": range_label,
        "start_date": filter_start_str,
        "end_date": filter_end_str,
        "motivational_pulse": motivational_pulse,
        "team_summary": {
            "prs_created": team_total_prs_created,
            "prs_closed": team_total_prs_closed,
            "commits_count": team_total_commits,
            "branches_started": team_total_branches_started,
            "branches_closed": team_total_branches_closed,
            "tasks_completed": team_total_tasks_completed,
            "bugs_resolved": team_total_bugs_resolved,
            "prs_reviewed": team_total_reviews,
            "prs_approved": team_total_approvals,
            "reviews_completed": team_total_reviews,
            "approvals_completed": team_total_approvals,
            "tags_pushed": team_total_tags,
            "builds_total": team_total_builds,
            "builds_succeeded": team_total_builds_succeeded,
            "builds_failed": team_total_builds_failed,
            "build_success_rate": team_build_success_rate,
            "total_state_changes": team_total_state_changes,
            "total_pushbacks": team_total_pushbacks,
            "total_stale_tasks": team_total_stale_tasks,
            "tasks_fast_closed": team_total_fast_closed,
            "task_evidences_count": team_total_evidences,
            "structured_syntax_completed": sum(m["structured_syntax_completed"] for m in member_list),
            "oldest_open_task_days": team_oldest_task_days,
            "active_contributors": active_contributors_count,
            "total_points": team_total_score_sum,
            "time_analytics": team_time_analytics,
            "cleaner_leader": leaderboard_cleaners.get("leader"),
            "decliner_leader": leaderboard_decliners.get("leader"),
            "fast_closer_leader": leaderboard_fast_closer.get("leader"),
            "oldest_task_leader": leaderboard_oldest_task.get("leader"),
            "evidences_leader": leaderboard_evidences.get("leader"),
            "syntax_leader": leaderboard_syntax.get("leader"),
        },
        "stale_radar": sorted(stale_radar, key=lambda x: x["days_idle"], reverse=True)[:25],
        "podium": podium,
        "members": sorted_active,
        "all_user_profiles": sorted_all,
        "leaderboards": {
            "overall": leaderboard_overall,
            "syntax_master": leaderboard_syntax,
            "cleaners": leaderboard_cleaners,
            "decliners": leaderboard_decliners,
            "fast_closer": leaderboard_fast_closer,
            "oldest_task": leaderboard_oldest_task,
            "evidences": leaderboard_evidences,
            "state_movers": leaderboard_state_movers,
            "prs_closed": leaderboard_prs_closed,
            "prs_created": leaderboard_prs_created,
            "commits": leaderboard_commits,
            "branches_started": leaderboard_branches_started,
            "branches_closed": leaderboard_branches_closed,
            "tasks_completed": leaderboard_tasks_completed,
            "bugs_resolved": leaderboard_bugs_resolved,
            "prs_reviewed": leaderboard_prs_reviewed,
            "prs_approved": leaderboard_prs_approved,
            "tags": leaderboard_tags,
            "builds": leaderboard_builds,
            "streaks": leaderboard_streaks,
            "night_owls": leaderboard_night_owls,
            "early_birds": leaderboard_early_birds,
            "weekend_warriors": leaderboard_weekend_warriors,
            "daytime": leaderboard_daytime,
        },
        "all_badges": list(BADGE_DEFINITIONS.values()),
        "score_config": active_score_config,
        "score_presets": SCORE_PRESETS,
        "system_users": system_users_list,
        "system_users_count": len([u for u in system_users_list if not u.get("is_builtin", False)]),
    }


def generate_motivation_markdown_summary(data):
    """
    Generates a stylish markdown summary of the team achievements for Slack/Teams sprint retro sharing.
    """
    if not data:
        return "No motivational data available."

    ts = data.get("team_summary", {})
    ta = ts.get("time_analytics", {})
    rl = data.get("range_label", "Sprint Period")
    pulse = data.get("motivational_pulse", "")
    podium = data.get("podium", [])
    members = data.get("members", [])

    lines = [
        f"# 🏆 Team Sprint Motivation & Hall of Fame",
        f"**Period:** {rl}",
        f"",
        f"> {pulse}",
        f"",
        f"## 📊 Team Sprint Pulse",
        f"- **🔀 Pull Requests Started / Merged:** {ts.get('prs_created', 0)} / {ts.get('prs_closed', 0)}",
        f"- **💻 Code Commits:** {ts.get('commits_count', 0)}",
        f"- **🌳 Feature Branches (Started / Merged):** {ts.get('branches_started', 0)} / {ts.get('branches_closed', 0)}",
        f"- **🏷️ Release Tags:** {ts.get('tags_pushed', 0)}",
        f"- **🏗️ CI Pipeline Builds:** {ts.get('builds_total', 0)} ({ts.get('builds_succeeded', 0)} succeeded, {ts.get('builds_failed', 0)} failed • **{ts.get('build_success_rate', 100.0)}% success**)",
        f"- **🔨 Work Items Completed:** {ts.get('tasks_completed', 0)} ({ts.get('bugs_resolved', 0)} bugs fixed)",
        f"- **🔍 Peer Code Reviews:** {ts.get('reviews_completed', 0)}",
        f"- **⏰ Work Rhythm:** {ta.get('daytime_pct', 0)}% Daytime (9-18h) • {ta.get('night_pct', 0)}% Night Owl (21-5h) • {ta.get('weekend_pct', 0)}% Weekend",
        f"- **👥 Active Contributors:** {ts.get('active_contributors', 0)}",
        f"",
    ]

    if podium:
        lines.append("## 🥇 Sprint Podium")
        for p in podium:
            m = p["member"]
            med = p["medal"]
            lines.append(f"- **{med} {p['title']}:** {m['name']} ({m.get('time_stats', {}).get('persona', '')}) — **{m['score']} pts** ({', '.join(m.get('recent_achievements', []))})")
        lines.append("")

    lines.append("## 🌟 Leaderboard & Badges")
    lines.append("| Rank | Contributor | Score | Commits | Branches (S/C) | PRs (M/C) | Tasks | Bugs | Builds (✓/✗) | Rhythm | Streak | Badges |")
    lines.append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |")

    for i, m in enumerate(members[:15], start=1):
        badge_icons = "".join(b.get("icon", "") for b in m.get("badges", []))
        streak_str = f"🔥 {m['current_streak_weeks']}w" if m['current_streak_weeks'] > 0 else "-"
        build_str = f"{m.get('builds_succeeded', 0)}/{m.get('builds_failed', 0)}" if m.get('builds_total', 0) > 0 else "—"
        br_str = f"{m.get('branches_started', 0)}/{m.get('branches_closed', 0)}"
        persona = m.get("time_stats", {}).get("persona", "☀️")
        lines.append(
            f"| #{i} | **{m['name']}** | **{m['score']}** | {m.get('commits_count', 0)} | {br_str} | {m['prs_closed']}/{m['prs_created']} | {m['tasks_completed']} | {m['bugs_resolved']} | {build_str} | {persona} | {streak_str} | {badge_icons} |"
        )

    lines.append("")
    lines.append("---")
    lines.append("*Generated by DevOps Manager Motivation & Sprint Gamification Engine*")

    return "\n".join(lines)
