"""Reviewer's own review-report artifact must never read as a scope violation.

Measured 2026-08-13 (E99-R08/H3, self-heal): the rotated Terra orchestrator
(ADR 0222/0242) halted E99-R08 with H3, reasoning that committing the
mandatory independent review report (`docs/reviews/e99-r08-*-review.md`,
AGENTS.md S15.1) would violate the brief's `allowed_paths`, since that list
does not name the report -- the standard convention across 145/149 round
briefs (docs/reviews/** is never listed; four pre-2026-08-01 briefs still do,
predating the exemption). The reasoning never ran the authoritative tool: at
the halted round's own measured coordinates (branch
sonnet-impl/e99-r08-gov-07-per-round-orchestrator-rotation, head bf413355,
base ba9b65eace338b1fbf4254dba0bb2175f5b575ec), adding
docs/reviews/e99-r08-gov-07-per-round-orchestrator-rotation-review.md --
untracked or committed -- and running

    python3 tools/scope-audit.py --repo <clone> \
        --brief docs/rounds/e99-r08-gov-07-per-round-orchestrator-rotation.md \
        --base ba9b65eace338b1fbf4254dba0bb2175f5b575ec

still prints ``Legacy scope audit OK`` with a ``generated/ignored`` count of
1: `docs/reviews` is an unconditional entry in
`tools/ai_router/security.py::GENERATED_IGNORED_PREFIXES`
(tools/tests/test_legacy_scope.py already pins that mechanism). The gap was
never the code -- it was `.claude/skills/sdd-round-review/SKILL.md` telling
the reviewer to eyeball `git diff --stat` against the brief's allowed list
with no mention of this exemption, so a careful-but-unfamiliar reviewer
engine (anyone other than Claude, which had accumulated tacit history with
this pattern) reads "anything outside the list is at least MAJOR" literally
and self-halts on its own mandated deliverable.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REVIEW_SKILL = ROOT / ".claude" / "skills" / "sdd-round-review" / "SKILL.md"
ADR_0138 = ROOT / "docs" / "adr" / "0138-factory-hardening-scope-guard-and-independence.md"


class ReviewReportScopeExemptionDocsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.skill_text = REVIEW_SKILL.read_text(encoding="utf-8")
        self.adr_text = ADR_0138.read_text(encoding="utf-8")

    def test_the_review_skill_points_at_the_authoritative_scope_tool(self) -> None:
        """A naive `git diff --stat` eyeball is what actually misled E99-R08/H3."""
        self.assertIn("tools/scope-audit.py", self.skill_text)

    def test_the_review_skill_names_the_generated_ignored_exemption(self) -> None:
        self.assertIn("GENERATED_IGNORED_PREFIXES", self.skill_text)

    def test_the_review_skill_states_its_own_report_is_never_a_violation(self) -> None:
        self.assertIn("SOHA nem sértés", self.skill_text)

    def test_adr_0138_documents_the_unconditional_exemption(self) -> None:
        """Normative record (ADR 0112 self-heal amendment), not just skill prose."""
        self.assertIn("FELTÉTEL NÉLKÜLI", self.adr_text)
        self.assertIn("E99-R08", self.adr_text)


if __name__ == "__main__":
    unittest.main()
