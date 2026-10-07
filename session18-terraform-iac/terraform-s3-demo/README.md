# terraform-s3-demo

An AWS S3 bucket defined as code, with versioning, server-side encryption and
public-access blocking.

## Files

| File | Purpose |
|---|---|
| `provider.tf` | `terraform` block (required provider) + AWS provider config |
| `variables.tf` | Input variables: region, bucket name, environment, force_destroy |
| `main.tf` | 4 resources: bucket, versioning, encryption, public access block |
| `outputs.tf` | 5 outputs: name, ARN, region, domain, versioning status |
| `terraform.tfvars` | Concrete variable values for this environment |
| `.terraform.lock.hcl` | Provider version lock (committed for reproducibility) |

## Resources created

```text
aws_s3_bucket.demo
├── aws_s3_bucket_versioning.demo                  status = Enabled
├── aws_s3_bucket_server_side_encryption_configuration.demo   sse_algorithm = AES256
└── aws_s3_bucket_public_access_block.demo         all four public-access flags = true
```

The three secondary resources each reference `aws_s3_bucket.demo.id`, which is
how Terraform knows to create the bucket before them — visible in
`terraform graph`.

## Commands

```bash
terraform init      # download providers
terraform fmt       # canonical formatting
terraform validate  # syntax + provider schema check
terraform plan      # preview changes (no credentials required)
terraform show      # inspect state or a saved plan
terraform output    # read outputs from state
terraform graph     # render dependency graph
terraform apply     # create the resources  (requires AWS credentials)
terraform destroy   # delete them            (requires AWS credentials)
```

## Working without an AWS account

`init`, `fmt`, `validate`, `plan`, `show`, `output` and `graph` never contact
AWS, so they work with no credentials at all. The provider block in
`provider.tf` disables the three credential checks the AWS provider normally
performs at startup:

```hcl
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
```

Delete those lines once you have real credentials.

`apply` is the first command that actually calls the AWS API. Run without
credentials it fails at bucket creation with `InvalidAccessKeyId` — see
`../02-screenshots/04-s18-04-apply-needs-credentials.png`, which shows that the
configuration is valid enough to reach AWS and only the key is missing.

## Notes on S3 modelling

Starting with AWS provider v4, settings that used to be inline arguments on
`aws_s3_bucket` became separate resources. Versioning, encryption, logging,
lifecycle and public-access-blocking therefore each get their own block, which
is why this project creates four resources for what looks like one bucket.

`force_destroy = true` lets `terraform destroy` delete a bucket that still
holds objects. Leave it `false` in production — it protects against deleting
data.