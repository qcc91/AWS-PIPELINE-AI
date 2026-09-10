import pytest

from src.rag.citations import build_cited_answer, validate_citations
from src.rag.run_rag import active_ingestion_job, citation_uris, retrieve_chunks


def test_build_cited_answer_is_grounded_and_attributable():
    result = build_cited_answer(
        "The waiting period is 14 days.",
        [{"title": "Claims guide", "uri": "s3://docs/rag/approved/claims.md"}],
    )
    assert "Sources:" in result
    assert "[1] Claims guide" in result
    assert validate_citations(result, ["s3://docs/rag/approved/claims.md"])


def test_rejects_uncited_answer():
    with pytest.raises(ValueError):
        build_cited_answer("An unsupported answer", [])


def test_rejects_non_s3_source():
    with pytest.raises(ValueError):
        build_cited_answer("Answer", [{"uri": "https://example.invalid/doc"}])


def test_flattens_and_deduplicates_all_bedrock_references():
    citations = [
        {
            "retrievedReferences": [
                {"location": {"s3Location": {"uri": "s3://docs/rag/approved/claims.md"}}},
                {"location": {"s3Location": {"uri": "s3://docs/rag/approved/terms.md"}}},
            ]
        },
        {
            "retrievedReferences": [
                {"location": {"s3Location": {"uri": "s3://docs/rag/approved/claims.md"}}}
            ]
        },
    ]
    assert citation_uris(citations) == [
        "s3://docs/rag/approved/claims.md",
        "s3://docs/rag/approved/terms.md",
    ]


def test_active_ingestion_job_prevents_overlap():
    class Agent:
        def list_ingestion_jobs(self, **_kwargs):
            return {
                "ingestionJobSummaries": [
                    {"ingestionJobId": "done", "status": "COMPLETE"},
                    {"ingestionJobId": "active", "status": "IN_PROGRESS"},
                ]
            }

    assert active_ingestion_job(Agent(), "kb", "source") == {
        "ingestionJobId": "active",
        "status": "IN_PROGRESS",
    }


def test_retrieve_chunks_keeps_source_and_content():
    class Runtime:
        def retrieve(self, **_kwargs):
            return {
                "retrievalResults": [
                    {
                        "score": 0.9,
                        "content": {"text": "Fourteen calendar days."},
                        "location": {
                            "s3Location": {"uri": "s3://docs/rag/approved/claims.md"}
                        },
                    }
                ]
            }

    assert retrieve_chunks(Runtime(), "kb", "waiting period", 2) == [
        {
            "score": 0.9,
            "text": "Fourteen calendar days.",
            "uri": "s3://docs/rag/approved/claims.md",
        }
    ]
