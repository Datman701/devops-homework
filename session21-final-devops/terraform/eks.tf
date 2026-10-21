# EKS control plane and a managed worker node group.
#
# Built with the standalone aws_eks_cluster / aws_eks_node_group resources
# rather than the community Terraform EKS module. The module pulls in a large
# dependency tree for this project, and writing the two resources directly
# keeps the CloudFormation trust policy visible — which matters for a resource
# that is expensive to create and must be destroyed cleanly.

# ---------- Cluster IAM role: EKS needs a trust policy ----------

data "aws_iam_policy_document" "eks_cluster_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_trust.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------- Node group IAM role ----------

data "aws_iam_policy_document" "node_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodes" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_trust.json
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}

# ---------- Cluster ----------

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version != "" ? var.kubernetes_version : null

  vpc_config {
    subnet_ids              = var.enable_nat_gateway ? concat(aws_subnet.private[*].id, aws_subnet.public[*].id) : aws_subnet.public[*].id
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = true
  }

  # Access entries are an API-level feature and are ignored unless the cluster's
  # authentication mode includes API. The default for a new cluster is CONFIG_MAP
  # only, under which CreateAccessEntry fails with InvalidRequestException. This
  # must be set at creation time (or an in-place update before any access entry
  # is created).
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"

    # Exported explicitly. It defaults to true, but leaving it unset makes the
    # provider read null against a real true and mark the cluster for
    # replacement on every plan.
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Name = var.cluster_name
  }
}

# ---------- Worker node group ----------

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-workers"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.enable_nat_gateway ? aws_subnet.private[*].id : aws_subnet.public[*].id

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Nodes need to pull the container images built by CI, so give them read
  # access to the registry. The GHCR packages are public, but pinning this
  # explicitly makes the dependency obvious if they ever stop being.
  update_config {
    max_unavailable = 1
  }

  # Node labels. Do not use kubernetes.io/, k8s.io/ or eks.amazonaws.com/ here:
  # those prefixes are reserved and CreateNodegroup rejects the whole request if
  # any label starts with one.
  labels = {
    "taskboard.io/tier" = "worker"
  }

  tags = {
    Name = "${var.cluster_name}-workers"
  }

  depends_on = [aws_iam_role_policy_attachment.nodes]
}

# ---------- Access entries ----------
#
# Replaces the removed aws-auth ConfigMap: registers the node role with the
# cluster, then grants it the built-in admin policy. The policy association is
# a separate resource in AWS provider v5 — aws_eks_access_entry has no nested
# policy_associations block.

resource "aws_eks_access_entry" "nodes" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.nodes.arn
  type          = "EC2_LINUX"
}

resource "aws_eks_access_policy_association" "nodes" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.nodes.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_iam_role_policy_attachment.nodes]
}