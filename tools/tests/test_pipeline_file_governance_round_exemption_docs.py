"""A governance round's OWN brief may target ADR 0087/round-pipeline.sh/etc.

Measured 2026-08-20 (E99-R19/H3, self-heal). The rotated Terra orchestrator
refused to dispatch an implementer for E99-R19 (GOV-13), whose brief
(docs/rounds/e99-r19-gov-13-chain-hygiene.md) lists `tools/round-pipeline.sh`
as the FIRST entry of its own `allowed_paths` -- the file D1/D2 are meant to
change. Terra's own words (session log
.pipeline/session-E99-R19-20260820T063619-fallback.log): "a brief D1/D2
kozvetlenul a tools/round-pipeline.sh modositasat igenyli, mikozben a jelen
session abszolut tiltott zonanak mondja ezt a fajlt. Nem inditok implementert
olyan feladatra, amelyet ez a kor szerzodese tilt."

Section 4 of docs/execution/pipeline-orchestrator-prompt.md says this session
"never modifies ADR 0087, ADR 0112, tools/round-pipeline.sh,
tools/round-gate.sh, or .github/" with no qualifier -- unlike its source,
ADR 0087 section 7, which scopes the same rule to "kor kozben" (mid-round,
i.e. an ad hoc, unplanned workaround for an obstacle the orchestrator
stumbled into). ADR 0087 section 2 also defines H3 precisely: a path OUTSIDE
the brief's own `allowed_paths`. A path the brief's authors explicitly listed
is, by that definition, never an H3 case. Five prior governance rounds
(E99-R08, E99-R14, E99-R15, E99-R16, E99-R18) already modified
`tools/round-pipeline.sh` through the standard implementer -> review -> merge
flow without tripping this halt -- proving the unqualified prompt reading is
wrong, not the brief.

This is the same failure shape as E99-R08/H3 (docs/LESSONS.md L251): a
rotated, less-experienced orchestrator engine reads absolute-sounding prose
literally and self-halts on its own sanctioned work, where Claude's
accumulated tacit history would not have. The fix there
(tools/tests/test_reviewer_scope_exemption_docs.py) was to make the
exemption explicit in the docs the orchestrator actually reads, rather than
rely on inferred context. This test applies the same remedy here.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ORCHESTRATOR_PROMPT = ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md"
ADR_0087 = ROOT / "docs" / "adr" / "0087-autonomous-round-pipeline.md"


class PipelineFileGovernanceRoundExemptionDocsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.prompt_text = ORCHESTRATOR_PROMPT.read_text(encoding="utf-8")
        self.adr_text = ADR_0087.read_text(encoding="utf-8")

    def test_prompt_section_4_scopes_the_ban_to_ad_hoc_mid_round_action(self) -> None:
        section_4 = self.prompt_text.split("## 4. Amit ez a session SOHA nem tesz", 1)[1]
        section_4 = section_4.split("## 4.1", 1)[0]
        self.assertIn("ad hoc", section_4)

    def test_prompt_section_4_names_the_governance_round_carveout(self) -> None:
        section_4 = self.prompt_text.split("## 4. Amit ez a session SOHA nem tesz", 1)[1]
        section_4 = section_4.split("## 4.1", 1)[0]
        self.assertIn("governance-kör", section_4)
        self.assertIn("allowed_paths", section_4)

    def test_prompt_section_4_cross_references_the_h3_definition(self) -> None:
        section_4 = self.prompt_text.split("## 4. Amit ez a session SOHA nem tesz", 1)[1]
        section_4 = section_4.split("## 4.1", 1)[0]
        self.assertIn("H3", section_4)
        self.assertIn("KÍVÜL", section_4)

    def test_prompt_section_4_cites_the_measured_e99_r19_incident_and_l251(self) -> None:
        section_4 = self.prompt_text.split("## 4. Amit ez a session SOHA nem tesz", 1)[1]
        section_4 = section_4.split("## 4.1", 1)[0]
        self.assertIn("E99-R19", section_4)
        self.assertIn("L251", section_4)

    def test_adr_0087_documents_the_self_heal_modification(self) -> None:
        """Normative record (ADR 0112 self-heal amendment), not just prompt prose."""
        self.assertIn("E99-R19/H3", self.adr_text)
        self.assertIn("kör közben", self.adr_text)

    def test_adr_0087_names_precedent_governance_rounds(self) -> None:
        self.assertIn("E99-R08/14/15/16/18", self.adr_text)


if __name__ == "__main__":
    unittest.main()
