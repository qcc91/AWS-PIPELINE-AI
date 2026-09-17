# Common Terraform contract

This module contains the shared environment and tagging contract. It creates
no AWS resources. Environment separation is represented by separate roots under
`infrastructure/terraform/environments/dev` and
`infrastructure/terraform/environments/prod`; workspaces are
not used as a security or state boundary.
