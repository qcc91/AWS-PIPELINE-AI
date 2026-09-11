"""Small V2 document identity, validation and ingestion-audit helpers."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Mapping


FIXED_RETRIEVAL_QUESTIONS = (
    "What is the waiting period for eligible accidental-damage claims?",
    "What repair costs are reimbursed and what amount is deducted?",
    "What information must be recorded at first notice of loss?",
)


class DocumentValidationError(ValueError):
    """A document is empty, malformed or outside the approved text contract."""


def validate_document(content: bytes, *, source: str) -> str:
    if not content or not content.strip():
        raise DocumentValidationError(f"{source}: document is empty")
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise DocumentValidationError(f"{source}: document is not valid UTF-8") from exc
    if "\x00" in text:
        raise DocumentValidationError(f"{source}: document contains NUL bytes")
    if len(text.split()) < 5:
        raise DocumentValidationError(f"{source}: document has insufficient meaningful text")
    return text


def document_record(identity: str, content: bytes) -> dict[str, object]:
    """Use location as identity and SHA-256 as immutable content version."""
    validate_document(content, source=identity)
    digest = hashlib.sha256(content).hexdigest()
    return {
        "document_id": hashlib.sha256(identity.encode("utf-8")).hexdigest()[:24],
        "source": identity,
        "content_hash": digest,
        "document_version": f"sha256:{digest}",
        "size_bytes": len(content),
        "status": "VALID",
    }


def build_document_manifest(paths: Iterable[Path], *, root: Path | None = None, identity_prefix: str = "") -> dict[str, object]:
    """Validate local documents and return accepted/rejected trace records."""
    accepted: list[dict[str, object]] = []
    rejected: list[dict[str, object]] = []
    for path in sorted(paths, key=lambda item: item.as_posix()):
        relative_name = path.relative_to(root).as_posix() if root else path.name
        identity = f"{identity_prefix.rstrip('/')}/{relative_name}" if identity_prefix else relative_name
        try:
            accepted.append(document_record(identity, path.read_bytes()))
        except (OSError, DocumentValidationError) as exc:
            rejected.append({"source": identity, "status": "REJECTED", "failure_reason": str(exc)})
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "documents_discovered": len(accepted) + len(rejected),
        "documents_valid": len(accepted),
        "documents_rejected": len(rejected),
        "documents": accepted,
        "quarantine": rejected,
    }


def manifest_changes(previous: Mapping[str, object] | None, current: Mapping[str, object]) -> dict[str, list[str]]:
    """Classify stable document versions so unchanged syncs are explicit."""
    old = {str(row["document_id"]): str(row["content_hash"]) for row in (previous or {}).get("documents", [])}  # type: ignore[union-attr]
    new = {str(row["document_id"]): str(row["content_hash"]) for row in current.get("documents", [])}  # type: ignore[union-attr]
    return {
        "added": sorted(key for key in new if key not in old),
        "changed": sorted(key for key in new if key in old and new[key] != old[key]),
        "unchanged": sorted(key for key in new if key in old and new[key] == old[key]),
        "deleted": sorted(key for key in old if key not in new),
    }


def load_manifest(path: Path | None) -> dict[str, object] | None:
    if not path or not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def write_manifest(path: Path, manifest: Mapping[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def ingestion_reconciliation(details: Mapping[str, object], discovered_count: int) -> dict[str, object]:
    stats = details.get("statistics") or {}
    if not isinstance(stats, Mapping):
        stats = {}
    scanned = int(stats.get("numberOfDocumentsScanned", 0))
    indexed = int(stats.get("numberOfNewDocumentsIndexed", 0)) + int(stats.get("numberOfModifiedDocumentsIndexed", 0))
    failed = int(stats.get("numberOfDocumentsFailed", 0))
    status = str(details.get("status", "UNKNOWN"))
    # An unchanged sync legitimately indexes zero; scanned and failed are the
    # useful reconciliation measures for that case.
    reconciled = status == "COMPLETE" and scanned == discovered_count and failed == 0
    return {
        "status": "PASSED" if reconciled else "FAILED",
        "documents_discovered": discovered_count,
        "documents_scanned": scanned,
        "documents_indexed_or_modified": indexed,
        "documents_failed": failed,
        "documents_unchanged_or_skipped": max(0, scanned - indexed - failed),
        "ingestion_status": status,
    }
