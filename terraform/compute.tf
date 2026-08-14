# Amazon Linux 2023 — ships with SSM Agent and cloud-init preinstalled,
# free-tier eligible, and supported on t3.micro/t3.small.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "node" {
  name = "${var.project_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM Session Manager / Run Command access (this is how CI deploys — no SSH key).
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent needs to publish custom metrics + logs.
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# No ecr:* grant on the node role: nothing here mints ECR tokens via IMDS.
# .github/workflows/refresh-ecr-creds.yml does that instead, using the same
# IAM user's static keys as the rest of the pipeline, and pulls images using
# the resulting `regcred` Secret's embedded bearer token directly —
# kubelet/containerd never touches the node's IAM role for that. Keeping ECR
# permissions off the node role means a compromised pod that somehow reached
# IMDS still couldn't touch ECR *through the node role* — that's a real,
# narrow win, but don't read it as bounding overall blast radius: the same
# GitHub secrets that authenticate refresh-ecr-creds.yml are a static,
# admin-access IAM user's keys (see terraform/bootstrap/README.md), which is
# a far larger and longer-lived exposure than anything scoped to this node.

resource "aws_iam_instance_profile" "node" {
  name = "${var.project_name}-node-profile"
  role = aws_iam_role.node.name
}

resource "aws_instance" "node" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.node.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  root_block_device {
    # 30GB, not less: the Amazon Linux 2023 AMI's backing snapshot requires a
    # root volume >= its own size (AWS rejects anything smaller with
    # InvalidBlockDeviceMapping), and that snapshot has grown to exactly the
    # free tier's 30GB ceiling. This uses the full free-tier EBS allowance —
    # there's nothing else on this stack that needs EBS, so that's fine, but
    # it means there's no headroom left for an additional volume without
    # incurring cost.
    volume_size = 30 # GB — the free-tier EBS ceiling, not "well within" it
    volume_type = "gp3"
    encrypted   = true
  }

  # hop_limit stays at the safe default (1): only the host network namespace
  # can reach IMDS, no pod on this node can. An earlier version raised this
  # to 2 so an in-cluster CronJob could reach IMDS to mint ECR tokens — but
  # that meant EVERY pod on the node (including the internet-facing,
  # DAST-scanned app services) could also reach IMDS and assume the node's
  # full IAM role, not just the intended one. Moving credential refresh to
  # .github/workflows/refresh-ecr-creds.yml (authenticated with the IAM
  # user's static keys, no IMDS) removed the need for any pod to reach IMDS
  # at all, so this could revert
  # to the safe default instead of trying to scope hop_limit's blast radius
  # down (which isn't possible — it's a whole-instance setting). http_tokens
  # stays "required" regardless, enforcing IMDSv2 (blocks the plain-HTTP-GET
  # SSRF path IMDSv1 allows) even for the host itself.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region = var.aws_region
  })

  # user_data changes should reprovision the node deliberately, not on every
  # unrelated apply.
  user_data_replace_on_change = true

  tags = { Name = "${var.project_name}-node" }
}

resource "aws_eip" "node" {
  instance = aws_instance.node.id
  domain   = "vpc"
  tags     = { Name = "${var.project_name}-eip" }
}
