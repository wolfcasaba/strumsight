"""Az `S12` szabály — a §7 gate-parancs tükrözze a `gate_tests` metaadatot.

MÉRT ok, SAJÁT HIBÁBÓL (2026-08-25). Az `S11` sáv-szintű eltakarítása a hat
Ch13-brief `gate_tests` metaadatát bővítette a hiányzó őrökkel — a §7-ben
ténylegesen FUTTATOTT `tools/round-gate.sh` parancssort viszont nem. A briefek
így olyan kaput ígértek, amit a kör sosem futtatott volna; a hiba csak azért
derült ki, mert a következő lépés előtt kimértem a korpuszt.

A szétcsúszás NÉMA, és ez a lényeg: a `gate_tests` metaadatot a `scope-audit`
és a `round-ci-plan` olvassa, a kaput viszont a **parancssor** futtatja
(`AGENTS.md` §12: a mérce egyetlen futtatható artefaktum). Semmi nem hozta
össze a kettőt — ezért gépi őr kell rá, nem fegyelem.

A korpuszon mérve (`main @ d32f11bd` + a Ch13 sáv eltakarítása után): 26 lelet,
ebből **0 `done` (merge-elt) kör** — 18 `prepared`, 7 `hold` és 1 `pending`
(az éppen FUTÓ E13-R18, amelynek a briefjét szándékosan nem mozgattuk kör
közben). A szabály `strict`, a CI-kapu pedig `--level base`, tehát ez sosem
vált pirosra egy lezárt kört.
"""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
BRIEF_NAME = "e13-r19-tuner-and-metronome-ui.md"
OWN_TEST = "test/features/tuner/tuner_ui_mapping_test.dart"
TREE_GUARD = "test/core/architecture_dependency_test.dart"


def _load_brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", TOOLS / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


brief_lint = _load_brief_lint()


def _make_repo(directory: Path, *, status: str = "pending") -> Path:
    (directory / "docs" / "rounds").mkdir(parents=True, exist_ok=True)
    (directory / "docs" / "execution").mkdir(parents=True, exist_ok=True)
    (directory / ".ai").mkdir(parents=True, exist_ok=True)
    (directory / ".ai" / "router.toml").write_text(
        '[security]\nhigh_risk_path_fragments = ["auth"]\n', encoding="utf-8"
    )
    for relative in (OWN_TEST, TREE_GUARD):
        path = directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("void main() {}\n", encoding="utf-8")
    (directory / "docs" / "execution" / "pipeline-queue.tsv").write_text(
        f"E13-R19\tdocs/rounds/{BRIEF_NAME}\tsonnet-impl\tnincs\t{status}\n", encoding="utf-8"
    )
    return directory


def _brief_text(*, gate_tests, command_tests) -> str:
    gates = "[" + ", ".join(f'"{gate}"' for gate in gate_tests) + "]"
    command = "tools/round-gate.sh " + " ".join(command_tests)
    return f"""# E13-R19 — Tuner és metronóm UI

**STOP-protokoll:** scope-ütközésnél állj meg.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/tuner/",
  "{OWN_TEST}",
  "docs/rounds/{BRIEF_NAME}",
]
gate_tests = {gates}
native_gate = false
```

## 7. A mérce

```bash
{command}
```

## 9. Kör-jelzés

`done` csak review + CI + merge után.
"""


def _lint(repo: Path, text: str):
    path = repo / "docs" / "rounds" / BRIEF_NAME
    path.write_text(text, encoding="utf-8")
    return brief_lint.lint_text(text, path=path, repo=repo)


def _codes(findings) -> set[str]:
    return {item["code"] for item in findings}


def _message(findings, code: str) -> str:
    return next(item["message"] for item in findings if item["code"] == code)


class BriefGateCommandMirrorsGateTestsTest(unittest.TestCase):
    def _repo(self, **kwargs) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        return _make_repo(Path(temporary.name), **kwargs)

    def test_a_gate_test_missing_from_the_command_is_a_finding(self) -> None:
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(gate_tests=(OWN_TEST, TREE_GUARD), command_tests=(OWN_TEST,)),
        )
        self.assertIn(
            "S12",
            _codes(findings),
            "a §7 parancsból hiányzó gate_test némán maradt — a brief olyan "
            "mércét ígér, amit a kör sosem futtat",
        )
        message = _message(findings, "S12")
        self.assertIn(TREE_GUARD, message)
        self.assertNotIn(OWN_TEST, message, "a parancsban SZEREPLŐ teszt nem lelet")

    def test_a_mirroring_command_clears_the_finding(self) -> None:
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                gate_tests=(OWN_TEST, TREE_GUARD), command_tests=(OWN_TEST, TREE_GUARD)
            ),
        )
        self.assertNotIn("S12", _codes(findings))

    def test_a_done_round_is_never_flagged_retroactively(self) -> None:
        repo = self._repo(status="done")
        findings = _lint(
            repo,
            _brief_text(gate_tests=(OWN_TEST, TREE_GUARD), command_tests=(OWN_TEST,)),
        )
        self.assertNotIn("S12", _codes(findings))


if __name__ == "__main__":
    unittest.main()
