"""Offline repository gates for the GitHub PR workflow.

This check intentionally uses only the Python standard library and Git's
tracked-file list. It catches accidental state files, high-confidence
credential material, Terraform workspace isolation, and CI workflow drift
without contacting AWS or requiring credentials.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "pull-request-ci.yml"

REQUIRED_PATHS = (
    ROOT / "terraform" / "environments" / "dev",
    ROOT / "terraform" / "environments" / "prod",
    ROOT / "terraform" / "bootstrap" / "environments" / "dev",
    ROOT / "terraform" / "bootstrap" / "environments" / "prod",
    ROOT / "tests" / "data",
    ROOT / "tests" / "infrastructure",
    ROOT / "scripts" / "ci",
)

FORBIDDEN_TRACKED_SUFFIXES = (
    ".tfstate",
    ".tfstate.backup",
    ".tfplan",
    ".pem",
    ".p12",
    ".pfx",
)

# These patterns require a value and therefore do not flag documentation that
# merely mentions credential variable names or Terraform input placeholders.
CREDENTIAL_PATTERNS = (
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"ASIA[0-9A-Z]{16}"),
    re.compile(r"-----BEGIN (?:RSA|OPENSSH|EC|DSA) PRIVATE KEY-----"),
    re.compile(
        r"(?i)\baws_access_key_id\s*[:=]\s*['\"]?(?!\$|<|\{|your_|example|redacted)[A-Za-z0-9/+=]{16,}"
    ),
    re.compile(
        r"(?i)\baws_secret_access_key\s*[:=]\s*['\"]?(?!\$|<|\{|your_|example|redacted)[A-Za-z0-9/+=]{30,}"
    ),
)


def tracked_files() -> list[Path]:
    """Return tracked files, or fail closed when this is not a Git checkout."""

    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=False,
    )
    return [ROOT / item for item in result.stdout.decode().split("\0") if item]


def check_required_paths() -> list[str]:
    return [f"missing required path: {path.relative_to(ROOT)}" for path in REQUIRED_PATHS if not path.exists()]


def check_tracked_files(files: list[Path]) -> list[str]:
    findings: list[str] = []
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        lower = relative.lower()
        if any(lower.endswith(suffix) for suffix in FORBIDDEN_TRACKED_SUFFIXES):
            findings.append(f"forbidden tracked artifact: {relative}")
            continue
        if ".terraform/" in lower or lower.startswith(".terraform/"):
            findings.append(f"Terraform working directory is tracked: {relative}")
            continue
        if not path.is_file():
            continue
        try:
            raw = path.read_bytes()
        except OSError as exc:
            findings.append(f"cannot read tracked file {relative}: {exc}")
            continue
        if b"\0" in raw:
            continue
        text = raw.decode("utf-8", errors="replace")
        for pattern in CREDENTIAL_PATTERNS:
            if pattern.search(text):
                findings.append(f"possible credential material in {relative}: {pattern.pattern}")
    return findings


def check_terraform_layout(files: list[Path]) -> list[str]:
    findings: list[str] = []
    for path in files:
        if path.suffix != ".tf":
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"(?im)^\s*workspace\s*=", text):
            findings.append(f"Terraform workspaces cannot isolate environments: {path.relative_to(ROOT)}")
    return findings


def check_workflow() -> list[str]:
    findings: list[str] = []
    if not WORKFLOW.exists():
        return [f"missing workflow: {WORKFLOW.relative_to(ROOT)}"]
    text = WORKFLOW.read_text(encoding="utf-8")
    required_fragments = (
        "pull_request:",
        "permissions:",
        "contents: read",
        "terraform fmt -check -recursive terraform",
        "init -backend=false",
        "validate -no-color",
        "scripts/ci/check_repository_consistency.py",
        "tests/data",
        "tests/infrastructure",
        "tests/ml",
        "tests/rag",
    )
    for fragment in required_fragments:
        if fragment not in text:
            findings.append(f"workflow missing required CI step: {fragment}")
    forbidden_fragments = (
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "configure-aws-credentials",
        "terraform apply",
        "aws cloudformation",
        "aws cloudcontrol",
    )
    for fragment in forbidden_fragments:
        if fragment in text:
            findings.append(f"workflow contains forbidden AWS/deployment material: {fragment}")
    return findings


def main() -> int:
    findings = check_required_paths() + check_workflow()
    try:
        files = tracked_files()
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: cannot enumerate tracked files: {exc}", file=sys.stderr)
        return 1
    findings.extend(check_tracked_files(files))
    findings.extend(check_terraform_layout(files))
    if findings:
        for finding in findings:
            print(f"FAIL: {finding}", file=sys.stderr)
        return 1
    print(f"PASS: repository consistency and high-confidence credential scan ({len(files)} tracked files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
