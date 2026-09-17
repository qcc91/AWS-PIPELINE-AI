# Gold transformation stage

Gold publishes the business-facing claim facts, summaries, and downstream
feature contracts as Iceberg tables.

The executable stage handlers remain in the two source-specific Glue entry
points:

- `pipelines/ingestion/batch/glue_claim_pipeline.py`
- `pipelines/ingestion/cdc/glue_cdc_pipeline.py`

Those jobs select this stage through `PROCESSING_STAGE=gold`. This directory is
an architectural navigation aid only: it does not duplicate executable code
and does not change deployment or runtime semantics.
