#!/bin/bash
# AWS ECR Deployment & Docker Image Push script
set -e

# Configuration - EDIT THESE VARIABLES OR SET ENVIRONMENT VARIABLES
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-123456789012}"
APP_NAME="${APP_NAME:-inventory-app}"

# Derived Variables
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
BACKEND_REPO="${APP_NAME}-backend"
FRONTEND_REPO="${APP_NAME}-frontend"

echo "============================================="
echo "  🚀 AWS ECR Container Image Deployer"
echo "============================================="
echo "AWS Region:     ${AWS_REGION}"
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
echo "Registry URL:   ${ECR_URL}"
echo "============================================="

echo "🔐 Step 1: Authenticating Docker with AWS ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URL}

echo "📦 Step 2: Creating repositories in ECR if they do not exist..."
aws ecr create-repository --repository-name ${BACKEND_REPO} --region ${AWS_REGION} 2>/dev/null || echo "Repo ${BACKEND_REPO} already exists."
aws ecr create-repository --repository-name ${FRONTEND_REPO} --region ${AWS_REGION} 2>/dev/null || echo "Repo ${FRONTEND_REPO} already exists."

echo "🐳 Step 3: Building container images..."
echo "Building backend: ${BACKEND_REPO}:latest"
docker build -t ${BACKEND_REPO}:latest ./backend

echo "Building frontend: ${FRONTEND_REPO}:latest"
docker build -t ${FRONTEND_REPO}:latest ./frontend

echo "🏷️ Step 4: Tagging container images..."
docker tag ${BACKEND_REPO}:latest ${ECR_URL}/${BACKEND_REPO}:latest
docker tag ${FRONTEND_REPO}:latest ${ECR_URL}/${FRONTEND_REPO}:latest

echo "🚀 Step 5: Pushing images to AWS ECR..."
docker push ${ECR_URL}/${BACKEND_REPO}:latest
docker push ${ECR_URL}/${FRONTEND_REPO}:latest

echo "============================================="
echo "🎉 SUCCESS: Images pushed to AWS ECR!"
echo "Backend URI:  ${ECR_URL}/${BACKEND_REPO}:latest"
echo "Frontend URI: ${ECR_URL}/${FRONTEND_REPO}:latest"
echo "============================================="
