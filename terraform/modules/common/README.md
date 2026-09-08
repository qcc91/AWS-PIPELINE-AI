# Common Terraform contract

This module contains the shared environment and tagging contract. It creates
no AWS resources. Environment separation is represented by separate roots under
`terraform/environments/dev` and `terraform/environments/prod`; workspaces are
not used as a security or state boundary.
