# Bootstrap stack — run ONCE, manually, before the main terraform/ stack exists.
# Creates the remote state backend (S3 + DynamoDB) that terraform/backend.tf points at,
# plus the GitHub Actions OIDC trust so CI never needs a long-lived AWS access key.
#
# State for THIS module is local on purpose (chicken-and-egg: it creates the backend
# other stacks use). terraform.tfstate here is gitignored — see terraform/bootstrap/.gitignore.

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

data "aws_caller_identity" "current" {}

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

# ---------------------------------------------------------------------------
# GitHub Actions OIDC — lets CI assume an AWS role with no stored access keys
# ---------------------------------------------------------------------------

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to this repo; allow any branch/PR/tag ref within it.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

# Least-privilege for what CI actually does: push/pull ECR images, run
# terraform plan/apply, and SSM Run Command to deploy on the EC2 box.
data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}/*"]
  }

  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
    ]
  }

  # Covers both: (a) terraform/deploy-artifacts.tf creating+configuring the
  # deploy-artifacts bucket via `terraform apply`, and (b) cd.yml uploading
  # rendered manifests to it at deploy time. Scoped by the project's naming
  # prefix rather than a fixed ARN, since the bucket doesn't exist yet the
  # first time this policy is evaluated.
  statement {
    sid    = "ProjectS3Buckets"
    effect = "Allow"
    actions = [
      "s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock", "s3:PutLifecycleConfiguration",
      "s3:GetBucketPolicy", "s3:GetBucketPublicAccessBlock",
      "s3:GetLifecycleConfiguration", "s3:GetBucketVersioning",
      # Required by aws_s3_bucket_versioning.deploy_artifacts in
      # terraform/deploy-artifacts.tf. Without it `terraform apply` fails with
      # AccessDenied on the versioning call — Get alone is not enough.
      "s3:PutBucketVersioning",
      "s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:PutBucketTagging",
    ]
    resources = [
      "arn:aws:s3:::${var.project_name}-*",
      "arn:aws:s3:::${var.project_name}-*/*",
    ]
  }

  statement {
    sid       = "TerraformLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.tf_lock.arn]
  }

  # Terraform in terraform/ manages VPC/EC2/IAM/ECR — CI needs to be able to
  # plan/apply those resource types. Scoped to the project tag where the
  # resource type supports it; EC2/VPC/IAM don't support tag-on-create
  # conditions cleanly for every action, so this is deliberately broad
  # within those services rather than pretending to be tighter than it is.
  statement {
    sid    = "ManageProjectInfra"
    effect = "Allow"
    actions = [
      "ec2:*",
      "iam:GetRole", "iam:GetInstanceProfile", "iam:PassRole",
      "iam:CreateRole", "iam:DeleteRole", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagRole", "iam:TagInstanceProfile", "iam:ListInstanceProfilesForRole",
      "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:SetRepositoryPolicy",
      "ecr:PutLifecyclePolicy", "ecr:TagResource",
      "logs:CreateLogGroup", "logs:PutRetentionPolicy", "logs:DescribeLogGroups", "logs:TagResource",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms",
      "sns:CreateTopic", "sns:DeleteTopic", "sns:Subscribe", "sns:GetTopicAttributes", "sns:TagResource",
      # aws_budgets_budget in terraform/monitoring.tf — AWS Budgets exposes
      # exactly these two IAM actions; ViewBudget covers reads, ModifyBudget
      # covers create/update/delete.
      "budgets:ViewBudget", "budgets:ModifyBudget",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DeployViaSSM"
    effect    = "Allow"
    actions   = ["ssm:SendCommand", "ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project_name}-github-actions-permissions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}
