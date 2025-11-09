# VPC Endpoint Dependency Fix - Implementation Guide

**Status**: Ready for Implementation
**Related Issue**: Bug #1 - Missing VPC Endpoint Deletion
**Priority**: High (blocks Terraform apply)
**Complexity**: Low (simple dependency declarations)
**Time to Implement**: 15-30 minutes

---

## Quick Summary

Add explicit `depends_on` declarations to VPC endpoints and export their IDs. This ensures proper deletion order and prevents DNS conflicts during recreation.

---

## File 1: `infra/aws-core/terraform/modules/networking/vpc-endpoints.tf`

### Change: Add `depends_on` to All Endpoints

**Location**: Each of the 6 VPC endpoint resources

**Current Pattern**:

```hcl
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(...)
  # ❌ Missing: depends_on
}
```

**New Pattern**:

```hcl
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-ecr-api-endpoint"
    }
  )

  # ✅ Explicit dependencies for proper destruction order
  depends_on = [
    aws_security_group.vpc_endpoints,
    module.vpc
  ]
}
```

**Apply to**: ALL 6 endpoints

- `aws_vpc_endpoint.ecr_api`
- `aws_vpc_endpoint.ecr_dkr`
- `aws_vpc_endpoint.s3`
- `aws_vpc_endpoint.sts`
- `aws_vpc_endpoint.ec2`
- `aws_vpc_endpoint.autoscaling`

**Verification**:

```bash
cd infra/aws-core/terraform/environments/dev
terraform plan
# Should show no changes (only adds metadata, not resource changes)
```

---

## File 2: `infra/aws-core/terraform/modules/networking/outputs.tf`

### Change: Add VPC Endpoint Output Exports

**Location**: End of file

**Current State**: File exports VPC module outputs (vpc_id, subnet_ids, etc.)

**Addition**:

```hcl
# ===================================================================
# VPC Endpoint Outputs - For cross-module explicit dependencies
# ===================================================================

output "vpc_endpoint_ecr_api_id" {
  description = "ID of the ECR API VPC endpoint"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "ID of the ECR Docker VPC endpoint"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "vpc_endpoint_s3_id" {
  description = "ID of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_sts_id" {
  description = "ID of the STS VPC endpoint"
  value       = aws_vpc_endpoint.sts.id
}

output "vpc_endpoint_ec2_id" {
  description = "ID of the EC2 VPC endpoint"
  value       = aws_vpc_endpoint.ec2.id
}

output "vpc_endpoint_autoscaling_id" {
  description = "ID of the AutoScaling VPC endpoint"
  value       = aws_vpc_endpoint.autoscaling.id
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group used by VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}
```

**Why**: Allows other modules (like EKS cluster) to create explicit dependencies via `depends_on`.

**Verification**:

```bash
cd infra/aws-core/terraform/environments/dev
terraform plan
terraform output | grep vpc_endpoint
# Should display 7 new outputs
```

---

## File 3: `infra/aws-core/terraform/environments/dev/main.tf`

### Change: Add VPC Endpoint Dependency to EKS Cluster

**Location**: `module "eks_cluster"` block

**Current Code**:

```hcl
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  # Networking from networking module
  vpc_id                   = module.networking.vpc_id
  vpc_cidr                 = var.vpc_cidr
  subnet_ids               = module.networking.private_subnet_ids
  control_plane_subnet_ids = module.networking.public_subnet_ids

  # ... rest of config ...

  tags = local.tags

  # Currently: depends_on commented out
  # depends_on = [module.eks_cluster]
}
```

**New Code**:

```hcl
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  # Networking from networking module
  vpc_id                   = module.networking.vpc_id
  vpc_cidr                 = var.vpc_cidr
  subnet_ids               = module.networking.private_subnet_ids
  control_plane_subnet_ids = module.networking.public_subnet_ids

  # Cluster endpoint access configuration
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Node group configuration
  use_spot_instances = var.use_spot_instances
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size

  tags = local.tags

  # ✅ Ensure VPC endpoints are created before EKS cluster nodes join
  # Nodes require: ECR (image pulls), STS (IRSA), EC2 (metadata), S3 (layers)
  depends_on = [
    module.networking
  ]
}
```

**Why**: Ensures VPC endpoints are fully operational before EKS nodes attempt to:

1. Pull container images from ECR
2. Assume IAM roles via STS
3. Query EC2 metadata
4. Access S3 for image layers

**Verification**:

```bash
cd infra/aws-core/terraform/environments/dev
terraform plan
# Graph should show: eks_cluster → networking (with vpc endpoints)
```

---

## Implementation Checklist

- [ ] **Step 1**: Add `depends_on` to `aws_vpc_endpoint.ecr_api` in vpc-endpoints.tf
- [ ] **Step 2**: Add `depends_on` to `aws_vpc_endpoint.ecr_dkr` in vpc-endpoints.tf
- [ ] **Step 3**: Add `depends_on` to `aws_vpc_endpoint.s3` in vpc-endpoints.tf
- [ ] **Step 4**: Add `depends_on` to `aws_vpc_endpoint.sts` in vpc-endpoints.tf
- [ ] **Step 5**: Add `depends_on` to `aws_vpc_endpoint.ec2` in vpc-endpoints.tf
- [ ] **Step 6**: Add `depends_on` to `aws_vpc_endpoint.autoscaling` in vpc-endpoints.tf
- [ ] **Step 7**: Add 7 VPC endpoint outputs to networking/outputs.tf
- [ ] **Step 8**: Add `depends_on = [module.networking]` to eks_cluster module in main.tf
- [ ] **Step 9**: Run `terraform plan` (should show no changes)
- [ ] **Step 10**: Run `terraform graph | dot -Tpng > graph.png` to verify ordering
- [ ] **Step 11**: Commit changes with message: `fix(terraform): Add explicit VPC endpoint dependencies for proper deletion order`

---

## Validation Commands

```bash
# 1. Navigate to environment
cd infra/aws-core/terraform/environments/dev

# 2. Format code
terraform fmt -recursive

# 3. Validate syntax
terraform init
terraform validate

# 4. Plan changes (should be none)
terraform plan

# 5. Generate dependency graph
terraform graph > graph.txt
# Inspect for: vpc_endpoint → security_group → vpc → subnet ordering

# 6. Target specific resource to verify dependencies
terraform plan -target=module.networking.aws_vpc_endpoint.ecr_dkr
# Should show: depends_on edges in plan output

# 7. Visual inspection
terraform graph | dot -Tpng > graph.png
# View in image viewer, confirm:
# - vpc_endpoints depend on security_group
# - security_group depends on vpc module
# - eks_cluster depends on networking module
```

---

## Expected Outcomes

After implementation:

1. **Dependency Graph**:

   ```text
   eks_cluster
       ↓
   networking (vpc module)
       ↓
   vpc_endpoint_* (all 6)
       ↓
   aws_security_group.vpc_endpoints
       ↓
   module.vpc (networking module)
   ```

2. **Terraform Plan Output**:
   - No resource changes
   - `depends_on` edges visible in graph
   - Dependencies validated by Terraform

3. **Destroy Order**:
   - EKS cluster destroyed first
   - VPC endpoints destroyed before security group
   - Security group destroyed before VPC module
   - Prevents DNS conflicts

4. **Future Recreations**:
   - If endpoint needs recreation, security group persists
   - DNS cleanup happens before recreation attempt
   - No "conflicting DNS domain" errors

---

## Common Issues & Troubleshooting

### Issue: `terraform plan` shows unexpected changes

**Cause**: Module outputs may trigger refresh

**Solution**: Run `terraform refresh` first:

```bash
terraform refresh
terraform plan
```

### Issue: Circular dependency error

**Cause**: Accidentally created circular dependency

**Solution**: Check that `depends_on` only goes one direction (never bidirectional)

### Issue: Plan shows vpc_endpoint being recreated

**Cause**: Normal after adding `depends_on` (may affect metadata)

**Solution**: This is safe, just a metadata change in state. No API calls made.

---

## Files Modified

1. `infra/aws-core/terraform/modules/networking/vpc-endpoints.tf`
   - Added `depends_on` to 6 endpoint resources

2. `infra/aws-core/terraform/modules/networking/outputs.tf`
   - Added 7 output exports (vpc_endpoint_*_id, vpc_endpoints_security_group_id)

3. `infra/aws-core/terraform/environments/dev/main.tf`
   - Added `depends_on = [module.networking]` to eks_cluster module

**Total Changes**: 3 files, ~40 lines added

---

## References

- Main research document: `/docs/VPC_ENDPOINT_DEPENDENCY_MANAGEMENT.md`
- Terraform depends_on: <https://www.terraform.io/language/meta-arguments/depends_on>
- EKS Private Clusters: <https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html>
- VPC Endpoint Private DNS: <https://docs.aws.amazon.com/vpc/latest/privatelink/vpce-interface.html#vpce-private-dns>
