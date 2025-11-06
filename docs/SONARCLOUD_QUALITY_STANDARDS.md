# SonarCloud Quality Standards

## Overview

SonarCloud is an automated code quality and security analysis tool. This project uses
**Automatic Analysis via GitHub App** integration with **"Sonar way"** quality gate.

- **Organization**: wlevan3
- **Project Key**: `wlevan3_ml-platform-engineering-practicum`
- **Dashboard**: [View on SonarCloud](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
- **Coverage Target**: 90% (gate: ≥80%)

---

## Quality Gate Thresholds

All conditions must **pass** for new code:

| Condition | Threshold | Fix Strategy |
|-----------|-----------|--------------|
| **Reliability Rating** | A (≤1 bug) | Fix all bugs in changes |
| **Security Rating** | A (≤1 vulnerability) | Resolve security issues |
| **Maintainability Rating** | A (≤5% technical debt) | Address code smells |
| **Coverage on New Code** | ≥ 80% | Add tests for new code |
| **Duplicated Lines** | ≤ 3% | Refactor duplicates |
| **Security Hotspots** | 100% reviewed | Review and mark safe/fixed |

**Current Status**: ✅ PASSING

---

## Issue Types

| Type | Impact | Examples |
|------|--------|----------|
| **Bugs** | Application crashes/errors | Null pointers, division by zero, type mismatches |
| **Vulnerabilities** | Security breaches | SQL injection, hardcoded secrets, insecure crypto |
| **Code Smells** | Maintainability issues | Long functions, duplication, dead code |
| **Security Hotspots** | Needs review | Authentication, authorization, crypto, file/network access |

---

## Severity Levels

| Severity | Action | Time to Fix |
|----------|--------|-------------|
| ⛔ **Blocker** | Fix immediately | < 1 hour |
| 🔴 **Critical** | Fix before merge | < 4 hours |
| 🟠 **Major** | Fix soon | < 1 day |
| 🟡 **Minor** | Fix when convenient | < 1 week |
| ℹ️ **Info** | Optional | As time allows |

---

## Ratings (A-E Scale)

| Rating | Bugs | Vulnerabilities | Technical Debt Ratio |
|--------|------|-----------------|---------------------|
| **A** 🟢 | 0 | 0 | ≤ 5% |
| **B** 🟡 | ≥ 1 Minor | ≥ 1 Minor | 6-10% |
| **C** 🟠 | ≥ 1 Major | ≥ 1 Major | 11-20% |
| **D** 🔴 | ≥ 1 Critical | ≥ 1 Critical | 21-50% |
| **E** ⛔ | ≥ 1 Blocker | ≥ 1 Blocker | > 50% |

---

## Quick Remediation

### When Quality Gate Fails

1. **View issues**: Click "Details" on SonarCloud check in PR
2. **Filter by "New Code"** to see issues in your changes
3. **Fix by severity**:
   - Blockers/Critical → Fix immediately
   - Major → Fix or document deferral
   - Minor/Info → Fix if time permits

### Common Fixes

**Coverage Below 80%**:

```bash
pytest --cov=app --cov-report=term-missing
# Add tests for lines marked as uncovered
```

**Code Duplication > 3%**:

```python
# Extract duplicated code into shared function
def shared_logic(param):
    # Common code here
    pass
```

**Cognitive Complexity Too High**:

- Use early returns instead of nested ifs
- Break into smaller functions
- Extract validation logic

### Mark as "Won't Fix"

Only if:

- Issue is not applicable to this context
- Fix would harm code quality/readability
- Issue is in generated/third-party code

Add comment explaining why when marking.

---

## Configuration

### `sonar-project.properties`

```properties
sonar.projectKey=wlevan3_ml-platform-engineering-practicum
sonar.organization=wlevan3
sonar.python.version=3.13
sonar.sources=services/api/
sonar.tests=tests/
sonar.python.coverage.reportPaths=coverage.xml
sonar.exclusions=**/__pycache__/**,**/services/api/models/**,**/.venv/**
sonar.sourceEncoding=UTF-8
```

### `pytest.ini` Coverage

```ini
[pytest]
testpaths = tests
python_files = test_*.py

[coverage:run]
source = app
omit = tests/*,.venv/*,services/api/models/**,**/__pycache__/*

[coverage:report]
show_missing = True
precision = 2
```

**Coverage Flow**:

1. `pytest --cov=app --cov-report=xml` generates `coverage.xml`
2. GitHub artifact uploads to SonarCloud
3. SonarCloud reads metrics during analysis

---

## IDE Integration (Optional)

**SonarLint** provides real-time feedback while coding:

- **VS Code**: Install "SonarLint" extension
- **PyCharm**: Install "SonarLint" plugin
- Benefits: See issues before committing, faster feedback loop, learn best practices

---

## Workflow

### When Analysis Runs

SonarCloud analyzes automatically on:

- ✅ Every push to PR branch
- ✅ Every merge to `main` branch
- Timing: 1-2 minutes

### Pull Request Flow

```text
Push → GitHub Actions CI → SonarCloud Analysis
       ↓
Quality Gate?
  ✅ Pass → Ready for review → Merge
  ❌ Fail → Fix locally → Push → Re-analyze
```

---

## Resources

**Official Docs**:

- [SonarCloud Documentation](https://docs.sonarcloud.io/)
- [Python Rules](https://docs.sonarsource.com/sonarqube/latest/analyzing-source-code/languages/python/)
- [Quality Gates](https://docs.sonarcloud.io/improving/quality-gates/)
- [Clean as You Code](https://docs.sonarcloud.io/improving/clean-as-you-code/)

**Project Links**:

- [Dashboard](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
- [Issues](https://sonarcloud.io/project/issues?id=wlevan3_ml-platform-engineering-practicum)
- [Measures](https://sonarcloud.io/component_measures?id=wlevan3_ml-platform-engineering-practicum)

**Related Docs**:

- [CONTRIBUTING.md](../CONTRIBUTING.md) - Development workflow
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Commands

---

**Version**: 1.0 | **Last Updated**: 2025-11-05 | **Next Review**: Phase 3 or 3 months
