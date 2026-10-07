# AWS S3 - Storage

Amazon Simple Storage Service (S3) is object storage: durable, virtually unlimited, and reachable over HTTP APIs. You store data as **objects** inside **buckets**, and control access with IAM and bucket policies.

S3 is the backbone of most AWS architectures. It holds static site content, application data, database and EBS snapshots, CloudTrail and VPC flow logs, CI/CD artefacts, and data lake zones. Its API is also what Terraform and most deployment tooling talk to when they store state.

## Buckets

A **bucket** is a namespace for objects. Properties:

- **Globally unique name** across all of AWS, in the format `bucket-name`. Lowercase only; 3-63 characters. Naming rules that people trip over: no underscores, no uppercase, no adjacent periods, and the name must not be formatted as an IP address.
- **Globally unique namespace** - this is why naming is strict. Because names are global, DNS-style rules apply and HTTPS is required (unless you are in a Region opt-in such as `us-east-1` legacy us-east-1 endpoints, or use a custom domain).
- **Region-bound.** A bucket lives in exactly one region. Objects in it never leave that region. There is no multi-region bucket; you create buckets in each region and configure replication.
- **Flat structure.** There is no real directory. See keys below.
- **Naming prefixes** such as `acme-assets-prod-` or including the account ID make ownership obvious and reduce the chance of a global collision when someone else's account tries the same name.
- **Ownership:** features including Block Public Access, Object Lock, and default encryption can be enforced with bucket-owner-enforced ACLs, which disables ACLs entirely.

Terraform creates a bucket and configures versioning, encryption, and public access blocking as separate resources, because they are separate API calls:

```hcl
resource "aws_s3_bucket" "assets" {
  bucket = "acme-assets-prod-123456789012"
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

The modern `aws_s3_bucket` resource family splits every setting into its own `aws_s3_bucket_*` resource (server-side encryption configuration, ownership controls, lifecycle configuration, and so on). Older tutorials use nested blocks inside `aws_s3_bucket`, which recent provider versions deprecate or reject.

## Objects

An **object** is the unit of storage: the data plus metadata plus a key that names it.

| Property | Notes |
|---|---|
| Key | Unique within the bucket. Up to **1,024 bytes** of UTF-8 |
| Size | 0 bytes to **5 TB** per object |
| Version | Optional, if versioning is enabled |
| Metadata | User-defined key/value pairs, or system `x-amz-meta-*` headers |
| Storage class | Per object, independent of the bucket default |
| ETag | Typically the MD5 for single-part uploads; **not** a reliable checksum for multipart uploads |

### Prefixes are not folders

S3's keyspace is a flat map from string to object. `logs/2026/01/access.log` is a single key containing slashes. There is no directory entity, no directory rename, and no directory-level permissions or quotas - slashes are purely a naming convention that clients (`aws s3 ls`, the console, `boto3`) present as folders.

Practical implications:

- `CopyObject` from `a/b.txt` to `a/` **does not** act like `mv`; it produces `a/b.txt` and leaves the original, because there is nothing to merge.
- "Empty folder" prefixes do not exist and cannot be created; the UI shows them only when a key ending in `/` exists.
- Listing is prefix-based: `aws s3api list-objects --bucket b --prefix logs/2026/ --delimiter /` emulates directory listings and "folders" by treating the delimiter as a boundary.
- Permissions and lifecycle rules work on key prefixes, which is why prefixes are still valuable - they are the unit of access control and transition policy.

Multipart upload is how objects above 5 GB (and how faster, more resilient uploads of smaller objects) are handled: upload in parts, then `CompleteMultipartUpload` assembles them. Parts must be 5 MB-5 GB, except the last, and S3 provides lifecycle rules to abort incomplete multipart uploads so they do not accumulate and quietly incur charges.

## Storage classes

| Class | Durability | Retrieval | Min storage duration | Intended use |
|---|---|---|---|---|
| **S3 Standard** | 11 nines across 3 AZs | Milliseconds | None | Default. Frequent access, primary data |
| **S3 Intelligent-Tiering** | 11 nines across 3 AZs | Milliseconds | 30 days for the auto tiers | Unknown/varying access patterns; small monthly monitoring fee, no retrieval charges |
| **S3 Standard-IA** | 11 nines across 3 AZs | Milliseconds | 30 days | Infrequent access but still latency-sensitive: backups, less-used apps |
| **S3 One Zone-IA** | 11 nines in 1 AZ | Milliseconds | 30 days | Infrequent access, recreatable data, lower cost than Standard-IA. **Data is lost if the AZ goes away** |
| **S3 Glacier Instant Retrieval** | 11 nines across 3 AZs | Milliseconds | 90 days | Archive that still needs millisecond reads |
| **S3 Glacier Flexible Retrieval** | 11 nines across 3 AZs | Milliseconds to 12 hours (bulk: minutes) | 90 days | Archives accessed rarely, e.g. quarterly logs, media masters |
| **S3 Glacier Deep Archive** | 11 nines across 3 AZs | 12 hours (bulk: hours) | 180 days | Compliance archives, records retention (7-10 year) |

"Eleven nines" (99.999999999%) is the design target for the multi-AZ classes and refers to **object durability**, not availability. Durability is the statistical probability that an object is not lost; availability (the endpoint responding) is a separate, generally lower figure.

Cost ordering: Standard is the most expensive per GB and cheapest per request; as you go down the table, cost per GB drops while cost per retrieval rises, with a **minimum storage duration charge** per object in each class - deleting or transitioning out before the minimum means you still pay for the minimum.

Selection guidance: if access pattern is genuinely unknown, Intelligent-Tiering removes the guesswork. If you know data is cold and retrievable in hours, Glacier Flexible. If it must be recalled in milliseconds, Instant Retrieval or Standard-IA.

## Versioning

Versioning stores every distinct version of an object, including deletes. Enabling it is a one-way switch for objects created after that point (you can suspend, but never return to unversioned state for existing objects).

Effect of deleting a versioned object: the delete creates a **delete marker**, which becomes the current version and makes `GetObject` return `404 NoSuchKey`. The object is not gone.

How to see and roll back to a previous version:

```bash
# List all versions, oldest first, newest marked as current
aws s3api list-object-versions \
  --bucket acme-assets-prod-123456789012 \
  --prefix config/app.yaml

# Roll back by copying an old version over the current key
aws s3api copy-object \
  --bucket acme-assets-prod-123456789012 \
  --key config/app.yaml \
  --copy-source "acme-assets-prod-123456789012/config/app.yaml?versionId=3HL4kqtJlcpXroDTDmjVBH40Nrjfkd" \
  --metadata-directive COPY
```

That copy creates a *new* version whose contents equal the old one, which becomes current. Version history is never truncated - restore-in-place is a copy, not a revert.

Cost and management implications:

- Every write creates another version, so storage cost grows roughly linearly with the number of writes. A config file rewritten hourly is 8,760 versions a year.
- A single malicious or accidental write is exactly what versioning protects against, and exactly what makes "restore the last good version" a routine runbook step.
- **Lifecycle rules are required to make versioning affordable**: a noncurrent-version expiration rule plus a noncurrent-version transition rule prune and reclassify old versions. Without them, versions accumulate indefinitely and in Standard class.
- Replica versioning can be enabled separately for S3 Cross-Region Replication, so replicas keep their version history independently of the source's lifecycle rules.
- Object Lock (WORM/retention lock in Governance or Compliance mode) only works on versioned buckets.

## Lifecycle policies

A lifecycle configuration is a set of **rules** applied to a whole bucket or to a prefix/filter. Two kinds of action:

- **Transition** - move objects (or their noncurrent versions) to a colder storage class after a number of days.
- **Expiration** - delete objects (or noncurrent versions, or expired delete markers) after a number of days. There is also `AbortIncompleteMultipartUpload` for abandoned uploads and `Expiration` as a *date* (specific expiry timestamp) for artefacts like presigned upload targets.

Rules evaluate once a day, in UTC, typically around midnight. Deletion by expiration for S3 Standard/IA is asynchronous, so an object past its expiry date may still be readable for a short window.

Example - three months hot, then archive, then delete after seven years:

```json
{
  "Rules": [
    {
      "ID": "tier-and-expire-objects",
      "Status": "Enabled",
      "Filter": { "Prefix": "logs/" },
      "Transitions": [
        {
          "Days": 90,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 365,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 2555
      }
    },
    {
      "ID": "prune-noncurrent-versions",
      "Status": "Enabled",
      "Filter": { "Prefix": "" },
      "NoncurrentVersionTransitions": [
        {
          "NoncurrentDays": 30,
          "StorageClass": "GLACIER"
        }
      ],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 120
      },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }
  ]
}
```

Rule 1 handles the happy path for objects under `logs/`: hot for 90 days, then Standard-IA, then Glacier after a year, deleted after seven years.

Rule 2 is the one people forget. With versioning on, `NoncurrentDays: 120` deletes old versions after four months, which stops silent unbounded growth; `AbortIncompleteMultipartUpload` stops orphaned upload parts from billing forever. These two rules are what make versioning safe to enable on a busy bucket.

Ordering rules: when two rules match the same object, S3 uses the older rule's *days* setting for a given action. Writing overlapping rules with conflicting transitions causes surprising behaviour, so keep them disjoint.

Terraform, since lifecycle configuration is its own resource:

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "prune-noncurrent-versions"
    status = "Enabled"

    filter { prefix = "" }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 120
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
```

## Encryption

All S3 objects are encrypted server-side at rest by default. There are three options for server-side encryption (SSE):

| Option | Key management | In CloudTrail | Revocable by you | Cost |
|---|---|---|---|---|
| **SSE-S3** (`AES256`) | AWS-owned keys | No key ID logged | No | Free |
| **SSE-KMS** (`aws:kms`) | Customer managed KMS key | Yes, key ID appears | **Yes**, disable/delete key | KMS request + storage cost |
| **SSE-C** | **You** supply the key in each request | No | Only by you possessing it | No KMS cost |

**SSE-S3.** AES-256 with AWS-managed keys, enabled by default on all new buckets, no configuration and no additional cost. AWS owns the keys and guarantees nobody can read your data. You cannot revoke access, because there is no key you control. What you *can* control is who can call `GetObject` - encryption and authorisation are separate, and IAM still gates every request.

**SSE-KMS.** You create a KMS key and S3 uses it. Because the key ID shows up in CloudTrail data events, you get an audit trail of which key was used for which request, and you can rotate or disable the key to cut off access immediately without deleting objects. This is why regulated workloads choose SSE-KMS over SSE-S3. You can restrict which principals may use the key via the key policy, and scope it with an S3 condition on the key ARN so a bucket's objects cannot be decrypted with the wrong key:

```json
{
  "Sid": "DenyUnencryptedUploads",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::acme-assets-prod-123456789012/*",
  "Condition": {
    "StringNotEquals": {
      "s3:x-amz-server-side-encryption": "aws:kms"
    }
  }
}
```

That explicit deny is a common pattern: it makes unencrypted upload impossible even for principals who hold an `Allow`.

**SSE-C.** You generate and hold the key. It travels in the request headers on every upload and download, S3 stores it only in encrypted form internally, and **it is never written to CloudTrail** - so an audit of who read what is not available from the key side. You lose access the moment you lose the key; there is no AWS recovery path. Note that SSE-C is not supported for every S3 feature (notably S3 Transfer Acceleration, and it cannot be used as a bucket default encryption setting - it must be specified per request).

Client-side encryption is a separate, additional layer (SSE-C under the hood via the SDK, or a library such as `cryptography`) for cases where even AWS should not be able to see plaintext.

## Bucket policies

A **bucket policy** is a **resource-based** IAM policy attached to a bucket. Because it is resource-based, it can name the principal as a beneficiary and grant access to accounts and IAM identities that have no way to be given an IAM policy of their own - which is what makes it the mechanism for cross-account S3 access.

An IAM policy on a user or role names resources and cannot reference *another account's* principal. A bucket policy can. Where the two meet, both must allow.

Choosing between the three mechanisms:

| Mechanism | Applies to | Use it for |
|---|---|---|
| IAM identity policy | user / role / group in **your** account | What your own principals may do, across many buckets |
| Bucket policy | a specific bucket | Cross-account access; anonymous/public access; explicit deny guardrails; requiring encryption or TLS |
| ACLs | individual objects and buckets | **Legacy.** Prefer `bucket-owner-enforced` ownership, which disables ACLs. New features assume ACLs are off |

On ACLs specifically: they predate IAM, they grant at object granularity (not prefix granularity), they interact confusingly with versioning, and several S3 features (Object Lock, all features via `aws:s3:ObjectOwnership`, default encryption behaviour) effectively require them to be disabled. AWS now defaults new buckets to `BucketOwnerEnforced`, which makes every ACL a no-op and blocks all public ACLs.

Public-read bucket policy for a website - note the `Principal: "*"` and the two conditions, because a public read policy without them is a serious data exposure:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::acme-assets-prod-123456789012/public/*"
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::acme-assets-prod-123456789012",
        "arn:aws:s3:::acme-assets-prod-123456789012/*"
      ],
      "Condition": {
        "Bool": { "aws:SecureTransport": "false" }
      }
    },
    {
      "Sid": "AllowCloudFrontRead",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::acme-assets-prod-123456789012/private/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::123456789012:distribution/EXXXXXXXXX"
        }
      }
    }
  ]
}
```

The third statement shows the OAC/OAI pattern: the principal is the CloudFront *service*, and pinning it with `AWS:SourceArn` prevents anyone else's CloudFront distribution from reading the private origin. Combine with Block Public Access on the bucket and the public-read statement has no effect either.

Same-account private access: put the principal in the bucket policy as the role ARN (not `*`), e.g. `"Principal": {"AWS": "arn:aws:iam::123456789012:role/AppRole"}`. You can also restrict to a specific source VPC endpoint with `aws:sourceVpce`.

Terraform:

```hcl
resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = data.aws_iam_policy_document.assets.json
}

data "aws_iam_policy_document" "assets" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.assets.arn, "${aws_s3_bucket.assets.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
```

## Common use cases

**Static website hosting.** An S3 bucket serving a built frontend, with the bucket's website endpoint or a CloudFront distribution in front. Set the index document to `index.html` and the error document to `404.html` (the latter is how client-side routers get their fallback). Requirements: all objects public-read or CloudFront OAC as above, and `Block Public Access` configured consistently - you cannot have BPA on and also serve anonymous reads from the bucket itself. CloudFront is the better answer in production for caching, TLS, and edge behaviour.

**Backups and data lakes.** RDS snapshots, EBS snapshots, DynamoDB exports, and on-premises backups land in S3 with versioning and lifecycle rules for retention tiers. For analytics-scale data lakes, S3 is the storage layer underneath Athena, Glue, EMR, Redshift Spectrum, and Lake Formation, which query it in place rather than requiring a copy.

**Log and archive storage.** CloudTrail, VPC Flow Logs, ELB access logs, WAF logs, and Config history are all written to S3. Because log volume is large, cold and heavily compressible, a lifecycle rule moving to Standard-IA then Glacier after 30-90 days typically cuts cost several-fold. Bucket policies with a `Deny` on `s3:DeleteObject` protect the logs from tampering; Object Lock adds WORM retention for compliance.

**CI/CD artefact store.** Build output (JARs, images layers, wheels, binaries) is pushed to S3 by the pipeline under an IAM role scoped to one prefix, and pulled by the deploy stage. S3 gives you versioning and cross-region replication for free, which makes artifact promotion across environments and disaster recovery straightforward. The convention of "immutable artefact path plus a `latest` or version manifest pointer" works well here.

**Terraform state.** `terraform.tfstate` contains sensitive values in plaintext, so remote state should live in an S3 bucket with `server_side_encryption = true`, versioning enabled, and Block Public Access on, combined with DynamoDB table locking (or, in current Terraform versions, S3-native locking with `use_lockfile = true`).
