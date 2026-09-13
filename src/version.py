# -*- coding: UTF-8 -*-
"""
Application version discovery module.
Dynamically reads Git tag and describe metadata at runtime and build time.
"""
import os
import re
import subprocess
import sys


def _get_repo_root():
    current_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.dirname(current_dir), # repository root if __file__ is in src/
        current_dir,
    ]
    for c in candidates:
        if os.path.exists(os.path.join(c, ".git")):
            return c
    return None


def _get_git_describe(repo_dir=None):
    """Executes git describe to obtain tag, distance, commit hash, and dirty status."""
    if not repo_dir:
        repo_dir = _get_repo_root()
    if not repo_dir or not os.path.exists(os.path.join(repo_dir, ".git")):
        return None

    try:
        cmd = ["git", "describe", "--tags", "--always", "--long", "--dirty"]
        out = subprocess.check_output(cmd, cwd=repo_dir, stderr=subprocess.DEVNULL, timeout=5)
        text = out.decode("utf-8", errors="ignore").strip()
        if text:
            return text
    except Exception:
        pass
    return None


def get_version_info():
    """
    Returns a comprehensive dictionary of version information.
    {
        "tag": "v0.01.2637",
        "distance": 0,
        "commit_hash": "b95f88e",
        "is_dirty": False,
        "is_exact_tag": True,
        "raw_describe": "v0.01.2637-0-gb95f88e",
        "display_version": "v0.01.2637",
        "status_label": "Official Release Tag",
        "pep440_version": "0.1.2637",
        "source": "git" | "scm_cache" | "package_metadata" | "fallback"
    }
    """
    describe_str = _get_git_describe()
    source = "git" if describe_str else None

    # Fallback to _version_scm.py or installed metadata if not in a git repo
    if not describe_str:
        try:
            from _version_scm import version as scm_ver, version_tuple
            source = "scm_cache"
            # Attempt to parse scm version
            return _format_from_pep440(scm_ver, source="scm_cache")
        except Exception:
            pass

        try:
            import importlib.metadata
            pkg_ver = importlib.metadata.version("azure-tagday-ui")
            source = "package_metadata"
            return _format_from_pep440(pkg_ver, source="package_metadata")
        except Exception:
            pass

        # Default fallback
        describe_str = "v0.01.2637-0-gb95f88e"
        source = "fallback"

    # Parse git describe: <tag>-<distance>-g<hash>[-dirty]
    pattern = r"^(?P<tag>.+)-(?P<distance>\d+)-g(?P<hash>[0-9a-fA-F]+)(?P<dirty>-dirty)?$"
    m = re.match(pattern, describe_str)

    if m:
        tag = m.group("tag")
        distance = int(m.group("distance"))
        commit_hash = m.group("hash")
        is_dirty = bool(m.group("dirty"))
        is_exact_tag = (distance == 0) and (not is_dirty)

        # Normalize tag to SemVer for PEP 440
        clean_tag_num = tag.lstrip("vV")
        # Ensure standard x.y.z or numbers
        parts = clean_tag_num.split(".")
        try:
            norm_parts = [str(int(p)) for p in parts]
            base_pep440 = ".".join(norm_parts)
        except ValueError:
            base_pep440 = clean_tag_num

        if is_exact_tag:
            pep440_version = base_pep440
            display_version = tag
            status_label = "Official Release Tag"
        elif distance > 0 and not is_dirty:
            pep440_version = f"{base_pep440}.post{distance}+{commit_hash}"
            display_version = f"{tag}+{distance} ({commit_hash})"
            status_label = f"+{distance} commits since {tag}"
        elif distance > 0 and is_dirty:
            pep440_version = f"{base_pep440}.post{distance}+{commit_hash}.dirty"
            display_version = f"{tag}+{distance} ({commit_hash}, modified)"
            status_label = f"+{distance} commits since {tag} (modified)"
        else: # distance == 0 but is_dirty
            pep440_version = f"{base_pep440}+dirty"
            display_version = f"{tag} ({commit_hash}, modified)"
            status_label = f"{tag} (modified working tree)"

        return {
            "tag": tag,
            "distance": distance,
            "commit_hash": commit_hash,
            "is_dirty": is_dirty,
            "is_exact_tag": is_exact_tag,
            "raw_describe": describe_str,
            "display_version": display_version,
            "status_label": status_label,
            "pep440_version": pep440_version,
            "source": source,
        }

    # Fallback for plain commit hash without tags
    is_dirty = "-dirty" in describe_str
    clean_hash = describe_str.replace("-dirty", "").lstrip("g")
    return {
        "tag": "v0.01.0",
        "distance": 0,
        "commit_hash": clean_hash,
        "is_dirty": is_dirty,
        "is_exact_tag": False,
        "raw_describe": describe_str,
        "display_version": f"dev ({clean_hash}{', modified' if is_dirty else ''})",
        "status_label": "Untagged Development Build",
        "pep440_version": f"0.1.0+g{clean_hash}{'.dirty' if is_dirty else ''}",
        "source": source,
    }


def _format_from_pep440(version_str, source="package_metadata"):
    v_str = str(version_str).strip()
    is_dirty = "dirty" in v_str.lower()
    is_exact = not is_dirty and ".post" not in v_str and ".dev" not in v_str and "+" not in v_str
    tag = f"v{v_str.split('+')[0].split('.post')[0]}"
    return {
        "tag": tag,
        "distance": 0 if is_exact else 1,
        "commit_hash": "",
        "is_dirty": is_dirty,
        "is_exact_tag": is_exact,
        "raw_describe": v_str,
        "display_version": tag if is_exact else f"{tag} ({v_str})",
        "status_label": "Installed Package" if is_exact else "Development Package",
        "pep440_version": v_str,
        "source": source,
    }


_info = get_version_info()
__version__ = _info["pep440_version"]
__display_version__ = _info["display_version"]
