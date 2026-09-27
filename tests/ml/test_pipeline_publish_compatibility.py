import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "workloads" / "ml"))
from sagemaker_pipeline_publish import compatible_manifest


class FakeS3:
    def __init__(self, raw):
        self.raw = raw
        self.writes = []

    def get_object(self, **kwargs):
        return {"Body": io.BytesIO(self.raw)}

    def head_object(self, **kwargs):
        return {"SSEKMSKeyId": "test-key"}

    def put_object(self, **kwargs):
        self.writes.append(kwargs)


def test_legacy_manifest_gets_lineage_only_in_separate_encrypted_copy():
    original = b"claim_id,as_of_date,feature_version\r\nC1,2026-01-01,v1\r\n"
    client = FakeS3(original)
    uri = compatible_manifest(client, "s3://bucket/execution/manifest")
    assert uri == "s3://bucket/execution/manifest-with-lineage/claim_ids.csv"
    write = client.writes[0]
    assert b"C1,2026-01-01,v1,legacy-manifest-sha256:" in write["Body"]
    assert write["ServerSideEncryption"] == "aws:kms"
    assert write["SSEKMSKeyId"] == "test-key"
    assert client.raw == original


def test_current_manifest_is_reused_without_any_write():
    client = FakeS3(b"claim_id,dataset_version\nC1,known-version\n")
    uri = "s3://bucket/execution/manifest/claim_ids.csv"
    assert compatible_manifest(client, uri) == uri
    assert client.writes == []
