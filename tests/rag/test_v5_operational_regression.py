"""V5 operational regression checks for the unchanged RAG path."""

import json
import sys
from pathlib import Path

import pytest

import src.rag.run_rag as run_rag
from src.rag.documents import build_document_manifest, write_manifest
from src.rag.run_rag import sync_documents


def test_unchanged_manifest_skips_ingestion_and_preserves_trace(tmp_path, monkeypatch):
    document_dir = tmp_path / "approved"
    document_dir.mkdir()
    (document_dir / "guide.md").write_text(
        "# Claims guide\n\nEligible claims have a documented waiting period.",
        encoding="utf-8",
    )
    identity_prefix = "s3://example-documents/rag/approved/"
    manifest_path = tmp_path / "manifest.json"
    audit_path = tmp_path / "audit.json"
    write_manifest(
        manifest_path,
        build_document_manifest(
            document_dir.glob("*.md"),
            root=document_dir,
            identity_prefix=identity_prefix,
        ),
    )

    calls = []

    def fake_run(
        region,
        knowledge_base_id,
        data_source_id,
        question,
        model_arn,
        timeout,
        sync=False,
        discovered_count=None,
        audit_events=None,
    ):
        calls.append({"sync": sync, "discovered_count": discovered_count})
        return "grounded answer [1]"

    monkeypatch.setattr(run_rag, "run", fake_run)
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "run_rag",
            "--knowledge-base-id",
            "kb",
            "--data-source-id",
            "source",
            "--question",
            "What is the waiting period?",
            "--document-dir",
            str(document_dir),
            "--document-identity-prefix",
            identity_prefix,
            "--manifest",
            str(manifest_path),
            "--audit-output",
            str(audit_path),
            "--sync",
        ],
    )

    run_rag.main()

    assert calls == [{"sync": False, "discovered_count": 1}]
    events = json.loads(audit_path.read_text(encoding="utf-8"))
    assert [event["status"] for event in events] == [
        "PASSED",
        "UNCHANGED_SKIPPED",
    ]
    assert not any(event["status"] == "STARTED" for event in events)


def test_failed_ingestion_exposes_terminal_reason_without_retry():
    class Agent:
        def list_ingestion_jobs(self, **_kwargs):
            return {"ingestionJobSummaries": []}

        def start_ingestion_job(self, **_kwargs):
            return {"ingestionJob": {"ingestionJobId": "failed-job"}}

        def get_ingestion_job(self, **_kwargs):
            return {
                "ingestionJob": {
                    "status": "FAILED",
                    "failureReasons": ["invalid document"],
                }
            }

    events = []
    with pytest.raises(RuntimeError, match="invalid document"):
        sync_documents(
            Agent(),
            "kb",
            "source",
            10,
            discovered_count=1,
            audit_events=events,
        )

    assert [event["status"] for event in events] == ["STARTED", "FAILED"]
    assert events[-1]["failure_reasons"] == ["invalid document"]
