# AWS DynamoDB & RDS - Database Services

Two of the most commonly confused AWS services, and the pair that comes up most often in interviews: **DynamoDB** (NoSQL) and **RDS** (relational). They are not competitors so much as answers to different questions - DynamoDB for single-key, high-scale, schemaless access patterns; RDS for multi-row transactions, joins, and SQL.

---
---

# Part A - DynamoDB

## What is DynamoDB (NoSQL)?

**NoSQL** means "not relational" - there is no fixed table schema, no `JOIN`, and no ACID transaction across multiple records. Data is stored as documents (JSON-like attribute maps) that you can write without declaring the fields in advance, so different items in the same table may have different attributes.

**Amazon DynamoDB** is a fully managed, **serverless** key-value and document database:

- **Fully managed** - AWS provisions and operates the storage, replication, and failover. There is no server to size, patch, or reboot.
- **Serverless** - there is nothing to run. You create a table (or on-demand capacity) and start calling `PutItem` / `GetItem` / `Query` / `Scan`. You can stop paying by deleting the table.
- **It scales by partition.** This is the crucial architectural fact. DynamoDB physically partitions your keyspace into **partitions**, each with its own throughput ceiling. Scaling is achieved by distributing data across more partitions, not by making a single partition bigger.
- It is a multi-AZ, multi-Region service with on-demand or provisioned capacity, and it supports automatic (or opt-in) global replication across Regions.
- Strongly consistent reads are available, though they cost double in on-demand mode and consume twice the read capacity in provisioned mode.

## Tables

A **table** is the top-level container. Its properties:

- **Region-bound** (unless you use global tables, which replicate a table across Regions).
- Has a name, a **primary key**, and a capacity mode.
- Items are addressed only through the primary key (or a GSI/LSI, see below).
- Has **no declared schema**: no columns, no types, no `ALTER TABLE`. Attributes are whatever JSON you put in the item.
- Supports single-AZ or global (multi-AZ) tables; **global tables** replicate to additional Regions for multi-Region reads and writes, with the last-writer-wins conflict resolution for concurrent writes.

Two kinds of secondary index exist, both needed because DynamoDB can only query on the primary key:

| Index | Key composition | Notes |
|---|---|---|
| **Local Secondary Index (LSI)** | Same partition key, **different** sort key | Max 5 per table, same Region as the table |
| **Global Secondary Index (GSI)** | **Different** partition key, optional sort key | Unlimited per table, can be in a different Region, own capacity |

An index is a full, maintained copy of the projected attributes - it costs extra storage and write throughput. Every write to the table propagates to every index, which is a real cost of denormalising your access patterns.

## Items

An **item** is one record - effectively one JSON document.

- Maximum **400 KB** per item. Item collections (all items sharing a partition key) have a **10 GB** limit.
- Attributes are `name: value` pairs, where value is a string, number, binary, boolean, null, or a set or map of those. **Nested maps and lists are allowed**, up to 32 levels deep.
- Sparse attributes are normal: an item need not have the same attributes as its neighbours. If two items in a table disagree about a number's type, DynamoDB stores both, but this breaks sorting and conditional expressions - keep types consistent.
- Every item **must** contain the primary key attributes. An item missing any part of the key is rejected with `ValidationException`. This is not optional.

Example item:

```json
{
  "customer_id": "C-10245",
  "order_date": "2026-02-14",
  "order_id": "O-8871",
  "status": "SHIPPED",
  "total": 149.99,
  "currency": "USD",
  "items": [
    { "sku": "SKU-3311", "qty": 2 },
    { "sku": "SKU-9002", "qty": 1 }
  ],
  "notes": "Leave at side door"
}
```

## Attributes

Attributes are the typed key-value fields inside an item. Points that matter in practice:

- **Attribute names** are the unique case-sensitive strings that key the document; they are not declared anywhere ahead of time.
- **Key attributes** (partition key, sort key) have type and naming constraints, and their names are part of your schema contract even though the table itself is schemaless.
- DynamoDB **does not enforce uniqueness or referential integrity** for non-key attributes. There is no foreign key, no `NOT NULL`, no `CHECK`. Constraints on non-key data are your application's responsibility.
- If a sort key is numeric it sorts numerically; if it is a string it sorts **lexicographically by UTF-8 bytes**, which is why timestamps must be zero-padded ISO 8601 strings (`2026-02-14`) rather than anything looser.
- Number precision is capped at 38 digits; exceeding it is rejected. Binary and number types cannot be mixed for the same key.

## Partition key

The **partition key** is the primary key component that decides which partition - which physical slice of storage - an item lives in. `Query` and all index operations are scoped to a single partition.

This is the single most important design decision in DynamoDB, and the reason is a hard AWS limit: **each partition is limited to 1,000 WCU and 1,000 RCU per second** (a WCU = 1 KB write, an RCU = 4 KB eventually-consistent read; 1 KB consistent read = 2 RCU). Exceed it and requests to that partition get throttled with `ProvisionedThroughputExceededException`, regardless of how much capacity the table has overall. This is called a **hot partition**.

**Choosing a bad partition key concentrates all traffic on one partition, which caps your throughput at the per-partition ceiling no matter what you provision.** Choosing a well-distributed key lets you scale linearly.

The core heuristic: **the partition key should have high cardinality and an even, unpredictable write distribution.**

| Partition key | Cardinality | Result |
|---|---|---|
| `timestamp` or `created_at` | Low | **Bad.** Every write in the same second or minute lands in the same partition - writes cluster and a hot partition forms instantly. Scans and queries are unusable for anything time-agnostic |
| `status` or `country` (few values) | Very low | **Bad.** A handful of partitions, each capped at 1,000 WCU |
| Random UUID | High, but random | Acceptable for uniform load; terrible for any query needing to find related items |
| `customer_id` | High | **Good**, provided no single customer generates enough traffic to saturate a partition |

## Sort key

The **sort key** (also called the range key) is the optional second primary key component. It organises items **within a partition** and gives you efficient range and "top N" queries.

Characteristics:

- Items with the same partition key but different sort keys can be ordered and range-scanned; items with different partition keys are never compared.
- `Query` on `(PK, SK)` can do: `BETWEEN` a range, `<`, `>`, `begins_with`, and `LIMIT n` for "latest n" - all served by a single read request with no full-table scan.
- A table without a sort key is effectively a pure key-value store; `Query` becomes an exact-match lookup.

## Partition key + sort key in practice

**Good composite key: `customer_id` (partition key) + `order_date` (sort key), for order history.**

Why it works:

- Cardinality is high on the partition side - customers are numerous and no single customer dominates traffic in normal retail.
- All of one customer's orders sit in **one partition**, in date order. `Query` with `KeyConditionExpression: "customer_id = :c AND order_date BETWEEN :from AND :to"` returns exactly the customer's orders in a date range.
- `ordersByCustomer` index (PK `customer_id`, SK `order_date`) is not needed - it *is* the table key. No GSI, no extra write cost.
- This is a genuine single-table design: the same partition can hold the customer, their orders, and their addresses as items distinguished by sort key prefixes, so a single query fetches a whole aggregate without a join.

A common refinement is an entity-typed sort key - `SK = "ORDER#2026-02-14"` versus `SK = "PROFILE"` - so one partition holds multiple item types and `begins_with("ORDER#")` selects among them. `customer_id` + `order_id` with a separate GSI on `order_id` is also common when orders must be fetched directly by order ID.

**Bad key: `timestamp` as the partition key.**

Why it fails:

- Cardinality is effectively 1 per unit of time. All writes in the same second hit the same partition and share the 1,000 WCU ceiling.
- A busy system throttles as soon as one second's write rate exceeds the per-partition limit.
- It forces `Scan` for anything that does not specify an exact timestamp - reading one customer's history becomes a full-table scan, which is slow, expensive, and unreliable at scale.
- With a UUID or single-field numeric counter it is no better: a counter is strictly serialised through one partition.

The fix in both cases: **keep the timestamp as the sort key, not the partition key.** Ordering by time is exactly what a sort key is for; distributing load is exactly what a partition key is for. Conflating the two is the classic DynamoDB design error.

Terraform, which is why this doc sits in a Terraform session:

```hcl
resource "aws_dynamodb_table" "orders" {
  name         = "orders"
  billing_mode = "PAY_PER_REQUEST" # on-demand

  attribute {
    name = "customer_id"
    type = "S"
  }
  attribute {
    name = "order_date"
    type = "S" # ISO 8601 string, zero-padded, sorts lexicographically
  }

  hash_key  = "customer_id"
  range_key = "order_date"

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true # KMS key; SSE is always on
  }

  tags = { Name = "orders" }
}
```

Note that only **key** attributes need `attribute` blocks. In Terraform's provider you declare them so the schema is stable and GSIs can reference them; non-key attributes are schema-free by design. `billing_mode = "PAY_PER_REQUEST"` means on-demand - for provisioned mode you would add `read_capacity`/`write_capacity` plus the autoscaling resources.

## Read/write capacity modes

| | On-demand (`PAY_PER_REQUEST`) | Provisioned |
|---|---|---|
| Pricing | Per request; roughly ~2x the provisioned rate | Per hour for the provisioned capacity, regardless of use |
| Scaling | Automatic, instant, effectively unlimited per table | Manual, or automatic via Application Auto Scaling / CloudWatch alarms |
| Capacity config | None | `read_capacity` / `write_capacity` |
| Provisioned warm / free tier | - | 20 WCU + 80,000 RCU per month across the account (a legacy benefit, keeps accruing) |

**Capacity units**, so the numbers mean something:

| Unit | Definition |
|---|---|
| **WCU** | 1 `PutItem` / `UpdateItem` / `DeleteItem` per second, up to 1 KB. Above 1 KB costs 2 WCU (up to 2 KB), and so on in KB-sized steps |
| **RCU** | One 4 KB eventually-consistent read per second. A 4 KB strongly consistent read costs 2 RCU. Above 4 KB it costs in 4 KB steps |

Guidance: start **on-demand** to discover real traffic, then switch to provisioned with autoscaling if steady-state traffic is predictable and high enough to justify the discount. Also remember there are **service quotas** on on-demand maximums per table and per account.

Finally, the "everything is a document" framing: DynamoDB is not only a key-value store. `GetItem` can return a `Document` type you can use as a JSON object directly, and the Java/Python/JS SDKs map documents to native types. But it remains a document database with **no cross-item joins and no multi-item ACID transactions** (there is `TransactWriteItems` for up to 100 coordinated single-item operations, but that is a constrained batch API, not SQL transactions, and it cannot join two items).

## DynamoDB use cases

**Key-value sessions.** Store a session record keyed by `session_id` (or `user_id` + `token`), with a TTL attribute for automatic expiry, and enable DynamoDB Accelerator (DAX) in front if microsecond latency is needed. Perfect fit: single-key lookup, no joins, expiring naturally.

**IoT and telemetry.** Devices write readings at high volume. Partition by device ID plus a time-range sort key, or by a hashed device bucket to spread very hot devices across partitions. High write throughput, schemaless payload that varies by firmware version, and TTL for retention. This is a standard IoT pattern.

**Low-latency gaming leaderboards.** A composite key of `game_id` (partition key) + `player_id` (sort key) with a GSI on `score` as the sort key and partition key `game_id`. `Query` the GSI with `score` in descending order and `Limit: 10` for a top-10 board - served from an index without scanning. DynamoDB is the documented approach for real-time leaderboards because the read is a single request.

**Other solid fits:** session/state stores, feature flags and configuration, low-traffic catalogues, cart contents, chat message history, and event/audit logs with TTL.

**Why you would NOT use DynamoDB for it:**

- **Relational joins.** Getting a customer's details *and* their orders *and* the product names requires multiple round trips or a denormalised single-table model. In SQL this is one `SELECT` with three `JOIN`s.
- **Multi-row ACID transactions.** No atomic update across arbitrary rows. DynamoDB's `TransactWriteItems` is limited to 100 items and each operation touches a single item; it is not a general transaction manager.
- **Referential integrity and constraints.** Nothing enforces that `customer_id` points at a real customer. The application must.
- **Ad-hoc analytical queries.** Complex aggregations, joins, and reporting are painful. Route those to Athena over S3, or Redshift.
- **Deep, unpredictable schema relationships.** If your data model is inherently a graph or a relational model with many-to-many relationships, a relational database is the right tool.

The heuristic: **if your access patterns are known, bounded, and mostly single-key lookups, DynamoDB. If you need joins, transactions, and ad-hoc SQL, RDS.**

---
---

# Part B - RDS

## What is RDS (Relational Database)?

**Amazon Relational Database Service (RDS)** is a **managed relational database**. AWS runs the database engine process, the storage, the patching, the backups, and the failover - you connect a SQL client to the endpoint and use SQL.

The contrast with DynamoDB is the whole point:

| | RDS | DynamoDB |
|---|---|---|
| Model | Relational, fixed schema, tables with rows and columns | Schemaless documents |
| Query language | SQL, `JOIN`, `GROUP BY`, subqueries | `GetItem`/`Query` by key only; `Scan` with filters |
| Transactions | Full ACID across rows | Limited `TransactWriteItems` (100 items, single-item operations) |
| Integrity | Constraints, foreign keys, unique indexes | None |
| Scaling | Vertical (bigger instance) + horizontal (read replicas) | Horizontal by partition, automatic |
| Operating model | A server you connect to; instance-based billing per hour + storage | Serverless per request |
| Best for | Transactional systems, reporting, anything relational | Single-key access patterns at very high scale |

Because RDS is a managed *instance*, it is a fundamentally different deployment model: you get a hostname and port, you must plan capacity, and you handle connection pooling, failover awareness, and maintenance windows.

## Supported engines

| Engine | Versions | Notes |
|---|---|---|
| **PostgreSQL** | 13-17 | Open source. Strong extensions (PostGIS, `pg_stat_statements`), well regarded as the default choice for new work |
| **MySQL** | 5.7, 8.0, 8.4 | Open source, InnoDB only in RDS |
| **MariaDB** | 10.x, 11.x | Open source MySQL fork, drop-in compatible |
| **Oracle** | 19c, 21c, 23ai | Commercial, licence-inclusive or BYOL. Enterprise features, heavier footprint |
| **SQL Server** | 2016-2022, Web/Standard/Enterprise editions | Commercial; licensed per edition |
| **SQL Server Enterprise** | As above, Enterprise edition | Higher baseline memory and features, notably Always On support |
| **Db2** | 11.5, and IBM Db2 variants | Commercial, for legacy IBM workloads and migrations |
| **Aurora** | Aurora PostgreSQL-Compatible, Aurora MySQL-Compatible | AWS's own engine - see below |

**Aurora is RDS-compatible but a different engine tier.** You create it through the RDS API (`aws rds create-db-cluster`) and manage it with RDS tools, but it is not a stock engine build:

- **Storage-separated architecture.** Aurora separates compute from a distributed, shared, six-copy storage layer. The storage auto-extends in 10 GB increments with no downtime, up to 128 TB.
- **Six copies across three AZs**, self-healing, with three copies of each write plus a write-ahead log.
- **Up to 15 low-latency read replicas** (versus 5 for other engines), and replicas share the cluster's storage, so a replica needs no separate copy.
- **Faster failover** than other engines, with the writer promoted in roughly under a minute.
- **Backtrack** - you can rewind the whole cluster to any point in the past 35 days.
- **Global Database** for multi-Region replication with a read-only secondary Region and fast RPO.

So "is Aurora RDS?" - it is provisioned, monitored, backed up, and fenced by RDS, but the engine, storage architecture, and scaling model are Aurora's own. For most new AWS workloads the choice is "RDS PostgreSQL or Aurora PostgreSQL", not "RDS or Aurora".

## DB instances

A **DB instance** is a running database server with its own storage, its own endpoint, and its own compute class.

Components of an instance you configure:

- **Engine and version**
- **DB instance class** - the compute sizing
- **Storage type and size** - provisioned
- **Storage autoscaling** - grows automatically to a ceiling
- **Multi-AZ** flag
- **Publicly accessible** flag - which should stay `false` almost always
- **Backup retention period** (0-35 days)
- **VPC, subnet group, security groups**
- **IAM database authentication** flag
- **Parameter group** - engine configuration
- **Option groups / DB cluster** for features
- **Certificate, maintenance window, enhanced monitoring**

**DB instance classes.** The naming is `db.<family><generation>.<size>`, mirroring EC2:

| Class | Character | Use |
|---|---|---|
| `db.t3.micro` / `small` / `medium` | **Burstable**, CPU credits, includes the **free tier** (750 h/month of `db.t3.micro`) | Dev, test, personal projects |
| `db.m6g` / `m7g` | General purpose, Graviton ARM | Balanced, most production workloads |
| `db.r6g` / `r7g` | Memory optimised | Large result sets, caching layers |
| `db.c6g` / `c7g` | Compute optimised | Heavy queries, complex reporting |
| `db.x1` / `x2iedn` | Memory extreme | Very large in-memory datasets |
| `db.z1d` | High frequency | CPU-sensitive, low latency |

`db.t3` burstable behaviour is worth calling out: it has a baseline CPU performance and accumulates credits when idle. A database that is busy continuously will deplete credits and then run at baseline performance **while being billed for the extra credits** - a bad fit for sustained production load. A database that sits idle between requests - which is exactly what a dev instance looks like - benefits enormously.

**Storage:**

| Type | Max size (general purpose) | Max IOPS | Throughput | Notes |
|---|---|---|---|---|
| **gp2** | 16 TiB | 3,000 | 125 MiB/s | Legacy default, burst performance, 20% baseline credit |
| **gp3** | 16 TiB (64 TiB on some engines/classes) | 80,000 | 4,000 MiB/s | **Current default.** Set IOPS and throughput independently, baseline 3,000 IOPS / 125 MiB/s. More free IOPS and throughput than gp2 at the same price |
| **io1** | 16 TiB | 64,000 | 1,000 MiB/s | Provisioned IOPS, consistent low latency, storage ratio 1:1 - 50:1 |
| **io2** | 64 TiB | 256,000 | 4,000 MiB/s | Provisioned IOPS, higher durability and throughput |

**Storage size is provisioned and independent of instance class** - you can give a `db.t3.micro` a 1 TiB volume. Minimum is 20 GiB on gp2/gp3, and most engines accept increments of 1 GiB or 10 GiB. **General Purpose SSD for most workloads; IO1/io2 only when you have a genuine, measured IOPS requirement.** Also note gp2/gp3 are network-attached EBS volumes with a single-AZ failure domain - which is precisely why Multi-AZ matters.

Terraform, keeping the security posture right by default:

```hcl
resource "aws_db_subnet_group" "main" {
  name       = "app"
  subnet_ids = [aws_subnet.private_app_a.id, aws_subnet.private_app_b.id]

  tags = { Name = "app" }
}

resource "aws_db_instance" "main" {
  identifier        = "app-db"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "appadmin"
  password = var.db_password # or manage via Secrets Manager / IAM auth

  multi_az                = false
  publicly_accessible    = false # keep this false in production
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  iam_database_authentication_enabled = true
  backup_retention_period = 7
  deletion_protection      = true
  skip_final_snapshot     = false

  tags = { Name = "app-db" }
}
```

`deletion_protection = true` and `skip_final_snapshot = false` are cheap safeguards against an accidental `terraform destroy` taking out a database.

## Security

RDS has **no instance key pair to distribute and no SSH access** - the engine is managed, so patching and shell access are AWS's job. Access control is layered instead:

**1. Network placement (VPC).** RDS instances live in a **subnet group** - a set of subnets in one VPC. The instance is placed in one subnet within the group, and Multi-AZ places the standby in a different AZ, both drawn from the group. This is why your DB subnets should be private and in at least two AZs.

**2. Security groups.** Attach SGs to the DB instance and allow the database port (5432 PostgreSQL, 3306 MySQL, 1433 SQL Server, 1521 Oracle) **only from the application tier's security group** - referenced by SG, not by CIDR:

```hcl
resource "aws_security_group" "db" {
  name        = "rds-postgres"
  description = "PostgreSQL from the app tier only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "PostgreSQL from app SG"
  }
}
```

**3. Why RDS does NOT go in a public subnet.** Being precise about the mechanism: `publicly_accessible = true` gives the instance a **public IP address**, and since the DB subnets' route tables often have no IGW route, that address is frequently unreachable anyway. But when the DB subnet *does* have an IGW route - which is a common mistake, because subnets default to the main route table - a public DB becomes **directly exposed to the internet on a well-known port**, with automated password brute-forcing within minutes. Even with a public IP, an inbound security group rule is still required to accept traffic, so SG rules are the last line of defence rather than the only one. The correct posture is: private subnets with no IGW route, `publicly_accessible = false`, and SG allowing 5432 only from the app SG. Access for humans then goes through SSM Session Manager port forwarding, a bastion host, or a VPN.

**4. IAM database authentication.** RDS supports passwordless **IAM auth**, where you generate a short-lived signed token:

```bash
aws rds generate-db-auth-token \
  --hostname app-db.abc123.eu-west-1.rds.amazonaws.com \
  --port 5432 --region eu-west-1 --username appadmin
```

The token is valid for **15 minutes**, signed with SigV4, and works with any PostgreSQL or MySQL client - pass it as the password. This removes static database credentials from your application configuration entirely: IAM, MFA, session duration, and CloudTrail auditing apply to database access the same way they apply to API calls.

**5. Encryption at rest.** `storage_encrypted = true` encrypts data, logs, and temp files with a KMS key (AES-256). Encryption is on by default for db instances created in the console, but **must be set explicitly when using Terraform or the CLI** - a real difference between console and IaC workflows. It cannot be disabled after creation. Also enable **SSL/TLS enforcement** with `rds.force_ssl = 1` in the parameter group, and remember in-transit encryption is not on by default:

```hcl
resource "aws_db_parameter_group" "pg" {
  name   = "pg16-require-ssl"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}
```

**6. Secrets in the password field.** Keep the master password in Secrets Manager and reference it, rather than hardcoding it in Terraform state. Be aware that any `password` argument on `aws_db_instance` lands in **plaintext in state** - this is the reason the S3 backend for state should be encrypted and tightly access-controlled. IAM auth and Secrets Manager rotation avoid the problem entirely.

## Backups

RDS provides two related but distinct things. Confusing them is a common mistake.

**Automated backups** - always on, cannot be disabled:

- Full backup taken daily, retained for the period you set (**0 to 35 days**).
- Incremental backups every 5 minutes during the window.
- Backups are retained at the end of the retention period for **zero additional charge** (they do not count against instance storage).
- **Point-in-time recovery (PITR)** lets you restore to any moment within the retention window - typically to within a second. This is the practical value of a long retention: it covers accidental `DELETE`/`DROP` and ransomware.
- Restoring from an automated backup creates a **new DB instance** on a new endpoint; it is not in-place.
- `0` days means no retention and no PITR - not an option for production.

**Manual snapshots** - you take them, they persist until you delete them:

- Full, restorable copies of the entire instance.
- **They count against your storage quota / storage cost.**
- Survive instance deletion - `deletion_protection = false` and `skip_final_snapshot = false` rely on them.
- Cross-region copy for disaster recovery; can be shared across accounts.
- Useful for pre-migration checkpoints, long-term records, and seeding environments.

| | Automated backups | Manual snapshots |
|---|---|---|
| Taken by | AWS, automatically, daily + incremental | You, manually |
| Retention | Configurable 0-35 days, then deleted | Until you delete them |
| Extra cost | None within the retention period | Storage cost until deleted |
| Point-in-time recovery | Yes, to any second in the window | No - a snapshot is a single point |
| Deleted with instance? | Deleted when instance is deleted | **No** - they persist |
| Use for | Operational safety net, PITR | Long-term, DR, pre-change checkpoints |

In Terraform, automated backups are simply `backup_retention_period`, and manual snapshots are the separate `aws_db_snapshot` resource:

```hcl
resource "aws_db_snapshot" "before_migration" {
  db_instance_identifier = aws_db_instance.main.identifier
  snapshot_identifier       = "appdb-pre-migration-${formatdate("YYYYMMDDhhmmss", timestamp())}"
}
```

Also consider `aws_rds_cluster` for Aurora, which uses a different set of resources (cluster + `aws_rds_cluster_instance` members) with its own backup semantics.

## Multi-AZ

A **Multi-AZ deployment** runs a **standby replica in a different Availability Zone**, synchronously replicated with the primary.

- The standby is not readable. It exists purely for availability. (Aurora behaves the same way for its cluster-level standby, though Aurora's read replicas are separate from it.)
- Synchronous replication means the standby has the same data; a committed write is present on both.
- On failure - instance crash, AZ failure, networking, or a failed patch - RDS **automatically fails over**, promoting the standby to primary and flipping the DNS endpoint. Typical failover is roughly 1-2 minutes (Aurora is faster).
- The failover changes what the endpoint resolves to, so **applications must not cache DNS** or they will keep connecting to the old primary. Long-lived connection pools must also survive the endpoint flip.
- **Maintenance failover** is the deliberate, planned case: RDS can fail over to the standby, do the patching, and fail back - so maintenance never causes downtime and never waits for a window. This is a genuine benefit of Multi-AZ, not just a recovery feature.
- You do not choose which AZ; AWS places it. You only provide a subnet group spanning at least two AZs.
- Cost: roughly double the instance cost.

## Read replicas

A **read replica** is a separate, readable copy of the primary, used for **read scaling** and cross-region distribution.

| | Multi-AZ standby | Read replica |
|---|---|---|
| Purpose | **High availability** | **Read scaling** |
| Readable by you | No | Yes |
| Replication | Synchronous | **Asynchronous** |
| Failover | Automatic, transparent | None by default; you promote it manually (`promote_read_replica`) |
| Count | One | Up to 5 for standard engines; up to 15 for Aurora |
| Data loss risk | None - synchronous | **Possible replica lag**; a crash can lose in-flight transactions |

**Asynchronous replication means the replica is behind.** If a write commits on the primary and the primary fails before the replica receives it, that write is lost. This is called **replica lag**, and it is why a read replica is never a backup and never a failover target for a Multi-AZ standby.

Read replicas are for:

- **Offloading reporting and analytics** - a `db.m6g.large` replica serving a dashboard query that would otherwise saturate the `db.t3` primary.
- **Scaling read-heavy applications** across multiple replicas.
- **Cross-region** replicas, so reads (and disaster recovery) are closer to users elsewhere. Promotion is manual and involves a brief outage.
- **Upgrading** across major engine versions (one replica, upgrade it, then it is the promoted new primary).
- **Testing** production-like queries without impacting users.

Real applications should be built to **handle replica lag**: "read your own writes" fails on a replica. Route the session's own writes to the primary, and only long-tail analytical reads to replicas.

## RDS use cases

**Transactional systems requiring ACID.** Order processing, payments, bookings, inventory, banking-style ledgers. Anything where a partial write is unacceptable and you need `BEGIN`/`COMMIT` with guaranteed atomicity. This is RDS's strongest case, and exactly where DynamoDB would make you redesign your problem.

**Relational data with genuine relationships.** CRM, ERP, order management with customers/orders/products, HR systems, catalogue and pricing with many-to-many relationships. The joins are the reason.

**Reporting and BI.** Warehousing-ish workloads with `GROUP BY`, window functions, and ad-hoc slicing. Run it on a read replica so the OLTP primary stays responsive - the canonical RDS pattern.

**Compliance and legacy migration.** Oracle and SQL Server lift-and-shift to RDS; existing schemas and tooling keep working.

**Schema enforcement and data integrity.** Unique constraints, foreign keys, `NOT NULL`, check constraints, triggers - all enforced by the engine rather than by application code.

**The classic heuristic:** *if you need joins, use RDS not DynamoDB.* More precisely - if your data model is relational and your queries are ad-hoc SQL, you want a relational engine, and RDS is the managed way to get one. Reach for DynamoDB when access patterns are known, bounded, and dominated by single-key lookups at high volume. Many production systems legitimately use **both**: RDS as the system of record and DynamoDB for a hot access pattern (sessions, leaderboards, a read-heavy feed) denormalised out of it.

**Heuristic summary:**

| Requirement | Choose |
|---|---|
| ACID across multiple rows | RDS |
| Joins across many tables | RDS |
| Ad-hoc SQL, complex reporting | RDS |
| Constraints / foreign keys | RDS |
| Simple key-value lookup at huge scale | DynamoDB |
| Schemaless, varying document shapes | DynamoDB |
| True serverless, pay per request | DynamoDB |
| Real-time leaderboard / counter / session store | DynamoDB |
| Low-latency access to a high-cardinality key | DynamoDB |
