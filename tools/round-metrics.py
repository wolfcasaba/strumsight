#!/usr/bin/env python3
"""Kör-időmérleg a lánc-naplóból (ADR 0171 §5).

    tools/round-metrics.py [--chain-log .pipeline/chain.log] [--last 20]
    tools/round-metrics.py --format json

MIÉRT: a gyorsítási döntések eddig becslésen álltak („a CI a szűk
keresztmetszet"), és a mérés mást mutatott (docs/LESSONS.md: a CI a kör ~8%-a).
Ez a CLI a `.pipeline/chain.log` MÉRT eseményeiből számol, nem emlékezetből:

* `kör-idő`   — az orchestrátor-session indulásától a MERGE-ELVE jelzésig;
* `holtidő`   — az előző kör merge-e és a következő kör indulása között eltelt
  idő (ide esik a cron-várakozás és minden blokkolt firing);
* `javító/önjavító körök` — a kör-időbe beépülő ismétlés mennyisége;
* `holtidő-arány` — a lánc mennyi ideje NEM dolgozott.

A kör-granularitás (5. lever) döntése ezen a kimeneten áll: ha egy kör
kör-ideje a fix overheadhez (pre-flight + review + CI + záró rituálék) képest
kicsi, a kör összevonása a szomszédjával több időt hoz, mint bármelyik
motor-gyorsítás. A tool NEM von össze köröket — mér, hogy a döntés ne becslés
legyen.

Kilépési kódok:
    0 = van kimenet
    2 = a napló nem olvasható / nincs benne egyetlen teljes kör sem
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

LEDGER_RELATIVE = Path(".pipeline") / "cost.tsv"
REGISTRY_RELATIVE = Path("docs") / "execution" / "engine-registry.tsv"
QUEUE_RELATIVE = Path("docs") / "execution" / "pipeline-queue.tsv"

LINE = re.compile(r"^(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+\-]\d{2}:\d{2})\s\s(?P<message>.*)$")
START = re.compile(r"^orchestrátor-session indul \((?P<round>[A-Z0-9-]+)\)")
MERGED = re.compile(r"^(?P<round>[A-Z0-9-]+) MERGE-ELVE")
HEAL = re.compile(r"^ÖNJAVÍTÓ KÖR indul: (?P<round>[A-Z0-9-]+) / (?P<code>[A-Z0-9-]+)")
BLOCKED = re.compile(r"^HIBA: (?P<reason>.*)$")
HALTED = re.compile(r"^a lánc MEGÁLLT")
# E99-R14 D3: a motor-statisztika kimenetének alapja. A `log "következő kör: …"`
# sor rögzíti, melyik motor vitte a kört — az `implementer=<x>` részt innen
# nyerjük. A `[A-Za-z0-9_-]+` minta megengedi a kötőjeles motor-neveket
# (`sonnet-impl`, `qwen-plus`).
NEXT_ROUND = re.compile(
    r"^következő kör: (?P<round>[A-Z0-9-]+) · orchestrátor=(?P<orchestrator>[A-Za-z0-9_-]+) · implementer=(?P<implementer>[A-Za-z0-9_-]+)"
)


def parse_chain_log(text: str) -> list[dict]:
    """Nyers események: (ts, kind, round, detail)."""
    events: list[dict] = []
    for line in text.splitlines():
        match = LINE.match(line)
        if not match:
            continue
        timestamp = datetime.fromisoformat(match.group("ts"))
        message = match.group("message")
        for kind, pattern in (("start", START), ("merged", MERGED), ("heal", HEAL), ("blocked", BLOCKED)):
            hit = pattern.match(message)
            if hit:
                groups = hit.groupdict()
                events.append(
                    {
                        "at": timestamp,
                        "kind": kind,
                        "round": groups.get("round", ""),
                        "detail": groups.get("reason") or groups.get("code") or "",
                    }
                )
                break
        else:
            if HALTED.match(message):
                events.append({"at": timestamp, "kind": "halt", "round": "", "detail": ""})
            else:
                next_match = NEXT_ROUND.match(message)
                if next_match:
                    events.append(
                        {
                            "at": timestamp,
                            "kind": "next_round",
                            "round": next_match.group("round"),
                            "detail": "",
                            "implementer": next_match.group("implementer"),
                        }
                    )
    return events


def summarize(events: list[dict]) -> dict:
    """Körök + lánc-szintű összesítés. Csak BEFEJEZETT körök számítanak."""
    rounds: list[dict] = []
    open_start: dict[str, datetime] = {}
    heals: dict[str, int] = {}
    halts: dict[str, int] = {}
    blocked_since_last_merge = 0
    last_merge_at: datetime | None = None
    pending_blocked: list[dict] = []
    current_round: str = ""

    for event in events:
        kind = event["kind"]
        if kind == "start":
            open_start.setdefault(event["round"], event["at"])
            current_round = event["round"]
        elif kind == "heal":
            heals[event["round"]] = heals.get(event["round"], 0) + 1
        elif kind == "halt":
            if current_round:
                halts[current_round] = halts.get(current_round, 0) + 1
        elif kind == "blocked":
            blocked_since_last_merge += 1
            pending_blocked.append(event)
        elif kind == "merged":
            round_id = event["round"]
            started = open_start.pop(round_id, None)
            if started is None:
                continue
            idle_before = None
            if last_merge_at is not None:
                idle_before = (started - last_merge_at).total_seconds()
            rounds.append(
                {
                    "round": round_id,
                    "started_at": started.isoformat(),
                    "merged_at": event["at"].isoformat(),
                    "duration_seconds": (event["at"] - started).total_seconds(),
                    "idle_before_seconds": idle_before,
                    "blocked_firings_before": blocked_since_last_merge if last_merge_at else 0,
                    "self_heal_rounds": heals.pop(round_id, 0),
                    "halts": halts.pop(round_id, 0),
                }
            )
            last_merge_at = event["at"]
            blocked_since_last_merge = 0
            pending_blocked = []
            current_round = ""

    durations = [item["duration_seconds"] for item in rounds]
    idles = [item["idle_before_seconds"] for item in rounds if item["idle_before_seconds"] is not None]
    total_span = sum(durations) + sum(idles)
    summary = {
        "rounds_measured": len(rounds),
        "median_round_seconds": statistics.median(durations) if durations else None,
        "mean_round_seconds": statistics.fmean(durations) if durations else None,
        "median_idle_seconds": statistics.median(idles) if idles else None,
        "total_idle_seconds": sum(idles) if idles else 0,
        "idle_share": (sum(idles) / total_span) if total_span else None,
        "rounds_with_self_heal": sum(1 for item in rounds if item["self_heal_rounds"]),
        "max_idle_seconds": max(idles) if idles else None,
    }
    return {"schema_version": 1, "rounds": rounds, "summary": summary}


# E99-R14 D3: motoronkénti statisztika. A számítás kizárólag a chain.log
# eseményeiből dolgozik (nincs hálózat, nincs `gh` hívás), így tesztelhető
# rögzített naplóból. A 10 óránál hosszabb kör-idő kiugró értékként marad
# ki (mérve: E07-R16 = 2636 perc, egy 42 órás halt-epizód, ami nem
# motor-tulajdonság).
OUTLIER_THRESHOLD_SECONDS = 10 * 3600


def engines_summary(events: list[dict], *, outlier_threshold: int = OUTLIER_THRESHOLD_SECONDS, epic: str | None = None) -> dict:
    """Motoronkénti statisztika a `következő kör: … implementer=<x>` sorokból.

    Az implementer hozzárendelés a `next_round` eseményből jön, a START és a
    MERGED eseményekkel összekötve. A kiugró-szűrés CSAK a középső/átlag
    számítást érinti — a `n` mező a TELJES mintát tükrözi (külön `n` oszlop
    nélkül a kiugró-szűrés hatása láthatatlan lenne).

    Az `epic` paraméter (opcionális) csak az adott epic köreit tartja meg
    (pl. `epic="E07"` → `E07-R01`, `E07-R02`, ...). A szűrés a `round`
    mező `epic-` prefix-ellenőrzésével történik, és a motor-aggregátum
    ELŐTT lép életbe — így a `next_round` implementer-hozzárendelés, a
    start/merged időpár, és a heal-számlálás is csak az epiches tartozó
    körökre fut le. Üres epic-szűrés esetén a globális nézet marad.
    """
    if epic is not None:
        epic_prefix = f"{epic}-"
        events = [event for event in events if (event.get("round") or "").startswith(epic_prefix)]

    # 1. lépés: implementer hozzárendelés az egyes körökhöz. A `next_round`
    # esemény a kör KIVÁLASZTÁSAKOR íródik, tehát néha ELŐBB, mint a `start`
    # (a motor-override és a függetlenség-feloldás a kettő között futhat le),
    # néha UTÁNA. A kettő közötti SORREND nem garancia — a legegyszerűbb
    # asszociáció: a `start` a `next_round` implementerét KAPJA, ha a
    # `next_round.round` megegyezik; ellenkező esetben a `next_round`
    # implementere a forrás.
    implementer_for_round: dict[str, str] = {}
    implementer_seen_at: dict[str, datetime] = {}
    latest_event_at: dict[str, datetime] = {}
    for event in events:
        round_id = event.get("round") or ""
        if not round_id:
            continue
        kind = event["kind"]
        at = event["at"]
        if kind == "next_round":
            implementer = event.get("implementer") or ""
            if implementer:
                implementer_for_round[round_id] = implementer
                implementer_seen_at[round_id] = at
        latest_event_at[round_id] = at

    # 2. lépés: a meglévő `summarize()`-szerű köridő-párok (start → merged).
    # A `next_round` implementerét a `start` ESEMÉNY KÖRÉRE rendeljük, a
    # START vagy a NEXT_ROUND időbélyegéből a korábbit használva.
    open_start: dict[str, datetime] = {}
    open_merged_at: dict[str, datetime] = {}

    for event in events:
        round_id = event["round"]
        if not round_id:
            continue
        kind = event["kind"]
        at = event["at"]
        if kind == "start":
            if round_id not in open_start:
                open_start[round_id] = at
        elif kind == "merged":
            if round_id in open_start:
                open_merged_at[round_id] = at

    # 3. lépés: a tényleges motor-aggregátum. A `n` a TELJES (szűrés nélküli)
    # mintán mért, így a kiugró-szűrés hatása a középső/átlag-becslésre
    # külön látható lesz.
    durations: dict[str, list[float]] = {}
    heals: dict[str, int] = {}
    heal_count_by_event = {}
    for event in events:
        if event["kind"] == "heal":
            heal_count_by_event[event["round"]] = heal_count_by_event.get(event["round"], 0) + 1

    for round_id, start_at in open_start.items():
        merged_at = open_merged_at.get(round_id)
        if merged_at is None:
            continue
        implementer = implementer_for_round.get(round_id, "")
        if not implementer:
            continue
        duration = (merged_at - start_at).total_seconds()
        durations.setdefault(implementer, []).append(duration)
        if heal_count_by_event.get(round_id):
            heals[implementer] = heals.get(implementer, 0) + 1

    rows = []
    for implementer, samples in sorted(durations.items()):
        filtered = [s for s in samples if s < outlier_threshold]
        n_total = len(samples)
        n_filtered = len(filtered)
        if filtered:
            median_s = statistics.median(filtered)
            mean_s = statistics.fmean(filtered)
        else:
            median_s = None
            mean_s = None
        rows.append(
            {
                "implementer": implementer,
                "n": n_total,
                "outliers_dropped": n_total - n_filtered,
                "median_seconds": median_s,
                "mean_seconds": mean_s,
                "self_heal_rounds": heals.get(implementer, 0),
            }
        )

    return {
        "schema_version": 1,
        "outlier_threshold_seconds": outlier_threshold,
        "epic": epic,
        "engines": rows,
    }


# E99-R16 D1: kör-granularitás. A rögzített (merge-elt) köröket a briefjük
# méretével (allowed_paths + gate_tests darabszáma, native_gate flag) párosítjuk,
# és a kör-időt a méret függvényében ábrázoljuk. A tengelymetszet a MÉRT fix
# overhead, a meredekség a fájlonkénti határköltség. A 10 óránál hosszabb
# körök kiugróként maradnak ki — az E07-R16 (2636p halt-epizód) egyetlen
# pontja elmozdítaná a meredekséget a tűrésen kívülre (mérve: S6 szabály
# falszifikációs cellája).
GRANULARITY_SIZE_BANDS: tuple[tuple[int, int], ...] = ((1, 4), (5, 8), (9, 10**9))


def _round_size(metadata) -> int:
    """`allowed_paths` + `gate_tests` egyesített mérete — a brief-fájl maga
    nem számít (a granularitás a MUNKÁ-t méri, nem a brief-dokumentumot)."""
    return len(metadata.allowed_paths) + len(metadata.gate_tests)


def load_briefs_for_queue(repo: Path, queue_path: Path | None = None) -> dict[str, object]:
    """A sor-fájlban HIVATKOZOTT összes brief metadata-ja. A `round_id` (normált
    nagybetűs) → BriefMetadata. A hibás / nem olvasható briefek kimaradnak
    (a granularitás-elemzés csak az érvényes adatpontokból dolgozik).

    A `brief` importja LOKÁLIS (NEM modul-szintű): a `--engines` / `--cost` /
    alapértelmezett tábla útvonalak nem igénylik a `tools` csomagot, így a
    másolt + önállóan futtatott script-példány (ld. `EnginesOutlierFalsificationTest`)
    e nélkül is működik. A `--granularity` az egyetlen útvonal, ami
    brief-eket olvas — az úgysem értelmezhető másolt scriptként.
    """
    if __package__ in (None, ""):
        # A `tools` csomag csak a repo-gyökérből indulva importálható —
        # ha a script más cwd-ből fut (pl. a granularitás-teszt subprocess-e),
        # a saját fájl-helye alapján tesszük elérhetővé.
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
        from tools.ai_router.brief import BriefMetadataError, load_brief
    else:
        from .ai_router.brief import BriefMetadataError, load_brief
    if queue_path is None:
        queue_path = repo / QUEUE_RELATIVE
    try:
        text = queue_path.read_text(encoding="utf-8")
    except OSError:
        return {}
    briefs: dict[str, object] = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        brief_path = repo / parts[1]
        try:
            briefs[parts[0].upper()] = load_brief(brief_path).metadata
        except (BriefMetadataError, OSError):
            continue
    return briefs


def granularity_summary(
    events: list[dict],
    *,
    briefs: dict[str, object],
    outlier_threshold: int = OUTLIER_THRESHOLD_SECONDS,
) -> dict:
    """Kör-granularitás: a merge-elt körök kör-ideje ↔ brief-méret párosítása.

    A kiugró-szűrés CSAK a sáv- és regresszió-számítást érinti (ugyanaz a
    elv, mint az `engines_summary`-nál): a `samples` mező a TELJES mintát
    tükrözi, hogy a kiugrók száma látható maradjon.

    A lineáris illesztés `statistics.linear_regression` (Python 3.10+) — a
    `tools/round-metrics.py` már importálja a `statistics` modult, és a
    numpy/scipy bevezetése nem indokolt.
    """
    open_start: dict[str, datetime] = {}
    open_merged_at: dict[str, datetime] = {}
    for event in events:
        round_id = event.get("round") or ""
        if not round_id:
            continue
        kind = event["kind"]
        at = event["at"]
        if kind == "start" and round_id not in open_start:
            open_start[round_id] = at
        elif kind == "merged" and round_id in open_start:
            open_merged_at[round_id] = at

    samples: list[dict] = []
    for round_id, start_at in open_start.items():
        merged_at = open_merged_at.get(round_id)
        if merged_at is None:
            continue
        metadata = briefs.get(round_id)
        if metadata is None:
            continue
        duration = (merged_at - start_at).total_seconds()
        samples.append(
            {
                "round": round_id,
                "duration_seconds": duration,
                "size_files": _round_size(metadata),
                "native_gate": bool(metadata.native_gate),
            }
        )

    filtered = [item for item in samples if item["duration_seconds"] < outlier_threshold]
    outliers_dropped = len(samples) - len(filtered)

    bands: list[dict] = []
    for low, high in GRANULARITY_SIZE_BANDS:
        band_samples = [item for item in filtered if low <= item["size_files"] <= high]
        durations_band = [item["duration_seconds"] for item in band_samples]
        if durations_band:
            median_s = statistics.median(durations_band)
            mean_s = statistics.fmean(durations_band)
        else:
            median_s = None
            mean_s = None
        bands.append(
            {
                "size_min": low,
                "size_max": high if high < 10**9 else None,
                "n": len(band_samples),
                "median_seconds": median_s,
                "mean_seconds": mean_s,
            }
        )

    regression: dict
    xs = [float(item["size_files"]) for item in filtered]
    ys = [item["duration_seconds"] / 60.0 for item in filtered]
    if len(xs) >= 2:
        slope, intercept = statistics.linear_regression(xs, ys)
        correlation = statistics.correlation(xs, ys)
        r_squared = correlation * correlation if correlation is not None else None
        regression = {
            "n": len(xs),
            "slope_minutes_per_file": slope,
            "intercept_minutes": intercept,
            "r_squared": r_squared,
        }
    else:
        regression = {
            "n": len(xs),
            "slope_minutes_per_file": None,
            "intercept_minutes": None,
            "r_squared": None,
        }

    return {
        "schema_version": 1,
        "outlier_threshold_seconds": outlier_threshold,
        "samples": samples,
        "outliers_dropped": outliers_dropped,
        "bands": bands,
        "regression": regression,
    }


def _fmt_slope(value: float | None) -> str:
    return "—" if value is None else f"{value:.1f}"


def render_granularity_table(result: dict) -> str:
    """A granularitás-elemzés szöveges táblája: sávonkénti medián + regresszió."""
    lines = [
        f"{'méret-sáv':<14} {'n':>4} {'medián':>9} {'átlag':>9}",
        "-" * 40,
    ]
    for band in result["bands"]:
        size_label = (
            f"{band['size_min']}+"
            if band["size_max"] is None
            else f"{band['size_min']}–{band['size_max']}"
        )
        median_cell = "—" if band["median_seconds"] is None else f"{band['median_seconds'] / 60:.0f}p"
        mean_cell = "—" if band["mean_seconds"] is None else f"{band['mean_seconds'] / 60:.0f}p"
        lines.append(
            f"{size_label:<14} {band['n']:>4} {median_cell:>9} {mean_cell:>9}"
        )

    reg = result["regression"]
    lines.append("")
    lines.append(
        f"lineáris illesztés (kör-idő ~ fájlszám): n={reg['n']}, "
        f"meredekség={_fmt_slope(reg['slope_minutes_per_file'])}p/fájl, "
        f"tengelymetszet={_fmt_slope(reg['intercept_minutes'])}p"
    )
    if reg["r_squared"] is not None:
        lines.append(f"R²={reg['r_squared']:.3f}")
    lines.append(
        f"A 10+ órás kör-idők kiugróként maradnak ki (küszöb: "
        f"{result['outlier_threshold_seconds'] // 3600} óra, "
        f"ebben a mintában {result['outliers_dropped']} db)."
    )
    return "\n".join(lines) + "\n"


def render_engines_table(result: dict) -> str:
    """A motoronkénti statisztika szöveges táblája."""
    rows = result["engines"]
    if not rows:
        return "round-metrics: a naplóban nincs motor-hozzárendelhető kör\n"
    lines = [
        f"{'implementer':<16} {'n':>4} {'kiugró':>7} {'medián':>9} {'átlag':>9} {'önjavító':>9}",
        "-" * 60,
    ]
    for row in rows:
        median_cell = "—" if row["median_seconds"] is None else f"{row['median_seconds'] / 60:.0f}p"
        mean_cell = "—" if row["mean_seconds"] is None else f"{row['mean_seconds'] / 60:.0f}p"
        lines.append(
            f"{row['implementer']:<16} {row['n']:>4} {row['outliers_dropped']:>7} "
            f"{median_cell:>9} {mean_cell:>9} {row['self_heal_rounds']:>9}"
        )
    lines.append("")
    lines.append(
        f"Az átlag/medián kiszámítása előtt a 10+ órás kör-idők kiugróként kimaradnak "
        f"(küszöb: {result['outlier_threshold_seconds'] // 3600} óra, mérve: E07-R16 = 2636p)."
    )
    return "\n".join(lines) + "\n"


def engine_prices(repo: Path) -> dict[str, tuple[float, float]]:
    """Motoronkénti (input, output) ár $/1M tokenben a nyilvántartásból."""
    prices: dict[str, tuple[float, float]] = {}
    try:
        text = (repo / REGISTRY_RELATIVE).read_text(encoding="utf-8")
    except OSError:
        return prices
    for line in text.splitlines():
        if line.startswith("#") or line.startswith("name\t") or not line.strip():
            continue
        columns = line.split("\t")
        if len(columns) < 12:
            continue
        try:
            prices[columns[0]] = (float(columns[10]), float(columns[11]))
        except ValueError:
            continue   # "-" = előfizetéses motor, nincs token-ár
    return prices


def summarize_cost(ledger_text: str, prices: dict[str, tuple[float, float]]) -> dict:
    """Kör- és motor-szintű token/költség kimutatás.

    A napló EGY összesített token-számot ad (a Codex „tokens used" sora), az
    input/output arányt NEM. Ezért nem találunk ki arányt: alsó becslés = minden
    token input-áron, felső = minden output-áron. A valóság a kettő között van,
    és a döntéshez (melyik motor mennyibe kerül egy LEZÁRT körre) ez elég.
    """
    runs: list[dict] = []
    for line in ledger_text.splitlines():
        if line.startswith("timestamp\t") or not line.strip():
            continue
        columns = line.split("\t")
        if len(columns) < 7:
            continue
        try:
            tokens = int(columns[4])
        except ValueError:
            continue
        engine = columns[2]
        priced = engine in prices
        price_in, price_out = prices.get(engine, (0.0, 0.0))
        runs.append(
            {
                "at": columns[0],
                "round": columns[1],
                "engine": engine,
                "model": columns[3],
                "tokens": tokens,
                "continuations": columns[5],
                "status": columns[6],
                "priced": priced,
                "cost_low_usd": tokens * price_in / 1_000_000,
                "cost_high_usd": tokens * price_out / 1_000_000,
            }
        )

    by_engine: dict[str, dict] = {}
    for run in runs:
        bucket = by_engine.setdefault(
            run["engine"],
            {
                "runs": 0,
                "rounds": set(),
                "tokens": 0,
                "cost_low_usd": 0.0,
                "cost_high_usd": 0.0,
                "unfinished": 0,
                "priced": run["priced"],
            },
        )
        bucket["runs"] += 1
        bucket["rounds"].add(run["round"])
        bucket["tokens"] += run["tokens"]
        bucket["cost_low_usd"] += run["cost_low_usd"]
        bucket["cost_high_usd"] += run["cost_high_usd"]
        if run["status"] not in ("done", "stopped"):
            bucket["unfinished"] += 1
    for bucket in by_engine.values():
        rounds = len(bucket.pop("rounds"))
        bucket["rounds"] = rounds
        # A LEZÁRT körre vetített ár a döntés alapja: a félbehagyott futások és
        # a javító körök tokenje is a kör számlájára megy.
        bucket["usd_per_round_low"] = bucket["cost_low_usd"] / rounds if rounds else None
        bucket["usd_per_round_high"] = bucket["cost_high_usd"] / rounds if rounds else None
    return {"schema_version": 1, "runs": runs, "by_engine": by_engine}


def render_cost(result: dict) -> str:
    lines = [
        f"{'motor':<16} {'futás':>6} {'kör':>5} {'token':>12} {'$/kör (alsó–felső)':>24} {'befejezetlen':>13}",
        "-" * 82,
    ]
    for engine, bucket in sorted(result["by_engine"].items()):
        low = bucket["usd_per_round_low"]
        high = bucket["usd_per_round_high"]
        # Az előfizetéses motor (Terra) tokenje nem számlázódik külön: a
        # nyilvántartásban `-` az ára. A 0.00 itt félrevezető lenne.
        if not bucket["priced"]:
            span = "előfizetés"
        else:
            span = "—" if low is None else f"{low:.2f}–{high:.2f}"
        lines.append(
            f"{engine:<16} {bucket['runs']:>6} {bucket['rounds']:>5} {bucket['tokens']:>12,} {span:>24} {bucket['unfinished']:>13}"
        )
    lines.append("")
    lines.append(
        "A napló csak összesített tokent ad, input/output bontást nem — ezért "
        "alsó becslés = minden token input-áron, felső = output-áron."
    )
    return "\n".join(lines) + "\n"


def _minutes(value: float | None) -> str:
    return "—" if value is None else f"{value / 60:.0f}p"


def render_table(result: dict, *, last: int) -> str:
    rounds = result["rounds"][-last:] if last else result["rounds"]
    lines = [
        f"{'kör':<10} {'kör-idő':>9} {'holtidő':>9} {'blokkolt':>9} {'önjavító':>9}",
        "-" * 50,
    ]
    for item in rounds:
        lines.append(
            f"{item['round']:<10} {_minutes(item['duration_seconds']):>9} "
            f"{_minutes(item['idle_before_seconds']):>9} "
            f"{item['blocked_firings_before']:>9} {item['self_heal_rounds']:>9}"
        )
    summary = result["summary"]
    share = summary["idle_share"]
    lines += [
        "",
        f"mért körök:            {summary['rounds_measured']}",
        f"medián kör-idő:        {_minutes(summary['median_round_seconds'])}",
        f"medián holtidő:        {_minutes(summary['median_idle_seconds'])}",
        f"összes holtidő:        {_minutes(summary['total_idle_seconds'])}",
        f"holtidő-arány:         {'—' if share is None else f'{share * 100:.1f}%'}",
        f"önjavítást igénylő:    {summary['rounds_with_self_heal']} kör",
    ]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Kör-időmérleg (ADR 0171)")
    parser.add_argument("--chain-log", type=Path, default=REPO_ROOT / ".pipeline" / "chain.log")
    parser.add_argument("--last", type=int, default=20, help="hány kör jelenjen meg a táblában")
    parser.add_argument("--format", choices=("table", "json", "summary-line"), default="table")
    parser.add_argument(
        "--cost",
        action="store_true",
        help="token/költség kimutatás a .pipeline/cost.tsv főkönyvből (ADR 0174)",
    )
    parser.add_argument("--ledger", type=Path, default=REPO_ROOT / LEDGER_RELATIVE)
    parser.add_argument("--repo", type=Path, default=REPO_ROOT)
    parser.add_argument(
        "--engines",
        action="store_true",
        help="motoronkénti statisztika (E99-R14 D3): n, medián/átlag, önjavító — a 10+ órás kör-idők kiugróként kimaradnak",
    )
    parser.add_argument(
        "--epic",
        help="a `--engines` statisztikát egy adott epicre szűkíti (pl. `E07` → csak E07-R* körök); a motor-aggregátum ELŐTT lép életbe",
    )
    parser.add_argument(
        "--granularity",
        action="store_true",
        help="E99-R16 D1: a merge-elt körök kör-ideje ↔ brief-méret (allowed_paths + gate_tests) párosítása; méret-sávonkénti medián + lineáris regresszió",
    )
    parser.add_argument(
        "--queue",
        type=Path,
        default=REPO_ROOT / QUEUE_RELATIVE,
        help="a granularitás-elemzéshez használt sor-fájl (alap: docs/execution/pipeline-queue.tsv)",
    )
    arguments = parser.parse_args(argv)

    if arguments.cost:
        try:
            ledger_text = arguments.ledger.read_text(encoding="utf-8")
        except OSError as error:
            print(f"round-metrics: a költség-főkönyv nem olvasható: {error}", file=sys.stderr)
            return 2
        result = summarize_cost(ledger_text, engine_prices(arguments.repo))
        if not result["runs"]:
            print("round-metrics: a főkönyvben nincs egyetlen futás sem", file=sys.stderr)
            return 2
        if arguments.format == "json":
            print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
        else:
            print(render_cost(result), end="")
        return 0

    try:
        text = arguments.chain_log.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        print(f"round-metrics: a lánc-napló nem olvasható: {error}", file=sys.stderr)
        return 2

    result = summarize(parse_chain_log(text))
    if not result["rounds"]:
        print("round-metrics: a naplóban nincs egyetlen BEFEJEZETT kör sem", file=sys.stderr)
        return 2

    if arguments.engines:
        engines_result = engines_summary(parse_chain_log(text), epic=arguments.epic)
        if arguments.format == "json":
            print(json.dumps(engines_result, ensure_ascii=False, sort_keys=True, indent=2))
        else:
            print(render_engines_table(engines_result), end="")
        return 0

    if arguments.granularity:
        briefs = load_briefs_for_queue(arguments.repo, arguments.queue)
        granularity_result = granularity_summary(
            parse_chain_log(text),
            briefs=briefs,
        )
        if not granularity_result["samples"]:
            print(
                "round-metrics: a naplóban nincs a sor-fájl briefjeihez párosítható merge-elt kör",
                file=sys.stderr,
            )
            return 2
        if arguments.format == "json":
            print(json.dumps(granularity_result, ensure_ascii=False, sort_keys=True, indent=2))
        else:
            print(render_granularity_table(granularity_result), end="")
        return 0

    if arguments.format == "json":
        print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    elif arguments.format == "summary-line":
        summary = result["summary"]
        share = summary["idle_share"]
        print(
            f"mért körök: {summary['rounds_measured']}"
            f" · medián kör-idő: {_minutes(summary['median_round_seconds'])}"
            f" · medián holtidő: {_minutes(summary['median_idle_seconds'])}"
            f" · holtidő-arány: {'—' if share is None else f'{share * 100:.1f}%'}"
        )
    else:
        print(render_table(result, last=arguments.last), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
