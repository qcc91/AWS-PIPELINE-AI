"""Leakage-safe, reproducible dataset preparation for claim risk."""
from __future__ import annotations

import csv
import hashlib
import json
import math
from collections import Counter
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Iterable, Mapping, Sequence

SEED = 42
LABEL_COLUMN = "high_risk_claim"
ID_COLUMN = "claim_id"
DATASET_VERSION_PREFIX = "claim-risk-v2"
LEAKAGE_FIELDS = frozenset(
    {
        "approved_amount",
        "paid_amount",
        "claim_status",
        "outcome_severity",
        "investigation_result",
        "settlement_duration",
        "updated_at",
    }
)

# Every feature is known at claim submission. Outcome severity, approved/paid
# amounts, final status, settlement duration and update timestamps are excluded.
NUMERIC_FEATURES = (
    "claim_amount",
    "reporting_delay_days",
    "years_experience",
    "catastrophe_risk_score",
    "region_theft_risk_score",
    "weather_risk_score",
    "accident_risk_score",
    "deductible_aud",
    "coverage_limit_aud",
    "optional_flag",
    "market_value_aud",
    "safety_rating",
    "vehicle_age",
)

CATEGORICAL_LEVELS = {
    "product_type": ("AUTO", "HOME", "LIFE", "TRAVEL", "OTHER"),
    "product_risk_tier": ("LOW", "MEDIUM", "HIGH", "OTHER"),
    "broker_tier": ("BRONZE", "SILVER", "GOLD", "PLATINUM", "OTHER"),
    "claim_category": ("COLLISION", "FIRE", "THEFT", "WEATHER", "OTHER"),
    "overall_risk_band": ("LOW", "MEDIUM", "HIGH", "OTHER"),
    "coverage_tier": ("BASIC", "PLUS", "STANDARD", "PREMIUM", "ULTIMATE", "OTHER"),
    "repair_cost_band": ("LOW", "MEDIUM", "HIGH", "OTHER"),
    "theft_risk_band": ("LOW", "MEDIUM", "HIGH", "OTHER"),
    "vehicle_risk_category": ("STANDARD", "ELEVATED", "SPECIALIST", "OTHER"),
}


def feature_names() -> list[str]:
    return [*NUMERIC_FEATURES, *(f"{column}__{level}" for column, levels in CATEGORICAL_LEVELS.items() for level in levels)]


class DatasetValidationError(ValueError):
    """Raised before any ML compute is submitted when the dataset is unsafe."""

    def __init__(self, issues: Sequence[str]):
        self.issues = list(issues)
        super().__init__("feature dataset validation failed: " + "; ".join(self.issues))


def _parse_date(value: object, field: str) -> date:
    text = str(value or "").strip()
    if not text:
        raise ValueError(f"{field} is null")
    if text.endswith(" UTC"):
        text = text[:-4] + "+00:00"
    text = text.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text).date()
    except ValueError as exc:
        raise ValueError(f"{field} is invalid") from exc


def dataset_version(rows: Sequence[Mapping[str, object]]) -> str:
    """Return a stable version for the logical, order-independent dataset."""
    fields = [ID_COLUMN, LABEL_COLUMN, "submitted_at", "as_of_date", "feature_version", *NUMERIC_FEATURES, *CATEGORICAL_LEVELS]
    logical_rows = [
        {field: str(row.get(field, "")).strip() for field in fields}
        for row in sorted(rows, key=lambda item: str(item.get(ID_COLUMN, "")))
    ]
    digest = hashlib.sha256(
        json.dumps(logical_rows, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return f"{DATASET_VERSION_PREFIX}-{digest[:16]}"


def validate_feature_dataset(rows: Sequence[Mapping[str, object]]) -> dict[str, object]:
    """Validate the prediction-time contract and return auditable DQ results."""
    issues: list[str] = []
    seen: Counter[str] = Counter()
    labels: Counter[int] = Counter()
    as_of_dates: list[date] = []
    if not rows:
        issues.append("dataset is empty")
    if LEAKAGE_FIELDS.intersection(feature_names()):
        issues.append("feature contract contains post-submission leakage fields")

    for index, row in enumerate(rows, 1):
        claim_id = str(row.get(ID_COLUMN, "")).strip()
        if not claim_id:
            issues.append(f"row {index}: claim_id is null")
        else:
            seen[claim_id] += 1
        try:
            label = int(str(row.get(LABEL_COLUMN, "")).strip())
            if label not in {0, 1}:
                raise ValueError
            labels[label] += 1
        except (TypeError, ValueError):
            issues.append(f"row {index}: {LABEL_COLUMN} must be 0 or 1")

        for feature in NUMERIC_FEATURES:
            try:
                if feature != "reporting_delay_days" and not str(row.get(feature, "")).strip():
                    raise ValueError
                value = _reporting_delay(row) if feature == "reporting_delay_days" else _number(row.get(feature))
                if not math.isfinite(value):
                    raise ValueError
                if feature in {"claim_amount", "reporting_delay_days", "years_experience", "deductible_aud", "coverage_limit_aud", "market_value_aud", "vehicle_age"} and value < 0:
                    raise ValueError
                if feature in {"catastrophe_risk_score", "region_theft_risk_score", "weather_risk_score", "accident_risk_score"} and not 0 <= value <= 1:
                    raise ValueError
                if feature == "optional_flag" and value not in {0, 1}:
                    raise ValueError
                if feature == "safety_rating" and not 1 <= value <= 5:
                    raise ValueError
                if feature == "years_experience" and value > 80:
                    raise ValueError
                if feature == "vehicle_age" and value > 100:
                    raise ValueError
            except (TypeError, ValueError, KeyError):
                issues.append(f"row {index}: {feature} is null, invalid, or outside its allowed range")
        for feature in CATEGORICAL_LEVELS:
            if not str(row.get(feature, "")).strip():
                issues.append(f"row {index}: {feature} is null")
        try:
            submitted = _parse_date(row.get("submitted_at"), "submitted_at")
            as_of = _parse_date(row.get("as_of_date") or row.get("submitted_at"), "as_of_date")
            if as_of > submitted:
                issues.append(f"row {index}: as_of_date is after claim submission")
            as_of_dates.append(as_of)
        except ValueError as exc:
            issues.append(f"row {index}: {exc}")

    duplicates = sorted(key for key, count in seen.items() if count > 1)
    if duplicates:
        issues.append(f"duplicate claim_id values: {','.join(duplicates)}")
    if rows and set(labels) != {0, 1}:
        issues.append("label distribution must contain both classes")
    if issues:
        raise DatasetValidationError(issues)
    version = dataset_version(rows)
    return {
        "status": "PASSED",
        "row_count": len(rows),
        "unique_claim_count": len(seen),
        "duplicate_claim_count": 0,
        "class_distribution": dict(labels),
        "dataset_version": version,
        "as_of_date_min": min(as_of_dates).isoformat(),
        "as_of_date_max": max(as_of_dates).isoformat(),
        "feature_count": len(feature_names()),
        "leakage_fields_in_feature_contract": [],
    }


def _number(value: object) -> float:
    if value is None or str(value).strip() == "":
        return 0.0
    return float(value)


def _reporting_delay(row: Mapping[str, object]) -> float:
    if str(row.get("reporting_delay_days", "")).strip():
        return _number(row["reporting_delay_days"])
    incident = datetime.fromisoformat(str(row["incident_date"])[:10]).date()
    submitted_text = str(row["submitted_at"]).strip()
    if submitted_text.endswith(" UTC"):
        submitted_text = submitted_text[:-4] + "+00:00"
    else:
        submitted_text = submitted_text.replace("Z", "+00:00")
    submitted = datetime.fromisoformat(submitted_text).date()
    return float((submitted - incident).days)


def vectorize(row: Mapping[str, object]) -> list[float]:
    numeric = []
    for name in NUMERIC_FEATURES:
        numeric.append(_reporting_delay(row) if name == "reporting_delay_days" else _number(row.get(name)))
    categorical = []
    for column, levels in CATEGORICAL_LEVELS.items():
        raw = str(row.get(column, "")).upper()
        value = raw if raw in levels[:-1] else "OTHER"
        categorical.extend(float(value == level) for level in levels)
    return numeric + categorical


def chronological_split(rows: Sequence[Mapping[str, object]]) -> dict[str, list[Mapping[str, object]]]:
    """Strict submitted_at 60/20/20 split so future claims cannot train the past."""
    ordered = sorted(rows, key=lambda row: (str(row["submitted_at"]), str(row[ID_COLUMN])))
    train_end = math.floor(len(ordered) * 0.60)
    validation_end = math.floor(len(ordered) * 0.80)
    result = {"train": ordered[:train_end], "validation": ordered[train_end:validation_end], "test": ordered[validation_end:]}
    for name, split_rows in result.items():
        if {int(row[LABEL_COLUMN]) for row in split_rows} != {0, 1}:
            raise ValueError(f"{name} split must contain both target classes")
    return result


def xgboost_lines(rows: Iterable[Mapping[str, object]], include_label: bool) -> list[str]:
    lines = []
    for row in rows:
        values = vectorize(row)
        if include_label:
            values = [int(row[LABEL_COLUMN]), *values]
        lines.append(",".join(str(value) for value in values))
    return lines


def evaluate_binary(labels: Sequence[int], probabilities: Sequence[float], threshold: float = 0.5) -> dict[str, float | int]:
    if len(labels) != len(probabilities) or not labels:
        raise ValueError("labels and probabilities must have equal non-zero length")
    positives = sum(labels)
    negatives = len(labels) - positives
    if not positives or not negatives:
        raise ValueError("evaluation needs both classes")
    concordant = ties = 0
    for score, label in zip(probabilities, labels):
        if label:
            for other_score, other_label in zip(probabilities, labels):
                if not other_label:
                    concordant += score > other_score
                    ties += score == other_score
    auc = (concordant + 0.5 * ties) / (positives * negatives)
    clipped = [min(1 - 1e-15, max(1e-15, float(p))) for p in probabilities]
    log_loss = -sum(y * math.log(p) + (1 - y) * math.log(1 - p) for y, p in zip(labels, clipped)) / len(labels)
    predicted = [int(p >= threshold) for p in probabilities]
    tp = sum(y == p == 1 for y, p in zip(labels, predicted))
    fp = sum(y == 0 and p == 1 for y, p in zip(labels, predicted))
    fn = sum(y == 1 and p == 0 for y, p in zip(labels, predicted))
    accuracy = sum(y == p for y, p in zip(labels, predicted)) / len(labels)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"row_count": len(labels), "auc": auc, "log_loss": log_loss, "accuracy": accuracy, "precision": precision, "recall": recall, "f1": f1}


def prepare_dataset(rows: Sequence[Mapping[str, object]], output_dir: Path, seed: int = SEED) -> dict[str, object]:
    """Write deterministic SageMaker CSVs, manifests and audit metadata."""
    validation = validate_feature_dataset(rows)
    output_dir.mkdir(parents=True, exist_ok=True)
    splits = chronological_split(rows)
    for name, split_rows in splits.items():
        (output_dir / f"{name}.csv").write_text("\n".join(xgboost_lines(split_rows, include_label=True)) + "\n", encoding="utf-8")
    ordered = [row for name in ("train", "validation", "test") for row in splits[name]]
    (output_dir / "inference.csv").write_text("\n".join(xgboost_lines(ordered, include_label=False)) + "\n", encoding="utf-8")
    with (output_dir / "claim_ids.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["claim_id", "as_of_date", "feature_version", "dataset_version", "source_split", "high_risk_claim"])
        writer.writeheader()
        for name in ("train", "validation", "test"):
            for row in splits[name]:
                writer.writerow({"claim_id": row[ID_COLUMN], "as_of_date": str(row.get("as_of_date") or row["submitted_at"])[:10], "feature_version": str(row.get("feature_version") or "v1"), "dataset_version": validation["dataset_version"], "source_split": name, "high_risk_claim": row[LABEL_COLUMN]})
    metadata = {
        "seed": seed,
        "prepared_at": datetime.now(timezone.utc).isoformat(),
        "validation": validation,
        "dataset_version": validation["dataset_version"],
        "target": LABEL_COLUMN,
        "target_definition": "Future synthetic high-severity or high-cost outcome after claim submission",
        "prediction_time": "claim submitted_at",
        "features": feature_names(),
        "excluded_leakage_fields": ["approved_amount", "paid_amount", "claim_status", "outcome_severity", "updated_at", "settlement_duration"],
        "excluded_redundant_features": ["natural_hazard_risk_score"],
        "row_count": len(rows),
        "class_distribution": dict(Counter(int(row[LABEL_COLUMN]) for row in rows)),
        "split_counts": {name: len(split_rows) for name, split_rows in splits.items()},
        "split_class_distribution": {name: dict(Counter(int(row[LABEL_COLUMN]) for row in split_rows)) for name, split_rows in splits.items()},
        "categorical_coverage": {
            column: dict(Counter((str(row.get(column, "")).upper() or "MISSING") for row in rows))
            for column in CATEGORICAL_LEVELS
        },
    }
    matrix = [vectorize(row) for row in rows]
    metadata["constant_features"] = [name for index, name in enumerate(feature_names()) if len({values[index] for values in matrix}) <= 1]
    metadata["low_variance_features"] = metadata["constant_features"]
    (output_dir / "metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return metadata
