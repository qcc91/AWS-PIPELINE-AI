# V1 streaming

Creates one on-demand Kinesis stream, a Kinesis-source Firehose delivery
stream, and a small Glue Iceberg job. Firehose writes newline-delimited JSON
to `stream/` in the existing lakehouse bucket. No resource is applied by this
module automatically.
