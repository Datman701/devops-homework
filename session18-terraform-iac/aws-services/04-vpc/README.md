# AWS VPC - Networking

Amazon Virtual Private Cloud (VPC) is the networking foundation for every EC2 instance, RDS instance, Elastic Load Balancer, and most other AWS compute and database services you launch. A VPC is a **logically isolated virtual network** inside a region, with its own address space, routing, and firewalls. Nothing can reach it from the internet unless you explicitly open a path.

Key framing facts:

- **A VPC is regional.** It exists in one region. There is no global VPC. Multi-region means multiple VPCs plus peering or Transit Gateway between them.
- **The default VPC is created automatically** the first time you visit a region. It comes with a public subnet in every AZ, a route table with a `0.0.0.0/0 -> igw-...` route, and a security group that allows all traffic *between* its members and all outbound.
- **You are not obliged to use the default VPC.** In production you almost always create your own with a deliberate CIDR, no public IPs by default, and tight rules. That way you know exactly what is in it.

## CIDR

A VPC is defined by a **CIDR block** - a range of IPv4 addresses written in `a.b.c.d/prefix` form. AWS supports IPv4 CIDRs between **/16 and /28**.

Because VPC subnets must not overlap, you pick a supernet big enough to carve into subnets for every AZ and tier:

```hcl
resource "aws_vpc" "main" {
  cidr_block                       = "10.0.0.0/16"
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true
}
```

`enable_dns_support` (on by default) allows instances to resolve the Amazon-provided DNS server at `169.254.169.253` plus the VPC resolver at the base +2/+3 addresses. `enable_dns_hostnames` additionally gives instances public DNS hostnames (required for some features, and for load balancers to register instances by name). `assign_generated_ipv6_cidr_block` adds a unique `/56` IPv6 range from Amazon's pool.

**The 5 reserved IPs per subnet.** AWS reserves five addresses in every subnet, so a `/24` subnet (256 addresses) gives you 251 usable:

| Reserved address | Why |
|---|---|
| `.0` | Network address (standard networking convention) |
| `.1` | Router - the VPC router / NAT device |
| `.2` | VPC DNS resolver |
| `.3` | Amazon-provided DNS server (future use / DHCP option set) |
| `.255` | Broadcast address (for subnet IPv4; this is the last address) |

This is why you should not try to use every address; the "only 4 usable in a /29" surprise (8 minus 5 = 3, plus AWS counts it as 3) is a common exam detail.

IPv6 subnets get a `/64` from the VPC's `/56` and AWS reserves only the `::0/64` network address.

```hcl
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-a"
    Tier = "public"
  }
}
```

Note `map_public_ip_on_launch`: in a VPC, subnets you create default this to `false`, so an instance in a public subnet still gets **no** public IP unless you set it or launch with `associate_public_ip_address = true`.

## Subnets

A **subnet** is a segment of the VPC's address range, and it is **tied to exactly one Availability Zone**. That single fact drives the entire design pattern: **you choose an AZ by choosing which subnet you place something in**.

- **Subnet size range:** IPv4 CIDR between **/28 and /16**.
- You cannot change a subnet's CIDR after creation. Terraform's `cidr_block` on `aws_subnet` therefore forces replacement on change, and since AWS will not let you delete a subnet that still has ENIs in it, resizing a subnet requires draining the resources first. This is why a well-planned CIDR (`10.0.0.0/16` with `/24` or smaller subnets) matters.
- Each subnet gets its own route table (unless you explicitly share one) and its own Network ACL.
- Subnets in the same AZ **can** talk to each other locally via the VPC `local` route - no IGW or NAT required.
- Subnets in **different AZs** can also communicate, but they traverse the VPC router, and (for some traffic) inter-AZ data transfer charges apply.

Typical AZ layout for a two-tier app in three AZs:

| Subnet | CIDR | AZ | Contains |
|---|---|---|---|
| public-a | 10.0.1.0/24 | eu-west-1a | ALB, NAT GW, bastion |
| public-b | 10.0.2.0/24 | eu-west-1b | ALB, NAT GW |
| public-c | 10.0.3.0/24 | eu-west-1c | ALB, NAT GW |
| private-app-a | 10.0.11.0/24 | eu-west-1a | EC2 app servers |
| private-app-b | 10.0.12.0/24 | eu-west-1b | EC2 app servers |
| private-app-c | 10.0.13.0/24 | eu-west-1c | EC2 app servers |

Because private-app-a is in the same AZ as public-a, an ALB in public-a talks to it without cross-AZ data transfer charges. This "keep tiers AZ-aligned" principle is worth internalising.

## Route tables

A **route table** controls what a subnet can reach. Each subnet has exactly one route table, and every subnet in the same route table shares the same routing.

| Route type | Behaviour |
|---|---|
| **Local route** | `10.0.0.0/16 -> local`. **Always present**, cannot be removed or overridden. All subnets in the VPC reach each other regardless of route tables |
| **Internet Gateway route** | `0.0.0.0/0 -> igw-...`. Makes the subnet *public* |
| **NAT Gateway route** | `0.0.0.0/0 -> nat-...`. Makes the subnet *private* but able to make outbound calls |
| **VPC peering route** | `10.1.0.0/16 -> pcx-...` to a peered VPC |
| **Transit Gateway route** | `10.2.0.0/16 -> tgw-...` |
| **VPC endpoints route** | `com.amazonaws.<region>.s3 -> vpce-...`, keeps traffic on AWS backbone |

**Main vs custom route tables:**

- Every VPC has an implicit **main route table**. Subnets you create with no explicit `route_table_id` use it.
- The main route table cannot be deleted and starts with only the local route.
- The **default VPC's** main route table already contains the `0.0.0.0/0 -> igw` route, which is why instances in the default VPC get internet access by default. In your own VPC, the main route table has **no** IGW route by default, so nothing is public until you add one.
- Custom route tables let you create layered tiers: public subnets share one, private subnets share another.

**Route evaluation is longest prefix match.** AWS picks the route whose destination prefix is the most specific match for the packet's destination. So with `10.0.0.0/16 -> local` and `0.0.0.0/0 -> igw`, traffic to `10.0.1.5` takes the local route and traffic to `8.8.8.8` takes the IGW. If you add `10.0.11.0/24 -> nat-xyz`, traffic to that subnet goes to the NAT gateway instead - because `/24` is more specific than `/16`.

Two consequences:

- A **more specific route overrides a less specific one**, in either direction. You can carve exceptions out of a default route this way.
- **Routes are bidirectional in effect for return traffic** - AWS removes return entries automatically, symmetrically. You do not need return routes.

An important subtlety: **a route table cannot block traffic**, it can only send it somewhere. A `0.0.0.0/0 -> igw` route makes everything in that subnet internet-*routable*. What actually prevents unwanted access is the security group. This is why "my subnets have a route to the internet, aren't they public?" has the answer "a subnet is only public in the meaningful sense if its instances also have public IP addresses - the route enables outbound, the public IP enables inbound."

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}
```

Terraform (AWS provider v4/v5) requires a separate `aws_route` resource per destination rather than an inline `route` block on `aws_route_table`, and each needs a distinct `route_table_id` + `destination_cidr_block` combination or you get a duplicate-route error.

## Internet Gateway

An **Internet Gateway (IGW)** is a VPC-attached, horizontally scalable, redundant virtual router that provides **bidirectional** connectivity between the VPC and the internet.

- **Only one IGW per VPC.** Not one per AZ - AWS handles the redundancy for you.
- The IGW is not a NAT device and is not a firewall; it exists purely to bridge to and from the internet.
- **A route to the IGW is what makes a subnet public.** Adding an IGW to a VPC does nothing on its own. You must add `0.0.0.0/0 -> igw-...` to the route table attached to the subnets you want to be public.
- **Inbound from the internet still requires a public IP address on the instance** and a permissive security group. The IGW route alone will not deliver unsolicited traffic to a private-IP-only instance - AWS drops it.
- Outbound traffic from a public-IP instance goes to the IGW; stateful return traffic comes back without needing an inbound rule.

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}
```

Use `gateway_id` for an IGW, `nat_gateway_id` for a NAT Gateway, `vpc_peering_connection_id`, `transit_gateway_id`, `network_interface_id`, or `egress_only_internet_gateway_id` for other target types - they are mutually exclusive fields on the same resource.

## NAT Gateway

A **NAT Gateway** (the AWS-managed form is a NAT *Gateway*; the EC2 feature called NAT instances is a different, self-managed thing) lets instances **without a public IP address initiate outbound connections to the internet**, while **preventing unsolicited inbound connections**. It is an Elastic Network Interface in a public subnet with an Elastic IP, plus a managed gateway that does the translation.

The mechanics:

- Route `0.0.0.0/0 -> nat-...` from the private subnet's route table.
- The NAT Gateway itself must live in a **public subnet** and own an **Elastic IP**, because that is the address the internet replies to. It forwards the translated request on behalf of the private instance.
- **Return traffic works automatically** because the NAT Gateway tracks the connection mapping.
- **Inbound from the internet is impossible** with no Elastic IP pointing at it, no inbound rule on the security group, and no port forwarding. That asymmetry is the whole point: private instances can download packages, call APIs, and reach the internet, but cannot be reached.
- **Reaching an instance through a NAT Gateway is not possible.** You need SSH over SSM Session Manager, or a bastion host with an Elastic IP, or a VPN/Direct Connect path.

Cost model - this is worth knowing before building an architecture around NAT:

| Component | Charge |
|---|---|
| NAT Gateway processing | Charged per hour, **per NAT Gateway** |
| Data processing | Charged per GB processed, **in each direction** |
| Elastic IP | No charge while attached to a NAT Gateway |
| Data transfer out to internet | Standard internet data transfer rates |

So NAT is charged **per instance-hour**, not per GB. Three NAT gateways (one per AZ) costs roughly triple one, and that is the deliberate trade-off: one NAT GW per AZ avoids cross-AZ charges for the traffic but pays for the extra gateways. The common middle ground is one NAT Gateway per AZ in production for resilience, accepting the hourly cost, because a single NAT Gateway in one AZ is an AZ-level single point of failure.

```hcl
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.main]
}
```

The `depends_on` is not optional decoration. Terraform creates resources in parallel, and a NAT Gateway needs the IGW already attached to the VPC or creation fails with a `DependencyViolation`.

For IPv6-only outbound you need an **Egress-only Internet Gateway** instead - a NAT Gateway does not translate IPv6. And if instances only need to reach S3 or DynamoDB, VPC endpoints are cheaper and keep traffic off the internet entirely.

## Security Groups

Covered in detail in `02-ec2`; the networking-relevant summary:

- **Stateful**, per-resource, attached to instances or ENIs.
- **Allow-only**, no explicit deny. Rules are additive across all groups attached to one instance, and the most permissive matching rule wins.
- A rule can reference another security group as its source, and that reference is **live** - attaching the referenced group to a new resource immediately grants access, detaching it revokes it.
- The default security group allows all inbound traffic **from itself**, and all outbound. Not from the internet.
- Applied at the **instance/interface level**, and evaluated after routing.

**How security groups combine with route tables** - the distinction that makes networking click:

| | Route table | Security group |
|---|---|---|
| Scope | Subnet-level | Instance / ENI level |
| Direction | Controls **path/reachability** between subnets | Controls **access to specific instances** |
| Can it block? | No - only routes traffic somewhere | Yes, by omission (no allow rule = no access) |
| Is a matching route enough for connectivity? | **No** - you also need the SG rule | Yes, assuming a route exists |

Both are required. A request must pass **both**: AWS first decides whether a route exists that can carry the traffic to the destination, and then whether security groups permit it. If there is no route, packets are dropped and security groups never get a say. If a route exists but no SG rule allows it, the traffic is also dropped. This is why "I added a security group rule and it does not work" is often a missing route table entry, and "I added a route and it does not work" is often a missing SG rule.

## Network ACLs

A **Network ACL (NACL)** attaches to a **subnet** and filters traffic by IP address, port, and protocol. The properties that distinguish it from a security group:

| Property | Security Group | Network ACL |
|---|---|---|
| Level | Instance / ENI | Subnet |
| Stateful | **Yes** | **No** |
| Rules | Allow only | **Allow and explicit deny** |
| Evaluation | Any matching allow wins; no order | **Lowest rule number first**, first match wins, all rules evaluated until a match |
| Applies to | Live on attach/detach | Changes apply to all resources in the subnet |
| Rule limit | No practical limit | 40 inbound + 40 outbound rules total, across all NACLs |

Being stateless means you must allow **both** directions explicitly - the return traffic is not implicitly allowed. Being rule-numbered and having explicit deny means a NACL can be a blunt but precise instrument: `rule 100 deny 0.0.0.0/0` at the bottom acts as a default deny, and a lower-numbered `allow` punches specific holes above it.

**Why layer both.** They solve different problems and neither replaces the other:

- **NACLs** are the coarse, subnet-wide control. They let you say "deny all inbound from the internet except from my office range to port 443", or blackhole a spoofed source range, without needing to visit every instance.
- **Security groups** are the fine-grained, per-resource control that can reference other security groups - which NACLs cannot do. This is why you model "the app tier may talk to the DB tier" as an SG reference; you cannot express that in a NACL without enumerating IPs.
- **NACLs protect the subnet as a whole**, so they still apply to resources created inside it later, which is useful for defence in depth against misconfigured security groups.

The cost of NACLs is real: stateless means duplicated rules, rule numbering is easy to get wrong, and the 40-rule limit is easy to hit with many ports. In most well-designed architectures the NACL keeps the default `allow all` rule and the security groups do the work. Use NACLs when you need an explicit subnet-level deny or IP-based blocking.

## Public vs private subnet

The concrete definition - this is exactly what an exam wants:

- A **public subnet** is one whose route table contains a route to an **Internet Gateway**: `0.0.0.0/0 -> igw-...`. Its instances can have public IP addresses and can be reached from the internet if their security groups allow it.
- A **private subnet** is one whose route table contains a route to a **NAT Gateway** (or a VPN/Direct Connect gateway, or a VPC endpoint) instead of an IGW: `0.0.0.0/0 -> nat-...`. Its instances have no public IP, cannot be reached from the internet, but can make outbound requests through the NAT.

In other words, "public" means "has a route out to the IGW"; "private" means "has no IGW route". The presence of a public IP on an instance is a separate fact that determines reachability.

### Two-tier layout (most common)

```
                    Internet
                        │
             ┌──────────┴──────────┐
             │   Internet Gateway  │
             └──────────┬──────────┘
                        │ 0.0.0.0/0
        ┌───────────────┴───────────────┐
        │     Route table: PUBLIC       │
        └───────┬───────────────┬───────┘
                │               │
    ┌───────────┴──────┐  ┌─────┴──────────┐
    │  public-a /24    │  │  public-b /24  │
    │  eu-west-1a      │  │  eu-west-1b    │
    │  ┌────────────┐  │  │                │
    │  │ ALB :443   │  │  │                │
    │  │ NAT GW     │  │  │                │
    │  └────────────┘  │  │                │
    └───────────┬──────┘  └─────┬──────────┘
                │  local route   │
        ┌───────┴───────────────┴───────┐
        │   Route table: PRIVATE        │
        │   0.0.0.0/0 -> NAT GW         │
        └───────┬───────────────┬───────┘
                │               │
    ┌───────────┴──────┐  ┌─────┴──────────┐
    │ private-app-a/24 │  │ private-db-a/24│
    │  eu-west-1a      │  │  eu-west-1a    │
    │  ┌────────────┐  │  │  ┌──────────┐  │
    │  │ EC2 app    │◄─┼──┼──│ RDS      │  │
    │  │ (no pub IP)│  │  │  │ (SG:5432)│  │
    │  └────────────┘  │  │  └──────────┘  │
    └──────────────────┘  └────────────────┘
```

Flow in this design: inbound HTTPS from the internet hits the IGW, reaches the ALB in a public subnet (which has a public IP), the ALB forwards to the app instances over HTTP on port 80/8080 in private subnets - reachable because of the local route and a security group referencing the ALB's SG. The app instances make outbound calls (package repos, external APIs) via the NAT Gateway. Nobody can initiate a connection to the app instances or the RDS instance from the internet. The DB subnets often have no `0.0.0.0/0` route at all - not even a NAT - so they are fully isolated except for local and peered routes.

### Three-tier layout (with a DMZ / isolated tier)

```
              Internet
                  │
        ┌─────────┴─────────┐
        │   Internet GW     │
        └─────────┬─────────┘
                  │ 0.0.0.0/0
    ┌─────────────┴─────────────┐
    │   PUBLIC subnet tier      │   Route: 0.0.0.0/0 -> IGW
    │   ALB, NAT GW, WAF       │
    └─────────────┬─────────────┘
                  │ local route, SG-referenced
    ┌─────────────┴─────────────┐
    │   APP subnet tier         │   Route: 0.0.0.0/0 -> NAT GW
    │   EC2 app, ECS, EKS      │
    └─────────────┬─────────────┘
                  │ local route, SG-referenced
    ┌─────────────┴─────────────┐
    │   DATABASE (isolated)     │   Route: local only, NO default route
    │   RDS, ElastiCache,       │   Not addressable from the app tier
    │   DynamoDB VPC endpoint    │   except by security group
    └───────────────────────────┘
```

The distinction between tier 2 and tier 3 is not just naming: the database tier has **no default route at all**, so there is no NAT and no IGW path. It is genuinely unreachable outbound to the internet and inbound from it. Data must leave it via the app tier. This is the layout to reach for when a compliance requirement forbids the database ever having an internet path.

Each AZ repeats all three tiers, and keeping tiers AZ-aligned avoids inter-AZ data transfer charges. Cross-AZ is used deliberately for the Multi-AZ database standby and for one NAT Gateway per AZ.

### Supporting pieces worth knowing

- **VPC endpoints** (Gateway endpoints for S3 and DynamoDB; interface endpoints for everything else) let you reach AWS services privately over the AWS backbone instead of the internet. No NAT Gateway, no IGW route, no public IPs. There is an hourly per-endpoint charge for interface endpoints and a per-GB charge, but often cheaper than NAT plus data transfer.
- **VPC peering** connects two VPCs for private routing, works within and across regions (and across accounts, if the other side accepts), and is **not transitive** - if A peers with B and B peers with C, A cannot reach C. Transit Gateway is the transitive alternative.
- **Network Firewall** for VPC-level L3/L7 filtering and intrusion detection; **Flow Logs** published to CloudWatch or S3 for observability and VPC Flow Logs-based path analysis.
- **Reachability Analyzer** answers questions like "can this SG reach that SG" by actually analysing the routing and rules - a useful sanity check before deploying.
