# -*- coding: UTF-8 -*-
"""
Azure DevOps integration package.
Provides clients, handlers, and caching for Azure DevOps (TFS) REST APIs.
"""

from .azure_base_client import AzureBaseClient, AzureServerConnectionError, AzureAuthenticationError, is_connection_error
from .azure_db import AzureDevOpsCache, DateTimeEncoder, is_work_item_in_area_path
from .azure_info_base_client import AzureBaseClient as AzureInfoBaseClient
from .azure_info_handler import AzureInfoHandler
from .azure_helper import AzureInfoHandler as AzureHelperInfoHandler
from .migration_service import (
    SubmoduleAuditor,
    LocalBackupManager,
    ForgejoClient,
    ForgejoStandbySyncManager,
    parse_gitmodules_content,
    classify_submodule_url,
    rewrite_gitmodules_to_relative,
    sort_repos_topologically,
    build_git_auth_args,
    VALID_BACKUP_MODES,
    VALID_FORGEJO_STRATEGIES,
)

__all__ = [
    "AzureBaseClient",
    "AzureServerConnectionError",
    "AzureAuthenticationError",
    "is_connection_error",
    "AzureDevOpsCache",
    "DateTimeEncoder",
    "is_work_item_in_area_path",
    "AzureInfoBaseClient",
    "AzureInfoHandler",
    "AzureHelperInfoHandler",
    "SubmoduleAuditor",
    "LocalBackupManager",
    "ForgejoClient",
    "ForgejoStandbySyncManager",
    "parse_gitmodules_content",
    "classify_submodule_url",
    "rewrite_gitmodules_to_relative",
    "sort_repos_topologically",
    "build_git_auth_args",
    "VALID_BACKUP_MODES",
    "VALID_FORGEJO_STRATEGIES",
]
