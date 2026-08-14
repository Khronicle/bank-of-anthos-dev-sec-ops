# Stage 12 (Monitoring & Observability): a memory-pressure alarm on a box
# whose whole design intentionally runs close to its RAM ceiling.
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.project_name}-node-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "BankOfAnthos/Node"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Node memory >90% for 10min — expected occasionally on a free-tier box, but sustained pressure means it's time to consider the t3.small fallback."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = aws_instance.node.id
  }
}

# Guardrail against the free tier being exceeded by mistake (e.g. a second
# instance left running, or NAT Gateway accidentally reintroduced).
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
