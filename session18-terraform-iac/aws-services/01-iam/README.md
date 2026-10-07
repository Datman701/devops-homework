# AWS IAM - Governance

Identity and Access Management (IAM) is the service that decides **who or what can do what** in an AWS account. Every single API call you make - via console, CLI, SDK, or Terraform - is evaluated against IAM before AWS will do anything.

IAM is **global**. There is no `us-east-1 IAM`; the service is replicated across all AWS regions and controlled from one namespace (`iam.amazonaws.com`). Its identity store (users, groups, roles, policies) is shared by every region in the account, which is why IAM is one of the first services to configure in any account and why it is on the AWS Well-Architected "foundational pillar".

Two facts that trip up most beginners:

- **Credentials are account-wide.** A set of access keys created in one region authenticates against every region. There is no per-region IAM.
- **IAM is authorisation, not authentication of people.** IAM does not log people in. That is handled by the AWS sign-in page, which may itself rely on an external identity provider (SAML/OIDC). IAM takes the resulting identity and answers "is this principal allowed to perform this action?"

## Users

An **IAM user** is a permanent, named identity representing a human (or, historically, a machine). It lives in your account until you explicitly delete it. A user can hold:

- A **password** for console sign-in.
- **Access keys** (an access key ID + a secret access key) for programmatic access to the CLI, SDKs, or API calls.

Users are cheap to create and bad to keep around. The reason is that each user carries long-lived credentials that do not expire on their own, can be copied, and are difficult to revoke everywhere at once. AWS has been actively steering new architectures away from IAM users for years; in the AWS console, creating a user now prompts you about whether you need console access, programmatic access, or neither (in which case the right answer is to use a role).

## Groups

An **IAM group** is a container for users so you can attach one policy to many identities instead of N. Groups are a convenience for permission management only - they do not grant permissions by themselves, and they do not appear in the AWS account as anything other than an organisational bucket for users.

Notably, **roles cannot be members of groups**. If you want to reuse permissions across identities of different types, you either duplicate the inline policy or reference a managed policy ARN in both places.

## Roles

An **IAM role** is an identity that AWS services, AWS resources, or federated users can *assume* in order to make API calls. When a role is assumed, AWS issues **temporary credentials** (access key ID, secret access key, and a session token) that expire automatically - typically one hour, configurable up to 12 hours with role chaining.

This is the distinction to remember for exams and interviews:

| | IAM user | IAM role |
|---|---|---|
| Credentials | Permanent (access key, password) | Temporary, issued on assume |
| Expiry | Never, until rotated or deleted | Session duration (15 min - 12 h) |
| Who can assume | Only the key holder | AWS services, EC2, ECS, Lambda, federated IdP, another account |
| Best practice status | Avoid for new designs | Preferred |
| Created by | A human, once | A human defines it; a principal assumes it at runtime |

Common role flavours:

- **Service roles** - e.g. EC2 instance profile, ECS task role, Lambda execution role. AWS itself assumes them on your behalf when the service starts or is invoked.
- **Cross-account roles** - defined in the target account with a trust policy naming the source account's principal. The source account's role then has `sts:AssumeRole` against the target.
- **Federation / SSO roles** - assumed after a user signs in through Identity Center or an external IdP.
- **Instance profiles** - technically a container that holds exactly one role, and is what you attach to an EC2 instance (or launch template / Auto Scaling group) so the instance can fetch role credentials from its metadata service.

An instance profile is worth calling out because it is a common exam trap: you cannot attach a role directly to an instance, you attach an instance profile that references the role.

## Policies

A **policy** is a JSON document that grants or denies permissions. Every policy has:

- **Version** - `2012-10-17` is the current policy language version.
- **Statement** - a list of statements.
- Each statement has an `Effect` (`Allow` or `Deny`), `Action` (which API calls), `Resource` (which objects), and optionally `Condition`, `Principal`, and `NotAction` / `NotResource`.

Actions are written as `service:Action` and support `*` wildcards: `s3:GetObject`, `s3:List*`, `ec2:Describe*`. Resources are ARNs:

```
arn:aws:service:region:account-id:resource-type/resource-id
arn:aws:s3:::my-bucket/path/*
arn:aws:iam::123456789012:role/MyRole
```

Policy types:

| Type | Count | Attached to |
|---|---|---|
| Identity-based (managed) | Unlimited (quota-limited) | A user, group, or role |
| Identity-based (inline) | One per identity | Embedded directly in the user/group/role |
| Resource-based | One per resource | The resource itself (S3 bucket, KMS key, SNS topic, SQS queue...) |
| Permissions boundary | One per identity | Caps the maximum permissions of a user or role |
| Service control policy (SCP) | Per OU | Caps the maximum permissions of an entire account or OU |

Note that an S3 **bucket policy** and a KMS **key policy** are both resource-based, but their default behaviour differs: an S3 bucket policy alone (with no IAM identity policy) is enough to grant access to a principal in another account, whereas a KMS key policy always effectively needs a matching IAM grant too.

## Permissions and policy evaluation logic

IAM is fundamentally **additive with an override for deny**. Understanding evaluation order is the single highest-value IAM topic:

1. Build a permission set from all applicable identity-based policies (inline, attached managed, group policies).
2. If a **permissions boundary** is attached, intersect with the boundary. Permissions outside it are dropped.
3. If an **SCP** applies, intersect again. Your account can never exceed what the SCP allows.
4. If the request includes a **resource-based policy** on the resource (bucket policy, key policy, and for some services also identity policies of the resource owner), include it in the evaluation.
5. Evaluate the request against the resulting set:
   - An explicit `Deny` anywhere in the relevant policies wins. **There is no override for deny.**
   - Otherwise, an explicit `Allow` in *any* applicable policy means allow.
   - If there is no `Allow` anywhere, the request is implicitly denied.

Consequences of "explicit deny wins":

- You cannot grant access that an SCP or permissions boundary forbids, even with `Allow`. SCPs and boundaries subtract; they never add.
- You can always revoke access with a single explicit `Deny`, even while other statements still say `Allow`. This is how you lock down a critical resource (say, a billing-owner protected S3 bucket) against *everyone* except the break-glass role.
- Resource-based policies are evaluated for the resource, and for most services only for the **same resource ARN**. A bucket policy on bucket A does not grant access to bucket B.

There is also **"identity vs resource"** as the two ways a permission can be granted:

- **Identity-based**: the policy names the *principal* as attached to it, and lists resources it may act on. Used to grant a role or user access to many resources.
- **Resource-based**: the policy is attached to the *resource* and uses a `Principal` block to name who benefits. Used to share a specific resource (cross-account bucket access, a KMS key, an SNS topic) without editing every identity.

## Credential types

| Credential | Typical use | Lifetime |
|---|---|---|
| Access key ID + secret access key | CLI, SDK, API calls | Long-lived (up to 90 days rotation) |
| Session token | Always present with role credentials | Tied to the session |
| Temporary STS credentials | AssumeRole, federation, instance profiles | 15 min - 12 h |
| Console password | Web console | Long-lived unless forced to reset |
| MFA (TOTP / FIDO2 / hardware key) | Second factor for console + sensitive API calls | Per use |

The MFA argument is not just "console security". A leaked long-lived access key can be used from anywhere in the world, indefinitely, with no prompt. With MFA enabled for the user and enforced with an MFA condition on the sensitive actions, you can require that a fresh MFA challenge result was presented recently:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["iam:CreateUser", "iam:DeleteUser", "iam:AttachRolePolicy"],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }
  ]
}
```

Shorter-lived credentials shrink the blast radius. A leaked role session expires on its own; a leaked access key does not. This is the core argument for short-lived credentials everywhere.

## Least privilege

**Least privilege** means granting exactly the permissions an identity needs to do its job, and nothing else. It is a continuous process, not a one-time setting.

How to derive minimal permissions:

1. **Start with nothing.** Attach no permissions (or a deny-everything boundary) and let the identity fail.
2. **Run the real workflow.** Every access-denied error reveals a missing action.
3. **Add only what breaks.** Record the failing action, add it, repeat. This converges on an accurate list quickly.
4. **Automate it with IAM Access Analyzer.** Rather than guessing, use the CloudTrail-recorded access model:
   - Run the workload.
   - Look at the CloudTrail events it generated.
   - Generate an Access Analyzer policy from that log data, which produces a policy limited to exactly those actions and resources.
5. **Trim resources.** Prefer `arn:aws:s3:::my-bucket/reports/*` over `arn:aws:s3:::*`. Prefer a specific role ARN over `*`.
6. **Re-review.** Permissions drift as code changes.

A minimal S3 policy for a CI/CD job that uploads build artefacts to one prefix of one bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListOnlyTheArtifactPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::acme-build-artifacts",
      "Condition": {
        "StringLike": { "s3:prefix": ["artifacts/*"] }
      }
    },
    {
      "Sid": "ReadWriteArtifactsOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::acme-build-artifacts/artifacts/*"
    }
  ]
}
```

Reading that line by line:

- `s3:ListBucket` is a **bucket-level** action. It cannot be scoped by prefix with the resource ARN, so the `Condition` on `s3:prefix` does the narrowing instead. Without it, this statement would let the role list the whole bucket.
- `s3:GetObject` / `PutObject` / `DeleteObject` are **object-level** actions, scoped by ARN to a single prefix.
- Both statements are needed. If you only allow the object actions, the CI job fails because clients typically list before uploading.
- Note what is *not* granted: no `s3:DeleteBucket`, no access to any other bucket, no `s3:PutObjectAcl`, no access to `artifacts-prod/` if that is a separate prefix. A role in the same account could still be granted more by another policy - least privilege is only meaningful when it is also enforced by a boundary or SCP for critical separation.

Corollaries worth stating: never use `"Resource": "*"` for write or delete actions when a narrower ARN works; wildcard actions like `s3:*` defeat the purpose; and use separate roles for separate jobs (deploy role, read role, admin role) so each is independently auditable and revocable.

## IAM best practices

- **Never use the root user for day-to-day work.** Root has unrestricted access, cannot be restricted by any policy, and cannot have MFA enforced by IAM. It exists for account creation, billing, and a handful of recovery operations. If you must use it, rotate its access key and enable MFA hardware keys. Prefer Identity Center so humans authenticate with a role.
- **Enable MFA** for every human identity, and for break-glass accounts.
- **Prefer roles over users**, especially for workloads. EC2, ECS, Lambda, CodeBuild, and CI runners should all use roles / instance profiles.
- **Never use long-lived access keys.** Use `sts:AssumeRole` or federated temporary credentials (15 min to 12 h). Where keys are unavoidable, rotate them and investigate them with IAM Access Analyzer Credential Reports.
- **Enable CloudTrail** in all regions and treat it as immutable reference data - it is what you use to audit and to generate least-privilege policies.
- **Use IAM Access Advisor / Access Analyzer** to find unused roles, unused permissions, and public (external-account) access.
- **Use the IAM credential report** periodically. It lists every user and whether each has console password, access keys, MFA, and when the credentials were last used. Users untouched for 90+ days should be deleted.
- **Use permissions boundaries** on roles that assume cross-account or developer identities, so an over-broad trust policy cannot turn into over-broad access.
- **Separate duties.** Nobody should hold both "can deploy" and "can approve/change security policy".
- **Name and tag consistently** (`team=platform`, `env=prod`) so governance queries and Access Analyzer findings are actionable.
- **Set up an org with SCPs** so that even account admins cannot bypass guardrails on regions, or on dangerous actions like unencrypted S3 or disabling CloudTrail.

## Common use cases

**CI/CD pipeline accessing S3 or ECR.** A CodeBuild project, GitHub Actions OIDC role, or Jenkins worker runs under a role rather than a static key. With OIDC federation, the CI provider issues a short-lived token that STS exchanges for role credentials - no stored secret anywhere. The role is scoped to one bucket prefix, or to one ECR repository, and permission boundaries can restrict which repos it may push to.

**EC2 instance profiles.** A role attached to an instance through an instance profile lets any process on that instance call `sts:AssumeRole` (via the instance metadata service, `169.254.169.254`) and receive temporary credentials. This replaces SSH key-based access to S3 entirely - no keys on the instance at all. The metadata endpoint is exposed by default (IMDSv1); set `HttpTokens=required` to require IMDSv2 sessions.

**Cross-account access.** Account A assumes a role in account B. B's role carries a trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::111122223333:root" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

The `Principal` naming `:root` means "account 111122223333, any principal in it" - the trust policy cannot enumerate individual IAM principals, only account-level or role-level principals. Using a specific role ARN instead of `:root` narrows who can assume it. Account A's role then needs `sts:AssumeRole` permission, and can further constrain the target account and role with an `ExternalId` condition to prevent confused-deputy attacks in third-party scenarios.

**Centralised identity with SSO / Identity Center.** Identity Center (AWS SSO) connects a corporate IdP (Microsoft Entra ID, Okta, Google Workspace) and issues permission sets. Users sign in to an account or subscription through SSO and get a role with temporary credentials - no IAM users, no passwords managed in AWS, joiners and leavers handled by the IdP. Permission sets can be attached to all accounts or scoped to particular ones.

**Third-party / service access.** Roles let SaaS vendors or AWS service principals access resources without you creating accounts for them, and the trust policy plus external ID plus session duration limit how long and from where that access is valid.
