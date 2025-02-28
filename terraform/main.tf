# main.tf

provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "app_repo" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Optional: Enable encryption with KMS (comment out if not needed)
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr_key.arn
  }

  tags = var.tags
}

# Optional: Create a KMS key for ECR repository encryption
resource "aws_kms_key" "ecr_key" {
  description             = "KMS key for ECR repository encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "ecr_key_alias" {
  name          = "alias/ecr-${var.repository_name}"
  target_key_id = aws_kms_key.ecr_key.key_id
}

# ECR Repository Policy using a more direct string approach
resource "aws_ecr_repository_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name
  
  # Using a template string to create a valid policy document
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPushPull",
      "Effect": "Allow",
      "Principal": {
        "AWS": ${jsonencode([for id in var.allowed_aws_account_ids : "arn:aws:iam::${id}:root"])}
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ]
    }
  ]
}
EOF
}

# Optional: Lifecycle policy to clean up untagged images older than 14 days
resource "aws_ecr_lifecycle_policy" "app_repo_lifecycle" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Remove untagged images older than 14 days",
        selection = {
          tagStatus     = "untagged",
          countType     = "sinceImagePushed",
          countUnit     = "days",
          countNumber   = 14
        },
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2,
        description  = "Keep only 10 images tagged with 'latest'",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["latest"],
          countType     = "imageCountMoreThan",
          countNumber   = 10
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Output the repository URL
output "repository_url" {
  value = aws_ecr_repository.app_repo.repository_url
}