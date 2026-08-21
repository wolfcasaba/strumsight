"""Regression guard for the E08-R17/H4 capability-axis brief repair.

Measured on stopped round commit ``a8980cab``: changing the account
capability check to ``snapshot.cloudAvailable`` still left the named A3
account test green.  Its shipping-catalog fixture made four entries eligible,
so the generator's three-item output limit hid the wrongly eligible account
quest.  The round contract must require an isolated two-entry candidate pool
for each availability axis before the product round can resume.
"""

import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs/rounds/e08-r17-daily-quest-generator.md"

EXPECTED_ALLOWED_PATHS = {
    "lib/features/gamification/application/daily_quest_generator.dart",
    "lib/features/gamification/infrastructure/default_quest_catalog.dart",
    "lib/features/gamification/public.dart",
    "test/features/gamification/application/daily_quest_generator_test.dart",
    "docs/rounds/e08-r17-daily-quest-generator.md",
}
EXPECTED_GATE_TESTS = {
    "test/features/gamification/application/daily_quest_generator_test.dart",
}


class E08R17CapabilityAxisContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = BRIEF.read_text(encoding="utf-8")
        cls.metadata = load_brief(BRIEF).metadata

    def test_heal_does_not_widen_product_scope_or_gate(self) -> None:
        self.assertEqual(set(self.metadata.allowed_paths), EXPECTED_ALLOWED_PATHS)
        self.assertEqual(set(self.metadata.gate_tests), EXPECTED_GATE_TESTS)

    def test_revision_records_the_measured_truncation_mask(self) -> None:
        self.assertIn("0.0.1 H4", self.text)
        self.assertIn("account → cloud", self.text)
        self.assertIn("max-3", self.text)
        self.assertIn("hibásan ZÖLD", self.text)

    def test_each_axis_requires_an_isolated_two_entry_candidate_pool(self) -> None:
        self.assertIn("pontosan két entry", self.text)
        for capability in ("camera", "account", "cloud"):
            with self.subTest(capability=capability):
                self.assertIn(f"local short + `{capability}`", self.text)

    def test_all_measured_axis_mutations_must_be_killed(self) -> None:
        for mutation in (
            "camera → account",
            "account → cloud",
            "cloud → camera",
        ):
            with self.subTest(mutation=mutation):
                self.assertRegex(
                    self.text,
                    rf"{mutation}[^\n]*PIROS",
                )

    def test_shipping_catalog_contract_remains_a_separate_cell(self) -> None:
        self.assertIn("shipping default katalógus", self.text)
        self.assertIn("külön contract-cella", self.text)


if __name__ == "__main__":
    unittest.main()
