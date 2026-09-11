"""Dependency-free V2 audit, quarantine, identity, and reconciliation contracts.

The AWS jobs persist equivalent JSON documents in the existing control and
quarantine buckets.  These types deliberately stay storage-neutral so the
semantics can be verified without AWS credentials.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from hashlib import sha256
from typing import Iterable

TERMINAL_STATUSES = frozenset({"SUCCEEDED", "FAILED", "DUPLICATE", "QUARANTINED"})


def file_identity(content: bytes) -> str:
    """Return the stable identity of file content, independent of S3 key."""

    return sha256(content).hexdigest()


def reconcile_batch(*, input_count: int, output_count: int, rejected_count: int, duplicate_count: int) -> bool:
    """Apply the V2 Batch reconciliation equation."""

    counts = (input_count, output_count, rejected_count, duplicate_count)
    if any(not isinstance(value, int) or value < 0 for value in counts):
        raise ValueError("reconciliation counts must be non-negative integers")
    return input_count == output_count + rejected_count + duplicate_count


@dataclass(frozen=True)
class QuarantineRecord:
    run_id: str
    source: str
    entity: str
    source_record: dict[str, object]
    failed_rules: tuple[str, ...]
    rejected_at: str

    @classmethod
    def create(
        cls,
        *,
        run_id: str,
        source: str,
        entity: str,
        source_record: dict[str, object],
        failed_rules: Iterable[str],
        rejected_at: datetime | None = None,
    ) -> "QuarantineRecord":
        rules = tuple(sorted(set(failed_rules)))
        if not rules:
            raise ValueError("a quarantined record needs at least one failed rule")
        instant = (rejected_at or datetime.now(timezone.utc)).astimezone(timezone.utc)
        return cls(run_id, source, entity, source_record, rules, instant.isoformat())

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass
class PipelineAudit:
    run_id: str
    pipeline_name: str
    source: str
    stage: str
    status: str = "RUNNING"
    start_time: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    end_time: str | None = None
    input_count: int = 0
    output_count: int = 0
    rejected_count: int = 0
    duplicate_count: int = 0
    quality_score: float | None = None
    error_message: str | None = None
    source_identity: str | None = None
    reconciliation_passed: bool | None = None

    def finish(
        self,
        status: str,
        *,
        input_count: int,
        output_count: int,
        rejected_count: int = 0,
        duplicate_count: int = 0,
        error_message: str | None = None,
        reconciliation_passed: bool | None = None,
        ended_at: datetime | None = None,
    ) -> None:
        normalized = status.upper()
        if normalized not in TERMINAL_STATUSES:
            raise ValueError(f"unsupported terminal status: {status}")
        counts = (input_count, output_count, rejected_count, duplicate_count)
        if any(not isinstance(value, int) or value < 0 for value in counts):
            raise ValueError("audit counts must be non-negative integers")
        self.status = normalized
        self.input_count, self.output_count, self.rejected_count, self.duplicate_count = counts
        accepted = output_count + duplicate_count
        self.quality_score = round(accepted / input_count, 6) if input_count else 1.0
        self.error_message = error_message
        self.reconciliation_passed = reconciliation_passed
        instant = (ended_at or datetime.now(timezone.utc)).astimezone(timezone.utc)
        self.end_time = instant.isoformat()

    def as_dict(self) -> dict[str, object]:
        return asdict(self)
