# Values come from terraform/bootstrap's outputs — filled in once after that
# stack is applied (see terraform/bootstrap/README.md). Backend config blocks
# can't use variables, so these are literal.
#
# Locking: `dynamodb_table` was deprecated in Terraform 1.11 in favour of S3's
# native conditional-write locking, and emits a deprecation warning on the 1.15
# line we pin. `use_lockfile` replaces it — the lock becomes a .tflock object
# beside the state file, so there's one less resource to provision and pay for.
#
# NOTE: terraform/bootstrap still creates an aws_dynamodb_table.tf_lock and
# grants dynamodb:GetItem/PutItem/DeleteItem on it. Both are now unused. They're
# left in place deliberately — removing them from bootstrap would destroy a live
# table on the next apply. Clean them up as a separate, deliberate change.
terraform {
  backend "s3" {
    bucket       = "REPLACE_WITH_state_bucket_name_OUTPUT"
    key          = "bank-of-anthos/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
