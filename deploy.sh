#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  deploy.sh — Build → Push to ECR → Terraform apply
#  Run from the photo_viewer/ root directory
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# ── Config ────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-us-east-1}"
APP_NAME="${APP_NAME:-lumina-photo-vault}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
# ─────────────────────────────────────────────────────────────

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Lumina Deploy"
echo "  Region:  $AWS_REGION"
echo "  Image:   $ECR_URL:$IMAGE_TAG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Terraform init + apply (creates ECR repo first) ───
echo ""
echo "▶ Step 1/4 — Provisioning infrastructure (Terraform)..."
cd terraform
terraform init -input=false
# Apply only ECR first so we have a repo to push to
terraform apply -target=aws_ecr_repository.app -auto-approve -input=false
cd ..

# ── Step 2: Build Docker image ────────────────────────────────
echo ""
echo "▶ Step 2/4 — Building Docker image..."
docker build --platform linux/amd64 -t "${APP_NAME}:${IMAGE_TAG}" .

# ── Step 3: Push to ECR ───────────────────────────────────────
echo ""
echo "▶ Step 3/4 — Pushing image to ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker tag "${APP_NAME}:${IMAGE_TAG}" "${ECR_URL}:${IMAGE_TAG}"
docker push "${ECR_URL}:${IMAGE_TAG}"

# ── Step 4: Full Terraform apply ──────────────────────────────
echo ""
echo "▶ Step 4/4 — Deploying all remaining resources..."
cd terraform
terraform apply -auto-approve -input=false \
  -var="image_tag=${IMAGE_TAG}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Deployment complete!"
echo ""
terraform output app_url
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
