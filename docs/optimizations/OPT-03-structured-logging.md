# OPT-03: Replace print() with Structured Logging

## Overview

**Priority:** TIER 1 - Critical Quick Win
**Estimated Time:** 15 minutes
**Impact:** Production-grade observability, log levels, structured logs for aggregation
**ROI:** VERY HIGH

## Problem Statement

Currently, the codebase uses `print()` statements for logging:

**app/main.py:**
- Line 28: `print("✓ Model loaded successfully")`
- Line 30: `print(f"✗ Failed to load model: {e}")`
- Line 36: `print("Shutting down...")`

**train_model.py:**
- Multiple `print()` statements throughout

**Issues with print():**
- No log levels (can't filter INFO vs ERROR)
- No timestamps
- No module/function context
- Hard to parse in log aggregation systems (ELK, CloudWatch)
- Not production-ready
- Can't disable debug logs in production

## Solution

Replace `print()` with Python's built-in `logging` module for structured, production-grade logging.

## Implementation Steps

### 1. Update app/main.py

**File:** `app/main.py`

#### Step 1.1: Add logging import

**Location:** Line 5 (after existing imports)

**Add:**
```python
import logging
```

#### Step 1.2: Initialize logger

**Location:** Line 18 (after imports, before @asynccontextmanager)

**Add:**
```python
# Configure logging
logger = logging.getLogger(__name__)
```

#### Step 1.3: Replace print() statements

**Line 28:** Replace:
```python
print("✓ Model loaded successfully")
```

**With:**
```python
logger.info("Model loaded successfully")
```

**Line 30:** Replace:
```python
print(f"✗ Failed to load model: {e}")
```

**With:**
```python
logger.error("Failed to load model: %s", e, exc_info=True)
```

**Line 36:** Replace:
```python
print("Shutting down...")
```

**With:**
```python
logger.info("Application shutting down")
```

#### Complete updated lifespan function:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model on startup, clean up on shutdown."""
    # Startup
    model = get_model()
    try:
        model.load()
        logger.info("Model loaded successfully")
    except Exception as e:
        logger.error("Failed to load model: %s", e, exc_info=True)
        raise

    yield

    # Shutdown
    logger.info("Application shutting down")
```

### 2. Create logging configuration module

**File:** `app/logging_config.py` (new file)

**Create:**
```python
"""
Logging configuration for the ML platform API.

Provides structured logging with timestamps, log levels, and module context.
"""

import logging
import sys


def setup_logging(level: str = "INFO") -> None:
    """
    Configure application-wide logging.

    Args:
        level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    """
    # Parse log level from string
    numeric_level = getattr(logging, level.upper(), logging.INFO)

    # Configure root logger
    logging.basicConfig(
        level=numeric_level,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[
            logging.StreamHandler(sys.stdout)
        ],
        force=True,  # Override any existing configuration
    )

    # Set third-party loggers to WARNING to reduce noise
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

    logging.info("Logging configured: level=%s", level)
```

### 3. Initialize logging on startup

**File:** `app/main.py`

**Location:** After imports, before `@asynccontextmanager`

**Add:**
```python
from app.logging_config import setup_logging

# Initialize logging
setup_logging()

logger = logging.getLogger(__name__)
```

### 4. Update train_model.py

**File:** `train_model.py`

#### Step 4.1: Add logging import

**Location:** Line 6 (after existing imports)

**Add:**
```python
import logging
```

#### Step 4.2: Initialize logger

**Location:** Line 17 (after imports, before train_model function)

**Add:**
```python
# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)
```

#### Step 4.3: Replace print() statements

**Line 21:** Replace:
```python
print("Loading Iris dataset...")
```

**With:**
```python
logger.info("Loading Iris dataset...")
```

**Line 30:** Replace:
```python
print(f"Training set: {len(X_train)} samples")
```

**With:**
```python
logger.info("Training set: %d samples", len(X_train))
```

**Line 31:** Replace:
```python
print(f"Test set: {len(X_test)} samples")
```

**With:**
```python
logger.info("Test set: %d samples", len(X_test))
```

**Line 34:** Replace:
```python
print("\nTraining Random Forest classifier...")
```

**With:**
```python
logger.info("Training Random Forest classifier...")
```

**Line 44:** Replace:
```python
print(f"\nModel accuracy: {accuracy:.4f}")
```

**With:**
```python
logger.info("Model accuracy: %.4f", accuracy)
```

**Line 45-46:** Replace:
```python
print("\nClassification Report:")
print(classification_report(y_test, y_pred, target_names=iris.target_names))
```

**With:**
```python
logger.info("Classification Report:\n%s",
    classification_report(y_test, y_pred, target_names=iris.target_names))
```

**Line 54:** Replace:
```python
print(f"\nModel saved to: {model_path}")
```

**With:**
```python
logger.info("Model saved to: %s", model_path)
```

**Line 58:** Replace:
```python
print(f"Model SHA-256 hash: {model_hash}")
```

**With:**
```python
logger.info("Model SHA-256 hash: %s", model_hash)
```

**Line 79:** Replace:
```python
print(f"Metadata saved to: {metadata_path}")
```

**With:**
```python
logger.info("Metadata saved to: %s", metadata_path)
```

## Verification Steps

### 1. Run linting

```bash
# Format code
black app/ train_model.py

# Check with ruff
ruff check app/ train_model.py

# Type checking
mypy app/
```

### 2. Run tests

```bash
# Ensure all tests pass
pytest -v
```

### 3. Test locally

```bash
# Train model - verify logging output
python train_model.py

# Expected output:
# 2025-01-15 10:30:45 - INFO - Loading Iris dataset...
# 2025-01-15 10:30:45 - INFO - Training set: 120 samples
# ...

# Run API server
uvicorn app.main:app --reload

# Expected output:
# 2025-01-15 10:31:00 - app.logging_config - INFO - Logging configured: level=INFO
# 2025-01-15 10:31:00 - app.main - INFO - Model loaded successfully
```

### 4. Test log levels

```bash
# Set environment variable for log level
export LOG_LEVEL=DEBUG
python train_model.py

# Should show more verbose output
```

### 5. Verify no print() statements remain

```bash
# Search for remaining print() calls
grep -n "print(" app/*.py train_model.py

# Should return no results (or only comments/docstrings)
```

## Testing Checklist

- [ ] All print() statements replaced with logger calls
- [ ] Logging module imported in all modified files
- [ ] Logger initialized in all modified files
- [ ] app/logging_config.py created
- [ ] Logging initialized in app/main.py
- [ ] All tests pass (`pytest`)
- [ ] Code formatted (`black`)
- [ ] No linting errors (`ruff check`)
- [ ] Local testing confirms log output is formatted correctly
- [ ] Log levels work correctly (INFO, DEBUG, ERROR)

## Expected Output

### Before (print statements)

```
✓ Model loaded successfully
Training Random Forest classifier...
Model accuracy: 0.9667
```

### After (structured logging)

```
2025-01-15 10:30:45 - app.main - INFO - Model loaded successfully
2025-01-15 10:30:46 - __main__ - INFO - Training Random Forest classifier...
2025-01-15 10:30:47 - __main__ - INFO - Model accuracy: 0.9667
```

## Git Workflow

### Branch name

```bash
git checkout -b refactor/replace-print-with-logging
```

### Commit messages

**Option 1: Single commit**

```bash
git add app/main.py app/logging_config.py train_model.py
git commit -m "refactor(logging): replace print() with structured logging

Replace all print() statements with Python logging module for
production-grade observability.

Changes:
- Add logging_config.py with centralized log configuration
- Replace print() with logger calls in app/main.py
- Replace print() with logger calls in train_model.py
- Configure log format: timestamp, module, level, message
- Set default log level to INFO (configurable via LOG_LEVEL env var)

Benefits:
- Structured logs with timestamps and context
- Filterable by log level (DEBUG, INFO, WARNING, ERROR)
- Ready for log aggregation (ELK, CloudWatch)
- Production-ready logging standard
- Easier debugging with exc_info=True for errors

Related: OPT-03 (optimization initiative)"
```

**Option 2: Multiple commits (recommended for review)**

```bash
# Commit 1: Create logging config
git add app/logging_config.py
git commit -m "feat(logging): add centralized logging configuration

Add logging_config.py module for application-wide logging setup."

# Commit 2: Update app/main.py
git add app/main.py
git commit -m "refactor(logging): replace print() with logging in app/main.py

Replace print() statements with structured logging.
Initialize logging on application startup."

# Commit 3: Update train_model.py
git add train_model.py
git commit -m "refactor(logging): replace print() with logging in train_model.py

Replace print() statements with structured logging in model training script."
```

### Push and create PR

```bash
git push -u origin refactor/replace-print-with-logging

# Create PR
gh pr create --title "refactor: Replace print() with structured logging" \
  --body "## Changes
- ✅ Add \`app/logging_config.py\` for centralized log configuration
- ✅ Replace \`print()\` with \`logger\` calls in \`app/main.py\`
- ✅ Replace \`print()\` with \`logger\` calls in \`train_model.py\`
- ✅ Configure structured log format (timestamp, module, level, message)

## Benefits
- 📊 Structured logs with timestamps and context
- 🎚️ Filterable by log level (DEBUG, INFO, WARNING, ERROR)
- 🔍 Ready for log aggregation systems (ELK, CloudWatch, Grafana Loki)
- 🏭 Production-ready logging standard
- 🐛 Better debugging with \`exc_info=True\` for exceptions

## Before
\`\`\`
✓ Model loaded successfully
Training Random Forest classifier...
\`\`\`

## After
\`\`\`
2025-01-15 10:30:45 - app.main - INFO - Model loaded successfully
2025-01-15 10:30:46 - __main__ - INFO - Training Random Forest classifier...
\`\`\`

## Testing
- [x] All tests pass (\`pytest\`)
- [x] Code formatted (\`black\`)
- [x] No linting errors (\`ruff check\`)
- [x] Local testing confirms correct log output
- [x] No remaining print() statements (verified with grep)

## Related
Part of optimization initiative OPT-03"
```

## Rollback Plan

If logging causes issues:

```bash
git revert <commit-sha>
```

Or manually revert changes in each file.

## Environment Variable Configuration

After merge, logging level can be configured via environment variable:

### Local development
```bash
# Debug mode (verbose)
export LOG_LEVEL=DEBUG
uvicorn app.main:app

# Production mode (minimal)
export LOG_LEVEL=WARNING
uvicorn app.main:app
```

### Docker
```dockerfile
# In Dockerfile
ENV LOG_LEVEL=INFO
```

### Kubernetes
```yaml
# In deployment.yaml
env:
  - name: LOG_LEVEL
    value: "INFO"
```

## Additional Notes

### Log Levels

- **DEBUG:** Detailed diagnostic information (verbose)
- **INFO:** Informational messages (default)
- **WARNING:** Warning messages (potential issues)
- **ERROR:** Error messages (failures)
- **CRITICAL:** Critical errors (system failures)

### Best Practices Applied

1. **Use logger.info(), not logger.info("message")**
   - ✅ Good: `logger.info("User %s logged in", username)`
   - ❌ Bad: `logger.info(f"User {username} logged in")`
   - Reason: Deferred string formatting (better performance)

2. **Use exc_info=True for exceptions**
   - ✅ Good: `logger.error("Error: %s", e, exc_info=True)`
   - Reason: Includes full stack trace

3. **Use __name__ for logger**
   - ✅ Good: `logger = logging.getLogger(__name__)`
   - Reason: Shows module path in logs (e.g., "app.main")

### Future Enhancements

After this PR, future improvements can include:
- JSON logging for log aggregation
- Log correlation IDs for request tracing
- Separate log files by level
- Log rotation
- Structured logging with extra fields

## References

- [Python Logging Documentation](https://docs.python.org/3/library/logging.html)
- [Python Logging Best Practices](https://docs.python.org/3/howto/logging.html#logging-basic-tutorial)
- [FastAPI Logging](https://fastapi.tiangolo.com/tutorial/handling-errors/#use-httpexception)
- Project: ml-platform-engineering-practicum
- Issue: Optimization Initiative (OPT-03)
