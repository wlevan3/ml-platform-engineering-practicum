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

```text
feature/add-model-registry
fix/eks-node-scaling
infra/setup-rds-feature-store
docs/architecture-diagram
refactor/cleanup-terraform
ci/add-security-scan
```

### Commit Message Format

```text
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

## Python Development

### API Server

```bash
# Run development server
uvicorn services.api.main:app --reload --host 0.0.0.0 --port 8000

# Run with custom port
uvicorn services.api.main:app --reload --port 3000
```

### Model Training

```bash
# Train and save model (.skops format)
python train_model.py
```

### Testing

```bash
# Run all tests
pytest

# Run with verbose output and coverage
pytest -v --cov=services.api --cov-report=term-missing

# Run specific test file
pytest tests/test_api.py

# Run with markers
pytest -m "not slow"
```

### Code Quality

```bash
# Format code (Black)
black .
black services/api/ tests/

# Lint and auto-fix (Ruff)
ruff check . --fix
ruff check services/api/

# Type checking (mypy)
mypy services/api/
mypy services/api/ --strict

# Run all pre-commit hooks
pre-commit run --all-files
```

### Docker

```bash
# Build image
docker build -t ml-platform-api:latest .

# Run container
docker run -p 8000:8000 ml-platform-api:latest

# Run with environment variables
docker run -p 8000:8000 -e LOG_LEVEL=debug ml-platform-api:latest

# Security scan
trivy image ml-platform-api:latest --severity HIGH,CRITICAL
```

### SBOM Generation

```bash
# Generate SPDX format
syft ml-platform-api:latest -o spdx-json --file sbom-docker-spdx.json

# Generate CycloneDX format
syft ml-platform-api:latest -o cyclonedx-json --file sbom-docker-cyclonedx.json
```

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
kubectl apply --dry-run=client -f clusters/dev/bootstrap/k8s-manifests/
kubeval clusters/dev/bootstrap/k8s-manifests/*.yaml

# Apply
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/

# Check status
kubectl get pods
kubectl get services
kubectl describe pod <pod-name>

# View logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # follow
```

## ArgoCD Workflow

```bash
# Apply ArgoCD Projects
kubectl apply -f argocd/projects/

# Apply ArgoCD Applications
kubectl apply -f argocd/applications/

# Check Sync Status
argocd app get ml-platform-api
argocd app get ml-platform-resource-quotas

# View Logs
argocd app logs ml-platform-api
```

## AWS Common Commands

```bash
# EKS - Cluster Management
aws eks list-clusters --region us-west-2
aws eks describe-cluster --name ml-platform-dev --region us-west-2
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# S3
aws s3 ls
aws s3 mb s3://bucket-name
aws s3 sync ./local s3://bucket-name

# RDS
aws rds describe-db-instances
```

### EKS Cluster Access Verification

After deploying EKS infrastructure, verify cluster access:

```bash
# 1. Update kubeconfig to point to EKS cluster
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# Expected output:
# Added new context arn:aws:eks:us-west-2:ACCOUNT_ID:cluster/ml-platform-dev to /Users/username/.kube/config

# 2. Verify current context points to EKS (not minikube)
kubectl config current-context

# Expected: arn:aws:eks:us-west-2:ACCOUNT_ID:cluster/ml-platform-dev

# 3. Verify cluster access - list nodes
kubectl get nodes

# Expected: Shows EKS worker nodes (t3.medium spot instances)
# Example output:
# NAME                                          STATUS   ROLES    AGE   VERSION
# ip-10-0-1-123.us-west-2.compute.internal     Ready    <none>   5m    v1.34.x
# ip-10-0-2-124.us-west-2.compute.internal     Ready    <none>   5m    v1.34.x

# 4. Verify namespaces exist
kubectl get namespaces

# Expected: Should see 'ml-platform' namespace (created by Terraform)
# NAME           STATUS   AGE
# default        Active   10m
# kube-system    Active   10m
# ml-platform    Active   8m

# 5. Verify ml-platform namespace resources
kubectl get all -n ml-platform

# Expected: May be empty initially (no deployments yet)
# or show pods/services if deployed via workflow

# 6. Test RBAC permissions
kubectl auth can-i list pods -n ml-platform

# Expected: yes (IAM role has necessary permissions)

# 7. Verify cluster info
kubectl cluster-info

# Expected: Shows EKS cluster endpoint URL

# 8. Check node details (capacity, instance type)
kubectl describe nodes | grep -E "Name:|InstanceType:|allocatable" | head -20
```

**Troubleshooting**:

- If `kubectl` still points to minikube: Check `kubectl config get-contexts` and switch context
- If access denied: Verify AWS credentials with `aws sts get-caller-identity`
- If no nodes: Check EKS console or run
  `aws eks describe-nodegroup --cluster-name ml-platform-dev --nodegroup-name <name> --region us-west-2`

## GitHub Actions Workflows

### EKS Infrastructure Deployment

```bash
# Bootstrap backend (one-time setup) - choose one:
gh workflow run eks-deploy.yml -f action=bootstrap  # GitHub Actions
./platform/scripts/bootstrap-eks-backend.sh dev              # Local script

# Plan infrastructure changes (no apply)
gh workflow run eks-deploy.yml -f action=plan-only

# Deploy EKS cluster + ECR
gh workflow run eks-deploy.yml -f action=deploy -f image_tag=v1.0.0

# Deploy EKS + ECR + deploy to Kubernetes
gh workflow run eks-deploy.yml \
  -f action=deploy \
  -f image_tag=v1.0.0 \
  -f deploy_to_k8s=true

# Destroy EKS only (keep VPC for faster recreation)
gh workflow run eks-deploy.yml -f action=destroy-eks-only

# Full destruction
gh workflow run eks-deploy.yml -f action=destroy
```

### Workflow Management

```bash
# List all workflows
gh workflow list

# View workflow runs
gh run list --workflow=eks-deploy.yml --limit 10

# Watch current workflow run
gh run watch

# View specific run
gh run view <run-id>

# View run logs
gh run view <run-id> --log

# Download artifacts
gh run download <run-id>

# Re-run failed jobs
gh run rerun <run-id> --failed

# Cancel running workflow
gh run cancel <run-id>
```

### Test OIDC Authentication

```bash
# Test AWS OIDC authentication
gh workflow run test-oidc-aws.yml

# View test results
gh run list --workflow=test-oidc-aws.yml --limit 1
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

- **Repository:** <https://github.com/wlevan3/ml-platform-engineering-practicum>
- **Project Board:** <https://github.com/users/wlevan3/projects>
- **Issues:** <https://github.com/wlevan3/ml-platform-engineering-practicum/issues>
- **Pull Requests:** <https://github.com/wlevan3/ml-platform-engineering-practicum/pulls>
- **Actions:** <https://github.com/wlevan3/ml-platform-engineering-practicum/actions>

### Quality Monitoring

- **SonarCloud Dashboard:** <https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum>
- **Quality Gate:** <https://sonarcloud.io/project/quality_gate?id=wlevan3_ml-platform-engineering-practicum>
- **Project Issues:** <https://sonarcloud.io/project/issues?id=wlevan3_ml-platform-engineering-practicum>
- **Quality Standards:** [SONARCLOUD_QUALITY_STANDARDS.md](SONARCLOUD_QUALITY_STANDARDS.md)
- **Coverage Target:** 90% (gate requirement: 80%)

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
