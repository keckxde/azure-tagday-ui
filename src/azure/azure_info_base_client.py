# -*- coding: UTF-8 -*-
"""
Backward-compatibility module shim.

AzureBaseClient has been consolidated into azure.azure_base_client.
This file re-exports AzureBaseClient, AzureServerConnectionError, and is_connection_error
to ensure backwards compatibility with legacy imports.
"""

try:
    from .azure_base_client import AzureBaseClient, AzureServerConnectionError, is_connection_error
except ImportError:
    from azure_base_client import AzureBaseClient, AzureServerConnectionError, is_connection_error

__all__ = ["AzureBaseClient", "AzureServerConnectionError", "is_connection_error"]
