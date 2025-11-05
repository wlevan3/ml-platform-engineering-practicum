# Contributing to ML Platform Engineering Practicum

This document outlines the development workflow and contribution guidelines for this project. While this is a
personal learning project, following production-grade practices helps build good habits for professional work.

## Development Setup

### Pre-Commit Hooks

This project uses **pre-commit hooks** to catch issues locally before pushing to GitHub. This "shift-left"
security approach provides faster feedback than waiting for CI/CD.

#### Installation

```bash
# Install pre-commit (if not already installed)
pip install pre-commit

# Install the git hooks
pre-commit install

# (Optional) Run on all files to verify setup
pre-commit run --all-files
```

#### What Gets Checked

The pre-commit hooks automatically run on every commit and check for:

**Security:**

- **detect-secrets** - Finds hardcoded secrets and credentials
- **detect-private-key** - Detects private SSH/PGP keys
- **bandit** - Python security vulnerability scanner
- **hadolint** - Dockerfile security and best practices
- **tfsec** - Terraform security scanner

**Code Quality:**

- **black** - Python code formatting
- **ruff** - Fast Python linter
- **mypy** - Python type checking
- **actionlint** - GitHub Actions workflow validation
- **markdownlint** - Markdown style checking

**General:**

- **trailing-whitespace** - Removes trailing whitespace
- **end-of-file-fixer** - Ensures files end with newline
- **check-yaml** - Validates YAML syntax
- **check-added-large-files** - Prevents large files (>1MB)
- **check-merge-conflict** - Detects merge conflict markers

#### Usage

```bash
# Hooks run automatically on commit
git commit -m "Your commit message"

# Skip hooks if needed (NOT recommended for security hooks)
git commit -m "Your commit message" --no-verify

# Run hooks manually on changed files
pre-commit run

# Run hooks on all files
pre-commit run --all-files

# Run a specific hook
pre-commit run detect-secrets --all-files
pre-commit run mypy --all-files

# Update hook versions
pre-commit autoupdate
```

### Handling Hook Failures

When a hook fails:

1. **Review the output** - Hooks explain what failed and why
2. **Fix the issue** - Address the problem in your code
3. **Stage the fixes** - `git add` the corrected files
4. **Retry commit** - Commit again after fixes

#### Example: Secrets detected

```bash
# If detect-secrets finds a secret
# 1. Remove or mask the secret
# 2. Update .secrets.baseline if it's a false positive:
detect-secrets scan --baseline .secrets.baseline
```

#### Example: Dockerfile issues

```bash
# If hadolint fails
# 1. Review Dockerfile warnings
# 2. Fix issues (e.g., pin versions, use non-root user)
# 3. Stage and commit
```

#### Example: Python security issues

```bash
# If bandit finds security issues
# 1. Review the vulnerability report
# 2. Fix the code (e.g., avoid shell=True, use parameterized queries)
# 3. Add # nosec comment ONLY if false positive with justification
```

### Code Quality Standards (SonarCloud)

This project uses **SonarCloud** for automated code quality and security analysis. Every PR is automatically
scanned, and quality metrics are visible via badges in the README.

#### What is SonarCloud?

SonarCloud is a cloud-based static analysis platform that identifies bugs, vulnerabilities, code smells, and
security hotspots in your code. It provides continuous code quality feedback on every pull request.

#### Quality Gate: "Sonar way" (Default)

All new code must meet these thresholds:

- ✅ **No new bugs** (Reliability Rating = A)
- ✅ **No new vulnerabilities** (Security Rating = A)
- ✅ **Minimal technical debt** (Maintainability Rating = A)
- ✅ **Test coverage ≥ 80%** for new code (Project target: **90%**)
- ✅ **Code duplication ≤ 3%** in new code
- ✅ **All Security Hotspots reviewed** (100%)

**Important**: Quality gate requirements apply to **new code** only (your PR changes), not the entire codebase.
This "Clean as You Code" philosophy prevents new technical debt without requiring you to fix historical issues.

#### Integration Method

SonarCloud runs via **Automatic Analysis (GitHub App)**:

- Analysis triggers automatically on every PR push and merge to `main`
- No CI job configuration needed
- No secrets required in local environment
- Results appear in PR status checks within 1-2 minutes

**Future**: Will migrate to CI-based analysis in Phase 3+ for finer control when integrating with MLflow.

#### Viewing Your Results

##### Option 1: PR Status Checks

```bash
# Check PR status (including SonarCloud)
gh pr checks

# Watch checks in real-time
gh pr checks --watch
```

##### Option 2: SonarCloud Dashboard

- Click any quality badge in README
- Direct link: [Project Dashboard](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
- Filter by "New Code" to see issues in your PR

##### Option 3: PR Comments

- SonarCloud bot comments on PRs with quality gate status
- Inline comments on specific lines if issues found

#### Addressing Issues

**When Quality Gate Fails** ❌:

1. **Review Issues**: Click "Details" on failed SonarCloud check in PR
2. **Prioritize by Severity**:
   - ⛔ **Blocker**: Fix immediately (app-breaking bugs, critical security)
   - 🔴 **Critical**: Fix before merge (likely bugs, vulnerabilities)
   - 🟠 **Major**: Fix or document why deferring
   - 🟡 **Minor/Info**: Fix if time permits
3. **Fix Locally**: Address issues in your code
4. **Test**: Run `pytest` and verify coverage `pytest --cov=app`
5. **Push**: Commit and push fixes → SonarCloud re-analyzes automatically
6. **Verify**: Check that Quality Gate passes ✅

**Common Issues**:

**Coverage Below 80%**:

```bash
# Check coverage locally
pytest --cov=app --cov-report=term-missing

# Add tests for uncovered lines
# Re-run to verify coverage increases
```

**Code Duplication > 3%**:

```bash
# Refactor duplicated blocks into shared functions
# Extract common logic to reduce duplication
```

**Bugs/Vulnerabilities**:

```bash
# Fix the issue (e.g., add null checks, use parameterized queries)
# SonarCloud provides specific guidance for each issue
```

#### Issue Types

- **Bugs** 🐛: Code that will likely break at runtime (e.g., null pointer, division by zero)
- **Vulnerabilities** 🔓: Security flaws attackers can exploit (e.g., SQL injection, hardcoded secrets)
- **Code Smells** 🧼: Maintainability issues making code harder to change (e.g., complex functions, dead code)
- **Security Hotspots** ⚠️: Security-sensitive code requiring review (e.g., authentication, cryptography)

#### IDE Integration (Optional but Recommended)

Install **SonarLint** extension for real-time feedback as you code:

- **VS Code**: Install "SonarLint" extension from marketplace
- **PyCharm**: Install "SonarLint" plugin
- **Benefit**: See issues before committing (faster feedback loop)

```bash
# After installing SonarLint
# 1. Open IDE settings
# 2. Connect to SonarCloud (optional)
# 3. Bind to project: wlevan3_ml-platform-engineering-practicum
# 4. Start coding → Issues appear inline with fixes
```

#### Detailed Documentation

For comprehensive guidance on SonarCloud integration, see:

- **[SonarCloud Quality Standards](docs/SONARCLOUD_QUALITY_STANDARDS.md)** - Complete guide to:
  - Quality Gate thresholds and ratings (A-E scale)
  - Issue types and severity levels
  - Step-by-step remediation workflows
  - New Code vs Overall Code philosophy
  - Integration details and future migration plans
  - FAQ and learning reflections

**Quick Links**:

- [SonarCloud Dashboard](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
- [Quality Gate Details](https://sonarcloud.io/project/quality_gate?id=wlevan3_ml-platform-engineering-practicum)
- [Project Issues](https://sonarcloud.io/project/issues?id=wlevan3_ml-platform-engineering-practicum)

## Development Workflow

This project follows a **production-like workflow** to practice real-world engineering practices:

1. **Create an issue** for the work (bug, feature, infrastructure change, or learning reflection)
2. **Create a feature branch** from `main`
3. **Make changes** with clear, atomic commits
4. **Test locally** before pushing
5. **Create a pull request** using the PR template
6. **Self-review** your changes
7. **Ensure CI/CD passes** (once workflows are set up)
8. **Merge using squash merge** to keep history clean

## Branch Strategy

### Branch Naming Convention

Use descriptive branch names that follow this pattern:

```text
<type>/<short-description>
```

**Types:**

- `feature/` - New functionality
- `fix/` - Bug fixes
- `infra/` - Infrastructure changes
- `docs/` - Documentation updates
- `refactor/` - Code improvements
- `ci/` - CI/CD pipeline changes

**Examples:**

```bash
feature/add-model-registry
fix/eks-node-scaling-issue
infra/setup-feature-store-rds
docs/add-architecture-diagram
```

### Protected Branches

- `main` - Production-ready code, protected by rulesets
  - Requires pull request
  - Requires conversation resolution
  - No force pushes
  - No direct commits

## Commit Guidelines

Follow **Conventional Commits** format for clear, semantic commit messages:

```text
<type>(<scope>): <subject>

<body>

<footer>
```

### Commit Types

- `feat` - New feature
- `fix` - Bug fix
- `infra` - Infrastructure changes
- `docs` - Documentation changes
- `style` - Code style/formatting (no functional changes)
- `refactor` - Code refactoring
- `test` - Adding or updating tests
- `chore` - Maintenance tasks
- `ci` - CI/CD changes

### Examples

```bash
feat(model-registry): add MLflow integration

Implement MLflow tracking server deployment on EKS with S3 backend
for artifact storage. Includes Terraform configurations and Kubernetes
manifests.

Closes #12

---

fix(feature-store): resolve connection timeout issue

Increase RDS connection timeout from 30s to 60s to handle
larger query loads during feature retrieval.

Closes #45

---

infra(eks): upgrade cluster to v1.28

Update EKS cluster from v1.27 to v1.28 for security patches
and new features. Updated node group configurations.

---

docs(readme): add architecture overview diagram

Added high-level architecture diagram showing component relationships
and data flow through the ML platform.
```

### Commit Best Practices

- Write in **imperative mood** ("add feature" not "added feature")
- Keep subject line under 50 characters
- Capitalize first letter of subject
- Don't end subject with a period
- Use body to explain **what** and **why**, not how
- Reference issues in footer

## Pull Request Process

### Before Creating a PR

- [ ] Code is tested locally
- [ ] All tests pass (when CI/CD is set up)
- [ ] Documentation is updated
- [ ] No sensitive data (credentials, keys) in commits
- [ ] Commits follow conventional commit format

### Creating a PR

1. Push your feature branch:

   ```bash
   git push -u origin feature/your-feature
   ```

2. Create PR on GitHub
3. Fill out the PR template completely
4. Link related issues
5. Add appropriate labels

### Self-Review Checklist

Even when working solo, self-review is valuable:

- [ ] Review your own diff line-by-line
- [ ] Check for commented-out code
- [ ] Verify no debug statements left behind
- [ ] Ensure code follows project conventions
- [ ] Check for security issues (hardcoded secrets, etc.)
- [ ] Validate infrastructure changes with `terraform plan`

### Merge Strategy

This project uses **squash merging** exclusively:

- Each PR becomes a single commit in `main`
- Keeps history clean and easy to navigate
- Commit message is generated from PR title and description

## Code Standards

### General Principles

- **Keep it simple** - Prefer clarity over cleverness
- **DRY principle** - Don't repeat yourself
- **Meaningful names** - Variables, functions, and resources should be self-documenting
- **Comments** - Explain *why*, not *what*
- **Error handling** - Always handle errors gracefully

### Python (for ML scripts)

- Follow **PEP 8** style guide
- Use `black` for formatting
- Use `pylint` or `ruff` for linting
- Type hints for function signatures
- Docstrings for modules, classes, and functions

### Terraform

- Use descriptive resource names
- Tag all AWS resources appropriately
- Use variables for reusable values
- Include comments for complex logic
- Organize by service or component
- Use modules for reusable infrastructure

### Kubernetes Manifests

- Use meaningful labels and annotations
- Set resource limits and requests
- Use namespaces for organization
- Include probes (liveness, readiness)
- Document non-obvious configurations

### Shell Scripts

- Use `#!/bin/bash` shebang
- Set `set -euo pipefail` for safety
- Comment complex sections
- Use meaningful variable names
- Quote variables to prevent word splitting

### GitHub Actions

#### Action Pinning Policy

To prevent supply chain attacks, all third-party GitHub Actions **must be pinned to commit SHAs** with version comments:

**GitHub-owned actions (safe with tags):**

- `actions/*` (e.g., `actions/checkout@v4`)
- `github/*` (e.g., `github/codeql-action/*@v3`)

**Third-party actions (require SHA pinning):**

```yaml
# ❌ BAD - Mutable tag vulnerable to tag poisoning
- uses: aquasecurity/trivy-action@master
- uses: some-action/tool@v1

# ✅ GOOD - Pinned to SHA with version comment
- uses: aquasecurity/trivy-action@b6643a29fecd7f34b3597bc6acb0a98b03d33ff8  # master
- uses: some-action/tool@a1b2c3d4e5f6...  # v1.2.3
```

#### Finding the Correct SHA

To pin an action to a specific SHA:

```bash
# Get SHA for a specific tag
gh api repos/OWNER/REPO/git/refs/tags/TAG_NAME --jq '.object.sha'

# Example for aquasecurity/trivy-action@master
gh api repos/aquasecurity/trivy-action/git/refs/heads/master --jq '.object.sha'
```

#### Updating Pinned Actions

Dependabot automatically creates PRs to update pinned actions weekly. The SHA will be updated while the version
comment remains for reference.

## Testing Requirements

### Local Testing

Before pushing:

```bash
# Terraform
terraform fmt -check
terraform validate
terraform plan

# Python
pytest tests/
# Note: black, ruff, and mypy run automatically via pre-commit hooks
# To run manually:
# black --check .
# ruff check .
# mypy app/

# Kubernetes
kubectl apply --dry-run=client -f manifests/
kubeval manifests/*.yaml
```

### CI/CD Testing

Once CI/CD is set up:

- All tests must pass before merge
- Terraform plan must succeed
- Security scans must pass
- No critical vulnerabilities

## Infrastructure Changes

### Terraform Workflow

1. **Make changes** in feature branch
2. **Format code**: `terraform fmt`
3. **Validate**: `terraform validate`
4. **Plan**: `terraform plan -out=tfplan`
5. **Review plan** carefully
6. **Document changes** in PR
7. **Apply** after PR approval: `terraform apply tfplan`

### Important Considerations

- Always review `terraform plan` output
- Check for unexpected resource deletions
- Consider cost implications
- Document rollback procedures
- Backup state before major changes
- Use workspaces for environments

### State Management

- **Never** commit `terraform.tfstate`
- Use remote state (S3 + DynamoDB)
- Lock state during operations
- Backup state regularly

## Documentation

### What to Document

- Architecture decisions and rationale
- Infrastructure design and component relationships
- Setup and deployment procedures
- Troubleshooting guides
- Learning reflections and insights

### Documentation Standards

- Keep README up to date
- Use diagrams for complex architectures
- Include code examples
- Link to relevant resources
- Document assumptions and trade-offs

### Learning Reflections

Use the "Learning Reflection" issue template to capture:

- Key learnings and insights
- Challenges encountered
- Solutions and approaches
- Alternative approaches considered
- Resources that helped

## Getting Help

### Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [MLOps Community](https://mlops.community/)

### Project Structure

```text
ml-platform-engineering-practicum/
├── .github/              # GitHub configuration
│   ├── workflows/        # CI/CD workflows
│   └── ISSUE_TEMPLATE/   # Issue templates
├── terraform/            # Infrastructure as Code
│   ├── eks/             # EKS cluster configuration
│   ├── networking/      # VPC, subnets, etc.
│   └── modules/         # Reusable Terraform modules
├── k8s/                 # Kubernetes manifests
│   ├── model-registry/  # MLflow/registry deployments
│   ├── feature-store/   # Feature store components
│   └── observability/   # Monitoring stack
├── scripts/             # Automation scripts
├── docs/                # Additional documentation
└── tests/               # Test files

```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Remember:** The goal of following these practices is not just to complete the project, but to build professional
engineering habits that translate to real-world team environments.
