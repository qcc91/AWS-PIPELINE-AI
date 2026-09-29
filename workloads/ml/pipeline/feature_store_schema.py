"""Terraform external-data adapter for the canonical claim-risk feature schema."""
from __future__ import annotations

import json
import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from claim_risk import feature_store_feature_definitions  # noqa: E402


def main() -> None:
    json.load(sys.stdin)
    json.dump(
        {
            "feature_definitions": json.dumps(
                feature_store_feature_definitions(), separators=(",", ":")
            )
        },
        sys.stdout,
    )


if __name__ == "__main__":
    main()
