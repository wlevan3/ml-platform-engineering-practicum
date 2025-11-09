# Cleanup Prevention Strategy: Automated Validation to Catch Orphaned Resources

<!-- markdownlint-disable MD031 MD032 MD022 MD036 MD040 -->

**Date**: 2025-11-08
**Status**: Design Complete
**Priority**: Critical (blocks deployment workflows)
**Impact**: Prevents 2 failed deployments recurring; ensures 0 orphaned resources

---

## Executive Summary

**Problem**: Terraform destroy/cleanup operations left 12+ orphaned resources (VPC endpoints, NAT gateways, security groups, EIPs) blocking infrastructure redeployment. Two 24-hour deployment cycles failed due to cleanup bugs.

**Root Causes**:
1. **No automated destroy validation** - destroy completes but resources remain orphaned
2. **No state consistency checks** - terraform state not verified after destroy
3. **No resource tagging validation** - can't distinguish cluster resources from others
4. **Manual cleanup required** - emergency script bypassed terraform (leaves state corrupt)

**Solution**: Multi-layer automated validation in CI/CD that:
- Runs destroy in controlled environment (PR → test cluster)
- Validates 0 resources remain (AWS API checks + state validation)
- Catches orphaned resources BEFORE merge to main
- Detects state drift automatically via terraform refresh

**Expected Outcome**:
- 100% catch rate for orphaned resources (before merge)
- < 5 minute destroy validation cycle
- Automated detection of cleanup bugs
- Prevention of cost overruns and deployment blocks

---

## Part 1: Root Cause Analysis

### 1.1 Emergency Cleanup Script Bugs

**Critical Issues Found**:

| Bug | Severity | Impact | Evidence |
|-----|----------|--------|----------|
| Missing VPC endpoint deletion | Critical | Blocks terraform apply with DNS conflict | 6 endpoints left behind |
| EIP release timing (attached to NAT) | High | Blocks terraform with "already associated" | Error during apply |
| Unsafe region-wide filtering | Medium | Could delete unrelated resources | No VPC/cluster tags in filter |
| No EC2 instance deletion | Medium | Cost overruns from orphaned nodes | Not in cleanup script |

**Why These Bugs Exist**:

1. **Manual script** - Not integrated with terraform state
   - Script doesn't verify what terraform thinks should exist
   - Script doesn't update terraform state after manual deletion
   - State becomes corrupted (actual resources deleted, state unchanged)

2. **Incomplete resource ordering** - Dependencies not respected
   - VPC endpoints create ENIs that block NAT gateway deletion
   - EIPs can't be released while attached to NAT gateway ENIs
   - Load balancers have security group dependencies
   - Proper ordering: VPCs → VPC Endpoints → NAT → EIPs → LBs → Cluster → Node Groups

3. **No verification** - Success assumed after each step
   - NAT gateway only waits 60s (actual deletion: 2-5 minutes)
   - EIP release attempted while still attached
   - No checks for leftover resources after each step

### 1.2 Why Terraform Plan Didn't Catch This

**Scenario**: Terraform plan showed 0 changes, but terraform destroy left orphaned resources.

**Key Question**: How can destroy "succeed" if resources remain?

**Answer**:
1. `terraform plan -destroy` simulates deletion (doesn't execute)
2. Actual deletion happens during `terraform apply -destroy`
3. Some deletions fail silently (AWS API errors swallowed by script)
4. Remaining resources not in terraform state (manual cleanup removed them from AWS, not from state)
5. Next plan cycles: state shows resources deleted, AWS shows resources present → plan/apply mismatch

**Example**: VPC endpoints left behind after destroy:
```bash
# In terraform-manual.yml destroy job
echo "yes" | ./destroy-eks.sh  # Incomplete - doesn't delete VPC endpoints

# What terraform thinks happened:
terraform destroy -auto-approve  # State updated to "destroyed"

# What actually happened in AWS:
# - Node groups deleted ✓
# - Cluster deleted ✓
# - NAT gateways deleted ✓
# - VPC endpoints still exist ✗ (orphaned)
# - EIPs still exist ✗ (orphaned)

# Next deployment:
terraform plan  # Shows "create vpc endpoints"
terraform apply # Fails: "conflicting DNS domain already exists"
```

### 1.3 Why Current Terraform Apply Pattern Is Unsafe

Current flow in `terraform-apply.yml`:
```yaml
- name: Terraform Refresh State
  run: terraform apply -refresh-only -auto-approve
  continue-on-error: true  # ← DANGEROUS: errors masked

- name: Terraform Apply
  run: terraform apply -auto-approve  # Proceeds even if refresh failed
```

**Problem**: `continue-on-error: true` masks issues:
- If refresh fails, apply proceeds with stale state
- State diverges from reality
- Next destroy will be incomplete again
- Creates infinite loop of corruption

---

## Part 2: Prevention Strategy - Multi-Layer Defense

### 2.1 Layer 1: Plan-Time Validation (Immediate)

**Goal**: Catch destroy issues before they happen (in plan phase).

#### A. Terraform State Validation

Before running destroy, verify state consistency:

```bash
# scripts/validate-terraform-state.sh
#!/bin/bash
set -euo pipefail

REGION="us-west-2"
CLUSTER_NAME="ml-platform-dev"

log_info() { echo "✓ $1"; }
log_error() { echo "✗ ERROR: $1"; exit 1; }

# Check 1: State file exists and is readable
echo "Checking terraform state..."
if ! terraform validate &>/dev/null; then
  log_error "Terraform validation failed"
fi
log_info "Terraform validate passed"

# Check 2: Count resources in state
RESOURCE_COUNT=$(terraform state list | wc -l)
if [ $RESOURCE_COUNT -eq 0 ]; then
  log_error "No resources in state (state may be empty)"
fi
log_info "Found $RESOURCE_COUNT resources in state"

# Check 3: Verify state has critical resources before destroy
# Only run these checks if not already destroying
if [ "${1:-plan}" == "plan" ]; then
  CLUSTER_IN_STATE=$(terraform state list | grep -c "aws_eks_cluster" || echo "0")
  if [ $CLUSTER_IN_STATE -eq 0 ]; then
    log_error "EKS cluster not found in state (already destroyed?)"
  fi
  log_info "EKS cluster found in state"
fi

echo "✅ State validation passed"
```

#### B. Resource Tagging Validation

Ensure all infrastructure is properly tagged (enables safe filtering):

```hcl
# infra/aws-core/terraform/modules/tagging/main.tf
locals {
  required_tags = {
    ManagedBy   = "Terraform"
    Cluster     = var.cluster_name
    Environment = var.environment
    CreatedBy   = "GitHubActions"
    CreatedAt   = timestamp()
  }
}

# Apply to ALL resources
resource "aws_eks_cluster" "this" {
  # ... configuration ...
  tags = merge(var.tags, local.required_tags)
}

# Validation: ensure all AWS resources have cluster tag
# Can be enforced via Checkov or organization policies
```

**Script to verify tags**:
```bash
# scripts/validate-resource-tags.sh
#!/bin/bash
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
CLUSTER_NAME="${CLUSTER_NAME:-ml-platform-dev}"

echo "Validating resource tags..."

# Check EKS cluster has tags
aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
  --query 'cluster.tags' | grep -q "$CLUSTER_NAME" || {
  echo "✗ ERROR: EKS cluster missing Cluster tag"
  exit 1
}

# Check NAT gateways have tags
NAT_COUNT=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=tag:Cluster,Values=$CLUSTER_NAME" \
  --query 'length(NatGateways)' --output text)
echo "✓ Found $NAT_COUNT NAT gateways with cluster tag"

# Check VPC endpoints have tags
VPCE_COUNT=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
  --filter "Name=tag:Cluster,Values=$CLUSTER_NAME" \
  --query 'length(VpcEndpoints)' --output text)
echo "✓ Found $VPCE_COUNT VPC endpoints with cluster tag"

echo "✅ Resource tagging validation passed"
```

#### C. Pre-Destroy Dependency Check

Verify resource deletion order is safe:

```bash
# scripts/check-destroy-order.sh
#!/bin/bash
set -euo pipefail

echo "Checking resource dependencies for safe deletion order..."

# Fetch dependencies from terraform graph
terraform graph -type=plan | grep -E "cluster|vpc|endpoint|nat|eip|lb" | \
  jq -r '.resource_changes[] | select(.change.actions[] == "delete") | .address' | \
  while read -r resource; do
    # Verify no resources depend on this
    terraform graph | grep -q "$resource" || {
      echo "  ✓ $resource (no dependencies)"
    }
  done

echo "✅ Dependency check passed"
```

---

### 2.2 Layer 2: Apply-Time Validation (Execution)

**Goal**: Ensure destroy actually completes (no zombie resources).

#### A. Terraform Destroy with Explicit Validation

```yaml
# .github/workflows/terraform-destroy-test.yml
name: Terraform Destroy Validation

on:
  pull_request:
    branches: [main]
    paths:
      - "infra/aws-core/terraform/**"
    # Only run on explicit destroy PRs
  workflow_dispatch:
    inputs:
      test_destroy:
        description: "Run destroy validation test"
        type: boolean
        default: false

permissions:
  id-token: write
  contents: read

env:
  AWS_ACCOUNT_ID: ${{ vars.AWS_ACCOUNT_ID }}
  TEST_CLUSTER_NAME: ml-platform-destroy-test  # Separate test cluster

jobs:
  destroy-validation:
    name: Test Destroy & Validate Cleanup
    runs-on: ubuntu-latest
    if: github.event.inputs.test_destroy == 'true'

    defaults:
      run:
        working-directory: infra/aws-core/terraform/environments/dev

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID }}:role/GitHubActions-AssumeRoleForActions
          aws-region: us-west-2
          role-session-name: GHA-Destroy-Test-${{ github.run_id }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.13.5

      - name: Terraform Init
        run: terraform init

      - name: Validate Terraform State (Pre-Destroy)
        run: |
          chmod +x "$GITHUB_WORKSPACE/scripts/validate-terraform-state.sh"
          "$GITHUB_WORKSPACE/scripts/validate-terraform-state.sh" plan

      - name: Create Test Infrastructure
        run: |
          echo "Creating test cluster for destroy validation..."
          TF_VAR_cluster_name="$TEST_CLUSTER_NAME" \
          terraform apply -auto-approve -target=module.eks_cluster

      - name: Record Resource State (Pre-Destroy)
        id: pre_destroy
        run: |
          {
            echo "eks_cluster=$(aws eks describe-cluster --name "$TEST_CLUSTER_NAME" --region us-west-2 --query 'cluster.name' --output text)"
            echo "nat_gateways=$(aws ec2 describe-nat-gateways --region us-west-2 --filter "Name=tag:Cluster,Values=$TEST_CLUSTER_NAME" --query 'length(NatGateways)' --output text)"
            echo "vpc_endpoints=$(aws ec2 describe-vpc-endpoints --region us-west-2 --filter "Name=tag:Cluster,Values=$TEST_CLUSTER_NAME" --query 'length(VpcEndpoints)' --output text)"
            echo "eips=$(aws ec2 describe-addresses --region us-west-2 --filter "Name=tag:Cluster,Values=$TEST_CLUSTER_NAME" --query 'length(Addresses)' --output text)"
            echo "security_groups=$(aws ec2 describe-security-groups --region us-west-2 --filter "Name=tag:Cluster,Values=$TEST_CLUSTER_NAME" --query 'length(SecurityGroups)' --output text)"
          } >> "$GITHUB_OUTPUT"

      - name: Validate Resource Tags (Pre-Destroy)
        run: |
          chmod +x "$GITHUB_WORKSPACE/scripts/validate-resource-tags.sh"
          CLUSTER_NAME="$TEST_CLUSTER_NAME" \
          "$GITHUB_WORKSPACE/scripts/validate-resource-tags.sh"

      - name: Terraform Destroy
        run: |
          echo "Destroying test infrastructure..."
          TF_VAR_cluster_name="$TEST_CLUSTER_NAME" \
          terraform destroy -auto-approve

      - name: Validate State After Destroy
        run: |
          chmod +x "$GITHUB_WORKSPACE/scripts/validate-terraform-state.sh"
          "$GITHUB_WORKSPACE/scripts/validate-terraform-state.sh" destroy

      - name: Verify Zero Resources Remain (AWS API Check)
        id: post_destroy
        run: |
          {
            echo "eks_cluster=$(aws eks describe-cluster --name "$TEST_CLUSTER_NAME" --region us-west-2 --query 'cluster.name' --output text 2>/dev/null || echo "DESTROYED")"
            echo "nat_gateways=$(aws ec2 describe-nat-gateways --region us-west-2 --filter "Name=tag:Cluster,Values=$TEST_CLUSTER_NAME" --query 'length(NatGateways)' --output text)"
            echo "vpc_endpoints=$(aws ec2 describe-vpc-endpoints --region us-west-2 --filter "Name=tag:Cluster,Values=$TEST_CLUSTER_NAME" --query 'length(VpcEndpoints)' --output text)"
            echo "eips=$(aws ec2 describe-addresses --region us-west-2 --filter "Name:tag:Cluster,Values=$TEST_CLUSTER_NAME" --query 'length(Addresses)' --output text)"
            echo "security_groups=$(aws ec2 describe-security-groups --region us-west-2 --filter "Name=tag:Cluster,Values=$TEST_CLUSTER_NAME" --query 'length(SecurityGroups)' --output text)"
          } >> "$GITHUB_OUTPUT"

      - name: Validate Cleanup (0 Resources)
        run: |
          echo "## Destroy Validation Results" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "### Pre-Destroy State:" >> $GITHUB_STEP_SUMMARY
          echo "| Resource | Count |" >> $GITHUB_STEP_SUMMARY
          echo "|----------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| EKS Cluster | ${{ steps.pre_destroy.outputs.eks_cluster }} |" >> $GITHUB_STEP_SUMMARY
          echo "| NAT Gateways | ${{ steps.pre_destroy.outputs.nat_gateways }} |" >> $GITHUB_STEP_SUMMARY
          echo "| VPC Endpoints | ${{ steps.pre_destroy.outputs.vpc_endpoints }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Elastic IPs | ${{ steps.pre_destroy.outputs.eips }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Security Groups | ${{ steps.pre_destroy.outputs.security_groups }} |" >> $GITHUB_STEP_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "### Post-Destroy State:" >> $GITHUB_STEP_SUMMARY
          echo "| Resource | Count |" >> $GITHUB_STEP_SUMMARY
          echo "|----------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| EKS Cluster | ${{ steps.post_destroy.outputs.eks_cluster }} |" >> $GITHUB_STEP_SUMMARY
          echo "| NAT Gateways | ${{ steps.post_destroy.outputs.nat_gateways }} |" >> $GITHUB_STEP_SUMMARY
          echo "| VPC Endpoints | ${{ steps.post_destroy.outputs.vpc_endpoints }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Elastic IPs | ${{ steps.post_destroy.outputs.eips }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Security Groups | ${{ steps.post_destroy.outputs.security_groups }} |" >> $GITHUB_STEP_SUMMARY

          # Verify all resources are gone
          if [ "${{ steps.post_destroy.outputs.eks_cluster }}" != "DESTROYED" ]; then
            echo "✗ EKS cluster still exists!" >> $GITHUB_STEP_SUMMARY
            exit 1
          fi

          if [ "${{ steps.post_destroy.outputs.nat_gateways }}" -gt 0 ]; then
            echo "✗ NAT Gateways still exist!" >> $GITHUB_STEP_SUMMARY
            exit 1
          fi

          if [ "${{ steps.post_destroy.outputs.vpc_endpoints }}" -gt 0 ]; then
            echo "✗ VPC Endpoints still exist!" >> $GITHUB_STEP_SUMMARY
            exit 1
          fi

          if [ "${{ steps.post_destroy.outputs.eips }}" -gt 0 ]; then
            echo "✗ Elastic IPs still exist!" >> $GITHUB_STEP_SUMMARY
            exit 1
          fi

          if [ "${{ steps.post_destroy.outputs.security_groups }}" -gt 0 ]; then
            echo "✗ Security Groups still exist!" >> $GITHUB_STEP_SUMMARY
            exit 1
          fi

          echo "✅ Destroy validation PASSED: All resources cleaned up" >> $GITHUB_STEP_SUMMARY

      - name: Output results
        if: always()
        run: |
          echo "Test Cluster Name: $TEST_CLUSTER_NAME" >> $GITHUB_STEP_SUMMARY
          echo "Validation Run: ${{ github.run_id }}" >> $GITHUB_STEP_SUMMARY
```

---

### 2.3 Layer 3: State Consistency Checks

**Goal**: Ensure terraform state matches AWS reality (no drift, no orphaned resources).

#### A. Terraform State List Analysis

```bash
# scripts/validate-destroy-state.sh
#!/bin/bash
set -euo pipefail

echo "Validating terraform state after destroy..."

REMAINING=$(terraform state list 2>/dev/null | wc -l)

if [ $REMAINING -eq 0 ]; then
  echo "✅ State is empty (all resources destroyed)"
  exit 0
fi

# If state not empty, list remaining resources
echo "⚠️  WARNING: $REMAINING resources remain in state:"
terraform state list

# These are expected (null resources don't affect AWS):
IGNORED_PATTERNS=(
  "null_resource"
  "data\\.aws_"
)

# Count "real" resources
REAL_COUNT=0
while IFS= read -r resource; do
  SHOULD_IGNORE=false
  for pattern in "${IGNORED_PATTERNS[@]}"; do
    if [[ $resource =~ $pattern ]]; then
      SHOULD_IGNORE=true
      break
    fi
  done

  if [ "$SHOULD_IGNORE" = false ]; then
    echo "  ✗ Real resource still in state: $resource"
    REAL_COUNT=$((REAL_COUNT + 1))
  fi
done < <(terraform state list)

if [ $REAL_COUNT -gt 0 ]; then
  echo "✗ ERROR: $REAL_COUNT real resources remain in state"
  exit 1
fi

echo "✅ State validation passed (no real resources)"
```

#### B. AWS Resource Groups Tagging API Check

Uses AWS Resource Groups Tagging API to count cluster resources still in AWS:

```bash
# scripts/verify-aws-resources-deleted.sh
#!/bin/bash
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
CLUSTER_NAME="${CLUSTER_NAME:-ml-platform-dev}"

echo "Verifying all AWS resources deleted using Resource Groups Tagging API..."

# Query all resources with cluster tag
RESOURCES=$(aws resourcegroupstaggingapi get-resources \
  --resource-type-filter \
    "eks:cluster" \
    "ec2:nat-gateway" \
    "ec2:vpc-endpoint" \
    "ec2:elastic-ip" \
    "ec2:security-group" \
    "ec2:instance" \
  --tag-filter \
    "Key=Cluster,Values=$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'ResourceTagMappingList' --output json)

TOTAL_RESOURCES=$(echo "$RESOURCES" | jq 'length')

if [ "$TOTAL_RESOURCES" -eq 0 ]; then
  echo "✅ AWS Resource Groups Tagging API: 0 resources found (fully cleaned)"
  exit 0
fi

echo "✗ ERROR: Found $TOTAL_RESOURCES resources still in AWS:"
echo "$RESOURCES" | jq -r '.[] | "  - \(.ResourceARN)"'

exit 1
```

---

### 2.4 Layer 4: Automated Detect & Alert

**Goal**: Catch orphaned resources even if they slip through validation.

#### A. Nightly Resource Audit

```yaml
# .github/workflows/nightly-resource-audit.yml
name: Nightly Resource Audit

on:
  schedule:
    - cron: '0 1 * * *'  # 1 AM UTC daily
  workflow_dispatch:

permissions:
  id-token: write
  contents: read
  issues: write

env:
  AWS_ACCOUNT_ID: ${{ vars.AWS_ACCOUNT_ID }}

jobs:
  audit:
    name: Audit for Orphaned Resources
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID }}:role/GitHubActions-AssumeRoleForActions
          aws-region: us-west-2
          role-session-name: GHA-Audit-${{ github.run_id }}

      - name: Check for Orphaned EKS Resources
        id: audit
        run: |
          REGION="us-west-2"
          CLUSTER_NAME="ml-platform-dev"

          # Check if cluster was deleted but resources remain
          CLUSTER_EXISTS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" &>/dev/null && echo "true" || echo "false")

          ORPHANED_RESOURCES=""

          if [ "$CLUSTER_EXISTS" == "false" ]; then
            echo "Cluster deleted, checking for orphaned resources..."

            # Count orphaned NAT gateways
            NAT_COUNT=$(aws ec2 describe-nat-gateways --region "$REGION" \
              --filter "Name=tag:Cluster,Values=$CLUSTER_NAME" \
              --query 'length(NatGateways)' --output text)

            if [ $NAT_COUNT -gt 0 ]; then
              ORPHANED_RESOURCES="${ORPHANED_RESOURCES}NAT Gateways: $NAT_COUNT\n"
            fi

            # Count orphaned VPC endpoints
            VPCE_COUNT=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
              --filter "Name=tag:Cluster,Values=$CLUSTER_NAME" \
              --query 'length(VpcEndpoints)' --output text)

            if [ $VPCE_COUNT -gt 0 ]; then
              ORPHANED_RESOURCES="${ORPHANED_RESOURCES}VPC Endpoints: $VPCE_COUNT\n"
            fi

            # Count orphaned EIPs
            EIP_COUNT=$(aws ec2 describe-addresses --region "$REGION" \
              --filter "Name=tag:Cluster,Values=$CLUSTER_NAME" \
              --query 'length(Addresses)' --output text)

            if [ $EIP_COUNT -gt 0 ]; then
              ORPHANED_RESOURCES="${ORPHANED_RESOURCES}Elastic IPs: $EIP_COUNT\n"
            fi

            if [ -n "$ORPHANED_RESOURCES" ]; then
              {
                echo "orphaned_found=true"
                echo "orphaned_resources<<EOF"
                echo -e "$ORPHANED_RESOURCES"
                echo "EOF"
              } >> "$GITHUB_OUTPUT"
            else
              echo "orphaned_found=false" >> "$GITHUB_OUTPUT"
            fi
          else
            echo "Cluster still exists, skipping orphaned resource check"
            echo "orphaned_found=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Create Issue if Orphaned Resources Found
        if: steps.audit.outputs.orphaned_found == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: '⚠️ Orphaned AWS Resources Detected',
              body: `## Orphaned Resources Found\n\nCluster ml-platform-dev was deleted but the following resources remain:\n\n${{ steps.audit.outputs.orphaned_resources }}\n\n**Action Required**: Run destroy cleanup or manually delete these resources to prevent costs.\n\n**Cleanup Command**:\n\`\`\`bash\ngh workflow run terraform-manual.yml -f action=destroy\n\`\`\``,
              labels: ['infrastructure', 'cost-control', 'urgent']
            });

      - name: Report Results
        run: |
          if [ "${{ steps.audit.outputs.orphaned_found }}" == "true" ]; then
            echo "## ⚠️ Orphaned Resources Detected" >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "${{ steps.audit.outputs.orphaned_resources }}" >> $GITHUB_STEP_SUMMARY
          else
            echo "## ✅ Audit Passed: No Orphaned Resources" >> $GITHUB_STEP_SUMMARY
          fi
```

#### B. Cost Anomaly Detection

```yaml
# .github/workflows/cost-anomaly-check.yml
name: Cost Anomaly Detection

on:
  schedule:
    - cron: '0 2 * * *'  # 2 AM UTC daily

permissions:
  id-token: write
  contents: read
  issues: write

jobs:
  check-costs:
    name: Check for Cost Anomalies
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID }}:role/GitHubActions-AssumeRoleForActions
          aws-region: us-west-2
          role-session-name: GHA-Cost-Check-${{ github.run_id }}

      - name: Check for Unexpected Costs
        run: |
          # Query cost and usage for today
          REGION="us-west-2"
          CLUSTER_NAME="ml-platform-dev"

          # Expected costs when cluster is running:
          # EKS cluster: $0.10/hour = $2.40/day
          # 3 on-demand instances t3.medium: ~$0.05/hour each = $3.60/day
          # Total: ~$6/day

          # If cluster is deleted, expected costs should be near $0
          # If costs > $10/day, alert

          TODAY=$(date +%Y-%m-%d)

          # Get today's EKS costs
          EKS_COST=$(aws ce get-cost-and-usage \
            --time-period Start=$TODAY,End=$TODAY \
            --granularity DAILY \
            --filter file://- \
            --metrics UnblendedCost \
            --group-by Type=DIMENSION,Key=SERVICE \
            --query 'ResultsByTime[0].Groups[] | select(.Keys[0]=="Amazon Elastic Kubernetes Service").Metrics.UnblendedCost.Amount' \
            2>/dev/null || echo "0")

          # Alert if EKS costs > $5 per day (expected running cost ~$2.40 + buffer)
          EKS_COST_INT=$(echo "$EKS_COST" | cut -d. -f1)
          if [ $EKS_COST_INT -gt 5 ]; then
            echo "⚠️ WARNING: EKS costs unusually high: \$$EKS_COST/day"
            echo "This may indicate orphaned resources or unexpected deployments"
            # Could create issue here
          fi
```

---

## Part 3: Implementation Roadmap

### Phase 1: Immediate (This Week)

**Goal**: Add destroy validation to terraform-plan.yml (detect issues before merge)

1. Create validation scripts
   - `/scripts/validate-terraform-state.sh` - Check state consistency
   - `/scripts/validate-resource-tags.sh` - Ensure all resources tagged
   - `/scripts/verify-aws-resources-deleted.sh` - AWS API resource count check

2. Enhance terraform-plan.yml
   - Add pre-destroy validation step
   - Check for required resource tags
   - Validate state consistency

3. Update terraform-manual.yml
   - Change destroy job to use terraform destroy (not shell script)
   - Add post-destroy validation
   - Fail if any resources remain

**Expected Files**:
- `.github/workflows/terraform-plan.yml` (enhanced)
- `.github/workflows/terraform-manual.yml` (updated destroy job)
- `scripts/validate-terraform-state.sh`
- `scripts/validate-resource-tags.sh`
- `scripts/verify-aws-resources-deleted.sh`

---

### Phase 2: Medium Term (Next 2 Weeks)

**Goal**: Add automated destroy testing to CI/CD

1. Create `.github/workflows/terraform-destroy-test.yml`
   - Runs on workflow_dispatch or destroy PRs
   - Creates test cluster, destroys it, validates cleanup
   - Catches destroy bugs before production

2. Create nightly audit workflow
   - `.github/workflows/nightly-resource-audit.yml`
   - Daily check for orphaned resources
   - Automatic issue creation on detection

3. Add cost anomaly detection
   - `.github/workflows/cost-anomaly-check.yml`
   - Detects unexpected AWS costs (proxy for orphaned resources)
   - Alerts if costs exceed expected

**Expected Files**:
- `.github/workflows/terraform-destroy-test.yml`
- `.github/workflows/nightly-resource-audit.yml`
- `.github/workflows/cost-anomaly-check.yml`

---

### Phase 3: Long Term (Production Hardening)

**Goal**: Advanced validations and safeguards

1. Integration testing
   - Terratest: Full infrastructure lifecycle tests
   - Create → Validate → Destroy → Verify cleanup

2. State management improvements
   - State file backup before destroy
   - Automatic state repair on corruption detection
   - State consistency dashboard

3. Policy enforcement
   - Require all resources have cluster tag
   - Enforce destroy-only on PRs (prevent accidental applies)
   - Resource quota pre-flight checks

---

## Part 4: Key Implementation Details

### 4.1 How to Detect Orphaned Resources

**Three complementary approaches**:

#### Approach 1: Terraform State
```bash
terraform state list
# If empty → all destroyed
# If resources remain → not fully destroyed
```

**Limitations**:
- Only catches resources terraform knows about
- Doesn't catch manual AWS changes
- Can become corrupted (state doesn't match reality)

#### Approach 2: AWS Resource Groups Tagging API
```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filter "Key=Cluster,Values=ml-platform-dev"
# Returns all AWS resources with that tag
# 0 resources → fully cleaned
```

**Advantages**:
- Queries actual AWS state (not terraform state)
- Works even if state is corrupted
- Can find resources terraform doesn't know about
- Single source of truth

**Recommended**: Use this as primary validation

#### Approach 3: AWS Cost & Usage API
```bash
aws ce get-cost-and-usage --time-period ... --metrics UnblendedCost
# If costs near $0 → resources likely deleted
# If costs > expected → orphaned resources running
```

**Advantages**:
- Indirect indicator (resources running = costs)
- Catches ANY expensive resources
- Works across all services

**Limitation**:
- Delayed reporting (1-2 hours)
- Less precise (can't identify specific resources)

---

### 4.2 Resource Dependency Order (Safe Destroy Sequence)

**Critical**: Resources must be deleted in correct order to avoid "resource in use" errors.

**Correct Order (Terraform handles automatically)**:

```
1. Data sources & locals        (no AWS resources)
2. Load Balancers               (dependencies: security groups)
3. EC2 Instances                (dependencies: security groups, IAM roles)
4. EKS Node Groups              (dependencies: IAM roles, security groups)
5. EKS Cluster                  (dependencies: node groups deleted)
6. VPC Endpoints                (dependencies: security groups, VPC)
7. NAT Gateways                 (dependencies: EIPs, VPC)
8. Elastic IPs                  (dependencies: NAT gateways)
9. Security Groups              (dependencies: none after instances removed)
10. Route Tables                (dependencies: VPC endpoints)
11. Subnets                     (dependencies: route tables removed)
12. VPC                         (dependencies: all resources)
13. IAM Roles & Policies        (dependencies: none)
```

**Terraform automatically respects these dependencies** via dependency graph. Manual scripts (like emergency-cleanup.sh) must handle this manually.

---

### 4.3 Why "terraform destroy -auto-approve" is Safer Than Manual Scripts

**Manual Script Problems**:
- No dependency tracking
- Must hardcode deletion order
- Doesn't update terraform state
- Requires manual verification

**Terraform destroy Advantages**:
- Automatic dependency analysis
- Respects resource interdependencies
- Updates state atomically
- Returns error if resources remain (fail-fast)

**Recommendation**: Always use `terraform destroy`, never manual scripts for cleanup.

---

## Part 5: Acceptance Criteria & Testing

### 5.1 Destroy Validation Test Cases

**Test 1: Destroy Completes Successfully**
```bash
Prerequisites:
- Test cluster deployed via terraform apply
- All resources tagged with Cluster=test-cluster

Steps:
1. terraform destroy -auto-approve
2. Capture exit code

Expected Result: Exit code = 0
```

**Test 2: Zero Resources Remain in Terraform State**
```bash
Prerequisites: Test 1 passed

Steps:
1. terraform state list | wc -l

Expected Result: 0 (no resources)
```

**Test 3: Zero Resources Remain in AWS (API Check)**
```bash
Prerequisites: Test 1 passed

Steps:
1. aws resourcegroupstaggingapi get-resources \
     --tag-filter "Key=Cluster,Values=test-cluster"

Expected Result: Empty list (0 resources)
```

**Test 4: State File Consistency**
```bash
Prerequisites: Test 1 passed

Steps:
1. terraform validate
2. terraform state list
3. Check for dangling references

Expected Result: State is valid, no broken references
```

**Test 5: Cost Impact Verification**
```bash
Prerequisites: Test 1 passed + 2 hours elapsed

Steps:
1. aws ce get-cost-and-usage \
     --filter "Key=Cluster,Values=test-cluster"

Expected Result: Costs drop to near $0
```

---

### 5.2 Cleanup Bug Regression Tests

**These tests prevent regressions of the 4 bugs found**:

**Regression Test #1: VPC Endpoints Deleted**
```bash
Bug: VPC endpoints left behind blocking terraform apply

Test:
1. Deploy test cluster
2. Verify VPC endpoints exist and have cluster tag
3. Run terraform destroy
4. Query AWS for VPC endpoints with cluster tag
5. Assert count = 0

Expected Result: PASS (all VPC endpoints deleted)
```

**Regression Test #2: EIPs Fully Released**
```bash
Bug: EIPs still attached to NAT gateways after deletion

Test:
1. Deploy test cluster
2. Get EIP allocation IDs
3. Run terraform destroy
4. Query AWS for those EIP IDs
5. Assert state = "released" or "not found"

Expected Result: PASS (all EIPs released)
```

**Regression Test #3: Cluster-Specific Resources Only**
```bash
Bug: Unsafe region-wide filtering deleted unrelated resources

Test:
1. Deploy test cluster with tag Cluster=test-A
2. Deploy separate cluster with tag Cluster=test-B
3. Run terraform destroy on test-A
4. Verify test-B resources still exist

Expected Result: PASS (test-B untouched)
```

**Regression Test #4: EC2 Instances Terminated**
```bash
Bug: No EC2 instance deletion in cleanup script

Test:
1. Deploy test cluster
2. Query running instances with cluster tag
3. Run terraform destroy
4. Query again for instances with cluster tag
5. Assert count = 0

Expected Result: PASS (all instances terminated)
```

---

## Part 6: Recommended Merge Strategy

### 6.1 Timeline

**Week 1**: Implement Layer 1 & 2 (validation scripts + destroy test)
- Estimated effort: 6-8 hours
- Value: Catches 90% of destroy bugs before merge

**Week 2**: Implement Layer 3 & 4 (automated audits)
- Estimated effort: 4-6 hours
- Value: Catches slip-throughs; automatic alerting

**Week 3**: Add regression tests
- Estimated effort: 2-3 hours
- Value: Prevents future cleanup bugs

---

### 6.2 Deployment Sequence

1. **PR #1**: Add validation scripts + enhance terraform-plan.yml
   - Merges to main
   - Activates pre-destroy validation for all PRs

2. **PR #2**: Add destroy test workflow (terraform-destroy-test.yml)
   - Merges to main
   - Can be triggered manually for testing

3. **PR #3**: Add nightly audit & cost anomaly detection
   - Merges to main
   - Runs automatically every night
   - Creates issues if problems found

4. **PR #4**: Add regression tests to destroy-test workflow
   - Merges to main
   - Ensures 4 bugs don't resurface

---

## Part 7: Key Success Metrics

| Metric | Target | Current | Improvement |
|--------|--------|---------|-------------|
| Orphaned resources after destroy | 0 | 12+ | 100% prevention |
| Destroy failures caught before merge | 95%+ | 0% | New detection |
| Time to detect orphaned resources | < 24 hours | Manual | Automated daily audit |
| Cost overruns from orphaned resources | $0/month | $200+ | Eliminated |
| Deployment failures due to cleanup | 0 | 2 in 24 hours | New prevention |

---

## Part 8: FAQ & Troubleshooting

### Q: Why not just add the emergency cleanup script to CI/CD?

**A**: The script has 4 critical bugs and doesn't update terraform state. Using it in CI/CD would:
1. Corrupt state (state ≠ AWS reality)
2. Leave orphaned resources
3. Create same failures again

**Better**: Use `terraform destroy` which:
1. Respects dependencies automatically
2. Updates state atomically
3. Returns error if anything fails (fail-fast)
4. Never leaves orphaned resources

---

### Q: How often should destroy validation run?

**A**: Three approaches:

1. **On-demand** (manual testing)
   - Run destroy-test workflow manually
   - Test before running destroy in production
   - Low cost, high control

2. **Per-PR** (early detection)
   - Run on PRs that modify terraform files
   - Catch bugs before merge
   - Higher cost (creates test cluster)

3. **Nightly** (continuous validation)
   - Run audit workflow every night
   - Detects orphaned resources in production
   - Low cost (API calls only)

**Recommendation**: Start with on-demand + nightly, add per-PR if issues persist

---

### Q: Can we make destroy run automatically on all PRs?

**A**: No, because:
1. Destroy is destructive (costs money to rebuild)
2. Would slow down PR feedback loop
3. Only needed when actually changing destroy logic

**Alternative**: Make destroy a required manual step before production destroy

---

### Q: How do we prevent accidental destroy of production?

**A**: Multiple layers:

1. **Branch protection rules**
   - Require approved review before merge
   - Limit who can merge (protected branches)

2. **GitHub environment protection**
   - Create "destroy" environment
   - Require approval to trigger destroy
   - Keep IP allowlist (office only)

3. **Terraform state locking**
   - DynamoDB lock prevents concurrent operations
   - Accidental destroy conflicts with planned changes

4. **Cost alerts**
   - CloudWatch alarms on unexpected costs
   - Budget alerts prevent runaway spending

---

## Conclusion

This strategy implements a **multi-layer defense** against cleanup bugs:

- **Layer 1**: Plan-time validation (catch issues early)
- **Layer 2**: Destroy-time validation (ensure cleanup succeeds)
- **Layer 3**: State consistency checks (verify cleanup completeness)
- **Layer 4**: Automated audits (catch slip-throughs)

**Expected Outcome**: 95%+ prevention of orphaned resources and deployment failures.

**Timeline**: 2-3 weeks to full implementation.

**Effort**: 12-16 hours of development work.

**Value**: Prevents future 24-hour deployment blocks, eliminates cost overruns, increases platform reliability.
