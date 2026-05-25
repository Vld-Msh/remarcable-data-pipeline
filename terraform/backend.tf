# backend.tf
# Remote state stored in S3 with DynamoDB locking.
# The S3 bucket and DynamoDB table must be pre-created (bootstrap) before
# running terraform init for the first time.  They are NOT managed by this
# configuration to avoid the chicken-and-egg problem.
#
# Bootstrap commands (one-time, run with admin credentials):
#   aws s3api create-bucket --bucket remarcable-tf-state --region us-east-1 \
#       --create-bucket-configuration LocationConstraint=us-east-1
#   aws s3api put-bucket-versioning --bucket remarcable-tf-state \
#       --versioning-configuration Status=Enabled
#   aws dynamodb create-table \
#       --table-name remarcable-tf-locks \
#       --attribute-definitions AttributeName=LockID,AttributeType=S \
#       --key-schema AttributeName=LockID,KeyType=HASH \
#       --billing-mode PAY_PER_REQUEST

terraform {
  backend "s3" {
    bucket         = "remarcable-tf-state"
    key            = "lakehouse/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "remarcable-tf-locks"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  required_version = ">= 1.7.0"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}
