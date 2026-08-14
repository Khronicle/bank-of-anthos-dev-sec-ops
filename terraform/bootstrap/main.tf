# Bootstrap stack — run ONCE, manually, before the main terraform/ stack exists.
# Creates the remote state backend (S3 + DynamoDB) that terraform/backend.tf points at.
#
# State for THIS module is local on purpose (chicken-and-egg: it creates the backend
# other stacks use). terraform.tfstate here is gitignored — see terraform/bootstrap/.gitignore.
#
# No GitHub OIDC role here: this project's CI authenticates to AWS using an
# existing IAM user's static access keys (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY
# GitHub repo secrets), an informed trade-off the account owner made in favor
# of an already-provisioned admin-access IAM user over standing up OIDC. If
# you'd rather use OIDC (short-lived credentials, nothing to leak) see this
# file's git history for the removed aws_iam_openid_connect_provider /
# aws_iam_role "github_actions" resources — CAPSTONE_DEVSECOPS_DEPLOYMENT.md
# stage 0 explains that trade-off.

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.31"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Remote state backend for terraform/ (main stack)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  # Capstone box only — flip to true before anything you'd be sad to lose.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST" # always-free tier: 25 RCU/WCU equivalent, no idle cost
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
