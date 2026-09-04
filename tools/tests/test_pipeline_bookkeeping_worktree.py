"""E14-R07 / H3 önjavító kör (ADR 0112, 2026-09-04) — regressziós őr.

MÉRT GYÖKÉROK. A merge utáni könyvelés (a sor-fájl `pending → done` fail-safe-je
+ a belőle származtatott completion-matrix) a KÖZÖS munkafában futott,
`git reset --hard origin/main` + `git push origin main` párossal. A kétslotos
lánc mellett viszont a közös fa nem feltétlenül a `main`-en áll, amikor egy kör
merge-el.

2026-09-04T09:43:17-kor (az E14-R06 merge-e) a másik slot köre (E14-R04) a közös
fát 09:09:02 óta a SAJÁT ágán tartotta, ezért egyszerre három dolog romlott el:

1. a `git reset --hard origin/main` az IDEGEN ágat mozdította el — az E14-R04
   lokális pre-flight commitja (`94f46951`) leesett róla;
2. a `chore(pipeline)` commit (`2cd3baef`) is arra az ágra került, nem a
   `main`-re;
3. a `git push -q origin main` a két committal LEMARADT lokális `main` refet
   tolta → non-fast-forward, és a kudarcot egyetlen néma sor jelezte:
   `FIGYELEM: a sor-fájl push-a nem ment át` (`.pipeline/chain.log:26359`).

Következmény: a `main` drifttel maradt (`tools/sync-completion-matrix.py
--check` → exit 1, „Ch14 (E14): reports done=3, queue measures done=4"), a
`test/tooling/program_completion_test.dart` A1 cellája pirosra vitte a main
gate-jét (run 33859597093), és a KÖVETKEZŐ kör (E14-R07) merge-kapuja állt meg
(H3) — pedig annak saját munkája zöld és review-APPROVED volt.

A mérce NEM lazult: az A1 szigorú egyenlősége és a D2 fail-safe kar változatlan.
Ami megváltozott, az a VÉGREHAJTÁS HELYE és a kudarc láthatósága — a könyvelés
saját, eldobható worktree-ben fut, minden próbálkozás a FRISS `origin/main`-ből
származtat újra, a push újrapróbálható, a végleges kudarc pedig hangos.

A fixture a MÉRT adatot használja: a valódi Ch14-sor (`done=3 | pending=16`) és
a valódi E14 queue-alak (19 sor, az E14-R06 flip után 4 done / 15 pending).
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIPELINE = ROOT / "tools" / "round-pipeline.sh"
SYNC_SCRIPT = ROOT / "tools" / "sync-completion-matrix.py"

QUEUE_REL = "docs/execution/pipeline-queue.tsv"
REPORT_REL = "docs/sdd/program-completion-report.md"
ROUND_BRANCH = "sonnet-impl/e14-r04-recognition-frame-v2-contract"

# A mért E14 queue-alak: R01–R03 `done`, R04–R19 `pending`. Az E14-R06 flip
# után 4 done / 15 pending — pontosan az a két szám, amit a piros CI mért.
QUEUE = "\n".join(
    ["# round\tbrief\tengine\tadr\tstatus"]
    + [
        f"E14-R{n:02d}\tdocs/rounds/e14-r{n:02d}.md\tsonnet-impl\t03{n:02d}\t"
        + ("done" if n <= 3 else "pending")
        for n in range(1, 20)
    ]
) + "\n"

# A riport §3 matrixának VALÓDI, drift-ben ragadt Ch14-sora.
REPORT = """# Fixture report

## 3. Completion matrix

| Sáv | Fejezet / cím | Queue-előtag | done | pending | prepared | hold | Riport-státusz | Bizonyíték |
|---|---|---|---:|---:|---:|---:|---|---|
| Ch13 | UI/UX Design System | E13 | 0 | 0 | 0 | 0 | queue-szinten lezárva | — |
| Ch14 | Recognition Accuracy & Useful UI Recovery | E14 | 3 | 16 | 0 | 0 | nyitva (prepared: R02–R19 megírva) | — |

## 4. Utána
"""


def _git(*args: str, cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args], cwd=str(cwd), text=True, capture_output=True, check=True
    )


def _status_of(queue_text: str, round_id: str) -> str:
    for line in queue_text.splitlines():
        if line.startswith(f"{round_id}\t"):
            return line.split("\t")[-1]
    return ""


class BookkeepingWorktreeTest(unittest.TestCase):
    """A könyvelés a közös fától FÜGGETLEN, és a friss `main`-re landol."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        base = Path(self._tmp.name)
        self.origin = base / "origin.git"
        self.repo = base / "repo"
        _git("init", "-q", "--bare", str(self.origin), cwd=base)
        self.repo.mkdir()
        _git("init", "-q", "-b", "main", cwd=self.repo)
        _git("config", "user.email", "pipeline@test", cwd=self.repo)
        _git("config", "user.name", "pipeline", cwd=self.repo)
        _git("remote", "add", "origin", str(self.origin), cwd=self.repo)
        for relative, content in ((QUEUE_REL, QUEUE), (REPORT_REL, REPORT)):
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        tools = self.repo / "tools"
        tools.mkdir(exist_ok=True)
        shutil.copy2(SYNC_SCRIPT, tools / "sync-completion-matrix.py")
        os.chmod(tools / "sync-completion-matrix.py", 0o755)
        _git("add", "-A", cwd=self.repo)
        _git("commit", "-qm", "seed", cwd=self.repo)
        _git("push", "-q", "-u", "origin", "main", cwd=self.repo)

    # --- segédek ---------------------------------------------------------

    def _run_bookkeeping(self, *, attempts: int = 3, cwd: Path | None = None) -> tuple[int, str]:
        """A driver SAJÁT függvényét futtatja — nem a teszt másolatát."""
        shell = (
            "set -uo pipefail\n"
            'log() { printf "LOG %s\\n" "$*" >&2; }\n'
            "source <(sed -n '/^commit_main_bookkeeping() {/,/^}$/p' \"$PIPELINE\")\n"
            "declare -F commit_main_bookkeeping >/dev/null || "
            '{ echo "HIÁNYZIK: commit_main_bookkeeping" >&2; exit 90; }\n'
            f'commit_main_bookkeeping "E14-R06" "{QUEUE_REL}" "{REPORT_REL}" {attempts}\n'
            "rc=$?\n"
            'printf "RC=%s\\n" "$rc"\n'
            'exit "$rc"\n'
        )
        completed = subprocess.run(
            ["bash", "-c", shell],
            cwd=str(cwd or self.repo),
            env={**os.environ, "PIPELINE": str(PIPELINE)},
            text=True,
            capture_output=True,
        )
        return completed.returncode, completed.stdout + completed.stderr

    def _origin_main(self) -> str:
        return _git("rev-parse", "refs/heads/main", cwd=self.origin).stdout.strip()

    def _origin_file(self, relative: str) -> str:
        return _git("show", f"main:{relative}", cwd=self.origin).stdout

    def _park_on_a_foreign_round_branch(self) -> str:
        """A KÖZÖS fa a másik slot körének ágán áll, saját lokális committal."""
        _git("checkout", "-q", "-b", ROUND_BRANCH, cwd=self.repo)
        preflight = self.repo / "docs" / "rounds" / "e14-r04.md"
        preflight.parent.mkdir(parents=True, exist_ok=True)
        preflight.write_text("pre-flight: ADR 0505\n", encoding="utf-8")
        _git("add", "-A", cwd=self.repo)
        _git("commit", "-qm", "[E14-R04] Pre-flight: ADR 0505", cwd=self.repo)
        return _git("rev-parse", "HEAD", cwd=self.repo).stdout.strip()

    # --- cellák ----------------------------------------------------------

    def test_it_lands_on_main_while_the_shared_tree_sits_on_another_branch(self) -> None:
        """A mért eset: a közös fa idegen ágon áll, a könyvelésnek mégis a main-re kell kerülnie."""
        preflight_head = self._park_on_a_foreign_round_branch()
        before_origin = self._origin_main()

        code, output = self._run_bookkeeping()
        self.assertEqual(code, 0, output)
        self.assertIn("RC=0", output)

        # 1. a könyvelés a main-en van, és a szám-cellák a queue-t követik
        self.assertNotEqual(self._origin_main(), before_origin, output)
        self.assertEqual(_status_of(self._origin_file(QUEUE_REL), "E14-R06"), "done")
        self.assertIn("| E14 | 4 | 15 | 0 | 0 |", self._origin_file(REPORT_REL))
        # a próza-oszlop és a többi sor érintetlen
        self.assertIn("nyitva (prepared: R02–R19 megírva)", self._origin_file(REPORT_REL))
        self.assertIn("| Ch13 | UI/UX Design System | E13 | 0 | 0 | 0 | 0 |", self._origin_file(REPORT_REL))

        # 2. a MÁSIK kör ága ÉS munkafája érintetlen — ez veszett el élesben
        self.assertEqual(
            _git("rev-parse", "HEAD", cwd=self.repo).stdout.strip(),
            preflight_head,
            "a könyvelés elmozdította a másik slot körének ágát",
        )
        self.assertEqual(
            _git("rev-parse", "--abbrev-ref", "HEAD", cwd=self.repo).stdout.strip(),
            ROUND_BRANCH,
        )
        self.assertTrue((self.repo / "docs" / "rounds" / "e14-r04.md").exists())
        self.assertEqual(_git("status", "--porcelain", cwd=self.repo).stdout.strip(), "")
        # a közös fa sor-fájlja sem íródott át a háta mögött
        self.assertEqual(
            _status_of((self.repo / QUEUE_REL).read_text(encoding="utf-8"), "E14-R06"),
            "pending",
        )

    def test_a_rejected_push_is_retried_against_the_fresh_main(self) -> None:
        """Elutasított push után a KÖVETKEZŐ próba a friss main-ből származtat újra.

        A hook az első push-t elutasítja, és közben a `main`-t egy párhuzamos
        kör commitjára gyorsítja — pontosan az a versenyhelyzet, amiben egy
        naiv „ugyanazt a commitot újra" retry elavult matrixot tolna a main-re.
        """
        # párhuzamos kör: E14-R07 is `done` lesz, de a riportját nem írja
        concurrent = self.repo.parent / "concurrent"
        _git("clone", "-q", "-b", "main", str(self.origin), str(concurrent), cwd=self.repo.parent)
        _git("config", "user.email", "other@test", cwd=concurrent)
        _git("config", "user.name", "other", cwd=concurrent)
        queue_path = concurrent / QUEUE_REL
        queue_path.write_text(
            queue_path.read_text(encoding="utf-8").replace(
                "E14-R07\tdocs/rounds/e14-r07.md\tsonnet-impl\t0307\tpending",
                "E14-R07\tdocs/rounds/e14-r07.md\tsonnet-impl\t0307\tdone",
            ),
            encoding="utf-8",
        )
        _git("add", "-A", cwd=concurrent)
        _git("commit", "-qm", "docs(handoff): E14-R07 lezárva", cwd=concurrent)
        _git("push", "-q", "origin", "HEAD:refs/heads/concurrent", cwd=concurrent)

        hook = self.origin / "hooks" / "pre-receive"
        hook.write_text(
            "#!/bin/sh\n"
            'if [ ! -f "$PWD/rejected-once" ]; then\n'
            '  touch "$PWD/rejected-once"\n'
            # a hook karantén-környezetben fut, onnan tilos a ref-írás — a
            # párhuzamos landolást ezért tisztított környezetben végezzük
            "  env -u GIT_QUARANTINE_PATH -u GIT_OBJECT_DIRECTORY"
            " -u GIT_ALTERNATE_OBJECT_DIRECTORIES"
            ' git --git-dir="$PWD" update-ref refs/heads/main refs/heads/concurrent\n'
            '  echo "párhuzamos kör landolt (teszt-hook)" >&2\n'
            "  exit 1\n"
            "fi\n"
            "exit 0\n",
            encoding="utf-8",
        )
        os.chmod(hook, 0o755)

        code, output = self._run_bookkeeping(attempts=3)
        self.assertEqual(code, 0, output)
        self.assertIn("RC=0", output)
        self.assertIn("a könyvelés push-a nem ment át (1/3)", output)

        queue_on_main = self._origin_file(QUEUE_REL)
        self.assertEqual(_status_of(queue_on_main, "E14-R06"), "done")
        # a párhuzamos kör munkája megmaradt — nem írtuk felül
        self.assertEqual(_status_of(queue_on_main, "E14-R07"), "done")
        # és a matrix a MOSTANI queue-t méri (5 done / 14 pending), nem a
        # bukott próbálkozás elavult számait
        self.assertIn("| E14 | 5 | 14 | 0 | 0 |", self._origin_file(REPORT_REL))

    def test_a_permanent_push_failure_is_reported_not_swallowed(self) -> None:
        """Tartós kudarcnál nem-nulla a visszatérés — a hívó ebből tud hangos lenni."""
        hook = self.origin / "hooks" / "pre-receive"
        hook.write_text('#!/bin/sh\necho "mindig elutasít (teszt-hook)" >&2\nexit 1\n', encoding="utf-8")
        os.chmod(hook, 0o755)

        code, output = self._run_bookkeeping(attempts=2)
        self.assertNotEqual(code, 0, output)
        self.assertIn("RC=1", output)
        self.assertIn("a könyvelés push-a nem ment át (2/2)", output)

    def test_an_already_flipped_queue_makes_no_commit(self) -> None:
        """Idempotencia: ha az orchesztrátor záró commitja elvégezte, nincs mit írni."""
        queue_path = self.repo / QUEUE_REL
        queue_path.write_text(
            queue_path.read_text(encoding="utf-8").replace(
                "E14-R06\tdocs/rounds/e14-r06.md\tsonnet-impl\t0306\tpending",
                "E14-R06\tdocs/rounds/e14-r06.md\tsonnet-impl\t0306\tdone",
            ),
            encoding="utf-8",
        )
        report_path = self.repo / REPORT_REL
        report_path.write_text(
            REPORT.replace("| E14 | 3 | 16 |", "| E14 | 4 | 15 |"), encoding="utf-8"
        )
        _git("add", "-A", cwd=self.repo)
        _git("commit", "-qm", "docs(handoff): E14-R06 lezárva", cwd=self.repo)
        _git("push", "-q", "origin", "main", cwd=self.repo)
        before_origin = self._origin_main()

        code, output = self._run_bookkeeping()
        self.assertEqual(code, 0, output)
        self.assertEqual(self._origin_main(), before_origin, "üres könyvelés-commit született")

    def test_the_bookkeeping_worktree_is_cleaned_up(self) -> None:
        """A munkapéldány nem marad a repóban — különben a következő firing megbotlik."""
        before = _git("worktree", "list", cwd=self.repo).stdout
        code, output = self._run_bookkeeping()
        self.assertEqual(code, 0, output)
        self.assertEqual(_git("worktree", "list", cwd=self.repo).stdout, before)


class MergedBranchContractTest(unittest.TestCase):
    """Forrás-szintű szerződés: a merge-ág nem eshet vissza a mért hibába."""

    def setUp(self) -> None:
        self.source = PIPELINE.read_text(encoding="utf-8")
        self.merged_block = self.source.split("merged)\n", 1)[1].split("\nesac\n", 1)[0]

    def test_the_merged_branch_delegates_to_the_bookkeeping_function(self) -> None:
        self.assertIn("commit_main_bookkeeping \"$round\"", self.merged_block)

    def test_the_shared_tree_is_never_reset_on_a_foreign_branch(self) -> None:
        """A `reset --hard` csak a main-en futhat — ez dobta el az E14-R04 commitját."""
        reset = self.merged_block.index("git reset -q --hard origin/main")
        guard = self.merged_block.rindex(
            'if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]; then', 0, reset
        )
        self.assertLess(guard, reset)

    def test_a_failed_bookkeeping_push_is_loud(self) -> None:
        """A néma `|| log "FIGYELEM…"` nyelés volt a mért hibaosztály."""
        self.assertNotIn('git push -q origin main || log', self.merged_block)
        failure = self.merged_block.split("if ! commit_main_bookkeeping", 1)[1]
        self.assertIn("HIBA:", failure)
        self.assertIn("notify ", failure)


if __name__ == "__main__":
    unittest.main()
