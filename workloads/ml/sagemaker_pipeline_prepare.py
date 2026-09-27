"""SageMaker Processing entry point for leakage-safe claim-risk preparation."""
from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

import boto3


CODE_DIR = Path("/opt/ml/processing/code")
sys.path.insert(0, str(CODE_DIR))

from claim_risk import prepare_dataset  # noqa: E402


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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", required=True)
    parser.add_argument("--athena-workgroup", required=True)
    parser.add_argument("--gold-database", required=True)
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
        print(json.dumps({
            "input_source": "prepared_snapshot",
            "prepared_input_uri": args.prepared_input_uri,
            "message": "Reused existing prepared snapshot; data was not queried from current Gold or revalidated.",
        }, sort_keys=True))
        return

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
    metadata = prepare_dataset(rows, work)
    for name, destination in destinations.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes((work / name).read_bytes())

    print(json.dumps(metadata, sort_keys=True))


if __name__ == "__main__":
    main()
