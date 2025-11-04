# OPT-05: Add Model Training Artifact Caching

## Overview

**Priority:** TIER 2 - High-Value Optimization
**Estimated Time:** 10 minutes
**Impact:** Saves 5-10 seconds × 3 jobs = 15-30 seconds per CI run
**ROI:** HIGH

## Problem Statement

Currently, three CI jobs train the model independently:
- `python-test` (line 264): Trains model for testing
- `docker-build-scan` (line 463): Trains model for Docker image
- `sbom-generation` (line 533): Trains model for SBOM generation

**Issues:**
- Model training is deterministic (same inputs → same outputs)
- Redundant computation wastes CPU cycles
- Takes 5-10 seconds per job (15-30s total)
- Identical model files generated three times

## Solution

Create a dedicated model-training job that caches the trained model as an artifact. Downstream jobs download the artifact instead of training.

## Implementation Steps

### 1. Open the CI workflow file

```bash
# Open in your editor
vim .github/workflows/ci.yml
# OR
code .github/workflows/ci.yml
```

### 2. Create new model-train job

**Location:** After the `python-lint` job (around line 244)

**Add new job:**

```yaml
  model-train:
    name: Train ML Model
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.13'

      - name: Cache pip dependencies
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-

      - name: Cache trained model
        id: cache-model
        uses: actions/cache@v4
        with:
          path: models/
          key: model-${{ hashFiles('train_model.py', 'requirements.txt', 'app/security.py') }}

      - name: Install training dependencies
        if: steps.cache-model.outputs.cache-hit != 'true'
        run: |
          python -m pip install --upgrade pip
          pip install scikit-learn skops numpy

      - name: Train model
        if: steps.cache-model.outputs.cache-hit != 'true'
        run: python train_model.py

      - name: Upload model artifact
        uses: actions/upload-artifact@v4
        with:
          name: trained-model
          path: models/
          retention-days: 1
```

### 3. Update python-test job

**Location:** Line 246 (now shifted due to new job)

**Find the "Train model for tests" step (around line 264):**

```yaml
      - name: Train model for tests
        run: python train_model.py
```

**Replace with:**

```yaml
      - name: Download trained model
        uses: actions/download-artifact@v4
        with:
          name: trained-model
          path: models/
```

**Update job dependencies (line 247):**

**Before:**
```yaml
  python-test:
    name: Python Tests with Coverage
    runs-on: ubuntu-latest
```

**After:**
```yaml
  python-test:
    name: Python Tests with Coverage
    runs-on: ubuntu-latest
    needs: [model-train]
```

### 4. Update docker-build-scan job

**Location:** Around line 442

**Find the "Install dependencies and train model" step (around line 459):**

```yaml
      - name: Install dependencies and train model
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          python train_model.py
```

**Replace with:**

```yaml
      - name: Download trained model
        uses: actions/download-artifact@v4
        with:
          name: trained-model
          path: models/
```

**Update job dependencies (around line 442):**

**Before:**
```yaml
  docker-build-scan:
    name: Docker Build & Security Scan
    runs-on: ubuntu-latest
    needs: [python-test]
```

**After:**
```yaml
  docker-build-scan:
    name: Docker Build & Security Scan
    runs-on: ubuntu-latest
    needs: [python-test, model-train]
```

### 5. Update sbom-generation job

**Location:** Around line 512

**Find the "Install dependencies and train model" step (around line 529):**

```yaml
      - name: Install dependencies and train model
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          python train_model.py
```

**Replace with:**

```yaml
      - name: Download trained model
        uses: actions/download-artifact@v4
        with:
          name: trained-model
          path: models/
```

**Note:** `sbom-generation` already has `needs: [docker-build-scan]`, so it implicitly depends on `model-train`. No change needed to dependencies.

## How It Works

### Model Training Job

```yaml
model-train:
  steps:
    - Cache trained model (cache key based on train_model.py + requirements.txt + app/security.py)
    - If cache miss → Train model
    - Upload as artifact for other jobs
```

### Cache Key

```yaml
key: model-${{ hashFiles('train_model.py', 'requirements.txt', 'app/security.py') }}
```

Cache invalidates when:
- `train_model.py` changes (training logic)
- `requirements.txt` changes (ML dependencies)
- `app/security.py` changes (hashing logic)

### Downstream Jobs

```yaml
python-test:
  needs: [model-train]
  steps:
    - Download trained-model artifact
    - Run tests
```

**Benefits:**
- Model trained once
- Downloaded by all jobs that need it
- Cache persists across CI runs (7 days)

## Verification Steps

### 1. Verify YAML syntax

```bash
# Check for YAML syntax errors
yamllint .github/workflows/ci.yml

# OR use actionlint
actionlint .github/workflows/ci.yml
```

### 2. Check job dependencies

```bash
# Verify dependency graph
grep -A 3 "needs:" .github/workflows/ci.yml

# Expected:
# python-test:
#   needs: [model-train]
# docker-build-scan:
#   needs: [python-test, model-train]
# sbom-generation:
#   needs: [docker-build-scan]  # (implicitly depends on model-train)
```

### 3. Visual inspection

Ensure:
- `model-train` job is positioned before jobs that need it
- All artifact names match: `trained-model`
- All artifact paths match: `models/`
- Dependencies are correct

### 4. Test in CI

1. Create PR with these changes
2. First run: Model trained once, cached
3. Verify all jobs pass
4. Check CI timeline: model-train runs first, others download artifact

## Testing Checklist

- [ ] YAML file is valid (no syntax errors)
- [ ] New `model-train` job created
- [ ] `python-test` updated to download artifact
- [ ] `docker-build-scan` updated to download artifact
- [ ] `sbom-generation` updated to download artifact
- [ ] Job dependencies (`needs:`) configured correctly
- [ ] All artifact names are consistent (`trained-model`)
- [ ] All artifact paths are consistent (`models/`)
- [ ] CI pipeline runs successfully
- [ ] All tests pass
- [ ] CI timeline shows model trained once

## Expected CI Behavior

### Job Execution Order

```
Parallel:
├── lint-and-validate
├── terraform-validate
├── kubernetes-validate
├── python-lint
└── model-train ← NEW JOB (trains model once)

Sequential:
├── python-test ← downloads model artifact
├── docker-build-scan ← downloads model artifact
└── sbom-generation ← downloads model artifact

Parallel (security):
├── security-scan
├── gitleaks-scan
├── semgrep-scan
└── pre-commit-checks
```

### First Run (cache miss)

```
model-train:
  Cache not found for key: model-abc123...
  Training model... (8.45s)
  Model saved to: models/iris_classifier.skops
  Uploading artifact: trained-model (2.1s)

python-test:
  Downloading artifact: trained-model (0.8s)
  Running tests... ✓

docker-build-scan:
  Downloading artifact: trained-model (0.8s)
  Building Docker image... ✓
```

### Subsequent Runs (cache hit)

```
model-train:
  Cache restored from key: model-abc123...
  Model already trained, skipping training step
  Uploading artifact: trained-model (2.1s)

python-test:
  Downloading artifact: trained-model (0.8s)
  Running tests... ✓

docker-build-scan:
  Downloading artifact: trained-model (0.8s)
  Building Docker image... ✓
```

**Time savings:**
- First run: 8.45s + 8.45s + 8.45s = 25.35s → 8.45s (16.9s saved)
- Subsequent runs: 0s (cache hit) + 0s + 0s = 0s → 0s (all training skipped)

## Git Workflow

### Branch name

```bash
git checkout -b ci/add-model-artifact-caching
```

### Commit message

```
ci(pipeline): add model training artifact caching

Create dedicated model-train job to train model once and share across
jobs. Eliminates redundant model training in python-test, docker-build-scan,
and sbom-generation jobs.

Changes:
- Add model-train job with caching based on train_model.py hash
- Upload trained model as artifact (retention: 1 day)
- Update python-test to download model artifact
- Update docker-build-scan to download model artifact
- Update sbom-generation to download model artifact
- Configure job dependencies (needs: [model-train])

Cache key: train_model.py + requirements.txt + app/security.py

Benefits:
- Model trained once per CI run (not 3 times)
- Saves 15-30 seconds per CI run
- Reduces CPU cycles (greener CI)
- Cache persists 7 days (subsequent runs skip training entirely)
- Consistent model across all jobs

Related: OPT-05 (optimization initiative)
```

### Push and create PR

```bash
git add .github/workflows/ci.yml
git commit -m "ci(pipeline): add model training artifact caching"
git push -u origin ci/add-model-artifact-caching

# Create PR
gh pr create --title "ci: Add model training artifact caching" \
  --body "## Changes
- ✅ Create \`model-train\` job to train model once
- ✅ Cache trained model based on \`train_model.py\` hash
- ✅ Upload model as artifact (\`trained-model\`, 1-day retention)
- ✅ Update \`python-test\` to download artifact
- ✅ Update \`docker-build-scan\` to download artifact
- ✅ Update \`sbom-generation\` to download artifact
- ✅ Configure job dependencies (\`needs: [model-train]\`)

## Problem
Currently, 3 jobs train the model independently:
- \`python-test\`: trains model (8s)
- \`docker-build-scan\`: trains model (8s)
- \`sbom-generation\`: trains model (8s)
- **Total: 24 seconds wasted**

## Solution
Train model once, share across jobs via artifacts + caching.

## Benefits
- ⚡ Saves 15-30 seconds per CI run
- 🌱 Reduces CPU cycles (greener CI)
- 💾 Cache persists 7 days (skip training on subsequent runs)
- 🎯 Consistent model across all jobs

## Job Execution Flow
\`\`\`
model-train (trains once)
    ↓
    ├→ python-test (downloads artifact)
    └→ docker-build-scan (downloads artifact)
           └→ sbom-generation (downloads artifact)
\`\`\`

## Cache Invalidation
Cache rebuilds when:
- \`train_model.py\` changes (training logic)
- \`requirements.txt\` changes (ML dependencies)
- \`app/security.py\` changes (hashing logic)
- 7 days pass (GitHub Actions expiration)

## Testing
- [x] YAML syntax validated
- [x] Job dependencies configured correctly
- [x] Artifact names/paths consistent
- [ ] CI passes with model trained once (will verify)
- [ ] All tests pass (will verify)

## Related
Part of optimization initiative OPT-05"
```

## Rollback Plan

If model artifact sharing causes issues:

```bash
git revert <commit-sha>
```

Or manually:
1. Remove `model-train` job
2. Revert download steps to training steps
3. Remove `needs: [model-train]` dependencies

## Troubleshooting

### Artifact not found

**Symptom:** Download step fails with "Artifact not found: trained-model"

**Possible causes:**
1. `model-train` job failed
2. Artifact name mismatch
3. Job ran before `model-train` completed

**Solution:**
- Check `model-train` job logs
- Verify `needs: [model-train]` dependency exists
- Ensure artifact name matches exactly

### Model file permissions

**Symptom:** Tests fail with "Permission denied: models/iris_classifier.skops"

**Possible cause:** Artifact extraction permissions

**Solution:**
```yaml
- name: Download trained model
  uses: actions/download-artifact@v4
  with:
    name: trained-model
    path: models/

- name: Fix permissions
  run: chmod -R 755 models/
```

### Cache not invalidating

**Symptom:** Old model used after train_model.py changes

**Possible cause:** Cache key doesn't include right files

**Solution:** Verify cache key includes all relevant files:
```yaml
key: model-${{ hashFiles('train_model.py', 'requirements.txt', 'app/security.py') }}
```

## Additional Notes

### Cache vs Artifact

**Cache:**
- Persists 7 days
- Shared across runs
- Faster restore (no download)
- Used for: Trained model files

**Artifact:**
- Persists 1 day (configurable)
- Shared within a single workflow run
- Used for: Passing model between jobs

**Why both?**
- Cache: Skip training on subsequent CI runs
- Artifact: Share model across jobs in current run

### Artifact Retention

```yaml
retention-days: 1
```

Short retention (1 day) because:
- Only needed within workflow run
- Models are cached separately (7 days)
- Reduces storage costs

### Cache Key Strategy

**Included files:**
- `train_model.py`: Training logic changes
- `requirements.txt`: ML library versions (scikit-learn, numpy)
- `app/security.py`: Hash calculation logic

**Not included:**
- `app/main.py`: API logic (doesn't affect training)
- `tests/`: Test code (doesn't affect model)
- `.github/workflows/ci.yml`: CI config (doesn't affect model)

### Performance Comparison

**Before (no optimization):**
```
python-test:        model training 8s
docker-build-scan:  model training 8s
sbom-generation:    model training 8s
Total training time: 24s
```

**After (with optimization, cache miss):**
```
model-train:        model training 8s (cached)
python-test:        download 0.8s
docker-build-scan:  download 0.8s
sbom-generation:    download 0.8s
Total training time: 10.4s (13.6s saved, 57% faster)
```

**After (with optimization, cache hit):**
```
model-train:        cache restore 1s (no training!)
python-test:        download 0.8s
docker-build-scan:  download 0.8s
sbom-generation:    download 0.8s
Total training time: 3.4s (20.6s saved, 86% faster)
```

## References

- [GitHub Actions Artifacts](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts)
- [GitHub Actions Cache](https://github.com/actions/cache)
- [Job dependencies (needs)](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idneeds)
- Project: ml-platform-engineering-practicum
- Issue: Optimization Initiative (OPT-05)
