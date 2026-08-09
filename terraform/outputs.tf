output "node_public_ip" {
  description = "Elastic IP — this is the URL the app, and ZAP's DAST scan, target: http://<this>/"
  value       = aws_eip.node.public_ip
}

output "node_instance_id" {
  description = "Used by cd.yml's `aws ssm send-command` calls to target the box"
  value       = aws_instance.node.id
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}
