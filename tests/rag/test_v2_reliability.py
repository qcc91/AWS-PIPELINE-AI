from pathlib import Path

import pytest

from src.rag.documents import (
    FIXED_RETRIEVAL_QUESTIONS,
    build_document_manifest,
    ingestion_reconciliation,
    manifest_changes,
)
from src.rag.run_rag import bounded_aws_call, sync_documents


def test_document_identity_hash_and_unchanged_version_are_stable(tmp_path: Path):
    document = tmp_path / "guide.md"
    document.write_text("# Guide\nA valid insurance guide with stable useful content.\n", encoding="utf-8")
    first = build_document_manifest([document], root=tmp_path)
    second = build_document_manifest([document], root=tmp_path)
    assert first["documents"][0]["document_id"] == second["documents"][0]["document_id"]
    assert first["documents"][0]["document_version"].startswith("sha256:")
    assert manifest_changes(first, second) == {
        "added": [], "changed": [], "unchanged": [first["documents"][0]["document_id"]], "deleted": []
    }


def test_empty_and_malformed_documents_are_rejected_with_trace(tmp_path: Path):
    empty = tmp_path / "empty.md"
    malformed = tmp_path / "bad.md"
    empty.write_text("   ", encoding="utf-8")
    malformed.write_bytes(b"\xff\xfe\x00")
    result = build_document_manifest([empty, malformed], root=tmp_path)
    assert result["documents_discovered"] == 2
    assert result["documents_valid"] == 0
    assert result["documents_rejected"] == 2
    assert {row["status"] for row in result["quarantine"]} == {"REJECTED"}


def test_ingestion_reconciliation_supports_unchanged_sync():
    result = ingestion_reconciliation(
        {
            "status": "COMPLETE",
            "statistics": {
                "numberOfDocumentsScanned": 2,
                "numberOfNewDocumentsIndexed": 0,
                "numberOfModifiedDocumentsIndexed": 0,
                "numberOfDocumentsFailed": 0,
            },
        },
        2,
    )
    assert result["status"] == "PASSED"
    assert result["documents_unchanged_or_skipped"] == 2


def test_sync_records_terminal_status_and_reconciliation_without_overlap():
    class Agent:
        def list_ingestion_jobs(self, **_kwargs):
            return {"ingestionJobSummaries": []}

        def start_ingestion_job(self, **_kwargs):
            return {"ingestionJob": {"ingestionJobId": "job-1"}}

        def get_ingestion_job(self, **_kwargs):
            return {"ingestionJob": {"status": "COMPLETE", "statistics": {"numberOfDocumentsScanned": 2, "numberOfNewDocumentsIndexed": 0, "numberOfModifiedDocumentsIndexed": 0, "numberOfDocumentsFailed": 0}}}

    events = []
    assert sync_documents(Agent(), "kb", "source", 10, discovered_count=2, audit_events=events) == "job-1"
    assert [event["status"] for event in events] == ["STARTED", "SUCCEEDED"]
    assert events[-1]["reconciliation"]["status"] == "PASSED"


def test_bedrock_429_retry_is_bounded(monkeypatch):
    calls = []

    class Throttled(Exception):
        response = {"Error": {"Code": "ThrottlingException"}}

    def operation():
        calls.append(1)
        raise Throttled()

    monkeypatch.setattr("src.rag.run_rag.time.sleep", lambda _seconds: None)
    with pytest.raises(Throttled):
        bounded_aws_call(operation, max_attempts=3)
    assert len(calls) == 3


def test_fixed_basic_retrieval_set_remains_small_and_stable():
    assert len(FIXED_RETRIEVAL_QUESTIONS) == 3
    assert "waiting period" in FIXED_RETRIEVAL_QUESTIONS[0]


def test_approved_v1_corpus_is_valid_and_versioned():
    root = Path(__file__).parents[2] / "documents" / "rag" / "approved"
    result = build_document_manifest(root.glob("*.md"), root=root, identity_prefix="s3://docs/rag/approved/")
    assert result["documents_discovered"] == result["documents_valid"] == 2
    assert result["documents_rejected"] == 0
    assert all(row["document_version"].startswith("sha256:") for row in result["documents"])
    assert all(row["source"].startswith("s3://docs/rag/approved/") for row in result["documents"])
