"""Folytatáskori orchestrátor-rotáció és reviewer-függetlenség (ADR 0242).

MÉRT ok (2026-08-13, E06-R23 H-INDEP, 4 óra 35 perc állásidő egy kész,
gate-zöld kör fölött). Az eredeti dispatch helyes párt adott:
`orchestrator=terra` + `implementer=sonnet-impl`. A session H3-ra elhalt, a
self-heal javította (PR #240), de az ÚJRAINDÍTÁS a `round-pipeline.sh`
GLOBÁLIS rotáció-állapota miatt `orchestrator=claude`-ra billent — miközben
az ágon már `sonnet-impl` (ugyanaz a `~/.claude` kvóta) commitolt. Nem
maradt független reviewer.

Ez a fájl két, egymásra épülő géppel mért döntést tesztel, mindkettőt
hálózat és élő modellhívás nélkül:

  D1 — a rotáció KÖRÖNKÉNT kulcsolt, nem globális (`--next-orchestrator
       <kör>`): egy kör MINDEN dispatchje (elhalt + újraindított is)
       ugyanazt az orchestrátort kapja vissza.
  D2 — folytatáskor az implementer-identitás az ágról MÉRT tény
       (`--branch-implementer <kör>`), és ütközésnél az ORCHESTRÁTOR billen,
       nem az implementer (`--resume-orchestrator <kör> <implementer>`).

A D2 tesztek egy lokális bare repót használnak "origin" gyanánt
(`PIPELINE_ROUND_REMOTE`) — nincs hálózat, nincs valódi GitHub-hívás.
"""

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "tools" / "round-pipeline.sh"


def driver(*args: str, state: Path, **env: str) -> subprocess.CompletedProcess:
    environment = dict(os.environ, PIPELINE_STATE_DIR=str(state), **env)
    return subprocess.run(
        ["bash", str(DRIVER), *args],
        capture_output=True,
        text=True,
        env=environment,
        timeout=60,
    )


def make_round_branch(root: Path, remote_name: str, prefix: str, round_id: str) -> Path:
    """Egy bare 'origin' repót hoz létre egy <prefix>/<round-slug>-... ág-gal.

    Visszaadja a bare repo elérési útját (ez kerül a PIPELINE_ROUND_REMOTE
    env-be, mint az a remote, amit a driver `git ls-remote`-tel olvas).
    """
    bare = root / f"{remote_name}.git"
    work = root / f"{remote_name}-work"
    subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
    subprocess.run(["git", "init", "-q", "-b", "main", str(work)], check=True)
    subprocess.run(["git", "-C", str(work), "config", "user.email", "a@x.test"], check=True)
    subprocess.run(["git", "-C", str(work), "config", "user.name", "A"], check=True)
    (work / "f.txt").write_text("x\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(work), "add", "f.txt"], check=True)
    subprocess.run(["git", "-C", str(work), "commit", "-q", "-m", "init"], check=True)
    slug = round_id.lower()
    branch = f"{prefix}/{slug}-some-round-title"
    subprocess.run(["git", "-C", str(work), "checkout", "-q", "-b", branch], check=True)
    subprocess.run(["git", "-C", str(work), "remote", "add", "origin", str(bare)], check=True)
    subprocess.run(["git", "-C", str(work), "push", "-q", "origin", branch], check=True)
    return bare


class PerRoundRotationTest(unittest.TestCase):
    """D1 (ADR 0242 §5.1): a rotáció a KÖRHÖZ rögzül, nem a lánchoz."""

    def test_a_second_dispatch_of_the_same_round_keeps_its_orchestrator(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            last = state / "orchestrator-last"
            last.write_text("claude\n", encoding="utf-8")

            first = driver("--next-orchestrator", "E06-R23", state=state)
            self.assertEqual(first.stdout.strip(), "terra", first.stderr)
            # az ELSŐ dispatch rögzít, és a globális léptető-fájl is frissül —
            # ez számít az ÚJ körök (nem ugyanez a kör) léptetésébe.
            self.assertEqual(last.read_text(encoding="utf-8").strip(), "terra")

            second = driver("--next-orchestrator", "E06-R23", state=state)
            self.assertEqual(
                second.stdout.strip(),
                "terra",
                "a MÁSODIK dispatch (retry/resume) nem billenhet át claude-ra",
            )
            # a globális fájl a MÁSODIK dispatch alatt nem mozdulhat tovább
            self.assertEqual(last.read_text(encoding="utf-8").strip(), "terra")

    def test_a_new_round_still_alternates(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            (state / "orchestrator-last").write_text("terra\n", encoding="utf-8")
            # E06-R23-hoz nincs rögzítés — csak E06-R24-et kérünk, ami ÚJ kör
            result = driver("--next-orchestrator", "E06-R24", state=state)
            self.assertEqual(result.stdout.strip(), "claude", result.stderr)


class ResumeImplementerFromBranchTest(unittest.TestCase):
    """D2 (ADR 0242 §5.2): az implementer az ágról MÉRT tény, nem a queue-é."""

    def test_resume_reads_the_committed_implementer_from_the_branch_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            bare = make_round_branch(root, "origin", "sonnet-impl", "E06-R23")
            state = root / "state"
            state.mkdir()
            result = driver(
                "--branch-implementer",
                "E06-R23",
                state=state,
                PIPELINE_ROUND_REMOTE=str(bare),
            )
            self.assertEqual(result.stdout.strip(), "sonnet-impl", result.stderr)

    def test_a_round_with_no_branch_yet_measures_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            bare = make_round_branch(root, "origin", "sonnet-impl", "E06-R23")
            state = root / "state"
            state.mkdir()
            result = driver(
                "--branch-implementer",
                "E06-R99",
                state=state,
                PIPELINE_ROUND_REMOTE=str(bare),
            )
            self.assertEqual(result.stdout.strip(), "", result.stderr)

    def test_an_ops_branch_never_matches_a_round_id(self) -> None:
        """ADR 0242 §9 kockázat: az `ops/*` ágak nem kör-ágak."""
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            bare = make_round_branch(root, "origin", "ops", "throughput")
            state = root / "state"
            state.mkdir()
            result = driver(
                "--branch-implementer",
                "E06-R23",
                state=state,
                PIPELINE_ROUND_REMOTE=str(bare),
            )
            self.assertEqual(result.stdout.strip(), "", result.stderr)


class WorkspaceRestorationHermeticityTest(unittest.TestCase):
    """Independent-review F1 regression (2026-08-13).

    A bare, no-argument dispatch used to run a REAL `git checkout -q main`
    on the process's cwd whenever that cwd's branch differed from `main`
    and the tree was clean -- harmless for the real production cron working
    directory (`PIPELINE_STATE_DIR` unset there), but hazardous for a
    `PIPELINE_STATE_DIR`-injected test/review clone: it silently switched
    the reviewed branch away from under later, alphabetically-ordered
    `tools/tests` files, which then measured `main` instead of the
    reviewed commit. Test-mode (`PIPELINE_STATE_DIR` set) must fail closed
    instead of touching the shared working tree's branch.
    """

    def _fixture_repo(self, root: Path) -> Path:
        bare = root / "origin.git"
        work = root / "work"
        subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(work)], check=True)
        subprocess.run(["git", "-C", str(work), "config", "user.email", "a@x.test"], check=True)
        subprocess.run(["git", "-C", str(work), "config", "user.name", "A"], check=True)
        (work / "f.txt").write_text("x\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(work), "add", "f.txt"], check=True)
        subprocess.run(["git", "-C", str(work), "commit", "-q", "-m", "init"], check=True)
        subprocess.run(["git", "-C", str(work), "remote", "add", "origin", str(bare)], check=True)
        subprocess.run(["git", "-C", str(work), "push", "-q", "origin", "main"], check=True)
        subprocess.run(
            ["git", "-C", str(work), "checkout", "-q", "-b", "sonnet-impl/e00-r00-fixture"],
            check=True,
        )
        return work

    def test_test_mode_dispatch_does_not_switch_the_working_tree_off_its_branch(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            work = self._fixture_repo(root)
            state = root / "state"
            state.mkdir()
            environment = dict(os.environ, PIPELINE_STATE_DIR=str(state))

            result = subprocess.run(
                ["bash", str(DRIVER)],
                capture_output=True,
                text=True,
                env=environment,
                cwd=work,
                timeout=60,
            )

            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("PIPELINE_STATE_DIR", result.stderr)
            branch = subprocess.run(
                ["git", "-C", str(work), "rev-parse", "--abbrev-ref", "HEAD"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            self.assertEqual(
                branch,
                "sonnet-impl/e00-r00-fixture",
                "teszt-módban a driver nem mozdíthatja el a megosztott munkafa ágát",
            )


class ResumeOrchestratorConflictTest(unittest.TestCase):
    """D2 (ADR 0242 §5.2): ütközésnél az ORCHESTRÁTOR billen, nem az implementer."""

    def test_no_conflict_keeps_the_pinned_orchestrator(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            # a kör orchestrátora már 'terra' -- a minimax implementer nem
            # oszt kvótát a claude-dal SEM, terra-val SEM.
            (state / "orchestrator-round").mkdir()
            (state / "orchestrator-round" / "E06-R23").write_text("terra\n", encoding="utf-8")
            result = driver("--resume-orchestrator", "E06-R23", "minimax", state=state)
            self.assertEqual(result.stdout.strip(), "terra", result.stderr)

    def test_on_conflict_the_orchestrator_flips_not_the_implementer(self) -> None:
        """MÉRT eset: a kör orchestrátora 'claude'-ra billent (globális bug),
        miközben az ágon a claude-kvótát fogyasztó `sonnet-impl` commitolt.
        A helyes feloldás: az orchestrátor megy 'terra'-ra -- az implementer
        `sonnet-impl` marad (a hívó ezt nem is adja át módosításra)."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            (state / "orchestrator-round").mkdir()
            (state / "orchestrator-round" / "E06-R23").write_text("claude\n", encoding="utf-8")
            result = driver("--resume-orchestrator", "E06-R23", "sonnet-impl", state=state)
            self.assertEqual(
                result.stdout.strip(),
                "terra",
                "ütközésnél az orchestrátornak kell billennie, nem HALT_INDEP-nek vagy claude-nak",
            )

    def test_a_terra_pin_facing_a_terra_model_implementer_also_flips(self) -> None:
        """A fordított ütközés: a kör orchestrátora 'terra', az ágon egy
        gpt-5.6-terra modellt futtató implementer (`terra`) commitolt -- a
        Terra nem review-zheti a saját diffjét (ADR 0138)."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            (state / "orchestrator-round").mkdir()
            (state / "orchestrator-round" / "E06-R23").write_text("terra\n", encoding="utf-8")
            result = driver("--resume-orchestrator", "E06-R23", "terra", state=state)
            self.assertEqual(result.stdout.strip(), "claude", result.stderr)

    def test_unknown_branch_prefix_fails_closed(self) -> None:
        """ADR 0242 §5.3: a registryből fel nem oldható ág-prefix H-INDEP,
        nem csendes átengedés -- a függetlenség bizonyítandó, nem vélelmezett."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            result = driver(
                "--resume-orchestrator", "E06-R23", "some-unregistered-engine", state=state
            )
            self.assertEqual(result.stdout.strip(), "HALT_INDEP", result.stderr)

    def test_a_conflicting_pin_with_no_available_alternate_fails_closed(self) -> None:
        """Independent-review F2: a pinned orchestrator conflicts with the
        branch-measured implementer AND the only alternate (claude) is under
        an active quota block -- the resolver must fail closed to HALT_INDEP,
        not silently select the unavailable alternate."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            (state / "orchestrator-round").mkdir()
            (state / "orchestrator-round" / "E06-R23").write_text("terra\n", encoding="utf-8")
            (state / "claude-blocked-until").write_text(
                f"{int(time.time()) + 3600}\n", encoding="utf-8"
            )
            result = driver("--resume-orchestrator", "E06-R23", "terra", state=state)
            self.assertEqual(
                result.stdout.strip(),
                "HALT_INDEP",
                "pinned orchestrator conflicts, and the only independent alternate is "
                "unavailable -- must fail closed, not select it anyway",
            )

    def test_an_independent_but_unavailable_pin_is_not_retained(self) -> None:
        """Opposite direction of F2: the pinned orchestrator is independent
        of the branch-measured implementer, but it is under an active quota
        block -- the resolver must move to the available alternate, not keep
        the unavailable pin merely because its identity is independent."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            (state / "orchestrator-round").mkdir()
            (state / "orchestrator-round" / "E06-R23").write_text("claude\n", encoding="utf-8")
            (state / "claude-blocked-until").write_text(
                f"{int(time.time()) + 3600}\n", encoding="utf-8"
            )
            result = driver("--resume-orchestrator", "E06-R23", "minimax", state=state)
            self.assertEqual(
                result.stdout.strip(),
                "terra",
                "the pinned claude is independent of minimax but unavailable -- "
                "the resolver must flip to the available alternate",
            )
            self.assertEqual(
                (state / "orchestrator-round" / "E06-R23").read_text(encoding="utf-8").strip(),
                "terra",
                "the round-pin must be updated to the new orchestrator, not left stale",
            )

    def test_the_full_measure_and_resolve_pipeline_fails_closed_on_unknown_prefix(self) -> None:
        """Végponttól végpontig: egy ismeretlen ág-prefixű kör-ág mérése
        (`--branch-implementer`) majd feloldása (`--resume-orchestrator`)
        MINDIG H-INDEP-re fut, sosem "biztos rendben van"-ra."""
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            bare = make_round_branch(root, "origin", "some-weird-tool", "E06-R23")
            state = root / "state"
            state.mkdir()
            measured = driver(
                "--branch-implementer",
                "E06-R23",
                state=state,
                PIPELINE_ROUND_REMOTE=str(bare),
            )
            self.assertEqual(measured.stdout.strip(), "some-weird-tool")
            resolved = driver(
                "--resume-orchestrator", "E06-R23", measured.stdout.strip(), state=state
            )
            self.assertEqual(resolved.stdout.strip(), "HALT_INDEP", resolved.stderr)


if __name__ == "__main__":
    unittest.main()
