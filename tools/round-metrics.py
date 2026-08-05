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

LINE = re.compile(r"^(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+\-]\d{2}:\d{2})\s\s(?P<message>.*)$")
START = re.compile(r"^orchestrátor-session indul \((?P<round>[A-Z0-9-]+)\)")
MERGED = re.compile(r"^(?P<round>[A-Z0-9-]+) MERGE-ELVE")
HEAL = re.compile(r"^ÖNJAVÍTÓ KÖR indul: (?P<round>[A-Z0-9-]+) / (?P<code>[A-Z0-9-]+)")
BLOCKED = re.compile(r"^HIBA: (?P<reason>.*)$")
HALTED = re.compile(r"^a lánc MEGÁLLT")


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
    arguments = parser.parse_args(argv)

    try:
        text = arguments.chain_log.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        print(f"round-metrics: a lánc-napló nem olvasható: {error}", file=sys.stderr)
        return 2

    result = summarize(parse_chain_log(text))
    if not result["rounds"]:
        print("round-metrics: a naplóban nincs egyetlen BEFEJEZETT kör sem", file=sys.stderr)
        return 2

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
