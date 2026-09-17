"""Generate deterministic V1 file-based insurance reference datasets.

The two seeded product keys deliberately match the existing PostgreSQL/DMS
fixtures.  Remaining rows represent file-owned master/reference data and do
not require changes to the OLTP schema.
"""

from __future__ import annotations

import argparse
import csv
import random
from datetime import date, datetime, timezone
from pathlib import Path

SEED = 20260910
COUNTS = {
    "broker_claims": 120,
    "product_master": 30,
    "broker_master": 80,
    "branch_master": 20,
    "claim_type_reference": 16,
    "region_risk_reference": 40,
    "vehicle_reference": 500,
    "coverage_reference": 20,
}

STATES = ("NSW", "VIC", "QLD", "SA", "WA", "TAS", "ACT", "NT")
PRODUCT_TYPES = ("AUTO", "HOME", "TRAVEL", "LIFE")


def _updated_at() -> str:
    # The reference snapshot predates every synthetic claim submission so the
    # same files are safe for point-in-time feature joins.
    return datetime(2026, 8, 1, 0, 0, tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")


def _rows(rng: random.Random) -> dict[str, list[dict[str, object]]]:
    regions = []
    for index in range(COUNTS["region_risk_reference"]):
        state = STATES[index % len(STATES)]
        catastrophe = round(rng.uniform(0.08, 0.92), 3)
        theft = round(rng.uniform(0.06, 0.88), 3)
        weather = round(rng.uniform(0.10, 0.95), 3)
        aggregate = (catastrophe + theft + weather) / 3
        regions.append(
            {
                "region_code": f"REG-{index + 1:03d}",
                "state_code": state,
                "region_name": f"{state} Synthetic Risk Area {index // len(STATES) + 1}",
                "catastrophe_risk_score": catastrophe,
                "theft_risk_score": theft,
                "weather_risk_score": weather,
                "risk_tier": "HIGH" if aggregate >= 0.67 else "MEDIUM" if aggregate >= 0.34 else "LOW",
                "urban_rural_class": "URBAN" if index % 3 else "RURAL",
                "accident_risk_score": round(rng.uniform(0.08, 0.94), 3),
                "natural_hazard_risk_score": catastrophe,
                "overall_risk_band": "HIGH" if aggregate >= 0.67 else "MEDIUM" if aggregate >= 0.34 else "LOW",
                "effective_date": "2026-01-01",
                "source_updated_at": _updated_at(),
            }
        )

    branches = []
    cities = ("Sydney", "Melbourne", "Brisbane", "Adelaide", "Perth", "Hobart", "Canberra", "Darwin")
    for index in range(COUNTS["branch_master"]):
        region = regions[index % len(regions)]
        branches.append(
            {
                "branch_id": f"brn_{1001 + index}",
                "branch_code": f"BR-{index + 1:03d}",
                "branch_name": f"{cities[index % len(cities)]} Branch {index // len(cities) + 1}",
                "region_code": region["region_code"],
                "state_code": region["state_code"],
                "city": cities[index % len(cities)],
                "branch_status": "ACTIVE" if index < 18 else "INACTIVE",
                "manager_code": f"MGR-{index + 1:03d}",
                "active_flag": 1 if index < 18 else 0,
                "source_updated_at": _updated_at(),
            }
        )

    brokers = []
    for index in range(COUNTS["broker_master"]):
        branch = branches[index % len(branches)]
        brokers.append(
            {
                "broker_id": f"brk_{2001 + index}",
                "broker_code": f"BKR-{index + 1:04d}",
                "broker_name": f"Synthetic Broker {index + 1:03d}",
                "branch_id": branch["branch_id"],
                "broker_status": "ACTIVE" if index < 72 else "INACTIVE",
                "commission_rate": f"{rng.uniform(0.035, 0.145):.4f}",
                "years_experience": rng.randint(1, 28),
                "broker_tier": ("BRONZE", "SILVER", "GOLD", "PLATINUM")[index % 4],
                "active_flag": 1 if index < 72 else 0,
                "effective_date": "2026-01-01",
                "source_updated_at": _updated_at(),
            }
        )

    claim_types = []
    labels = ("Collision", "Theft", "Weather", "Fire")
    for index in range(COUNTS["claim_type_reference"]):
        product_type = PRODUCT_TYPES[index % len(PRODUCT_TYPES)]
        severity = ("LOW", "MEDIUM", "HIGH", "CATASTROPHIC")[index % 4]
        claim_types.append(
            {
                "claim_type_id": f"cty_{3001 + index}",
                "claim_type_code": f"{product_type[:2]}-{labels[index % len(labels)][:3].upper()}-{index + 1:02d}",
                "claim_type_name": f"{product_type.title()} {labels[index % len(labels)]}",
                "product_type": product_type,
                "claim_category": labels[index % len(labels)].upper(),
                "severity_band": severity,
                "severity_group": severity,
                "default_reserve_band": ("0-5K", "5K-20K", "20K-50K", "50K+")[index % 4],
                "expected_resolution_days": (5, 14, 30, 60)[index % 4],
                "high_risk_threshold_aud": (1500, 5000, 15000, 40000)[index % 4],
                "active_flag": 1,
                "source_updated_at": _updated_at(),
            }
        )

    coverages = []
    for index in range(COUNTS["coverage_reference"]):
        product_type = PRODUCT_TYPES[index % len(PRODUCT_TYPES)]
        tier = ("BASIC", "STANDARD", "PLUS", "PREMIUM", "ULTIMATE")[index % 5]
        coverages.append(
            {
                "coverage_code": f"COV-{product_type[:2]}-{index + 1:03d}",
                "coverage_name": f"{product_type.title()} {tier.title()} Cover",
                "product_type": product_type,
                "deductible_aud": (250, 500, 750, 1000, 1500)[index % 5],
                "coverage_limit_aud": (25000, 50000, 100000, 250000, 500000)[index % 5],
                "coverage_tier": tier,
                "coverage_category": product_type,
                "default_limit": (25000, 50000, 100000, 250000, 500000)[index % 5],
                "default_excess": (250, 500, 750, 1000, 1500)[index % 5],
                "optional_flag": 0 if tier in {"BASIC", "STANDARD"} else 1,
                "active_flag": 1,
                "source_updated_at": _updated_at(),
            }
        )

    vehicles = []
    makes = ("Toyota", "Mazda", "Ford", "Hyundai", "Kia", "Subaru", "Honda", "Tesla")
    models = ("Sedan", "Hatch", "SUV", "Ute", "Wagon")
    for index in range(COUNTS["vehicle_reference"]):
        model_year = rng.randint(2005, 2026)
        market_value = rng.randint(8, 140) * 1000
        vehicles.append(
            {
                "vehicle_code": f"VEH-{index + 1:05d}",
                "make": makes[index % len(makes)],
                "model": f"{models[index % len(models)]}-{index % 17 + 1}",
                "model_year": model_year,
                "vehicle_class": models[index % len(models)].upper(),
                "vehicle_type": models[index % len(models)].upper(),
                "market_value_aud": market_value,
                "manufacture_year": model_year,
                "value_band": "HIGH" if market_value >= 80000 else "MEDIUM" if market_value >= 30000 else "LOW",
                "engine_size_band": ("SMALL", "MEDIUM", "LARGE", "ELECTRIC")[index % 4],
                "repair_cost_band": ("LOW", "MEDIUM", "HIGH")[index % 3],
                "safety_rating": rng.randint(2, 5),
                "theft_risk_score": f"{rng.uniform(0.05, 0.90):.3f}",
                "theft_risk_band": ("LOW", "MEDIUM", "HIGH")[index % 3],
                "risk_category": ("STANDARD", "ELEVATED", "SPECIALIST")[index % 3],
                "source_updated_at": _updated_at(),
            }
        )

    products = []
    seeded = (
        ("prd_5001", "HOME-BASIC", "Synthetic Home Basic", "HOME"),
        ("prd_5002", "AUTO-PLUS", "Synthetic Auto Plus", "AUTO"),
    )
    for index in range(COUNTS["product_master"]):
        if index < len(seeded):
            product_id, product_code, product_name, product_type = seeded[index]
        else:
            product_type = PRODUCT_TYPES[index % len(PRODUCT_TYPES)]
            product_id = f"prd_{5100 + index}"
            product_code = f"{product_type}-FILE-{index + 1:03d}"
            product_name = f"Synthetic {product_type.title()} Product {index + 1:03d}"
        products.append(
            {
                "product_id": product_id,
                "product_code": product_code,
                "product_name": product_name,
                "product_type": product_type,
                "product_category": product_type,
                "product_status": "ACTIVE" if index < 27 else "RETIRED",
                "effective_from": date(2026, 1, 1).isoformat(),
                "effective_to": "" if index < 27 else date(2026, 12, 31).isoformat(),
                "base_premium_aud": f"{rng.uniform(280, 2600):.2f}",
                "coverage_type": ("COMPREHENSIVE", "STANDARD", "BASIC")[index % 3],
                "default_excess": (250, 500, 1000)[index % 3],
                "risk_tier": ("LOW", "MEDIUM", "HIGH")[index % 3],
                "underwriting_category": ("STANDARD", "PREFERRED", "SPECIALIST")[index % 3],
                "distribution_channel": ("BROKER", "DIRECT", "PARTNER")[index % 3],
                "max_sum_insured_aud": (100000, 250000, 500000, 1000000)[index % 4],
                "max_sum_insured": (100000, 250000, 500000, 1000000)[index % 4],
                "active_flag": 1 if index < 27 else 0,
                "expiry_date": "" if index < 27 else "2026-12-31",
                "source_updated_at": _updated_at(),
            }
        )

    # Existing OLTP fixtures are intentionally treated as immutable.  The file
    # claims use only their three established policy/customer/product links.
    policy_links = (
        ("pol_6001", "cus_4001", "prd_5001", "HOME"),
        ("pol_6002", "cus_4002", "prd_5002", "AUTO"),
        ("pol_6003", "cus_4003", "prd_5001", "HOME"),
    )
    statuses = ("SUBMITTED", "UNDER_REVIEW", "APPROVED", "REJECTED", "PAID", "CLOSED")
    policy_associations = {}
    for policy_index, (policy_id, _customer_id, _product_id, product_type) in enumerate(policy_links):
        policy_associations[policy_id] = {
            "broker": brokers[policy_index],
            "claim_type": [item for item in claim_types if item["product_type"] == product_type][policy_index],
            "coverage": [item for item in coverages if item["product_type"] == product_type][policy_index],
            "vehicle": vehicles[policy_index * 37] if product_type == "AUTO" else None,
        }
    broker_claims = []
    for index in range(COUNTS["broker_claims"]):
        policy_id, customer_id, _product_id, product_type = policy_links[index % len(policy_links)]
        association = policy_associations[policy_id]
        broker = association["broker"]
        claim_type = association["claim_type"]
        coverage = association["coverage"]
        region = regions[(index * 7) % len(regions)]
        vehicle = association["vehicle"]
        claim_amount = round(rng.triangular(250, 60000, 4500), 2)
        latent_risk = (
            float(region["catastrophe_risk_score"]) * 0.30
            + float(region["weather_risk_score"]) * 0.20
            + min(claim_amount / 50000, 1) * 0.35
            + (float(vehicle["theft_risk_score"]) * 0.15 if vehicle else 0.05)
        )
        high_risk = 1 if latent_risk + rng.uniform(-0.18, 0.18) >= 0.54 else 0
        submitted_day = 1 + index % 8
        submitted_at = datetime(2026, 9, submitted_day, 9 + index % 8, index % 60, tzinfo=timezone.utc)
        status = statuses[index % len(statuses)]
        approved = "" if status in {"SUBMITTED", "UNDER_REVIEW"} else f"{claim_amount * rng.uniform(0.35, 0.98):.2f}"
        broker_claims.append(
            {
                "claim_id": f"fclm_{900001 + index}",
                "claim_number": f"FILE-CLM-{900001 + index}",
                "policy_id": policy_id,
                "customer_id": customer_id,
                "claim_status": status,
                "incident_date": date(2026, 8, 20 + index % 10).isoformat(),
                "submitted_at": submitted_at.isoformat().replace("+00:00", "Z"),
                "claim_amount": f"{claim_amount:.2f}",
                "approved_amount": approved,
                "currency_code": "AUD",
                "description": f"Synthetic {product_type.lower()} claim {index + 1}",
                "updated_at": submitted_at.replace(hour=min(submitted_at.hour + 1, 23)).isoformat().replace("+00:00", "Z"),
                "broker_id": broker["broker_id"],
                "claim_type_id": claim_type["claim_type_id"],
                "claim_type_code": claim_type["claim_type_code"],
                "incident_region_code": region["region_code"],
                "coverage_code": coverage["coverage_code"],
                "vehicle_code": vehicle["vehicle_code"] if vehicle else "",
                "outcome_severity": "HIGH" if high_risk else "STANDARD",
                "high_risk_claim": high_risk,
            }
        )

    return {
        "broker_claims": broker_claims,
        "product_master": products,
        "broker_master": brokers,
        "branch_master": branches,
        "claim_type_reference": claim_types,
        "region_risk_reference": regions,
        "vehicle_reference": vehicles,
        "coverage_reference": coverages,
    }


def generate(output_dir: Path) -> dict[str, int]:
    """Write all datasets and return their row counts."""

    datasets = _rows(random.Random(SEED))
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, rows in datasets.items():
        path = output_dir / f"{name}.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    return {name: len(rows) for name, rows in datasets.items()}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=Path("data/file_sources"))
    args = parser.parse_args()
    for name, count in generate(args.output_dir).items():
        print(f"{name}: {count}")


if __name__ == "__main__":
    main()
