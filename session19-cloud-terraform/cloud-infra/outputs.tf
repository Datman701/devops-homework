# Networking
output "vpc_id" { value = aws_vpc.main.id }
output "vpc_cidr" { value = aws_vpc.main.cidr_block }
output "public_subnet_id" { value = aws_subnet.public.id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "igw_id" { value = aws_internet_gateway.main.id }
output "nat_gateway_id" { value = aws_nat_gateway.main.id }
output "public_route_table_id" { value = aws_route_table.public.id }
output "private_route_table_id" { value = aws_route_table.private.id }

# Compute
output "security_group_id" { value = aws_security_group.web.id }
output "instance_id" { value = aws_instance.web.id }
output "instance_public_ip" { value = aws_instance.web.public_ip }

# Storage
output "bucket_name" { value = aws_s3_bucket.artifacts.bucket }
output "bucket_arn" { value = aws_s3_bucket.artifacts.arn }
