# Architecture

```text
                              AWS Region: ap-south-1
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│   VPC  10.20.0.0/16                                        session19-vpc │
│   ┌────────────────────────────────────────────────────────────────────┐  │
│   │                                                                    │  │
│   │   PUBLIC SUBNET  10.20.1.0/24  (ap-south-1a)                       │  │
│   │   map_public_ip_on_launch = true                                  │  │
│   │   ┌──────────────────┐          ┌────────────────────────┐        │  │
│   │   │ EC2 instance     │          │ NAT Gateway            │        │  │
│   │   │ t3.micro         │          │ + Elastic IP            │        │  │
│   │   │ ami-0e02b35...   │          │ (outbound only)        │        │  │
│   │   │ session19-devops │          └───────────┬────────────┘        │  │
│   │   └────────┬─────────┘                      │                     │  │
│   │            │                        route 0.0.0.0/0 → nat-gw        │  │
│   │   ┌────────┴─────────────────────────┐                            │  │
│   │   │ Security Group  session19-web-sg│  (stateful, per-resource)   │  │
│   │   │   ingress 22  0.0.0.0/0  SSH    │                            │  │
│   │   │   ingress 80  0.0.0.0/0  HTTP   │                            │  │
│   │   │   egress  ALL  0.0.0.0/0         │                            │  │
│   │   └──────────────────────────────────┘                            │  │
│   │                                                                    │  │
│   │   ROUTE TABLE  session19-public-rt                                  │  │
│   │     local 10.20.0.0/16                                              │  │
│   │     0.0.0.0/0  → Internet Gateway        ┌──────────────────┐      │  │
│   │  ───────────────────────────────────────│ Internet Gateway │      │  │
│   │                                          │ session19-igw   │      │  │
│   │   ROUTE TABLE  session19-private-rt       └──────────────────┘      │  │
│   │     local 10.20.0.0/16                                              │  │
│   │     0.0.0.0/0  → NAT Gateway  (outbound only, no inbound)          │  │
│   │                                                                    │  │
│   │   PRIVATE SUBNET 1  10.20.2.0/24  (ap-south-1a)                     │  │
│   │   PRIVATE SUBNET 2  10.20.3.0/24  (ap-south-1b)                     │  │
│   │     map_public_ip_on_launch = false                                 │  │
│   │     ↕ reach the internet for outbound requests via NAT only        │  │
│   └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│   S3 BUCKET  session19-cloud-artifacts                    (global name)  │
│     versioning    = Enabled                                             │
│     public access = blocked (all four flags true)                       │
│     encryption    = AES256 (SSE-S3)                                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Resource count

20 resources in a single `terraform apply`:

| Type | Count | Purpose |
|---|---|---|
| `aws_vpc` | 1 | The network boundary |
| `aws_subnet` | 3 | 1 public + 2 private |
| `aws_internet_gateway` | 1 | Bidirectional internet for the VPC |
| `aws_eip` | 1 | Fixed public IP for the NAT gateway |
| `aws_nat_gateway` | 1 | Outbound-only internet for private subnets |
| `aws_route_table` | 2 | Public (→ IGW) and private (→ NAT) |
| `aws_route` | 2 | The two `0.0.0.0/0` default routes |
| `aws_route_table_association` | 3 | Binds each subnet to a route table |
| `aws_security_group` | 1 | Stateful firewall for the instance |
| `aws_key_pair` | 1 | SSH key pair |
| `aws_instance` | 1 | The web server |
| `aws_s3_bucket` | 1 | Artifact storage |
| `aws_s3_bucket_versioning` | 1 | Object versioning |
| `aws_s3_bucket_public_access_block` | 1 | Public-access hardening |

## What Terraform's dependency graph proves

`terraform graph` renders the edges Terraform uses to order creation. The
important ones:

```text
aws_nat_gateway.main  →  aws_eip.nat
aws_nat_gateway.main  →  aws_internet_gateway.main
aws_nat_gateway.main  →  aws_subnet.public
aws_route.private_nat → aws_nat_gateway.main
aws_route.private_nat → aws_route_table.private
aws_instance.web      → aws_subnet.public
aws_instance.web      → aws_security_group.web
aws_instance.web      → aws_key_pair.devops
aws_subnet.public     → aws_vpc.main
```

Read as "A must exist before B":

- The VPC must exist before any subnet, route table, gateway or security group.
- The NAT gateway cannot be created before its **EIP** exists, and before the
  **internet gateway** is attached — which is why `main.tf` also carries
  `depends_on = [aws_internet_gateway.main]`. Without that, `apply` races and
  fails intermittently with `NatGatewayNotReady`.
- The EC2 instance waits for its subnet, its security group, **and** its key
  pair. Omitting the key pair is the classic
  `InvalidKeyPair.NotFound` failure.

The S3 resources form their own independent chain off `aws_s3_bucket.artifacts`:
nothing in the compute path depends on storage, so Terraform can create the
bucket and the VPC in parallel.