"""A §0.2 „Örökség-ellenőrzés" glob-ja MÉRVE (E06-R23 self-heal, ADR 0112, 2026-08-12).

`docs/execution/pipeline-orchestrator-prompt.md` §0.2 egy `ls -d` mintát ad a
friss orchestrátor-sessionnek, hogy megtalálja egy korábbi, halt-olt/megölt
session munkapéldányát a saját köréhez. A minta a `{{ROUND}}` (pl. `E06-R23`)
azonosítót `tr -d '-'`-vel kötőjel NÉLKÜL illesztette a globba (`e06r23`),
miközben a TÉNYLEGES munkapéldány-könyvtárnév megőrzi a kötőjelet
(`ss-sonnet-impl-e06-r23`) — a minta emiatt SOSEM talált semmit a bevett
`ss-<motor>-eXX-rYY` elnevezésen. Élesben mérve: az E06-R23 self-heal saját
könyvtára (`/home/ubuntu/ss-sonnet-impl-e06-r23`, teljes, pusholt
implementáció) a régi mintával 0 találatot adott.

Ez a teszt a SABLONBÓL kinyert, tényleges bash-sort futtatja (nem egy
kézzel másolt duplikátumot), hogy a teszt ne szakadjon el a sablon
szövegétől — ha valaki később megváltoztatja a mintát, ez a teszt azt méri,
nem egy elavult másolatot.
"""

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md"


def extract_discovery_command() -> str:
    text = TEMPLATE.read_text(encoding="utf-8")
    section = text.split("## 0.2 ", 1)[1]
    block = re.search(r"```bash\n(.*?)\n```", section, re.DOTALL)
    assert block, "nincs bash kódblokk a §0.2 szakaszban"
    first_line = block.group(1).splitlines()[0]
    assert first_line.startswith("ls -d "), f"a §0.2 első sora nem `ls -d` (talált: {first_line!r})"
    return first_line


class LegacyWorktreeDiscoveryTest(unittest.TestCase):
    def run_discovery(self, round_id: str, home: Path) -> list[str]:
        # A sablon a `/home/ubuntu/`-t szó szerint (nem `$HOME`-mal) írja elő —
        # ez a doboz konkrét elérési útja, nem a mérendő logika, ezért CSAK ezt
        # cseréljük egy elszigetelt sandboxra; a `tr`-csővezeték és a glob
        # utótag változatlanul a sablonból jön.
        command = (
            extract_discovery_command()
            .replace("{{ROUND}}", round_id)
            .replace("/home/ubuntu/", f"{home}/")
        )
        result = subprocess.run(
            ["bash", "-c", command],
            capture_output=True,
            text=True,
            timeout=10,
            env={"PATH": "/usr/bin:/bin"},
            cwd=str(home),
        )
        return [line for line in result.stdout.splitlines() if line]

    def test_finds_the_real_naming_convention_for_the_measured_round(self) -> None:
        """Mért eset: ss-sonnet-impl-e06-r23 az E06-R23 self-heal saját könyvtára."""
        with tempfile.TemporaryDirectory() as home_name:
            home = Path(home_name)
            (home / "ss-sonnet-impl-e06-r23").mkdir()
            found = self.run_discovery("E06-R23", home)
        self.assertEqual(found, [str(home / "ss-sonnet-impl-e06-r23")])

    def test_finds_the_minimax_naming_convention_too(self) -> None:
        with tempfile.TemporaryDirectory() as home_name:
            home = Path(home_name)
            (home / "ss-mm-e06-r20").mkdir()
            found = self.run_discovery("E06-R20", home)
        self.assertEqual(found, [str(home / "ss-mm-e06-r20")])

    def test_does_not_match_a_different_round_in_the_same_epic(self) -> None:
        with tempfile.TemporaryDirectory() as home_name:
            home = Path(home_name)
            (home / "ss-sonnet-impl-e06-r23").mkdir()
            (home / "ss-codex-e06-r24").mkdir()
            found = self.run_discovery("E06-R23", home)
        self.assertEqual(found, [str(home / "ss-sonnet-impl-e06-r23")])

    def test_works_for_epics_other_than_the_old_hardcoded_e02_fallback(self) -> None:
        """A régi minta második tagja (`ss-*e02*r*`) kör-független, epic-2-re
        bedrótozott literál volt — a javított PARANCSSOR már nem tartalmazza
        ezt a maradékot (a szöveges magyarázat lentebb szándékosan említi,
        mint történeti kontextust, ezért csak a futtatott sort vizsgáljuk)."""
        command = extract_discovery_command()
        self.assertNotIn("e02", command, "a régi epic-2-re bedrótozott fallback-nek el kellett tűnnie a parancsból")
        self.assertEqual(command.count("ls -d"), 1, "egyetlen ls -d hívás maradjon, nem kettő mintával")
        with tempfile.TemporaryDirectory() as home_name:
            home = Path(home_name)
            (home / "ss-sonnet-impl-e06-r23").mkdir()
            found = self.run_discovery("E06-R23", home)
        self.assertEqual(found, [str(home / "ss-sonnet-impl-e06-r23")])


if __name__ == "__main__":
    unittest.main()
