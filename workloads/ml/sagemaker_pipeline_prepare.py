"""SageMaker Processing entry point for leakage-safe claim-risk preparation."""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import boto3


CODE_DIR = Path("/opt/ml/processing/code")
sys.path.insert(0, str(CODE_DIR))

from claim_risk import (  # noqa: E402
    FEATURE_STORE_EVENT_TIME,
    ID_COLUMN,
    LABEL_COLUMN,
    feature_names,
    prepare_dataset,
)


def _export_gold_features(
    *, region: str, workgroup: str, database: str, output_uri: str, poll_seconds: int
) -> Path:
    athena = boto3.client("athena", region_name=region)
    query = athena.start_query_execution(
        QueryString=(
            'SELECT * FROM "' + database + '"."claim_risk_features" '
            "ORDER BY submitted_at, claim_id"
        ),
        QueryExecutionContext={"Database": database},
        WorkGroup=workgroup,
        ResultConfiguration={"OutputLocation": output_uri},
    )
    query_id = query["QueryExecutionId"]
    while True:
        execution = athena.get_query_execution(QueryExecutionId=query_id)["QueryExecution"]
        state = execution["Status"]["State"]
        if state in {"SUCCEEDED", "FAILED", "CANCELLED"}:
            if state != "SUCCEEDED":
                raise RuntimeError(
                    f"Gold feature export {query_id} ended {state}: "
                    f"{execution['Status'].get('StateChangeReason', 'unknown')}"
                )
            break
        time.sleep(poll_seconds)

    location = execution["ResultConfiguration"]["OutputLocation"]
    bucket, key = location[5:].split("/", 1)
    destination = Path("/opt/ml/processing/source/claim_risk_features.csv")
    destination.parent.mkdir(parents=True, exist_ok=True)
    boto3.client("s3", region_name=region).download_file(bucket, key, str(destination))
    return destination


def _download_prepared_snapshot(*, s3_uri: str, destinations: dict[str, Path], region: str) -> None:
    """Copy an existing prepared ML snapshot without reprocessing its rows."""
    parsed = urlparse(s3_uri)
    prefix = parsed.path.lstrip("/").rstrip("/")
    if parsed.scheme != "s3" or not parsed.netloc or not prefix:
        raise ValueError("prepared-input-uri must be an s3://bucket/prefix URI")

    s3 = boto3.client("s3", region_name=region)
    for name, destination in destinations.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        s3.download_file(parsed.netloc, f"{prefix}/{name}", str(destination))


def _iso_event_time(value: str) -> str:
    """Normalize claim submission time to Feature Store's ISO-8601 form."""
    text = value.strip()
    if not text:
        raise ValueError("feature-store event time is empty")
    if len(text) == 10:
        text += "T00:00:00Z"
    if text.endswith(" UTC"):
        text = text[:-4] + "+00:00"
    elif text.endswith("Z"):
        text = text[:-1] + "+00:00"
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    parsed = parsed.astimezone(timezone.utc)
    timespec = "milliseconds" if parsed.microsecond else "seconds"
    return parsed.isoformat(timespec=timespec).replace("+00:00", "Z")


def _prepared_feature_store_records(destinations: dict[str, Path]) -> list[list[dict[str, str]]]:
    """Build offline records from the exact matrices consumed by XGBoost."""
    metadata = json.loads(destinations["metadata.json"].read_text(encoding="utf-8"))
    if metadata.get("features") != feature_names():
        raise ValueError("prepared metadata feature contract differs from claim_risk.py")
    with destinations["claim_ids.csv"].open(newline="", encoding="utf-8-sig") as handle:
        manifests = list(csv.DictReader(handle))
    manifests_by_split = {
        split: [row for row in manifests if row["source_split"] == split]
        for split in ("train", "validation", "test")
    }
    names = feature_names()
    records: list[list[dict[str, str]]] = []
    for split in ("train", "validation", "test"):
        with destinations[f"{split}.csv"].open(newline="", encoding="utf-8") as handle:
            matrices = list(csv.reader(handle))
        split_manifests = manifests_by_split[split]
        if len(matrices) != len(split_manifests):
            raise ValueError(
                f"{split} matrix/manifest row-count mismatch: "
                f"{len(matrices)} != {len(split_manifests)}"
            )
        for matrix, manifest in zip(matrices, split_manifests):
            if len(matrix) != len(names) + 1:
                raise ValueError(
                    f"{split} matrix has {len(matrix) - 1} features; expected {len(names)}"
                )
            label = int(matrix[0])
            if label not in {0, 1} or label != int(manifest[LABEL_COLUMN]):
                raise ValueError(f"{split} matrix/manifest label mismatch")
            values = [float(value) for value in matrix[1:]]
            if not all(math.isfinite(value) for value in values):
                raise ValueError(f"{split} matrix contains a non-finite feature")
            event_time = manifest.get(FEATURE_STORE_EVENT_TIME) or manifest["as_of_date"]
            records.append(
                [
                    {"FeatureName": ID_COLUMN, "ValueAsString": manifest[ID_COLUMN]},
                    {
                        "FeatureName": FEATURE_STORE_EVENT_TIME,
                        "ValueAsString": _iso_event_time(event_time),
                    },
                    {"FeatureName": LABEL_COLUMN, "ValueAsString": str(label)},
                    *(
                        {"FeatureName": name, "ValueAsString": str(value)}
                        for name, value in zip(names, values)
                    ),
                ]
            )
    return records


def _ingest_offline_feature_store(
    *, feature_group_name: str, destinations: dict[str, Path], region: str
) -> int:
    """Ingest the canonical prepared matrices into the offline store only."""
    feature_store = boto3.client("sagemaker-featurestore-runtime", region_name=region)
    records = _prepared_feature_store_records(destinations)
    for record in records:
        feature_store.put_record(
            FeatureGroupName=feature_group_name,
            Record=record,
            TargetStores=["OfflineStore"],
        )
    return len(records)


def _record_feature_store_metadata(
    *, feature_group_name: str, destinations: dict[str, Path], record_count: int
) -> dict[str, object]:
    metadata_path = destinations["metadata.json"]
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["feature_store"] = {
        "event_time_feature": FEATURE_STORE_EVENT_TIME,
        "feature_group_name": feature_group_name,
        "feature_names": feature_names(),
        "submitted_record_count": record_count,
        "online_store_enabled": False,
        "record_identifier_feature": ID_COLUMN,
        "target_store": "OfflineStore",
    }
    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", required=True)
    parser.add_argument("--athena-workgroup", required=True)
    parser.add_argument("--gold-database", required=True)
    parser.add_argument("--feature-group-name", required=True)
    parser.add_argument("--athena-output-uri", required=True)
    parser.add_argument("--poll-seconds", type=int, default=10)
    parser.add_argument("--prepared-input-uri", default="")
    args = parser.parse_args()

    destinations = {
        "train.csv": Path("/opt/ml/processing/train/train.csv"),
        "validation.csv": Path("/opt/ml/processing/validation/validation.csv"),
        "test.csv": Path("/opt/ml/processing/test/test.csv"),
        "inference.csv": Path("/opt/ml/processing/inference/inference.csv"),
        "claim_ids.csv": Path("/opt/ml/processing/manifest/claim_ids.csv"),
        "metadata.json": Path("/opt/ml/processing/metadata/metadata.json"),
    }
    if args.prepared_input_uri:
        _download_prepared_snapshot(
            s3_uri=args.prepared_input_uri,
            destinations=destinations,
            region=args.region,
        )
        input_metadata = {
            "input_source": "prepared_snapshot",
            "prepared_input_uri": args.prepared_input_uri,
            "message": "Reused existing prepared snapshot; data was not queried from current Gold or revalidated.",
        }
    else:
        source = _export_gold_features(
            region=args.region,
            workgroup=args.athena_workgroup,
            database=args.gold_database,
            output_uri=args.athena_output_uri,
            poll_seconds=args.poll_seconds,
        )
        with source.open(newline="", encoding="utf-8-sig") as handle:
            rows = list(csv.DictReader(handle))

        work = Path("/opt/ml/processing/work")
        prepare_dataset(rows, work)
        for name, destination in destinations.items():
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((work / name).read_bytes())
        input_metadata = {"input_source": "gold"}

    record_count = _ingest_offline_feature_store(
        feature_group_name=args.feature_group_name,
        destinations=destinations,
        region=args.region,
    )
    metadata = _record_feature_store_metadata(
        feature_group_name=args.feature_group_name,
        destinations=destinations,
        record_count=record_count,
    )
    metadata.update(input_metadata)

    print(json.dumps(metadata, sort_keys=True))


if __name__ == "__main__":
    main()
