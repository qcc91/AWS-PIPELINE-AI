"""Prepare and execute bounded V5 data-operability drills.

The default mode is local-only.  AWS writes require the ``execute`` command and
the explicit ``--execute`` safety latch.  The tool never deletes an object or
modifies RDS/DMS; it only uploads uniquely named synthetic Batch objects or
starts an existing Step Functions state machine.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess
import uuid


REGION = "ap-southeast-2"
LANDING_BUCKET = "aip-insurance-dev-landing-dev01"
STATE_MACHINE_ARN = (
    "arn:aws:states:ap-southeast-2:199476069493:stateMachine:"
    "insurance-dev-batch-claim-lakehouse"
)
CDC_STATE_MACHINE_ARN = (
    "arn:aws:states:ap-southeast-2:199476069493:stateMachine:"
    "insurance-dev-cdc-iceberg"
)
CONTROL_BUCKET = "aip-insurance-dev-control-dev01"
QUARANTINE_BUCKET = "aip-insurance-dev-quarantine-dev01"
RUN_ID_RE = re.compile(r"^v5-[a-z0-9-]+-\d{8}T\d{6}Z-[0-9a-f]{8}$")


def new_run_id(scenario: str, *, now: datetime | None = None, suffix: str | None = None) -> str:
    """Create a collision-resistant, Step Functions-safe V5 drill identifier."""

    clean = re.sub(r"[^a-z0-9-]+", "-", scenario.lower()).strip("-")
    if not clean:
        raise ValueError("scenario must contain letters or numbers")
    instant = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    return f"v5-{clean}-{instant:%Y%m%dT%H%M%SZ}-{suffix or uuid.uuid4().hex[:8]}"


def validate_run_id(run_id: str) -> str:
    if not RUN_ID_RE.fullmatch(run_id):
        raise ValueError("run_id must be a generated v5-<scenario>-<UTC>-<8hex> identifier")
    return run_id


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_claims(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames:
            raise ValueError("baseline CSV has no header")
        rows = list(reader)
        required = {"claim_id", "claim_number", "policy_id", "customer_id", "claim_amount"}
        missing = sorted(required - set(reader.fieldnames))
        if missing:
            raise ValueError(f"baseline CSV missing columns: {','.join(missing)}")
        if not rows:
            raise ValueError("baseline CSV must contain at least one valid row")
        return list(reader.fieldnames), rows


def prepare(baseline: Path, output_root: Path, run_id: str) -> Path:
    """Create an invalid-file drill plus byte-identical recovery/replay files."""

    run_id = validate_run_id(run_id)
    fields, rows = _read_claims(baseline)
    drill_dir = output_root / run_id
    drill_dir.mkdir(parents=True, exist_ok=False)

    valid = dict(rows[0])
    valid.update(
        {
            "claim_id": f"{run_id}-claim",
            "claim_number": f"V5-{run_id[-8:]}",
            "claim_amount": "101.00",
            "approved_amount": "",
            "description": "V5 controlled recovery row; synthetic and non-PII",
        }
    )

    def write_claims(path: Path, records: list[dict[str, str]]) -> None:
        with path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
            writer.writeheader()
            writer.writerows(records)

    # The Glue job publishes each input as the whole current Batch snapshot.
    # Keep the complete trusted baseline in every candidate so the drill can
    # never shrink Silver/Gold to a single synthetic row.
    recovery = drill_dir / "broker_claims_v5_recovery.csv"
    replay = drill_dir / "broker_claims_v5_duplicate_replay.csv"
    write_claims(recovery, [*rows, valid])
    replay.write_bytes(recovery.read_bytes())

    invalid = dict(valid)
    invalid.update({"claim_amount": "-1.00", "description": "V5 controlled invalid row; synthetic and non-PII"})
    bad_batch = drill_dir / "broker_claims_v5_bad.csv"
    with bad_batch.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows([*rows, invalid])

    prefix = f"batch/v5-drill/{run_id}"
    manifest = {
        "schema_version": 1,
        "run_id": run_id,
        "region": REGION,
        "landing_bucket": LANDING_BUCKET,
        "control_bucket": CONTROL_BUCKET,
        "quarantine_bucket": QUARANTINE_BUCKET,
        "state_machine_arn": STATE_MACHINE_ARN,
        "baseline_row_count": len(rows),
        "drill_claim_id": valid["claim_id"],
        "expected": {
            "bad_batch": {"input": len(rows) + 1, "output": len(rows), "rejected": 1, "duplicate": 0},
            "recovery": {"input": len(rows) + 1, "output": len(rows) + 1, "rejected": 0, "duplicate": 0},
            "duplicate_replay": {"input": len(rows) + 1, "output": 0, "rejected": 0, "duplicate": len(rows) + 1},
            "final_gold_count": len(rows) + 1,
        },
        "objects": {
            "missing": f"{prefix}/missing.csv",
            "bad_batch": f"{prefix}/{bad_batch.name}",
            "recovery": f"{prefix}/{recovery.name}",
            "duplicate_replay": f"{prefix}/{replay.name}",
        },
        "files": {
            "bad_batch": {"path": bad_batch.name, "sha256": sha256(bad_batch)},
            "recovery": {"path": recovery.name, "sha256": sha256(recovery)},
            "duplicate_replay": {"path": replay.name, "sha256": sha256(replay)},
        },
        "safety": {
            "synthetic": True,
            "contains_pii": False,
            "delete_operations": False,
            "aws_write_requires_execute_flag": True,
        },
    }
    manifest_path = drill_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest_path


def load_manifest(path: Path) -> dict[str, object]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    validate_run_id(str(manifest["run_id"]))
    expected_prefix = f"batch/v5-drill/{manifest['run_id']}/"
    if any(not str(key).startswith(expected_prefix) for key in manifest["objects"].values()):
        raise ValueError("manifest object escaped the V5 drill prefix")
    if manifest["safety"].get("delete_operations") is not False:
        raise ValueError("unsafe manifest")
    return manifest


def event_input(run_id: str, bucket: str, key: str) -> str:
    return json.dumps(
        {
            "version": "0",
            "id": run_id,
            "detail-type": "Object Created",
            "source": "v5.operational-drill",
            "detail": {"bucket": {"name": bucket}, "object": {"key": key}},
        },
        separators=(",", ":"),
    )


def aws_command(
    manifest_path: Path,
    scenario: str,
    profile: str | None,
    kms_key_arn: str,
    cdc_object_key: str = "",
) -> list[str]:
    manifest = load_manifest(manifest_path)
    run_id = str(manifest["run_id"])
    common = ["--region", str(manifest["region"])]
    if profile:
        common.extend(["--profile", profile])
    if scenario == "missing-input":
        return [
            "aws", "stepfunctions", "start-execution", *common,
            "--state-machine-arn", str(manifest["state_machine_arn"]),
            "--name", f"{run_id}-missing"[:80],
            "--input", event_input(run_id, str(manifest["landing_bucket"]), str(manifest["objects"]["missing"])),
        ]
    if scenario == "cdc-replay":
        if not cdc_object_key.startswith("oltp/") or ".." in cdc_object_key:
            raise ValueError("cdc_object_key must be an existing retained object under oltp/")
        cdc_run_id = run_id.replace("batch-ops", "cdc-replay")
        return [
            "aws", "stepfunctions", "start-execution", *common,
            "--state-machine-arn", CDC_STATE_MACHINE_ARN,
            "--name", cdc_run_id[:80],
            "--input", event_input(cdc_run_id, str(manifest["landing_bucket"]), cdc_object_key),
        ]
    file_key = {"bad-batch": "bad_batch", "recovery": "recovery", "duplicate-replay": "duplicate_replay"}.get(scenario)
    if not file_key:
        raise ValueError(f"unsupported scenario: {scenario}")
    if not kms_key_arn.startswith("arn:aws:kms:ap-southeast-2:"):
        raise ValueError("a valid ap-southeast-2 KMS key ARN is required for S3 writes")
    local_path = manifest_path.parent / str(manifest["files"][file_key]["path"])
    if sha256(local_path) != manifest["files"][file_key]["sha256"]:
        raise ValueError(f"fixture checksum mismatch: {local_path}")
    return [
        "aws", "s3", "cp", str(local_path),
        f"s3://{manifest['landing_bucket']}/{manifest['objects'][file_key]}",
        *common, "--sse", "aws:kms", "--sse-kms-key-id", kms_key_arn,
        "--only-show-errors",
    ]


def command_text(command: list[str]) -> str:
    """Render a copyable PowerShell command without executing it."""

    def quote(value: str) -> str:
        return "'" + value.replace("'", "''") + "'" if any(char.isspace() or char in "{}:," for char in value) else value

    return " ".join(quote(part) for part in command)


def validate_batch_audit(payload: dict[str, object]) -> list[str]:
    errors: list[str] = []
    required = {"run_id", "pipeline_name", "source", "stage", "status", "input_count", "output_count", "rejected_count", "duplicate_count"}
    missing = sorted(required - payload.keys())
    if missing:
        return [f"missing audit fields: {','.join(missing)}"]
    counts = [payload[name] for name in ("input_count", "output_count", "rejected_count", "duplicate_count")]
    if any(not isinstance(value, int) or value < 0 for value in counts):
        errors.append("audit counts must be non-negative integers")
    elif counts[0] != counts[1] + counts[2] + counts[3]:
        errors.append("batch reconciliation failed")
    if payload.get("reconciliation_passed") is not True:
        errors.append("reconciliation_passed is not true")
    return errors


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prepare_parser = sub.add_parser("prepare", help="create local synthetic drill artifacts")
    prepare_parser.add_argument("--baseline", type=Path, required=True)
    prepare_parser.add_argument("--output", type=Path, default=Path(".v5-drill"))
    prepare_parser.add_argument("--run-id", default=None)

    for name in ("show-command", "execute"):
        action = sub.add_parser(name)
        action.add_argument("--manifest", type=Path, required=True)
        action.add_argument("--scenario", choices=("missing-input", "bad-batch", "recovery", "duplicate-replay", "cdc-replay"), required=True)
        action.add_argument(
            "--profile",
            default=None,
            help="optional profile; omit when using an in-memory DataEngineer role session",
        )
        action.add_argument("--kms-key-arn", default="")
        action.add_argument("--cdc-object-key", default="")
        if name == "execute":
            action.add_argument("--execute", action="store_true", help="required safety latch for AWS writes")
    audit = sub.add_parser("validate-audit")
    audit.add_argument("--file", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.command == "prepare":
        run_id = args.run_id or new_run_id("batch-ops")
        print(prepare(args.baseline, args.output, run_id))
        return 0
    if args.command == "validate-audit":
        errors = validate_batch_audit(json.loads(args.file.read_text(encoding="utf-8")))
        print(json.dumps({"valid": not errors, "errors": errors}))
        return 0 if not errors else 2
    command = aws_command(args.manifest, args.scenario, args.profile, args.kms_key_arn, args.cdc_object_key)
    if args.command == "show-command":
        print(command_text(command))
        return 0
    if not args.execute:
        raise SystemExit("refusing AWS write: pass --execute explicitly")
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
