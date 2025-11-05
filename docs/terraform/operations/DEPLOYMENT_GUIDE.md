# ML Platform Deployment Guide

Complete end-to-end deployment guide for the ML Platform Engineering Practicum.

## Prerequisites

- AWS CLI configured with credentials
- kubectl >= 1.28
- Docker Desktop
- terraform >= 1.7.0
- jq (for JSON parsing)

## Quick Start (15-20 minutes)

```bash
# 1. Deploy infrastructure
cd terraform/environments/dev
terraform apply

# 2. Configure kubectl
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# 3. Build and push Docker image to ECR
./deploy-to-ecr.sh  # (script to be created)

# 4. Deploy to Kubernetes
kubectl apply -f ../../../k8s/namespace.yaml
kubectl apply -f ../../../k8s/deployment.yaml
kubectl apply -f ../../../k8s/service.yaml
kubectl apply -f ../../../k8s/ingress.yaml

# 5. Wait for ALB to provision (2-3 minutes)
kubectl get ingress -n ml-platform -w

# 6. Test API
ALB_DNS=$(kubectl get ingress -n ml-platform -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
curl http://${ALB_DNS}/health/ready
```

---

## Detailed Step-by-Step Instructions

### Step 1: Deploy AWS Infrastructure (15-20 minutes)

```bash
cd terraform/environments/dev

# Initialize Terraform (first time only)
terraform init

# Review changes
terraform plan

# Deploy EKS cluster, VPC, ECR, security services
terraform apply

# Expected resources:
# - VPC with public/private subnets across 3 AZs
# - EKS cluster (10-12 min)
# - EKS node group (3-5 min)
# - NAT Gateway
# - ECR repository
# - CloudTrail, Budgets (if enabled)
# - ALB controller (deployed via Helm)
```

**Cost**: $0.26/hour while running ($6.27/day if left on)

**Outputs you'll need**:

```bash
# Get cluster name
terraform output -raw cluster_name
# Output: ml-platform-dev

# Get ECR repository URL
terraform output -raw ecr_repository_url
# Output: 984479408136.dkr.ecr.us-west-2.amazonaws.com/ml-platform-api

# Get AWS account ID
terraform output -raw aws_account_id
# Output: 984479408136
```

---

### Step 2: Configure kubectl Access

```bash
# Update kubeconfig with EKS cluster credentials
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# Verify connection
kubectl get nodes
# Expected output:
# NAME                                         STATUS   ROLES    AGE   VERSION
# ip-10-0-1-123.us-west-2.compute.internal    Ready    <none>   5m    v1.34.0
# ip-10-0-2-456.us-west-2.compute.internal    Ready    <none>   5m    v1.34.0

# Check ALB controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
# Expected: 2 pods in Running state
```

---

### Step 3: Build and Push Docker Image to ECR

```bash
# Get ECR repository URL
ECR_REPO=$(terraform output -raw ecr_repository_url)
AWS_REGION="us-west-2"
IMAGE_TAG="v1.0.0"

# Authenticate Docker to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ECR_REPO}

# Build Docker image (from project root)
cd ../../../
docker build -t ml-platform-api:${IMAGE_TAG} .

# Tag for ECR
docker tag ml-platform-api:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}

# Push to ECR
docker push ${ECR_REPO}:${IMAGE_TAG}

# Verify image in ECR
aws ecr describe-images --repository-name ml-platform-api --region ${AWS_REGION}
```

**Alternative**: Create a helper script `deploy-to-ecr.sh`:

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "→ Getting ECR repository URL..."
ECR_REPO=$(terraform output -raw ecr_repository_url)
IMAGE_TAG="${1:-v1.0.0}"
AWS_REGION="us-west-2"

echo "→ Authenticating Docker to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ECR_REPO}

echo "→ Building Docker image..."
cd ../../../
docker build -t ml-platform-api:${IMAGE_TAG} .

echo "→ Tagging image for ECR..."
docker tag ml-platform-api:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}

echo "→ Pushing to ECR..."
docker push ${ECR_REPO}:${IMAGE_TAG}

echo "✓ Image pushed: ${ECR_REPO}:${IMAGE_TAG}"
```

---

### Step 4: Update Kubernetes Deployment with ECR Image

```bash
# Get ECR image URL
ECR_IMAGE=$(terraform output -raw ecr_repository_url):v1.0.0

# Update deployment.yaml (line 42)
# Before: image: ml-platform-api:v1.0.0
# After:  image: 984479408136.dkr.ecr.us-west-2.amazonaws.com/ml-platform-api:v1.0.0

# Option A: Manual edit
vim k8s/deployment.yaml

# Option B: Automated with sed (macOS)
sed -i '' "s|image: ml-platform-api:v1.0.0|image: ${ECR_IMAGE}|g" k8s/deployment.yaml

# Option B: Automated with sed (Linux)
sed -i "s|image: ml-platform-api:v1.0.0|image: ${ECR_IMAGE}|g" k8s/deployment.yaml
```

---

### Step 5: Deploy to Kubernetes

```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml
# Output: namespace/ml-platform created

# Deploy application
kubectl apply -f k8s/deployment.yaml
# Output: deployment.apps/ml-platform-api created

# Create service
kubectl apply -f k8s/service.yaml
# Output: service/ml-platform-api created

# Create ingress (triggers ALB creation)
kubectl apply -f k8s/ingress.yaml
# Output: ingress.networking.k8s.io/ml-platform-api created
```

---

### Step 6: Wait for ALB Provisioning (2-3 minutes)

```bash
# Watch ingress status (Ctrl+C to exit)
kubectl get ingress -n ml-platform -w

# Expected progression:
# NAME              CLASS   HOSTS   ADDRESS                                                                  PORTS   AGE
# ml-platform-api   alb     *       <pending>                                                                80      10s
# ml-platform-api   alb     *       k8s-mlplatfo-mlplatfo-abc123-1234567890.us-west-2.elb.amazonaws.com     80      2m30s

# Get ALB DNS name (when ADDRESS is populated)
kubectl get ingress -n ml-platform -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

**Troubleshooting**: If ADDRESS stays `<pending>` for >5 minutes:

```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Check ingress events
kubectl describe ingress ml-platform-api -n ml-platform

# Common issues:
# - Insufficient IAM permissions (check IRSA role)
# - Subnet tags missing (should be auto-tagged by Terraform)
# - Security group conflicts
```

---

### Step 7: Verify Deployment

```bash
# Get ALB DNS name
ALB_DNS=$(kubectl get ingress -n ml-platform -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
echo "ALB URL: http://${ALB_DNS}"

# Check pod status
kubectl get pods -n ml-platform
# Expected: 2 pods in Running state

# Check pod logs
kubectl logs -n ml-platform -l app=ml-platform-api --tail=50

# Test liveness endpoint (process alive)
curl http://${ALB_DNS}/health/live
# Expected: {"status":"ok"}

# Test readiness endpoint (model loaded)
curl http://${ALB_DNS}/health/ready
# Expected: {"status":"ready","model_loaded":true,"model_version":"1.0.0"}

# Test prediction endpoint
curl -X POST http://${ALB_DNS}/predict \
  -H "Content-Type: application/json" \
  -d '{"features": [5.1, 3.5, 1.4, 0.2]}'
# Expected: {"prediction":"setosa","confidence":1.0}
```

---

### Step 8: Monitor Resources

```bash
# Watch pods
kubectl get pods -n ml-platform -w

# View pod logs (follow mode)
kubectl logs -n ml-platform -l app=ml-platform-api -f

# Describe pod (resource usage, events)
kubectl describe pod -n ml-platform -l app=ml-platform-api

# Check resource usage
kubectl top pods -n ml-platform
kubectl top nodes

# View ALB in AWS Console
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-mlplatfo`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}' \
  --output table
```

---

## Cleanup (Save Costs)

When done testing, destroy infrastructure to avoid charges:

```bash
cd terraform/environments/dev

# Option 1: Destroy everything except CloudTrail/Budgets (RECOMMENDED)
./destroy-eks.sh

# Option 2: Destroy only EKS, keep VPC/NAT for faster restart
./destroy-eks-only.sh

# Option 3: Destroy absolutely everything
terraform destroy
```

**Cost savings**:

- Destroy EKS: Save $6.27/day
- Keep CloudTrail: $0.02/day ($0.60/month)
- Total idle cost: $0.60/month

---

## Common Issues and Solutions

### Issue: Pods in ImagePullBackOff

```bash
# Check pod events
kubectl describe pod -n ml-platform -l app=ml-platform-api

# Common causes:
# 1. ECR image not pushed
aws ecr describe-images --repository-name ml-platform-api

# 2. Node IAM role lacks ECR permissions
# Solution: Check terraform/environments/dev/main.tf - node IAM role should have AmazonEC2ContainerRegistryReadOnly policy

# 3. Wrong image URL in deployment.yaml
kubectl get deployment ml-platform-api -n ml-platform -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Issue: Pods in CrashLoopBackOff

```bash
# Check pod logs
kubectl logs -n ml-platform -l app=ml-platform-api --previous

# Common causes:
# 1. Model file missing
#    Solution: Ensure train_model.py was run and models/iris_classifier.skops exists before docker build

# 2. Python dependencies missing
#    Solution: Rebuild Docker image with updated requirements.txt

# 3. Security context issues (read-only filesystem)
#    Solution: Check volume mounts in deployment.yaml
```

### Issue: Ingress stuck at ADDRESS `<pending>`

```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100

# Common causes:
# 1. IRSA role missing permissions
#    Solution: Check module.load_balancer_controller_irsa_role in Terraform

# 2. Subnets not tagged properly
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'Subnets[].Tags' --output table
# Required tags:
# - kubernetes.io/role/elb=1 (public subnets)
# - kubernetes.io/cluster/ml-platform-dev=owned

# 3. Security group rules blocking ALB → pods
kubectl describe ingress ml-platform-api -n ml-platform
```

### Issue: Health checks failing (503 errors)

```bash
# Check pod readiness
kubectl get pods -n ml-platform

# Check readiness probe logs
kubectl logs -n ml-platform -l app=ml-platform-api | grep "health"

# Test health endpoint directly from pod
kubectl exec -n ml-platform -it $(kubectl get pod -n ml-platform -l app=ml-platform-api -o jsonpath='{.items[0].metadata.name}') -- curl localhost:8000/health/ready

# Common causes:
# 1. Model loading timeout (>70 seconds)
#    Solution: Increase startupProbe.failureThreshold in deployment.yaml

# 2. Model file corrupted or wrong hash
#    Solution: Rebuild Docker image after re-running train_model.py
```

---

## CI/CD Automated Deployment

### Overview

Automated deployment via GitHub Actions is now available as an alternative to manual
deployment. This workflow handles infrastructure provisioning, Docker image building,
ECR pushing, and optional Kubernetes deployment.

**When to use**:

- ✅ **GitHub Actions**: Auditable, automated, production-like workflow
- ✅ **Manual deployment**: Learning, troubleshooting, quick iteration

### Workflow Setup

1. **S3 Backend Setup** (one-time) - choose one option:

**Option A - GitHub Actions (Recommended)**:

```bash
gh workflow run eks-deploy.yml -f action=bootstrap
```

**Option B - Local Script**:

```bash
./scripts/bootstrap-eks-backend.sh dev

# Expected output:
# ✅ S3 bucket created: ml-platform-terraform-state
# ✅ DynamoDB table created: ml-platform-terraform-locks
```

1. **OIDC Authentication** (already configured):
   - AWS OIDC provider exists
   - IAM role: `GitHubActions-AssumeRoleForActions`
   - See [docs/AWS_OIDC_SETUP.md](../../AWS_OIDC_SETUP.md)

### Deployment Workflow

#### Option 1: Bootstrap Backend (First Time Only)

```bash
gh workflow run eks-deploy.yml -f action=bootstrap
```

**Duration**: 1-2 minutes

**What it does**:

- Creates S3 bucket `ml-platform-terraform-state` with versioning and encryption
- Creates DynamoDB table `ml-platform-terraform-locks` for state locking
- Blocks public access to S3 bucket
- Idempotent (safe to run multiple times)

#### Option 2: Plan Only (No Changes)

```bash
gh workflow run eks-deploy.yml -f action=plan-only
```

**Use case**: Review infrastructure changes before applying

**What it does**:

- Initializes Terraform
- Runs `terraform plan`
- Uploads plan artifact for review
- No resources created or modified

#### Option 3: Full Deployment

```bash
gh workflow run eks-deploy.yml \
  -f action=deploy \
  -f image_tag=v1.0.0
```

**Duration**: 20-25 minutes

**What it does**:

1. **Terraform Apply** (15-20 min):
   - Creates VPC, subnets, NAT gateway
   - Provisions EKS cluster and node groups
   - Creates ECR repository
   - Sets up security services
2. **Build & Push to ECR** (2-5 min):
   - Builds Docker image from Dockerfile
   - Tags image with specified version
   - Pushes to ECR repository
3. **Outputs Summary**:
   - Cluster information
   - ECR repository URL
   - kubectl configuration command
   - Cost reminders

#### Option 4: Full Deployment + Kubernetes

```bash
gh workflow run eks-deploy.yml \
  -f action=deploy \
  -f image_tag=v1.0.0 \
  -f deploy_to_k8s=true
```

**Duration**: 22-28 minutes

**Additional steps**:

- Configures kubectl for EKS cluster
- Updates deployment manifest with ECR image
- Applies Kubernetes manifests (namespace, deployment, service)
- Waits for rollout to complete
- Verifies deployment status

#### Option 5: Destroy Infrastructure

```bash
# Destroy EKS only (keep VPC for faster recreation)
gh workflow run eks-deploy.yml -f action=destroy-eks-only

# Full destruction (EKS + VPC)
gh workflow run eks-deploy.yml -f action=destroy
```

**Cost savings**:

- **destroy-eks-only**: ~$6.27/day → ~$1.60/day (VPC + NAT remaining)
- **destroy (full)**: ~$6.27/day → ~$0.60/month (S3 state + ECR only)

### Monitoring Workflow Runs

```bash
# View workflow runs
gh run list --workflow=eks-deploy.yml --limit 10

# Watch current run
gh run watch

# View specific run with logs
gh run view <run-id> --log

# Download plan artifact
gh run download <run-id>
```

### Workflow Outputs

After successful deployment, the workflow outputs:

**Example output:**

> ## 🎉 EKS Deployment Successful
>
> ### Cluster Information
>
> | Resource | Value |
> |----------|-------|
> | **Cluster Name** | ml-platform-dev |
> | **Region** | us-west-2 |
> | **ECR Repository** | 984479408136.dkr.ecr.us-west-2.amazonaws.com/ml-platform-api |
>
> ### Next Steps
>
> 1. **Configure kubectl**: `aws eks update-kubeconfig --name ml-platform-dev --region us-west-2`
> 1. **Verify cluster access**: `kubectl get nodes` and `kubectl get namespaces`
>
> ### 💰 Cost Reminder
>
> - **Running cost**: ~$0.26/hour ($6.27/day)
> - **Remember to destroy** when done testing

### CI/CD vs Manual Deployment

| Aspect | GitHub Actions | Manual |
|--------|---------------|--------|
| **Audit trail** | ✅ Full workflow logs | ❌ Local only |
| **Reproducibility** | ✅ Consistent environment | ⚠️ Depends on local setup |
| **Learning value** | ⚠️ Abstracts details | ✅ Hands-on experience |
| **Speed** | ⚠️ 20-25 min | ✅ 15-20 min (local build faster) |
| **Troubleshooting** | ❌ Less visibility | ✅ Direct access |
| **Cost** | ⚠️ GitHub Actions minutes | ✅ Free (local compute) |

**Recommendation**: Use manual deployment for learning and troubleshooting,
GitHub Actions for production-like workflows and auditability.

### Troubleshooting Workflow Issues

#### "Resource not found: S3 bucket"

```bash
# Run bootstrap script
./scripts/bootstrap-eks-backend.sh dev
```

#### "OIDC authentication failed"

```bash
# Verify IAM role exists
aws iam get-role --role-name GitHubActions-AssumeRoleForActions --profile dev

# Check trust policy allows this repo
aws iam get-role --role-name GitHubActions-AssumeRoleForActions \
  --query 'Role.AssumeRolePolicyDocument' \
  --profile dev
```

#### "Terraform state lock"

Another workflow run is in progress. Wait or cancel it:

```bash
gh run list --workflow=eks-deploy.yml
gh run cancel <run-id>
```

### Related Documentation

- [.github/workflows/README.md](../../../.github/workflows/README.md) - All workflows documentation
- [docs/QUICK_REFERENCE.md](../../QUICK_REFERENCE.md#github-actions-workflows) - Quick command reference
- [docs/AWS_OIDC_SETUP.md](../../AWS_OIDC_SETUP.md) - OIDC setup guide

---

## Future Roadmap

### Phase 2 Completion

To fully complete Phase 2 (EKS & Kubernetes), you still need:

1. ~~**Automate ECR deployment**~~ ✅ **DONE** - GitHub Actions workflow created
2. **Add HTTPS/TLS** - ACM certificate + Route 53 DNS
3. **End-to-end tests** - CI pipeline to test deployment
4. **Documentation** - Add deployment guide to main README

### Phase 3: Model Registry

- MLflow deployment on EKS
- S3 backend for model artifacts
- Update API to load models from MLflow registry

### Phase 4: Observability

- Prometheus + Grafana for metrics
- ELK stack for logs
- Distributed tracing (Jaeger/Tempo)

---

## Quick Reference Commands

```bash
# Deploy everything
terraform apply && \
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2 && \
kubectl apply -f k8s/

# Get ALB URL
kubectl get ingress -n ml-platform -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'

# Test API
curl http://$(kubectl get ingress -n ml-platform -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')/health/ready

# View logs
kubectl logs -n ml-platform -l app=ml-platform-api -f

# Cleanup
./destroy-eks.sh
```
