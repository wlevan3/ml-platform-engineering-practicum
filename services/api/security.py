"""Compatibility shim for security utilities.

This module is maintained for backward compatibility during the STREAMLINING_PLAN
migration. The canonical implementation now lives in ml_platform_api.security.
"""

from ml_platform_api.security import *  # noqa: F401,F403
