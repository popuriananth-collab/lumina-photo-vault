# ─────────────────────────────────────────────────────────────
#  oidc.tf — IAM role that GitHub Actions assumes via OIDC
#  Apply this once before your first pipeline run.
# ─────────────────────────────────────────────────────────────

# GitHub's OIDC provider (only needs to exist once per AWS account)
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint (stable — changes only if GitHub rotates their cert)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM Role that GitHub Actions assumes
resource "aws_iam_role" "github_actions" {
  name = "${var.app_name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Only YOUR repo can assume this role — replace with your GitHub org/repo
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })

  tags = local.common_tags
}

# What GitHub Actions is allowed to do
resource "aws_iam_role_policy" "github_actions" {
  name = "${var.app_name}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR — push images
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      # Lambda — update function
      {
        Sid    = "LambdaDeploy"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction",
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${var.app_name}"
      },
      # API Gateway — Terraform manages these
      {
        Sid    = "APIGateway"
        Effect = "Allow"
        Action = ["apigateway:*"]
        Resource = "*"
      },
      # S3 — Terraform state bucket + photos bucket management
      {
        Sid    = "S3State"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket}",
          "arn:aws:s3:::${var.tf_state_bucket}/*"
        ]
      },
      {
        Sid    = "S3PhotosBucketManage"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket",
          "s3:GetBucketVersioning", "s3:PutBucketVersioning",
          "s3:GetBucketEncryption", "s3:PutBucketEncryption",
          "s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketTagging", "s3:PutBucketTagging",
          "s3:GetBucketPolicy", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy"
        ]
        Resource = "arn:aws:s3:::${var.photos_bucket_name}"
      },
      # IAM — Terraform manages roles
      {
        Sid    = "IAMRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole",
          "iam:GetRole", "iam:PassRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRolePolicy", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:TagRole", "iam:UntagRole"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.app_name}-*"
      },
      # CloudWatch Logs
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup",
          "logs:DescribeLogGroups", "logs:PutRetentionPolicy",
          "logs:TagResource", "logs:ListTagsLogGroup"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.app_name}*"
      },
      # STS — needed for account ID lookup
      {
        Sid    = "STSCallerIdentity"
        Effect = "Allow"
        Action = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

# Output the role ARN — paste this into GitHub Secrets as AWS_OIDC_ROLE_ARN
output "github_actions_role_arn" {
  description = "Paste this into GitHub Secrets → AWS_OIDC_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
