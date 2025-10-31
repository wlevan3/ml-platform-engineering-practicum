# Contributing to ML Platform Engineering Practicum

This document outlines the development workflow and contribution guidelines for this project. While this is a personal learning project, following production-grade practices helps build good habits for professional work.

## Table of Contents

- [Development Workflow](#development-workflow)
- [Branch Strategy](#branch-strategy)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Code Standards](#code-standards)
- [Testing Requirements](#testing-requirements)
- [Infrastructure Changes](#infrastructure-changes)
- [Documentation](#documentation)

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

```
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

```
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
- Static type checking with `mypy` (runs automatically via pre-commit)
- Type hints for function signatures
- Docstrings for modules, classes, and functions

> **Type checking:** A `mypy` pre-commit hook runs on every commit. Run `pre-commit run mypy --all-files` (or `mypy app/`) to check locally. If you must bypass it, use `SKIP=mypy git commit ...`—avoid skipping unless absolutely necessary.

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

Dependabot automatically creates PRs to update pinned actions weekly. The SHA will be updated while the version comment remains for reference.

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
black --check .
ruff check .
mypy app/

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

```
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

**Remember:** The goal of following these practices is not just to complete the project, but to build professional engineering habits that translate to real-world team environments.
