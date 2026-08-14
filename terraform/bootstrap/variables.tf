variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag resources"
  type        = string
  default     = "bank-of-anthos"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state (bucket names are global across all AWS accounts)"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "bank-of-anthos-tf-lock"
}
