output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.id
}

output "lock_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}

output "github_actions_role_arn" {
  description = "Set this as the GH_ACTIONS_ROLE_ARN repo variable / secret used by ci.yml and cd.yml"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
