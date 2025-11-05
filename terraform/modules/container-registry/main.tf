# ===================================================================
# Container Registry Module - ECR Repository
# ===================================================================
#
# This module creates an Amazon Elastic Container Registry (ECR)
# repository with security best practices:
# - Image vulnerability scanning on push
# - Encryption at rest with KMS
# - Lifecycle policies for image cleanup
# ===================================================================

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  # Vulnerability scanning on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest with KMS
  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.kms_key_arn
  }

  tags = merge(
    var.tags,
    {
      Name = var.repository_name
    }
  )
}
