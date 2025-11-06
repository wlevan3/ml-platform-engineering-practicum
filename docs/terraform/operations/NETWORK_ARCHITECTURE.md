# Complete Network Architecture for ML Platform

This document describes the complete network architecture for the ML Platform Engineering
Practicum project, covering VPC design, EKS cluster access, and public API serving.

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud (us-west-2)                      │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                    VPC (10.0.0.0/16)                          │ │
│  │                                                               │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │         Public Subnets (3 AZs)                          │ │ │
│  │  │  10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24           │ │ │
│  │  │                                                         │ │ │
│  │  │  ┌──────────────────────────────────┐                 │ │ │
│  │  │  │  Application Load Balancer       │                 │ │ │
│  │  │  │  (Public, Internet-Facing)       │                 │ │ │
│  │  │  └────────────┬─────────────────────┘                 │ │ │
│  │  │               │                                        │ │ │
│  │  │  ┌────────────┴─────────────────────┐                 │ │ │
│  │  │  │  NAT Gateway (AZ-a)              │                 │ │ │
│  │  │  └────────────┬─────────────────────┘                 │ │ │
│  │  └───────────────┼──────────────────────────────────────┘ │ │
│  │                  │                                          │ │
│  │  ┌───────────────┼──────────────────────────────────────┐ │ │
│  │  │         Private Subnets (3 AZs)          │           │ │ │
│  │  │  10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24  │           │ │ │
│  │  │                                          │           │ │ │
│  │  │  ┌────────────────────────────────────┐ │           │ │ │
│  │  │  │    EKS Control Plane               │ │           │ │ │
│  │  │  │    (AWS-Managed)                   │ │           │ │ │
│  │  │  └────────────┬───────────────────────┘ │           │ │ │
│  │  │               │                          │           │ │ │
│  │  │  ┌────────────┴───────────────────────┐ │           │ │ │
│  │  │  │  EKS Worker Nodes (EC2)            │ │           │ │ │
│  │  │  │  - t3.medium (2 vCPU, 4GB RAM)     │◄┼───────────┘ │ │
│  │  │  │  - Auto Scaling: 1-4 nodes         │ │             │ │
│  │  │  │                                    │ │             │ │
│  │  │  │  ┌──────────────────────────────┐ │ │             │ │
│  │  │  │  │  Kubernetes Pods             │ │ │             │ │
│  │  │  │  │  - ml-platform-api (×2)      │ │ │             │ │
│  │  │  │  │  - Ingress Controller        │ │ │             │ │
│  │  │  │  └──────────────────────────────┘ │ │             │ │
│  │  │  └────────────────────────────────────┘ │             │ │
│  │  └─────────────────────────────────────────┘             │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    AWS Services                           │ │
│  │  - ECR (Container Registry)                               │ │
│  │  - S3 (CloudTrail, Terraform State)                       │ │
│  │  - CloudTrail (Audit Logging)                             │ │
│  │  - Budgets (Cost Monitoring)                              │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Network Components

### 1. VPC Design

**CIDR Block**: `10.0.0.0/16` (65,536 IP addresses)

**Public Subnets** (for internet-facing resources):

- `10.0.101.0/24` (us-west-2a) - 256 IPs
- `10.0.102.0/24` (us-west-2b) - 256 IPs
- `10.0.103.0/24` (us-west-2c) - 256 IPs

**Private Subnets** (for EKS worker nodes):

- `10.0.1.0/24` (us-west-2a) - 256 IPs
- `10.0.2.0/24` (us-west-2b) - 256 IPs
- `10.0.3.0/24` (us-west-2c) - 256 IPs

**Internet Gateway**: Attached to VPC for public subnet internet access

**NAT Gateway**: Single NAT Gateway in us-west-2a for private subnet internet access (cost optimization - dev environment)

**Route Tables**:

- Public route table: Routes 0.0.0.0/0 → Internet Gateway
- Private route tables: Routes 0.0.0.0/0 → NAT Gateway

### 2. Security Groups

**EKS Cluster Security Group** (managed by Terraform):

- Ingress: 443 from VPC CIDR (API server access)
- Egress: All traffic (required for EKS control plane)

**EKS Node Security Group** (managed by Terraform):

- Ingress: All traffic from cluster security group
- Ingress: 443 from cluster security group (kubelet API)
- Ingress: 1025-65535 from cluster security group (node ports)
- Egress: All traffic (required for pulling images, AWS API calls)

**ALB Security Group** (created by AWS Load Balancer Controller):

- Ingress: 80/443 from 0.0.0.0/0 (public internet)
- Egress: Traffic to EKS nodes on pod ports

### 3. EKS Cluster Configuration

**Control Plane**:

- Managed by AWS (HA across 3 AZs)
- Endpoint: Public (accessible from internet with IAM auth)
- Version: 1.34 (latest stable)

**Worker Nodes**:

- Instance type: t3.medium (2 vCPU, 4GB RAM)
- Auto-scaling: 1-4 nodes (min: 1, desired: 2, max: 4)
- AMI: Amazon EKS-optimized AMI
- Disk: 20GB gp3 EBS volume per node

**Add-ons**:

- AWS Load Balancer Controller (deployed via Helm)
- CoreDNS (AWS-managed)
- kube-proxy (AWS-managed)
- VPC CNI (AWS-managed)

---

## How to Access the EKS Cluster

You have three options for accessing the EKS cluster. **Option 1 is recommended** for this learning project.

### Option 1: Direct kubectl Access (Recommended)

**How it works**:

- Your local kubectl talks directly to the EKS API server over the internet
- Authentication via AWS IAM credentials (no passwords needed)
- EKS control plane validates your IAM identity and checks RBAC permissions

**Setup**:

```bash
# 1. Ensure you have AWS credentials configured
aws sts get-caller-identity

# 2. Update kubeconfig with EKS cluster credentials
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# 3. Verify access
kubectl get nodes
kubectl get pods -A
```

**Security**:

- IAM authentication prevents unauthorized access
- Kubernetes RBAC controls what you can do in the cluster
- All API calls are logged in CloudTrail

**Pros**:

- ✅ Simple setup (no bastion host)
- ✅ Secure (IAM-based authentication)
- ✅ No extra infrastructure cost
- ✅ Works from anywhere with AWS credentials

**Cons**:

- ❌ Requires internet access
- ❌ EKS API endpoint is publicly accessible (but protected by IAM)

**When to use**: Default for development and personal projects

---

### Option 2: Bastion Host (Production-Grade)

**How it works**:

- SSH into a bastion host (jump server) in the public subnet
- Run kubectl commands from the bastion host
- Bastion host has IAM role with EKS permissions

**Architecture**:

```text
Your Laptop → SSH → Bastion (Public Subnet) → kubectl → EKS API Server
```

**Setup** (NOT YET IMPLEMENTED):

```bash
# 1. Create bastion host (Terraform module needed)
terraform apply -target=module.bastion

# 2. SSH to bastion
ssh -i ~/.ssh/your-key.pem ec2-user@<bastion-public-ip>

# 3. Run kubectl from bastion
kubectl get nodes
```

**Implementation** (you would need to add this Terraform module):

```hcl
# infra/aws-core/terraform/modules/bastion/main.tf
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"  # $0.0104/hour ($7.50/month)
  subnet_id     = var.public_subnet_ids[0]

  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # Install kubectl and aws-cli
  user_data = <<-EOF
    #!/bin/bash
    yum install -y kubectl aws-cli

    # Update kubeconfig for ec2-user
    su - ec2-user -c "aws eks update-kubeconfig --name ml-platform-dev --region us-west-2"
  EOF

  tags = {
    Name    = "ml-platform-bastion"
    Project = "ml-platform-engineering-practicum"
  }
}

resource "aws_security_group" "bastion" {
  name_prefix = "ml-platform-bastion-"
  vpc_id      = var.vpc_id

  # SSH from your IP only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]  # e.g., "1.2.3.4/32"
    description = "SSH from your IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
}
```

**Cost**: ~$7.50/month (t3.micro running 24/7)

**Pros**:

- ✅ More secure (EKS API not publicly accessible)
- ✅ Centralized access control
- ✅ Can install other management tools on bastion

**Cons**:

- ❌ Extra infrastructure cost ($7.50/month)
- ❌ Requires SSH key management
- ❌ Bastion becomes a single point of failure

**When to use**: Production environments, corporate compliance requirements

---

### Option 3: VPN or AWS Systems Manager (Enterprise)

**AWS Client VPN**:

- Managed VPN service for remote access to VPC
- Cost: $0.10/hour ($72/month per connection) + data transfer
- Use case: Enterprise with many developers needing VPC access

**AWS Systems Manager Session Manager**:

- Browser-based SSH alternative (no SSH keys needed)
- Cost: FREE (minimal CloudWatch Logs cost)
- Use case: Enterprise with strict security policies (no SSH keys)

**Setup** (Session Manager example):

```hcl
# Enable Session Manager on bastion host
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

```bash
# Connect via Session Manager (no SSH key needed)
aws ssm start-session --target i-1234567890abcdef0

# Run kubectl from session
kubectl get nodes
```

**When to use**: Enterprise environments with SSO, MFA requirements

---

## Serving a Public API

Your infrastructure already supports serving a public API! Here's the complete traffic flow:

### Traffic Flow

```text
User Request (Internet)
    ↓
Application Load Balancer (Public Subnet)
    ↓
Kubernetes Ingress Controller (EKS Pods)
    ↓
ml-platform-api Service (ClusterIP)
    ↓
ml-platform-api Pods (2 replicas)
```

### Components

#### 1. Application Load Balancer (ALB)

**Managed by**: AWS Load Balancer Controller (Kubernetes Ingress → AWS ALB)

**Configuration**: Automatically created when you deploy `clusters/dev/bootstrap/k8s-manifests/ingress.yaml`

**Features**:

- Internet-facing (public IP)
- Health checks: `/health/ready` endpoint
- Target type: IP (routes directly to pod IPs)
- Cost: ~$0.0225/hour ($16/month) + data transfer

**DNS**: ALB provides a DNS name like:

```text
k8s-mlplatfo-mlplatfo-abc123def456-1234567890.us-west-2.elb.amazonaws.com
```

#### 2. Kubernetes Ingress

**File**: `clusters/dev/bootstrap/k8s-manifests/ingress.yaml` (just created)

**Purpose**: Defines routing rules from ALB → Service

**Key annotations**:

- `alb.ingress.kubernetes.io/scheme: internet-facing` - Public ALB
- `alb.ingress.kubernetes.io/target-type: ip` - Route to pod IPs
- `alb.ingress.kubernetes.io/healthcheck-path: /health/ready` - Health check endpoint

#### 3. Kubernetes Service

**File**: `clusters/dev/bootstrap/k8s-manifests/service.yaml`

**Type**: ClusterIP (internal service, not exposed outside cluster)

**Purpose**: Load balances traffic across ml-platform-api pods

#### 4. Kubernetes Pods

**File**: `clusters/dev/bootstrap/k8s-manifests/deployment.yaml`

**Replicas**: 2 (high availability)

**Security**:

- Non-root user (UID 10001)
- Read-only root filesystem
- No privilege escalation
- Seccomp profile enabled

### Deployment Steps

```bash
# 1. Deploy EKS infrastructure
cd infra/aws-core/terraform/environments/dev
terraform apply

# 2. Update kubeconfig
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# 3. Build and push Docker image to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-west-2.amazonaws.com
docker build -t ml-platform-api:v1.0.0 .
docker tag ml-platform-api:v1.0.0 <account-id>.dkr.ecr.us-west-2.amazonaws.com/ml-platform-api:v1.0.0
docker push <account-id>.dkr.ecr.us-west-2.amazonaws.com/ml-platform-api:v1.0.0

# 4. Update deployment.yaml with ECR image URL
# Edit clusters/dev/bootstrap/k8s-manifests/deployment.yaml line 42:
# image: <account-id>.dkr.ecr.us-west-2.amazonaws.com/ml-platform-api:v1.0.0

# 5. Deploy Kubernetes resources
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/namespace.yaml
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/deployment.yaml
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/service.yaml
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/ingress.yaml

# 6. Wait for ALB to provision (2-3 minutes)
kubectl get ingress -n ml-platform -w

# 7. Get ALB DNS name
kubectl get ingress -n ml-platform -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'

# 8. Test API (replace <ALB_DNS> with output from step 7)
curl http://<ALB_DNS>/health/ready
curl -X POST http://<ALB_DNS>/predict \
  -H "Content-Type: application/json" \
  -d '{"features": [5.1, 3.5, 1.4, 0.2]}'
```

### Security Considerations

**TLS/HTTPS** (Not yet configured):

To enable HTTPS, you need:

1. **Domain name** (e.g., api.ml-platform.example.com)
2. **AWS Certificate Manager (ACM) certificate** for your domain
3. **Route 53** for DNS management (or external DNS)

**Setup**:

```hcl
# infra/aws-core/terraform/environments/dev/acm.tf (NOT YET CREATED)
resource "aws_acm_certificate" "api" {
  domain_name       = "api.ml-platform.example.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "api" {
  zone_id = var.route53_zone_id
  name    = "api.ml-platform.example.com"
  type    = "A"

  alias {
    name                   = data.kubernetes_ingress_v1.ml_platform_api.status.0.load_balancer.0.ingress.0.hostname
    zone_id                = data.aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}
```

**Update Ingress for HTTPS**:

```yaml
# clusters/dev/bootstrap/k8s-manifests/ingress.yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'  # Redirect HTTP → HTTPS
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:ACCOUNT_ID:certificate/CERT_ID
```

**Cost**: ACM certificates are FREE, Route 53 hosted zone is $0.50/month

**For now**: Use HTTP with ALB DNS (good enough for learning project)

---

## MILESTONE 1 from README

Based on the README.md, here's what **Phase 2: EKS & Kubernetes** (similar to MILESTONE 1) requires:

### Phase 2 Checklist

- [ ] Terraform configuration for EKS ✅ **DONE** (infra/aws-core/terraform/environments/dev/main.tf)
- [ ] VPC and networking setup ✅ **DONE** (VPC module with public/private subnets)
- [ ] Node groups and autoscaling ✅ **DONE** (t3.medium, 1-4 nodes)
- [ ] kubectl access configuration ✅ **DONE** (IAM-based, instructions above)
- [ ] Deploy sample workload ⚠️ **PARTIALLY DONE**
  - Deployment: ✅ clusters/dev/bootstrap/k8s-manifests/deployment.yaml exists
  - Service: ✅ clusters/dev/bootstrap/k8s-manifests/service.yaml exists
  - Ingress: ✅ clusters/dev/bootstrap/k8s-manifests/ingress.yaml just created
  - Namespace: ✅ clusters/dev/bootstrap/k8s-manifests/namespace.yaml just created
  - **MISSING**: ECR image push and deployment with ECR URL

### What's Still Missing for Complete Phase 2

1. **CI/CD Pipeline for ECR Push**:
   - GitHub Actions workflow to build and push Docker image to ECR
   - Update deployment.yaml with ECR image URL

2. **End-to-End Deployment Guide**:
   - Step-by-step instructions from `terraform apply` to `curl http://<ALB_DNS>/predict`
   - Troubleshooting guide

3. **Documentation**:
   - docs/EKS_DEPLOYMENT.md with complete deployment workflow

---

## Cost Summary

### Always-On Resources

| Resource | Cost | Notes |
|----------|------|-------|
| CloudTrail | ~$0.60/month | First trail free, S3 storage only |
| AWS Budgets | FREE | First 2 budgets free |
| S3 State Bucket | ~$0.10/month | Minimal storage |
| **Total** | **~$0.70/month** | Baseline cost when EKS destroyed |

### EKS Session Resources (Destroy After Use)

| Resource | Hourly | Daily (24h) | Notes |
|----------|--------|-------------|-------|
| EKS Control Plane | $0.10 | $2.40 | Per cluster |
| EC2 Nodes (2× t3.medium) | $0.08 | $1.92 | Worker nodes |
| NAT Gateway | $0.045 | $1.08 | Single NAT (dev) |
| ALB | $0.0225 | $0.54 | Load balancer |
| **Total** | **$0.26/hour** | **$6.27/day** | Destroy after each session |

### Cost Optimization Strategy

**For intermittent usage (few minutes at a time)**:

```bash
# Start session (15-20 min to create)
terraform apply

# Work with EKS (cost accrues at $0.26/hour)
# ...

# End session (destroy everything except CloudTrail/Budgets)
./destroy-eks.sh

# Monthly cost: $0.70 (always-on) + ($0.26 × hours_used)
# Example: 15 min/day × 20 days = 5 hours/month = $0.70 + $1.30 = $2/month
```

---

## Next Steps

To complete Phase 2 (EKS & Kubernetes deployment), you need:

1. **Create GitHub Actions workflow for ECR**:
   - Build Docker image on PR merge
   - Push to ECR with semantic versioning
   - Update deployment.yaml with new image

2. **Create end-to-end deployment guide** (`docs/EKS_DEPLOYMENT.md`):
   - Terraform apply
   - ECR image push
   - Kubernetes deployment
   - Testing and verification
   - Troubleshooting

3. **Optional enhancements**:
   - HTTPS/TLS with ACM certificate
   - Route 53 DNS for custom domain
   - Bastion host for production-grade access
   - VPC Flow Logs for network monitoring

Would you like me to create any of these missing pieces?
