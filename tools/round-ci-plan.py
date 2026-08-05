#!/usr/bin/env python3
"""Kör-CI terv: MELYIK workflow futása a kör zöld kapuja (ADR 0171 §3).

    tools/round-ci-plan.py --brief <brief> [--base <sha>] [--head <sha>]
    tools/round-ci-plan.py --brief <brief> --changed-file lib/a.dart ...

MIÉRT: a `build-apk.yml` futása MÉRVE ~11 perc, és körönként legalább kétszer
fut (első dispatch + javító kör utáni újra-dispatch), miközben a kör diffje a
körök többségében egyetlen natív bájtot sem érint. A drága rész a Java/Gradle
lánc, NEM a mérce: a `flutter-gates` composite (format, analyze, architecture,
secret, l10n, asset, teljes teszt, randomizált property) és a coverage job
ugyanaz a két artefaktum a `full-gate.yml`-ben, APK-építés nélkül.

Ez a CLI tehát NEM gyengíti a mércét — a mérce-lánc mindkét ágon TELJES —,
hanem eldönti, kell-e MELLÉ Android-build. A döntés fail-closed: ha a briefet
nem lehet elemezni, vagy a változott fájlok listája ismeretlen, a terv az
APK-s ág (exit 0, `build-apk.yml`), mert a bizonyítatlan eset nem lehet
olcsóbb, mint a bizonyított.

A `router-ci.yml` push-trigger, nem dispatch: a terv csak JELZI, hogy a diff
érinti-e a trigger-útvonalait, mert a merge-kapunak azt is a merge SHA-ján
zöldnek kell látnia (docs/LESSONS.md L113 — nyolc körön át piros Router CI,
mert a kapu csak a build-apk-t nézte).

Kilépési kódok:
    0 = van terv (a `dispatch` lista a stdouton)
    2 = használati hiba (a hívó ilyenkor a `build-apk.yml`-t dispatch-elje)
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.ai_router.brief import BriefMetadataError, load_brief  # noqa: E402

APK_WORKFLOW = "build-apk.yml"
FULL_GATE_WORKFLOW = "full-gate.yml"
ROUTER_CI_WORKFLOW = "router-ci.yml"

# Az APK-t KÖTELEZŐVÉ tevő útvonalak. Ami a release-fordítást, a natív
# projektet, a függőségeket, az assetet vagy magát a build-workflow-t érinti,
# azt csak egy valódi `flutter build apk --release` méri — a `flutter test`
# nem fordít release-módban (tree-shaking, R8, hiányzó asset a release
# manifestben).
NATIVE_PATH_PATTERNS = (
    "android/**",
    "ios/**",
    "macos/**",
    "linux/**",
    "windows/**",
    "web/**",
    "assets/**",
    "pubspec.yaml",
    "pubspec.lock",
    ".github/actions/**",
    ".github/workflows/build-apk.yml",
    ".github/workflows/full-gate.yml",
    ".github/workflows/release-apk.yml",
)


def _glob_to_regex(pattern: str) -> re.Pattern[str]:
    """A workflow `paths:` glob-jainak fordítása (csak `**` és `*` szerepel)."""
    out: list[str] = []
    index = 0
    while index < len(pattern):
        if pattern.startswith("**/", index):
            out.append("(?:.*/)?")
            index += 3
        elif pattern.startswith("**", index):
            out.append(".*")
            index += 2
        elif pattern[index] == "*":
            out.append("[^/]*")
            index += 1
        else:
            out.append(re.escape(pattern[index]))
            index += 1
    return re.compile("^" + "".join(out) + "$")


def matches_any(path: str, patterns: tuple[str, ...]) -> str | None:
    """Az ELSŐ illeszkedő minta, vagy None. A találat a döntés indoklása."""
    for pattern in patterns:
        if _glob_to_regex(pattern).match(path):
            return pattern
    return None


def router_ci_trigger_paths(workflow_text: str) -> tuple[str, ...]:
    """A `router-ci.yml` `on.push.paths` listája a workflow-fájlból olvasva.

    Szándékosan a VALÓDI fájlból, nem másolt konstansból: ha a workflow
    trigger-listája bővül, a merge-kapu elvárása vele mozog. A parser
    soralapú, mert a repó stdlib-only (nincs PyYAML).
    """
    lines = workflow_text.splitlines()
    paths: list[str] = []
    inside = False
    indent = 0
    for line in lines:
        stripped = line.strip()
        if not inside:
            if stripped == "paths:":
                inside = True
                indent = len(line) - len(line.lstrip())
            continue
        if not stripped or stripped.startswith("#"):
            continue
        current_indent = len(line) - len(line.lstrip())
        if not stripped.startswith("- ") or current_indent <= indent:
            break
        value = stripped[2:].strip()
        if value[:1] in ('"', "'") and value[-1:] == value[:1]:
            value = value[1:-1]
        paths.append(value)
    return tuple(paths)


def changed_files_from_git(repo: Path, base: str, head: str) -> tuple[str, ...]:
    """A kör diffje: a `base` és a `head` KÖZÖS ŐSÉHEZ képest (merge-base).

    Kétpontos diff a main előrehaladásakor idegen fájlokat is a körnek
    tulajdonítana, ezért itt is a scope-audit szemantikája érvényes.
    """
    merge_base = subprocess.run(
        ["git", "-C", str(repo), "merge-base", base, head],
        text=True,
        capture_output=True,
        check=False,
    )
    if merge_base.returncode != 0:
        raise RuntimeError(f"merge-base sikertelen: {merge_base.stderr.strip()}")
    diff = subprocess.run(
        ["git", "-C", str(repo), "diff", "--name-only", merge_base.stdout.strip(), head],
        text=True,
        capture_output=True,
        check=False,
    )
    if diff.returncode != 0:
        raise RuntimeError(f"git diff sikertelen: {diff.stderr.strip()}")
    return tuple(line for line in diff.stdout.splitlines() if line)


def plan(
    *,
    native_gate: bool,
    changed_files: tuple[str, ...],
    router_ci_paths: tuple[str, ...],
    force_apk: bool = False,
    round_id: str = "",
) -> dict:
    """A terv kiszámítása. Tiszta függvény — a tesztek ezt mérik."""
    reasons: list[str] = []
    apk_required = False

    if force_apk:
        apk_required = True
        reasons.append("force-apk: a hívó kikényszerítette az APK-ágat")
    if native_gate:
        apk_required = True
        reasons.append("native_gate = true a brief ai-router blokkjában")

    native_hits: list[str] = []
    for path in changed_files:
        pattern = matches_any(path, NATIVE_PATH_PATTERNS)
        if pattern:
            native_hits.append(f"{path} ({pattern})")
    if native_hits:
        apk_required = True
        reasons.append("natív/release-érintő diff: " + ", ".join(sorted(native_hits)[:5]))

    if not changed_files:
        apk_required = True
        reasons.append("üres vagy ismeretlen diff — fail-closed APK-ág")

    router_hits = sorted(
        {path for path in changed_files if matches_any(path, router_ci_paths)}
    )

    if apk_required:
        dispatch = [APK_WORKFLOW]
        skipped = [FULL_GATE_WORKFLOW]
    else:
        dispatch = [FULL_GATE_WORKFLOW]
        skipped = [APK_WORKFLOW]
        reasons.append(
            "a diff nem érint natív/release-útvonalat — a teljes mérce-lánc "
            "(format+analyze+architecture+secret+l10n+asset+teszt+property+coverage) "
            "APK-építés nélkül fut"
        )

    return {
        "schema_version": 1,
        "round": round_id,
        "dispatch": dispatch,
        "skipped": skipped,
        "apk_required": apk_required,
        "router_ci_expected": bool(router_hits),
        "router_ci_paths_hit": router_hits[:10],
        "changed_file_count": len(changed_files),
        "reasons": reasons,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Kör-CI terv (ADR 0171)")
    parser.add_argument("--brief", type=Path, help="a kör briefje (ai-router blokk)")
    parser.add_argument("--repo", type=Path, default=REPO_ROOT, help="munkapéldány (alap: a repó gyökere)")
    parser.add_argument("--base", default="origin/main", help="összehasonlítási alap (alap: origin/main)")
    parser.add_argument("--head", default="HEAD", help="a kör feje (alap: HEAD)")
    parser.add_argument(
        "--changed-file",
        action="append",
        default=[],
        help="diff-fájl kézzel (teszthorog; megadva a git-hívás kimarad)",
    )
    parser.add_argument("--force-apk", action="store_true", help="APK-ág kikényszerítése")
    parser.add_argument("--format", choices=("lines", "json"), default="lines")
    arguments = parser.parse_args(argv)

    repo = arguments.repo.resolve()

    native_gate = False
    round_id = ""
    if arguments.brief is not None:
        brief_path = arguments.brief
        if not brief_path.is_absolute():
            brief_path = (repo / brief_path).resolve()
        try:
            brief = load_brief(brief_path)
        except BriefMetadataError as error:
            print(f"round-ci-plan: a brief nem elemezhető: {error}", file=sys.stderr)
            return 2
        native_gate = brief.metadata.native_gate
        round_id = brief.task_id

    if arguments.changed_file:
        changed_files = tuple(arguments.changed_file)
    else:
        try:
            changed_files = changed_files_from_git(repo, arguments.base, arguments.head)
        except RuntimeError as error:
            print(f"round-ci-plan: {error}", file=sys.stderr)
            return 2

    workflow = repo / ".github" / "workflows" / ROUTER_CI_WORKFLOW
    try:
        router_paths = router_ci_trigger_paths(workflow.read_text(encoding="utf-8"))
    except OSError as error:
        print(f"round-ci-plan: a router-ci.yml nem olvasható: {error}", file=sys.stderr)
        return 2

    result = plan(
        native_gate=native_gate,
        changed_files=changed_files,
        router_ci_paths=router_paths,
        force_apk=arguments.force_apk,
        round_id=round_id,
    )

    if arguments.format == "json":
        print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        for name in result["dispatch"]:
            print(name)
        for reason in result["reasons"]:
            print(f"# {reason}", file=sys.stderr)
        if result["router_ci_expected"]:
            print(
                "# a Router CI is a merge-kapu része (push-trigger illeszkedik)",
                file=sys.stderr,
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
