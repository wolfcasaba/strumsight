"""Minden brief-lint szabálynak van szerződés-sora az orchestrátor-promptban.

MÉRT rés (2026-09-03): a `tools/brief-lint.py` az `S1`–`S14` szabályokat
implementálta, a `docs/execution/pipeline-orchestrator-prompt.md` §1.0
táblája viszont **csak az S1–S4-et** dokumentálta. Tíz szabály úgy tüzelt,
hogy az orchestrátor semmilyen szerződést nem kapott rájuk — miközben a
prompt saját mondata szerint a strict lelet „nem hagyható ki".

Ez ugyanaz a hibaosztály, amit az L593 mért kódszinten: egy szabály, ami
FUT, de amire nincs kimondott elvárás, a gyakorlatban nem él. A parancsolat
egyszerű: aki új lint-szabályt vezet be, a táblát is bővíti.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LINT = ROOT / "tools" / "brief-lint.py"
PROMPT = ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md"

RULE_IN_CODE = re.compile(r'"(S\d+)"')
RULE_IN_TABLE = re.compile(r"^\|\s*`(S\d+)`\s*\|", re.MULTILINE)


def implemented_rules() -> set[str]:
    return set(RULE_IN_CODE.findall(LINT.read_text(encoding="utf-8")))


def documented_rules() -> set[str]:
    return set(RULE_IN_TABLE.findall(PROMPT.read_text(encoding="utf-8")))


class LintRuleContractParityTest(unittest.TestCase):
    def test_every_implemented_strict_rule_has_a_contract_row(self) -> None:
        missing = sorted(implemented_rules() - documented_rules(), key=lambda r: int(r[1:]))
        self.assertEqual(
            missing,
            [],
            "ezek a lint-szabályok tüzelnek, de nincs soruk a pipeline-orchestrator-prompt.md "
            f"§1.0 táblájában, tehát az orchestrátor nem kap rájuk elvárást: {missing}",
        )

    def test_the_table_does_not_promise_rules_that_do_not_exist(self) -> None:
        phantom = sorted(documented_rules() - implemented_rules(), key=lambda r: int(r[1:]))
        self.assertEqual(
            phantom,
            [],
            f"a tábla olyan szabályt ígér, amit a brief-lint nem implementál: {phantom}",
        )

    def test_the_rule_set_is_not_empty(self) -> None:
        """Néma-mód elleni őr: egy elrontott regex mindkét halmazt üresre vinné."""
        self.assertGreaterEqual(len(implemented_rules()), 14)
        self.assertGreaterEqual(len(documented_rules()), 14)


if __name__ == "__main__":
    unittest.main()
