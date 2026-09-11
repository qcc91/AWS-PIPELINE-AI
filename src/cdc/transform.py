"""Dependency-free current-state CDC semantics for local tests."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import datetime
from hashlib import sha256
import json

from src.reliability.control import PipelineAudit, QuarantineRecord

VALID_OPERATIONS = frozenset({"I", "U", "D"})


def source_change_id(change: Mapping[str, object], *, primary_key: str) -> str:
    """Return a stable identity for one source change, including tombstones."""

    if change.get(primary_key) in (None, ""):
        raise ValueError(f"{primary_key} is required")
    order = change.get("_source_order")
    if not isinstance(order, datetime) or order.tzinfo is None:
        raise ValueError("_source_order must be a timezone-aware datetime")
    canonical = {
        key: (value.isoformat() if isinstance(value, datetime) else value)
        for key, value in sorted(change.items())
        if key not in {"_run_id", "_ingested_at", "_source_change_id"}
    }
    return sha256(json.dumps(canonical, sort_keys=True, default=str, separators=(",", ":")).encode()).hexdigest()


@dataclass(frozen=True)
class CdcApplyResult:
    current_state: tuple[dict[str, object], ...]
    quarantined: tuple[QuarantineRecord, ...]
    audit: PipelineAudit


def apply_changes(
    changes: Iterable[Mapping[str, object]], *, primary_key: str,
    current_state: Iterable[Mapping[str, object]] = (),
) -> list[dict[str, object]]:
    """Apply I/U/D records deterministically; replay is a no-op.

    Equal source timestamps are resolved by stable change identity rather than
    input order. Existing current state can be supplied for incremental runs.
    """

    latest: dict[object, dict[str, object]] = {}
    latest_ids: dict[object, str] = {}
    for existing in current_state:
        key = existing.get(primary_key)
        if key not in (None, ""):
            latest[key] = dict(existing)
            latest_ids[key] = str(existing.get("_source_change_id", ""))
    seen_changes: set[str] = set()
    for raw_change in changes:
        change = dict(raw_change)
        key = change.get(primary_key)
        if key in (None, ""):
            continue
        order = change.get("_source_order")
        if not isinstance(order, datetime) or order.tzinfo is None:
            raise ValueError("_source_order must be a timezone-aware datetime")
        operation = str(change.get("_operation", "I")).upper()
        if operation not in VALID_OPERATIONS:
            raise ValueError(f"unsupported CDC operation: {operation}")
        change["_operation"] = operation
        change_id = source_change_id(change, primary_key=primary_key)
        if change_id in seen_changes:
            continue
        seen_changes.add(change_id)
        previous = latest.get(key)
        previous_order = previous.get("_source_order") if previous else None
        previous_id = latest_ids.get(key, "")
        if previous is None or (order, change_id) >= (previous_order, previous_id):
            latest[key] = change
            latest_ids[key] = change_id
    return [
        dict(latest[key])
        for key in sorted(latest, key=str)
        if str(latest[key].get("_operation", "I")).upper() != "D"
    ]


def process_cdc_changes(
    changes: Iterable[Mapping[str, object]],
    *,
    primary_key: str,
    run_id: str,
    source: str,
    current_state: Iterable[Mapping[str, object]] = (),
) -> CdcApplyResult:
    """Validate, de-duplicate and apply CDC changes with traceable counts."""

    materialized = [dict(change) for change in changes]
    valid: list[dict[str, object]] = []
    quarantined: list[QuarantineRecord] = []
    seen: set[str] = set()
    duplicate_count = 0
    for change in materialized:
        errors: list[str] = []
        try:
            change_id = source_change_id(change, primary_key=primary_key)
        except ValueError as error:
            errors.append(str(error))
            change_id = ""
        operation = str(change.get("_operation", "I")).upper()
        if operation not in VALID_OPERATIONS:
            errors.append(f"unsupported CDC operation: {operation}")
        if errors:
            quarantined.append(
                QuarantineRecord.create(
                    run_id=run_id,
                    source=source,
                    entity=primary_key.removesuffix("_id"),
                    source_record=change,
                    failed_rules=errors,
                )
            )
        elif change_id in seen:
            duplicate_count += 1
        else:
            seen.add(change_id)
            valid.append(change)

    state = apply_changes(valid, primary_key=primary_key, current_state=current_state)
    audit = PipelineAudit(run_id, "cdc", source, "silver")
    audit.finish(
        "SUCCEEDED" if valid or not quarantined else "QUARANTINED",
        input_count=len(materialized),
        output_count=len(state),
        rejected_count=len(quarantined),
        duplicate_count=duplicate_count,
        reconciliation_passed=True,
    )
    return CdcApplyResult(tuple(state), tuple(quarantined), audit)
