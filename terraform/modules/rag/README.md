# RAG module

Creates one S3 Vectors bucket/index, a least-privilege Bedrock Knowledge Base
role, a vector Knowledge Base, and an approved-prefix S3 data source. The
module is intentionally not wired into the V1 foundation root until Gate 2 and
successful authenticated discovery. It never creates OpenSearch resources.
