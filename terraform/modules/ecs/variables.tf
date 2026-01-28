variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of public subnets for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs of private subnets for ECS tasks"
  type        = list(string)
}

variable "container_image" {
  description = "Docker image URI"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
}

variable "cpu" {
  description = "CPU units for the task"
  type        = number
}

variable "memory" {
  description = "Memory in MiB for the task"
  type        = number
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "db_endpoint" {
  description = "RDS endpoint"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on the ALB"
  type        = bool
  default     = true
}
