# ML Platform Optimization Initiative

## Overview

This directory contains **micro-optimization guides** for the ML Platform Engineering Practicum project. Each optimization is designed as a **standalone, atomic PR** that can be implemented independently.

**Goal:** Small, high-impact improvements with minimal effort and maximum ROI.

**Approach:** "Ultrathink and find the smallest unit of optimizations with the largest value."

## Quick Reference

| ID | Optimization | Priority | Time | Impact | ROI | Status |
|----|-------------|----------|------|--------|-----|--------|
| [OPT-01](#opt-01-python-dependency-caching) | Python Dependency Caching | **Tier 1** | 5 min | 2-4 min/run | ⭐⭐⭐⭐⭐ | 🔲 TODO |
| [OPT-02](#opt-02-concurrency-control) | CI Concurrency Control | **Tier 1** | 2 min | Cost ↓, Speed ↑ | ⭐⭐⭐⭐⭐ | 🔲 TODO |
| [OPT-03](#opt-03-structured-logging) | Structured Logging | **Tier 1** | 15 min | Prod-ready | ⭐⭐⭐⭐⭐ | 🔲 TODO |
| [OPT-04](#opt-04-pre-commit-caching) | Pre-commit Caching | Tier 2 | 3 min | 15-30s/run | ⭐⭐⭐⭐ | 🔲 TODO |
| [OPT-05](#opt-05-model-artifact-caching) | Model Artifact Caching | Tier 2 | 10 min | 15-30s/run | ⭐⭐⭐⭐ | 🔲 TODO |
| [OPT-06](#opt-06-api-timeout-configuration) | API Timeout Config | Tier 3 | 2 min | Resilience ↑ | ⭐⭐⭐ | 🔲 TODO |
| [OPT-07](#opt-07-cors-configuration) | CORS Configuration | Tier 3 | 5 min | Frontend ready | ⭐⭐ | 🔲 TODO |

**Legend:**
- 🔲 TODO: Not started
- 🟡 IN PROGRESS: PR open
- ✅ DONE: Merged to main

## Implementation Strategy

### Phase 1: Critical Quick Wins (< 30 minutes)

**Implement in order:**

1. **OPT-02** - Concurrency Control (2 min) → Immediate CI cost savings
2. **OPT-01** - Python Dependency Caching (5 min) → 2-4 min faster per run
3. **OPT-03** - Structured Logging (15 min) → Production-grade observability

**Total time:** ~22 minutes
**Total value:** 2-4 minutes saved per CI run + production-ready logging

**Combined PR Option:**
These three can be combined into a single PR if desired (still recommend separate PRs for easier review).

### Phase 2: High-Value Enhancements (< 1 hour)

**Implement in order:**

4. **OPT-04** - Pre-commit Caching (3 min) → 15-30s faster per run
5. **OPT-05** - Model Artifact Caching (10 min) → 15-30s faster per run

**Total additional time:** ~13 minutes
**Total additional value:** 30-60 seconds saved per CI run

**Cumulative savings:** 2.5-5 minutes per CI run (with Phase 1)

### Phase 3: Polish & Conditionals (optional)

**Implement as needed:**

6. **OPT-06** - API Timeout Configuration (2 min) → Production resilience
7. **OPT-07** - CORS Configuration (5 min) → Only if frontend planned

**When to implement:**
- OPT-06: Before production deployment
- OPT-07: Only if cross-origin requests needed

## Optimization Details

### OPT-01: Python Dependency Caching

**File:** [OPT-01-python-dependency-caching.md](./OPT-01-python-dependency-caching.md)

**What:** Add pip dependency caching to 4 Python jobs in CI pipeline

**Impact:** Saves 30-60 seconds per job × 4 jobs = **2-4 minutes per CI run**

**Effort:** 5 minutes (add 6 lines to 4 jobs)

**Files changed:** `.github/workflows/ci.yml`

**Branch:** `ci/add-python-dependency-caching`

**Quick start:**
```bash
# Add cache step after Python setup in these jobs:
# - python-lint
# - python-test
# - docker-build-scan
# - sbom-generation
```

---

### OPT-02: Concurrency Control

**File:** [OPT-02-concurrency-control.md](./OPT-02-concurrency-control.md)

**What:** Add GitHub Actions concurrency control to cancel outdated CI runs

**Impact:** Reduces CI costs, faster PR feedback, prevents resource waste

**Effort:** 2 minutes (add 3 lines)

**Files changed:** `.github/workflows/ci.yml`

**Branch:** `ci/add-concurrency-control`

**Quick start:**
```yaml
# Add after 'on:' trigger section:
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

---

### OPT-03: Structured Logging

**File:** [OPT-03-structured-logging.md](./OPT-03-structured-logging.md)

**What:** Replace `print()` statements with Python logging module

**Impact:** Production-grade observability, log levels, structured logs

**Effort:** 15 minutes

**Files changed:**
- `app/main.py` (replace 3 print statements)
- `train_model.py` (replace ~9 print statements)
- `app/logging_config.py` (new file)

**Branch:** `refactor/replace-print-with-logging`

**Quick start:**
```python
# Instead of:
print("Model loaded successfully")

# Use:
logger.info("Model loaded successfully")
```

---

### OPT-04: Pre-commit Caching

**File:** [OPT-04-precommit-caching.md](./OPT-04-precommit-caching.md)

**What:** Add caching for pre-commit hook environments

**Impact:** Saves 15-30 seconds per CI run (pre-commit setup time)

**Effort:** 3 minutes (add 6 lines to 1 job)

**Files changed:** `.github/workflows/ci.yml`

**Branch:** `ci/add-precommit-caching`

**Quick start:**
```bash
# Add cache step after "Install pre-commit" in pre-commit-checks job
```

---

### OPT-05: Model Artifact Caching

**File:** [OPT-05-model-artifact-caching.md](./OPT-05-model-artifact-caching.md)

**What:** Train model once, share via artifacts instead of training in each job

**Impact:** Saves 5-10 seconds × 3 jobs = **15-30 seconds per CI run**

**Effort:** 10 minutes (add new job, update 3 jobs)

**Files changed:** `.github/workflows/ci.yml`

**Branch:** `ci/add-model-artifact-caching`

**Quick start:**
```bash
# 1. Create model-train job with caching
# 2. Update python-test to download artifact
# 3. Update docker-build-scan to download artifact
# 4. Update sbom-generation to download artifact
```

---

### OPT-06: API Timeout Configuration

**File:** [OPT-06-api-timeout-configuration.md](./OPT-06-api-timeout-configuration.md)

**What:** Add explicit timeout configuration to uvicorn command

**Impact:** Production resilience, prevents hung connections

**Effort:** 2 minutes (modify 1 line)

**Files changed:** `Dockerfile`

**Branch:** `infra/add-api-timeout-configuration`

**Quick start:**
```dockerfile
# Add to uvicorn command:
--timeout-keep-alive 30
```

---

### OPT-07: CORS Configuration

**File:** [OPT-07-cors-configuration.md](./OPT-07-cors-configuration.md)

**What:** Add CORS middleware for browser-based API calls

**Impact:** Enables frontend integration (conditional - only if needed)

**Effort:** 5 minutes

**Files changed:**
- `app/main.py` (add CORS middleware)
- `app/config.py` (optional: environment-based config)

**Branch:** `feat/add-cors-configuration`

**Quick start:**
```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Note:** Only implement if cross-origin requests are needed.

---

## Combined Impact Analysis

### Cumulative CI Time Savings

**Baseline:** ~10 minutes per CI run

**After Phase 1 (OPT-01, OPT-02, OPT-03):**
- First run: 7-8 minutes (20-30% faster)
- Subsequent runs: 4-6 minutes (40-60% faster with caching)
- Cost savings: 50%+ on repeated runs

**After Phase 2 (+ OPT-04, OPT-05):**
- First run: 6-7 minutes (30-40% faster)
- Subsequent runs: 3-4 minutes (60-70% faster with caching)
- Cost savings: 60-70% on repeated runs

### Monthly Savings (10 PRs/day)

**Assumptions:**
- 10 pull requests per day
- 3 commits per PR (average)
- 30 CI runs per day

**Before optimizations:**
- 30 runs × 10 min = 300 minutes/day = 9,000 minutes/month

**After Phase 1:**
- 30 runs × 6 min (avg) = 180 minutes/day = 5,400 minutes/month
- **Savings: 3,600 minutes/month = 60 hours/month**

**After Phase 2:**
- 30 runs × 4 min (avg) = 120 minutes/day = 3,600 minutes/month
- **Savings: 5,400 minutes/month = 90 hours/month**

### Developer Experience

**Before:**
- Wait 10 minutes for CI feedback
- Multiple PRs queue up
- Context switching

**After:**
- Wait 4-6 minutes for CI feedback (40-60% faster)
- Old runs cancelled automatically
- Faster iteration cycle
- Better flow state

## Implementation Workflow

### For Each Optimization

1. **Read the guide:**
   ```bash
   # Open the specific optimization guide
   cat docs/optimizations/OPT-XX-optimization-name.md
   ```

2. **Create branch:**
   ```bash
   git checkout main
   git pull origin main
   git checkout -b <branch-name-from-guide>
   ```

3. **Implement changes:**
   - Follow step-by-step instructions in guide
   - Use provided code snippets
   - Verify syntax/formatting

4. **Test locally:**
   ```bash
   # Run linting
   black .
   ruff check .

   # Run tests
   pytest

   # Validate YAML (if CI changes)
   yamllint .github/workflows/ci.yml
   actionlint .github/workflows/ci.yml
   ```

5. **Commit and push:**
   ```bash
   git add <files>
   git commit -m "<commit-message-from-guide>"
   git push -u origin <branch-name>
   ```

6. **Create PR:**
   ```bash
   gh pr create --title "<title-from-guide>" \
     --body "<body-from-guide>"
   ```

7. **Monitor CI:**
   ```bash
   gh pr checks --watch
   ```

8. **Address feedback:**
   - Respond to review comments
   - Make requested changes
   - Push updates

9. **Merge:**
   ```bash
   # After approval
   gh pr merge --squash
   ```

10. **Update status:**
    - Mark optimization as ✅ DONE in this README
    - Delete feature branch

## Testing Strategy

### Pre-merge Testing

Each optimization guide includes:
- ✅ Syntax validation commands
- ✅ Local testing steps
- ✅ Expected behavior verification
- ✅ Rollback instructions

### Post-merge Verification

**After each optimization:**

1. **Verify CI behavior:**
   - Create trivial PR (update README)
   - Observe CI run
   - Confirm expected speedup/behavior
   - Close PR

2. **Monitor for 24 hours:**
   - Watch for issues in Slack/email
   - Check CI success rate
   - Verify no regressions

3. **Rollback if needed:**
   ```bash
   git revert <commit-sha>
   git push origin main
   ```

## Rollback Procedures

### Quick Rollback

**If optimization causes issues:**

```bash
# Revert the commit
git revert <commit-sha>
git push origin main

# OR revert via GitHub UI:
# 1. Go to commit in GitHub
# 2. Click "..." menu
# 3. Select "Revert"
# 4. Create PR with revert
# 5. Merge immediately
```

### Detailed Rollback

Each optimization guide includes specific rollback instructions in the "Rollback Plan" section.

## Troubleshooting

### Common Issues

**Issue: Cache not working**
- **Symptoms:** "Cache not found" on every run
- **Cause:** Cache key calculation issue
- **Solution:** Check file paths in `hashFiles()` function

**Issue: Artifact not found**
- **Symptoms:** "Artifact not found: trained-model"
- **Cause:** Job dependencies not configured correctly
- **Solution:** Add `needs: [model-train]` to dependent jobs

**Issue: YAML syntax error**
- **Symptoms:** CI fails with "Invalid workflow file"
- **Cause:** Indentation or syntax error
- **Solution:** Run `yamllint` and `actionlint` locally

**Issue: Tests failing after optimization**
- **Symptoms:** Tests pass locally, fail in CI
- **Cause:** Missing dependencies or configuration
- **Solution:** Check CI logs, verify all dependencies installed

### Getting Help

1. **Check the specific optimization guide** - Each has a troubleshooting section
2. **Review CI logs** - GitHub Actions provides detailed output
3. **Search existing issues** - Someone may have encountered similar issue
4. **Create new issue** - Include logs, error messages, and steps to reproduce

## Dependencies Between Optimizations

### Independent (can implement in any order)

- OPT-01 (Python caching)
- OPT-02 (Concurrency control)
- OPT-03 (Structured logging)
- OPT-04 (Pre-commit caching)
- OPT-06 (API timeouts)
- OPT-07 (CORS)

### Dependent

- **OPT-05** (Model artifacts) → Benefits from **OPT-01** (Python caching)
  - Can implement independently, but works better together

### Recommended Order

**For maximum impact:**
1. OPT-02 (quick win, immediate cost savings)
2. OPT-01 (foundational, benefits other optimizations)
3. OPT-03 (important for production)
4. OPT-04 (quick additional win)
5. OPT-05 (builds on OPT-01)
6. OPT-06 (production hardening)
7. OPT-07 (conditional, only if needed)

## Metrics & Monitoring

### Key Metrics to Track

**After implementing optimizations:**

1. **CI Duration:**
   - Average time per CI run
   - P50, P95, P99 percentiles
   - Trend over time

2. **CI Cost:**
   - GitHub Actions minutes consumed
   - Monthly cost
   - Cost per PR

3. **Cache Hit Rate:**
   - Pip cache hit rate
   - Pre-commit cache hit rate
   - Model cache hit rate

4. **Developer Experience:**
   - Time to first CI feedback
   - PR merge velocity
   - Context switching frequency

### GitHub Actions Insights

**Access metrics:**
1. Go to repository → Insights → Actions
2. View workflow runs
3. Filter by workflow, branch, status
4. Export data for analysis

### Custom Tracking

**Create a tracking issue:**

```markdown
# Optimization Impact Tracking

## Baseline (before optimizations)
- Average CI duration: 10 minutes
- Monthly CI minutes: 9,000
- Cache hit rate: N/A (no caching)

## After OPT-01, OPT-02, OPT-03 (Phase 1)
- Average CI duration: ? minutes
- Monthly CI minutes: ?
- Cache hit rate: ?%
- Savings: ?%

## After OPT-04, OPT-05 (Phase 2)
- Average CI duration: ? minutes
- Monthly CI minutes: ?
- Cache hit rate: ?%
- Savings: ?%
```

## Lessons Learned

**As you implement each optimization, document:**

- What worked well
- What didn't work as expected
- Unexpected benefits
- Unexpected challenges
- Recommendations for future optimizations

**Add to this section after each PR.**

## Future Optimizations

**Ideas for future micro-PRs:**

1. **Docker layer caching** - Cache Docker layers in CI
2. **Parallel test execution** - Run pytest with `-n auto`
3. **Conditional job execution** - Skip jobs when files unchanged
4. **Matrix strategy** - Test multiple Python versions efficiently
5. **Build matrix parallelization** - Parallelize Docker builds
6. **Terraform plan caching** - Cache Terraform state
7. **Dependency updates automation** - Dependabot configuration
8. **Code coverage optimization** - Only run on changed files

**Want to contribute?** Create a new guide following the template in existing optimizations.

## Contributing

### Creating New Optimization Guides

**Template structure:**

1. **Overview** - Priority, time, impact, ROI
2. **Problem Statement** - What's the issue?
3. **Solution** - What's the fix?
4. **Implementation Steps** - Detailed walkthrough
5. **Verification Steps** - How to test
6. **Testing Checklist** - Pre-merge verification
7. **Git Workflow** - Branch, commit, PR instructions
8. **Rollback Plan** - How to undo
9. **Additional Notes** - Context, references, tips

**Naming convention:**
- File: `OPT-XX-optimization-name.md`
- Branch: `<type>/optimization-name`
- Commit: `<type>(<scope>): brief description`

### Review Process

1. Create optimization guide
2. Submit PR for review (guide only)
3. After guide approved, implement optimization
4. Submit separate PR for implementation
5. Link PRs (guide → implementation)

## License

These optimization guides are part of the ml-platform-engineering-practicum project.
See LICENSE file in repository root.

## Acknowledgments

**Methodology:** "Ultrathink and find the smallest unit of optimizations with the largest value"

**Inspiration:** Lean principles, kaizen (continuous improvement), atomic PRs

## Questions?

- **Project docs:** See `/docs` directory
- **GitHub Issues:** For bugs or suggestions
- **Pull Requests:** For implementations

---

**Last updated:** 2025-01-15

**Status:** All optimizations documented, ready for implementation

**Next step:** Implement OPT-02 (Concurrency Control) for immediate impact
