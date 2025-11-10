"""Compatibility shim for model training utilities.

This module is maintained for backward compatibility during the STREAMLINING_PLAN
migration. The canonical implementation now lives in ml_platform_api.train_model.
"""

from ml_platform_api.train_model import *  # noqa: F401,F403
