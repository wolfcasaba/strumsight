"""Regression guard for E16-R02 / H3, 2nd pre-flight (ADR 0112, 2026-09-03).

Measured on ``main @ 18a649ec`` — the round's SECOND pre-flight halted because
the brief prescribes a NEW skill-detail route (§3 scope, cell A2) while the
owner of the route catalogue was not on ``allowed_paths``::

    grep -n "skill" lib/app/routing/app_route.dart          # -> 0 constants
    grep -c "path: '" lib/app/routing/app_router.dart       # -> 0 inline literals
    grep -rn "SkillDetailScreen" --include=*.dart lib       # -> only its own file

Every ``GoRoute.path`` on the tree comes from an ``AppRoutes`` constant, and
``test/tooling/route_literal_guard_test.dart`` forbids navigation literals, so
A2 is unreachable without ``lib/app/routing/app_route.dart``. This is the same
class as ``lessons/L97`` (E03-R17: router wiring allowed, catalogue not) and
``lessons/L246`` (E06-R23: missing owner file -> out-of-list write). The
immediately preceding round of the same chapter (E16-R01) had the catalogue on
its list and added ``levelDetail`` exactly this way.

The same halt measured four more brief defects that the same revision fixes;
each assertion below cross-checks the brief against the CODE it will run on,
not against a hand-copied expectation:

* §5.4 milestone ids ran against ``MasteryMilestone``'s own stable-id regex
  (``mastery.chordTransition.v1`` would throw ``ArgumentError`` at runtime);
* the catalogue cannot be ``const`` — ``MasteryMilestone``'s public surface is
  a factory, the ``const`` constructor is private;
* ``MasteryMilestone.difficulty`` is required AND
  ``mastery_evaluator.dart:108`` drops evidence whose difficulty differs, so
  the §5.4 table has to pin it or cell A10 is underspecified;
* the §4 ``practice/public.dart`` export permission has to name every type the
  §5.5 adapter must mention, because ``tool/check_architecture.dart`` only
  accepts cross-feature imports through the barrel.

This guard is red on the pre-revision brief.

## The two live-tree cells were REWRITTEN, not deleted (2026-09-03)

ADR 0112 self-heal round, E16-R02 / 4th H3. Two cells measured the tree with
``assertNotIn`` — they pinned the ABSENCE of work this round's own brief makes
MANDATORY (§5.8 the route constant, §0.0.I/I5 the barrel exports). The round
therefore turned its own guard red by SUCCEEDING: targeted gate 21/21 green,
Full Gate green on ``c2b1362a``, yet ``router-ci`` red on every SHA
(``.pipeline/halt-detail-E16-R02.md``). Both cells said so themselves — *"if it
lands outside this round, this guard must be rewritten, not deleted"* and
*"this guard's premise moved; re-measure instead of relaxing it"*.

Both now measure an invariant that holds on BOTH sides of the landing and is
strictly stronger afterwards: the catalogue declares the pinned route shape or
no skill-detail route at all (a typo or a competing variant is red), and the
practice barrel exports the whole §5.5 adapter surface or none of it (a
half-landed export is red). The general lesson is ``docs/LESSONS.md`` L612.
"""

import re
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = (
    REPO_ROOT
    / "docs"
    / "rounds"
    / "e16-r02-progress-projection-and-router-placeholders.md"
)
ROUTE_CATALOGUE = REPO_ROOT / "lib" / "app" / "routing" / "app_route.dart"
MILESTONE = (
    REPO_ROOT
    / "lib"
    / "features"
    / "gamification"
    / "domain"
    / "mastery"
    / "mastery_milestone.dart"
)
PRACTICE_BARREL = REPO_ROOT / "lib" / "features" / "practice" / "public.dart"

# The §5.4 table rows: `| <id> | <skill> | ...`
MILESTONE_ROW = re.compile(r"^\|\s*`(mastery[A-Za-z0-9_.]*)`\s*\|", re.MULTILINE)
# The types the §5.5 adapter has to be able to name across the feature border.
ADAPTER_TYPES = (
    "PracticeHistoryEntry",
    "PracticeMetricSnapshot",
    "PracticeMetricDimension",
)

# The SDD UI-50 route shape §5 pins, and every skill-detail literal the
# catalogue could carry — a near-miss (`:skill`, `/skill/`, a trailing segment)
# has to be visible, otherwise the shape check would be a substring test.
SKILL_DETAIL_ROUTE = "/profile/progress/skills/:skillId"
SKILL_DETAIL_LITERAL = re.compile(r"'(/profile/progress/skill[^']*)'")


def _brief_text() -> str:
    return BRIEF.read_text(encoding="utf-8")


def _catalogue_text() -> str:
    return ROUTE_CATALOGUE.read_text(encoding="utf-8")


def _stable_id_regex() -> re.Pattern[str]:
    """The regex ``MasteryMilestone`` itself enforces on an id."""
    source = MILESTONE.read_text(encoding="utf-8")
    match = re.search(r"RegExp\(r'(\^\[a-z\][^']*)'\)", source)
    assert match is not None, "the stable-id regex moved in mastery_milestone.dart"
    return re.compile(match.group(1))


class E16R02RouteCatalogScopeTest(unittest.TestCase):
    def test_brief_owns_the_route_catalogue(self) -> None:
        allowed = set(load_brief_metadata(BRIEF).allowed_paths)

        self.assertIn(
            "lib/app/routing/app_route.dart",
            allowed,
            "cell A2 prescribes a NEW skill-detail route; every GoRoute.path "
            "on the tree is an AppRoutes constant and route literals are "
            "forbidden, so the catalogue owner must be in scope (L97/L246)",
        )
        self.assertIn(
            "lib/app/routing/app_router.dart",
            allowed,
            "the wiring side must stay in scope too",
        )

    def test_route_catalogue_permission_is_additive_only(self) -> None:
        text = _brief_text()

        self.assertIn(
            "lib/app/routing/app_route.dart",
            text.split("## 4.", 1)[1] if "## 4." in text else "",
            "the §4 allowed-files table must carry the catalogue with its "
            "narrow reason, not only the ai-router block",
        )
        self.assertRegex(
            text,
            r"app_route\.dart`?\s*\|[^|\n]*(KIZÁRÓLAG|kizárólag)",
            "the §4 row must limit the permission to ADDING the new "
            "constant — rewriting or deleting an existing one is forbidden",
        )

    def test_new_route_shape_is_pinned_and_matches_the_sdd(self) -> None:
        text = _brief_text()

        self.assertIn(
            SKILL_DETAIL_ROUTE,
            text,
            "§5 must pin the route shape (the SDD UI-50 route, also named in "
            "skill_detail_screen.dart:15) so the implementer invents nothing",
        )

        # REWRITTEN, not deleted (ADR 0112 self-heal round, 4th H3, 2026-09-03).
        # The original cell asserted the constant was ABSENT from the catalogue
        # — i.e. it pinned the ABSENCE of the very work §5.8 makes MANDATORY for
        # this round, so the round's SUCCESS turned it red and its own guard
        # locked it out of the merge (`.pipeline/halt-detail-E16-R02.md`).
        # The invariant that holds on BOTH sides of the landing, and is strictly
        # stronger afterwards: whatever skill-detail route the catalogue
        # declares must be EXACTLY the shape §5 pins. A typo, a renamed
        # parameter or a second competing variant is red.
        catalogue = _catalogue_text()
        declared = sorted(set(SKILL_DETAIL_LITERAL.findall(catalogue)))

        self.assertIn(
            declared,
            ([], [SKILL_DETAIL_ROUTE]),
            "the catalogue must declare either no skill-detail route (before "
            f"this round lands) or exactly {SKILL_DETAIL_ROUTE!r} (after) — "
            f"found {declared}",
        )

        if not declared:
            return

        # A2's premise is that every `GoRoute.path` comes from an `AppRoutes`
        # constant (`test/tooling/route_literal_guard_test.dart` forbids
        # navigation literals). Once the route lands, that is the measure.
        self.assertRegex(
            catalogue,
            r"static\s+const\s+String\s+\w+\s*=\s*\n?\s*'"
            + re.escape(SKILL_DETAIL_ROUTE)
            + r"'",
            "the landed skill-detail route must be an AppRoutes constant, not "
            "an inline literal",
        )

    def test_milestone_ids_satisfy_the_domain_regex(self) -> None:
        pattern = _stable_id_regex()
        ids = MILESTONE_ROW.findall(_brief_text())

        self.assertEqual(
            len(ids),
            3,
            f"the §5.4 table must pin exactly three v1 milestones, found {ids}",
        )
        for milestone_id in ids:
            self.assertRegex(
                milestone_id,
                pattern,
                f"MasteryMilestone rejects {milestone_id!r} at runtime "
                "(_requireStableId, mastery_milestone.dart)",
            )

    def test_catalog_is_not_prescribed_const(self) -> None:
        text = _brief_text()

        self.assertNotIn(
            "const List<MasteryMilestone>",
            text,
            "MasteryMilestone's public constructor is a factory (the const "
            "one is private) — a const catalogue is unbuildable",
        )
        self.assertIn(
            "List.unmodifiable",
            text,
            "the §5.4 catalogue shape must be pinned to the buildable one",
        )

    def test_difficulty_is_pinned_for_the_v1_milestones(self) -> None:
        text = _brief_text()

        self.assertIn(
            "MasteryDifficulty.beginner",
            text,
            "mastery_evaluator.dart drops evidence whose difficulty differs "
            "from the milestone's, so the §5.4 table must pin it — without "
            "it cell A10 is green on any fixture the implementer picks",
        )
        self.assertIn(
            "difficulty",
            text.split("### 5.4", 1)[1].split("### 5.5", 1)[0],
            "the §5.4 table needs its own difficulty column",
        )

    def test_practice_barrel_permission_covers_every_adapter_type(self) -> None:
        barrel = PRACTICE_BARREL.read_text(encoding="utf-8")
        text = _brief_text()
        table = text.split("## 4.", 1)[1].split("## 5.", 1)[0]

        for type_name in ADAPTER_TYPES:
            self.assertIn(
                type_name,
                table,
                f"the §5.5 adapter must name {type_name} across the feature "
                "border, and check_architecture.dart only allows that "
                "through public.dart — the §4 row must permit the export",
            )

        # REWRITTEN, not relaxed (ADR 0112 self-heal round, 4th H3,
        # 2026-09-03). The original cell asserted every type was ABSENT from the
        # barrel — the ABSENCE of the export §0.0.I/I5 makes MANDATORY for this
        # round, so the round's SUCCESS turned it red
        # (`.pipeline/halt-detail-E16-R02.md`). The invariant that holds on both
        # sides of the landing: the §5.5 adapter needs the WHOLE set across the
        # feature border, so the barrel exports all three or none. A partial
        # export is a half-landed round — the adapter cannot compile — and that
        # is exactly what this cell now catches.
        exported = sorted(name for name in ADAPTER_TYPES if name in barrel)

        self.assertIn(
            exported,
            ([], sorted(ADAPTER_TYPES)),
            "practice/public.dart must export either none of the §5.5 adapter "
            "types (before this round lands) or all of them (after) — found "
            f"{exported}",
        )

    def test_header_adr_matches_the_reservation(self) -> None:
        text = _brief_text()

        self.assertNotIn(
            "ADR 0491",
            text,
            "0491 is a merged decision "
            "(docs/adr/0491-practice-generator-entry-point-and-rollout.md); "
            "the reservation gave this round 0500 (L603)",
        )
        self.assertIn(
            "0500",
            text,
            "the brief must carry the reserved ADR number",
        )


if __name__ == "__main__":
    unittest.main()
