# -*- coding: UTF-8 -*-
"""
Legacy helper and date parsing utilities for Azure DevOps integration.
Re-exports AzureInfoHandler from azure_info_handler to eliminate duplicate implementation.
"""
import logging
from datetime import datetime, timedelta

try:
    from .azure_info_handler import AzureInfoHandler, _enrich_pr
    from .azure_base_client import AzureBaseClient
except ImportError:
    from azure_info_handler import AzureInfoHandler, _enrich_pr
    from azure_base_client import AzureBaseClient

logger = logging.getLogger(__name__)


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
        s = date_str.replace("Z", "").replace("T", " ")
        if "." in s:
            s = s.split(".")[0]
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


__all__ = [
    "AzureInfoHandler",
    "AzureBaseClient",
    "parse_iso_datetime",
    "UpdateDateString",
    "_enrich_pr",
]
