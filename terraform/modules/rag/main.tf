data "aws_caller_identity" "current" {
}

locals {
  documents_bucket_name = replace(var.documents_bucket_arn, "arn:aws:s3:::", "")
  documents_objects_arn = "${var.documents_bucket_arn}/${var.documents_prefix}*"
  documents_source_dir  = abspath("${path.root}/../../../documents/rag/approved")
}

resource "aws_s3_object" "claims_guide" {
  bucket                 = local.documents_bucket_name
  key                    = "${var.documents_prefix}claims-handling-guide.md"
  source                 = "${local.documents_source_dir}/claims-handling-guide.md"
  source_hash            = filemd5("${local.documents_source_dir}/claims-handling-guide.md")
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  tags                   = var.tags
}

resource "aws_s3_object" "product_terms" {
  bucket                 = local.documents_bucket_name
  key                    = "${var.documents_prefix}product-terms.md"
  source                 = "${local.documents_source_dir}/product-terms.md"
  source_hash            = filemd5("${local.documents_source_dir}/product-terms.md")
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  tags                   = var.tags
}

resource "aws_s3vectors_vector_bucket" "this" {
  vector_bucket_name = var.vector_bucket_name
  encryption_configuration {
    sse_type    = "aws:kms"
    kms_key_arn = var.kms_key_arn
  }
  tags = merge(var.tags, { Purpose = "rag-vectors" })
}

resource "aws_s3vectors_index" "this" {
  index_name         = var.vector_index_name
  vector_bucket_name = aws_s3vectors_vector_bucket.this.vector_bucket_name
  data_type          = "float32"
  dimension          = var.embedding_dimensions
  distance_metric    = "cosine"
  encryption_configuration {
    sse_type    = "aws:kms"
    kms_key_arn = var.kms_key_arn
  }
  metadata_configuration {
    non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"]
  }
  tags = var.tags
}

resource "aws_iam_role" "bedrock" {
  name               = "insurance-${var.environment}-rag-bedrock-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "bedrock.amazonaws.com" }, Action = "sts:AssumeRole", Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*" } } }] })
  tags               = var.tags
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "bedrock" {
  name = "rag-documents-and-vectors"
  role = aws_iam_role.bedrock.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "ReadApprovedDocuments", Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = local.documents_objects_arn },
    { Sid = "ListApprovedPrefix", Effect = "Allow", Action = ["s3:ListBucket"], Resource = var.documents_bucket_arn, Condition = { StringLike = { "s3:prefix" = [var.documents_prefix, "${var.documents_prefix}*"] } } },
    { Sid = "UseDocumentKey", Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext"], Resource = var.kms_key_arn },
    { Sid = "UseVectorBucket", Effect = "Allow", Action = ["s3vectors:GetVectorBucket"], Resource = aws_s3vectors_vector_bucket.this.vector_bucket_arn },
    { Sid = "UseVectorIndex", Effect = "Allow", Action = ["s3vectors:GetIndex", "s3vectors:PutVectors", "s3vectors:QueryVectors", "s3vectors:GetVectors", "s3vectors:ListVectors", "s3vectors:DeleteVectors"], Resource = aws_s3vectors_index.this.index_arn },
    { Sid = "InvokeEmbeddingModel", Effect = "Allow", Action = ["bedrock:InvokeModel"], Resource = var.embedding_model_arn }
  ] })
}

resource "aws_bedrockagent_knowledge_base" "this" {
  name        = var.knowledge_base_name
  role_arn    = aws_iam_role.bedrock.arn
  description = "V1 non-agentic insurance document retrieval with source citations."
  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = var.embedding_model_arn
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = var.embedding_dimensions
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }
  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.this.index_arn
    }
  }
  tags = var.tags
}

resource "aws_bedrockagent_data_source" "this" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.this.id
  name              = "approved-insurance-documents"
  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = var.documents_bucket_arn
      inclusion_prefixes = [var.documents_prefix]
    }
  }
  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 10
      }
    }
  }
}
