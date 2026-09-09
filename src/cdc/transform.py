"""Dependency-free current-state CDC semantics for local tests."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from datetime import datetime


def apply_changes(
    changes: Iterable[Mapping[str, object]], *, primary_key: str
) -> list[dict[str, object]]:
    """Apply ordered I/U/D records; the highest source order wins per key."""

    latest: dict[object, Mapping[str, object]] = {}
    for change in changes:
        key = change.get(primary_key)
        if key in (None, ""):
            continue
        order = change.get("_source_order")
        if not isinstance(order, datetime):
            raise ValueError("_source_order must be a timezone-aware datetime")
        previous = latest.get(key)
        if previous is None or order >= previous["_source_order"]:
            latest[key] = change
    return [dict(change) for change in latest.values() if str(change.get("_operation", "I")).upper() != "D"]
