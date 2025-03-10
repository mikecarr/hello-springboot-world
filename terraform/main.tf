# main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # or your preferred version
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.default_tags
  }
}

# Data source to get account ID
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# ECR Resources
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "app_repo" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"  # Or "IMMUTABLE" if you use content-addressable images

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key =  aws_kms_key.ecr_key.arn
    # kms_key_arn     = aws_kms_key.ecr_key.arn # Requires aws_kms_key.ecr_key to be defined
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# KMS Resources
# -----------------------------------------------------------------------------

resource "aws_kms_key" "ecr_key" {
  description             = "KMS key for ECR repository encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "ecr_key_alias" {
  name          = "alias/ecr-${var.repository_name}"
  target_key_id = aws_kms_key.ecr_key.id
}

# KMS Key Policy
# resource "aws_kms_key_policy" "ecr_key_policy" {
#   key_id = aws_kms_key.ecr_key.id   # Requires aws_kms_key.ecr_key to be defined
#   policy = data.aws_iam_policy_document.ecr_key_policy_document.json
# }

# data "aws_iam_policy_document" "ecr_key_policy_document" {
#   statement {
#     sid    = "Enable IAM User Permissions"
#     effect = "Allow"

#     principals {
#       type        = "AWS"
#       identifiers = [ "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" ] # Requires data.aws_caller_identity.current to be defined
#     }

#     actions = [
#       "kms:DescribeKey",
#       "kms:ListAliases",
#       "kms:GetKeyPolicy",
#       "kms:PutKeyPolicy",
#     ]

#     resources = ["*"]
#   }
#   statement {
#     sid    = "Allow Access For ECR Actions"
#     effect = "Allow"

#     principals {
#       type        = "AWS"
#       identifiers = var.allowed_principal_arns  # Modified: Using IAM Roles/Users/Account Ids passed via a variable
#     }

#     actions = [
#       "kms:Encrypt",
#       "kms:Decrypt",
#       "kms:ReEncrypt*",
#       "kms:GenerateDataKey*",
#       "kms:DescribeKey"
#     ]
#     resources = ["*"]
#     condition {
#       test     = "StringEquals"
#       variable = "kms:CallerAccount"
#       values   = [data.aws_caller_identity.current.account_id] # Requires data.aws_caller_identity.current to be defined
#     }
#     condition {
#       test     = "StringEquals"
#       variable = "kms:ViaService"
#       values   = ["ecr.${var.aws_region}.amazonaws.com"]
#     }
#   }
# }

# -----------------------------------------------------------------------------
# IAM Resources
# -----------------------------------------------------------------------------

# IAM Role for ECR Push/Pull
resource "aws_iam_role" "ecr_push_pull_role" {
  name = "ecr-push-pull-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/webdev" # Allow webdev user to assume, requires data.aws_caller_identity
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for ECR Push/Pull Permissions
resource "aws_iam_policy" "ecr_push_pull_policy" {
  name        = "ecr-push-pull-policy"
  description = "Grants permissions to push and pull images to/from ECR repository"
  policy      = data.aws_iam_policy_document.ecr_push_pull_policy_document.json
}

# Data source for the ECR push/pull policy document
data "aws_iam_policy_document" "ecr_push_pull_policy_document" {
  statement {
    sid    = "AllowECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:GetAuthorizationToken" #Crucial for docker login to ECR
    ]
    resources = [aws_ecr_repository.app_repo.arn] # Limit to the specific repo, requires ecr repo defined
  }
  statement {
    sid = "AllowKMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*"
    ]
    resources = [aws_kms_key.ecr_key.arn] # Limit to the KMS key used by ECR., requires kms key to be defined
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id] #Requires data.aws_caller_identity
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ecr.${var.aws_region}.amazonaws.com"]
    }
  }
}

# Attach the ECR push/pull policy to the IAM role
# resource "aws_iam_role_policy_attachment" "ecr_push_pull_role_policy_attachment" {
#   role       = aws_iam_role.ecr_push_pull_role.name
#   policy_arn = aws_iam_policy.ecr_push_pull_policy.arn
# }

# -----------------------------------------------------------------------------
# Modify the ECR Repository Policy to allow the IAM Role
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "app_repo_policy_document" {
  statement {
    sid    = "AllowPushPull"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ecr_push_pull_role.arn]  # Allow IAM Role
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:ListImages", # Add this action
      "ecr:DescribeImages" # Add this action
    ]

    resources = [aws_ecr_repository.app_repo.arn]  # Limit to the repository ARN
  }
}
#KMS Key Policy, add the role

data "aws_iam_policy_document" "ecr_key_policy_document" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [ "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" ] # Allow account owner
    }

    actions = [
      "kms:DescribeKey",
      "kms:ListAliases",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:DeleteAlias",
      "kms:CreateGrant"
    ]

    resources = ["*"]
  }
  statement {
    sid    = "Allow Access For ECR Actions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ecr_push_pull_role.arn] # Modified: Using IAM Role
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:DeleteAlias"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ecr.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_ecr_repository_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name
  policy     = data.aws_iam_policy_document.app_repo_policy_document.json
}

resource "aws_kms_key_policy" "ecr_key_policy" {
  key_id = aws_kms_key.ecr_key.id
  policy = data.aws_iam_policy_document.ecr_key_policy_document.json
}

resource "aws_iam_role_policy_attachment" "ecr_push_pull_role_policy_attachment" {
  role       = aws_iam_role.ecr_push_pull_role.name
  policy_arn = aws_iam_policy.ecr_push_pull_policy.arn
}

resource "aws_ecr_lifecycle_policy" "app_repo_lifecycle_policy" { # Changed name
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

# Output the IAM role ARN
output "ecr_push_pull_role_arn" {
  value = aws_iam_role.ecr_push_pull_role.arn
}