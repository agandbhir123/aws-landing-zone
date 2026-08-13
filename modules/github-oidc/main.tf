terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# GitHub's OIDC identity provider. Registering this ONE TIME lets GitHub
# Actions workflows in ANY repo assume AWS roles without ever storing an
# AWS access key as a GitHub secret. The workflow proves its identity with a
# short-lived signed token from GitHub itself, verified against this
# provider's thumbprint.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # GitHub's OIDC thumbprint. AWS validates the provider's TLS cert chain
  # against this - it rarely changes, but if GitHub ever rotates their
  # intermediate CA, this value would need to be updated.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

# ---------------------------------------------------------------------------
# The role CI assumes. Trust policy is scoped to ONE specific GitHub repo
# (not "any repo in my org") via the `sub` claim condition - this is the
# part that actually matters for security. Without the StringLike condition
# scoping the repo, ANY GitHub Actions workflow anywhere could assume this
# role and touch your AWS account.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_actions_ci" {
  name = "github-actions-terraform-ci"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Restricts to this exact repo. The `*` after the colon allows
            # any branch/PR/tag from that repo, but no other repo can match.
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Purpose = "github-actions-ci"
  }
}

# ---------------------------------------------------------------------------
# Permissions: read-only across the board, plus write access ONLY to the
# Terraform state bucket and lock table. CI can plan and see drift, but it
# cannot apply changes - that stays a manual, human-run step from a local
# machine. This is a deliberate, defensible choice for a personal project:
# CI catches "does this even parse and what would it do" on every PR,
# without handing a CI pipeline the keys to modify a live AWS Organization.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.github_actions_ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "terraform_state_access" {
  name = "TerraformStateAccess"
  role = aws_iam_role.github_actions_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.tfstate_bucket_name}",
          "arn:aws:s3:::${var.tfstate_bucket_name}/*"
        ]
      },
      {
        Sid    = "StateLockTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/${var.tflock_table_name}"
      }
    ]
  })
}
