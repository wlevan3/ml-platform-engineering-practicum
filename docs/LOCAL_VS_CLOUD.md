# Local vs Cloud Development Guide

This guide helps you decide when to use local Kubernetes (k3d/minikube) vs AWS EKS for development and testing.

## TL;DR - Quick Decision Matrix

| Task | Use Local (k3d) | Use EKS | Reason |
|------|----------------|---------|--------|
| **API endpoint testing** | ✅ | ❌ | Instant feedback, $0 cost |
| **Kubernetes manifest changes** | ✅ | ❌ | Fast iteration (30 sec) |
| **Model changes / retraining** | ✅ | ❌ | Quick Docker rebuild |
| **Debugging application code** | ✅ | ❌ | Faster deployment cycle |
| **Testing ALB Ingress** | ❌ | ✅ | AWS-specific feature |
| **Testing ECR integration** | ❌ | ✅ | AWS-specific feature |
| **Testing IAM roles (IRSA)** | ❌ | ✅ | AWS-specific feature |
| **Final deployment validation** | ❌ | ✅ | Production parity check |

**Recommended split**: 80% local (k3d) / 20% cloud (EKS)

---

## Overview

### Local Development (k3d)

**Pros**:

- ⚡ **Fast** - 30 seconds from code to running pod
- 💰 **Free** - Zero AWS charges
- 🏠 **Offline** - Works without internet
- 🔄 **Rapid iteration** - Code → Build → Test in seconds
- 💚 **Low resource usage** - 512MB RAM (vs 2GB Minikube)

**Cons**:

- ❌ No AWS-specific features (ALB, ECR, IAM)
- ❌ Not 100% identical to production
- ❌ Limited to single-machine resources

### Cloud Development (AWS EKS)

**Pros**:

- ☁️ **Production parity** - Exact same environment as production
- 🔐 **AWS integrations** - ALB, ECR, IAM, VPC, security groups
- 📊 **Cloud-native testing** - CloudWatch metrics, ALB access logs
- 🎓 **Learning AWS** - Hands-on experience with real infrastructure

**Cons**:

- ⏱️ **Slow** - 15-20 min cluster creation + 12-15 min destruction
- 💸 **Cost** - $0.26/hour ($6.27/day if left running)
- 🌐 **Requires internet** - Can't work offline
- 🐢 **Slow iteration** - Each change takes 20+ minutes

---

## Detailed Comparison

### Speed Comparison

| Task | k3d (Local) | EKS (Cloud) | Winner |
|------|-------------|-------------|--------|
| **Cluster creation** | 30 seconds | 15-20 minutes | k3d (40x faster) |
| **Docker build** | 1-2 minutes | Same | Tie |
| **Deploy application** | 10 seconds | 2-3 minutes | k3d (18x faster) |
| **Total time (clean start)** | ~3 minutes | ~22 minutes | k3d (7x faster) |
| **Iteration after changes** | 30 seconds | 20 minutes | k3d (40x faster) |

### Cost Comparison (4-Month Practicum)

| Scenario | Local (k3d) | EKS (Cloud) | Savings |
|----------|-------------|-------------|---------|
| **All work on EKS** (2 hours/day) | N/A | $31.20/month = $124.80 | Baseline |
| **80% local, 20% EKS** (24 min/day EKS) | $0 | $6.24/month = $24.96 | **$99.84 saved** |
| **Current usage** (15 min/day) | $0 | $2/month = $8 | **$116.80 saved** |

---

## When to Use Local (k3d) - 80% of Development

### ✅ Perfect For Local Development

1. **Daily development iteration**
   - Editing Python code (FastAPI endpoints, model logic)
   - Testing new features locally
   - Debugging application issues
   - Running unit tests and integration tests

2. **Kubernetes manifest testing**
   - Changing deployment.yaml (replicas, resources, probes)
   - Modifying service.yaml (ports, selectors)
   - Testing ConfigMaps and Secrets
   - Experimenting with pod scheduling (affinity, tolerations)

3. **Docker image changes**
   - Updating Dockerfile
   - Changing base images
   - Adding new dependencies
   - Testing security contexts

4. **Model experimentation**
   - Retraining with different hyperparameters
   - Testing new ML libraries
   - Changing model architecture
   - Validating predictions locally

5. **CI/CD pipeline development**
   - Testing GitHub Actions workflows locally
   - Validating deployment scripts
   - Debugging automation issues

### Example Workflow

```bash
# Morning: Start local cluster (30 seconds)
./platform/scripts/deploy-local-k3d.sh

# Develop and iterate (instant feedback)
# 1. Edit services/api/main.py
# 2. docker build -t ml-platform-api:v1.0.0 .
# 3. k3d image import ml-platform-api:v1.0.0 -c ml-platform-dev
# 4. kubectl rollout restart deployment/ml-platform-api -n ml-platform
# 5. Test: curl http://localhost:8000/health/ready

# Or use the script for full rebuild + deploy
./platform/scripts/deploy-local-k3d.sh

# Evening: Stop cluster (saves memory)
k3d cluster stop ml-platform-dev

# Next day: Resume where you left off (10 seconds)
k3d cluster start ml-platform-dev
```

---

## When to Use Cloud (EKS) - 20% of Development

### ☁️ Requires AWS EKS

1. **AWS Load Balancer Controller (ALB) testing**
   - Ingress → ALB integration
   - Health check configuration
   - Path-based routing
   - TLS/SSL termination (when added)

2. **ECR (Elastic Container Registry) integration**
   - Pulling images from ECR
   - IAM permissions for image pull
   - Vulnerability scanning results
   - Image lifecycle policies

3. **IAM Roles for Service Accounts (IRSA)**
   - Pod-level AWS permissions
   - S3 access from pods
   - DynamoDB access from pods
   - CloudWatch Logs integration

4. **VPC and networking**
   - Security group rules
   - Network policies
   - NAT Gateway behavior
   - Private/public subnet routing

5. **AWS-managed addons**
   - EBS CSI driver (persistent volumes)
   - VPC-CNI (pod networking)
   - CoreDNS (DNS resolution)

6. **Final validation before merge/release**
   - End-to-end testing in production-like environment
   - Performance testing with real ALB
   - Security testing with actual IAM policies

### Example Cloud Workflow

```bash
# Friday afternoon: Weekly EKS validation

# 1. Deploy infrastructure (15-20 min - take a coffee break)
cd infra/aws-core/terraform/environments/dev
terraform apply

# 2. Configure kubectl
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# 3. Build and push to ECR
../../../infra/aws-core/terraform/environments/dev/deploy-to-ecr.sh v1.0.0

# 4. Deploy to EKS
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/

# 5. Wait for ALB provisioning (2-3 minutes)
kubectl get ingress -n ml-platform -w

# 6. Test with real ALB
ALB_DNS=$(kubectl get ingress -n ml-platform -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
curl http://${ALB_DNS}/health/ready

# 7. Validate AWS integrations
# - Check CloudWatch Logs
# - Verify IAM roles
# - Test security groups

# 8. Destroy infrastructure (12-15 min)
./destroy-eks.sh

# Total time: ~35 minutes
# Cost: ~$0.15 (if completed quickly)
```

---

## Tool Comparison: k3d vs Minikube vs kind

### k3d (Recommended for Daily Development)

**Overview**: Lightweight Kubernetes (K3s) in Docker

**Pros**:

- ⚡ **Fastest startup** - 30 seconds
- 💚 **Lowest memory** - 512MB
- 🚀 **Built-in load balancer** - Easy service exposure
- 🔄 **Easy multi-node clusters** - `--agents 2`
- 📦 **Small footprint** - 50MB binary

**Cons**:

- ❌ K3s (not full Kubernetes) - Some features differ
- ❌ Less documentation than Minikube

**Use for**: Daily development, rapid iteration

```bash
# Install
brew install k3d  # macOS
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash  # Linux

# Deploy
./platform/scripts/deploy-local-k3d.sh
```

### Minikube (Good for AWS-Like Features)

**Overview**: Full Kubernetes distribution, most mature local option

**Pros**:

- ✅ **Most feature-complete** - Closest to production Kubernetes
- ✅ **Addons** - Metrics server, dashboard, ingress
- ✅ **Best documentation** - Extensive guides and tutorials
- ✅ **LoadBalancer support** - Via `minikube tunnel`

**Cons**:

- ⏱️ **Slower startup** - 2-3 minutes
- 💛 **Higher memory** - 2GB minimum
- 🐢 **Slower iteration** - Heavier resource usage

**Use for**: Testing Kubernetes features, learning K8s

```bash
# Deploy
./platform/scripts/deploy-to-minikube.sh
```

### kind (Best for CI/CD)

**Overview**: Kubernetes in Docker, designed for testing

**Pros**:

- 🧪 **CI/CD optimized** - Fast, reproducible
- 🐋 **Docker-native** - Runs K8s nodes as containers
- ⚡ **Fast cluster creation** - 60 seconds

**Cons**:

- ❌ **No LoadBalancer** - Requires manual port forwarding
- ❌ **Less user-friendly** - More manual setup

**Use for**: GitHub Actions, automated testing

---

## Project-Specific Guidance

This ML Platform practicum has 7 projects. Here's when each should use local vs cloud:

### Project 1: Containerized Microservice (Current)

- **Local**: 80% - API development, model changes, manifest testing
- **Cloud**: 20% - Final validation with ECR and ALB

### Project 2: Model Registry (MLflow)

- **Local**: 70% - MLflow server setup, API integration, testing
- **Cloud**: 30% - S3 backend integration, IAM roles, RDS connection

### Project 3: Batch Inference Pipeline

- **Local**: 90% - Pipeline development, job testing
- **Cloud**: 10% - S3 input/output testing

### Project 4: Feature Store (Feast)

- **Local**: 80% - Feature definitions, entity testing
- **Cloud**: 20% - DynamoDB backend integration

### Project 5: Observability Stack (Prometheus + Grafana)

- **Local**: 85% - Dashboard development, metric testing
- **Cloud**: 15% - CloudWatch integration, EKS metrics

### Project 6: CI/CD Pipeline

- **Local**: 60% - Workflow development, testing
- **Cloud**: 40% - GitHub Actions with EKS deployment, OIDC authentication

### Project 7: Advanced Topics (AutoScaling, Spot)

- **Local**: 40% - HPA testing, pod autoscaling
- **Cloud**: 60% - Cluster autoscaling, spot interruption handling

---

## Cost Savings Calculator

### Scenario 1: All Development on EKS

- **Time on EKS**: 2 hours/day × 20 days = 40 hours/month
- **Cost**: 40 hours × $0.26/hour = **$10.40/month**
- **4-month practicum**: **$41.60**

### Scenario 2: 80% Local, 20% EKS (Recommended)

- **Time on EKS**: 24 min/day × 20 days = 8 hours/month
- **Cost**: 8 hours × $0.26/hour = **$2.08/month**
- **4-month practicum**: **$8.32**
- **Savings**: **$33.28 (80% cost reduction)**

### Scenario 3: 90% Local, 10% EKS (Aggressive)

- **Time on EKS**: 12 min/day × 20 days = 4 hours/month
- **Cost**: 4 hours × $0.26/hour = **$1.04/month**
- **4-month practicum**: **$4.16**
- **Savings**: **$37.44 (90% cost reduction)**

---

## Quick Reference Commands

### k3d Commands

```bash
# Create cluster
k3d cluster create ml-platform-dev --agents 2 --port "8000:80@loadbalancer"

# Stop cluster (saves memory, keeps data)
k3d cluster stop ml-platform-dev

# Start cluster
k3d cluster start ml-platform-dev

# Delete cluster
k3d cluster delete ml-platform-dev

# List clusters
k3d cluster list

# Import Docker image
k3d image import ml-platform-api:v1.0.0 -c ml-platform-dev
```

### Minikube Commands

```bash
# Start cluster
minikube start --cpus=2 --memory=4096

# Stop cluster
minikube stop

# Delete cluster
minikube delete

# Access service
minikube service ml-platform-api -n ml-platform
```

### EKS Commands

```bash
# Deploy infrastructure
cd infra/aws-core/terraform/environments/dev
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# Destroy infrastructure
./destroy-eks.sh
```

---

## Best Practices

### Daily Development Workflow

```bash
# Morning (5 minutes):
k3d cluster start ml-platform-dev  # If stopped overnight
./platform/scripts/deploy-local-k3d.sh      # Deploy latest code

# During day (continuous iteration):
# Edit code → Build → Import → Test
docker build -t ml-platform-api:v1.0.0 .
k3d image import ml-platform-api:v1.0.0 -c ml-platform-dev
kubectl rollout restart deployment/ml-platform-api -n ml-platform
curl http://localhost:8000/health/ready

# Evening:
k3d cluster stop ml-platform-dev  # Free up 512MB RAM
```

### Weekly EKS Validation

```bash
# Friday afternoon (35 minutes total):
# 1. Deploy EKS (15-20 min - work on other tasks)
# 2. Test AWS-specific features (5-10 min)
# 3. Destroy EKS (12-15 min - end of day)

# Cost: ~$0.15 per weekly validation
```

### Rule of Thumb

**If your task mentions any of these, use EKS**:

- ALB, Load Balancer, Ingress (with AWS ALB Controller)
- ECR, Docker registry (when pulling from ECR)
- IAM, Roles, Policies (IRSA)
- S3, DynamoDB, RDS (AWS services)
- Security Groups, VPC, Subnets
- CloudWatch, CloudTrail

**Otherwise, use k3d for fast iteration!**

---

## Troubleshooting

### Issue: "k3d not found"

```bash
# Install k3d
brew install k3d  # macOS
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash  # Linux
```

### Issue: k3d cluster won't start

```bash
# Delete and recreate
k3d cluster delete ml-platform-dev
k3d cluster create ml-platform-dev --agents 2 --port "8000:80@loadbalancer"
```

### Issue: Can't access <http://localhost:8000>

```bash
# Check service
kubectl get service -n ml-platform

# Check pods
kubectl get pods -n ml-platform

# Check k3d port mapping
k3d cluster list

# Recreate cluster with correct port
k3d cluster delete ml-platform-dev
k3d cluster create ml-platform-dev --port "8000:80@loadbalancer"
```

---

## Summary

**Use k3d for 80% of work**:

- ⚡ 40x faster iteration (30 sec vs 20 min)
- 💰 Zero cost
- 🚀 Perfect for daily development

**Use EKS for 20% of work**:

- ☁️ AWS-specific features (ALB, ECR, IAM)
- 🎓 Learning production infrastructure
- ✅ Final validation before merge

**Expected outcome**:

- **Time saved**: ~15 hours over 4-month practicum
- **Cost saved**: ~$33/practicum (80% reduction)
- **Better workflow**: Fast feedback loop for most development

**Action**: Start using k3d today!

```bash
# Install k3d
brew install k3d

# Deploy to local cluster
./platform/scripts/deploy-local-k3d.sh

# Start developing!
```
