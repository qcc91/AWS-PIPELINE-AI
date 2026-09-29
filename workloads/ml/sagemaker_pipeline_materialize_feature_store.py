"""Materialize XGBoost channels from the SageMaker Feature Store offline table."""
from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from pathlib import Path

import boto3


CODE_DIR = Path("/opt/ml/processing/code")
sys.path.insert(0, str(CODE_DIR))

from claim_risk import (  # noqa: E402
    FEATURE_STORE_EVENT_TIME,
    ID_COLUMN,
    LABEL_COLUMN,
    feature_names,
)
from sagemaker_pipeline_prepare import _iso_event_time  # noqa: E402


def _sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _offline_query(catalog: dict[str, str], manifests: list[dict[str, str]]) -> str:
    names = [ID_COLUMN, FEATURE_STORE_EVENT_TIME, LABEL_COLUMN, *feature_names()]
    select = ", ".join(f'"{name}"' for name in names)
    record_filters = []
    for row in manifests:
        event_time = _iso_event_time(
            row.get(FEATURE_STORE_EVENT_TIME) or row["as_of_date"]
        )
        record_filters.append(
            f'("{ID_COLUMN}" = {_sql_literal(row[ID_COLUMN])} '
            f'AND "{FEATURE_STORE_EVENT_TIME}" = {_sql_literal(event_time)})'
        )
    where = " OR ".join(record_filters)
    table = (
        f'"{catalog["Catalog"]}"."{catalog["Database"]}".'
        f'"{catalog["TableName"]}"'
    )
    return (
        "WITH latest AS ("
        f"SELECT {select}, ROW_NUMBER() OVER ("
        f'PARTITION BY "{ID_COLUMN}", "{FEATURE_STORE_EVENT_TIME}" '
        'ORDER BY "api_invocation_time" DESC, "write_time" DESC) AS record_rank '
        f"FROM {table} WHERE \"is_deleted\" = false AND ({where})"
        f") SELECT {select} FROM latest WHERE record_rank = 1"
    )


def _query_rows(athena, query_id: str) -> list[dict[str, str]]:
    result = athena.get_query_results(QueryExecutionId=query_id, MaxResults=1000)
    columns = [
        column["Name"]
        for column in result["ResultSet"]["ResultSetMetadata"]["ColumnInfo"]
    ]
    rows = result["ResultSet"]["Rows"]
    return [
        {
            name: data.get("VarCharValue", "")
            for name, data in zip(columns, row["Data"])
        }
        for row in rows[1:]
    ]


def _wait_for_query(athena, query_id: str, deadline: float, poll_seconds: int) -> str:
    while time.monotonic() < deadline:
        execution = athena.get_query_execution(QueryExecutionId=query_id)[
            "QueryExecution"
        ]
        state = execution["Status"]["State"]
        if state in {"SUCCEEDED", "FAILED", "CANCELLED"}:
            return state
        time.sleep(poll_seconds)
    return "TIMEOUT"


def wait_for_offline_records(
    *,
    region: str,
    feature_group_name: str,
    workgroup: str,
    output_uri: str,
    manifests: list[dict[str, str]],
    timeout_seconds: int,
    poll_seconds: int,
) -> list[dict[str, str]]:
    """Bounded poll until every submitted record is visible in the offline table."""
    sagemaker = boto3.client("sagemaker", region_name=region)
    athena = boto3.client("athena", region_name=region)
    description = sagemaker.describe_feature_group(
        FeatureGroupName=feature_group_name
    )
    catalog = description["OfflineStoreConfig"]["DataCatalogConfig"]
    query_text = _offline_query(catalog, manifests)
    expected = {
        (
            row[ID_COLUMN],
            _iso_event_time(
                row.get(FEATURE_STORE_EVENT_TIME) or row["as_of_date"]
            ),
        )
        for row in manifests
    }
    deadline = time.monotonic() + timeout_seconds
    last_state = "NOT_STARTED"
    last_count = 0
    while time.monotonic() < deadline:
        query_id = athena.start_query_execution(
            QueryString=query_text,
            QueryExecutionContext={
                "Catalog": catalog["Catalog"],
                "Database": catalog["Database"],
            },
            WorkGroup=workgroup,
            ResultConfiguration={
                "OutputLocation": output_uri.rstrip("/")
                + "/feature-store-readback/"
            },
        )["QueryExecutionId"]
        last_state = _wait_for_query(
            athena, query_id, deadline=deadline, poll_seconds=poll_seconds
        )
        if last_state == "SUCCEEDED":
            rows = _query_rows(athena, query_id)
            keys = {
                (row[ID_COLUMN], _iso_event_time(row[FEATURE_STORE_EVENT_TIME]))
                for row in rows
            }
            last_count = len(keys)
            if keys == expected:
                return rows
        if time.monotonic() < deadline:
            time.sleep(poll_seconds)
    raise TimeoutError(
        "Feature Store offline readback timed out after "
        f"{timeout_seconds}s (state={last_state}, visible={last_count}, "
        f"expected={len(expected)})"
    )


def write_materialized_channels(
    *, rows: list[dict[str, str]], manifests: list[dict[str, str]], output_root: Path
) -> None:
    by_key = {
        (row[ID_COLUMN], _iso_event_time(row[FEATURE_STORE_EVENT_TIME])): row
        for row in rows
    }
    names = feature_names()
    ordered: list[dict[str, str]] = []
    for split in ("train", "validation", "test"):
        split_rows = []
        for manifest in manifests:
            if manifest["source_split"] != split:
                continue
            key = (
                manifest[ID_COLUMN],
                _iso_event_time(
                    manifest.get(FEATURE_STORE_EVENT_TIME)
                    or manifest["as_of_date"]
                ),
            )
            row = by_key[key]
            if int(row[LABEL_COLUMN]) != int(manifest[LABEL_COLUMN]):
                raise ValueError(f"offline label mismatch for {manifest[ID_COLUMN]}")
            split_rows.append(row)
            ordered.append(row)
        destination = output_root / split / f"{split}.csv"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            "\n".join(
                ",".join([row[LABEL_COLUMN], *(row[name] for name in names)])
                for row in split_rows
            )
            + "\n",
            encoding="utf-8",
        )
    inference = output_root / "inference" / "inference.csv"
    inference.parent.mkdir(parents=True, exist_ok=True)
    inference.write_text(
        "\n".join(
            ",".join(row[name] for name in names) for row in ordered
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", required=True)
    parser.add_argument("--feature-group-name", required=True)
    parser.add_argument("--athena-workgroup", required=True)
    parser.add_argument("--athena-output-uri", required=True)
    parser.add_argument("--timeout-seconds", type=int, default=1200)
    parser.add_argument("--poll-seconds", type=int, default=20)
    args = parser.parse_args()

    manifest_path = Path("/opt/ml/processing/input/manifest/claim_ids.csv")
    with manifest_path.open(newline="", encoding="utf-8-sig") as handle:
        manifests = list(csv.DictReader(handle))
    rows = wait_for_offline_records(
        region=args.region,
        feature_group_name=args.feature_group_name,
        workgroup=args.athena_workgroup,
        output_uri=args.athena_output_uri,
        manifests=manifests,
        timeout_seconds=args.timeout_seconds,
        poll_seconds=args.poll_seconds,
    )
    output_root = Path("/opt/ml/processing")
    write_materialized_channels(
        rows=rows, manifests=manifests, output_root=output_root
    )

    metadata = json.loads(
        Path("/opt/ml/processing/input/metadata/metadata.json").read_text(
            encoding="utf-8"
        )
    )
    metadata["feature_store"].update(
        {
            "materialized_record_count": len(rows),
            "training_source": "offline_store_readback",
        }
    )
    metadata_output = output_root / "metadata" / "metadata.json"
    metadata_output.parent.mkdir(parents=True, exist_ok=True)
    metadata_output.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(metadata["feature_store"], sort_keys=True))


if __name__ == "__main__":
    main()
