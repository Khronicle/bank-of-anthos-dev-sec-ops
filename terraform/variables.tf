variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag resources and name ECR repos"
  type        = string
  default     = "bank-of-anthos"
}

variable "instance_type" {
  description = "EC2 instance type running k3s. t3.micro is free-tier eligible (750 hrs/mo for 12mo); t3.small is the documented paid fallback (~$15/mo) if memory pressure proves unworkable."
  type        = string
  default     = "t3.micro"
}

variable "ssh_cidr_blocks" {
  description = "CIDR ranges allowed to reach the SSM-managed instance's emergency-access SSH port. Left empty by default — deployment uses SSM Session Manager, not SSH; only add entries here if you need a break-glass path."
  type        = list(string)
  default     = []
}

variable "budget_alert_email" {
  description = "Email address to notify when the AWS Budgets alert fires"
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly budget threshold in USD that triggers the alert"
  type        = number
  default     = 5
}

variable "alarm_email" {
  description = "Email address for the CloudWatch memory-pressure alarm (SNS subscription)"
  type        = string
}
