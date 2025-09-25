output "cluster_id" {
  description = "EMR cluster ID"
  value       = aws_emr_cluster.cluster.id
}

output "cluster_name" {
  description = "EMR cluster name"
  value       = aws_emr_cluster.cluster.name
}

output "master_public_dns" {
  description = "Public DNS name of the master node"
  value       = aws_emr_cluster.cluster.master_public_dns
}

output "cluster_arn" {
  description = "ARN of the EMR cluster"
  value       = aws_emr_cluster.cluster.arn
}

output "vpc_id" {
  description = "VPC ID (created or existing)"
  value       = local.vpc_id
}

output "subnet_id" {
  description = "Subnet ID (created or existing)"
  value       = local.subnet_id
}

output "security_group_emr_nodes" {
  description = "Master security group ID"
  value       = aws_security_group.emr_nodes.id
}

output "bootstrap_script_s3_uri" {
  description = "S3 URI of the bootstrap script"
  value       = "s3://${var.scripts_bucket}/${aws_s3_object.bootstrap.key}"
}

output "vpc_created" {
  description = "Whether VPC was created by this configuration"
  value       = local.create_vpc
}
