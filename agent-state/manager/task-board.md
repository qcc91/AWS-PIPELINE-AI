# Manager Work-Package Board

| Package | Owner | Scope | Status | Human gate |
|---|---|---|---|---|
| V1-INFRASTRUCTURE | Sol Manager + Luna Infrastructure Worker | Continue TASK-INF-001–005 as one package: validation, discovery, identity preparation, bootstrap/foundation plans, security and cost review | In progress; local init/validate complete, AWS identity bootstrap required before real plan | P1-CP1 / Gate 2 Terraform Plan Approval |
| DEV APPLY AND VERIFICATION | Luna Infrastructure Worker | Former TASK-INF-006; apply only the approved plans and verify controls | Not authorized | Requires explicit Gate 2 approval |
| V1-BATCH-LAKEHOUSE | Data Engineering + Infrastructure Workers | CSV happy path and minimum Bronze/Silver/Gold Iceberg | Planned; not started | After approved DEV infrastructure |
| V1-CDC | Data Engineering + Infrastructure Workers | RDS PostgreSQL, DMS full load/CDC and current-state lakehouse flow | Planned; not started | V1 integration review |
| V1-STREAMING | Data Engineering + Infrastructure Workers | Python producer, Kinesis, Firehose and event lakehouse flow | Planned; not started | V1 integration review |
| V1-BI / V1-ML / V1-RAG | Domain Workers | Minimum working downstream happy paths | Planned; not started | V1 completion review |

Routine rework stays internal to each package. V1 is authorized; V2–V5 are not.
