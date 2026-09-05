"""Regressziós teszt: tools/codex-round.sh és tools/mm-round.sh önjavítása a
gitignore-olt generált Flutter/l10n előfeltételre (self-heal E08-R03/H6).

MÉRT gyökérok (2026-08-19, .pipeline/session-E08-R03-20260819T212506.log +
/tmp/codex-e08-r03.log): az orchesztrátor a `/home/ubuntu/ss-codex-e08-r03`
klónt helyesen előkészítette (`tools/prepare-flutter-generated.sh` lefutott,
`lib/l10n/app_localizations*.dart` létrejött — saját méréssel igazolva). A
TÉNYLEGES Codex-dispatch viszont a `/home/ubuntu/ss-codex-e08-r03-impl`
WORKTREE-be ment (`git -C ss-codex-e08-r03 worktree list` a `-impl` utat
worktree-ként, nem klónként listázta; `.codex-round-status`: `head=63e9bf9e`,
ugyanaz, mint a worktree HEAD-je). A gitignore-olt generált kimenet
worktree-k közt NEM öröklődik — a `-impl` worktree `lib/l10n/`-jában csak a
két `.arb` forrás volt, a generált `app_localizations*.dart` hiányzott, noha
`.dart_tool/` (tehát valamilyen `pub get`) már lefutott ott. A round-gate
`flutter analyze`-je emiatt 1071 hamis hibával blokkolt; az implementer
helyesen `blocked`-ot jelzett, mert a `tools/prepare-flutter-generated.sh`
hívása a saját tiltott zónáján (tools/**) kívül esett.

A `.claude/skills/sdd-round-driver/SKILL.md` §3 ezt eddig PRÓZÁBAN írta elő
az orchesztrátornak — és ez már a NEGYEDIK mérés ugyanerre a hibaosztályra
(korábbi: L222/E06-R07, L228/E06-R10, L230/E06-R11). A workflow-szövegbe
ágyazott emlékeztető ÖNMAGÁBAN nem tartott, mert a tényleges dispatch-cél
(worktree) eltért attól, amit az orchesztrátor előkészített (klón) — egy
prózai lépés nem védi meg a folyamatot egy MÁSIK könyvtárra mutató
végrehajtási hibától. A javítás ezért a mechanikus legalsó rétegbe kerül: a
burkoló (`codex-round.sh`/`mm-round.sh`) MOST MÁR a SAJÁT workdirjét
készíti elő, közvetlenül az engine-dispatch előtt — függetlenül attól, mit
tett (vagy felejtett el) az orchesztrátor, és függetlenül attól, hogy a
workdir klón vagy worktree.

Hamis `codex`/`claude`/`flutter` binárisokkal fut, hálózat és modellhívás
nélkül; a `flutter`-t meghívó lépés a VALÓDI `tools/prepare-flutter-
generated.sh` másolatán át íródik (nem kitalált fixture), a worktree-fixture
pedig szó szerint reprodukálja a mért `ss-codex-e08-r03` → `ss-codex-e08-r03-
impl` alakot (előkészített forrás-klón + belőle nyitott, előkészítetlen
worktree).
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CODEX_WRAPPER = ROOT / "tools" / "codex-round.sh"
MM_WRAPPER = ROOT / "tools" / "mm-round.sh"
PREPARE_SCRIPT = ROOT / "tools" / "prepare-flutter-generated.sh"

SESSION_ID = "019fd369-a3ab-7713-9750-960f66886400"

FAKE_CODEX = """#!/usr/bin/env bash
set -uo pipefail
printf 'CODEX_CALL\\n' >> "$EVENTS_LOG"
printf 'OpenAI Codex v0.146.0\\n--------\\nsession id: %s\\n--------\\n' "$FAKE_SESSION"
printf 'munka\\n' >> "$FAKE_WORKFILE"
printf 'status=done\\nsummary=kesz\\n' > "$FAKE_SIGNAL"
exit 0
"""

FAKE_CLAUDE = """#!/usr/bin/env bash
set -uo pipefail
printf 'CLAUDE_CALL\\n' >> "$EVENTS_LOG"
printf '{\\"type\\":\\"result\\",\\"subtype\\":\\"success\\",\\"result\\":\\"ok\\"}\\n'
printf 'munka\\n' >> "$FAKE_WORKFILE"
printf 'status=done\\nsummary=kesz\\n' > "$FAKE_SIGNAL"
exit 0
"""

FAKE_FLUTTER = """#!/usr/bin/env bash
set -uo pipefail
{
  printf 'FLUTTER_CALL'
  for argument in "$@"; do printf '\\t%s' "$argument"; done
  printf '\\n'
} >> "$EVENTS_LOG"
if [ "${1:-}" = "gen-l10n" ]; then
  mkdir -p lib/l10n
  printf '// generated\\n' > lib/l10n/app_localizations.dart
fi
exit 0
"""


def write_executable(path: Path, body: str) -> Path:
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)
    return path


def git(*arguments, cwd):
    return subprocess.run(
        ["git", *arguments], cwd=cwd, capture_output=True, text=True, check=True
    )


def seed_flutter_source_tree(repo: Path) -> None:
    """A mért forma: pubspec.yaml + l10n.yaml + ARB forrás, és a VALÓDI
    prepare-flutter-generated.sh saját másolata. A script a repo_root-ot a
    BASH_SOURCE saját útvonalából számolja (L232/E06-R13) — ezért minden
    munkapéldánynak (klónnak ÉS worktree-nek) saját másolat kell."""
    (repo / "tools").mkdir(parents=True, exist_ok=True)
    write_executable(
        repo / "tools" / "prepare-flutter-generated.sh",
        PREPARE_SCRIPT.read_text(encoding="utf-8"),
    )
    (repo / "pubspec.yaml").write_text("name: sandbox\n", encoding="utf-8")
    (repo / "l10n.yaml").write_text("arb-dir: lib/l10n\n", encoding="utf-8")
    (repo / "lib" / "l10n").mkdir(parents=True, exist_ok=True)
    (repo / "lib" / "l10n" / "app_en.arb").write_text("{}\n", encoding="utf-8")


class CodexRoundWorktreePrerequisiteTest(unittest.TestCase):
    """A mért eset szó szerinti alakja: a dispatch-cél egy WORKTREE egy
    másik, már előkészített klónról."""

    def _make_worktree_fixture(self, base: Path) -> Path:
        source = base / "ss-codex-e08-r03"
        source.mkdir()
        git("init", "-q", cwd=source)
        git("config", "user.email", "t@example.com", cwd=source)
        git("config", "user.name", "T", cwd=source)
        seed_flutter_source_tree(source)
        git("add", "-A", cwd=source)
        git("commit", "-q", "-m", "seed", cwd=source)

        impl = base / "ss-codex-e08-r03-impl"
        git("worktree", "add", "-q", "-b", "codex/e08-r03-test", str(impl), cwd=source)
        return impl

    def test_codex_round_generates_l10n_inside_the_dispatched_worktree_before_calling_the_engine(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as name:
            base = Path(name)
            impl = self._make_worktree_fixture(base)

            prompt = base / "prompt.md"
            prompt.write_text("feladat\n", encoding="utf-8")
            log = base / "round.log"
            events_log = base / "events.log"
            events_log.touch()
            fake_flutter = write_executable(base / "fake-flutter", FAKE_FLUTTER)
            fake_codex = write_executable(base / "fake-codex", FAKE_CODEX)

            environment = dict(os.environ)
            environment.update(
                {
                    "ROUND_ENGINE": "terra",
                    "CODEX_BIN": str(fake_codex),
                    "FLUTTER_BIN": str(fake_flutter),
                    "EVENTS_LOG": str(events_log),
                    "FAKE_SIGNAL": str(impl / ".codex-round-status"),
                    "FAKE_WORKFILE": str(impl / "munka.txt"),
                    "FAKE_SESSION": SESSION_ID,
                    "CODEX_POLL_SECONDS": "1",
                }
            )
            environment.pop("ROUND_BRIEF", None)

            result = subprocess.run(
                ["bash", str(CODEX_WRAPPER), str(impl), str(prompt), str(log)],
                capture_output=True,
                text=True,
                env=environment,
                cwd=str(ROOT),
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

            lines = events_log.read_text(encoding="utf-8").splitlines()
            self.assertIn("FLUTTER_CALL\tpub\tget", lines, lines)
            self.assertIn("FLUTTER_CALL\tgen-l10n", lines, lines)
            self.assertIn("CODEX_CALL", lines, lines)
            self.assertLess(
                lines.index("FLUTTER_CALL\tgen-l10n"),
                lines.index("CODEX_CALL"),
                "az l10n-előfeltételnek a motor-dispatch ELŐTT kell lefutnia, "
                f"nem utána vagy helyette: {lines}",
            )
            self.assertTrue(
                (impl / "lib" / "l10n" / "app_localizations.dart").exists(),
                "a WORKTREE saját másolatában kell létrejönnie, nem csak a "
                "forrás-klónban — a gitignore-olt kimenet worktree-k közt "
                "nem öröklődik",
            )


class MmRoundClonePrerequisiteTest(unittest.TestCase):
    """mm-round.sh a nem-könyvtár .git-et (worktree) elutasítja (54-57. sor)
    — ez a sáv a KLÓN esetét méri ugyanazzal az önjavítással, a claude-
    harness oldalon."""

    def test_mm_round_generates_l10n_before_calling_the_engine(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            base = Path(name)
            workdir = base / "work"
            workdir.mkdir()
            git("init", "-q", cwd=workdir)
            git("config", "user.email", "t@example.com", cwd=workdir)
            git("config", "user.name", "T", cwd=workdir)
            seed_flutter_source_tree(workdir)
            git("add", "-A", cwd=workdir)
            git("commit", "-q", "-m", "seed", cwd=workdir)

            prompt = base / "prompt.md"
            prompt.write_text("feladat\n", encoding="utf-8")
            log = base / "round.log"
            events_log = base / "events.log"
            events_log.touch()
            fake_flutter = write_executable(base / "fake-flutter", FAKE_FLUTTER)
            fake_claude = write_executable(base / "fake-claude", FAKE_CLAUDE)

            environment = dict(os.environ)
            environment.update(
                {
                    "ROUND_ENGINE": "sonnet-impl",
                    "CLAUDE_BIN": str(fake_claude),
                    "FLUTTER_BIN": str(fake_flutter),
                    "EVENTS_LOG": str(events_log),
                    "FAKE_SIGNAL": str(workdir / ".codex-round-status"),
                    "FAKE_WORKFILE": str(workdir / "munka.txt"),
                    "MM_POLL_SECONDS": "1",
                    # Hamis, azonnal kilépő `claude` — az éles 5 mp-es
                    # SIGTERM→SIGKILL türelem itt tiszta fali óra
                    # (E14-R13/H5 önjavító kör, 2026-09-05).
                    "MM_KILL_GRACE_SECONDS": "1",
                }
            )
            environment.pop("ROUND_BRIEF", None)

            result = subprocess.run(
                ["bash", str(MM_WRAPPER), str(workdir), str(prompt), str(log)],
                capture_output=True,
                text=True,
                env=environment,
                cwd=str(ROOT),
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

            lines = events_log.read_text(encoding="utf-8").splitlines()
            self.assertIn("FLUTTER_CALL\tpub\tget", lines, lines)
            self.assertIn("FLUTTER_CALL\tgen-l10n", lines, lines)
            self.assertIn("CLAUDE_CALL", lines, lines)
            self.assertLess(
                lines.index("FLUTTER_CALL\tgen-l10n"),
                lines.index("CLAUDE_CALL"),
                f"az l10n-előfeltételnek a motor-dispatch ELŐTT kell lefutnia: {lines}",
            )
            self.assertTrue(
                (workdir / "lib" / "l10n" / "app_localizations.dart").exists()
            )


if __name__ == "__main__":
    unittest.main()
