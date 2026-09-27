"""Evaluate the untouched chronological test split inside SageMaker Processing."""
from __future__ import annotations

import csv
import json
import sys
import tarfile
from pathlib import Path


CODE_DIR = Path("/opt/ml/processing/code")
sys.path.insert(0, str(CODE_DIR))

from claim_risk import evaluate_binary  # noqa: E402


def _model_file() -> Path:
    model_dir = Path("/opt/ml/processing/model")
    archives = sorted(model_dir.glob("**/*.tar.gz"))
    if archives:
        extraction = model_dir / "extracted"
        extraction.mkdir(exist_ok=True)
        with tarfile.open(archives[0], "r:gz") as archive:
            extraction_root = extraction.resolve()
            for member in archive.getmembers():
                destination = (extraction / member.name).resolve()
                if not destination.is_relative_to(extraction_root):
                    raise RuntimeError("model artifact contains an unsafe path")
                if member.issym() or member.islnk():
                    raise RuntimeError("model artifact contains an unsupported link")
            archive.extractall(extraction)
        candidates = sorted(extraction.glob("**/xgboost-model"))
    else:
        candidates = sorted(model_dir.glob("**/xgboost-model"))
    if len(candidates) != 1:
        raise RuntimeError(f"expected one xgboost-model artifact, found {len(candidates)}")
    return candidates[0]


def main() -> None:
    import xgboost as xgb

    test_files = sorted(Path("/opt/ml/processing/test").glob("**/*.csv"))
    if len(test_files) != 1:
        raise RuntimeError(f"expected one test CSV, found {len(test_files)}")

    rows = []
    with test_files[0].open(newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle):
            rows.append([float(value) for value in row])
    labels = [int(row[0]) for row in rows]
    matrix = xgb.DMatrix([row[1:] for row in rows])
    booster = xgb.Booster()
    booster.load_model(str(_model_file()))
    probabilities = [float(value) for value in booster.predict(matrix)]
    metrics = evaluate_binary(labels, probabilities)

    report = {
        "binary_classification_metrics": {
            name: {"value": value}
            for name, value in metrics.items()
            if name != "row_count"
        },
        "row_count": metrics["row_count"],
        "split": "chronological_test",
    }
    output = Path("/opt/ml/processing/evaluation/evaluation.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
