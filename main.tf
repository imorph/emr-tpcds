terraform {
  required_version = ">= 1.12.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC and Networking (only created when not using existing VPC)
resource "aws_vpc" "main" {
  count                = local.create_vpc ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Project     = var.project_name
    Department  = "Engineering"
    Product     = "Spark-Benchmarking"
    Environment = "Development"
    Lifetime    = "8 Days"
    Owner       = "user@example.com"
    Team        = "Performance"
    ManagedBy   = "Terraform"
  }
}

resource "aws_internet_gateway" "main" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name        = "${var.project_name}-igw"
    Project     = var.project_name
    Department  = "Engineering"
    Product     = "Spark-Benchmarking"
    Environment = "Development"
    Lifetime    = "8 Days"
    Owner       = "user@example.com"
    Team        = "Performance"
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "public" {
  count                   = local.create_vpc ? 1 : 0
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Project     = var.project_name
    Department  = "Engineering"
    Product     = "Spark-Benchmarking"
    Environment = "Development"
    Lifetime    = "8 Days"
    Owner       = "user@example.com"
    Team        = "Performance"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table" "public" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Project     = var.project_name
    Department  = "Engineering"
    Product     = "Spark-Benchmarking"
    Environment = "Development"
    Lifetime    = "8 Days"
    Owner       = "user@example.com"
    Team        = "Performance"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "public" {
  count          = local.create_vpc ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

# Security Group for EMR Master and Slave nodes
resource "aws_security_group" "emr_nodes" {
  name_prefix = "${var.project_name}-emr-nodes"
  vpc_id      = local.vpc_id

  # This prevents the hanging destroy issue
  revoke_rules_on_delete = true

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Spark UIs
  ingress {
    from_port   = 4040
    to_port     = 4099
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # YARN UI
  ingress {
    from_port   = 8088
    to_port     = 8088
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Hadoop Web UIs
  ingress {
    from_port   = 9870
    to_port     = 9870
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All internal cluster communication (self-reference)
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  # All egress traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-emr-nodes-sg"
    Project     = var.project_name
    Department  = "Engineering"
    Product     = "Spark-Benchmarking"
    Environment = "Development"
    Lifetime    = "8 Days"
    Owner       = "user@example.com"
    Team        = "Performance"
    ManagedBy   = "Terraform"
  }
}

# Separate Security Group for EMR Service Access
resource "aws_security_group" "emr_service_access" {
  name_prefix = "${var.project_name}-emr-service"
  vpc_id      = local.vpc_id

  # This prevents the hanging destroy issue
  revoke_rules_on_delete = true

  # EMR service communication from nodes
  ingress {
    from_port       = 9443
    to_port         = 9443
    protocol        = "tcp"
    security_groups = [aws_security_group.emr_nodes.id]
  }

  # All egress for AWS service communication
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-emr-service-sg"
    Project     = var.project_name
    Department  = "Engineering"
    Product     = "Spark-Benchmarking"
    Environment = "Development"
    Lifetime    = "8 Days"
    Owner       = "user@example.com"
    Team        = "Performance"
    ManagedBy   = "Terraform"
  }
}



# IAM Service Role
resource "aws_iam_role" "emr_service_role" {
  name = "${var.project_name}-emr-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "elasticmapreduce.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-emr-service-role"
    Project     = var.project_name
    Department  = "Engineering"
    Product     = "Spark-Benchmarking"
    Environment = "Development"
    Lifetime    = "8 Days"
    Owner       = "user@example.com"
    Team        = "Performance"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "emr_service_role_policy" {
  role       = aws_iam_role.emr_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

# IAM EC2 Role
resource "aws_iam_role" "emr_ec2_role" {
  name = "${var.project_name}-emr-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-emr-ec2-role"
    Project     = var.project_name
    Department  = "Engineering"
    Product     = "Spark-Benchmarking"
    Environment = "Development"
    Lifetime    = "8 Days"
    Owner       = "user@example.com"
    Team        = "Performance"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "emr_ec2_role_policy" {
  role       = aws_iam_role.emr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}

# S3 access policy for buckets
resource "aws_iam_role_policy" "emr_s3_policy" {
  name = "${var.project_name}-emr-s3-policy"
  role = aws_iam_role.emr_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.log_bucket}",
          "arn:aws:s3:::${var.log_bucket}/*",
          "arn:aws:s3:::${var.scripts_bucket}",
          "arn:aws:s3:::${var.scripts_bucket}/*"
        ]
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "emr_ec2_profile" {
  name = "${var.project_name}-emr-ec2-profile"
  role = aws_iam_role.emr_ec2_role.name

  tags = {
    Name        = "${var.project_name}-emr-ec2-profile"
    Project     = var.project_name
    Department  = "Engineering"
    Product     = "Spark-Benchmarking"
    Environment = "Development"
    Lifetime    = "8 Days"
    Owner       = "user@example.com"
    Team        = "Performance"
    ManagedBy   = "Terraform"
  }
}

# Bootstrap script upload
resource "aws_s3_object" "bootstrap" {
  bucket = var.scripts_bucket
  key    = "${var.project_name}/bootstrap-${var.runtime_variant}.sh"
  content = templatefile("${path.module}/bootstrap.sh.tpl", {
    tar_url         = local.tar_url
    runtime_variant = var.runtime_variant
  })
  content_type = "text/plain"

  tags = {
    Name           = "${var.project_name}-bootstrap-script-${var.runtime_variant}"
    Project        = var.project_name
    RuntimeVariant = var.runtime_variant
    Department     = "Engineering"
    Product        = "Spark-Benchmarking"
    Environment    = "Development"
    Lifetime       = "8 Days"
    Owner          = "user@example.com"
    Team           = "Performance"
    ManagedBy      = "Terraform"
  }
}


locals {
  configurations_map = {
    "zulu" = [
      {
        "Classification" : "spark-defaults",
        "Properties" : {
          "spark.executorEnv.JAVA_HOME" : "/opt/azul-jdk",
          "spark.yarn.appMasterEnv.JAVA_HOME" : "/opt/azul-jdk"
        }
      },
      {
        "Classification" : "hadoop-env",
        "Configurations" : [
          {
            "Classification" : "export",
            "Properties" : {
              "JAVA_HOME" : "/opt/azul-jdk"
            }
          }
        ],
        "Properties" : {}
      },
      {
        "Classification" : "spark-env",
        "Configurations" : [
          {
            "Classification" : "export",
            "Properties" : {
              "JAVA_HOME" : "/opt/azul-jdk"
            }
          }
        ],
        "Properties" : {}
      }
    ]

    "zing" = [
      {
        "Classification" : "spark-defaults",
        "Properties" : {
          "spark.executorEnv.JAVA_HOME" : "/opt/azul-jdk",
          "spark.yarn.appMasterEnv.JAVA_HOME" : "/opt/azul-jdk",
          "spark.sql.codegen.useIdInClassName" : "false",
          "spark.sql.codegen.cache.maxEntries" : "9999"
        }
      },
      {
        "Classification" : "hadoop-env",
        "Configurations" : [
          {
            "Classification" : "export",
            "Properties" : {
              "JAVA_HOME" : "/opt/azul-jdk"
            }
          }
        ],
        "Properties" : {}
      },
      {
        "Classification" : "spark-env",
        "Configurations" : [
          {
            "Classification" : "export",
            "Properties" : {
              "JAVA_HOME" : "/opt/azul-jdk"
            }
          }
        ],
        "Properties" : {}
      }
    ]

    "default" = [
      {
        "Classification" : "spark-defaults",
        "Properties" : {
          "spark.sql.codegen.useIdInClassName" : "false",
          "spark.sql.codegen.cache.maxEntries" : "9999"
        }
      }
    ]
  }
}

# EMR Cluster
resource "aws_emr_cluster" "cluster" {
  name          = "${var.project_name}-cluster"
  release_label = var.release_label
  applications  = ["Spark", "Hadoop"]

  ec2_attributes {
    key_name                          = var.ssh_key_name
    subnet_id                         = local.subnet_id
    emr_managed_master_security_group = aws_security_group.emr_nodes.id
    emr_managed_slave_security_group  = aws_security_group.emr_nodes.id
    service_access_security_group     = aws_security_group.emr_service_access.id
    instance_profile                  = aws_iam_instance_profile.emr_ec2_profile.arn
  }

  master_instance_group {
    instance_type = var.master_instance_type
  }

  core_instance_group {
    instance_type  = var.core_instance_type
    instance_count = var.core_instance_count
  }

  log_uri      = "s3://${var.log_bucket}/${var.project_name}/logs/"
  service_role = aws_iam_role.emr_service_role.arn

  bootstrap_action {
    path = "s3://${var.scripts_bucket}/${aws_s3_object.bootstrap.key}"
    name = "Install Azul ${title(var.runtime_variant)} JVM"
  }

  # Variant-specific Spark configuration
  configurations_json = jsonencode(lookup(local.configurations_map, var.runtime_variant, local.configurations_map["default"]))
  # configurations_json = var.runtime_variant != "default" ? jsonencode(local.configurations_map[var.runtime_variant]) : null

  depends_on = [aws_s3_object.bootstrap]

  tags = {
    Name           = "${var.project_name}-emr-cluster-${var.runtime_variant}"
    Project        = var.project_name
    RuntimeVariant = var.runtime_variant
    Department     = "Engineering"
    Product        = "Spark-Benchmarking"
    Environment    = "Development"
    Lifetime       = "8 Days"
    Owner          = "user@example.com"
    Team           = "Performance"
    ManagedBy      = "Terraform"
  }
}

# Task Instance Group (conditional)
resource "aws_emr_instance_group" "task" {
  count          = var.task_instance_count > 0 ? 1 : 0
  cluster_id     = aws_emr_cluster.cluster.id
  instance_type  = var.task_instance_type
  instance_count = var.task_instance_count
  name           = "task"
}
