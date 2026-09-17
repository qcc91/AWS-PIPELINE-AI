# Lake Formation baseline

Registers exactly two explicit S3 locations with the passed data-access role;
the service-linked role is disabled. Data lake administrators and all workload
roles must be explicit, unique, same-account role ARNs with normal role paths.

| Principal | Database metadata permissions |
|---|---|
| DataEngineer | `ALTER`, `CREATE_TABLE`, `DESCRIBE` on bronze, silver, gold, control |
| Analyst | `DESCRIBE` on gold only |
| MLEngineer | `DESCRIBE` on silver and gold only |
| RAGApplication | none |

No table exists in this foundation task, so this module does not create table,
column, data-location, or `SELECT` grants. When tables and classified columns
exist, PII column controls must be added under the approved role matrix and
tested with positive and negative access cases. Any table/column `DROP`
permission must be granted later through a specific reviewed table contract.
The RAGApplication role is an
explicit validated input solely to prove it is distinct and receives no grant.
The module validates and exposes the complete integration tag contract, but the
Lake Formation settings, registration, and permission resources do not expose
resource tags in this provider shape; no tag application is falsely claimed.
