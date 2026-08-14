# cd.yml renders deploy/k8s (image tags substituted) in the GitHub Actions
# runner, uploads the tarball here, then SSM Run Command tells the node to
# pull it down and `kubectl apply -k` it. This is the hand-off — there is no
# other file-transfer path since the node has no inbound SSH.
resource "aws_s3_bucket" "deploy_artifacts" {
  bucket        = "${var.project_name}-deploy-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "deploy_artifacts" {
  bucket                  = aws_s3_bucket.deploy_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning is what makes a bad deploy recoverable: cd.yml writes each release
# to releases/<sha>.tar.gz, so an overwrite of an existing SHA would otherwise
# be unrecoverable. Costs nothing extra here because the lifecycle rule below
# expires noncurrent versions aggressively. (Checkov CKV_AWS_21)
resource "aws_s3_bucket_versioning" "deploy_artifacts" {
  bucket = aws_s3_bucket.deploy_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Old releases aren't needed once deployed — keep this well inside the 5GB
# free-tier S3 allowance.
resource "aws_s3_bucket_lifecycle_configuration" "deploy_artifacts" {
  bucket = aws_s3_bucket.deploy_artifacts.id

  # Versioning is enabled above, so this must be applied for the rules below to
  # behave predictably against noncurrent versions.
  depends_on = [aws_s3_bucket_versioning.deploy_artifacts]

  rule {
    id     = "expire-old-releases"
    status = "Enabled"
    filter {}
    expiration {
      days = 14
    }

    # Without this, enabling versioning above would quietly accumulate every
    # superseded object forever and eat the free-tier allowance.
    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    # A multipart upload interrupted mid-flight (a cancelled CI job) leaves
    # billable parts behind that are invisible in the console. (CKV_AWS_300)
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_iam_role_policy" "node_read_deploy_artifacts" {
  name = "${var.project_name}-node-read-deploy-artifacts"
  role = aws_iam_role.node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.deploy_artifacts.arn}/*"
    }]
  })
}

data "aws_caller_identity" "current" {}

output "deploy_artifacts_bucket" {
  value = aws_s3_bucket.deploy_artifacts.id
}
