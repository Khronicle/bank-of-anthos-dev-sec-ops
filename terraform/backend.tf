# Values come from terraform/bootstrap's outputs — filled in once after that
# stack is applied (see terraform/bootstrap/README.md). Backend config blocks
# can't use variables, so these are literal.
terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_state_bucket_name_OUTPUT"
    key            = "bank-of-anthos/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "bank-of-anthos-tf-lock"
    encrypt        = true
  }
}
