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
]
