# AWS EC2 - Compute

Amazon Elastic Compute Cloud (EC2) is the foundational compute service: it provides **virtual servers (instances)** on AWS hardware, with configurable CPU, memory, storage, network, and OS. Because it is IaaS rather than PaaS, you own the guest OS, patching, and everything above it - which is exactly what Terraform is usually automating.

EC2 instances live inside a **VPC** (see `04-vpc`). They need a subnet, a route table that lets traffic reach them, a security group, and usually an IAM role. Pricing is per-second (or per-minute for some instance types) with no upfront commitment, and you can use Savings Plans or Reserved Instances for steady-state workloads.

## Instance lifecycle

An instance moves through these states. Knowing them explains most console behaviour, and explains why some operations "hang":

| State | Meaning | Can you stop it? | Data on root volume |
|---|---|---|---|
| `pending` | Launch requested, resources being allocated | No (too early) | N/A |
| `running` | Booted, usable, billing at full rate | Yes | Intact |
| `stopping` | Graceful shutdown in progress | Wait | Intact |
| `stopped` | Halted. Public IP released, instance keeps EBS volumes | Yes | **Intact** |
| `shutting-down` | Termination in progress | No | Depends on setting |
| `terminated` | Deleted. Instance no longer exists | No - **permanent** | Deleted unless `DeleteOnTermination=false` |

Key points:

- **Start/stop preserves EBS volumes.** Stopping an instance releases its public IP address (a different one is assigned on next start), stops billing for compute, and keeps attached EBS volumes and their contents. This makes `stop`/`start` a cheap way to park non-production environments.
- **Terminate is permanent.** The instance ID is gone and cannot be recovered.
- **Whether the root volume survives termination depends on one setting:** the block device mapping's `DeleteOnTermination` attribute, which defaults to `true` for root volumes and `false` for other (non-root) EBS volumes. Setting it to `false` keeps the root volume, and you can re-attach it later or snapshot it first:

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = false
  }
}
```

- **Reboot** restarts the OS but keeps the same host and public IP. It does not count as a stop.
- EBS volumes cannot be moved to a different Availability Zone, so an instance stopped and relaunched may land in a different AZ; plan for that rather than treating it as transparent.

Terraform `create_before_destroy` on an instance (by setting `depends_on` or a distinct `name` on the resource) is worth using when you need zero-downtime replacement, since terminate-then-create causes downtime and - with the default `delete_on_termination = true` - destroys the root disk too.

## AMI

An **Amazon Machine Image (AMI)** is the template used to launch an instance. It captures:

- A root (and optionally additional) EBS volume snapshot, so the OS and all its state as of image creation.
- Pre-installed software, application code, and configuration - this is what makes "Golden Image" or "Packer AMI" workflows possible.
- Launch-time configuration that can be baked in: kernel parameters, `cloud-init`/user data scripts, boot mode (UEFI vs legacy), and the default user / SSH key handling.

Key properties:

| Property | Notes |
|---|---|
| Naming | Region + architecture specific, e.g. `ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*` |
| Region-bound | AMIs are regional; you copy them between regions |
| Architecture-bound | `amd64` and `arm64` AMIs are distinct; EC2 will not launch an `arm64` AMI on an `amd64` instance type |
| Account-bound | Private AMIs are visible only to the owning account until shared |
| Public AMIs | Owned by Canonical, Amazon, or other vendors in the public catalogue |
| Immutability | **AMIs are immutable.** To change an AMI you create a new one from a modified snapshot |

Because they are immutable and region-scoped, you can safely copy a private AMI across regions or accounts and it will not drift afterwards. `CopyImage` is asynchronous, so expect minutes, and the destination AMI launches only after the copy completes.

In Terraform you normally resolve an AMI with a data source filtered on name, owner, and architecture rather than hardcoding the `ami-0...` ID:

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

Using `most_recent = true` means the next `terraform apply` after a new Ubuntu point release can pick up a newer AMI, which is convenient for patching but is a behaviour change worth knowing about in CI.

## Instance types

Instance types are named `family.size`. The family encodes the hardware class, the size encodes the amount of CPU and RAM.

**Family letters:**

| Prefix | Optimised for | Character |
|---|---|---|
| `t` | General purpose, **burstable** | Has CPU credits. Baseline performance is free, sustained use of CPU above baseline depletes credits and incurs charges |
| `m` | General purpose | Balanced, sustained full performance. The default choice for most workloads |
| `c` | Compute optimised | High ratio of vCPU to memory. Good for web servers, game servers, batch, CI |
| `r` | Memory optimised | High ratio of memory to vCPU. Good for caching, in-memory databases, analytics, Elasticsearch/OpenSearch |
| `i` | Storage optimised | High sequential I/O. Good for NoSQL stores, data warehouses |
| `d` | Dense compute | Balanced compute and memory |
| `g` | Graphics | GPU / accelerated workloads |
| `z` | High frequency | Very high clock speed |

**Burstable (`t`) deserves emphasis.** A `t3` instance gets a small baseline share of its vCPUs and accumulates CPU credits at a fixed rate when idle. Running near or above baseline for long periods exhausts the credit bucket, and the instance then runs at baseline performance **and** is billed for the surplus credits. Default `t3.micro` bursting capacity is roughly 12 vCPUs, so a moderately loaded micro can throttle. `t3.unlimited` launches with no credit limit and bills for extra CPU directly, which makes cost unpredictable but performance predictable. For anything that runs continuously at high CPU, use `m` or `c`.

**Size suffixes** are per family: `nano` (sub-1 vCPU), `micro`, `small`, `medium`, `large`, `xlarge`, `2xlarge`, ... each step doubling the previous. `large` is almost always 2 vCPU and 8 GiB of RAM.

**Decoding `t3.large`:**

| Component | Value |
|---|---|
| `t` | General purpose, burstable |
| `3` | Generation 3 (newer silicon + higher baseline burst) |
| `large` | 2 vCPU, 8 GiB memory |

Other common ones: `m5.xlarge` = 4 vCPU / 16 GiB, `c6g.large` = 2 vCPU / 4 GiB on Graviton (`g` = AWS Graviton ARM), `r6i.xlarge` = 4 vCPU / 32 GiB.

A practical decision rule: start with `t3.micro`/`t3.small` or `m6i.large`, measure with CloudWatch, and only then move up a size or family. Naming a larger type than you need is one of the easiest ways to waste budget.

## Key pairs

An EC2 **key pair** is a cryptographic pair used for SSH authentication:

- The **public key** is stored in AWS on the key pair resource and injected into the instance's authorised keys at launch.
- The **private key** is downloaded **once** at creation time and never leaves your machine. AWS does not keep a copy and cannot recover or re-issue it.

In Terraform, `aws_key_pair` does not download a private key (AWS never generated one):

```hcl
resource "aws_key_pair" "web" {
  key_name   = "web-server"
  public_key = file("~/.ssh/id_ed25519.pub")
}

resource "aws_instance" "web" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.micro"
  subnet_id       = aws_subnet.private.id
  key_name        = aws_key_pair.web.key_name
  vpc_security_group_ids = [aws_security_group.web.id]
}
```

Practical points:

- Public key formats: RSA, and the newer ED25519 keys. Plain `ssh-rsa` with SHA-1 has been disabled by most current SSH clients; prefer ED25519 or RSA with SHA-2.
- **SSM Session Manager** is usually preferable, because it removes the private key entirely: no key to distribute or leak, no inbound SSH port, no bastion host, and access is controlled through IAM and CloudTrail. It requires the SSM agent on the instance and IAM permissions for `ssmmessages:*` on the instance.
- With Session Manager you also still need a working network path (or an SSM VPC interface endpoint for private instances).
- Public key baked into an AMI (`ssh_authorized_keys` in `cloud-init`) is a common alternative; the risk is that keys become part of the image and must be rotated by rebuilding.

## Security Groups

A **security group** is a stateful virtual firewall attached to instances (or ENIs, which for a normal instance is effectively the same thing).

Key characteristics:

- **Stateful**: if you send a request out to a host, the response traffic back to the initiating instance is automatically allowed, regardless of inbound rules. You never have to write return rules.
- **Rules are allow-only.** There is no "deny" rule in a security group. To block something you simply do not allow it. (Contrast with network ACLs, which do support explicit deny.)
- **Rules are additive.** Security groups do not have priority. If you attach multiple security groups to one instance, access is allowed if **any** group's rule allows it.
- Each rule has a direction (`ingress` / `egress`), a protocol, a port range, a source/destination (`cidr_blocks`, `ipv6_cidr_blocks`, `prefix_list_ids`, or another **security group** as source), and an optional description.

**Rule evaluation and referenced security groups** are a genuine exam point:

- When a rule's source is another security group (`vpc_security_group_ids` inside an ingress rule), it means "allow traffic from any instance that has that security group attached". The reference is **live**: if you later attach that group to a new instance, that new instance immediately gains the permission. Conversely, if you detach the group from the instance that was the source, access is immediately lost.
- Because there is no deny and rules merge across groups, a widely-used "open" security group referenced by many rules becomes a broad authorisation path. Restricting which groups are referenced is therefore part of least privilege.
- A security group can reference itself, which is how the default security group only allows SSH (and inbound from itself) - see below.

**Default security group:** every VPC comes with one named `default`. It allows **all inbound traffic from resources that have the same security group** (which includes itself), and allows **all outbound traffic**. It does *not* allow SSH from the internet - a very common misconception. Anything you create with no explicit security group gets this one, so always specify `vpc_security_group_ids` in Terraform.

Terraform shape:

```hcl
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Allow HTTPS from the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # referenced SG, not a CIDR
    description     = "HTTPS from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

Note the Terraform anti-pattern this avoids: separate `aws_security_group` resources with inline `ingress`/`egress` and no `name_prefix` will fail to create the second one, because AWS rejects the duplicate rule. If you must inline rules, use distinct `name_prefix` values, or define `aws_vpc_security_group_ingress_rule` / `..._egress_rule` as separate resources.

## EBS

**Amazon Elastic Block Store (EBS)** provides block-level (disk) storage that attaches to instances as a volume.

| Type | Max size | Max IOPS | Throughput | Use |
|---|---|---|---|---|
| `gp2` | 16 TiB | 3,000 | 125 MiB/s | Legacy default; burst performance |
| `gp3` | 16 TiB | 80,000 | 1,000 MiB/s | **Current default.** Provision IOPS/throughput independently; includes 3,000 IOPS and 125 MiB/s baseline |
| `io1` | 16 TiB | 64,000 | 1,000 MiB/s | Provisioned IOPS, consistent low-latency |
| `io2` | 64 TiB | 256,000 | 4,000 MiB/s | Provisioned IOPS, higher durability/latency |
| `st1` | 16 TiB | 500 | 125 MiB/s | Throughput-optimised HDD, sequential workloads (data lake) |
| `sc1` | 16 TiB | 250 | 60 MiB/s | Cold HDD, lowest cost, low IOPS |
| `standard` | 1 TiB | - | - | Magnetic, legacy |

Note the io2 figures above are the documented per-volume limits; io2 Block Express on specific Nitro-based instance types raises the IOPS ceiling considerably.

Key properties:

- **Volume size is independent of instance size.** You can attach a 16 TiB `gp3` volume to a `t3.nano`. The instance type limits network and, for some types, attached volume counts, not volume capacity.
- **AZ-bound.** An EBS volume lives in one Availability Zone and can only attach to instances in that same AZ. Multi-region or cross-AZ designs need replication (EBS Multi-Attach within an AZ, or snapshot copy to another region).
- **EBS Multi-Attach** (io1/io2 only, same AZ) lets you attach the *same* volume read-write to multiple Nitro-based instances. Combine with a cluster-aware filesystem for a shared-write HA setup, e.g. a database or a file server needing a single logical volume with no SPOF.
- **gp3 performance is provisioned, not bursty**, which is why it is recommended over gp2 for predictable databases.
- **Encryption** can be set per volume (`encrypted = true`) or by default with EBS encryption by default at the account/region level.
- **Snapshots** are incremental, crash-consistent, stored in S3, and can be copied across regions and shared across accounts. Crash-consistent means the volume is captured at a single point in time - not a true application-consistent state; for databases you need to quiesce first (`f.flush`/`pg_backup`, freeze, or shut down).

Terraform:

```hcl
resource "aws_ebs_volume" "data" {
  availability_zone = "eu-west-1a"
  type              = "gp3"
  size              = 100
  iops              = 3000
  throughput        = 125
  encrypted         = true
  tags = { Name = "app-data" }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.web.id
}
```

Using a separate `aws_volume_attachment` rather than `ebs_block_device` lets Terraform manage the attachment lifecycle independently of the volume, which matters for reattaching to a replacement instance.

## Public vs private IP addressing

Every instance gets a **private IPv4 address** from its subnet's CIDR range. That address is stable for the life of the instance and is the address everything inside the VPC uses.

A **public IPv4 address** is an internet-routable address assigned from Amazon's public address space. Points that matter:

- **A public IP is not tied to your account.** It is not a fixed piece of IP space you own or rent. Whichever instance holds it at that moment is reachable at it.
- **It is not persistent.** Public IPs are released on stop, on terminate, and on detach/attach of the primary network interface. If you need a stable public address, use an **Elastic IP** - which is allocated to your account in the region and can be reassociated to another instance or interface, and is retained across stop/start.
- **Cost.** Public IPv4 addresses are chargeable; the free tier covers a small allowance of usage. Elastic IPs are not charged while attached to a running instance, but you are billed for an Elastic IP that is *unassociated* for long periods, which encourages deallocating them when idle.
- **How it is assigned**: an instance in a **public subnet** (one whose route table has `0.0.0.0/0 -> igw-...`) that is launched with `associate_public_ip_address = true` (or via an Auto Scaling group setting) receives a public IP. It is not automatic otherwise - in a VPC, `map_public_ip_on_launch` defaults to false for subnets you create. Public subnet plus IGW route alone is not sufficient; the association flag matters.
- **Traffic flow**: outbound from a public-IP instance needs the IGW route; return traffic back is allowed because of the stateful nature of security groups and the fact that the reply matches the session.
- **IPv6** is separate: assign an IPv6 CIDR to the VPC, use `amazon-vpc-assign-ipv6-cidr-blocks-on-creation = true`, and instances get globally routable IPv6 addresses with no charge for the address itself.

Terraform example of the distinction:

```hcl
# Private instance - app tier, no public IP, outbound via NAT Gateway
resource "aws_instance" "app" {
  ami                     = data.aws_ami.ubuntu.id
  instance_type           = "t3.medium"
  subnet_id               = aws_subnet.private.id
  vpc_security_group_ids  = [aws_security_group.app.id]
  iam_instance_profile    = aws_iam_instance_profile.app.name
}

# Public instance - bastion / web server
resource "aws_instance" "bastion" {
  ami                     = data.aws_ami.ubuntu.id
  instance_type           = "t3.micro"
  subnet_id               = aws_subnet.public.id
  vpc_security_group_ids  = [aws_security_group.bastion.id]
  associate_public_ip_address = true
}
```

## Common use cases

**Web servers and load-balanced application tiers.** A fleet of `t3.large`/`m6i.large` instances behind an Application Load Balancer, with the ALB in public subnets and the instances in private subnets, registered to a target group. Combine with an Auto Scaling group, target tracking policies, and Spot Instances for cost. This is the shape most Terraform web-tier examples teach.

**Bastion hosts / jump boxes.** A small instance in a public subnet, reachable only from your corporate IP range (security group source restricted to the office CIDR or your VPN range), with no egress to the internet except via the NAT Gateway. Everything else is in private subnets and reachable only from the bastion's security group. Alternatively, use SSM Session Manager and skip the bastion entirely - fewer moving parts and no SSH keys.

**Batch processing.** EC2 Spot Instances in an Auto Scaling group against a queue (SQS) or a scheduler, with a checkpointing job design so interruption is survivable. Spot gives up to 90% discount in exchange for possible 2-minute interruption notices. Fleet or capacity-optimised allocation types spread capacity and reduce the risk of a whole batch stalling.

**Self-hosted CI runners.** A Spot-based Auto Scaling group of runners registered to GitLab/GitHub Actions/ Jenkins, launched in private subnets with a NAT Gateway for outbound package and registry access, and an instance profile for AWS permissions (push to ECR, read secrets). Ephemeral runners that are destroyed after each job avoid state leakage between pipelines.

**Also worth knowing:** EC2 Spot and On-Demand underpin a lot of managed services you will meet later - Lambda's underlying compute, RDS's serverless/instance classes, ECS Fargate's host instances, and EKS node groups all reduce to EC2 capacity underneath. Knowing EC2 well makes the managed services easier to reason about, and makes it clear when "just use EC2" is genuinely the better fit.
