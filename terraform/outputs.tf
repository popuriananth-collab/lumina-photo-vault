# ─────────────────────────────────────────────
#  outputs.tf — Values printed after apply
# ─────────────────────────────────────────────

output "app_url" {
  description = "Public URL for the photo vault"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "ecr_repository_url" {
  description = "ECR repository URL (used in docker push)"
  value       = aws_ecr_repository.app.repository_url
}

output "photos_bucket_name" {
  description = "S3 bucket where photos are stored"
  value       = aws_s3_bucket.photos.bucket
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.app.function_name
}
