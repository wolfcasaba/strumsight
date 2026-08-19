#!/usr/bin/env python3
"""Összevonásra javasolt brief-párok a sor-ból (E99-R16 D2 / ADR 0307 §3).

    tools/brief-merge-plan.py [--format json|text] [--max-paths 12]

MIÉRT: az ADR 0171 §5 kimondta, hogy a kör-összevonás MÉRT döntés legyen —
ez a tool a mérőeszköz (D1) és a döntéshozó (a brief-előkészítő orchesztrátor)
közötti hidat adja. A kimenet JAVASLAT, nem müvelet: a tool nem ír át briefet
és nem nyúl a sorhoz.

A négy feltétel MIND együttesen teljesül (ADR 0307 §3 szó szerint):

1. a két kör a sorban SZOMSZÉDOS és egymás közvetlen előfeltétele (azonos
   epic, egymás utáni sorszám);
2. azonos feature-gyökér (`lib/features/<x>/...` VAGY `lib/core/<x>/...`) az
   `allowed_paths` többségében — a számítás 3-szegmenses (mindkét ágon),
   mert a `brief-lint._feature_root` `lib/core/<x>/...` útvonalakra csak
   2 szegmenst adna, és ez a kör szövegéhez hű (R2, pre-flight §0.0);
3. az egyesített `allowed_paths` mérete ≤ `--max-paths` küszöb (alap 12);
4. egyik kör sem `native_gate = true` (a natív gate-es kör a saját CI-t
   futtatja, az összevonás elvesztené ezt a garanciát).

A kimenet minden párnál megadja a D1 illesztésből jövő MÉRT indokot: a két
kör becsült ideje, az összevonással megspórolt overhead, és az új egyesített
becslés.

Kilépési kódok:
    0 = van kimenet (akár nulla javaslat is)
    2 = a sor-fájl nem olvasható
    3 = használati hiba
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path, PurePosixPath

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from tools.ai_router.brief import BriefMetadataError, load_brief
else:
    from .ai_router.brief import BriefMetadataError, load_brief

REPO_ROOT = Path(__file__).resolve().parent.parent
QUEUE_RELATIVE = Path("docs") / "execution" / "pipeline-queue.tsv"

DEFAULT_MAX_PATHS = 12


def queue_rows(repo: Path) -> list[tuple[str, str, str]]:
    """(kör-azonosító, brief-útvonal, státusz) a sor-fájlból, sorrendben.

    A sor-fájl 5 oszlopos TSV (lásd a fájl fejlécét). A 4. oszlop az ADR,
    az 5. a státusz — nekünk csak a státusz kell. Hibás sorok kimaradnak.
    """
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


def load_brief_metadata(repo: Path, brief: str) -> object | None:
    """Egyetlen brief metadata-ja, hibakezeléssel. A merge-plan CSAK
    érvényes brief-ekből dolgozik — a hiányzó/érvénytelen sorok átugranak."""
    try:
        return load_brief(repo / brief).metadata
    except (BriefMetadataError, OSError):
        return None


def _feature_root(relative: str) -> PurePosixPath | None:
    """A brief-lint `_feature_root` logikáját KÖVETI, de NEM importálja —
    a pre-flight R2 szerint a 3-szegmenses számítás a brief szövegéhez hű,
    és a brief-lint saját (2-szegmenses) változata az S5 leletre van
    hangolva. Ezt a kört ne terhelje visszamenőleges kompatibilitás.

    Szabály: `lib/features/<x>/...` → 3 szegmens (`lib/features/<x>`),
            `lib/core/<x>/...`     → 3 szegmens (`lib/core/<x>`).
    """
    parts = PurePosixPath(relative).parts
    if len(parts) >= 3 and parts[0] == "lib" and parts[1] in ("features", "core"):
        return PurePosixPath(*parts[:3])
    return None


def _majority_feature_root(paths: tuple[str, ...]) -> PurePosixPath | None:
    """A `paths` többségi feature-gyökere. A `lib/`-n kívüli útvonalak
    (pl. `tools/...`, `docs/...`) semlegesek — csak az azonos gyökeret
    ADÓ útvonalak számítanak a többségbe. Ha nincs ilyen útvonal,
    None (a pár nem összevonható)."""
    roots: list[PurePosixPath] = []
    for path in paths:
        root = _feature_root(path)
        if root is not None:
            roots.append(root)
    if not roots:
        return None
    counts: dict[PurePosixPath, int] = {}
    for root in roots:
        counts[root] = counts.get(root, 0) + 1
    top_count = max(counts.values())
    if top_count * 2 <= len(roots):
        return None
    for root, count in counts.items():
        if count == top_count:
            return root
    return None  # pragma: no cover — determinisztikus a counts max()


def _is_predecessor_pair(left_id: str, right_id: str) -> bool:
    """Két kör-azonosítóról eldönti, hogy szomszédos, azonos epic, egymás
    utáni sorszámú páros (R3, pre-flight §0.0 — csak NYITOTT kör-párok).

    Az `E##-R##` formátumból kinyerjük az epicket és a sorszámot; a bal
    oldali sorszám eggyel kisebb, mint a jobb oldali.
    """
    left_parts = left_id.split("-")
    right_parts = right_id.split("-")
    if len(left_parts) != 2 or len(right_parts) != 2:
        return False
    if left_parts[0] != right_parts[0]:
        return False
    try:
        left_num = int(left_parts[1][1:])
        right_num = int(right_parts[1][1:])
    except ValueError:
        return False
    return right_num == left_num + 1


def _merged_paths(left: tuple[str, ...], right: tuple[str, ...]) -> tuple[str, ...]:
    """Az egyesített `allowed_paths` halmaz (duplikátumok nélkül). A
    sorrend a bal oldali, majd a jobb oldali újdonságok — a duplikátumok
    kimaradnak, így a küszöb-lépés a tényleges egyesített halmazra fut."""
    seen: dict[str, None] = {}
    for path in left:
        seen[path] = None
    for path in right:
        if path not in seen:
            seen[path] = None
    return tuple(seen.keys())


def _estimate_pair_seconds(
    left_size: int,
    right_size: int,
    *,
    slope_minutes_per_file: float | None,
    intercept_minutes: float | None,
) -> dict:
    """A két kör becsült ideje a D1 regresszióból (vagy semmi, ha nincs
    regresszió). A `tools/round-metrics.granularity_summary` másodperces
    kimenetet ad — itt percre konvertálunk és az `intercept` a fix
    overhead becslése."""
    if slope_minutes_per_file is None or intercept_minutes is None:
        return {
            "left_minutes": None,
            "right_minutes": None,
            "saved_minutes": None,
        }
    left_minutes = intercept_minutes + slope_minutes_per_file * left_size
    right_minutes = intercept_minutes + slope_minutes_per_file * right_size
    return {
        "left_minutes": left_minutes,
        "right_minutes": right_minutes,
        "saved_minutes": intercept_minutes,
    }


def find_merge_candidates(
    repo: Path,
    *,
    max_paths: int = DEFAULT_MAX_PATHS,
    regression: dict | None = None,
) -> list[dict]:
    """Az összevonható brief-párok listája. A `regression` a D1-ből jön —
    ha None, a mért indok nélkül marad, de a javaslatlista összeáll.

    A négy feltétel (D2):
    1. egymás előfeltétele (azonos epic, egymás utáni sorszám, mindkettő
       pending VAGY prepared — R3, pre-flight §0.0);
    2. azonos feature-gyökér az `allowed_paths` többségében (saját 3-szegmenses
       számítás, NEM a brief-lint importált változata);
    3. egyesített `allowed_paths` mérete ≤ `max_paths`;
    4. egyik kör sem `native_gate = true`.
    """
    rows = queue_rows(repo)
    pairs: list[dict] = []
    for index in range(len(rows) - 1):
        left_id, left_brief, left_status = rows[index]
        right_id, right_brief, right_status = rows[index + 1]
        if not _is_predecessor_pair(left_id, right_id):
            continue
        if left_status not in ("pending", "prepared") or right_status not in ("pending", "prepared"):
            continue
        left_metadata = load_brief_metadata(repo, left_brief)
        right_metadata = load_brief_metadata(repo, right_brief)
        if left_metadata is None or right_metadata is None:
            continue
        if left_metadata.native_gate or right_metadata.native_gate:
            continue
        left_root = _majority_feature_root(left_metadata.allowed_paths)
        right_root = _majority_feature_root(right_metadata.allowed_paths)
        if left_root is None or left_root != right_root:
            continue
        merged = _merged_paths(left_metadata.allowed_paths, right_metadata.allowed_paths)
        if len(merged) > max_paths:
            continue
        slope = intercept = None
        if regression is not None:
            slope = regression.get("slope_minutes_per_file")
            intercept = regression.get("intercept_minutes")
        estimate = _estimate_pair_seconds(
            len(left_metadata.allowed_paths) + len(left_metadata.gate_tests),
            len(right_metadata.allowed_paths) + len(right_metadata.gate_tests),
            slope_minutes_per_file=slope,
            intercept_minutes=intercept,
        )
        pairs.append(
            {
                "left_round": left_id,
                "right_round": right_id,
                "left_paths": len(left_metadata.allowed_paths),
                "right_paths": len(right_metadata.allowed_paths),
                "merged_paths": len(merged),
                "feature_root": str(left_root),
                "max_paths": max_paths,
                "regression_basis": {
                    "intercept_minutes": intercept,
                    "slope_minutes_per_file": slope,
                    "saved_overhead_minutes": estimate["saved_minutes"],
                    "left_minutes": estimate["left_minutes"],
                    "right_minutes": estimate["right_minutes"],
                },
                "rationale": (
                    f"azonos epic + egymás utáni sorszám, "
                    f"azonos feature-gyökér ({left_root}), "
                    f"egyesített allowed_paths = {len(merged)} ≤ {max_paths}, "
                    f"egyik sem natív gate; "
                    + (
                        f"becsült megtakarítás: {estimate['saved_minutes']:.0f}p fix overhead"
                        if estimate["saved_minutes"] is not None
                        else "mért indok nincs (nincs D1 regresszió)"
                    )
                ),
            }
        )
    return pairs


def render_text(pairs: list[dict]) -> str:
    if not pairs:
        return "brief-merge-plan: nincs javasolt összevonás\n"
    lines = [f"{'bal':<10} {'jobb':<10} {'egyesített':>10} {'feature-gyökér':<26} {'megtakarítás':>12}"]
    lines.append("-" * 70)
    for pair in pairs:
        saved = pair["regression_basis"]["saved_overhead_minutes"]
        saved_cell = "—" if saved is None else f"{saved:.0f}p"
        lines.append(
            f"{pair['left_round']:<10} {pair['right_round']:<10} "
            f"{pair['merged_paths']:>10} {pair['feature_root']:<26} {saved_cell:>12}"
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Brief-összevonási javaslat (E99-R16 D2)")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--max-paths", type=int, default=DEFAULT_MAX_PATHS, help=f"az egyesített allowed_paths felső küszöbe (alap {DEFAULT_MAX_PATHS})")
    parser.add_argument("--repo", type=Path, default=REPO_ROOT)
    parser.add_argument(
        "--with-regression",
        type=Path,
        default=None,
        help="opcionális D1 JSON kimenet, amiből a mért indokot veszi",
    )
    arguments = parser.parse_args(argv)

    regression: dict | None = None
    if arguments.with_regression is not None:
        try:
            regression = json.loads(arguments.with_regression.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"brief-merge-plan: a regresszió-forrás nem olvasható: {error}", file=sys.stderr)
            return 3

    pairs = find_merge_candidates(arguments.repo, max_paths=arguments.max_paths, regression=regression)
    if arguments.format == "json":
        print(
            json.dumps(
                {
                    "schema_version": 1,
                    "max_paths": arguments.max_paths,
                    "regression_basis": bool(regression is not None),
                    "candidates": pairs,
                },
                ensure_ascii=False,
                sort_keys=True,
                indent=2,
            )
        )
    else:
        print(render_text(pairs), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())