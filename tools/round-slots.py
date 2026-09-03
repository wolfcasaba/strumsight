#!/usr/bin/env python3
"""Párhuzamos kör-slotok: diszjunkt-vizsgálat és ADR-foglalás (ADR 0171 §1).

    tools/round-slots.py check --brief A.md --brief B.md
    tools/round-slots.py plan --slots 2 [--inflight .pipeline/inflight]
    tools/round-slots.py reserve-adr --round E04-R15 [--inflight .pipeline/inflight]
    tools/round-slots.py inflight-add|inflight-remove|inflight-list ...

MIÉRT: a lánc ma szigorúan EGY kört enged egyszerre, pedig minden brief
`ai-router` blokkja DEKLARÁLJA a maga `allowed_paths` halmazát — vagyis gépileg
eldönthető, hogy két várakozó kör egyáltalán hozzáérhet-e ugyanahhoz a fájlhoz.
Két diszjunkt kör párhuzamos futása nem lazítja a mércét: mindkettő ugyanazt a
gate-et, review-t és CI-t kapja, csak nem egymásra várnak.

Amit ez a modul NEM enged meg:

* átfedő fájlhalmazú körök párhuzamát (a rebase-konfliktus a legdrágább
  hibaosztály, mert a kör VÉGÉN derül ki);
* néma ADR-ütközést: a sorszámot innen kell kérni, nem `ls docs/adr | tail`-ből
  — pontosan ez a MÉRT ütközés vezetett a 0139 duplikátumhoz (két párhuzamos
  munka, egyenként helyes diff, hibás összeg — tools/tests/test_adr_numbering.py).

A záró rituálék közös fájljai (HANDOFF, RTM, LESSONS, sor-fájl) NEM számítanak
ütközésnek: azokat a merge-zár sorosítja (`tools/round-merge-lock.sh`), mert
minden kör hozzájuk ér, különben soha semmi nem lehetne párhuzamos.

Kilépési kódok:
    0 = rendben (check: diszjunkt)
    1 = ütközés (check: átfedés)
    2 = használati/elemzési hiba
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.ai_router.brief import BriefMetadataError, load_brief  # noqa: E402

# Minden kör záró rituáléja hozzájuk ér; a merge-zár sorosítja őket.
SERIALIZED_PATHS = frozenset(
    {
        "HANDOFF.md",
        "docs/handoff-archive.md",
        "docs/LESSONS.md",
        "docs/execution/pipeline-queue.tsv",
        "docs/execution/06-requirements-traceability-matrix.md",
        # A képernyő-migrációs napló (ADR 0495 D2). MÉRVE 2026-09-03: ez volt az
        # EGYETLEN ütközési felület az E15 migrációs körei között (E15-R09 ↔
        # E15-R10), és nincs olyan gépi mérce, amely a TARTALMÁT a fa ellen
        # olvasná — a `test/tooling/screen_reachability_test.dart` és a
        # `test/app/theme_adoption_test.dart` a FÁT méri, a fájlt csak prózában
        # említi. Minden kör a saját dátumozott blokkját fűzi hozzá, ezért a
        # `tools/round-land.sh` ugyanazzal az append-only unióval oldja fel,
        # mint a HANDOFF-ot és a LESSONS-t.
        "docs/ui/migration-status.md",
    }
)
# Public barrelek generált artefaktumok (tool/gen_public_barrel.dart kimenetei);
# bármely két kör újra tudja őket generálni ugyanabból a `public/*.dart`
# halmazból, ezért NEM ütközési felület.
#
# KIZÁRÓLAG AZ ITT FELSOROLT útvonalak számítanak generáltnak — NEM glob.
# Egy feature barrelje csak akkor kerülhet ki az ütközés-számításból, ha a
# saját körében (a) fragmentum-forrás, (b) a generátor frissességét mérő
# teszt, és (c) explicit nyilvántartási bejegyzés egyaránt létezik (ADR 0336,
# E99-R18 §0.0c). E99-R18-ban kizárólag a `practice_generator` felel meg
# ennek; a többi feature root `public.dart`-ja és minden `public/*.dart`
# fragmentuma TOVÁBBRA IS TELJES ÉRTÉKŰ ütközési felület.
#
# A korábbi, `lib/features/*/public.dart` blanket glob szándékosan túl széles
# volt: a pilot egyetlen migrált feature-jére szélesítette ki a kivételt,
# ami a `SlotPlanningTest::test_real_epic_four_rounds_are_correctly_rejected`
# regressziós őrt némította el (L343). A fenti lista ezt a konkrét, mért
# kört nyilvántartja; egy jövőbeli feature csak a saját migrációs körében
# (a fenti három feltétel együttes teljesülésével) kerülhet ide.
GENERATED_PATH_PATTERNS: tuple[str, ...] = (
    "lib/features/practice_generator/public.dart",
)

# Az ARB-aggregátumok (`tool/gen_l10n_segments.dart` írja) NEM ütközési felület:
# a tartalmuk determinisztikusan újragenerálható, a frissességet a `l10n`
# gate-lépés méri (`tool/ci/check_l10n_parity.dart`), és a merge-zár sorosítja
# azokat a köröket, amelyek egy fragmentumhoz (`lib/l10n/base/`,
# `lib/l10n/features/`) hozzáérnek. Két ilyen kör PÁRHUZAMOSAN futhat — ez a
# GOV-11 / E99-R17 mechanikus feloldása (ADR 0307 §4).
#
# H8 self-heal (E99-R18, 2026-08-20): ez a halmaz és a fenti
# GENERATED_PATH_PATTERNS két FÜGGETLEN, additív kizárási ok — az
# `effective_paths` mindkettőt méri, egyik sem helyettesíti a másikat.
GENERATED_PATHS = frozenset(
    {
        "lib/l10n/app_en.arb",
        "lib/l10n/app_hu.arb",
    }
)
ADR_NAME = re.compile(r"^(\d{4})-[a-z0-9-]+\.md$")
ROUND_ID = re.compile(r"^[A-Z]\d{2}-R\d{2}$")
ROUND_TOKEN = re.compile(r"E\d{2}-R\d{2}")
PREREQ_LINE = re.compile(r"(?im)^.*(?:Előfeltétel|Elofeltetel)\b.*$")


def declared_prerequisites(repo: Path, brief: str | Path) -> frozenset[str]:
    """A brief „Előfeltétel" sorában nevesített körök.

    A fájl-diszjunktság NEM elég a párhuzamhoz: két kör hozzáérhet teljesen
    külön fájlokhoz úgy, hogy a második az elsőben SZÜLETŐ API-t importálja.
    Ezt a brief prózája mondja ki, ezért gépileg innen olvassuk.
    """
    path = Path(brief)
    if not path.is_absolute():
        path = repo / path
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return frozenset()
    tokens: set[str] = set()
    for line in PREREQ_LINE.findall(text):
        tokens.update(ROUND_TOKEN.findall(line))
    return frozenset(tokens)


def has_prerequisite_line(repo: Path, brief: str | Path) -> bool:
    """True iff a brief KIMONDJA az előfeltételét (akár úgy, hogy „nincs")."""
    path = Path(brief)
    if not path.is_absolute():
        path = repo / path
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return False
    return bool(PREREQ_LINE.search(text))


def unmet_prerequisites(repo: Path, round_id: str, brief: str, rows: list[tuple[str, str, str, str, str]]) -> list[str]:
    """A kör indulását blokkoló, még nem `done` körök (ADR 0495 D1).

    A blokkolás forrása a brief `Előfeltétel` sora — ez az EGYETLEN csatorna,
    amelyen az importfüggés (a fájllistából nem látszó „a második kör az
    elsőben SZÜLETŐ API-t használja" eset) kimondható. Aki nem függ, az
    párhuzamosan futhat; a fájl-átfedést a hívó `plan_slots` külön méri.

    MÉRVE 2026-09-03: a korábbi, epicen belüli VAK sorosítás („minden korábbi,
    nem `done` kör ugyanabból az epicből blokkol") a teljes hátralévő sort
    egyszálúvá tette — az `E15-R10`/`E15-R11` valódi, briefben kimondott
    előfeltétele az `E15-R03` (KÉSZ), az `E15-R12` pedig egyetlen fájlban sem
    ütközik egyetlen UI-körrel sem. A 2. slot ezért heteken át üresen állt
    (`.pipeline/chain.log`, „nincs a futókkal diszjunkt, előfeltétel-kész kör").

    FAIL-CLOSED tartalék: ha a brief NEM mondja ki az előfeltételét, a régi,
    epicen belüli sorosítás lép életbe rá — a hallgatás nem enged párhuzamot.
    """
    status_by_round = {row[0]: row[4] for row in rows}
    blocking: list[str] = []
    if not has_prerequisite_line(repo, brief):
        epic = round_id.split("-")[0]
        for other_round, _brief, _engine, _adr, status in rows:
            if other_round == round_id:
                break
            if other_round.startswith(epic + "-") and status != "done":
                blocking.append(other_round)
    for prerequisite in sorted(declared_prerequisites(repo, brief)):
        if prerequisite == round_id:
            continue
        if status_by_round.get(prerequisite, "done") != "done" and prerequisite not in blocking:
            blocking.append(prerequisite)
    return blocking


def is_generated_path(path: str) -> bool:
    """True iff [path] matches a generated-path pattern.

    Generated paths are artifacts that any round can recreate from its
    fragments (see [GENERATED_PATH_PATTERNS]). The fragments themselves
    are NOT generated and remain full-value collision surfaces.
    """
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in GENERATED_PATH_PATTERNS)


def effective_paths(paths: tuple[str, ...]) -> frozenset[str]:
    return frozenset(
        path
        for path in paths
        if path not in SERIALIZED_PATHS
        and path not in GENERATED_PATHS
        and not is_generated_path(path)
    )


def paths_conflict(left: frozenset[str], right: frozenset[str]) -> list[tuple[str, str]]:
    """Ütköző (bal, jobb) párok: azonos fájl vagy egymás könyvtár-előtagja."""
    conflicts: list[tuple[str, str]] = []
    for a in sorted(left):
        for b in sorted(right):
            if a == b or a.startswith(b.rstrip("/") + "/") or b.startswith(a.rstrip("/") + "/"):
                conflicts.append((a, b))
    return conflicts


def load_paths(repo: Path, brief: str | Path) -> frozenset[str]:
    path = Path(brief)
    if not path.is_absolute():
        path = repo / path
    return effective_paths(load_brief(path).metadata.allowed_paths)


def queue_rows(repo: Path) -> list[tuple[str, str, str, str, str]]:
    path = repo / "docs" / "execution" / "pipeline-queue.tsv"
    rows: list[tuple[str, str, str, str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 5:
            rows.append(tuple(parts[:5]))  # type: ignore[arg-type]
    return rows


# --- in-flight nyilvántartás ---------------------------------------------
# Egy fájl körönként, KEY=VALUE sorokkal. A driver írja/törli; a terv és az
# ADR-foglalás ezt olvassa. Fájl-alapú, mert a driver bash, és a crash utáni
# maradék így SZEMMEL is látszik (`tools/pipeline-status.sh`).


def inflight_entries(directory: Path) -> list[dict]:
    if not directory.is_dir():
        return []
    entries: list[dict] = []
    for path in sorted(directory.iterdir()):
        if not path.is_file():
            continue
        entry: dict[str, str] = {"_file": path.name}
        for line in path.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                entry[key.strip()] = value.strip()
        entries.append(entry)
    return entries


def _write_entry(directory: Path, round_id: str, values: dict[str, str]) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / round_id
    payload = "".join(f"{key}={value}\n" for key, value in sorted(values.items()))
    descriptor, temporary = tempfile.mkstemp(prefix=round_id + ".", dir=directory)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, target)
    return target


def branch_adr_numbers(repo: Path) -> set[int]:
    """MINDEN ágon (nem csak a main-en) létrehozott ADR-fájlok sorszámai.

    MÉRT rés (2026-08-05): a futó E04-R16 kör a saját branchén már lefoglalta a
    0172-t, de az a `main`-en még nem létezett — a lemez-alapú foglaló ezért
    ugyanazt a számot adta volna ki másodszor is. Ez a 0139-es duplikátum
    hibaosztálya, csak egy fázissal korábban.
    """
    result = subprocess.run(
        ["git", "-C", str(repo), "log", "--all", "--diff-filter=A", "--name-only", "--format=", "--", "docs/adr"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return set()
    numbers: set[int] = set()
    for line in result.stdout.splitlines():
        match = ADR_NAME.match(Path(line).name)
        if match:
            numbers.add(int(match.group(1)))
    return numbers


def reserve_adr(repo: Path, directory: Path, round_id: str) -> int:
    """A következő szabad ADR-szám ATOMI foglalása (O_EXCL marker-fájl).

    A lemezen lévő ADR-ek ÉS a már foglalt (in-flight) számok fölé megy, ezért
    két párhuzamos kör soha nem kaphatja ugyanazt — a marker létrehozása
    `O_CREAT|O_EXCL`, tehát a versenyt a fájlrendszer dönti el, nem az időzítés.
    """
    used = {
        int(match.group(1))
        for match in (ADR_NAME.match(path.name) for path in (repo / "docs" / "adr").iterdir() if path.is_file())
        if match
    }
    used.update(branch_adr_numbers(repo))
    directory.mkdir(parents=True, exist_ok=True)
    reserved_dir = directory / "adr"
    reserved_dir.mkdir(parents=True, exist_ok=True)
    used.update(int(path.name) for path in reserved_dir.iterdir() if path.name.isdigit())

    candidate = max(used) + 1 if used else 1
    while True:
        marker = reserved_dir / f"{candidate:04d}"
        try:
            handle = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            candidate += 1
            continue
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            stream.write(f"round={round_id}\n")
        return candidate


def plan_slots(repo: Path, directory: Path, slots: int, limit: int) -> dict:
    """Melyik várakozó körök indulhatnának MOST, a foglalt slotok mellett."""
    running = inflight_entries(directory)
    running_paths: list[tuple[str, frozenset[str]]] = []
    problems: list[str] = []
    for entry in running:
        brief = entry.get("brief", "")
        if not brief:
            continue
        try:
            running_paths.append((entry.get("round", entry["_file"]), load_paths(repo, brief)))
        except (BriefMetadataError, OSError) as error:
            problems.append(f"{entry.get('round', entry['_file'])}: {error}")

    free = max(0, slots - len(running))
    admitted: list[dict] = []
    rejected: list[dict] = []
    taken = list(running_paths)

    rows = queue_rows(repo)

    for round_id, brief, _engine, _adr, status in rows:
        if status != "pending" or len(admitted) >= min(free, limit):
            continue
        # A FUTÓ előfeltétel NEM teljesített előfeltétel: amíg a kör nem
        # merge-elt, az általa születő API nem létezik. Ezért itt nincs
        # kivétel a futó/aznap admittált körökre — a párhuzam csak valóban
        # független munkafolyamok között engedett.
        blocking = unmet_prerequisites(repo, round_id, brief, rows)
        if blocking:
            rejected.append(
                {
                    "round": round_id,
                    "reason": "teljesítetlen előfeltétel: " + ", ".join(blocking[:4]),
                }
            )
            continue
        try:
            paths = load_paths(repo, brief)
        except (BriefMetadataError, OSError) as error:
            rejected.append({"round": round_id, "reason": f"a brief nem elemezhető: {error}"})
            continue
        conflict_with = None
        conflicts: list[tuple[str, str]] = []
        for other_round, other_paths in taken:
            conflicts = paths_conflict(paths, other_paths)
            if conflicts:
                conflict_with = other_round
                break
        if conflict_with:
            rejected.append(
                {
                    "round": round_id,
                    "reason": f"átfedés a(z) {conflict_with} körrel",
                    "conflicts": [f"{a} ↔ {b}" for a, b in conflicts[:5]],
                }
            )
            continue
        admitted.append({"round": round_id, "brief": brief})
        taken.append((round_id, paths))

    return {
        "schema_version": 1,
        "slots": slots,
        "in_flight": [entry.get("round", entry["_file"]) for entry in running],
        "free_slots": free,
        "admitted": admitted,
        "rejected": rejected[:10],
        "problems": problems,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Párhuzamos kör-slotok (ADR 0171)")
    parser.add_argument("--repo", type=Path, default=REPO_ROOT)
    parser.add_argument("--inflight", type=Path, default=None, help="in-flight könyvtár (alap: <repo>/.pipeline/inflight)")
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check", help="briefek páronkénti diszjunkt-vizsgálata")
    check.add_argument("--brief", action="append", required=True)
    check.add_argument("--against-inflight", action="store_true", help="a futó körökkel is vesse össze")

    plan = sub.add_parser("plan", help="mi indulhatna most párhuzamosan")
    plan.add_argument("--slots", type=int, default=1)
    plan.add_argument("--limit", type=int, default=4)
    plan.add_argument(
        "--format",
        choices=("json", "round"),
        default="json",
        help="round: csak az ELSŐ indítható kör azonosítója (a bash driver ezt olvassa)",
    )

    reserve = sub.add_parser("reserve-adr", help="a következő szabad ADR-szám atomi foglalása")
    reserve.add_argument("--round", required=True)

    add = sub.add_parser("inflight-add")
    add.add_argument("--round", required=True)
    add.add_argument("--brief", required=True)
    add.add_argument("--branch", default="")
    add.add_argument("--worktree", default="")
    add.add_argument("--started-at", default="")

    remove = sub.add_parser("inflight-remove")
    remove.add_argument("--round", required=True)

    sub.add_parser("inflight-list")

    arguments = parser.parse_args(argv)
    repo = arguments.repo.resolve()
    directory = (arguments.inflight or (repo / ".pipeline" / "inflight")).resolve()

    if arguments.command == "check":
        try:
            loaded = [(brief, load_paths(repo, brief)) for brief in arguments.brief]
        except (BriefMetadataError, OSError) as error:
            print(f"round-slots: {error}", file=sys.stderr)
            return 2
        if arguments.against_inflight:
            for entry in inflight_entries(directory):
                if entry.get("brief"):
                    try:
                        loaded.append((entry["brief"], load_paths(repo, entry["brief"])))
                    except (BriefMetadataError, OSError):
                        continue
        conflicts: list[str] = []
        for index, (name, paths) in enumerate(loaded):
            for other_name, other_paths in loaded[index + 1 :]:
                for a, b in paths_conflict(paths, other_paths):
                    conflicts.append(f"{name} ↔ {other_name}: {a} / {b}")
        if conflicts:
            for line in conflicts[:20]:
                print(line)
            return 1
        print("diszjunkt")
        return 0

    if arguments.command == "plan":
        try:
            result = plan_slots(repo, directory, arguments.slots, arguments.limit)
        except OSError as error:
            print(f"round-slots: {error}", file=sys.stderr)
            return 2
        if arguments.format == "round":
            if result["admitted"]:
                print(result["admitted"][0]["round"])
            return 0
        print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
        return 0

    if arguments.command == "reserve-adr":
        if not ROUND_ID.match(arguments.round):
            print("round-slots: a --round alakja E##-R##", file=sys.stderr)
            return 2
        print(f"{reserve_adr(repo, directory, arguments.round):04d}")
        return 0

    if arguments.command == "inflight-add":
        if not ROUND_ID.match(arguments.round):
            print("round-slots: a --round alakja E##-R##", file=sys.stderr)
            return 2
        _write_entry(
            directory,
            arguments.round,
            {
                "round": arguments.round,
                "brief": arguments.brief,
                "branch": arguments.branch,
                "worktree": arguments.worktree,
                "started_at": arguments.started_at,
            },
        )
        return 0

    if arguments.command == "inflight-remove":
        target = directory / arguments.round
        if ROUND_ID.match(arguments.round) and target.is_file():
            target.unlink()
        return 0

    if arguments.command == "inflight-list":
        print(json.dumps(inflight_entries(directory), ensure_ascii=False, sort_keys=True, indent=2))
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
