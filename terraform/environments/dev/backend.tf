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

    # Prevents accidental deletion of state
    # Must explicitly disable to destroy infrastructure
    # Note: This setting is in terraform configuration, not S3 bucket
  }
}
