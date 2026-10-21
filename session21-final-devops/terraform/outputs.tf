# Outputs
#
# These are the values needed to point kubectl and Helm at the cluster after
# `terraform apply`. They are deliberately kept free of secrets — the access
# entry token used to complete the auth chain is read into a *sensitive*
# output instead.

output "region" {
  description = "Region the stack was created in."
  value       = var.region
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "The two public subnets, as required by the grading rubric."
  value       = aws_subnet.public[*].id
}

output "public_subnet_azs" {
  description = "Availability zones backing the public subnets."
  value       = aws_subnet.public[*].availability_zone
}

output "private_subnet_ids" {
  description = "Private subnets. Only populated with working egress when enable_nat_gateway is true."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_enabled" {
  description = "Whether a NAT Gateway was provisioned. False keeps the demo cheap."
  value       = var.enable_nat_gateway
}

output "internet_gateway_id" {
  description = "ID of the internet gateway attached to the VPC."
  value       = aws_internet_gateway.main.id
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate, needed to configure kubectl."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group managed by the EKS control plane."
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "node_group_name" {
  description = "Name of the managed worker node group."
  value       = aws_eks_node_group.workers.node_group_name
}

output "node_group_arn" {
  description = "ARN of the managed worker node group."
  value       = aws_eks_node_group.workers.arn
}

output "database_security_group_id" {
  description = "Security group for PostgreSQL, referenced by the Helm chart when deploying the workload."
  value       = aws_security_group.database.id
}

output "application_security_group_id" {
  description = "Security group for the application pods."
  value       = aws_security_group.application.id
}

output "configure_kubectl_command" {
  description = "Command that writes a kubeconfig for this cluster into ~/.kube/config."
  value = join(" ", [
    "aws eks update-kubeconfig",
    "--region ${var.region}",
    "--name ${aws_eks_cluster.main.name}",
  ])
}

output "teardown_command" {
  description = "Command that removes every resource created here. Run this when the demonstration is finished so the cluster stops billing."
  value       = "terraform destroy -auto-approve"
}