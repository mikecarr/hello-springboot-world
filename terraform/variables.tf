# variables.tf

variable "aws_region" {
  description = "The AWS region in which to create resources"
  type        = string
  default     = "us-west-2"
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "my-springboot-app"
}

variable "allowed_aws_account_ids" {
  description = "List of AWS account IDs that are allowed to access the ECR repository"
  type        = list(string)
  default     = ["183585643319"] # Replace with your actual account IDs
}

variable "tags" {
  description = "A map of tags to apply to the ECR repository"
  type        = map(string)
  default     = {
    Environment = "production"
    Application = "springboot-app"
    Terraform   = "true"
  }
}

# We've removed any AWS credential variables that might have been here