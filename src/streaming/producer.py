"""Small Kinesis producer for the V1 streaming happy path.

The module keeps boto3 imports lazy so contract generation and tests work
without AWS credentials. It intentionally does not implement V2 retries or
deduplication; Kinesis partitioning uses the business identifier when present.
"""

from __future__ import annotations

import argparse
import json
import uuid
from datetime import datetime, timezone
from typing import Any, Iterable, Mapping

EVENT_TYPES = {
    "QUOTE_CREATED": ("customer_id", "policy_id"),
    "POLICY_VIEWED": ("policy_id",),
    "CLAIM_SUBMITTED": ("claim_id", "policy_id", "customer_id"),
    "LOGIN": ("customer_id",),
    "PAYMENT_ATTEMPT": ("payment_id", "policy_id"),
}


def build_event(
    event_type: str,
    payload: Mapping[str, Any],
    *,
    source: str = "claims-api",
    event_id: str | None = None,
    event_timestamp: datetime | None = None,
    correlation_id: str | None = None,
    **business_ids: str | None,
) -> dict[str, Any]:
    """Build and validate one schema-version-1 streaming envelope."""

    if event_type not in EVENT_TYPES:
        raise ValueError(f"unsupported event_type: {event_type}")
    required = EVENT_TYPES[event_type]
    missing = [key for key in required if not business_ids.get(key)]
    if missing:
        raise ValueError(f"missing business identifiers: {','.join(missing)}")
    timestamp = event_timestamp or datetime.now(timezone.utc)
    if timestamp.tzinfo is None:
        raise ValueError("event_timestamp must include a timezone")
    event = {
        "schema_version": 1,
        "event_id": event_id or f"evt_{uuid.uuid4().hex}",
        "event_type": event_type,
        "event_timestamp": timestamp.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "source": source.strip(),
        **{key: value for key, value in business_ids.items() if value is not None},
        "correlation_id": correlation_id or f"corr_{uuid.uuid4().hex}",
        "payload": dict(payload),
    }
    if not event["source"] or not event["payload"]:
        raise ValueError("source and payload must be non-empty")
    return event


def send_events(stream_name: str, events: Iterable[Mapping[str, Any]], *, region: str) -> int:
    """Send newline-delimited JSON records to Kinesis and return record count."""

    import boto3  # imported only when the real producer is invoked

    client = boto3.client("kinesis", region_name=region)
    count = 0
    for event in events:
        record = dict(event)
        partition_key = next((record.get(key) for key in ("claim_id", "policy_id", "customer_id", "payment_id") if record.get(key)), record["event_id"])
        client.put_record(StreamName=stream_name, Data=(json.dumps(record, separators=(",", ":") + "\n").encode("utf-8")), PartitionKey=str(partition_key))
        count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description="Send one V1 insurance event to Kinesis")
    parser.add_argument("--stream-name", required=True)
    parser.add_argument("--region", default="ap-southeast-2")
    parser.add_argument("--event-type", default="CLAIM_SUBMITTED", choices=sorted(EVENT_TYPES))
    parser.add_argument("--customer-id", default=None)
    parser.add_argument("--policy-id", default=None)
    parser.add_argument("--claim-id", default=None)
    parser.add_argument("--payment-id", default=None)
    parser.add_argument("--payload", default='{"claim_amount":"125.00","currency_code":"AUD"}')
    args = parser.parse_args()
    event = build_event(args.event_type, json.loads(args.payload), customer_id=args.customer_id, policy_id=args.policy_id, claim_id=args.claim_id, payment_id=args.payment_id)
    print(f"sent {send_events(args.stream_name, [event], region=args.region)} event(s): {event['event_id']}")


if __name__ == "__main__":
    main()
