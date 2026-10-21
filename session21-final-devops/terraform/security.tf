# Security groups and IAM roles.
#
# EKS creates its own control-plane and node security groups automatically, so
# these exist for the workload itself: the database and the API pods.

# ---------- Workload security groups ----------

resource "aws_security_group" "database" {
  name        = "${local.name_prefix}-db"
  description = "PostgreSQL, reachable only from inside the VPC"
  vpc_id      = aws_vpc.main.id

  # Ingress is defined in aws_vpc_security_group_ingress_rule below so it can
  # reference the security group id without creating a cycle.
  tags = {
    Name = "${local.name_prefix}-db"
  }
}

resource "aws_security_group" "application" {
  name        = "${local.name_prefix}-app"
  description = "Application pods running on the EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-app"
  }
}

# PostgreSQL only accepts connections from the application tier.
resource "aws_vpc_security_group_ingress_rule" "database_from_app" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.application.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from the application pods"
}

# The application tier accepts HTTP from anywhere inside the VPC. Traffic from
# the internet reaches it through an Ingress/load balancer, not by allowing
# direct ingress on the pods.
resource "aws_vpc_security_group_ingress_rule" "app_from_vpc" {
  security_group_id = aws_security_group.application.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  description       = "Application HTTP from inside the VPC"
}
