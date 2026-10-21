variable "region" {
  description = "AWS region to build the stack in. us-east-1 is the default demo region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix applied to resource names and tags."
  type        = string
  default     = "taskboard"
}

variable "environment" {
  description = "Environment label used in tags and resource names."
  type        = string
  default     = "demo"

  validation {
    condition     = contains(["demo", "staging", "production"], var.environment)
    error_message = "environment must be one of: demo, staging, production."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones used for the subnets. Pinned explicitly so validate/plan work without AWS credentials; override for another region."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 2
    error_message = "Provide at least two availability zones, or leave the list empty to auto-select the first two."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "taskboard-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane. Left empty so the provider picks the current default."
  type        = string
  default     = ""
}

variable "node_instance_types" {
  description = <<-EOT
    EC2 instance types for the worker node group.

    t3.small is a small, free-tier-eligible default that keeps the demo cluster
    inexpensive. Raise this for a production cluster.
  EOT
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Create a NAT Gateway so nodes in private subnets can reach the internet.

    A NAT Gateway costs roughly USD 0.045/hour plus per-GB data charges, which
    is the single most expensive line item in this stack. It defaults to false:
    nodes run in public subnets instead, which keeps the demo cheap and is
    acceptable for a throwaway cluster. Set it to true for anything resembling
    a real deployment.
  EOT
  type        = bool
  default     = false
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint to the internet."
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR ranges permitted to reach the EKS API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_cidr_blocks) > 0
    error_message = "At least one CIDR block must be allowed to reach the API endpoint."
  }
}