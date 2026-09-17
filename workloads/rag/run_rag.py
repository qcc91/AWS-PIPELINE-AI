"""Explicit V1 Bedrock KB sync/retrieval CLI (run only after plan approval)."""

import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import boto3

from .citations import build_cited_answer
from .documents import build_document_manifest, ingestion_reconciliation, load_manifest, manifest_changes, write_manifest


DEFAULT_MODEL_ARN = "arn:aws:bedrock:ap-southeast-2::foundation-model/amazon.nova-micro-v1:0"
TRANSIENT_CODES = {"ThrottlingException", "TooManyRequestsException", "ServiceUnavailableException", "InternalServerException"}


def _error_code(exc: Exception) -> str:
    response = getattr(exc, "response", {})
    return str(response.get("Error", {}).get("Code", "")) if isinstance(response, dict) else ""


def bounded_aws_call(operation, *, max_attempts: int = 3, base_delay_seconds: float = 1.0):
    """Retry only transient Bedrock failures; 429 handling is finite and visible."""
    for attempt in range(1, max_attempts + 1):
        try:
            return operation()
        except Exception as exc:
            if _error_code(exc) not in TRANSIENT_CODES or attempt == max_attempts:
                raise
            time.sleep(base_delay_seconds * (2 ** (attempt - 1)))
    raise AssertionError("unreachable")


def citation_uris(citations: list[dict]) -> list[str]:
    """Flatten and de-duplicate every S3 reference returned by Bedrock."""
    uris: list[str] = []
    for citation in citations:
        for reference in citation.get("retrievedReferences", []):
            uri = reference.get("location", {}).get("s3Location", {}).get("uri", "")
            if uri and uri not in uris:
                uris.append(uri)
    return uris


def active_ingestion_job(agent, knowledge_base_id: str, data_source_id: str) -> dict | None:
    """Return an active ingestion job so callers never start overlapping syncs."""
    jobs = agent.list_ingestion_jobs(
        knowledgeBaseId=knowledge_base_id,
        dataSourceId=data_source_id,
        maxResults=10,
    ).get("ingestionJobSummaries", [])
    return next(
        (job for job in jobs if job.get("status") in {"STARTING", "IN_PROGRESS"}),
        None,
    )


def sync_documents(agent, knowledge_base_id: str, data_source_id: str, timeout: int, *, discovered_count: int | None = None, audit_events: list[dict] | None = None) -> str:
    """Run one non-overlapping ingestion and wait for its terminal status."""
    events = audit_events if audit_events is not None else []
    try:
        active = bounded_aws_call(lambda: active_ingestion_job(agent, knowledge_base_id, data_source_id))
    except Exception as exc:
        events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "ingestion", "status": "OVERLAP_CHECK_FAILED", "error": str(exc)})
        raise
    if active:
        events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "ingestion", "status": "OVERLAP_BLOCKED", "ingestion_job_id": active["ingestionJobId"]})
        raise RuntimeError(
            f"ingestion job {active['ingestionJobId']} is already {active['status']}; "
            "refusing to start an overlapping job"
        )
    try:
        job = bounded_aws_call(
            lambda: agent.start_ingestion_job(
                knowledgeBaseId=knowledge_base_id,
                dataSourceId=data_source_id,
            )
        )
    except Exception as exc:
        events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "ingestion", "status": "START_FAILED", "error": str(exc)})
        raise
    job_id = job["ingestionJob"]["ingestionJobId"]
    events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "ingestion", "status": "STARTED", "ingestion_job_id": job_id})
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            details = bounded_aws_call(
                lambda: agent.get_ingestion_job(
                    knowledgeBaseId=knowledge_base_id,
                    dataSourceId=data_source_id,
                    ingestionJobId=job_id,
                )
            )
        except Exception as exc:
            events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "ingestion", "status": "POLL_FAILED", "ingestion_job_id": job_id, "error": str(exc)})
            raise
        details = details["ingestionJob"]
        status = details["status"]
        if status == "COMPLETE":
            event = {"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "ingestion", "status": "SUCCEEDED", "ingestion_job_id": job_id, "statistics": details.get("statistics", {})}
            if discovered_count is not None:
                event["reconciliation"] = ingestion_reconciliation(details, discovered_count)
            events.append(event)
            return job_id
        if status in {"FAILED", "STOPPED"}:
            reasons = "; ".join(details.get("failureReasons", []))
            events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "ingestion", "status": status, "ingestion_job_id": job_id, "failure_reasons": details.get("failureReasons", [])})
            raise RuntimeError(
                f"ingestion job {job_id} ended with {status}: "
                f"{reasons or 'no failure reason returned'}"
            )
        time.sleep(5)
    events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "ingestion", "status": "TIMED_OUT", "ingestion_job_id": job_id})
    raise TimeoutError(f"ingestion job {job_id} did not complete before timeout")


def retrieve_chunks(runtime, knowledge_base_id: str, question: str, number_of_results: int = 4) -> list[dict]:
    """Retrieve attributable chunks without invoking a generation model."""
    response = runtime.retrieve(
        knowledgeBaseId=knowledge_base_id,
        retrievalQuery={"text": question},
        retrievalConfiguration={
            "vectorSearchConfiguration": {"numberOfResults": number_of_results}
        },
    )
    chunks = []
    for result in response.get("retrievalResults", []):
        chunks.append(
            {
                "score": result.get("score"),
                "text": result.get("content", {}).get("text", ""),
                "uri": result.get("location", {}).get("s3Location", {}).get("uri", ""),
            }
        )
    return chunks


def run(
    region: str,
    knowledge_base_id: str,
    data_source_id: str,
    question: str,
    model_arn: str,
    timeout: int,
    sync: bool = False,
    discovered_count: int | None = None,
    audit_events: list[dict] | None = None,
) -> str:
    agent = boto3.client("bedrock-agent", region_name=region)
    runtime = boto3.client("bedrock-agent-runtime", region_name=region)
    if sync:
        sync_documents(agent, knowledge_base_id, data_source_id, timeout, discovered_count=discovered_count, audit_events=audit_events)
    events = audit_events if audit_events is not None else []
    try:
        response = bounded_aws_call(
            lambda: runtime.retrieve_and_generate(
                input={"text": question},
                retrieveAndGenerateConfiguration={
                    "type": "KNOWLEDGE_BASE",
                    "knowledgeBaseConfiguration": {
                        "knowledgeBaseId": knowledge_base_id,
                        "modelArn": model_arn,
                        "retrievalConfiguration": {"vectorSearchConfiguration": {"numberOfResults": 4}},
                    },
                },
            )
        )
    except Exception as exc:
        events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "retrieval", "status": "FAILED", "error": str(exc)})
        raise
    output = response["output"]["text"]
    uris = citation_uris(response.get("citations", []))
    if not output.strip() or not uris:
        events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "retrieval", "status": "GROUNDING_FAILED"})
        raise RuntimeError("RetrieveAndGenerate response failed citation validation")
    events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "retrieval", "status": "SUCCEEDED", "citation_count": len(uris)})
    return build_cited_answer(output, [{"uri": uri} for uri in uris])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--knowledge-base-id", required=True)
    parser.add_argument("--data-source-id", required=True)
    parser.add_argument("--question", required=True)
    parser.add_argument("--model-arn", default=DEFAULT_MODEL_ARN)
    parser.add_argument("--region", default="ap-southeast-2", choices=["ap-southeast-2"])
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument(
        "--sync",
        action="store_true",
        help="run exactly one ingestion sync after checking that no sync is active",
    )
    parser.add_argument("--document-dir", type=Path, help="validate and version the approved local document corpus")
    parser.add_argument("--document-identity-prefix", help="stable S3 prefix used to identify manifest documents")
    parser.add_argument("--manifest", type=Path, help="persist the document identity/version manifest")
    parser.add_argument("--audit-output", type=Path, help="persist ingestion and idempotency audit JSON")
    args = parser.parse_args()
    if args.sync and not (args.document_dir and args.document_identity_prefix and args.manifest and args.audit_output):
        parser.error("--sync requires --document-dir, --document-identity-prefix, --manifest, and --audit-output for V2 traceability")
    if args.document_identity_prefix and not args.document_identity_prefix.startswith("s3://"):
        parser.error("--document-identity-prefix must be an s3:// prefix")
    audit_events: list[dict] = []
    discovered_count = None
    should_sync = args.sync
    current_manifest = None
    validation_failed = False
    if args.document_dir:
        paths = [path for path in args.document_dir.rglob("*") if path.is_file()]
        current_manifest = build_document_manifest(paths, root=args.document_dir, identity_prefix=args.document_identity_prefix or "")
        discovered_count = int(current_manifest["documents_valid"])
        previous = load_manifest(args.manifest)
        changes = manifest_changes(previous, current_manifest)
        audit_events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "document_validation", "status": "PASSED" if not current_manifest["documents_rejected"] else "FAILED", "counts": {key: current_manifest[key] for key in ("documents_discovered", "documents_valid", "documents_rejected")}, "changes": changes, "quarantine": current_manifest["quarantine"]})
        if args.sync and previous is not None and not (changes["added"] or changes["changed"] or changes["deleted"]):
            should_sync = False
            audit_events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": "ingestion", "status": "UNCHANGED_SKIPPED", "reason": "all document identities and content hashes are unchanged"})
        validation_failed = bool(current_manifest["documents_rejected"])
    try:
        if validation_failed:
            raise RuntimeError("document validation failed; rejected documents must not be synchronized")
        print(run(
            args.region,
            args.knowledge_base_id,
            args.data_source_id,
            args.question,
            args.model_arn,
            args.timeout,
            should_sync,
            discovered_count,
            audit_events,
        ))
    finally:
        ingestion_committed = any(event.get("stage") == "ingestion" and event.get("status") in {"SUCCEEDED", "UNCHANGED_SKIPPED"} for event in audit_events)
        if current_manifest is not None and args.manifest and ingestion_committed:
            write_manifest(args.manifest, current_manifest)
        if args.audit_output:
            args.audit_output.parent.mkdir(parents=True, exist_ok=True)
            args.audit_output.write_text(json.dumps(audit_events, indent=2, default=str) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
