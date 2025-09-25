variable "project_name" {
  description = "Name prefix for all tags"
  type        = string
  default     = "spark-tpcds-benchmark"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "release_label" {
  description = "EMR release label - keep in sync with Spark version"
  type        = string
  default     = "emr-7.9.0"
}

variable "log_bucket" {
  description = "Existing S3 bucket for EMR logs"
  type        = string
  default     = "your-s3-bucket-name"
}

variable "scripts_bucket" {
  description = "Bucket where bootstrap script is uploaded"
  type        = string
  default     = "your-s3-bucket-name"
}

variable "ssh_key_name" {
  description = "Pre-created EC2 key pair"
  type        = string
  default     = "your-ssh-key-name"
}

# VPC-related variables with enhanced validation
variable "existing_vpc_id" {
  description = "ID of existing VPC to use. If not provided, a new VPC will be created"
  type        = string
  default     = null
}

variable "existing_subnet_id" {
  description = "ID of existing subnet to use. Required if existing_vpc_id is provided"
  type        = string
  default     = null

  validation {
    condition     = (var.existing_vpc_id == null && var.existing_subnet_id == null) || (var.existing_vpc_id != null && var.existing_subnet_id != null)
    error_message = "Both existing_vpc_id and existing_subnet_id must be provided together, or both must be null."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for new VPC (only used when creating new VPC)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for new subnet (only used when creating new subnet)"
  type        = string
  default     = "10.20.0.0/24"
}

variable "master_instance_type" {
  description = "Instance type for master node"
  type        = string
  default     = "c7gd.2xlarge"
}

variable "core_instance_type" {
  description = "Instance type for core nodes"
  type        = string
  default     = "c7gd.2xlarge"
}

variable "core_instance_count" {
  description = "Number of core instances"
  type        = number
  default     = 1
}

variable "task_instance_type" {
  description = "Instance type for task nodes"
  type        = string
  default     = "c7i.xlarge"
}

variable "task_instance_count" {
  description = "Number of task instances (0 = no TASK group)"
  type        = number
  default     = 0
}

variable "runtime_variant" {
  description = "JVM runtime variant"
  type        = string
  default     = "default"
  validation {
    condition     = contains(["zulu", "zing", "default"], var.runtime_variant)
    error_message = "Runtime variant must be either 'zulu','zing' or 'default' for EMR Java"
  }
}

variable "custom_tar_url" {
  description = "Override download URL for custom RPM"
  type        = string
  default     = ""
}

locals {
  default_tar_urls = {
    # Replace these URLs with your own JVM distribution URLs
    # For Azul Zulu, you can download from: https://www.azul.com/downloads/#downloads-table-zulu
    # For Azul Zing, contact Azul Systems for access
    zulu    = "https://your-repository.com/path/to/zulu-jdk17-linux_aarch64.tar.gz"
    zing    = "https://your-repository.com/path/to/zing-jdk17-linux_aarch64.tar.gz"
    default = ""
  }

  tar_url = var.custom_tar_url != "" ? var.custom_tar_url : local.default_tar_urls[var.runtime_variant]

  # SAFE: Determine whether to create new VPC resources
  # This ensures existing resources are NEVER in terraform state, so NEVER destroyed
  create_vpc = var.existing_vpc_id == null && var.existing_subnet_id == null

  # SAFE: VPC and subnet references - only reference created resources when they exist
  vpc_id    = local.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id
  subnet_id = local.create_vpc ? aws_subnet.public[0].id : var.existing_subnet_id
}
