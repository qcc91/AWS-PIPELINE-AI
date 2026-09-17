# Bronze transformation stage

Bronze preserves source-oriented records and ingestion metadata in Iceberg.

The executable stage handlers remain in the two source-specific Glue entry
points:

- `pipelines/ingestion/batch/glue_claim_pipeline.py`
- `pipelines/ingestion/cdc/glue_cdc_pipeline.py`

Those jobs select this stage through `PROCESSING_STAGE=bronze`. This directory
is an architectural navigation aid only: it does not duplicate executable code
and does not change deployment or runtime semantics.
