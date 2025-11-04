# Remote state backend configuration
# S3 bucket and DynamoDB table must be created manually before first apply
# See terraform/README.md for setup instructions

terraform {
  backend "s3" {
    bucket         = "ml-platform-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "ml-platform-terraform-locks"

    # State protection via S3 bucket versioning (see terraform/README.md)
    # Versioning retains 30 previous state versions for recovery
    # Terraform backend config does not support prevent_destroy
  }
}
