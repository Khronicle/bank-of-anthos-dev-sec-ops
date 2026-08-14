# Bootstrap stack

Run this **once**, manually, from a team member's machine with admin AWS credentials.

```bash
cd terraform/bootstrap
terraform init
terraform apply \
  -var="state_bucket_name=bank-of-anthos-tfstate-<unique-suffix>"
```

State for this module stays **local** (`terraform.tfstate`, gitignored) — it can't use the
remote backend it's the one creating. Keep that state file safe (e.g. in a password manager
or encrypted drive); it's small and only changes if you re-bootstrap.

After `apply`, copy the `state_bucket_name`/`lock_table_name` outputs into
`terraform/backend.tf` (see the full deployment guide, `CAPSTONE_DEVSECOPS_DEPLOYMENT.md`,
for exact values).

**Auth for CI:** this project uses an existing IAM user's static access keys
rather than provisioning a GitHub OIDC role here. Create an access key for
that user (`aws iam create-access-key --user-name <your-iam-user>`, run
locally — never paste the output into a shared chat/PR) and add it as two
GitHub repo **secrets** (Settings → Secrets and variables → Actions →
Secrets, not Variables): `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
That user needs the same permissions this stack used to grant a dedicated
OIDC role for (EC2/IAM/ECR/S3/DynamoDB/SSM/CloudWatch/SNS/Budgets) — an
admin-access user, as used here, already covers all of it.
