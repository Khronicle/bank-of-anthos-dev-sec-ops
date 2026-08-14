# Deployment

Quick-reference snapshot of what's actually running and how it gets there.
For the full stage-by-stage rationale and every file's contents, see
[`CAPSTONE_DEVSECOPS_DEPLOYMENT.md`](./CAPSTONE_DEVSECOPS_DEPLOYMENT.md) /
[`CAPSTONE_DEPLOYMENT_STEPS.md`](./CAPSTONE_DEPLOYMENT_STEPS.md).

## Infrastructure

All AWS, free-tier only, one region (`us-east-1`), provisioned by `terraform/`:

| Component | What it is |
|---|---|
| Compute | 1x EC2 `t3.micro` running **k3s** (single-node Kubernetes), Amazon Linux 2023, Elastic IP |
| Network | Custom VPC (`10.42.0.0/16`), 1 public subnet, IGW, no NAT Gateway. Security group: 80/443 in, no inbound SSH |
| Container images | 8 private **ECR** repos (one per deployed service), `IMMUTABLE` tags, lifecycle policy keeps last 10 |
| Deployed services | frontend, userservice, contacts, ledgerwriter, balancereader, transactionhistory, accounts-db, ledger-db (`loadgenerator` excluded — not deployed) |
| Terraform state | S3 bucket `bank-of-anthos-tfstate-490809404878` + DynamoDB table `bank-of-anthos-tf-lock`, created once by `terraform/bootstrap/` (not part of the main stack) |
| Deploy artifacts | S3 bucket holding rendered Kustomize manifests, shuttled from CI to the node |
| Monitoring | CloudWatch agent on the host (mem/swap/cpu/disk metrics + container log tailing), one CloudWatch alarm on memory >90%, SNS email subscription, AWS Budgets alert |
| IAM (node) | EC2 instance role: SSM + CloudWatch agent only. No ECR permissions, IMDS hop limit stays at the safe default (1) |
| IAM (CI) | An existing **admin-access IAM user's static keys** (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` GitHub secrets) — not OIDC. See `terraform/bootstrap/README.md` for the trade-off this implies |

## CI/CD

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yml` | PR → `main`, push → `main` | Stages 1-5: gitleaks, build+unit test, Trivy SCA, Semgrep SAST, Checkov IaC scan |
| `terraform-validate-ci.yaml` | PR/push touching `terraform/**` | `terraform fmt -check` + `terraform validate` (no AWS credentials, no plan) |
| `cd.yml` | push → `main`, or manual `workflow_dispatch` | Stages 6-12: build+scan+push images, `terraform apply`, deploy via SSM (no SSH), OWASP ZAP baseline (report-only) |
| `refresh-ecr-creds.yml` | every 6h, + right after every `cd.yml` deploy | Rewrites the `regcred` image-pull Secret with a fresh ECR token |
| `audit-iam-user.yml` | weekly (Monday), or manual | Reports the CI IAM user's attached/inline policies; warns if `AdministratorAccess` is attached |

`terraform apply` and everything downstream only ever runs on a push to
`main` — never on a PR.

## One-time setup (already done, recorded here so it isn't repeated by accident)

- `terraform/bootstrap` applied once, manually, to create the state bucket/lock table above.
- GitHub repo **secrets**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (the admin IAM user's keys).
- GitHub repo **variables**: `BUDGET_ALERT_EMAIL`, `ALARM_EMAIL` (real email addresses — Terraform validates these are non-empty and email-shaped; SNS also requires confirming a subscription email once, sent to `ALARM_EMAIL` after the first successful apply).

## Operating it

- **Redeploy**: merge to `main`, or run `cd.yml` via `workflow_dispatch`.
- **Access the node**: `aws ssm start-session --target <node_instance_id>` (no SSH key exists for this box).
- **One-time manual step**: the JWT signing key (`jwt-key` k8s Secret) is bootstrapped on the instance itself via `scripts/bootstrap-jwt-secret.sh`, run over SSM — the private key never transits CI. `dast-zap` is skipped until this exists.
- **Reach the app**: `http://<node_public_ip>/` (Elastic IP, from `terraform output node_public_ip`).
