# -*- coding: UTF-8 -*-
"""
Unit and integration tests for Milestone 1 (Submodule URL Auditor & Relative-Path Converter)
and Milestone 2 / Path 1 (LocalBackupManager with worktree, mirror, and both modes).
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import MagicMock

# Ensure src is on sys.path
src_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if src_dir not in sys.path:
    sys.path.insert(0, src_dir)

from azure.azure_db import AzureDevOpsCache
from azure.azure_info_handler import AzureInfoHandler
from azure.migration_service import (
    CLASSIFICATION_ABSOLUTE_CROSS_PROJECT,
    CLASSIFICATION_ABSOLUTE_SAME_PROJECT,
    CLASSIFICATION_EXTERNAL_OR_MISSING,
    CLASSIFICATION_RELATIVE_OK,
    ForgejoClient,
    ForgejoStandbySyncManager,
    LocalBackupManager,
    SubmoduleAuditor,
    build_git_auth_args,
    classify_submodule_url,
    parse_gitmodules_content,
    rewrite_gitmodules_to_relative,
    sort_repos_topologically,
)


class TestMilestone1SubmoduleAuditor(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.tmp_dir.name, "test_migration.db")
        self.cache_db = AzureDevOpsCache(self.db_path)
        self.known_repos = ["CoreEngine", "CommonLib", "UiWidgets", "DriversPkg"]

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_parse_gitmodules_content(self):
        content = """# Project submodules
[submodule "libs/common"]
\tpath = libs/common
\turl = ../CommonLib
\tbranch = dev

[submodule "drivers"]
    path = src/drivers
    url = http://tfs.local:8080/tfs/DefaultCollection/MyProj/_git/DriversPkg
"""
        parsed = parse_gitmodules_content(content)
        self.assertEqual(len(parsed), 2)
        self.assertEqual(parsed[0]["name"], "libs/common")
        self.assertEqual(parsed[0]["path"], "libs/common")
        self.assertEqual(parsed[0]["url"], "../CommonLib")
        self.assertEqual(parsed[0]["branch"], "dev")
        self.assertEqual(parsed[1]["name"], "drivers")
        self.assertEqual(parsed[1]["path"], "src/drivers")
        self.assertEqual(
            parsed[1]["url"],
            "http://tfs.local:8080/tfs/DefaultCollection/MyProj/_git/DriversPkg",
        )

    def test_classify_submodule_urls_all_categories(self):
        # 1. Clean relative URL pointing to an existing repo
        r1 = classify_submodule_url(
            "../CommonLib",
            parent_repo_name="CoreEngine",
            project_id="MyProj",
            known_repo_names=self.known_repos,
        )
        self.assertEqual(r1["classification"], CLASSIFICATION_RELATIVE_OK)
        self.assertTrue(r1["target_repo_exists"])
        self.assertEqual(r1["proposed_relative_url"], "../CommonLib")

        # 2. Clean relative URL with .git suffix
        r2 = classify_submodule_url(
            "../UiWidgets.git",
            parent_repo_name="CoreEngine",
            project_id="MyProj",
            known_repo_names=self.known_repos,
        )
        self.assertEqual(r2["classification"], CLASSIFICATION_RELATIVE_OK)
        self.assertTrue(r2["target_repo_exists"])

        # 3. Hardcoded HTTP TFS URL in the same project
        r3 = classify_submodule_url(
            "http://tfs.local:8080/tfs/DefaultCollection/MyProj/_git/CommonLib",
            parent_repo_name="CoreEngine",
            project_id="MyProj",
            known_repo_names=self.known_repos,
        )
        self.assertEqual(r3["classification"], CLASSIFICATION_ABSOLUTE_SAME_PROJECT)
        self.assertEqual(r3["proposed_relative_url"], "../CommonLib")
        self.assertTrue(r3["target_repo_exists"])

        # 4. Hardcoded SSH TFS URL in the same project (case-insensitive repo match)
        r4 = classify_submodule_url(
            "ssh://tfs.local:22/tfs/DefaultCollection/MyProj/_ssh/commonlib.git",
            parent_repo_name="CoreEngine",
            project_id="MyProj",
            known_repo_names=self.known_repos,
        )
        self.assertEqual(r4["classification"], CLASSIFICATION_ABSOLUTE_SAME_PROJECT)
        self.assertEqual(r4["proposed_relative_url"], "../CommonLib")
        self.assertTrue(r4["target_repo_exists"])

        # 5. Cross-project TFS URL
        r5 = classify_submodule_url(
            "http://tfs.local:8080/tfs/DefaultCollection/OtherTeamProj/_git/SharedHal",
            parent_repo_name="CoreEngine",
            project_id="MyProj",
            known_repo_names=self.known_repos,
        )
        self.assertEqual(r5["classification"], CLASSIFICATION_ABSOLUTE_CROSS_PROJECT)
        self.assertEqual(r5["proposed_relative_url"], "../SharedHal")
        self.assertEqual(r5["target_project"], "OtherTeamProj")

        # 6. External GitHub URL -> EXTERNAL_OR_MISSING (not rewritten)
        r6 = classify_submodule_url(
            "https://github.com/fmtlib/fmt.git",
            parent_repo_name="CoreEngine",
            project_id="MyProj",
            known_repo_names=self.known_repos,
        )
        self.assertEqual(r6["classification"], CLASSIFICATION_EXTERNAL_OR_MISSING)
        self.assertFalse(r6["target_repo_exists"])

        # 7. Relative URL to a deleted/missing repo -> EXTERNAL_OR_MISSING
        r7 = classify_submodule_url(
            "../DeletedLegacyRepo",
            parent_repo_name="CoreEngine",
            project_id="MyProj",
            known_repo_names=self.known_repos,
        )
        self.assertEqual(r7["classification"], CLASSIFICATION_EXTERNAL_OR_MISSING)
        self.assertFalse(r7["target_repo_exists"])

    def test_rewrite_gitmodules_to_relative_preserves_formatting_and_generates_diff(self):
        original = (
            '# Header comment\n'
            '[submodule "libs/common"]\n'
            '\tpath = libs/common\n'
            '\turl = ../CommonLib\n'
            '[submodule "src/drivers"]\n'
            '\tpath = src/drivers\n'
            '\turl = http://tfs.local:8080/tfs/DefaultCollection/MyProj/_git/DriversPkg\n'
            '\tbranch = dev\n'
            '[submodule "thirdparty/fmt"]\n'
            '\tpath = thirdparty/fmt\n'
            '\turl = https://github.com/fmtlib/fmt.git\n'
        )
        new_content, changes, diff_text = rewrite_gitmodules_to_relative(
            original,
            parent_repo_name="CoreEngine",
            project_id="MyProj",
            known_repo_names=self.known_repos,
        )
        self.assertEqual(len(changes), 1)
        self.assertEqual(changes[0]["submodule_path"], "src/drivers")
        self.assertEqual(
            changes[0]["old_url"],
            "http://tfs.local:8080/tfs/DefaultCollection/MyProj/_git/DriversPkg",
        )
        self.assertEqual(changes[0]["new_url"], "../DriversPkg")
        self.assertIn("\turl = ../DriversPkg\n", new_content)
        self.assertIn("\turl = ../CommonLib\n", new_content)
        self.assertIn("\turl = https://github.com/fmtlib/fmt.git\n", new_content)
        self.assertIn("-	url = http://tfs.local:8080/tfs/DefaultCollection/MyProj/_git/DriversPkg", diff_text)
        self.assertIn("+	url = ../DriversPkg", diff_text)

    def test_auditor_and_interactive_tfs_conversion(self):
        handler = AzureInfoHandler("http://tfs.local:8080/tfs/DefaultCollection", "dummy_pat")
        repos = [
            {"id": "id-core", "name": "CoreEngine", "defaultBranch": "refs/heads/dev", "isDisabled": False},
            {"id": "id-common", "name": "CommonLib", "defaultBranch": "refs/heads/dev", "isDisabled": False},
            {"id": "id-ui", "name": "UiWidgets", "defaultBranch": "refs/heads/dev", "isDisabled": False},
        ]
        handler.get_repositories = MagicMock(return_value=repos)

        gitmodules_by_repo = {
            "id-core": (
                '[submodule "libs/common"]\n'
                '\tpath = libs/common\n'
                '\turl = http://tfs.local:8080/tfs/DefaultCollection/MyProj/_git/CommonLib\n'
                '[submodule "libs/ui"]\n'
                '\tpath = libs/ui\n'
                '\turl = ../UiWidgets\n'
            ),
            "id-ui": (
                '[submodule "libs/common"]\n'
                '\tpath = libs/common\n'
                '\turl = http://tfs.local:8080/tfs/DefaultCollection/MyProj/_git/CommonLib\n'
            ),
        }

        def fake_get_items(proj, repo_id, path, params=None, raw_text=False):
            if path == ".gitmodules" and repo_id in gitmodules_by_repo:
                return gitmodules_by_repo[repo_id]
            return ""

        handler.get_repository_items = MagicMock(side_effect=fake_get_items)
        handler.push_file_update = MagicMock(return_value={"pushId": 777})

        auditor = SubmoduleAuditor(info_handler=handler, project_id="MyProj", cache_db=self.cache_db)
        report = auditor.audit_project_submodules()

        self.assertEqual(report["total_repos_scanned"], 3)
        self.assertEqual(report["repos_with_submodules"], 2)
        self.assertEqual(report["repos_needing_conversion"], 2)
        self.assertEqual(report["total_submodules"], 3)
        self.assertEqual(report["relative_ok_count"], 1)
        self.assertEqual(report["needs_conversion_count"], 2)

        # Verify SQLite submodule_audit persistence
        cached_audit = self.cache_db.get_submodule_audit()
        self.assertEqual(len(cached_audit), 3)

        # Simulate interactive user prompt: accept CoreEngine, decline UiWidgets
        prompted_repos = []
        def user_prompt(repo_name, diff_text, changes):
            prompted_repos.append(repo_name)
            return repo_name == "CoreEngine"

        conv_res = auditor.convert_submodules_to_relative_in_tfs(
            audit_report=report,
            prompt_callback=user_prompt,
        )
        self.assertEqual(prompted_repos, ["CoreEngine", "UiWidgets"])
        self.assertEqual(conv_res["updated_repos"], ["CoreEngine"])
        self.assertEqual(conv_res["skipped_repos"], ["UiWidgets"])
        self.assertEqual(len(conv_res["failed_repos"]), 0)
        handler.push_file_update.assert_called_once()

        # Verify CoreEngine audit entries in DB are now updated to RELATIVE_OK
        core_audit = self.cache_db.get_submodule_audit("id-core")
        self.assertTrue(all(a["classification"] == CLASSIFICATION_RELATIVE_OK for a in core_audit))


class TestPath1LocalBackupManager(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.remotes_dir = os.path.join(self.tmp_dir.name, "remote_tfs_git")
        self.backup_dir = os.path.join(self.tmp_dir.name, "local_backup")
        self.db_path = os.path.join(self.tmp_dir.name, "tfs_cache_TestProj.db")
        self.cache_db = AzureDevOpsCache(self.db_path)
        os.makedirs(self.remotes_dir, exist_ok=True)

        # Create two real bare/source Git repositories:
        # 1. CommonLib (leaf repository)
        # 2. MainApp (parent repository that includes CommonLib as a relative submodule ../CommonLib)
        self.common_remote = os.path.join(self.remotes_dir, "CommonLib")
        self.app_remote = os.path.join(self.remotes_dir, "MainApp")
        self._init_source_repos()

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _run_git(self, args, cwd):
        env = os.environ.copy()
        env["GIT_AUTHOR_NAME"] = "Test User"
        env["GIT_AUTHOR_EMAIL"] = "test@example.com"
        env["GIT_COMMITTER_NAME"] = "Test User"
        env["GIT_COMMITTER_EMAIL"] = "test@example.com"
        res = subprocess.run(
            ["git", "-c", "protocol.file.allow=always"] + args,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        return res.stdout.strip()

    def _init_source_repos(self):
        # 1. Create CommonLib
        os.makedirs(self.common_remote, exist_ok=True)
        self._run_git(["init", "-b", "dev"], self.common_remote)
        with open(os.path.join(self.common_remote, "common.h"), "w", encoding="utf-8") as f:
            f.write("#pragma once\nint common_version = 1;\n")
        self._run_git(["add", "common.h"], self.common_remote)
        self._run_git(["commit", "-m", "Initial CommonLib commit"], self.common_remote)
        self._run_git(["tag", "v01.00.2601"], self.common_remote)

        # 2. Create MainApp with relative submodule ../CommonLib at libs/common
        os.makedirs(self.app_remote, exist_ok=True)
        self._run_git(["init", "-b", "dev"], self.app_remote)
        with open(os.path.join(self.app_remote, "main.cpp"), "w", encoding="utf-8") as f:
            f.write('#include "libs/common/common.h"\nint main() { return 0; }\n')
        self._run_git(["add", "main.cpp"], self.app_remote)
        self._run_git([" submodule", "add", "../CommonLib", "libs/common"], self.app_remote) if False else None
        # Add submodule cleanly with relative URL ../CommonLib
        self._run_git(["submodule", "add", self.common_remote, "libs/common"], self.app_remote)
        # Rewrite .gitmodules in MainApp to use portable relative URL ../CommonLib
        gitmodules_path = os.path.join(self.app_remote, ".gitmodules")
        with open(gitmodules_path, "r", encoding="utf-8") as f:
            gm = f.read()
        gm_rel = gm.replace(self.common_remote, "../CommonLib")
        with open(gitmodules_path, "w", encoding="utf-8") as f:
            f.write(gm_rel)
        self._run_git(["add", ".gitmodules"], self.app_remote)
        self._run_git(["commit", "-m", "Initial MainApp with CommonLib submodule"], self.app_remote)

    def test_topological_repo_sorting(self):
        repos = [
            {"id": "r-app", "name": "MainApp"},
            {"id": "r-common", "name": "CommonLib"},
        ]
        sub_map = {"MainApp": ["CommonLib"]}
        ordered = sort_repos_topologically(repos, submodule_map=sub_map)
        self.assertEqual([r["name"] for r in ordered], ["CommonLib", "MainApp"])

    def test_build_git_auth_args_never_exposes_plaintext_pat_in_url(self):
        args = build_git_auth_args(
            pat="my_secret_pat_123",
            tfs_project_git_base="http://tfs:8080/tfs/DefaultCollection/Proj/_git",
            local_override_base="/tmp/mirrors",
        )
        joined = " ".join(args)
        self.assertNotIn("my_secret_pat_123", joined)
        self.assertIn("http.extraHeader=Authorization: Basic ", joined)
        self.assertIn("http.sslVerify=false", joined)
        self.assertIn("url./tmp/mirrors/.insteadOf=http://tfs:8080/tfs/DefaultCollection/Proj/_git/", joined)

    def test_backup_mode_toggle_mirror_worktree_and_both_with_incremental_standby(self):
        # Intentionally list MainApp BEFORE CommonLib to verify topological ordering
        repos = [
            {"id": "r-app", "name": "MainApp", "remoteUrl": self.app_remote, "last_push_id": 10},
            {"id": "r-common", "name": "CommonLib", "remoteUrl": self.common_remote, "last_push_id": 5},
        ]
        sub_map = {"MainApp": ["CommonLib"]}

        # 1. Run with mode="both"
        mgr = LocalBackupManager(
            target_dir=self.backup_dir,
            mode="both",
            project_id="TestProj",
            pat="test_pat_token",
            cache_db=self.cache_db,
        )
        manifest = mgr.backup_all_repositories(repos=repos, submodule_map=sub_map)

        self.assertEqual(manifest["total_repositories"], 2)
        self.assertEqual(manifest["ok_count"], 2)
        self.assertEqual(manifest["failed_count"], 0)
        self.assertTrue(os.path.isfile(mgr.manifest_path))
        self.assertTrue(os.path.isfile(manifest["sqlite_snapshot_path"]))

        # Verify topological execution order: CommonLib first, then MainApp
        self.assertEqual([r["repo_name"] for r in manifest["repositories"]], ["CommonLib", "MainApp"])

        # Verify both bare mirrors and recursive worktrees exist
        self.assertTrue(os.path.isfile(os.path.join(mgr.mirrors_dir, "CommonLib.git", "HEAD")))
        self.assertTrue(os.path.isfile(os.path.join(mgr.mirrors_dir, "MainApp.git", "HEAD")))
        self.assertTrue(os.path.isfile(os.path.join(mgr.worktrees_dir, "MainApp", "main.cpp")))
        # Verify recursive submodule was checked out inside MainApp/libs/common/common.h!
        sub_header = os.path.join(mgr.worktrees_dir, "MainApp", "libs/common", "common.h")
        self.assertTrue(os.path.isfile(sub_header))

        # Verify PAT was NOT written into .git/config
        with open(os.path.join(mgr.worktrees_dir, "MainApp", ".git", "config"), "r", encoding="utf-8") as f:
            git_cfg = f.read()
        self.assertNotIn("test_pat_token", git_cfg)

        # 2. Re-run standby backup with unchanged push_id -> should SKIP as up-to-date
        manifest2 = mgr.backup_all_repositories(repos=repos, submodule_map=sub_map, force=False)
        self.assertEqual(manifest2["skipped_up_to_date_count"], 2)

        # 3. Simulate a new commit in CommonLib & push_id increment -> incremental UPDATE
        with open(os.path.join(self.common_remote, "common.h"), "w", encoding="utf-8") as f:
            f.write("#pragma once\nint common_version = 2;\n")
        self._run_git(["add", "common.h"], self.common_remote)
        new_sha = self._run_git(["commit", "-m", "Bump common_version to 2"], self.common_remote)
        new_head = self._run_git(["rev-parse", "HEAD"], self.common_remote)

        repos[1]["last_push_id"] = 6  # CommonLib push ID advanced from 5 -> 6
        manifest3 = mgr.backup_all_repositories(repos=repos, submodule_map=sub_map, force=False)
        self.assertEqual(manifest3["skipped_up_to_date_count"], 1)  # MainApp skipped, CommonLib updated
        common_res = next(r for r in manifest3["repositories"] if r["repo_name"] == "CommonLib")
        self.assertEqual(common_res["action"], "UPDATED")
        self.assertEqual(common_res["head_commit"], new_head)

    def test_backup_mode_toggle_individual_mirror_and_worktree_modes(self):
        repos = [
            {"id": "r-app", "name": "MainApp", "remoteUrl": self.app_remote, "last_push_id": 10},
            {"id": "r-common", "name": "CommonLib", "remoteUrl": self.common_remote, "last_push_id": 5},
        ]
        sub_map = {"MainApp": ["CommonLib"]}

        # Mode = "mirror" only
        mirror_only_dir = os.path.join(self.tmp_dir.name, "backup_mirror_only")
        mgr_mirror = LocalBackupManager(
            target_dir=mirror_only_dir,
            mode="mirror",
            project_id="TestProj",
            cache_db=self.cache_db,
        )
        m_mirror = mgr_mirror.backup_all_repositories(repos=repos, submodule_map=sub_map, force=True)
        self.assertEqual(m_mirror["ok_count"], 2)
        self.assertTrue(os.path.isdir(mgr_mirror.mirrors_dir))
        self.assertFalse(os.path.exists(mgr_mirror.worktrees_dir))

        # Mode = "worktree" only
        wt_only_dir = os.path.join(self.tmp_dir.name, "backup_wt_only")
        mgr_wt = LocalBackupManager(
            target_dir=wt_only_dir,
            mode="worktree",
            project_id="TestProj",
            cache_db=self.cache_db,
        )
        m_wt = mgr_wt.backup_all_repositories(repos=repos, submodule_map=sub_map, force=True)
        self.assertEqual(m_wt["ok_count"], 2)
        self.assertTrue(os.path.isdir(mgr_wt.worktrees_dir))
        self.assertFalse(os.path.exists(mgr_wt.mirrors_dir))
        self.assertTrue(os.path.isfile(os.path.join(mgr_wt.worktrees_dir, "MainApp", "libs/common", "common.h")))


class TestPath2ForgejoStandbySync(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.remotes_dir = os.path.join(self.tmp_dir.name, "remote_tfs_git")
        self.backup_dir = os.path.join(self.tmp_dir.name, "local_backup")
        self.forgejo_git_dir = os.path.join(self.tmp_dir.name, "forgejo_server_repos")
        self.db_path = os.path.join(self.tmp_dir.name, "tfs_cache_ForgejoProj.db")
        self.cache_db = AzureDevOpsCache(self.db_path)
        os.makedirs(self.remotes_dir, exist_ok=True)
        os.makedirs(self.forgejo_git_dir, exist_ok=True)

        self.common_remote = os.path.join(self.remotes_dir, "CommonLib")
        self.app_remote = os.path.join(self.remotes_dir, "MainApp")
        self._init_source_repos()

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _run_git(self, args, cwd):
        env = os.environ.copy()
        env["GIT_AUTHOR_NAME"] = "Test User"
        env["GIT_AUTHOR_EMAIL"] = "test@example.com"
        env["GIT_COMMITTER_NAME"] = "Test User"
        env["GIT_COMMITTER_EMAIL"] = "test@example.com"
        res = subprocess.run(
            ["git", "-c", "protocol.file.allow=always"] + args,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        return res.stdout.strip()

    def _init_source_repos(self):
        os.makedirs(self.common_remote, exist_ok=True)
        self._run_git(["init", "-b", "dev"], self.common_remote)
        with open(os.path.join(self.common_remote, "common.h"), "w", encoding="utf-8") as f:
            f.write("#pragma once\nint common_version = 1;\n")
        self._run_git(["add", "common.h"], self.common_remote)
        self._run_git(["commit", "-m", "Initial CommonLib commit"], self.common_remote)
        self._run_git(["tag", "v01.00.2601"], self.common_remote)

        os.makedirs(self.app_remote, exist_ok=True)
        self._run_git(["init", "-b", "dev"], self.app_remote)
        with open(os.path.join(self.app_remote, "main.cpp"), "w", encoding="utf-8") as f:
            f.write('#include "libs/common/common.h"\nint main() { return 0; }\n')
        self._run_git(["add", "main.cpp"], self.app_remote)
        self._run_git(["commit", "-m", "Initial MainApp commit"], self.app_remote)

    def test_forgejo_client_test_connection_and_org_provisioning(self):
        client = ForgejoClient("http://forgejo.local:3000", "fg_secret_token")

        def fake_request(method, path, params=None, data=None, timeout=30):
            if path == "/api/v1/version":
                return {"version": "9.0.1+gitea-1.22.0"}, 200
            if path == "/api/v1/user":
                return {"login": "devops_admin"}, 200
            if path == "/api/v1/orgs/MyTeamOrg" and method == "GET":
                return None, 404
            if path == "/api/v1/orgs" and method == "POST":
                return {"username": data["username"]}, 201
            return {}, 200

        client._request = MagicMock(side_effect=fake_request)
        conn_info = client.test_connection()
        self.assertTrue(conn_info["success"])
        self.assertEqual(conn_info["version"], "9.0.1+gitea-1.22.0")
        self.assertEqual(conn_info["username"], "devops_admin")
        self.assertTrue(conn_info["authenticated"])

        org_info = client.ensure_org("MyTeamOrg")
        self.assertEqual(org_info["username"], "MyTeamOrg")

    def test_forgejo_standby_push_and_pull_mirror_strategies(self):
        # Create bare repositories on disk to act as the Forgejo server's Git storage
        fg_common_bare = os.path.join(self.forgejo_git_dir, "CommonLib.git")
        fg_app_bare = os.path.join(self.forgejo_git_dir, "MainApp.git")
        os.makedirs(fg_common_bare, exist_ok=True)
        os.makedirs(fg_app_bare, exist_ok=True)
        self._run_git(["init", "--bare"], fg_common_bare)
        self._run_git(["init", "--bare"], fg_app_bare)

        client = ForgejoClient("http://forgejo.local:3000", "fg_token")
        client.ensure_org = MagicMock(return_value={"username": "MyOrg"})

        def fake_ensure_repo(org_name, repo_name, description="", private=True, default_branch="dev"):
            bare_target = fg_common_bare if repo_name == "CommonLib" else fg_app_bare
            return {
                "name": repo_name,
                "html_url": f"http://forgejo.local:3000/{org_name}/{repo_name}",
                "clone_url": bare_target,
            }

        client.ensure_repo = MagicMock(side_effect=fake_ensure_repo)
        client.update_repo_metadata = MagicMock(return_value={})
        client.migrate_pull_mirror = MagicMock(side_effect=lambda **kw: {
            "name": kw["repo_name"],
            "html_url": f"http://forgejo.local:3000/{kw['org_name']}/{kw['repo_name']}",
        })

        repos = [
            {"id": "r-app", "name": "MainApp", "remoteUrl": self.app_remote, "defaultBranch": "refs/heads/dev", "last_push_id": 10},
            {"id": "r-common", "name": "CommonLib", "remoteUrl": self.common_remote, "defaultBranch": "refs/heads/dev", "last_push_id": 5},
        ]
        sub_map = {"MainApp": ["CommonLib"]}

        # 1. Test "push" strategy (automatically creates Path 1 mirrors and pushes refs/heads/* & refs/tags/* to Forgejo)
        sync_mgr = ForgejoStandbySyncManager(
            forgejo_client=client,
            org_name="MyOrg",
            strategy="push",
            backup_dir=self.backup_dir,
            project_id="ForgejoProj",
            cache_db=self.cache_db,
        )
        res_push = sync_mgr.sync_all_repositories(repos=repos, submodule_map=sub_map)
        self.assertEqual(res_push["total_repositories"], 2)
        self.assertEqual(res_push["ok_count"], 2)
        self.assertEqual(res_push["failed_count"], 0)
        self.assertEqual([r["repo_name"] for r in res_push["repositories"]], ["CommonLib", "MainApp"])

        # Verify branches and tags actually arrived inside the target Forgejo bare repos
        tags_in_fg_common = self._run_git(["tag", "-l"], fg_common_bare)
        self.assertIn("v01.00.2601", tags_in_fg_common)
        branches_in_fg_app = self._run_git(["branch", "-l"], fg_app_bare)
        self.assertIn("dev", branches_in_fg_app)

        # Verify SQLite migration_status was updated with Forgejo status
        mig_rows = self.cache_db.get_migration_status(project_id="ForgejoProj")
        self.assertEqual(len(mig_rows), 2)
        self.assertTrue(all(r["forgejo_status"] == "OK" for r in mig_rows))

        # 2. Test "pull_mirror" strategy
        sync_mgr_pull = ForgejoStandbySyncManager(
            forgejo_client=client,
            org_name="MyOrg",
            strategy="pull_mirror",
            backup_dir=self.backup_dir,
            project_id="ForgejoProj",
            cache_db=self.cache_db,
        )
        res_pull = sync_mgr_pull.sync_all_repositories(repos=repos, submodule_map=sub_map)
        self.assertEqual(res_pull["ok_count"], 2)
        self.assertEqual(client.migrate_pull_mirror.call_count, 2)

    def test_devops_backend_get_migration_status_list_on_existing_project(self):
        """
        Verifies that opening an existing project database on DevOpsBackend and calling
        getMigrationStatusList() / getSubmoduleAuditList() / selectedProject / tfsToken
        succeeds without AttributeError and lists cached active repositories.
        """
        from gui.backend import DevOpsBackend
        self.cache_db.save_repository("LegacyProj", {"id": "leg-1", "name": "LegacyRepoA", "isDisabled": False}, 42)
        backend = DevOpsBackend()
        backend._cache_db = self.cache_db
        backend._project_id = "LegacyProj"

        self.assertEqual(backend.selectedProject, backend.selectedProject)
        self.assertIsInstance(backend.tfsToken, str)
        status_list = backend.getMigrationStatusList()
        self.assertEqual(len(status_list), 1)
        self.assertEqual(status_list[0]["repo_name"], "LegacyRepoA")
        self.assertEqual(status_list[0]["local_status"], "PENDING")
        self.assertEqual(backend.getSubmoduleAuditList(), [])

    def test_submodule_audit_suppresses_http_404_error_logs_for_repos_without_gitmodules_or_branches(self):
        """
        Verifies that repositories without a .gitmodules file (TF401174 HTTP 404) or
        empty repositories without branches (VS403403 HTTP 404) do not log ERRORs on
        azure.azure_base_client during ParseSubmodules or SubmoduleAuditor scans.
        """
        import io
        import urllib.error
        from unittest.mock import patch
        from azure.azure_info_handler import AzureInfoHandler

        handler = AzureInfoHandler(
            url="https://tfs.simdev.defence.ruag.com/tfs/DefaultCollection",
            token="dummy-pat",
        )

        repos_payload = {
            "value": [
                {
                    "id": "cda45509-6465-454b-ad76-a3d6b3b8302f",
                    "name": "elsa-tdp",
                    "defaultBranch": "refs/heads/dev",
                    "remoteUrl": "https://tfs.simdev.defence.ruag.com/tfs/DefaultCollection/CH_ELSA/_git/elsa-tdp",
                },
                {
                    "id": "94b47644-40fc-400e-a745-00655132186b",
                    "name": "CH_ELSA",
                    "defaultBranch": "",
                    "remoteUrl": "https://tfs.simdev.defence.ruag.com/tfs/DefaultCollection/CH_ELSA/_git/CH_ELSA",
                },
            ]
        }

        def fake_urlopen(req, *args, **kwargs):
            url = req.full_url if hasattr(req, "full_url") else str(req)
            if "path=.gitmodules" in url:
                if "94b47644" in url:
                    err_body = b'{"$id":"1","message":"VS403403: Cannot find any branches for the CH_ELSA repository.","typeKey":"GitItemNotFoundException"}'
                else:
                    err_body = b'{"$id":"1","message":"TF401174: The item \'.gitmodules\' could not be found in the repository \'elsa-tdp\'","typeKey":"GitItemNotFoundException"}'
                raise urllib.error.HTTPError(url, 404, "Not Found", {}, io.BytesIO(err_body))
            raise AssertionError(f"Unexpected URL: {url}")

        with patch.object(handler, "get_repositories", return_value=repos_payload["value"]), \
             patch("urllib.request.urlopen", side_effect=fake_urlopen), \
             self.assertNoLogs("azure.azure_base_client", level="ERROR"):
            parsed = handler.ParseSubmodules(
                repo=repos_payload["value"][0],
                project_id="CH_ELSA",
                branch_name="dev",
                fetch_item_info=True,
            )
            self.assertEqual(parsed, [])

            auditor = SubmoduleAuditor(info_handler=handler, project_id="CH_ELSA", cache_db=self.cache_db)
            summary = auditor.audit_project_submodules()
            self.assertEqual(summary["total_repos_scanned"], 2)
            self.assertEqual(summary["total_submodules"], 0)


if __name__ == "__main__":
    unittest.main()
