#!/usr/bin/env python3
"""Static, offline audit of the repository delivery-workflow policy.

Kizarolag a repo FAJLJAIT olvassa: nem hiv halozatot, nem futtat `gh`-t es
tokent nem olvas (ADR 0444 D2). A CI-kapu a Dart oldalon fut
(`test/tooling/repository_policy_test.dart`, `package:yaml` nelkul, ADR 0444
D3); ez a script egy FUGGETLEN, operator-oldali meres ugyanazokra a
fajlokra, teljes YAML-ervenyesseggel (PyYAML).

`--dry-run` az EGYETLEN tamogatott mod - a script sosem ir a repoba, irasi
ag nincs. A live branch-protection ellenorzeshez szukseges `gh api`
parancsot KIIRJA, de nem futtatja: az Administration-jogu ellenorzes
operatori lepes, nem script-ag ("ha van token, hivjuk az API-t" TILOS
gyengites, lasd ADR 0444 D2 es a Kontextus 2. pontja).

Az `import yaml` KEMENY fuggoseg: hianyzo PyYAML eseten a script hangosan
elszall (ModuleNotFoundError), nem esik vissza csendben egy gyengebb
ellenorzesre.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent

ISSUE_TEMPLATE_DIR = REPO_ROOT / ".github" / "ISSUE_TEMPLATE"
ISSUE_TEMPLATE_FILES = (
    "feature.yml",
    "bug.yml",
    "security.yml",
    "migration.yml",
    "release.yml",
)
ISSUE_TEMPLATE_CONFIG = ISSUE_TEMPLATE_DIR / "config.yml"
CODEOWNERS_PATH = REPO_ROOT / ".github" / "CODEOWNERS"
PR_TEMPLATE_PATH = REPO_ROOT / ".github" / "pull_request_template.md"
BRANCH_PROTECTION_DOC = REPO_ROOT / "docs" / "process" / "branch-protection.md"

# A hat kozos kotelezo mezo minden issue-sablonon (docs/process/backlog-policy.md §3).
REQUIRED_ISSUE_FIELDS = ("chapter", "round", "acceptance", "test_plan", "rollback", "privacy")

# D1-sertes: emberi jovahagyast a merge FELTETELEVE tevo minta a
# branch-protection.md-ben. A pontos szam (>=1) a tiltott allitas, mert az
# fagyasztana be az autonom kor-pipeline squash-merge-et.
#
# A minta SZOVEGES elofordulast mer, nem szandekot: egy olyan mondat is
# pirosra valt, amely ezt a tilalmat sajat szavaival mondja ki (nem csak
# egy olyan, ami megserti). Ez szandekos fail-closed viselkedes, nem hiba
# - a szerkesztett dokumentumok ezert a szabalyt korulirassal fogalmazzak,
# a lenti mintak szo szerinti fordulatai nelkul, es a minta GYENGITESE
# (pl. negacio-erzekennye tetel) NEM megoldas, mert az pont ezt az ort
# olne meg.
FORBIDDEN_HUMAN_APPROVAL_PATTERNS = (
    re.compile(r"required_approving_review_count\s*[:=]?\s*[1-9]"),
    re.compile(r"legal[aá]bb\s+1\s+(?:approving\s+)?review", re.IGNORECASE),
    re.compile(r"k[oö]telez[oő]\s+(?:emberi\s+)?j[oó]v[aá]hagy[aá]s", re.IGNORECASE),
)

REQUIRED_PR_TEMPLATE_HEADERS = (
    "## SDD requirement / kör",
    "## Cél és nem-cél",
    "## Fő változások",
    "## Migration / API hatás",
    "## Tesztek",
    "## Evidence",
    "## Release evidence",
    "## Privacy / security hatás",
    "## Rollback",
    "## Follow-up",
)


class PolicyViolation:
    def __init__(self, check: str, message: str) -> None:
        self.check = check
        self.message = message

    def __str__(self) -> str:  # pragma: no cover - trivial
        return f"[{self.check}] {self.message}"


def load_yaml(path: Path) -> object:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def check_issue_templates() -> list[PolicyViolation]:
    violations: list[PolicyViolation] = []
    for filename in ISSUE_TEMPLATE_FILES:
        path = ISSUE_TEMPLATE_DIR / filename
        if not path.exists():
            violations.append(PolicyViolation("issue-template", f"hianyzik: {path}"))
            continue
        document = load_yaml(path)
        if not isinstance(document, dict):
            violations.append(
                PolicyViolation(
                    "issue-template", f"{filename}: a gyoker nem mapping (invalid issue form)"
                )
            )
            continue
        body = document.get("body")
        if not isinstance(body, list):
            violations.append(
                PolicyViolation("issue-template", f"{filename}: hianyzik a 'body' lista")
            )
            continue
        required_ids_present: set[str] = set()
        for element in body:
            if not isinstance(element, dict):
                continue
            field_id = element.get("id")
            validations = element.get("validations")
            required = isinstance(validations, dict) and validations.get("required") is True
            if field_id in REQUIRED_ISSUE_FIELDS and required:
                required_ids_present.add(field_id)
        missing = [field for field in REQUIRED_ISSUE_FIELDS if field not in required_ids_present]
        if missing:
            violations.append(
                PolicyViolation(
                    "issue-template",
                    f"{filename}: hianyzo kotelezo mezo(k): {', '.join(missing)}",
                )
            )
    return violations


def check_blank_issues_disabled() -> list[PolicyViolation]:
    if not ISSUE_TEMPLATE_CONFIG.exists():
        return [PolicyViolation("blank-issues", f"hianyzik: {ISSUE_TEMPLATE_CONFIG}")]
    document = load_yaml(ISSUE_TEMPLATE_CONFIG)
    if not isinstance(document, dict) or document.get("blank_issues_enabled") is not False:
        return [
            PolicyViolation(
                "blank-issues",
                "config.yml: 'blank_issues_enabled: false' kotelezo es hianyzik vagy true",
            )
        ]
    return []


def check_codeowners_paths() -> list[PolicyViolation]:
    violations: list[PolicyViolation] = []
    if not CODEOWNERS_PATH.exists():
        return [PolicyViolation("codeowners", f"hianyzik: {CODEOWNERS_PATH}")]
    for line_number, raw_line in enumerate(
        CODEOWNERS_PATH.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        pattern = line.split()[0]
        relative = pattern.strip("/")
        if not relative:
            continue
        if not (REPO_ROOT / relative).exists():
            violations.append(
                PolicyViolation(
                    "codeowners",
                    f"CODEOWNERS:{line_number}: fantom-utvonal '{pattern}' "
                    "nem letezik a repoban (ADR 0444 D4)",
                )
            )
    return violations


def check_branch_protection_no_required_human_review() -> list[PolicyViolation]:
    violations: list[PolicyViolation] = []
    for path, label in (
        (CODEOWNERS_PATH, "codeowners"),
        (BRANCH_PROTECTION_DOC, "branch-protection"),
    ):
        if not path.exists():
            violations.append(PolicyViolation(label, f"hianyzik: {path}"))
            continue
        contents = path.read_text(encoding="utf-8")
        for pattern in FORBIDDEN_HUMAN_APPROVAL_PATTERNS:
            if pattern.search(contents):
                violations.append(
                    PolicyViolation(
                        label,
                        f"{path.name}: emberi jovahagyast a merge feltetelekent iro minta "
                        f"talalhato ('{pattern.pattern}') - ADR 0444 D1 sertes",
                    )
                )
    return violations


def check_pr_template_sections() -> list[PolicyViolation]:
    if not PR_TEMPLATE_PATH.exists():
        return [PolicyViolation("pr-template", f"hianyzik: {PR_TEMPLATE_PATH}")]
    contents = PR_TEMPLATE_PATH.read_text(encoding="utf-8")
    violations: list[PolicyViolation] = []
    for header in REQUIRED_PR_TEMPLATE_HEADERS:
        if header not in contents:
            violations.append(
                PolicyViolation("pr-template", f"hianyzo szakasz-fejlec: '{header}'")
            )
    if "release asset" not in contents.lower():
        violations.append(
            PolicyViolation(
                "pr-template", "hianyzik a kotelezoen kitoltendo release-asset sor"
            )
        )
    return violations


def run_all_checks() -> list[PolicyViolation]:
    violations: list[PolicyViolation] = []
    violations += check_issue_templates()
    violations += check_blank_issues_disabled()
    violations += check_codeowners_paths()
    violations += check_branch_protection_no_required_human_review()
    violations += check_pr_template_sections()
    return violations


def print_live_verification_commands() -> None:
    """Kiirja - de nem futtatja - az Administration-jogu live ellenorzest.

    A `gh api` hivas Administration jogot igenyel, amivel az implementer
    tokenje nem rendelkezik (ADR 0050 "Szolo-fejleszto adaptaciok" 2. pont).
    Ez a script sosem hivja meg - az operator kezi lepese.
    """
    print()
    print("Live branch-protection ellenorzeshez (operatori lepes, NEM ez a script futtatja):")
    print("  gh api repos/wolfcasaba/strumsight/branches/main/protection")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        default=True,
        help="Az egyetlen tamogatott mod - a script sosem ir a repoba, irasi ag nincs.",
    )
    parser.parse_args(argv)

    violations = run_all_checks()

    if violations:
        print(f"Repository-policy audit: {len(violations)} sertes talalva.")
        for violation in violations:
            print(f"  - {violation}")
        print_live_verification_commands()
        return 1

    print("Repository-policy audit: minden ellenorzes zold.")
    print_live_verification_commands()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
