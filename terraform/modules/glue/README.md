# Glue Catalog module

Creates exactly four databases: `bronze`, `silver`, `gold`, and `control`.
Names are `insurance_<environment>_<layer>`. Bronze, Silver, and Gold receive
distinct layer prefixes derived below the lakehouse URI; Control uses a
separate validated URI. The two input bases cannot be equal.

This module creates no Glue tables, crawlers, jobs, classifiers, or
connections. Tables and column-level governance are intentionally absent at
this foundation stage.
