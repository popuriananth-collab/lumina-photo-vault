# ─────────────────────────────────────────────
#  variables.tf — Input variable definitions
# ─────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Name used for all resources (Lambda, ECR repo, IAM role, etc.)"
  type        = string
  default     = "lumina-photo-vault"
}

variable "photos_bucket_name" {
  description = "S3 bucket name for storing photos (must be globally unique)"
  type        = string
  # No default — must be set in terraform.tfvars
}

variable "image_tag" {
  description = "Docker image tag to deploy (updated by CI/CD or deploy script)"
  type        = string
  default     = "latest"
}

variable "secret_key" {
  description = "Flask secret key for session signing"
  type        = string
  sensitive   = true
  # No default — must be set in terraform.tfvars or via env var TF_VAR_secret_key
}

variable "environment" {
  description = "Deployment environment label (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "github_repo" {
  description = "GitHub repo in org/repo format"
  type        = string
}

variable "tf_state_bucket" {
  description = "S3 bucket for Terraform remote state"
  type        = string
}
