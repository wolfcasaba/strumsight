#!/usr/bin/env python3
"""Kör-brief × MÉRCE-őr ütközés-vizsgálat (ADR 0321).

    tools/gateguard-scan.py --brief docs/rounds/e99-r17-....md
    tools/gateguard-scan.py --all [--format json]

MIÉRT: a `H-GATEGUARD` halt MÉRT gyökéroka háromszor egymás után (E99-R17,
2026-08-19, docs/LESSONS.md L322–L323) NEM az implementer hibája volt, hanem
TERVEZÉSI hiba: a brief `allowed_paths` listájára olyan fájl került, amit a
`.claude/hooks/protect_factory_files.py` `PROTECTED_GLOBS` listája véd. Egy
autonóm session ezt a fájlt STRUKTURÁLISAN nem tudja megírni — sem a
`.claude/gate-edit-authorized` markerrel (az implementer-session a
`tools/hooks/implementer_guard.py` alatt fut, ami a markert nem ismeri), sem
Claude-oldalról (a harness saját auto-mode osztályozója is blokkolja). A kör
tehát a session ELINDÍTÁSA ELŐTT eldőlt — csak órákkal és három halttal
később derült ki.

Ez a szkript ezt az ütközést a dispatch ELŐTT méri: a mércét NEM módosítja,
csak OLVASSA, és a védett listát magából az őrből importálja, hogy a két
lista ne tudjon szétcsúszni.

Kilépési kódok:
    0 = nincs ütközés (a kör indítható)
    1 = ütközés (a kör emberi gate-engedély nélkül nem futtatható)
    3 = használati/olvasási hiba
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from fnmatch import fnmatch
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.ai_router.brief import BriefMetadataError, load_brief  # noqa: E402

HOOK_RELATIVE = Path(".claude") / "hooks" / "protect_factory_files.py"
QUEUE_RELATIVE = Path("docs") / "execution" / "pipeline-queue.tsv"


def protected_globs(repo: Path = REPO_ROOT) -> tuple[str, ...]:
    """Az őr SAJÁT listája — importálva, nem másolva (nincs két igazság)."""
    hook = repo / HOOK_RELATIVE
    spec = importlib.util.spec_from_file_location("protect_factory_files_readonly", hook)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"az őr nem olvasható: {hook}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return tuple(module.PROTECTED_GLOBS)


def _normalize(path: str) -> str:
    return path.strip().rstrip("/")


def conflicts(allowed_paths, globs: tuple[str, ...]) -> list[tuple[str, str]]:
    """(allowed_path, védett minta) párok — üres lista = a kör indítható.

    Három illeszkedési irány, mert az `allowed_paths` fájlt ÉS könyvtárat is
    tartalmazhat:

    1. maga az útvonal illeszkedik egy védett mintára (`tool/ci/x.dart`);
    2. az útvonal egy védett minta SZÜLŐ könyvtára (`tool/` ⊃ `tool/ci/*`) —
       ilyenkor a kör a védett fájlt is írhatná;
    3. az útvonal egy védett, glob nélküli minta ALÁ esik (`tools/ai_router/x`).
    """
    hits: list[tuple[str, str]] = []
    for raw in allowed_paths:
        path = _normalize(raw)
        if not path:
            continue
        for pattern in globs:
            literal = _normalize(pattern)
            matched = (
                fnmatch(path, pattern)
                or literal == path
                or literal.startswith(path + "/")
                or ("*" not in literal and path.startswith(literal + "/"))
            )
            if matched:
                hits.append((path, pattern))
                break
    return hits


def scan_brief(brief: Path, globs: tuple[str, ...]) -> dict:
    metadata = load_brief(brief).metadata
    hits = conflicts(metadata.allowed_paths, globs)
    return {
        "brief": str(brief.relative_to(REPO_ROOT)) if brief.is_absolute() else str(brief),
        "conflicts": [{"path": path, "protected_by": pattern} for path, pattern in hits],
    }


def open_queue_briefs(repo: Path) -> list[tuple[str, str, str]]:
    """(kör, brief, státusz) a NEM `done` sorokra."""
    rows: list[tuple[str, str, str]] = []
    try:
        text = (repo / QUEUE_RELATIVE).read_text(encoding="utf-8")
    except OSError:
        return rows
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 5 and parts[4] != "done":
            rows.append((parts[0], parts[1], parts[4]))
    return rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--brief", type=Path, help="egyetlen kör-brief útvonala")
    group.add_argument("--all", action="store_true", help="a sor minden NEM done köre")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--repo", type=Path, default=REPO_ROOT)
    args = parser.parse_args(argv)

    try:
        globs = protected_globs(args.repo)
    except (OSError, RuntimeError) as error:
        print(f"HIBA: {error}", file=sys.stderr)
        return 3

    reports: list[dict] = []
    if args.brief is not None:
        brief = args.brief if args.brief.is_absolute() else args.repo / args.brief
        try:
            reports.append(scan_brief(brief, globs))
        except (BriefMetadataError, OSError) as error:
            print(f"HIBA: a brief nem olvasható ({args.brief}): {error}", file=sys.stderr)
            return 3
    else:
        for round_id, brief_path, status in open_queue_briefs(args.repo):
            try:
                report = scan_brief(args.repo / brief_path, globs)
            except (BriefMetadataError, OSError):
                continue
            report["round"] = round_id
            report["status"] = status
            reports.append(report)

    flagged = [report for report in reports if report["conflicts"]]
    if args.format == "json":
        print(json.dumps({"protected_globs": list(globs), "reports": reports}, ensure_ascii=False, indent=2))
    else:
        for report in flagged:
            head = report.get("round", report["brief"])
            for conflict in report["conflicts"]:
                print(f"{head}\t{conflict['path']}\tvédett minta: {conflict['protected_by']}")
        if not flagged:
            print("nincs ütközés a MÉRCE-őr védett listájával")
    return 1 if flagged else 0


if __name__ == "__main__":
    raise SystemExit(main())
