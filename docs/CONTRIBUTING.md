# Contributing Guide

This guide covers the development workflow, coding standards, and contribution process for the ML Platform project.

## Table of Contents

- [Development Workflow](#development-workflow)
- [Commit and PR Process](#commit-and-pr-process)
- [Code Standards](#code-standards)
- [Testing Requirements](#testing-requirements)
- [Pre-commit Checks](#pre-commit-checks)

## Development Workflow

### When to Create Issues vs. Direct Changes

**Create an issue first** when:
- Implementing new features (use Feature Request template)
- Fixing non-trivial bugs (use Bug Report template)
- Making infrastructure changes (use Infrastructure Change template)
- Documenting learning reflections (use Learning Reflection template)
- Changes require discussion or architectural decisions
- Work will take multiple commits or sessions

**Skip issue creation** for:
- Typo fixes in documentation
- Updating dependencies (minor version bumps)
- Fixing broken links
- Small refactoring with no functional changes
- Documentation improvements (grammar, formatting)

**Workflow**:
```bash
# For issues: Create issue → Create branch → Make changes → Create PR → Link issue
# For direct changes: Create branch → Make changes → Create PR
```

## Commit and PR Process

### Branch Naming

Use descriptive branch names following this pattern:

```text
<type>/<short-description>
```

**Types**:
- `feature/` - New features or enhancements
- `fix/` - Bug fixes
- `infra/` - Infrastructure changes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring
- `ci/` - CI/CD changes

**Examples**:
- `feature/add-mlflow-integration`
- `fix/prediction-timeout`
- `infra/eks-cluster-setup`
- `docs/update-readme`

### Commit Format (Conventional Commits)

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat` - New feature
- `fix` - Bug fix
- `infra` - Infrastructure changes
- `docs` - Documentation
- `style` - Code style/formatting
- `refactor` - Code refactoring
- `test` - Adding/updating tests
- `chore` - Maintenance tasks
- `ci` - CI/CD changes

**Examples**:
```
feat(model-registry): add MLflow integration

Integrate MLflow for model versioning and experiment tracking.
Implements model registration workflow with custom PyFunc wrapper.

Closes #42
```

```
fix(api): resolve prediction timeout issue

Increase model loading timeout from 30s to 60s for large models.
Add retry logic with exponential backoff.

Fixes #58
```

```
infra(eks): upgrade cluster to v1.28

- Upgrade EKS cluster from v1.27 to v1.28
- Update node group AMI
- Test with sample workload

Related to #73
```

### Pull Request Process

1. **Create feature branch** from `main`
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feature/your-feature-name
   ```

2. **Make changes** with atomic commits
   - Keep commits focused on a single change
   - Write clear commit messages following Conventional Commits

3. **Run tests locally** before pushing
   ```bash
   # Run all tests
   pytest -v

   # Check code quality
   black --check .
   ruff check .
   mypy app/

   # Run pre-commit hooks
   pre-commit run --all-files
   ```

4. **Push and create PR** using the template
   ```bash
   git push -u origin feature/your-feature-name
   ```
   Then create a PR on GitHub using the pull request template.

5. **Self-review your changes**
   - Review the diff on GitHub
   - Check for commented-out code, debugging statements
   - Ensure documentation is updated

6. **Ensure CI passes**
   - Monitor CI checks: `gh pr checks $PR_NUMBER --watch`
   - Address any automated PR comments
   - Fix failing tests or security scans

7. **Squash merge** to `main`
   - Keeps history clean with one commit per PR
   - Combine all commits into a single, well-described commit

### Handling Merge Conflicts

If your branch has conflicts with `main`:

#### Option 1: Rebase (Preferred)

Creates a clean, linear history:

```bash
# Update your local main branch
git checkout main
git pull origin main

# Switch back to feature branch
git checkout your-feature-branch

# Rebase on latest main
git rebase main

# If conflicts occur, resolve them in your editor
# Then continue rebase
git add <resolved-files>
git rebase --continue

# Force push (rebase rewrites history)
git push --force-with-lease origin your-feature-branch
```

**Tip**: Use `--force-with-lease` instead of `--force` to prevent overwriting others' work.

#### Option 2: Merge

Creates a merge commit:

```bash
# Update your local main branch
git checkout main
git pull origin main

# Switch back to feature branch
git checkout your-feature-branch

# Merge main into your branch
git merge main

# Resolve conflicts if any
git add <resolved-files>
git commit

# Push changes
git push origin your-feature-branch
```

### Before Creating PRs

Run the `pre-push-review` skill (Claude Code skill) to automatically check shell scripts and GitHub Actions:

```bash
/pre-push-review
```

This runs:
- `shellcheck` on `.sh/.bash` files
- `actionlint` on `.github/workflows/*.yml` files

## Code Standards

### Python

- **Style**: Follow PEP 8 via `black` (line length: 88)
- **Type hints**: Required for all function signatures
- **Docstrings**: Required for modules, classes, and public functions
- **Exception handling**: Use specific exceptions, never bare `except:`
- **Data validation**: Use Pydantic models for FastAPI schemas

**Example**:
```python
def predict(features: List[float]) -> Tuple[str, float]:
    """
    Make a prediction for the given features.

    Args:
        features: List of 4 float values

    Returns:
        Tuple of (predicted_class, confidence)

    Raises:
        ValueError: If features count is not 4
    """
    if len(features) != 4:
        raise ValueError(f"Expected 4 features, got {len(features)}")

    # Implementation...
```

### FastAPI Patterns

- **Singleton pattern** for model loading (see `app/model.py:get_model()`)
- **Lifespan events** for startup/shutdown logic (see `app/main.py:lifespan()`)
- **Dependency injection** for shared resources
- **HTTPException** for error responses with proper status codes
- **Response models** for all endpoints (type safety and auto-docs)

**Example**:
```python
from fastapi import HTTPException, status

@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest) -> PredictionResponse:
    """Make a prediction."""
    try:
        result = model.predict(request.features)
        return PredictionResponse(**result)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
```

### Infrastructure (Future)

When Terraform is added:

- **Resource naming**: Descriptive names with consistent prefixes
- **Tagging**: Tag all AWS resources with `Project`, `Environment`, `ManagedBy`
- **Variables**: Use variables for reusable values
- **Organization**: Organize by service/component
- **Plan review**: Always review `terraform plan` before apply

## Testing Requirements

### Test Structure

- **Location**: All tests in `tests/` directory
- **Naming**: Test files named `test_*.py`
- **Fixtures**: Use `pytest` fixtures for shared setup
- **API testing**: Use FastAPI `TestClient` (see `tests/test_api.py`)

### Coverage Target

- **Minimum**: 80% code coverage (configured in `pytest.ini`)
- **Check coverage**: `pytest --cov=app --cov-report=html`
- **View report**: Open `htmlcov/index.html`

### Running Tests

```bash
# Run all tests
pytest

# Run specific test file
pytest tests/test_api.py

# Run with verbose output
pytest -v

# Run tests matching pattern
pytest -k "test_health"

# Run with coverage
pytest --cov=app --cov-report=term-missing
```

## Pre-commit Checks

Pre-commit hooks automatically run before each commit:

- **black** - Code formatting
- **ruff** - Linting
- **mypy** - Type checking
- **detect-secrets** - Secret detection
- **semgrep** - Security scanning

### Setup

```bash
# Install hooks
pre-commit install

# Run manually on all files
pre-commit run --all-files

# Run specific hook
pre-commit run black --all-files

# Update hook versions
pre-commit autoupdate
```

### Handling Failures

If pre-commit hooks fail:

1. **Formatting issues**: Run `black .` to auto-fix
2. **Linting issues**: Run `ruff check . --fix` to auto-fix
3. **Type errors**: Fix manually based on mypy output
4. **Secrets detected**: Review and add to `.secrets.baseline` if false positive
5. **Security issues**: Review semgrep findings and fix or add `# nosemgrep` with justification

## Branch Protection

The `main` branch is protected:

- ✅ Requires pull request
- ✅ Requires conversation resolution
- ❌ No force pushes
- ❌ No direct commits

All changes must go through pull requests.

## Getting Help

- **Questions**: Create a discussion on GitHub
- **Bugs**: Use the Bug Report issue template
- **Features**: Use the Feature Request issue template
- **Documentation**: Check `docs/` directory
- **Troubleshooting**: See `docs/TROUBLESHOOTING.md`
