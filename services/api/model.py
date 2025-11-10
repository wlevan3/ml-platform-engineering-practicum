"""
Compatibility shim for ML model utilities.

Canonical implementation:
- src/ml_platform_api/model.py

This shim ensures that imports like:
- from services.api.model import IrisModel, get_model, ModelIntegrityError
continue to work regardless of whether `ml_platform_api` has been installed
as a package or is only present in the local src/ tree.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Try the canonical import first (works if the project is installed/editable).
try:
    from ml_platform_api.model import *  # noqa: F401,F403
except ModuleNotFoundError:
    # Fallback for local development / CI when src/ is not on PYTHONPATH.
    repo_root = Path(__file__).resolve().parents[2]
    src_dir = repo_root / "src"
    if src_dir.is_dir() and str(src_dir) not in sys.path:
        sys.path.insert(0, str(src_dir))

    # Retry import now that src/ is on sys.path.
    from ml_platform_api.model import *  # type: ignore[assignment, misc]  # noqa: F401,F403
