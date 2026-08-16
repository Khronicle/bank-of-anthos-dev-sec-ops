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
  description = "EC2 instance type running k3s. t3.micro is free-tier eligible (750 hrs/mo for 12mo); c7i-flex.large is the current choice after t3.small proved insufficient (c5.large was rejected outright by this account: 'FreeTierRestrictionError: This operation is not available for free plan accounts')."
  type        = string
  # t3.small (2 vCPU, 2GiB) still wasn't enough: frontend/contacts were
  # undersized at 96Mi and OOM-crash-looped on every boot (fixed separately in
  # deploy/k8s/*.yaml, now 192Mi) — but the bigger problem was that t3 is a
  # *burstable* family. Under the sustained CPU churn from that crash loop
  # (plus kine/SQLite contention), the instance exhausted its CPU credit
  # balance and got throttled to a fraction of baseline performance, which is
  # why SSM commands and the k3s API server were uniformly unresponsive for
  # 30+ minutes at a time even across multiple reboots/stop-starts — not just
  # "busy," but credit-throttled. c7i-flex is NOT credit-based like t3: it
  # guarantees a fixed CPU baseline (bursting above it for a bounded % of
  # time), removing that whole failure class, at 4GiB RAM — real headroom
  # over the ~1.5GiB this app actually needs at its (now-corrected) limits.
  default = "c7i-flex.large"
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
