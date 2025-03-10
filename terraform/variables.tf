variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-west-2"
}

variable "repository_name" {
  type        = string
  description = "Name of the ECR repository"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the ECR repository"
  default     = {}
}

variable "allowed_principal_arns" {
  type        = list(string)
  description = "List of IAM role/user/account ARNs allowed to push/pull images from the ECR repository"
  default     = ["arn:aws:iam::183585643319:user/webdev"] # Example: ["arn:aws:iam::123456789012:role/my-ecr-role"]
}

variable "default_tags" {
  type        = map(string)
  description = "Default tags to apply to all resources"
  default     = {}
}