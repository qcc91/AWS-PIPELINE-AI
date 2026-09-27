from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "workloads" / "ml"))

import sagemaker_pipeline_prepare as prepare  # noqa: E402


def test_prepared_snapshot_downloads_all_six_existing_artifacts(tmp_path, monkeypatch):
    downloads = []

    class FakeS3:
        def download_file(self, bucket, key, destination):
            downloads.append((bucket, key))
            Path(destination).write_text(key, encoding="utf-8")

    monkeypatch.setattr(prepare.boto3, "client", lambda service, region_name: FakeS3())
    names = (
        "train.csv",
        "validation.csv",
        "test.csv",
        "inference.csv",
        "claim_ids.csv",
        "metadata.json",
    )
    destinations = {name: tmp_path / name for name in names}

    prepare._download_prepared_snapshot(
        s3_uri="s3://aip-insurance-dev-control-dev01/ml/runs/known/input/",
        destinations=destinations,
        region="ap-southeast-2",
    )

    assert downloads == [
        ("aip-insurance-dev-control-dev01", f"ml/runs/known/input/{name}")
        for name in names
    ]
    assert [destinations[name].read_text(encoding="utf-8") for name in names] == [
        key for _, key in downloads
    ]


@pytest.mark.parametrize("uri", ["", "https://bucket/prefix", "s3://bucket", "s3:///prefix"])
def test_prepared_snapshot_rejects_invalid_s3_uri(uri, tmp_path):
    with pytest.raises(ValueError, match="s3://bucket/prefix"):
        prepare._download_prepared_snapshot(
            s3_uri=uri,
            destinations={"train.csv": tmp_path / "train.csv"},
            region="ap-southeast-2",
        )
