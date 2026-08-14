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
  validation {
    # Catches an empty/blank value at plan time with a clear message instead
    # of AWS Budgets' "notification must have at least one subscriber" —
    # which looks like a config bug in monitoring.tf, not a missing -var.
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be a real email address (e.g. you@example.com) — got an empty or invalid value. Pass it explicitly: -var=\"budget_alert_email=...\"."
  }
}

variable "budget_limit_usd" {
  description = "Monthly budget threshold in USD that triggers the alert"
  type        = number
  default     = 5
}

variable "alarm_email" {
  description = "Email address for the CloudWatch memory-pressure alarm (SNS subscription)"
  type        = string
  validation {
    # Same rationale as budget_alert_email: an empty value here produces
    # SNS's opaque "InvalidParameter: Endpoint" instead of naming the
    # actual missing input.
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alarm_email))
    error_message = "alarm_email must be a real email address (e.g. you@example.com) — got an empty or invalid value. Pass it explicitly: -var=\"alarm_email=...\"."
  }
}
