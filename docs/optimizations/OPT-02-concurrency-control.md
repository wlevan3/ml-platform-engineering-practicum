# OPT-02: Add GitHub Actions Concurrency Control

## Overview

**Priority:** TIER 1 - Critical Quick Win
**Estimated Time:** 2 minutes
**Impact:** Reduces CI costs, faster PR feedback, prevents resource waste
**ROI:** VERY HIGH

## Problem Statement

Currently, when multiple commits are pushed to the same PR branch:
- Each commit triggers a full CI run
- Old CI runs continue executing even after new commits are pushed
- Wastes GitHub Actions minutes
- Clutters the Actions UI with redundant runs
- Delays feedback (waiting for old runs to finish)

**Example scenario:**
1. Push commit A → CI starts (10 minutes)
2. Push commit B (2 minutes later) → New CI starts
3. Both CIs run in parallel, but CI for commit A is now obsolete

## Solution

Add concurrency control to automatically cancel in-progress runs when new commits are pushed to the same branch.

## Implementation Steps

### 1. Open the CI workflow file

```bash
# Open in your editor
vim .github/workflows/ci.yml
# OR
code .github/workflows/ci.yml
```

### 2. Add concurrency configuration

**Location:** After line 7 (after the `on:` trigger section, before `env:`)

**Add these lines:**

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

**Result:** Your workflow file should look like this:

```yaml
name: CI Pipeline

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  DOCKER_IMAGE_ARTIFACT: docker-image-${{ github.sha }}
```

### 3. Save the file

The change is complete! Only 3 lines added.

## How It Works

### Concurrency Group

```yaml
group: ${{ github.workflow }}-${{ github.ref }}
```

Creates a unique identifier combining:
- `github.workflow`: "CI Pipeline"
- `github.ref`: Branch reference (e.g., `refs/heads/feature/my-branch`)

**Examples:**
- PR branch `feature/auth`: `CI Pipeline-refs/heads/feature/auth`
- Main branch: `CI Pipeline-refs/heads/main`

Each branch gets its own concurrency group.

### Cancel In Progress

```yaml
cancel-in-progress: true
```

When a new run starts in the same concurrency group:
- Existing in-progress runs are automatically cancelled
- Completed runs are unaffected
- New run proceeds immediately

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
# Before: 649 lines (or 673 if OPT-01 applied)
# After: +3 lines
wc -l .github/workflows/ci.yml
```

### 3. Visual inspection

Ensure:
- Proper indentation (no spaces, top-level key)
- Positioned after `on:` and before `env:`
- No syntax errors

### 4. Test in PR (recommended)

Best way to verify:
1. Create PR with this change
2. Push first commit → CI starts
3. Push second commit immediately → First CI should be cancelled

## Testing Checklist

- [ ] YAML file is valid (no syntax errors)
- [ ] Concurrency block is at the correct level (same as `on:`, `env:`)
- [ ] Indentation is correct (0 spaces for `concurrency:`, 2 spaces for sub-keys)
- [ ] CI pipeline runs successfully
- [ ] Test cancellation: push 2 commits quickly, verify first run is cancelled

## Expected Behavior

### Before (without concurrency control)

```
PR: feature/auth
├── Commit A pushed → CI Run #1 (10 min) ✓ Completed
├── Commit B pushed → CI Run #2 (10 min) ✓ Completed
└── Commit C pushed → CI Run #3 (10 min) ✓ Completed
Total: 30 minutes of CI time used
```

### After (with concurrency control)

```
PR: feature/auth
├── Commit A pushed → CI Run #1 (2 min) ❌ Cancelled by #2
├── Commit B pushed → CI Run #2 (3 min) ❌ Cancelled by #3
└── Commit C pushed → CI Run #3 (10 min) ✓ Completed
Total: ~15 minutes of CI time used (50% reduction)
```

### GitHub Actions UI

When a run is cancelled, you'll see:
```
This workflow run was cancelled because a newer run started.
Cancelled by: github-actions[bot]
```

## Git Workflow

### Branch name

```bash
git checkout -b ci/add-concurrency-control
```

### Commit message

```
ci(pipeline): add concurrency control to cancel outdated runs

Add GitHub Actions concurrency control to automatically cancel
in-progress CI runs when new commits are pushed to the same branch.

Concurrency group: workflow name + branch ref
Behavior: Cancel in-progress runs when new run starts

Benefits:
- Reduces CI costs (fewer wasted minutes)
- Faster PR feedback (no waiting for old runs)
- Cleaner Actions UI (fewer redundant runs)
- Resource efficiency (runners freed immediately)

Related: OPT-02 (optimization initiative)
```

### Push and create PR

```bash
git add .github/workflows/ci.yml
git commit -m "ci(pipeline): add concurrency control to cancel outdated runs"
git push -u origin ci/add-concurrency-control

# Create PR
gh pr create --title "ci: Add concurrency control to cancel outdated runs" \
  --body "## Changes
- Add concurrency control to CI pipeline
- Automatically cancels old runs when new commits are pushed
- Concurrency group: \`\${{ github.workflow }}-\${{ github.ref }}\`

## Benefits
- 💰 Reduces CI costs (fewer wasted minutes)
- ⚡ Faster PR feedback (no waiting for outdated runs)
- 🧹 Cleaner Actions UI

## Testing
- [x] YAML syntax validated
- [x] Proper indentation verified
- [ ] Cancellation behavior verified (will test by pushing multiple commits)

## Related
Part of optimization initiative OPT-02"
```

## Testing the Cancellation Behavior

After PR is created:

```bash
# Make a trivial change
echo "# Test concurrency" >> README.md
git add README.md
git commit -m "test: trigger first CI run"
git push

# Wait 10 seconds, then make another change
sleep 10
echo "# Test concurrency 2" >> README.md
git add README.md
git commit -m "test: trigger second CI run (should cancel first)"
git push

# Check GitHub Actions UI
gh pr checks

# First run should show "Cancelled"
# Second run should show "In Progress" or "Completed"
```

## Rollback Plan

If concurrency causes issues:

```bash
git revert <commit-sha>
```

Or manually remove the 3 lines:
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## Edge Cases

### Main branch behavior

- Concurrency control applies to `main` branch too
- If multiple pushes to `main` happen rapidly, old runs are cancelled
- This is desired behavior (only final state matters)

### Concurrent PRs

- Each PR branch has its own concurrency group
- PR #123 and PR #124 run independently
- No interference between different branches

### Protected branches

- Works with branch protection rules
- Required status checks will use the latest run
- Cancelled runs don't count as failures

## Additional Notes

### Why this is safe

- Only cancels **in-progress** runs (not completed ones)
- Each branch is isolated (no cross-contamination)
- Latest code always gets tested
- Required checks still enforce quality gates

### Cost savings example

**Scenario:** 10 PRs per day, 3 commits per PR average

**Before:**
- 10 PRs × 3 commits × 10 min = 300 minutes/day

**After (assuming 2/3 commits are superseded):**
- 10 PRs × 1 full run × 10 min = 100 minutes/day
- 10 PRs × 2 partial runs × 2 min avg = 40 minutes/day
- **Total: 140 minutes/day (53% reduction)**

**Monthly savings:** ~3,200 minutes = 53 hours of CI time

## References

- [GitHub Actions Concurrency Documentation](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#concurrency)
- [Best practices for CI efficiency](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#example-using-concurrency-to-cancel-any-in-progress-job-or-run)
- Project: ml-platform-engineering-practicum
- Issue: Optimization Initiative (OPT-02)
