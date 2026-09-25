"""Publish Batch Transform predictions to Gold Iceberg and validate with Athena."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import boto3


def wait_glue(client, job_name: str, run_id: str, poll_seconds: int) -> dict:
    while True:
        result = client.get_job_run(
            JobName=job_name, RunId=run_id, PredecessorsIncluded=False
        )["JobRun"]
        state = result["JobRunState"]
        if state in {"SUCCEEDED", "FAILED", "ERROR", "TIMEOUT", "STOPPED"}:
            if state != "SUCCEEDED":
                raise RuntimeError(
                    f"Glue publication {job_name}/{run_id} ended {state}: "
                    f"{result.get('ErrorMessage', 'unknown')}"
                )
            return result
        time.sleep(poll_seconds)


def wait_athena(client, query_id: str, poll_seconds: int) -> None:
    while True:
        execution = client.get_query_execution(QueryExecutionId=query_id)["QueryExecution"]
        state = execution["Status"]["State"]
        if state in {"SUCCEEDED", "FAILED", "CANCELLED"}:
            if state != "SUCCEEDED":
                raise RuntimeError(
                    f"Athena validation {query_id} ended {state}: "
                    f"{execution['Status'].get('StateChangeReason', 'unknown')}"
                )
            return
        time.sleep(poll_seconds)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", required=True)
    parser.add_argument("--glue-job-name", required=True)
    parser.add_argument("--transform-output-uri", required=True)
    parser.add_argument("--claim-ids-uri", required=True)
    parser.add_argument("--gold-database", required=True)
    parser.add_argument("--model-version", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--athena-workgroup", required=True)
    parser.add_argument("--athena-output-uri", required=True)
    parser.add_argument("--poll-seconds", type=int, default=15)
    args = parser.parse_args()

    glue = boto3.client("glue", region_name=args.region)
    run = glue.start_job_run(
        JobName=args.glue_job_name,
        Arguments={
            "--TRANSFORM_OUTPUT_URI": args.transform_output_uri,
            "--CLAIM_IDS_URI": args.claim_ids_uri,
            "--GOLD_DATABASE": args.gold_database,
            "--GOLD_TABLE": "claim_risk",
            "--MODEL_VERSION": args.model_version,
            "--RUN_ID": args.run_id,
        },
    )
    wait_glue(glue, args.glue_job_name, run["JobRunId"], args.poll_seconds)

    athena = boto3.client("athena", region_name=args.region)
    query = athena.start_query_execution(
        QueryString=(
            "SELECT count(*) AS rows, count(DISTINCT claim_id) AS unique_claims, "
            "sum(CASE WHEN high_risk_probability IS NULL OR high_risk_probability < 0 "
            "OR high_risk_probability > 1 THEN 1 ELSE 0 END) AS invalid_probabilities "
            f'FROM "{args.gold_database}"."claim_risk"'
        ),
        QueryExecutionContext={"Database": args.gold_database},
        WorkGroup=args.athena_workgroup,
        ResultConfiguration={"OutputLocation": args.athena_output_uri},
    )
    query_id = query["QueryExecutionId"]
    wait_athena(athena, query_id, args.poll_seconds)
    result = athena.get_query_results(QueryExecutionId=query_id)
    values = [item.get("VarCharValue", "") for item in result["ResultSet"]["Rows"][1]["Data"]]
    rows, unique_claims, invalid_probabilities = map(int, values)
    if rows == 0 or rows != unique_claims or invalid_probabilities:
        raise RuntimeError(
            f"Gold validation failed: rows={rows}, unique={unique_claims}, "
            f"invalid_probabilities={invalid_probabilities}"
        )

    report = {
        "status": "PASSED",
        "glue_job_run_id": run["JobRunId"],
        "athena_query_execution_id": query_id,
        "row_count": rows,
        "unique_claim_count": unique_claims,
        "invalid_probability_count": invalid_probabilities,
    }
    output = Path("/opt/ml/processing/validation/validation.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
