# OPT-01: Add Python Dependency Caching to CI Pipeline

## Overview

**Priority:** TIER 1 - Critical Quick Win
**Estimated Time:** 5 minutes
**Impact:** Saves 30-60 seconds per Python job (4 jobs total = 2-4 minutes per CI run)
**ROI:** HIGHEST

## Problem Statement

Currently, the CI pipeline installs Python dependencies from scratch in every job:
- `python-lint` (line ~227)
- `python-test` (line ~254)
- `docker-build-scan` (line ~454)
- `sbom-generation` (line ~524)

Each job downloads packages from PyPI every time, wasting time and bandwidth.

## Solution

Add GitHub Actions caching for pip dependencies using `actions/cache@v4`.

## Implementation Steps

### 1. Open the CI workflow file

```bash
# Open in your editor
vim .github/workflows/ci.yml
# OR
code .github/workflows/ci.yml
```

### 2. Add caching to `python-lint` job

**Location:** After line 230 (after `Setup Python` step)

**Add these lines:**

```yaml
      - name: Cache pip dependencies
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-
```

**Result:** Lines 231-237 should be the new cache step.

### 3. Add caching to `python-test` job

**Location:** After line 257 (after `Setup Python` step)

**Add the same cache configuration:**

```yaml
      - name: Cache pip dependencies
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-
```

### 4. Add caching to `docker-build-scan` job

**Location:** After line 457 (after `Setup Python` step)

**Add the same cache configuration:**

```yaml
      - name: Cache pip dependencies
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-
```

### 5. Add caching to `sbom-generation` job

**Location:** After line 527 (after `Setup Python` step)

**Add the same cache configuration:**

```yaml
      - name: Cache pip dependencies
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-
```

## Verification Steps

### 1. Verify YAML syntax

```bash
# Check for YAML syntax errors
yamllint .github/workflows/ci.yml

# OR use GitHub Actions validator (if available)
actionlint .github/workflows/ci.yml
```

### 2. Check line counts

```bash
# Before: 649 lines
# After: Should be ~673 lines (24 lines added: 6 lines × 4 jobs)
wc -l .github/workflows/ci.yml
```

### 3. Visual inspection

Ensure each cache block:
- Is properly indented (same level as other steps)
- Comes AFTER `Setup Python` step
- Comes BEFORE `Install dependencies` step

### 4. Test locally with act (optional)

```bash
# If you have act installed
act pull_request -j python-lint
```

### 5. Create PR and observe CI

- First run: Cache miss (normal installation time)
- Second run: Cache hit (30-60s faster per job)

## Testing Checklist

- [ ] YAML file is valid (no syntax errors)
- [ ] All 4 Python jobs have the cache step added
- [ ] Cache step is positioned correctly (after Python setup, before dependency install)
- [ ] Indentation matches existing steps
- [ ] CI pipeline runs successfully
- [ ] Second CI run shows cache hit in logs

## Expected CI Output

**First run (cache miss):**
```
Cache not found for input keys: ubuntu-latest-pip-abc123...
```

**Subsequent runs (cache hit):**
```
Cache restored from key: ubuntu-latest-pip-abc123...
```

**Time savings:**
- python-lint: 15-30s faster
- python-test: 30-60s faster
- docker-build-scan: 30-60s faster
- sbom-generation: 30-60s faster
- **Total: 2-4 minutes per CI run**

## Git Workflow

### Branch name

```bash
git checkout -b ci/add-python-dependency-caching
```

### Commit message

```
ci(pipeline): add pip dependency caching to Python jobs

Add GitHub Actions caching for pip dependencies across all Python jobs
(python-lint, python-test, docker-build-scan, sbom-generation).

Cache key: requirements.txt hash
Cache location: ~/.cache/pip

Benefits:
- Reduces CI time by 2-4 minutes per run
- Reduces PyPI bandwidth usage
- Faster feedback on PRs

Related: OPT-01 (optimization initiative)
```

### Push and create PR

```bash
git add .github/workflows/ci.yml
git commit -m "ci(pipeline): add pip dependency caching to Python jobs"
git push -u origin ci/add-python-dependency-caching

# Create PR
gh pr create --title "ci: Add pip dependency caching to Python jobs" \
  --body "## Changes
- Add pip dependency caching to 4 Python jobs
- Cache key: requirements.txt hash
- Expected speedup: 2-4 minutes per CI run

## Testing
- [x] YAML syntax validated
- [x] CI runs successfully
- [ ] Cache hit confirmed on second run (will verify post-merge)

## Related
Part of optimization initiative OPT-01"
```

## Rollback Plan

If caching causes issues:

```bash
git revert <commit-sha>
```

Or manually remove the 4 cache step blocks.

## Additional Notes

### Why this works

- Pip stores downloaded packages in `~/.cache/pip`
- Cache key is based on `requirements.txt` hash
- When requirements.txt doesn't change, cache is reused
- When requirements.txt changes, cache is rebuilt

### Cache invalidation

Cache automatically invalidates when:
- `requirements.txt` is modified
- 7 days pass (GitHub Actions default)
- Manual cache deletion via GitHub UI

### Restore keys

The `restore-keys` provides a fallback:
- If exact match not found, uses most recent cache from same OS
- Provides partial speedup even when requirements.txt changes slightly

## References

- [GitHub Actions Cache Documentation](https://github.com/actions/cache)
- [Caching pip dependencies](https://github.com/actions/cache/blob/main/examples.md#python---pip)
- Project: ml-platform-engineering-practicum
- Issue: Optimization Initiative (OPT-01)
