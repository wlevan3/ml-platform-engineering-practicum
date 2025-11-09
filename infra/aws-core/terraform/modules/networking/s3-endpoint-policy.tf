# ===================================================================
# S3 VPC Endpoint Policy - Least Privilege Access
# ===================================================================
#
# This policy restricts S3 gateway endpoint access to only the required
# ECR S3 buckets, following the principle of least privilege.
#
# ECR stores image layers in region-specific S3 buckets with the naming
# pattern: prod-{region}-starport-layer-bucket
#
# References:
# - AWS ECR VPC Endpoints: https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html
# - GitHub Issue #130: https://github.com/wlevan3/ml-platform-engineering-practicum/issues/130
# ===================================================================

# Generate ECR S3 bucket ARN for the current region
locals {
  # ECR uses region-specific S3 buckets for storing image layers
# The naming pattern `prod-{region}-starport-layer-bucket` is observed in practice,
  # but is not officially documented by AWS and may change in the future.
  # Please verify this pattern for your region and refer to the AWS ECR documentation
  # for updates: https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html
  # If AWS changes their infrastructure, this pattern may need to be updated.
  ecr_s3_bucket_name = "prod-${data.aws_region.current.region}-starport-layer-bucket"

  # Create both bucket and bucket object ARNs for the ECR bucket
  ecr_s3_bucket_arns = [
    "arn:aws:s3:::${local.ecr_s3_bucket_name}",
    "arn:aws:s3:::${local.ecr_s3_bucket_name}/*"
  ]

  # Combine ECR buckets with any additional buckets specified by the user
  all_allowed_s3_bucket_arns = concat(
    local.ecr_s3_bucket_arns,
    var.s3_endpoint_allow_additional_buckets
  )

  # S3 endpoint policy that restricts access to only allowed buckets
  s3_endpoint_policy = var.s3_endpoint_enable_policy ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
                # NOTE: Allows any AWS principal to access the allowed buckets via the VPC endpoint.
          # This is required for EKS nodes and other AWS services to function.
          # This policy only restricts which S3 buckets can be accessed, NOT which IAM roles/users can access them.
          # Actual authentication and principal-level restrictions are enforced via IAM policies on roles/users.
          AWS = "*"
        }
        Action = [
          # Required actions for ECR to pull image layers (least privilege)
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = local.all_allowed_s3_bucket_arns
      },
      {
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
      Action      = "s3:*"
        Resource    = "arn:aws:s3:::*"
        NotResource = local.all_allowed_s3_bucket_arns
      }
    ]
  }) : null
}

# Output the ECR S3 bucket name for reference and debugging
output "ecr_s3_bucket_name" {
  description = "The ECR S3 bucket name for the current region"
  value       = local.ecr_s3_bucket_name
}

# Output the full policy for reference
output "s3_endpoint_policy" {
  description = "The S3 VPC endpoint policy (if enabled)"
  value       = local.s3_endpoint_policy
  sensitive   = true
}
