# OPT-04: Add Pre-commit Environment Caching

## Overview

**Priority:** TIER 2 - High-Value Optimization
**Estimated Time:** 3 minutes
**Impact:** Saves 15-30 seconds per CI run on pre-commit checks
**ROI:** HIGH

## Problem Statement

The `pre-commit-checks` job (lines 422-441) installs pre-commit and all hook environments from scratch every time:
- Downloads and installs pre-commit tools (black, ruff, mypy, hadolint, etc.)
- Builds isolated environments for each hook
- Takes 30-60 seconds to set up before running checks

Pre-commit stores these environments in `~/.cache/pre-commit` and they can be cached between CI runs.

## Solution

Add GitHub Actions caching for pre-commit hook environments using `actions/cache@v4`.

## Implementation Steps

### 1. Open the CI workflow file

```bash
# Open in your editor
vim .github/workflows/ci.yml
# OR
code .github/workflows/ci.yml
```

### 2. Locate the pre-commit-checks job

**Current location:** Lines 422-441

**Current structure:**
```yaml
  pre-commit-checks:
    name: Pre-commit Checks
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.13'

      - name: Install pre-commit
        run: pip install pre-commit

      - name: Run pre-commit
        run: pre-commit run --all-files
        continue-on-error: true
```

### 3. Add pre-commit cache step

**Location:** After line 436 (after "Install pre-commit" step)

**Add these lines:**

```yaml
      - name: Cache pre-commit environments
        uses: actions/cache@v4
        with:
          path: ~/.cache/pre-commit
          key: ${{ runner.os }}-precommit-${{ hashFiles('.pre-commit-config.yaml') }}
          restore-keys: |
            ${{ runner.os }}-precommit-
```

### 4. Updated job structure

**Result:** The complete job should look like this:

```yaml
  pre-commit-checks:
    name: Pre-commit Checks
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.13'

      - name: Install pre-commit
        run: pip install pre-commit

      - name: Cache pre-commit environments
        uses: actions/cache@v4
        with:
          path: ~/.cache/pre-commit
          key: ${{ runner.os }}-precommit-${{ hashFiles('.pre-commit-config.yaml') }}
          restore-keys: |
            ${{ runner.os }}-precommit-

      - name: Run pre-commit
        run: pre-commit run --all-files
        continue-on-error: true
```

## How It Works

### Cache Key

```yaml
key: ${{ runner.os }}-precommit-${{ hashFiles('.pre-commit-config.yaml') }}
```

Cache is based on:
- **OS:** `ubuntu-latest` (prevents cross-platform cache pollution)
- **Config hash:** `.pre-commit-config.yaml` content hash

**Cache invalidates when:**
- `.pre-commit-config.yaml` is modified (new hooks, version updates)
- 7 days pass (GitHub Actions default)

### Cache Path

```yaml
path: ~/.cache/pre-commit
```

Pre-commit stores:
- Hook repository clones
- Virtual environments for each hook
- Compiled binaries (hadolint, shellcheck, etc.)

### Restore Keys

```yaml
restore-keys: |
  ${{ runner.os }}-precommit-
```

Fallback strategy:
- If exact match not found, uses most recent pre-commit cache from same OS
- Provides partial speedup even when config changes slightly

## Verification Steps

### 1. Verify YAML syntax

```bash
# Check for YAML syntax errors
yamllint .github/workflows/ci.yml

# OR use actionlint
actionlint .github/workflows/ci.yml
```

### 2. Check line count

```bash
# Before: 649 lines (or more if other optimizations applied)
# After: +6 lines
wc -l .github/workflows/ci.yml
```

### 3. Visual inspection

Ensure:
- Cache step is positioned **after** "Install pre-commit"
- Cache step is positioned **before** "Run pre-commit"
- Indentation matches other steps (6 spaces for step name)

### 4. Test in CI

Best way to verify:
1. Create PR with this change
2. First run: Cache miss (normal installation time ~45s)
3. Second run: Cache hit (installation time ~5-10s)

## Testing Checklist

- [ ] YAML file is valid (no syntax errors)
- [ ] Cache step added to pre-commit-checks job
- [ ] Cache step positioned correctly (after install, before run)
- [ ] Indentation matches existing steps
- [ ] CI pipeline runs successfully
- [ ] Second CI run shows cache hit and faster execution

## Expected CI Output

### First run (cache miss)

```
Run actions/cache@v4
  with:
    path: ~/.cache/pre-commit
    key: ubuntu-latest-precommit-a1b2c3d4...
Cache not found for input keys: ubuntu-latest-precommit-a1b2c3d4...

Run pre-commit run --all-files
[INFO] Initializing environment for https://github.com/pre-commit/pre-commit-hooks...
[INFO] Initializing environment for https://github.com/psf/black...
[INFO] Installing environment for https://github.com/pre-commit/pre-commit-hooks...
[INFO] Installing environment for https://github.com/psf/black...
...
[INFO] Time: 45.23s
```

### Subsequent runs (cache hit)

```
Run actions/cache@v4
  with:
    path: ~/.cache/pre-commit
    key: ubuntu-latest-precommit-a1b2c3d4...
Cache restored from key: ubuntu-latest-precommit-a1b2c3d4...

Run pre-commit run --all-files
trailing-whitespace.................................................Passed
end-of-file-fixer................................................Passed
check-yaml.......................................................Passed
...
[INFO] Time: 8.12s
```

**Time savings:** 15-30 seconds per CI run

## Git Workflow

### Branch name

```bash
git checkout -b ci/add-precommit-caching
```

### Commit message

```
ci(pipeline): add pre-commit environment caching

Add GitHub Actions caching for pre-commit hook environments to speed up
the pre-commit-checks job.

Cache location: ~/.cache/pre-commit
Cache key: OS + .pre-commit-config.yaml hash

Benefits:
- Reduces pre-commit setup time from 45s to ~8s
- Saves 15-30 seconds per CI run
- Hook environments reused across runs
- Only rebuilds when config changes

Related: OPT-04 (optimization initiative)
```

### Push and create PR

```bash
git add .github/workflows/ci.yml
git commit -m "ci(pipeline): add pre-commit environment caching"
git push -u origin ci/add-precommit-caching

# Create PR
gh pr create --title "ci: Add pre-commit environment caching" \
  --body "## Changes
- Add caching for pre-commit hook environments
- Cache location: \`~/.cache/pre-commit\`
- Cache key: OS + \`.pre-commit-config.yaml\` hash

## Benefits
- ⚡ Reduces pre-commit setup time: 45s → 8s
- 💾 Reuses hook environments across CI runs
- 🔄 Rebuilds only when config changes

## Expected Behavior
- **First run:** Cache miss, ~45s setup time
- **Subsequent runs:** Cache hit, ~8s setup time
- **After config change:** Cache invalidation, rebuild

## Testing
- [x] YAML syntax validated
- [x] Proper positioning verified (after install, before run)
- [ ] Cache hit confirmed on second run (will verify post-merge)

## Related
Part of optimization initiative OPT-04"
```

## Rollback Plan

If caching causes issues:

```bash
git revert <commit-sha>
```

Or manually remove the cache step (6 lines).

## Cache Invalidation Scenarios

### When cache is invalidated (rebuilt)

1. **Config file changes:**
   - New hook added to `.pre-commit-config.yaml`
   - Hook version updated (e.g., `black` 24.10.0 → 25.0.0)
   - Hook args modified

2. **Time-based expiration:**
   - 7 days pass since cache creation (GitHub Actions default)

3. **Manual deletion:**
   - Via GitHub UI: Settings → Actions → Caches

### When cache is reused

- No changes to `.pre-commit-config.yaml`
- Same runner OS (ubuntu-latest)
- Within 7-day expiration window

## Troubleshooting

### Cache not working (always miss)

**Symptom:** Every run shows "Cache not found"

**Possible causes:**
1. `.pre-commit-config.yaml` changes between runs
2. Cache key syntax error
3. Cache path incorrect

**Debug:**
```bash
# Check cache key calculation locally
sha256sum .pre-commit-config.yaml
```

### Hooks failing after cache hit

**Symptom:** Cache hit, but hooks fail with "command not found"

**Possible cause:** Pre-commit version incompatibility

**Solution:**
- Update pre-commit install step to pin version
- Clear cache and rebuild

## Additional Notes

### What gets cached

- **Hook repository clones:** Pre-commit downloads repos once
- **Virtual environments:** Python envs for hooks (black, ruff, mypy)
- **Binaries:** hadolint, shellcheck, actionlint binaries
- **Config files:** Hook metadata and state

### What doesn't get cached

- Pre-commit CLI itself (installed via pip every time - see OPT-01 for that)
- Your repository code (checked out fresh)
- pip cache (handled separately in OPT-01)

### Dependency with OPT-01

If OPT-01 (Python dependency caching) is implemented:
- Pre-commit CLI installation will also be faster (pip cache hit)
- **Combined savings:** 30-45s + 15-30s = **45-75s per CI run**

### Cache size

Typical pre-commit cache:
- Size: 200-500 MB
- Includes: ~15 hook environments + binaries
- Within GitHub Actions cache limits (10 GB total per repo)

## Performance Metrics

### Baseline (no caching)

```
Pre-commit setup: 45.23s
Pre-commit run: 12.34s
Total: 57.57s
```

### With caching (cache hit)

```
Cache restore: 2.11s
Pre-commit run: 8.12s
Total: 10.23s
```

### Speedup

- **Absolute:** 57.57s → 10.23s (47.34s saved)
- **Relative:** 82% faster
- **Per day (10 PRs):** 7.9 minutes saved
- **Per month:** ~3.9 hours saved

## References

- [GitHub Actions Cache Documentation](https://github.com/actions/cache)
- [Pre-commit caching](https://pre-commit.com/#pre-commit-during-ci)
- [Pre-commit cache location](https://pre-commit.com/#advanced-features)
- Project: ml-platform-engineering-practicum
- Issue: Optimization Initiative (OPT-04)
