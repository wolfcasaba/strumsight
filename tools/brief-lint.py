#!/usr/bin/env python3
"""Kör-brief lint: a javító körök MÉRT okait a briefben fogja meg (ADR 0171 §4).

    tools/brief-lint.py --brief docs/rounds/e04-r15-....md [--level strict]
    tools/brief-lint.py --all [--level base] [--format json]

MIÉRT: egy javító kör ára a kör legdrágább ismételhető eleme (implementer-futás
+ teljes gate + review + CI-újradispatch). A mért javító körök nagy része nem
kódhiba, hanem BRIEF-hiba: hiányzó falszifikációs cella (docs/LESSONS.md
„a mércét is ellenőrizd"), küszöb fölötti cella nélküli mátrix, olyan
gate_test, ami nem is létezik, vagy parancslánc a gate helyett.

Két szint, MÉRT okból:

* `base`  — ezt MINDEN meglévő brief teljesíti (mérve a bevezetéskor), ezért
  CI-kapunak alkalmas: a drift pirosra vált. Csak olyat tilt, ami bizonyítottan
  hibás.
* `strict` — a falszifikációs elvárások. Az előre megírt briefek egy része ezt
  még nem teljesíti, ezért NEM CI-kapu: a pipeline a kör pre-flightjában adja
  át az orchestrátornak teendőlistaként (a brief-revízió a §2 szerint az
  orchestrátor saját hatásköre), így a hiány a kör ELEJÉN javul, nem a
  review-ban.

Kilépési kódok:
    0 = nincs lelet a kért szinten
    1 = csak strict-lelet (figyelmeztetés)
    2 = base-lelet (hiba — CI-kapu piros)
    3 = használati hiba
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.ai_router.brief import BriefMetadataError, load_brief  # noqa: E402

GATE_ARTIFACT = "tools/round-gate.sh"
FENCE = re.compile(r"^```(?:bash|sh)?[ \t]*\n(.*?)^```[ \t]*$", re.MULTILINE | re.DOTALL)
HEADING_TASK_ID = re.compile(r"(?im)^#\s*(E\d{2}-R\d{2})\b")
# A gate futtatását elrejtő parancsalakok. MÉRVE: a MiniMax M3 háromszor tette
# `| tail`-be a gate-et (docs/LESSONS.md), az `analyze && test` lánc pedig ezen
# a boxon OOM-ot okoz (L05) — ezért a briefben SEM szerepelhet mintaként.
FORBIDDEN_GATE_SHAPES = (
    (re.compile(r"round-gate\.sh[^\n]*\|\s*(tail|head)\b"), "a gate kimenetét csonkító pipe (`| tail`/`| head`)"),
    (re.compile(r"flutter\s+analyze[^\n]*&&[^\n]*flutter\s+test"), "`analyze && test` lánc (OOM ezen a boxon, L05)"),
)
FALSIFICATION_MARKERS = ("pirosra", "falszifik", "mérce-mátrix", "melyik hibás implementáció")
STOP_MARKERS = ("**STOP", "STOP:", "STOP-protokoll", "STOP on scope conflict")
SIGNAL_MARKERS = ("kör-jelzés", "codex-round-status", "round-status", "Kör-jelzés")


QUEUE_RELATIVE = Path("docs") / "execution" / "pipeline-queue.tsv"


def queue_rows(repo: Path) -> list[tuple[str, str, str]]:
    """(kör, brief, státusz) hármasok a sor-fájlból, sorrendben."""
    path = repo / QUEUE_RELATIVE
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return []
    rows: list[tuple[str, str, str]] = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 5:
            rows.append((parts[0], parts[1], parts[4]))
    return rows


def predecessor_paths(repo: Path, task_id: str) -> frozenset[str]:
    """A sorban KORÁBBI körök allowed_paths uniója.

    MIÉRT KELL: egy előre megírt brief `gate_tests` értéke jogosan hivatkozhat
    olyan könyvtárra, amit egy korábbi kör hoz létre (mérve: az Epic 5 kamerás
    köreinél a `test/core/camera` az E05-R03-ban születik, de az E05-R06 is
    gate-eli). A puszta lemez-állapot ezt hamis pozitívnak látná, és a lint
    használhatatlanná válna minden előre megírt epicre.
    """
    collected: set[str] = set()
    for round_id, brief, _status in queue_rows(repo):
        if round_id.upper() == task_id.upper():
            break
        try:
            metadata = load_brief(repo / brief).metadata
        except (BriefMetadataError, OSError):
            continue
        collected.update(metadata.allowed_paths)
    return frozenset(collected)


def _gate_test_is_covered(gate_test: str, paths: frozenset[str] | tuple[str, ...]) -> bool:
    prefix = gate_test.rstrip("/") + "/"
    for candidate in paths:
        if gate_test == candidate or candidate.startswith(prefix) or gate_test.startswith(candidate.rstrip("/") + "/"):
            return True
    return False


class Finding(dict):
    """Egy lelet: szint + kód + üzenet. dict, hogy a JSON-kimenet triviális legyen."""

    def __init__(self, level: str, code: str, message: str) -> None:
        super().__init__(level=level, code=code, message=message)


def _fenced_blocks(text: str) -> str:
    return "\n".join(FENCE.findall(text))


def lint_text(text: str, *, path: Path, repo: Path) -> list[Finding]:
    """A brief teljes leletlistája (base + strict), sorrendben."""
    findings: list[Finding] = []

    try:
        brief = load_brief(path)
    except BriefMetadataError as error:
        return [Finding("base", "B1", f"az ai-router blokk nem elemezhető: {error}")]

    metadata = brief.metadata
    relative = path.resolve().relative_to(repo.resolve()).as_posix()

    # B2 — a brief SAJÁT magát is engedélyezze: a pre-flight brief-revíziója
    # (§0.0) és a státuszfrissítés különben scope-sértés lenne.
    if relative not in metadata.allowed_paths:
        findings.append(
            Finding("base", "B2", f"a brief nem szerepel a saját allowed_paths listáján ({relative})")
        )

    # B3 — minden gate_test vagy LÉTEZIK, vagy a kör hozza létre (allowed_paths).
    # Mért hibaosztály: nem létező gate-útvonalra írt acceptance = mérhetetlen kör.
    earlier = predecessor_paths(repo, brief.task_id)
    for gate_test in metadata.gate_tests:
        if (repo / gate_test).exists():
            continue
        if _gate_test_is_covered(gate_test, metadata.allowed_paths) or _gate_test_is_covered(gate_test, earlier):
            continue
        findings.append(
            Finding(
                "base",
                "B3",
                f"a gate_tests eleme nem létezik, és sem ez a kör, sem korábbi sorbeli kör nem hozza létre: {gate_test}",
            )
        )

    # B4 — a gate artefaktum SZÓ SZERINT szerepeljen: a parancssorban
    # reprodukált lista nem bizonyíték (AGENTS.md §12).
    if GATE_ARTIFACT not in text:
        findings.append(Finding("base", "B4", f"a brief nem hivatkozza a gate artefaktumot ({GATE_ARTIFACT})"))

    # B5 — tiltott parancsalakok a brief kód-blokkjaiban.
    blocks = _fenced_blocks(text)
    for pattern, label in FORBIDDEN_GATE_SHAPES:
        if pattern.search(blocks):
            findings.append(Finding("base", "B5", f"tiltott parancsalak a brief kód-blokkjában: {label}"))

    # B6 — a fájlnév és a címsor kör-azonosítója egyezzen.
    heading = HEADING_TASK_ID.search(text)
    if heading and heading.group(1).upper() != brief.task_id:
        findings.append(
            Finding("base", "B6", f"a címsor kör-azonosítója ({heading.group(1)}) ≠ fájlnév ({brief.task_id})")
        )

    # S1 — STOP-protokoll: scope-ütközéskor a brief-revízió a kimenet, nem a
    # lista-tágítás. Enélkül az implementer csendben tágít.
    if not any(marker in text for marker in STOP_MARKERS):
        findings.append(Finding("strict", "S1", "nincs STOP-protokoll szakasz (scope-ütközés esetére)"))

    # S2 — falszifikáció: minden acceptance-ponthoz tartozzon mért állítás
    # arról, MELYIK hibás implementációt fogja pirosra.
    if not any(marker in text.lower() for marker in FALSIFICATION_MARKERS):
        findings.append(
            Finding(
                "strict",
                "S2",
                "nincs falszifikációs cella: egyetlen acceptance-pont sem mondja meg, "
                "melyik hibás implementációt fogja pirosra (docs/LESSONS.md: a mércét is ellenőrizd)",
            )
        )

    # S3 — küszöb-mátrix: ahol numerikus küszöb van, ott alatta/rajta/fölötte
    # hármas kell (mérve: E02-R08 lag-mátrixából hiányzott a FÖLÖTTE cella).
    has_threshold = re.search(r"(?i)\b(küszöb|threshold|timeout|tolerancia|max(imum)?\s*=)\b", text) is not None
    has_matrix = re.search(r"(?i)(alatta|below).{0,80}(rajta|at\b).{0,80}(fölötte|felette|above)", text, re.S) is not None
    if has_threshold and not has_matrix:
        findings.append(
            Finding("strict", "S3", "numerikus küszöb szerepel, de nincs alatta/rajta/fölötte cellahármas")
        )

    # S4 — kör-jelzés: jelzés nélküli futás = bukott futás (AGENTS.md §15.2).
    if not any(marker.lower() in text.lower() for marker in SIGNAL_MARKERS):
        findings.append(Finding("strict", "S4", "nincs kör-jelzés (STOP/`done`) szakasz"))

    return findings


def lint_paths(paths: list[Path], *, repo: Path, level: str) -> tuple[list[dict], int]:
    """Leletek + a legmagasabb súlyosság kilépési kódja."""
    wanted = {"base"} if level == "base" else {"base", "strict"}
    report: list[dict] = []
    worst = 0
    for path in sorted(paths):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as error:
            report.append({"brief": str(path), "findings": [Finding("base", "B0", f"olvashatatlan: {error}")]})
            worst = 2
            continue
        findings = [item for item in lint_text(text, path=path, repo=repo) if item["level"] in wanted]
        if findings:
            report.append({"brief": path.resolve().relative_to(repo.resolve()).as_posix(), "findings": findings})
            if any(item["level"] == "base" for item in findings):
                worst = 2
            elif worst == 0:
                worst = 1
    return report, worst


def render_markdown(report: list[dict], *, level: str) -> str:
    if not report:
        return f"# Brief-lint ({level}) — nincs lelet\n"
    lines = [f"# Brief-lint ({level}) — {len(report)} briefen van lelet", ""]
    for entry in report:
        lines.append(f"## {entry['brief']}")
        for finding in entry["findings"]:
            lines.append(f"- **{finding['code']}** ({finding['level']}): {finding['message']}")
        lines.append("")
    lines.append(
        "> A `strict` leletek a kör pre-flightjának teendői: a brief-revízió "
        "(§0.0) az orchestrátor saját hatásköre, a lista-tágítás NEM."
    )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Kör-brief lint (ADR 0171)")
    parser.add_argument("--brief", type=Path, action="append", default=[], help="egy brief útvonala")
    parser.add_argument("--all", action="store_true", help="minden docs/rounds/*.md brief")
    parser.add_argument(
        "--open",
        action="store_true",
        help="a sor MÉG NYITOTT (státusz != done) köreinek briefjei — ez a CI-kapu hatóköre",
    )
    parser.add_argument("--repo", type=Path, default=REPO_ROOT)
    parser.add_argument("--level", choices=("base", "strict"), default="base")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--out", type=Path, default=None, help="a jelentés fájlba is")
    arguments = parser.parse_args(argv)

    repo = arguments.repo.resolve()
    paths = [path if path.is_absolute() else repo / path for path in arguments.brief]
    if arguments.all:
        rounds = repo / "docs" / "rounds"
        paths.extend(sorted(path for path in rounds.glob("*.md") if re.search(r"(?i)e\d{2}-r\d{2}", path.name)))
    if arguments.open:
        # A MERGE-ELT körök briefje történeti rekord: visszamenőleg nem
        # linteljük (a régi, ai-router blokk nélküli E01/E02-es briefek
        # különben örökre pirosra állítanák a kaput). A kapu a JÖVŐ köreit
        # méri — ott van értelme, mert ott még olcsó javítani.
        paths.extend(repo / brief for _round, brief, status in queue_rows(repo) if status != "done")
    if not paths:
        print("brief-lint: adj meg --brief-et, --open-t vagy --all-t", file=sys.stderr)
        return 3

    report, worst = lint_paths(paths, repo=repo, level=arguments.level)

    if arguments.format == "json":
        rendered = json.dumps(
            {"schema_version": 1, "level": arguments.level, "briefs": report},
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
        )
    else:
        rendered = render_markdown(report, level=arguments.level)
    print(rendered)
    if arguments.out is not None:
        arguments.out.parent.mkdir(parents=True, exist_ok=True)
        arguments.out.write_text(rendered, encoding="utf-8")
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
