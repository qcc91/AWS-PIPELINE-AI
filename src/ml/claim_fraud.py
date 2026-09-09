"""Pure helpers shared by local tests and the SageMaker claim-fraud job.

The SageMaker XGBoost CSV convention is: label first, then numeric features.
The claim id is carried in a sidecar manifest so predictions can be joined
back to Gold without exposing customer PII to the model.
"""
from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from typing import Iterable, Mapping

FEATURE_COLUMNS = ("claim_amount", "approved_amount", "days_to_submit", "is_approved")
RISK_LEVELS = ("LOW", "MEDIUM", "HIGH")

DETERMINISTIC_TRAINING_ROWS = (
    {"claim_id": "ml-train-1", "claim_amount": "100", "approved_amount": "0", "incident_date": "2026-09-01", "submitted_at": "2026-09-02T00:00:00Z", "claim_status": "SUBMITTED", "fraud_label": 1},
    {"claim_id": "ml-train-2", "claim_amount": "80", "approved_amount": "75", "incident_date": "2026-09-01", "submitted_at": "2026-09-02T00:00:00Z", "claim_status": "APPROVED", "fraud_label": 0},
    {"claim_id": "ml-train-3", "claim_amount": "300", "approved_amount": "0", "incident_date": "2026-09-01", "submitted_at": "2026-09-05T00:00:00Z", "claim_status": "UNDER_REVIEW", "fraud_label": 1},
    {"claim_id": "ml-train-4", "claim_amount": "50", "approved_amount": "50", "incident_date": "2026-09-01", "submitted_at": "2026-09-01T00:00:00Z", "claim_status": "APPROVED", "fraud_label": 0},
)


def deterministic_dataset() -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    """Return a stable 2/2 split with both classes in each tiny partition."""
    return list(DETERMINISTIC_TRAINING_ROWS[:2]), list(DETERMINISTIC_TRAINING_ROWS[2:])


def claim_features(row: Mapping[str, object]) -> list[float]:
    """Return stable numeric features; missing approved amount is zero."""
    submitted = str(row["submitted_at"]).replace("Z", "+00:00")
    incident = str(row["incident_date"])
    submitted_dt = datetime.fromisoformat(submitted)
    incident_dt = datetime.fromisoformat(incident).replace(tzinfo=timezone.utc)
    approved = Decimal(str(row.get("approved_amount") or "0"))
    return [
        float(Decimal(str(row["claim_amount"]))),
        float(approved),
        float((submitted_dt.date() - incident_dt.date()).days),
        float(str(row.get("claim_status", "")).upper() == "APPROVED"),
    ]


def to_xgboost_csv(rows: Iterable[Mapping[str, object]], *, label_field: str = "fraud_label") -> str:
    """Serialize rows as label-first CSV (no header), as required by XGBoost."""
    lines = []
    for row in rows:
        label = int(row.get(label_field, 0))
        lines.append(",".join([str(label), *(str(value) for value in claim_features(row))]))
    return "\n".join(lines) + ("\n" if lines else "")


def format_claim_risk(
    claim_ids: Iterable[str], probabilities: Iterable[float], *, model_version: str, run_id: str,
    prediction_timestamp: datetime | None = None,
) -> list[dict[str, object]]:
    """Build the Gold claim_risk contract from Batch Transform probabilities."""
    timestamp = (prediction_timestamp or datetime.now(timezone.utc)).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    output = []
    for claim_id, probability in zip(claim_ids, probabilities):
        p = min(1.0, max(0.0, float(probability)))
        level = "HIGH" if p >= 0.70 else "MEDIUM" if p >= 0.30 else "LOW"
        output.append({
            "claim_id": str(claim_id),
            "fraud_probability": str(Decimal(str(p)).quantize(Decimal("0.00001"), rounding=ROUND_HALF_UP)),
            "risk_level": level,
            "model_version": model_version,
            "prediction_timestamp": timestamp,
            "_run_id": run_id,
        })
    return output
