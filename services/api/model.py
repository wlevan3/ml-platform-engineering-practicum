"""
Compatibility shim for ML model utilities.

This module is maintained for backward compatibility during the STREAMLINING_PLAN
migration. The canonical implementation now lives in ml_platform_api.model.
"""

from ml_platform_api.model import *  # noqa: F401,F403
