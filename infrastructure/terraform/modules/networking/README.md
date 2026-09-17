# Networking module

Creates exactly one VPC, two private subnets derived with `cidrsubnet`, one
private route table, two route-table associations, and one S3 Gateway endpoint
in `ap-southeast-2`. The module creates no internet gateway, NAT gateway,
interface endpoint, public route, or automatic public IP assignment.

Callers must provide two distinct Sydney availability zones and two distinct
non-negative subnet numbers below `2^private_subnet_newbits`. Newbits is limited
to an integer from 1 through 8, and each derived CIDR must be valid.

The complete project tag contract has no defaults. Required values must be
non-empty, `ManagedBy` must be `terraform`, and `DataClassification` must be one
of `public`, `internal`, `confidential`, or `restricted`.
