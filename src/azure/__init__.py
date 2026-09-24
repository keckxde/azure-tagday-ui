# -*- coding: UTF-8 -*-
"""
Azure DevOps integration package.
Provides clients, handlers, and caching for Azure DevOps (TFS) REST APIs.
"""

from .azure_base_client import AzureBaseClient, AzureServerConnectionError, is_connection_error
from .azure_db import AzureDevOpsCache, DateTimeEncoder
from .azure_info_base_client import AzureBaseClient as AzureInfoBaseClient
from .azure_info_handler import AzureInfoHandler
from .azure_helper import AzureInfoHandler as AzureHelperInfoHandler

__all__ = [
    "AzureBaseClient",
    "AzureServerConnectionError",
    "is_connection_error",
    "AzureDevOpsCache",
    "DateTimeEncoder",
    "AzureInfoBaseClient",
    "AzureInfoHandler",
    "AzureHelperInfoHandler",
]
