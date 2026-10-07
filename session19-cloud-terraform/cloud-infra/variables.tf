variable "aws_region" {
  type        = string
  description = "AWS region for all resources."
  default     = "ap-south-1"
}

variable "project_name" {
  type        = string
  description = "Name prefix applied to resource tags."
  default     = "session19"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR for the public subnet (hosts EC2 and the NAT gateway)."
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for the private subnets (host internal-only workloads)."
  default     = ["10.20.2.0/24", "10.20.3.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to spread subnets across."
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type."
  default     = "t3.micro"
}

variable "ssh_key_name" {
  type        = string
  description = "Name of the EC2 key pair used for SSH access."
  default     = "session19-devops"
}

variable "root_volume_size" {
  type        = number
  description = "Size in GiB of the EC2 root EBS volume."
  default     = 8
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket created alongside the compute."
  default     = "session19-cloud-artifacts"
}

variable "environment" {
  type        = string
  description = "Environment tag applied to every resource."
  default     = "dev"
}

variable "ami_id" {
  type        = string
  description = "AMI to launch (Amazon Linux 2023 in the default region)."
  default     = "ami-0e02b35e2dd2ee0c5"
}
