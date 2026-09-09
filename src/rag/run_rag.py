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


def run(region: str, knowledge_base_id: str, data_source_id: str, question: str, model_arn: str, timeout: int) -> str:
    agent = boto3.client("bedrock-agent", region_name=region)
    runtime = boto3.client("bedrock-agent-runtime", region_name=region)
    job = agent.start_ingestion_job(knowledgeBaseId=knowledge_base_id, dataSourceId=data_source_id)
    job_id = job["ingestionJob"]["ingestionJobId"]
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = agent.get_ingestion_job(knowledgeBaseId=knowledge_base_id, dataSourceId=data_source_id, ingestionJobId=job_id)["ingestionJob"]["status"]
        if status == "COMPLETE":
            break
        if status in {"FAILED", "STOPPED"}:
            details = agent.get_ingestion_job(
                knowledgeBaseId=knowledge_base_id,
                dataSourceId=data_source_id,
                ingestionJobId=job_id,
            )["ingestionJob"]
            reasons = "; ".join(details.get("failureReasons", []))
            raise RuntimeError(f"ingestion job ended with {status}: {reasons or 'no failure reason returned'}")
        time.sleep(5)
    else:
        raise TimeoutError("ingestion job did not complete before timeout")
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
    args = parser.parse_args()
    print(run(args.region, args.knowledge_base_id, args.data_source_id, args.question, args.model_arn, args.timeout))


if __name__ == "__main__":
    main()
