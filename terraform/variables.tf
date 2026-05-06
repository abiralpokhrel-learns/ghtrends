variable "project_name" {
  description = "Used as prefix for all resource names and as a tag value"
  type        = string
  default     = "ghtrends"
}

variable "env" {
  description = "Deployment environment (dev, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name to use"
  type        = string
  default     = "ghtrends"
}
