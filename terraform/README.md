# Terraform Infrastructure for ML Platform

This directory contains Terraform configurations for provisioning AWS infrastructure for the ML Platform.

## Directory Structure

```text
terraform/
├── environments/
│   └── dev/
│       ├── backend.tf        # S3 + DynamoDB state backend
│       ├── providers.tf      # AWS, Kubernetes, Helm providers
│       ├── variables.tf      # Input variables
│       ├── main.tf           # Main infrastructure (VPC, EKS, ECR, ALB)
│       └── outputs.tf        # Output values
├── scripts/
│   └── bootstrap-backend.sh  # Creates S3 bucket and DynamoDB table
└── README.md                 # This file
```

## Prerequisites

### Required Tools

- **AWS CLI** (v2.x+): `aws --version`
- **Terraform** (v1.6.0+): `terraform version`
- **kubectl** (v1.34+): `kubectl version --client`
- **helm** (v3.x+): `helm version`

### AWS Authentication

This project uses **AWS OIDC authentication** for GitHub Actions. For local development:

```bash
# Configure AWS CLI profile
aws configure --profile kodekloud

# Verify authentication
AWS_PROFILE=kodekloud aws sts get-caller-identity

# Set profile as environment variable (recommended)
export AWS_PROFILE=kodekloud
```

See `docs/AWS_OIDC_SETUP.md` for details on OIDC configuration.

## Initial Setup

### 1. Bootstrap Remote State Backend

The S3 bucket and DynamoDB table for Terraform state must be created **before** running `terraform init`:

```bash
# Run bootstrap script
./terraform/scripts/bootstrap-backend.sh

# Verify resources created
aws s3 ls s3://ml-platform-terraform-state
aws dynamodb describe-table --table-name ml-platform-terraform-locks
```

**Bootstrap script creates:**

- **S3 bucket**: `ml-platform-terraform-state`
  - Versioning enabled (state history)
  - Encryption enabled (AES256)
  - Public access blocked
  - Lifecycle policy (retain 30 versions)
- **DynamoDB table**: `ml-platform-terraform-locks`
  - Pay-per-request billing
  - Used for state locking (prevents concurrent applies)

### 2. Initialize Terraform

```bash
cd terraform/environments/dev

# Initialize Terraform (downloads providers, configures backend)
terraform init

# Review configuration
terraform validate
```

### 3. Review Infrastructure Plan

```bash
# Generate and review plan
terraform plan -out=tfplan

# Review what will be created:
# - VPC with public/private subnets across 3 AZs
# - EKS cluster (v1.34) with managed node group
# - ECR repository for ml-platform-api
# - AWS Load Balancer Controller (via Helm)
# - IAM roles and policies
```

**Expected resources**: ~40-50 resources (VPC: 20, EKS: 15-20, ECR: 3, IAM: 5-10)

### 4. Apply Infrastructure

```bash
# Apply plan (creates infrastructure)
terraform apply tfplan

# This will take 15-20 minutes
# - VPC: ~2 minutes
# - EKS cluster: ~12-15 minutes
# - Node group: ~3-5 minutes
# - Load Balancer Controller: ~1-2 minutes
```

### 5. Configure kubectl

```bash
# Update kubeconfig with EKS cluster credentials
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# Verify cluster access
kubectl get nodes
kubectl get pods --all-namespaces
```

Expected output:

```text
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-1-123.us-west-2.compute.internal    Ready    <none>   5m    v1.34.x
ip-10-0-2-456.us-west-2.compute.internal    Ready    <none>   5m    v1.34.x
```

## Infrastructure Components

### VPC Configuration

- **CIDR**: `10.0.0.0/16`
- **Availability Zones**: 3 (us-west-2a, us-west-2b, us-west-2c)
- **Subnets**:
  - Public: `10.0.101.0/24`, `10.0.102.0/24`, `10.0.103.0/24` (for ALB)
  - Private: `10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24` (for EKS nodes)
- **NAT Gateway**: Single NAT (cost optimization for dev)
- **DNS**: Enabled (required for EKS)

### EKS Cluster

- **Name**: `ml-platform-dev`
- **Version**: Kubernetes 1.34
- **Endpoint Access**: Public + Private
- **OIDC Provider**: Enabled (for IAM roles for service accounts)
- **Addons**: CoreDNS, kube-proxy, VPC-CNI, EBS CSI Driver

### EKS Node Group

- **Instance Type**: t3.medium (2 vCPU, 4 GB RAM)
- **Capacity**: 2 desired, 1 min, 4 max
- **AMI**: Amazon Linux 2 (x86_64)
- **Disk**: 50 GB EBS per node
- **IAM**: Includes SSM access for troubleshooting

### ECR Repository

- **Name**: `ml-platform-api`
- **Tag Mutability**: IMMUTABLE (security best practice)
- **Scan on Push**: Enabled (vulnerability scanning)
- **Encryption**: AES256
- **Lifecycle Policy**:
  - Keep last 10 tagged images (v*)
  - Remove untagged images after 7 days

### AWS Load Balancer Controller

- **Chart**: `aws-load-balancer-controller` (chart v1.14.1, controller v2.14.1)
- **Purpose**: Manages ALBs for Kubernetes Ingress
- **IAM**: IRSA (IAM Roles for Service Accounts)
- **Namespace**: kube-system

## Working with Infrastructure

### Common Commands

```bash
# Show current state
terraform show

# List all resources
terraform state list

# Show specific resource
terraform state show module.eks.aws_eks_cluster.this[0]

# View outputs
terraform output

# Get ECR repository URL
terraform output ecr_repository_url

# Get kubeconfig command
terraform output kubeconfig_command
```

### Updating Infrastructure

```bash
# Pull latest code
git pull origin main

# Review changes
terraform plan

# Apply updates
terraform apply

# Verify EKS cluster health
kubectl get nodes
kubectl get pods --all-namespaces
```

### Scaling Node Group

```bash
# Edit variables.tf
# Change node_desired_size, node_min_size, node_max_size

# Apply changes
terraform apply

# Verify scaling
kubectl get nodes -w
```

### Destroying Infrastructure

**⚠️ WARNING**: This will delete **ALL** infrastructure including the EKS cluster, VPC, and ECR images.

```bash
# Dry run (show what will be destroyed)
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Confirm when prompted
# This takes ~15-20 minutes

# Optional: Clean up state backend (if no longer needed)
# aws s3 rb s3://ml-platform-terraform-state --force
# aws dynamodb delete-table --table-name ml-platform-terraform-locks
```

## Troubleshooting

### Issue: `terraform init` fails with "backend configuration changed"

**Cause**: Backend configuration modified but not re-initialized

**Fix**:

```bash
terraform init -reconfigure
```

### Issue: EKS cluster creation fails with "subnet not found"

**Cause**: VPC module failed or subnets not tagged correctly

**Fix**:

```bash
# Check VPC resources
terraform state list | grep vpc

# Verify subnet tags
aws ec2 describe-subnets \
  --filters "Name=tag:kubernetes.io/cluster/ml-platform-dev,Values=shared"
```

### Issue: kubectl cannot connect to cluster

**Cause**: Kubeconfig not updated or IAM permissions missing

**Fix**:

```bash
# Update kubeconfig
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# Verify AWS identity
aws sts get-caller-identity

# Check EKS cluster endpoint
aws eks describe-cluster --name ml-platform-dev \
  --query 'cluster.endpoint' --output text
```

### Issue: Node group nodes not joining cluster

**Cause**: Security group rules or IAM roles misconfigured

**Fix**:

```bash
# Check node group status
aws eks describe-nodegroup \
  --cluster-name ml-platform-dev \
  --nodegroup-name ml-platform-dev-node-group

# Check node group health
kubectl get nodes
kubectl describe node <node-name>

# Review node logs (via AWS Console EC2 -> Systems Manager -> Session Manager)
```

### Issue: Helm chart installation fails

**Cause**: Kubernetes provider not authenticated or IRSA role missing

**Fix**:

```bash
# Verify Helm can connect to cluster
helm list --all-namespaces

# Check Load Balancer Controller pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# View pod logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## Cost Optimization

### Dev Environment (Default)

- **EKS Control Plane**: $0.10/hour = $72/month
- **EC2 Nodes (2x t3.medium)**: $0.0832/hour = $60/month
- **NAT Gateway (single)**: $0.045/hour = $32/month
- **EBS Volumes (2x 50GB gp3)**: ~$8/month
- **Data Transfer**: Variable (minimal for dev)
- **Total**: ~$172/month

### Cost Reduction Tips

1. **Stop cluster when not in use**:

   ```bash
   # Scale node group to 0
   terraform apply -var="node_desired_size=0" -var="node_min_size=0"
   ```

2. **Use Spot Instances** (not implemented, future enhancement):

   - 50-70% cost savings on compute
   - Requires handling interruptions

3. **Single NAT Gateway** (already implemented):

   - Saves ~$32/month per additional NAT
   - Dev environment uses 1 NAT instead of 3

4. **Delete when not needed**:

   ```bash
   terraform destroy
   ```

## Security Considerations

1. **IAM Roles**: Least privilege principle
   - Node group: ECR read, CloudWatch write, SSM read
   - Load Balancer Controller: ALB/ELB management only

2. **Network Isolation**:
   - Worker nodes in private subnets (no direct internet access)
   - Egress via NAT Gateway
   - Security groups restrict traffic to necessary ports

3. **Encryption**:
   - EKS secrets encrypted with AWS KMS (default)
   - ECR images encrypted at rest (AES256)
   - EBS volumes encrypted

4. **Image Security**:
   - ECR vulnerability scanning on push
   - Immutable image tags (prevent overwrites)
   - Lifecycle policies (remove old/untagged images)

5. **Kubernetes Security**:
   - Non-root containers (enforced in deployment.yaml)
   - Read-only root filesystem (where possible)
   - No privilege escalation
   - Service account automounting disabled

## Next Steps

After infrastructure is provisioned:

1. **Push Docker image to ECR**:

   ```bash
   # Get ECR login command from Terraform output
   terraform output ecr_login_command

   # Authenticate Docker
   $(terraform output -raw ecr_login_command)

   # Tag and push image
   ECR_URL=$(terraform output -raw ecr_repository_url)
   docker tag ml-platform-api:v1.0.0 ${ECR_URL}:v1.0.0
   docker push ${ECR_URL}:v1.0.0
   ```

2. **Update Kubernetes manifests** (see `k8s/README.md`):

   - Update `k8s/deployment.yaml` with ECR image URL
   - Change `imagePullPolicy: Never` → `IfNotPresent`
   - Create `k8s/ingress.yaml` for ALB

3. **Deploy application**:

   ```bash
   kubectl apply -f k8s/
   ```

4. **Verify deployment**:

   ```bash
   kubectl get pods
   kubectl get ingress
   kubectl get svc
   ```

5. **Set up CI/CD** (see `.github/workflows/deploy.yml`):
   - Automate ECR push on main merge
   - Update deployment with new image
   - Verify health checks

## References

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform AWS VPC Module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
- [Terraform AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS Load Balancer Controller Docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

## Support

For project-specific questions, see:

- `CLAUDE.md` - Project conventions and workflows
- `docs/AWS_OIDC_SETUP.md` - AWS authentication setup
- `docs/EKS_DEPLOYMENT.md` - End-to-end deployment guide (created after first deploy)
