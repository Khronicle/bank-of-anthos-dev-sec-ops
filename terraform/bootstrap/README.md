# Bootstrap stack

Run this **once**, manually, from a team member's machine with admin AWS credentials
(never CI — CI doesn't exist yet at this point, and this stack is what creates its identity).

```bash
cd terraform/bootstrap
terraform init
terraform apply \
  -var="state_bucket_name=bank-of-anthos-tfstate-<unique-suffix>" \
  -var="github_org=<your-github-org-or-username>"
```

State for this module stays **local** (`terraform.tfstate`, gitignored) — it can't use the
remote backend it's the one creating. Keep that state file safe (e.g. in a password manager
or encrypted drive); it's small and only changes if you re-bootstrap.

After `apply`, copy the `github_actions_role_arn` output into a GitHub Actions repo variable
named `AWS_ROLE_ARN`, and the `state_bucket_name`/`lock_table_name` outputs into
`terraform/backend.tf` (see the full deployment guide, `CAPSTONE_DEVSECOPS_DEPLOYMENT.md`,
for exact values).
