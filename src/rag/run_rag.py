"""Explicit V1 Bedrock KB sync/retrieval CLI (run only after plan approval)."""

import argparse
import time

import boto3

from .citations import build_cited_answer


DEFAULT_MODEL_ARN = "arn:aws:bedrock:ap-southeast-2::foundation-model/amazon.nova-micro-v1:0"


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


def sync_documents(agent, knowledge_base_id: str, data_source_id: str, timeout: int) -> str:
    """Run one non-overlapping ingestion and wait for its terminal status."""
    active = active_ingestion_job(agent, knowledge_base_id, data_source_id)
    if active:
        raise RuntimeError(
            f"ingestion job {active['ingestionJobId']} is already {active['status']}; "
            "refusing to start an overlapping job"
        )
    job = agent.start_ingestion_job(
        knowledgeBaseId=knowledge_base_id,
        dataSourceId=data_source_id,
    )
    job_id = job["ingestionJob"]["ingestionJobId"]
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        details = agent.get_ingestion_job(
            knowledgeBaseId=knowledge_base_id,
            dataSourceId=data_source_id,
            ingestionJobId=job_id,
        )["ingestionJob"]
        status = details["status"]
        if status == "COMPLETE":
            return job_id
        if status in {"FAILED", "STOPPED"}:
            reasons = "; ".join(details.get("failureReasons", []))
            raise RuntimeError(
                f"ingestion job {job_id} ended with {status}: "
                f"{reasons or 'no failure reason returned'}"
            )
        time.sleep(5)
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
) -> str:
    agent = boto3.client("bedrock-agent", region_name=region)
    runtime = boto3.client("bedrock-agent-runtime", region_name=region)
    if sync:
        sync_documents(agent, knowledge_base_id, data_source_id, timeout)
    response = runtime.retrieve_and_generate(
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
    output = response["output"]["text"]
    uris = citation_uris(response.get("citations", []))
    if not output.strip() or not uris:
        raise RuntimeError("RetrieveAndGenerate response failed citation validation")
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
    args = parser.parse_args()
    print(
        run(
            args.region,
            args.knowledge_base_id,
            args.data_source_id,
            args.question,
            args.model_arn,
            args.timeout,
            args.sync,
        )
    )


if __name__ == "__main__":
    main()
