# Remote state backend configuration
# S3 bucket and DynamoDB table must be created manually before first apply
# See terraform/README.md for setup instructions

terraform {
  backend "s3" {
    bucket         = "ml-platform-terraform-state-984479408136"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "ml-platform-terraform-locks"

    # State protection via S3 bucket versioning and DynamoDB locking
    # - S3 versioning retains 30 previous state versions for recovery
    # - DynamoDB prevents concurrent state modifications
    # - KMS encryption enforced at bucket level
    # - Public access blocked at bucket level
  }
}
