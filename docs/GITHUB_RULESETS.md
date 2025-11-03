# GitHub Branch Protection Rules

This document describes the GitHub rulesets configured for the `main` branch to enforce security checks and code
quality standards before merging.

## Overview

The `main-protection` ruleset enforces automated security and quality checks on all pull requests targeting the
`main` branch. This ensures that only tested, reviewed, and secure code is merged into production.

**Ruleset ID**: `9342319`
**Target**: `refs/heads/main`
**Enforcement**: Active

## Prerequisites

The branch protection rules rely on existing CI/CD workflows that are already configured in this repository:

- **`.github/workflows/ci.yml`**: Main CI pipeline containing all required status checks (Python tests, security scans,
  Docker builds, linting)
- **`.github/workflows/codeql.yml`**: CodeQL security analysis workflow

These workflow files are version-controlled and maintained as part of the repository. If you're setting up branch
protection in a new repository, ensure these workflows exist and are properly configured before enabling the rulesets.

## Configured Protections

### 1. Branch Protection Rules

#### Deletion Protection

- **Rule Type**: `deletion`
- **Purpose**: Prevents accidental deletion of the `main` branch
- **Rationale**: The `main` branch is the production baseline and should never be deleted

#### Non-Fast-Forward Protection

- **Rule Type**: `non_fast_forward`
- **Purpose**: Blocks force pushes to `main`
- **Rationale**: Maintains git history integrity and prevents accidental overwrites

### 2. Pull Request Requirements

#### Required Approvals

- **Required Approving Reviews**: 1
- **Dismiss Stale Reviews**: Enabled (reviews dismissed when new commits pushed)
- **Require Code Owner Review**: Disabled (solo learning project)
- **Require Last Push Approval**: Disabled
- **Required Review Thread Resolution**: Enabled

**Rationale**:

- For this solo learning project, at least 1 approval is required (self-approval allowed)
- Stale reviews are dismissed to ensure reviewers see the latest changes
- Thread resolution ensures all conversations are addressed before merge

#### Merge Methods

- **Allowed Methods**: `merge`, `squash`, `rebase`
- **Recommended**: Squash merge (keeps history clean)

### 3. Required Status Checks

All PRs must pass the following CI checks before merging:

#### Security Checks

1. **CodeQL Analysis**
   - **Check Name**: `Analyze (python)`
   - **Integration ID**: `15368` (GitHub CodeQL)
   - **Purpose**: Static analysis security testing (SAST) for Python code
   - **Workflow**: `.github/workflows/codeql.yml`
   - **Severity**: Detects security vulnerabilities, CWEs, and unsafe patterns

2. **Security Scanning (Trivy Filesystem)**
   - **Check Name**: `Security Scanning`
   - **Purpose**: Scans repository files for vulnerabilities
   - **Workflow**: `.github/workflows/ci.yml` (job: `security-scan`)
   - **Severity**: HIGH and CRITICAL vulnerabilities reported to GitHub Security

3. **Secret Scanning (Gitleaks)**
   - **Check Name**: `Secret Scanning (Gitleaks)`
   - **Purpose**: Detects accidentally committed secrets, API keys, credentials
   - **Workflow**: `.github/workflows/ci.yml` (job: `gitleaks-scan`)
   - **Severity**: Blocks merge if secrets found

4. **Semgrep Security Analysis**
   - **Check Name**: `Semgrep Security Analysis`
   - **Purpose**: Comprehensive SAST with OWASP Top 10 and security audit rules
   - **Workflow**: `.github/workflows/ci.yml` (job: `semgrep-scan`)
   - **Rulesets**: `p/security-audit`, `p/python`, `p/owasp-top-ten`

5. **Docker Build & Security Scan**
   - **Check Name**: `Docker Build & Security Scan`
   - **Purpose**: Scans Docker image for OS and dependency vulnerabilities
   - **Workflow**: `.github/workflows/ci.yml` (job: `docker-build-scan`)
   - **Severity**: HIGH and CRITICAL vulnerabilities reported (exit-code disabled for Trivy v0.65.0 false positives)

#### Quality Checks

1. **Python Tests with Coverage**
   - **Check Name**: `Python Tests with Coverage`
   - **Purpose**: Runs pytest suite with coverage reporting
   - **Workflow**: `.github/workflows/ci.yml` (job: `python-test`)
   - **Coverage Target**: 80%+ (configured in `pytest.ini`)

### 4. Code Scanning Tools (Advanced Security)

GitHub Advanced Security integration with automated alerts:

#### CodeQL

- **Security Alerts Threshold**: `high_or_higher`
- **Alerts Threshold**: `errors`
- **Query Suite**: `security-extended`
- **Purpose**: Comprehensive vulnerability detection for Python

#### Semgrep

- **Security Alerts Threshold**: `high_or_higher`
- **Alerts Threshold**: `errors`
- **Purpose**: SAST with OWASP and security audit rules

#### Trivy

- **Security Alerts Threshold**: `high_or_higher`
- **Alerts Threshold**: `errors`
- **Purpose**: Container and filesystem vulnerability scanning

### 5. Copilot Code Review

- **Review on Push**: Enabled
- **Review Draft Pull Requests**: Enabled
- **Purpose**: Automated AI-powered code review for quality and best practices

## Required Status Checks Behavior

### Strict Status Checks Policy

- **Enabled**: `strict_required_status_checks_policy: true`
- **Behavior**: Branch must be up-to-date with `main` before merging
- **Rationale**: Ensures all required checks run against the latest code

### Do Not Enforce on Create

- **Disabled**: `do_not_enforce_on_create: false`
- **Behavior**: Status checks enforced even when creating the branch
- **Rationale**: Consistent enforcement for all scenarios

## Status Checks Not Required (Conditional Jobs)

The following CI jobs run conditionally and are **not** enforced as required checks:

- **Lint and Validate** (markdown linting) - Always runs but allows failures
- **Terraform Validation** - Only runs if `terraform/` directory exists
- **Kubernetes Validation** - Only runs if `k8s/` directory exists
- **Python Linting** - Runs but not blocking (Black/Ruff)
- **Pre-commit Checks** - Runs but not blocking

**Rationale**: These are quality checks that provide valuable feedback but shouldn't block merges for a learning
project. Infrastructure jobs (Terraform/K8s) will be added as required checks when those directories exist.

## Testing the Protections

### Test 1: Verify Required Status Checks

1. Create a test branch:

   ```bash
   git checkout -b test/verify-protection
   ```

2. Make a trivial change (e.g., update README.md)

3. Push and create a PR:

   ```bash
   git add README.md
   git commit -m "test: verify branch protection rules"
   git push -u origin test/verify-protection
   gh pr create --title "Test: Verify Branch Protection" --body "Testing required status checks"
   ```

4. **Expected Behavior**:
   - PR shows "Merging is blocked" until all 6 required checks pass
   - PR requires 1 approval before merge button is enabled
   - All conversations must be resolved

### Test 2: Verify Force Push Protection

1. Try to force push to `main`:

   ```bash
   git push --force origin main
   ```

2. **Expected Behavior**:

   ```text
   remote: error: GH013: Repository rule violations found for refs/heads/main.
   remote:
   remote: - RULE: main-protection
   remote:   Commit: <sha>
   remote:   Non fast forward updates are not allowed
   ```

### Test 3: Verify Branch Deletion Protection

1. Try to delete `main` branch:

   ```bash
   git push origin --delete main
   ```

2. **Expected Behavior**:

   ```text
   remote: error: GH013: Repository rule violations found for refs/heads/main.
   remote:
   remote: - RULE: main-protection
   remote:   Deletions are not allowed
   ```

### Test 4: Test Failing Security Check

1. Create a Dockerfile with intentional security issues:

   ```dockerfile
   FROM ubuntu:20.04  # Intentionally outdated/EOL version to trigger security checks
   RUN apt-get update && apt-get install -y curl
   USER root  # Running as root
   ```

2. Commit and push:

   ```bash
   git checkout -b test/failing-security
   git add Dockerfile
   git commit -m "test: add insecure Dockerfile"
   git push -u origin test/failing-security
   gh pr create --title "Test: Failing Security Check" --body "Intentionally insecure Dockerfile"
   ```

3. **Expected Behavior**:
   - Trivy scan detects HIGH/CRITICAL vulnerabilities in ubuntu:20.04
   - GitHub Security tab shows alerts
   - PR cannot be merged until issues resolved

4. **Resolution**:
   - Update to secure base image: `FROM ubuntu:24.04`
   - Add non-root user
   - Re-push to update PR

## Future Enhancements

### Signed Commits (Optional)

**Status**: Not currently enabled
**Consideration**: Adds setup complexity for learning project

**To enable**:

1. Setup GPG key:

   ```bash
   gpg --full-generate-key
   gpg --list-secret-keys --keyid-format LONG
   gpg --armor --export <KEY_ID>
   ```

2. Add GPG key to GitHub account (Settings → SSH and GPG keys)

3. Configure git:

   ```bash
   git config --global user.signingkey <KEY_ID>
   git config --global commit.gpgsign true
   ```

4. Update ruleset to require signed commits:

   ```json
   {
     "type": "required_signatures"
   }
   ```

**Trade-off**: Better security vs. added complexity for solo learning project

### Additional Status Checks (Phase 2+)

When Terraform and Kubernetes infrastructure is added:

- **tfsec** - Terraform security scanning
- **Checkov** - IaC security and compliance
- **Terraform Validate** - Syntax and configuration validation
- **Kubernetes Validation** - Manifest validation (kubeval, kube-linter)

## Viewing Ruleset Configuration

### Via GitHub UI

Navigate to: **Settings** → **Rules** → **Rulesets** → `main-protection`

### Via GitHub CLI

```bash
# View all rulesets
gh api repos/:owner/:repo/rulesets --jq '.[] | {id, name, target, enforcement}'

# View specific ruleset details
gh api repos/:owner/:repo/rulesets/9342319 --jq '.'
```

### Via API

```bash
curl -H "Authorization: token $GITHUB_TOKEN" \
     -H "Accept: application/vnd.github+json" \
     https://api.github.com/repos/wlevan3/ml-platform-engineering-practicum/rulesets/9342319
```

## Updating the Ruleset

To update the ruleset configuration:

1. Export current configuration:

   ```bash
   gh api repos/:owner/:repo/rulesets/9342319 > ruleset_backup.json
   ```

2. Modify the JSON (add/remove rules or status checks)

3. Update via API:

   ```bash
   gh api \
     --method PUT \
     -H "Accept: application/vnd.github+json" \
     repos/:owner/:repo/rulesets/9342319 \
     --input modified_ruleset.json
   ```

## Troubleshooting

### PR Blocked with "Required status check is expected"

**Cause**: A required status check hasn't started or completed

**Solutions**:

1. **Check workflow triggers**: Ensure PR targets `main` branch
2. **Verify workflow files**: `.github/workflows/ci.yml` and `codeql.yml` must exist
3. **Check workflow runs**: Navigate to Actions tab to see if jobs are queued/running
4. **Re-run failed checks**: Click "Re-run all jobs" in the Checks tab

### Status Check Shows as "Expected" but Never Runs

**Cause**: Job may be conditional or workflow not triggered

**Solutions**:

1. **Conditional jobs**: Some jobs (terraform, k8s) only run if directories exist
2. **Push new commit**: Trigger workflow with a new commit
3. **Check workflow syntax**: Use `actionlint` to validate workflow YAML

### Cannot Merge After All Checks Pass

**Causes**:

1. **Missing approval**: At least 1 approval required
2. **Unresolved conversations**: All PR comments must be resolved
3. **Branch not up-to-date**: Rebase or merge `main` into your branch

**Solution**:

```bash
git checkout your-branch
git pull origin main --rebase
git push --force-with-lease
```

## References

- [GitHub Rulesets Documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [Required Status Checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#require-status-checks-before-merging)
- [Code Scanning Integration](https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning)
- [Branch Protection Rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

## Issue Tracking

This configuration was implemented to address:

- **Issue #18**: Configure GitHub Branch Protection Rules
- **Milestone 3**: Infrastructure Hardening
- **Component**: Access Control
- **Priority**: HIGH

## Last Updated

**Date**: 2025-11-03
**Ruleset Version**: Updated at 2025-11-03T07:56:15.802-08:00
**Updated By**: Automated via GitHub API (`gh api`)
