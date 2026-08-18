"""A Router CI path-szűrője NE maradjon le a saját mércéjéről.

MÉRT hibaosztály (2026-08-18): a `tools/mm-round.sh` és a
`docs/execution/engine-registry.tsv` szerepel a `tools/tests` csomag
állításaiban — tehát VAN rájuk guard-teszt —, de a `.github/workflows/
router-ci.yml` `paths:` szűrőjéből hiányoztak. Ezért a PR #298, amely az
implementer engedélyezett eszközlistáját és a kör időkorlátját írta át, ZÉRÓ
CI-futással ment volna a mainre. A felmérés akkor 17 ilyen fájlt talált.

A szabály, amit ez a teszt kikényszerít:

    ha a `tools/tests` csomag HIVATKOZIK egy verziókövetett `tools/` vagy
    `docs/execution/` fájlra, akkor annak a fájlnak a Router CI szűrőjében is
    szerepelnie kell

Miért ez a helyes megfogalmazás: a teszt-hivatkozás a bizonyíték arra, hogy a
fájlnak van mérhető szerződése. Ami mérhető, arra fusson is a mérés — különben
a guard-teszt csak akkor derül ki, ha valaki MÁS PR-je véletlenül elindítja.

Ha ez a teszt pirosra vált, a teendő NEM a teszt lazítása, hanem a hiányzó
útvonal felvétele a `router-ci.yml` `paths:` blokkjába.
"""

from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "router-ci.yml"
TEST_DIR = ROOT / "tools" / "tests"

# A szűrőben glob-bal fedett családok: a `*` egy útvonal-szegmensen belül.
_GLOB = re.compile(r"[*?\[]")


def filter_patterns() -> list[str]:
    """A `router-ci.yml` `paths:` blokkjának mintái."""
    text = WORKFLOW.read_text(encoding="utf-8")
    block = text.split("paths:", 1)[1].split("permissions:", 1)[0]
    return re.findall(r'^\s+- "([^"]+)"', block, re.M)


def _matches(pattern: str, path: str) -> bool:
    if pattern.endswith("/**"):
        return path.startswith(pattern[:-3] + "/")
    if _GLOB.search(pattern):
        # Egyszerű glob EGY szegmensen belül (pl. implementer-preamble*.md).
        regex = "^" + re.escape(pattern).replace(r"\*", "[^/]*").replace(r"\?", "[^/]") + "$"
        return re.match(regex, path) is not None
    return pattern == path


def covered(path: str, patterns: list[str]) -> bool:
    return any(_matches(p, path) for p in patterns)


def tracked_files() -> list[str]:
    out = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "tools", "docs/execution"],
        capture_output=True,
        text=True,
        check=True,
    )
    return out.stdout.split()


def referenced_by_tests() -> set[str]:
    """Verziókövetett fájlok, amelyek NEVE előfordul a teszt-csomag forrásában.

    A név-alapú illesztés szándékosan konzervatív: szóhatárral keresünk, hogy a
    `round-gate.sh` ne illeszkedjen egy `my-round-gate.sh` említésre.
    """
    blob = "\n".join(p.read_text(encoding="utf-8") for p in sorted(TEST_DIR.glob("*.py")))
    hits: set[str] = set()
    for relative in tracked_files():
        if relative.startswith("tools/tests/"):
            continue
        name = Path(relative).name
        if re.search(r"(?<![\w.-])" + re.escape(name) + r"(?![\w-])", blob):
            hits.add(relative)
    return hits


class RouterCiPathFilterTest(unittest.TestCase):
    def test_every_test_referenced_file_is_in_the_ci_filter(self) -> None:
        patterns = filter_patterns()
        self.assertTrue(patterns, "a router-ci.yml paths: blokkja üres vagy nem elemezhető")

        missing = sorted(p for p in referenced_by_tests() if not covered(p, patterns))
        self.assertEqual(
            missing,
            [],
            "a tools/tests csomag hivatkozik ezekre a fájlokra (tehát van rájuk "
            "guard-teszt), de a Router CI szűrője nem indul el rájuk — vedd fel "
            "őket a .github/workflows/router-ci.yml `paths:` blokkjába: "
            + ", ".join(missing),
        )

    def test_the_filter_has_no_dead_patterns(self) -> None:
        """Elgépelt útvonal = néma lyuk: a minta ott van, de sosem illeszkedik."""
        tracked = tracked_files()
        dead = []
        for pattern in filter_patterns():
            if not pattern.startswith(("tools/", "docs/execution/")):
                continue  # a `.ai/**`, `.github/**` a git ls-files hatókörén kívül van
            if not any(_matches(pattern, path) for path in tracked):
                dead.append(pattern)
        self.assertEqual(
            dead,
            [],
            "a Router CI szűrőjében olyan minta szerepel, amire EGYETLEN "
            "verziókövetett fájl sem illeszkedik (elgépelés vagy törölt fájl): "
            + ", ".join(dead),
        )


if __name__ == "__main__":
    unittest.main()
