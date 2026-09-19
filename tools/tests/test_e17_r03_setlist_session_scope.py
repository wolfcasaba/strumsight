"""Regression guard for E17-R03 / H3 (ADR 0112 self-heal round, 2026-09-19).

Measured on ``main @ 3ffde512`` — the round halted in its PRE-FLIGHT, before
any engine started, because the brief's premise is measurably false::

    §2: "a `SetlistDetailScreen` (ami a természetes belépési pontja)"

There are TWO disjoint setlist worlds on this tree, and the screen the round
must wire belongs to the other one:

* legacy ``Setlist{id, name, songIds}``
  (``lib/features/songs/model/setlist.dart``) — timestamp ids, key-value
  store, rendered by the reachable ``SetlistDetailScreen``;
* V2 ``SongSetlist{id, name, items: [SongSetlistItem{SongId, overrides}]}``
  (``lib/features/song_trainer/domain/models/song_setlist.dart``) — ``SongId``
  keys, file repository, and the type ``SetlistSessionScreen.setlist``
  actually takes.

The two id spaces do not intersect, and the ONLY production editor of the V2
document is the (then unreachable) ``SetlistListScreenV2``::

    grep -rn "SongSetlist(" --include=*.dart lib   # 4 hits, one editor
    grep -rn "persistV2"    --include=*.dart lib   # 0 production callers

So the honest wiring runs through the V2 surface — which is an
``allowed_paths`` WIDENING, not a narrowing, and therefore outside a round
orchestrator's authority (ADR 0087 §2 → H3, brief-lint S15). The full
pre-flight measurement is ``.pipeline/halt-E17-R03-preflight.md``.

Same class as ``docs/LESSONS.md`` L606/L652 (a V2 store with no production
writer) and L97/L246 (the route catalogue missing from a wiring round's
list).

## The cells measure the brief against the CODE, not against a copied list

Every assertion below re-derives its expectation from the tree (the grep for
``SongSetlist`` producers, ``LearnScreen``'s constructor, the retirement
plan's own table) so a later refactor moves the guard with the code instead
of pinning a hand-typed snapshot.

## Live-tree cells state the REQUIRED END STATE (L612)

``docs/LESSONS.md`` L612, measured on E16-R02: three earlier self-heal guards
pinned the ABSENCE of the very work their round made mandatory, so the round's
SUCCESS turned its own guard red and locked it out of the merge. The two
live-tree cells here therefore assert an invariant that holds on BOTH sides of
the landing and is strictly stronger afterwards:

* the route catalogue declares either no ``/song-trainer/setlist*`` route at
  all (before) or exactly the shape §5 pins, as an ``AppRoutes`` constant
  (after);
* once ``app_router.dart`` names ``SetlistListScreenV2``, that screen must
  carry the design system — because ``test/tooling/screen_reachability_test``
  A3 turns red the moment a reachable-and-unmigrated screen has no ``E15-Rxx``
  owner row, and every E15 round is ``done`` (measured below).
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e17-r03-setlist-session-wiring.md"

LIB = REPO_ROOT / "lib"
SONG_TRAINER_SCREENS = (
    LIB / "features" / "song_trainer" / "presentation" / "screens"
)
V2_LIST_SCREEN = SONG_TRAINER_SCREENS / "setlist_list_screen_v2.dart"
V2_SESSION_SCREEN = SONG_TRAINER_SCREENS / "setlist_session_screen.dart"
LEGACY_DETAIL_SCREEN = (
    LIB / "features" / "songs" / "screens" / "setlist_detail_screen.dart"
)
LEGACY_SETLIST_MODEL = LIB / "features" / "songs" / "model" / "setlist.dart"
LEARN_SCREEN = LIB / "features" / "learn" / "screens" / "learn_screen.dart"
ROUTE_CATALOGUE = LIB / "app" / "routing" / "app_route.dart"
ROUTER = LIB / "app" / "routing" / "app_router.dart"
RETIREMENT_PLAN = REPO_ROOT / "docs" / "ui" / "retirement-plan.md"
QUEUE = REPO_ROOT / "docs" / "execution" / "pipeline-queue.tsv"

# The V2 setlist route §5.1 pins, plus every near-miss the catalogue could
# carry, so the shape check is not a substring test.
SETLIST_ROUTE = "/song-trainer/setlists"
SETLIST_ROUTE_LITERAL = re.compile(r"'(/song-trainer/setlist[^']*)'")

# `_isMigrated` in test/tooling/screen_reachability_test.dart is exactly this.
DESIGN_SYSTEM_MARKER = "design_system"
PLAN_OWNER = re.compile(r"^E15-R\d+$")


def _rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def _brief_text() -> str:
    return BRIEF.read_text(encoding="utf-8")


def _allowed_paths() -> set[str]:
    return set(load_brief_metadata(BRIEF).allowed_paths)


def _gate_tests() -> list[str]:
    return list(load_brief_metadata(BRIEF).gate_tests)


def _v2_document_producers() -> set[str]:
    """`lib/` files that CONSTRUCT a `SongSetlist` — the V2 write side."""
    producers: set[str] = set()
    for dart in sorted(LIB.rglob("*.dart")):
        if "SongSetlist(" in dart.read_text(encoding="utf-8"):
            producers.add(_rel(dart))
    return producers


def _plan_rows() -> dict[str, tuple[str, str]]:
    """`§6` table: screen path -> (verdict, owner round)."""
    rows: dict[str, tuple[str, str]] = {}
    for line in RETIREMENT_PLAN.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| `lib/"):
            continue
        cells = [cell.strip() for cell in line.split("|")[1:-1]]
        if len(cells) != 8:
            continue
        rows[cells[0].strip("`")] = (cells[4], cells[5])
    return rows


class E17R03SetlistSessionScopeTest(unittest.TestCase):
    # ------------------------------------------------------------------
    # The measured premise: two disjoint setlist worlds.
    # ------------------------------------------------------------------
    def test_the_session_screen_belongs_to_the_v2_world(self) -> None:
        session = V2_SESSION_SCREEN.read_text(encoding="utf-8")
        legacy_model = LEGACY_SETLIST_MODEL.read_text(encoding="utf-8")

        self.assertRegex(
            session,
            r"final\s+SongSetlist\s+setlist;",
            "SetlistSessionScreen takes the V2 document; if that moved, the "
            "whole premise of this guard has to be re-measured",
        )
        self.assertIn(
            "final List<String> songIds;",
            legacy_model,
            "the legacy Setlist holds song-id STRINGS (timestamp ids), not "
            "SongSetlistItems — the two id spaces do not intersect",
        )

    def test_the_v2_editor_is_in_scope(self) -> None:
        producers = _v2_document_producers()
        editor = _rel(V2_LIST_SCREEN)

        self.assertIn(
            editor,
            producers,
            "the measured V2 write side moved; re-measure before trusting "
            f"this guard (found {sorted(producers)})",
        )
        self.assertIn(
            editor,
            _allowed_paths(),
            "SetlistSessionScreen needs a real SongSetlist, and the only "
            "production editor of that document is SetlistListScreenV2 — "
            "wiring the session without it can only produce an invented "
            "setlist (L606/L652)",
        )

    def test_the_legacy_detail_screen_is_not_the_entry_point(self) -> None:
        detail = LEGACY_DETAIL_SCREEN.read_text(encoding="utf-8")

        self.assertNotIn(
            "SongSetlist",
            detail,
            "the legacy detail screen holds a legacy Setlist; if it ever "
            "learns the V2 document, re-measure this guard",
        )
        # No production caller bridges legacy -> V2, so the detail screen
        # cannot hand the session a SongSetlist at all.
        bridge_callers = [
            _rel(dart)
            for dart in sorted(LIB.rglob("*.dart"))
            if ".persistV2(" in dart.read_text(encoding="utf-8")
        ]
        self.assertEqual(
            bridge_callers,
            [],
            "a production legacy->V2 setlist bridge appeared; the brief's "
            "entry-point decision has to be re-measured",
        )
        self.assertNotIn(
            _rel(LEGACY_DETAIL_SCREEN),
            _allowed_paths(),
            "the halted brief made the legacy detail screen the entry point "
            "of a V2-only session; with two disjoint models and no "
            "production bridge that wiring cannot be honest "
            "(.pipeline/halt-E17-R03-preflight.md §2)",
        )

    # ------------------------------------------------------------------
    # The route catalogue (L97/L246).
    # ------------------------------------------------------------------
    def test_route_catalogue_and_router_are_in_scope(self) -> None:
        allowed = _allowed_paths()

        self.assertIn(
            _rel(ROUTE_CATALOGUE),
            allowed,
            "every GoRoute.path on this tree comes from an AppRoutes "
            "constant and test/tooling/route_literal_guard_test.dart forbids "
            "navigation literals, so the catalogue owner must be in scope",
        )
        self.assertIn(
            _rel(ROUTER),
            allowed,
            "the registration side must stay in scope too",
        )

    def test_route_shape_is_pinned_and_the_catalogue_agrees(self) -> None:
        self.assertIn(
            SETLIST_ROUTE,
            _brief_text(),
            "§5 must pin the V2 setlist route shape so the implementer "
            "invents nothing",
        )

        # L612 form: holds before AND after the landing, stricter afterwards.
        declared = sorted(
            set(SETLIST_ROUTE_LITERAL.findall(ROUTE_CATALOGUE.read_text("utf-8")))
        )
        self.assertIn(
            declared,
            ([], [SETLIST_ROUTE]),
            "the catalogue must declare either no setlist route (before this "
            f"round lands) or exactly {SETLIST_ROUTE!r} (after) — found "
            f"{declared}",
        )
        if declared:
            self.assertRegex(
                ROUTE_CATALOGUE.read_text("utf-8"),
                r"static\s+const\s+String\s+\w+\s*=\s*\n?\s*'"
                + re.escape(SETLIST_ROUTE)
                + r"'",
                "the landed setlist route must be an AppRoutes constant, not "
                "an inline literal",
            )

    # ------------------------------------------------------------------
    # The runner may not fabricate a result.
    # ------------------------------------------------------------------
    def test_the_legacy_learn_screen_is_not_the_runner(self) -> None:
        learn = LEARN_SCREEN.read_text(encoding="utf-8")

        # Premise: LearnScreen takes a lesson and reports NOTHING back, so a
        # SetlistItemRunner built on it would invent every SetlistItemResult.
        self.assertNotIn(
            "onCompleted",
            learn,
            "LearnScreen grew a completion callback; re-measure this guard "
            "before trusting the entry-point decision",
        )
        self.assertNotIn(
            _rel(LEARN_SCREEN),
            _allowed_paths(),
            "a runner built on LearnScreen can only fabricate "
            "SetlistItemResult values (it returns nothing)",
        )
        self.assertIn(
            "songTrainerSessionLauncherProvider",
            _brief_text(),
            "§5 must bind the runner to the ALREADY registered trainer "
            "session path, which reports a real outcome",
        )

    # ------------------------------------------------------------------
    # l10n: the generated aggregate never travels without its source (S16).
    # ------------------------------------------------------------------
    def test_l10n_source_travels_with_the_generated_aggregate(self) -> None:
        allowed = _allowed_paths()
        for locale in ("en", "hu"):
            generated = f"lib/l10n/app_{locale}.arb"
            source = f"lib/l10n/base/app_{locale}.arb"
            self.assertIn(
                generated,
                allowed,
                "the round adds user-facing strings; the generated "
                "aggregate shows up in the diff",
            )
            self.assertIn(
                source,
                allowed,
                f"{generated} is written by tool/gen_l10n_segments.dart "
                f"(ADR 0307 §4) — without {source} the round cannot add a "
                "single key (brief-lint S16, L646)",
            )

    # ------------------------------------------------------------------
    # The reachability guard's A3 cell (measured consequence of wiring).
    # ------------------------------------------------------------------
    def test_a3_consequence_is_carried_by_the_brief(self) -> None:
        plan = _plan_rows()
        row = plan.get(_rel(V2_LIST_SCREEN))

        self.assertIsNotNone(
            row,
            "the retirement plan must keep one row per measured screen",
        )
        assert row is not None
        # Measured premise: no E15 round owns this screen, and every E15
        # round is already `done` — so an owner row cannot be invented.
        self.assertFalse(
            PLAN_OWNER.fullmatch(row[1]),
            "an E15 owner appeared for SetlistListScreenV2; re-measure the "
            "A3 consequence before trusting this guard",
        )
        e15_open = [
            line.split("\t")[0]
            for line in QUEUE.read_text(encoding="utf-8").splitlines()
            if line.startswith("E15-R") and not line.rstrip().endswith("done")
        ]
        self.assertEqual(
            e15_open,
            [],
            "an E15 round is still open; then A3 could be satisfied by an "
            "owner row instead of the design-system migration",
        )

        text = _brief_text()
        self.assertIn(
            "screen_reachability_test",
            text,
            "the brief must name the guard whose A3 cell the wiring moves",
        )
        self.assertRegex(
            text,
            r"design[- ]rendszer|design_system",
            "A3 turns red on a reachable-and-unmigrated screen with no E15 "
            "owner, so the brief must require SetlistListScreenV2's "
            "design-system migration in the SAME round that wires it",
        )
        self.assertIn(
            "test/tooling/screen_reachability_test.dart",
            _gate_tests(),
            "the round has to MEASURE the A3 consequence, not assume it",
        )

    def test_a_wired_v2_list_carries_the_design_system(self) -> None:
        # L612 form: vacuous before the landing, strictly stronger after.
        if "SetlistListScreenV2" not in ROUTER.read_text(encoding="utf-8"):
            return
        self.assertIn(
            DESIGN_SYSTEM_MARKER,
            V2_LIST_SCREEN.read_text(encoding="utf-8"),
            "the router now renders SetlistListScreenV2, so the screen is "
            "reachable-and-legacy; screen_reachability_test A3 demands an "
            "E15-Rxx owner row for exactly that state, and every E15 round "
            "is done — the design-system migration is the only honest fix",
        )


if __name__ == "__main__":
    unittest.main()
