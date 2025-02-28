# AWS ECR Repository Terraform Module

This Terraform module creates an Amazon ECR repository with security best practices.

## Prerequisites

- Terraform v1.0+
- AWS CLI configured
- Appropriate AWS permissions

## Authentication

This module uses the AWS provider's default credential chain, which will check the following sources in order:

1. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
2. Shared credentials file (`~/.aws/credentials`)
3. EC2 instance profile or ECS task role (if running on AWS)

**IMPORTANT: Never hardcode AWS credentials in your Terraform files or commit them to Git!**

## Usage

1. Make sure you have AWS credentials configured:
   ```bash
   # Option 1: Set environment variables
   export AWS_ACCESS_KEY_ID="your_access_key"
   export AWS_SECRET_ACCESS_KEY="your_secret_key"
   export AWS_REGION="us-east-1"
   
   # Option 2: Configure AWS CLI (creates ~/.aws/credentials)
   aws configure
   ```

2. Create a `terraform.tfvars` file (DO NOT COMMIT THIS FILE) with your specific configuration:
   ```hcl
   aws_region = "us-east-1"
   repository_name = "my-springboot-app"
   allowed_aws_account_ids = ["123456789012"]
   ```

3. Initialize and apply the Terraform configuration:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## CI/CD Integration

When using this module in CI/CD pipelines:

- Store AWS credentials as secure environment variables or secrets
- For GitHub Actions, use AWS's official action:
  ```yaml
  - name: Configure AWS credentials
    uses: aws-actions/configure-aws-credentials@v2
    with:
      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      aws-region: us-east-1
  ```

## Variables

See variables.tf for all available options.

## Outputs

- `repository_url`: The URL of the created ECR repository