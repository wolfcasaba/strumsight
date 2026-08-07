"""A lánc maradék holtidejének és vakfoltjainak őrei (ADR 0174).

Három MÉRT hiányosság, három őr:

1. **Governance-PR lefagyasztotta a termék-láncot** — 2026-08-05-én KILENC
   firing maradt ki (`nyitott PR van`), pedig a nyitott PR-ek (`ops/…`) egyetlen
   körrel sem versenyeztek. Az őr mostantól csak KÖR-branchre néz.
2. **A közös munkafa idegen ágon maradt** — egy másik session a
   `gov/03-factory-hardening` ágon hagyta, és a lánc emiatt is kiesett egy
   firingre. Tiszta fánál ez maradék, tehát helyreállítható.
3. **A main egészségét csak az egyik sávon néztük** — a 2026-08-05-i három
   önjavító körből egy azért kellett, mert a main ÖRÖKÖLT piros gate-tel élt.

Plusz a költség-főkönyv (token → $), ami a motorválasztást méréssé teszi.
"""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIPELINE = ROOT / "tools" / "round-pipeline.sh"
WRAPPER = ROOT / "tools" / "codex-round.sh"


def _load(module_name: str, relative: str):
    spec = importlib.util.spec_from_file_location(module_name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


round_metrics = _load("round_metrics_plumbing", "tools/round-metrics.py")


class RoundBranchGuardTest(unittest.TestCase):
    """1. hiányosság: mi számít „másik kör" jelének."""

    def branch_filter(self, branches: str, *, inflight: str = "") -> str:
        """A driver `count_foreign` logikája, ugyanazokkal a mintákkal."""
        script = f"""
        set -uo pipefail
        own_branches='{inflight}'
        ROUND_BRANCH_PATTERN='[eE][0-9]{{2}}-[rR][0-9]{{2}}'
        count_foreign() {{
          local rounds_only
          rounds_only=$(grep -E "$ROUND_BRANCH_PATTERN" || true)
          [ -n "$rounds_only" ] || {{ echo 0; return; }}
          if [ -n "$own_branches" ]; then
            printf '%s\\n' "$rounds_only" | grep -Evi "$own_branches" | grep -c '[^[:space:]]' || true
          else
            printf '%s\\n' "$rounds_only" | grep -c '[^[:space:]]' || true
          fi
        }}
        printf '%s\\n' '{branches}' | count_foreign
        """
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
        return result.stdout.strip()

    def test_governance_branches_do_not_block_the_chain(self) -> None:
        for branch in ("ops/pipeline-throughput", "gov/03-factory-hardening", "chore/adr-0069"):
            with self.subTest(branch=branch):
                self.assertEqual(self.branch_filter(branch), "0")

    def test_round_branches_still_block_the_chain(self) -> None:
        for branch in ("codex/e04-r15-streaming-transport", "heal/E04-R15-H3-1", "minimax/e02-r18-results"):
            with self.subTest(branch=branch):
                self.assertEqual(self.branch_filter(branch), "1")

    def test_the_own_inflight_round_is_not_counted_as_foreign(self) -> None:
        self.assertEqual(
            self.branch_filter("codex/e04-r15-streaming-transport", inflight="e04-r15"), "0"
        )

    def test_the_pattern_lives_in_the_driver(self) -> None:
        """Ha valaki a driverben átírja a mintát, ez a teszt elavul — ezért kötjük."""
        self.assertIn("ROUND_BRANCH_PATTERN='[eE][0-9]{2}-[rR][0-9]{2}'", PIPELINE.read_text(encoding="utf-8"))


class WorktreeRecoveryTest(unittest.TestCase):
    """2. hiányosság: a közös munkafa idegen ágon maradt."""

    def test_the_driver_recovers_a_clean_stray_branch(self) -> None:
        text = PIPELINE.read_text(encoding="utf-8")
        self.assertIn("munkafa-helyreállítás", text)
        self.assertIn('git checkout -q main', text)

    def test_a_dirty_stray_branch_still_stops_the_chain(self) -> None:
        """Piszkos fán a helyreállítás munkát semmisítene meg."""
        text = PIPELINE.read_text(encoding="utf-8")
        self.assertIn("és nem tiszta — a lánc csak tiszta main-ről indul", text)


class MainHealthTest(unittest.TestCase):
    """3. hiányosság: a main egészsége mindkét sávon."""

    def setUp(self) -> None:
        self.text = PIPELINE.read_text(encoding="utf-8")

    def test_both_lanes_are_checked_before_a_round_starts(self) -> None:
        self.assertIn("for main_workflow in router-ci.yml full-gate.yml", self.text)

    def test_a_red_main_still_stops_the_chain(self) -> None:
        self.assertIn("a lánc nem indul piros main fölé", self.text)

    def test_a_flaky_red_run_does_not_block_when_the_same_sha_is_green(self) -> None:
        """MÉRT eset (2026-08-06): duplikált dispatch → `cancelled`, és GitHub-infra
        hiba → `Set up job` bukás, miközben UGYANAZON a SHA-n van zöld futás.
        A legutolsó futás önmagában ilyenkor feleslegesen állítaná a láncot."""
        self.assertIn('select(.headSha == ', self.text)
        self.assertIn("*success*)", self.text)

    def test_a_genuinely_red_main_still_stops_the_chain_and_notifies(self) -> None:
        self.assertIn("nem indul piros main fölé", self.text)
        self.assertIn('notify "⛔ piros main"', self.text)

    def test_the_health_run_is_dispatched_after_a_merge(self) -> None:
        self.assertIn("gh workflow run full-gate.yml --ref main", self.text)
        self.assertIn("PIPELINE_MAIN_HEALTH", self.text)


class ActionsOutageGuardTest(unittest.TestCase):
    """Külső kimaradás alatt a lánc VÁR, nem éget keretet (2026-08-06, MÉRT eset).

    A GitHub 15:22-kor nyílt incidenst vezetett az Actionsön („Workflow runs are
    failing or delayed in starting"). Ilyenkor (a) a main-egészség pirosat lát,
    pedig a fa jó, és (b) a kör CI-je kétszer piros → H5 halt → önjavító kör
    indulna egy olyan hibára, amit a repóban nem lehet megjavítani.
    """

    def setUp(self) -> None:
        self.text = PIPELINE.read_text(encoding="utf-8")

    def test_the_guard_reads_the_official_status_component(self) -> None:
        self.assertIn("githubstatus.com/api/v2/components.json", self.text)
        self.assertIn('"Actions"', self.text)
        for state in ("major_outage", "partial_outage", "degraded_performance"):
            with self.subTest(state=state):
                self.assertIn(state, self.text)

    def test_a_red_main_during_an_outage_waits_instead_of_dying(self) -> None:
        self.assertIn("GITHUB-INCIDENS alatt keletkezett", self.text)

    def test_self_heal_is_skipped_during_an_outage(self) -> None:
        """A javító kör külső hibán tiszta keret-égetés."""
        self.assertIn("az önjavítás KIMARAD: GitHub Actions incidens", self.text)

    def test_the_guard_is_fail_open_and_switchable(self) -> None:
        self.assertIn('PIPELINE_STATUS_CHECK:-1', self.text)
        self.assertIn("PIPELINE_STATUS_TIMEOUT", self.text)


class StaleQueuedRunTest(unittest.TestCase):
    """MÉRT eset (2026-08-06): 3,5 órán át `queued` futás állította a láncot."""

    def setUp(self) -> None:
        self.text = PIPELINE.read_text(encoding="utf-8")

    def test_a_long_queued_run_is_not_counted_as_a_running_round(self) -> None:
        self.assertIn("PIPELINE_STALE_QUEUED_MINUTES:-60", self.text)
        self.assertIn("BERAGADT FUTÁS", self.text)

    def test_a_fresh_queued_run_still_blocks(self) -> None:
        """A friss `queued` futás VALÓBAN másik kör lehet — az őr csak a korra szűr."""
        self.assertIn('[ "$state" = "queued" ] && [ "$age_minutes" -ge "$stale_queued_minutes" ]', self.text)


class OutageWorkModeTest(unittest.TestCase):
    """Kimaradás alatt a merge-kapu a LOKÁLIS teljes mérce — nem kevesebb."""

    def setUp(self) -> None:
        self.text = PIPELINE.read_text(encoding="utf-8")
        self.prompt = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text(encoding="utf-8")

    def test_the_note_is_only_written_during_an_outage(self) -> None:
        self.assertIn('ci_note="nincs"', self.text)
        self.assertIn("if github_actions_degraded; then", self.text)

    def test_the_local_substitute_covers_the_full_ci_chain(self) -> None:
        """Ha ebből bármelyik kimarad, a lokális evidencia KEVESEBB a CI-nél."""
        for command in (
            "tools/round-gate.sh",
            "flutter test",
            "PROPERTY_SEED=$(date +%s)",
            "check_assets.dart",
            "check_song_schema.dart",
            "check_song_fixture_licenses.dart",
        ):
            with self.subTest(command=command):
                self.assertIn(command, self.text)

    def test_native_rounds_have_no_local_substitute(self) -> None:
        self.assertIn("NINCS lokális pótlás", self.text)

    def test_the_ci_evidence_must_be_backfilled_after_recovery(self) -> None:
        self.assertIn("helyreállás UTÁN pótlandó", self.text)

    def test_the_prompt_template_declares_the_placeholder(self) -> None:
        self.assertIn("{{CI_NOTE}}", self.prompt)


class CostLedgerTest(unittest.TestCase):
    """Költség-főkönyv — MINIMÁLIS őrzés (user 2026-08-05: „költség nem fontos").

    A mérés bent marad (a burkoló egy sort ír futásonként, a `--cost` kimutatás
    olvassa), de nem fejlesztjük tovább. Két dolgot mérünk: a sor tényleg
    megszületik, és a főkönyv SOHA nem buktathat kört.
    """

    def test_the_wrapper_records_a_ledger_row(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            base = Path(name)
            workdir = base / "work"
            workdir.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=workdir, check=True)
            subprocess.run(["git", "config", "user.email", "t@e.hu"], cwd=workdir, check=True)
            subprocess.run(["git", "config", "user.name", "T"], cwd=workdir, check=True)
            (workdir / "f.txt").write_text("x\n", encoding="utf-8")
            subprocess.run(["git", "add", "-A"], cwd=workdir, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=workdir, check=True)
            subprocess.run(["git", "checkout", "-q", "-b", "codex/e09-r01-probe"], cwd=workdir, check=True)

            fake = base / "fake-codex"
            fake.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'session id: 019fd369-a3ab-7713-9750-960f66886489\\n'\n"
                "printf 'tokens used\\n123456\\n'\n"
                "printf 'status=done\\nsummary=kesz\\n' > \"$FAKE_SIGNAL\"\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)

            ledger_dir = base / "state"
            ledger_dir.mkdir()
            environment = dict(os.environ)
            environment.update(
                {
                    "CODEX_BIN": str(fake),
                    "ROUND_ENGINE": "qwen38-max",
                    "FAKE_SIGNAL": str(workdir / ".codex-round-status"),
                    "PIPELINE_COST_LEDGER": str(ledger_dir / "cost.tsv"),
                    "CODEX_POLL_SECONDS": "1",
                }
            )
            environment.pop("ROUND_BRIEF", None)
            prompt = base / "prompt.md"
            prompt.write_text("feladat\n", encoding="utf-8")
            subprocess.run(
                ["bash", str(WRAPPER), str(workdir), str(prompt), str(base / "round.log")],
                capture_output=True,
                text=True,
                env=environment,
                cwd=str(ROOT),
            )
            rows = (ledger_dir / "cost.tsv").read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(rows), 2, rows)
            fields = rows[1].split("\t")
            self.assertEqual(fields[1], "E09-R01", "a kör a branch nevéből jön")
            self.assertEqual(fields[4], "123456")

    def test_the_ledger_is_a_no_op_when_its_directory_is_missing(self) -> None:
        """Fail-open: a költségmérés SOHA nem buktathat kört."""
        self.assertIn('[ -d "$(dirname "$ledger")" ] || return 0', WRAPPER.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
