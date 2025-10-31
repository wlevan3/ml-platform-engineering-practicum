# Quick Reference Guide

Quick commands and workflows for the ML Platform Engineering Practicum.

## GitHub Project Quick Actions

### Create New Work

```bash
# Create infrastructure task
gh issue create --template infrastructure.yml --web

# Create feature request
gh issue create --template feature_request.yml --web

# Create learning reflection
gh issue create --template learning_reflection.yml --web

# Create bug report
gh issue create --template bug_report.yml --web
```

### View Project

```bash
# Open project in browser
open https://github.com/users/wlevan3/projects

# List issues in project
gh issue list --state open
```

## Git Workflow

### Start New Work

```bash
# Create feature branch from main
git checkout main
git pull origin main
git checkout -b feature/your-feature-name

# Make changes...

# Commit with conventional commits
git add .
git commit -m "feat(component): add feature description"

# Push and create PR
git push -u origin feature/your-feature-name
gh pr create --title "feat: Feature title" --body "Description" --web
```

### Branch Naming Conventions

```
feature/add-model-registry
fix/eks-node-scaling
infra/setup-rds-feature-store
docs/architecture-diagram
refactor/cleanup-terraform
ci/add-security-scan
```

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `infra` - Infrastructure
- `docs` - Documentation
- `refactor` - Code refactor
- `test` - Tests
- `ci` - CI/CD
- `chore` - Maintenance

## Project Status Updates

### In Project UI

1. Open project board
2. Drag item between columns
3. Or click item and change **Status** field

### Via Issue Labels

```bash
# Add status label to issue
gh issue edit 123 --add-label "status:in-progress"
gh issue edit 123 --add-label "status:blocked"
```

## Terraform Workflow

```bash
# Format
terraform fmt -recursive

# Validate
terraform validate

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Destroy (careful!)
terraform destroy
```

## Kubernetes Workflow

```bash
# Validate manifests
kubectl apply --dry-run=client -f k8s/
kubeval k8s/*.yaml

# Apply
kubectl apply -f k8s/

# Check status
kubectl get pods
kubectl get services
kubectl describe pod <pod-name>

# View logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # follow
```

## AWS Common Commands

```bash
# EKS
aws eks list-clusters
aws eks describe-cluster --name <cluster-name>
aws eks update-kubeconfig --name <cluster-name>

# S3
aws s3 ls
aws s3 mb s3://bucket-name
aws s3 sync ./local s3://bucket-name

# RDS
aws rds describe-db-instances
```

## Pre-commit

```bash
# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files

# Update hooks
pre-commit autoupdate
```

## Useful GitHub CLI Commands

```bash
# View PR
gh pr view

# List PRs
gh pr list

# Create PR
gh pr create --web

# Merge PR (after approval)
gh pr merge --squash

# View issue
gh issue view 123

# List issues
gh issue list --label "priority:high"

# Close issue
gh issue close 123
```

## Project Field Values Reference

### Component
- 🎯 EKS Cluster
- 📦 Model Registry
- 🗄️ Feature Store
- 🔄 CI/CD Pipeline
- 📊 Observability
- 🏗️ Infrastructure
- 📚 Documentation
- 🧠 Learning

### Priority
- 🔴 Critical
- 🟠 High
- 🟡 Medium
- 🟢 Low

### Status
- 📋 Backlog
- 🎯 Ready
- 🚧 In Progress
- 👀 In Review
- ✅ Done
- 🧊 Blocked

### Complexity (1-5)
- 1 = < 1 hour
- 2 = 1-3 hours
- 3 = Half day
- 4 = 1-2 days
- 5 = > 2 days

## Links

- **Repository:** https://github.com/wlevan3/ml-platform-engineering-practicum
- **Project Board:** https://github.com/users/wlevan3/projects
- **Issues:** https://github.com/wlevan3/ml-platform-engineering-practicum/issues
- **Pull Requests:** https://github.com/wlevan3/ml-platform-engineering-practicum/pulls
- **Actions:** https://github.com/wlevan3/ml-platform-engineering-practicum/actions

## Keyboard Shortcuts (GitHub)

- `g` + `i` - Go to Issues
- `g` + `p` - Go to Pull Requests
- `g` + `n` - Go to Notifications
- `?` - Show all shortcuts
- `/` - Search
- `c` - Create issue
- `.` - Open in github.dev (VS Code in browser)

## Documentation

- [Contributing Guide](../CONTRIBUTING.md)
- [Project Management](./PROJECT_MANAGEMENT.md)
- [Architecture](./ARCHITECTURE.md) _(to be created)_
