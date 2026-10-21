# Terraform — TaskBoard AWS foundation

This stack describes the AWS foundation for the TaskBoard deployment: a VPC
across two Availability Zones, public and private subnets, an internet gateway,
security groups, an EKS cluster, and a managed node group.

It is written with explicit resources rather than registry modules so that
`init`, `fmt`, `validate`, and `plan` work from configuration alone. There are no
AWS data sources in the default path: the Availability Zones are pinned in
`variables.tf`.

## Files

| File | Contents |
| --- | --- |
| `versions.tf` | Terraform/provider versions and provider configuration |
| `variables.tf` | region, CIDRs, AZs, EKS sizing, NAT toggle |
| `vpc.tf` | VPC, IGW, subnets, route tables, optional NAT |
| `security.tf` | application and database security groups |
| `eks.tf` | IAM roles, EKS cluster, node group, access entries |
| `outputs.tf` | IDs and a teardown hint |

## Commands run locally

```bash
cd session21-final-devops/terraform
terraform init -input=false
terraform fmt -check -recursive
terraform validate
terraform plan -input=false -out=s21.tfplan
```

Observed result:

```text
Success! The configuration is valid.

Plan: 15 to add, 0 to change, 0 to destroy.
```

`plan` was run without AWS credentials. The provider has three validation flags
enabled (`skip_credentials_validation`, `skip_requesting_account_id`,
`skip_metadata_api_check`) so the offline plan can render every resource. The
plan is not an apply: AWS would still authenticate normally when real
credentials are present.

## Apply is intentionally not run

This submission has no AWS account. `terraform apply` and `terraform destroy`
were **not** run and no AWS resources were created. The plan is the evidence that
the configuration is syntactically valid and internally consistent.

To run it in an account:

```bash
export AWS_PROFILE=your-profile
terraform plan -out=s21.tfplan
terraform apply s21.tfplan
# ... use the cluster ...
terraform destroy -auto-approve
```

## Cost notes

- NAT Gateway is disabled by default. Worker nodes run in public subnets, which
  is cheap but not production-hardened.
- The default node group is `t3.small`, desired 2, min 1, max 3.
- EKS control plane and worker nodes are the main recurring costs. Destroy the
  stack after the demo.

## Safety

- No credentials, account IDs, or state files are committed.
- `.terraform/`, `*.tfstate`, `*.tfplan`, and `terraform.tfvars` are ignored.
- The only committed variable example is `terraform.tfvars.example`.
