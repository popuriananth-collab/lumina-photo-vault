# ─────────────────────────────────────────────────────────────
#  main.tf — Lumina Photo Vault infrastructure
#  Resources: ECR, Lambda, API Gateway, S3, IAM
# ─────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Optional: store state remotely so your team can share it
  # Uncomment and set your bucket name after first apply
  backend "s3" {
    bucket = "lumina-tf-state-anarch-adheera"
    key    = "lumina/terraform.tfstate"
    region = "us-east-1"
    }
}

provider "aws" {
  region = var.aws_region
}

# ── Data ─────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  ecr_image  = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.app_name}:${var.image_tag}"
}

# ── S3 — Photos bucket ────────────────────────────────────────
resource "aws_s3_bucket" "photos" {
  bucket        = var.photos_bucket_name
  force_destroy = false # safety: won't delete bucket if photos exist

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "photos" {
  bucket = aws_s3_bucket.photos.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "photos" {
  bucket = aws_s3_bucket.photos.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "photos" {
  bucket                  = aws_s3_bucket.photos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── ECR — Container registry ──────────────────────────────────
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

# Auto-clean old images — keep only the last 5
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ── IAM — Lambda execution role ───────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "${var.app_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "${var.app_name}-s3-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.photos.arn
      },
      {
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.photos.arn}/*"
      }
    ]
  })
}

# Allow Lambda to write CloudWatch logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── CloudWatch — Log group ────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.app_name}"
  retention_in_days = 30
  tags              = local.common_tags
}

# ── Lambda — Function ─────────────────────────────────────────
resource "aws_lambda_function" "app" {
  function_name = var.app_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = local.ecr_image
  timeout       = 30
  memory_size   = 256

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.photos.bucket
      SECRET_KEY     = var.secret_key
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_logs,
  ]

  tags = local.common_tags
}

# ── API Gateway — HTTP API ────────────────────────────────────
resource "aws_apigatewayv2_api" "app" {
  name          = "${var.app_name}-api"
  protocol_type = "HTTP"
  tags          = local.common_tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.app.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.app.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.app.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.lambda.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = local.common_tags
}

# Allow API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.app.execution_arn}/*"
}

locals {
  common_tags = {
    Project     = var.app_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
