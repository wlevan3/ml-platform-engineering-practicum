# ===================================================================
# ECR Lifecycle Policy
# ===================================================================
#
# Automatically cleans up old and untagged images to reduce storage costs.
# ===================================================================

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_tagged_images} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = var.tag_prefix_list
          countType     = "imageCountMoreThan"
          countNumber   = var.max_tagged_images
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after ${var.untagged_image_retention_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_retention_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
