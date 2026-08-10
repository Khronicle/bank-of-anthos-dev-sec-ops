# One private repo per deployed service (loadgenerator is excluded — not
# deployed, see CAPSTONE_DEVSECOPS_DEPLOYMENT.md for why).
locals {
  services = [
    "frontend",
    "userservice",
    "contacts",
    "accounts-db",
    "ledger-db",
    "ledgerwriter",
    "balancereader",
    "transactionhistory",
  ]
}

resource "aws_ecr_repository" "service" {
  for_each = toset(local.services)

  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true # belt-and-suspenders alongside the Trivy scan in CI
  }
}

# Free tier is 500MB-month per account for 12mo — keep it that way by not
# accumulating every build's images forever.
resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
