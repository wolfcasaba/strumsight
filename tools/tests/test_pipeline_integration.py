import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class PipelineIntegrationTest(unittest.TestCase):
    def run_command(self, argv, *, cwd=ROOT, env=None):
        return subprocess.run(
            argv,
            cwd=cwd,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_engine_enum_accepts_auto_and_keeps_legacy_overrides(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        for engine in ("auto", "minimax", "codex"):
            with self.subTest(engine=engine):
                result = self.run_command(["bash", str(script), "--validate-engine", engine])
                self.assertEqual(result.returncode, 0, result.stderr)
        rejected = self.run_command(["bash", str(script), "--validate-engine", "surprise"])
        self.assertEqual(rejected.returncode, 2)

    def test_queue_runs_the_whole_epic3_on_auto_including_the_closure_round(self) -> None:
        # A user 2026-08-01-i döntése: az Epic 3 MIND a 22 sora fut az auto
        # routeren, folyamatosan. (A korábbi `prepared` + kézi zárókör
        # elvárását ez a döntés váltotta le — ADR 0087 §7, ADR 0112 §6.)
        queue = (ROOT / "docs" / "execution" / "pipeline-queue.tsv").read_text()
        self.assertIn("auto | minimax | codex", queue)
        rows = [line.split("\t") for line in queue.splitlines() if line and not line.startswith("#")]
        self.assertTrue(all(row[2] in {"auto", "minimax", "codex"} for row in rows))
        epic3 = [row for row in rows if row[0].startswith("E03-")]
        self.assertEqual([row[0] for row in epic3], [f"E03-R{i:02d}" for i in range(1, 23)])
        self.assertTrue(all(row[2] == "auto" for row in epic3))
        self.assertTrue(all(row[4] in {"pending", "running", "done"} for row in epic3))

    def test_prompt_has_one_initial_auto_dispatch_and_budget_preserving_resume(self) -> None:
        prompt = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text()
        self.assertEqual(prompt.count("ai-router-round.sh run"), 1)
        self.assertIn("ai-router-round.sh resume", prompt)
        self.assertIn("READY_FOR_REVIEW", prompt)
        self.assertIn("független", prompt.lower())
        self.assertIn("review + CI", prompt)
        self.assertIn("örökölt", prompt.lower())

    def test_prompt_auto_dispatch_is_detached_and_polled_not_synchronous(self) -> None:
        # Módosítás (ADR 0112 önjavító kör, 2026-08-02, E03-R05 H6): a
        # `engine=auto` dispatch a Bash-eszköz mért 600s-es kemény plafonjánál
        # rövidebbre volt kényszerítve egy szinkron hívással, miközben
        # `.ai/router.toml`-ban `model_timeout_seconds=7200` — két egymást
        # követő hívás mindkétszer SIGTERM-mel halt meg jelzés nélkül
        # (docs/LESSONS.md L42 pontos ismétlődése). A javítás a már
        # `minimax`/`codex` úton szentesített leválaszt-és-előtérben-várj
        # mintát vezeti be `auto`-ra is. Ez a teszt a REGRESSZIÓ ellen véd:
        # a szinkron parancs visszaállítása ne csússzon be észrevétlenül.
        prompt = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text()
        auto_section = prompt.split("### `auto`", 1)[1].split("### `minimax`", 1)[0]
        self.assertIn("setsid", auto_section)
        self.assertIn("wait-for-router.sh", auto_section)
        self.assertNotIn("előtérben, szinkron módon", prompt)
        self.assertTrue((ROOT / "tools" / "wait-for-router.sh").exists())

    def make_router_signal_worktree(self, directory: Path) -> Path:
        worktree = directory / "signal-worktree"
        (worktree / "tools").mkdir(parents=True)
        shutil.copy2(ROOT / "tools" / "codex-signal.sh", worktree / "tools" / "codex-signal.sh")
        subprocess.run(["git", "init", "-q"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.email", "pipeline@example.invalid"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.name", "Pipeline Test"], cwd=worktree, check=True)
        (worktree / "readme.txt").write_text("signal fixture\n")
        subprocess.run(["git", "add", "."], cwd=worktree, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=worktree, check=True)
        return worktree

    def test_wait_for_round_does_not_recognize_router_terminal_signals(self) -> None:
        # A MÉRT gyökérok, ami miatt `wait-for-router.sh` külön szkript kell:
        # az örökölt `wait-for-round.sh` `case`-ága nem ismeri a router
        # `progress`/`blocked` állapotait, tehát azokra a `max_wait` leteltéig
        # üresen pörögne -- ha ezt valaha megoldanák `wait-for-round.sh`
        # bővítésével, ez a teszt jelezze, mert akkor `wait-for-router.sh`
        # feleslegessé válhat, de a mostani, MÉRT viselkedés ez. A jelzést a
        # VÁRAKOZÁS INDULÁSA UTÁN írjuk (Popen), mert a valós futásban is így
        # történik -- előbb írva a baseline-védelem (L12) takarná el a
        # `case`-ág hiányát.
        with tempfile.TemporaryDirectory() as directory_name:
            worktree = self.make_router_signal_worktree(Path(directory_name))
            env = dict(os.environ, WAIT_POLL_SECONDS="1")
            process = subprocess.Popen(
                ["bash", str(ROOT / "tools" / "wait-for-round.sh"), str(worktree), "3"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            time.sleep(1)
            script = worktree / "tools" / "codex-signal.sh"
            self.run_command(["bash", str(script), "READY_FOR_REVIEW", "router done"], cwd=worktree)
            stdout, stderr = process.communicate(timeout=10)

            self.assertEqual(process.returncode, 5, stdout + stderr)
            self.assertIn("MÉG FUTHAT", stderr)

    def test_wait_for_router_recognizes_every_terminal_router_status_promptly(self) -> None:
        for router_status in ("READY_FOR_REVIEW", "STOPPED", "DEFERRED", "BLOCKED", "INTERNAL_ERROR"):
            with self.subTest(router_status=router_status):
                with tempfile.TemporaryDirectory() as directory_name:
                    worktree = self.make_router_signal_worktree(Path(directory_name))
                    env = dict(os.environ, WAIT_POLL_SECONDS="1")
                    process = subprocess.Popen(
                        ["bash", str(ROOT / "tools" / "wait-for-router.sh"), str(worktree), "10"],
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        env=env,
                    )
                    time.sleep(1)
                    script = worktree / "tools" / "codex-signal.sh"
                    self.run_command(["bash", str(script), router_status, "router terminal"], cwd=worktree)
                    stdout, stderr = process.communicate(timeout=10)

                    self.assertEqual(process.returncode, 0, stdout + stderr)
                    self.assertIn(f"router_status={router_status}", stdout)

    def test_wait_for_router_times_out_while_the_router_is_still_running(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            worktree = self.make_router_signal_worktree(Path(directory_name))

            completed = self.run_command(
                ["bash", str(ROOT / "tools" / "wait-for-router.sh"), str(worktree), "2"],
            )

            self.assertEqual(completed.returncode, 5, completed.stdout + completed.stderr)
            self.assertIn("MÉG FUTHAT", completed.stderr)

    def test_wait_for_router_ignores_a_stale_terminal_signal_from_a_previous_round(self) -> None:
        # Ugyanaz a védelem, mint wait-for-round.sh-nál: egy korábbi kör
        # bennragadt terminális jelzése ne zárja le azonnal az új várakozást.
        with tempfile.TemporaryDirectory() as directory_name:
            worktree = self.make_router_signal_worktree(Path(directory_name))
            script = worktree / "tools" / "codex-signal.sh"
            self.run_command(["bash", str(script), "STOPPED", "stale from a previous round"], cwd=worktree)

            completed = self.run_command(
                ["bash", str(ROOT / "tools" / "wait-for-router.sh"), str(worktree), "2"],
            )

            self.assertEqual(completed.returncode, 5, completed.stdout + completed.stderr)

    def test_selfheal_prompt_defines_the_three_outcomes_and_the_gate_boundary(self) -> None:
        prompt = (ROOT / "docs" / "execution" / "pipeline-selfheal-prompt.md").read_text()
        for placeholder in ("{{ROUND}}", "{{HALT_CODE}}", "{{ATTEMPT}}", "{{HEAL_STATUS_FILE}}"):
            self.assertIn(placeholder, prompt)
        for outcome in ("outcome=fixed", "`retry`", "`escalate`"):
            self.assertIn(outcome, prompt)
        # A mérce-határ nem opcionális része a promptnak (ADR 0112 §3).
        self.assertIn("round-gate.sh", prompt)
        self.assertIn(".github/workflows/", prompt)
        self.assertIn("regressziós teszt", prompt)

    def test_selfheal_prompt_preserves_current_main_scope_for_h8_brief_conflicts(self) -> None:
        """H8 regression: a superseded round brief must not require a force-push."""
        prompt = (ROOT / "docs" / "execution" / "pipeline-selfheal-prompt.md").read_text()
        self.assertIn("H8", prompt)
        self.assertIn("rebase --abort", prompt)
        self.assertIn("merge --no-ff origin/main", prompt)
        self.assertIn("merge-base --is-ancestor origin/main HEAD", prompt)
        self.assertIn("force-push", prompt)
        self.assertIn("aktuális `main` brief-változatát", prompt)
        adr = (ROOT / "docs" / "adr" / "0112-self-healing-pipeline.md").read_text()
        self.assertIn("merge-base --is-ancestor origin/main HEAD", adr)

    def test_halted_chain_starts_selfheal_unless_it_is_switched_off(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H6\nsummary=teszt halt\n")
            env = dict(os.environ)
            env.update(PIPELINE_STATE_DIR=str(state), PIPELINE_SELFHEAL="0")

            switched_off = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(switched_off.returncode, 3)
            self.assertIn("önjavítás kikapcsolva", switched_off.stderr)
            self.assertTrue((state / "HALTED").exists())

    def test_selfheal_gives_up_after_the_configured_attempt_budget(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H6\nsummary=teszt halt\n")
            (state / "selfheal.count").write_text("E09-R01|H6|2\n")
            env = dict(os.environ)
            env.update(PIPELINE_STATE_DIR=str(state), PIPELINE_SELFHEAL_MAX="2")

            exhausted = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(exhausted.returncode, 3)
            self.assertIn("KIMERÜLT", exhausted.stderr)
            # A kimerült keret nem indíthat újabb sessiont, és nem old fel.
            self.assertNotIn("ÖNJAVÍTÓ KÖR indul", exhausted.stderr)
            self.assertTrue((state / "HALTED").exists())

    def test_selfheal_attempt_counter_is_scoped_to_round_and_halt_code(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "selfheal.count").write_text("E09-R01|H6|2\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)

            same = self.run_command(["bash", str(script), "--heal-attempts", "E09-R01", "H6"], env=env)
            other_code = self.run_command(["bash", str(script), "--heal-attempts", "E09-R01", "H5"], env=env)
            other_round = self.run_command(["bash", str(script), "--heal-attempts", "E09-R02", "H6"], env=env)

            self.assertEqual(same.stdout.strip(), "2")
            self.assertEqual(other_code.stdout.strip(), "0")
            self.assertEqual(other_round.stdout.strip(), "0")

    def test_terra_hold_active_test_hook_matches_round_and_future_timestamp(self) -> None:
        # E03-R08 H6 self-heal (2026-08-02): the shared daily Terra budget
        # (.ai/router.toml max_automatic_terra_calls_per_utc_day) only
        # resets at UTC midnight, not on any retry cadence — a hold file
        # scoped to the blocked round should read as active while its
        # deadline is in the future.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": false, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            future = int(time.time()) + 3600
            (state / "terra-budget-hold").write_text(f"round=E03-R08\nhold_until={future}\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            active = self.run_command(["bash", str(script), "--terra-hold-active", "E03-R08"], env=env)
            other_round = self.run_command(["bash", str(script), "--terra-hold-active", "E03-R09"], env=env)

            self.assertEqual(active.returncode, 0, active.stderr)
            self.assertIn("felfüggesztés aktív", active.stderr)
            self.assertEqual(other_round.returncode, 1, other_round.stderr)

    def test_unlimited_terra_policy_removes_a_stale_daily_budget_hold(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            hold_file = state / "terra-budget-hold"
            hold_file.write_text(
                f"round=E03-R08\nhold_until={int(time.time()) + 3600}\n"
            )
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-active", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertFalse(hold_file.exists())

    def test_stale_h6_halt_is_cleared_once_the_daily_terra_cap_goes_unlimited(self) -> None:
        # MÉRT gyökérok (E03-R08 H6, 7. előfordulás, 2026-08-02 18:45 UTC,
        # heal-prompt-E03-R08-20260802T184502.md): a napi Terra-korlát
        # eltávolítása (PR #72, `max_automatic_terra_calls_per_utc_day = 0`
        # = unlimited) után az ELSŐ firing helyesen törölte az akkor még élő
        # `terra-budget-hold` fájlt (l.
        # `test_unlimited_terra_policy_removes_a_stale_daily_budget_hold`
        # fentebb) — attól kezdve a hold-fájl NEM LÉTEZIK többé. A
        # `.pipeline/HALTED` fájl viszont, amit a MÉG korlátozott policy
        # alatt írt ki `handle_round_halt` ugyanerre a Terra-kimerülésre,
        # érintetlen maradt, és a driver főági 2. szakasza (`[ -f
        # "$halt_file" ]`) ezt — a hold-fájl (nemlétező) állapotától
        # TELJESEN függetlenül — egy ÚJABB, valódi önjavító sessionnek nézte.
        # Élesben ez pontosan megtörtént (heal-E03-R08-20260802T184502.log,
        # 7. heal-session egy már megszűnt okra). Ez a teszt EZT a valós
        # állapotot reprodukálja: NINCS hold-fájl, csak a stale HALTED —
        # `terra_clear_stale_halt_for` önállóan, a hold-fájl létezésétől
        # függetlenül kell hogy lekérdezze a policy-t és archiválja a
        # HALTED-et.
        #
        # SAFETY (mérve, ennek a tesztnek egy korábbi verziója élesen
        # megtörtént: egy RED futás — a `--terra-clear-stale-halt` hook még
        # nem létezett — a flag-et ismeretlen argumentumként átengedte a
        # TELJES driver-folyamatnak, ami a HALTED-re egy VALÓDI
        # tmux+claude önjavító sessiont indított ezen a repón, kézzel kellett
        # leállítani). `selfheal.count` ezért a kísérletbüdzsé HATÁRÁN
        # (3) ül, `PIPELINE_SELFHEAL_MAX=3`-mal együtt — pontosan úgy, mint a
        # `test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`
        # mintája: ha a hook hiányzik, a driver a kimerült-büdzsé
        # rövidzárba fut ("KIMERÜLT", session nélkül), sosem spawnol
        # valódi sessiont.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            halt_file = state / "HALTED"
            halt_file.write_text(
                "round=E03-R08\n"
                "halt=H6\n"
                "summary=auto router task E03-R08 is DEFERRED — Terra's automatic "
                "daily budget is genuinely exhausted for utc_day=2026-08-02\n"
                "halted_at=2026-08-02T16:58:03+00:00\n"
            )
            (state / "selfheal.count").write_text("E03-R08|H6|3\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PIPELINE_SELFHEAL_MAX"] = "3"
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-clear-stale-halt", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(
                halt_file.exists(),
                "a stale H6 HALTED fájlnak el kell tűnnie, amikor a napi Terra-korlát "
                "megszűnik — különben a következő firing felesleges önjavítást indít",
            )
            self.assertFalse(
                (state / "selfheal.count").exists(),
                "a kísérletszámlálónak nullázódnia kell, mert ez nem egy valódi javítás volt",
            )
            healed = list(state.glob("healed-E03-R08-*.txt"))
            self.assertEqual(len(healed), 1, "a stale halt-ot archiválni kell, nem eldobni")
            self.assertIn("Terra", healed[0].read_text())

    def test_stale_h6_halt_survives_when_daily_terra_cap_is_still_finite(self) -> None:
        # A biztonsági ellenpélda: amíg a napi Terra-korlát ténylegesen
        # kimerült (nem `unlimited`), a HALTED-nek ÉLNIE kell — ez a
        # naptár-korlátozott, valódi halt, amit [[L62]]/[[L65]] szándékosan
        # nem old fel session/heal-kísérlet nélkül.
        #
        # SAFETY: ugyanaz az indoklás, mint a fenti
        # `test_stale_h6_halt_is_cleared_once_the_daily_terra_cap_goes_unlimited`-ben
        # — `selfheal.count` a büdzsé HATÁRÁN ül, hogy egy hiányzó hook
        # esetén a driver sose spawnoljon valódi tmux+claude sessiont.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": false, \"exhausted\": true}'\n"
                "    exit 1\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            halt_file = state / "HALTED"
            halt_file.write_text(
                "round=E03-R08\n"
                "halt=H6\n"
                "summary=auto router task E03-R08 is DEFERRED — Terra's automatic "
                "daily budget is genuinely exhausted for utc_day=2026-08-02\n"
                "halted_at=2026-08-02T16:58:03+00:00\n"
            )
            (state / "selfheal.count").write_text("E03-R08|H6|3\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PIPELINE_SELFHEAL_MAX"] = "3"
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-clear-stale-halt", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(
                halt_file.exists(),
                "amíg a napi Terra-korlát ténylegesen kimerült, a HALTED-et nem "
                "szabad törölni",
            )

    def test_unlimited_terra_policy_keeps_hold_active_when_removal_fails(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            python_stub = stub_bin / "python3"
            python_stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            python_stub.chmod(0o755)
            rm_stub = stub_bin / "rm"
            rm_stub.write_text("#!/bin/sh\nexit 1\n")
            rm_stub.chmod(0o755)
            hold_file = state / "terra-budget-hold"
            hold_file.write_text(
                f"round=E03-R08\nhold_until={int(time.time()) + 3600}\n"
            )
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-active", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("elavult Terra-hold nem törölhető", result.stderr)
            self.assertTrue(hold_file.exists())

    def test_terra_hold_remains_fail_closed_when_policy_status_is_unavailable(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*) exit 50 ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            hold_file = state / "terra-budget-hold"
            hold_file.write_text(
                f"round=E03-R08\nhold_until={int(time.time()) + 3600}\n"
            )
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-active", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(hold_file.exists())

    def test_terra_hold_expired_deadline_is_inactive_and_self_clears(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            past = int(time.time()) - 60
            hold_file = state / "terra-budget-hold"
            hold_file.write_text(f"round=E03-R08\nhold_until={past}\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)

            expired = self.run_command(["bash", str(script), "--terra-hold-active", "E03-R08"], env=env)

            self.assertEqual(expired.returncode, 1, expired.stderr)
            self.assertFalse(hold_file.exists())

    def test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt(self) -> None:
        # The end-to-end regression: a HALT on the round the hold names must
        # make the WHOLE driver invocation a cheap no-op (no selfheal
        # session, no attempt-counter burn) while the hold is in the future
        # — this is what stops the retry loop from exhausting the 3-attempt
        # self-heal budget minutes into an 8+ hour calendar-gated wait.
        #
        # SAFETY (measured the hard way, E03-R08 H6 2nd heal, 2026-08-02):
        # selfheal.count is seeded AT the attempt budget (3), matching the
        # already-safe `test_selfheal_gives_up_after_the_configured_attempt_budget`
        # pattern above — NOT one below it. Without this driver's hold gate
        # (e.g. reverted for a RED check), a below-budget counter lets
        # `attempt_selfheal()` run for real and spawn an ACTUAL tmux+claude
        # self-heal session with --permission-mode bypassPermissions against
        # this real repo (confirmed: it happened, branch heal/E03-R08-H6-3,
        # had to be killed by hand). At-budget keeps every code path —
        # pre-fix AND post-fix — inside the exhausted-budget short-circuit,
        # which spawns nothing; only the exit code/message differ (0 + "hold
        # active" post-fix vs. 3 + "KIMERÜLT" pre-fix), which is enough to
        # tell the fix apart without ever risking a live session.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": false, \"exhausted\": true}'\n"
                "    exit 1\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            (state / "HALTED").write_text(
                "round=E03-R08\nhalt=H6\nsummary=auto-router DEFERRED: Terra daily budget is exhausted\n"
            )
            future = int(time.time()) + 3600
            (state / "terra-budget-hold").write_text(f"round=E03-R08\nhold_until={future}\n")
            (state / "selfheal.count").write_text("E03-R08|H6|3\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_SELFHEAL_MAX="3",
                PATH=f"{stub_bin}:{env['PATH']}",
            )

            held = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(held.returncode, 0, held.stderr)
            self.assertIn("felfüggesztés aktív", held.stderr)
            self.assertNotIn("ÖNJAVÍTÓ KÖR indul", held.stderr)
            self.assertNotIn("KIMERÜLT", held.stderr)
            self.assertEqual((state / "selfheal.count").read_text(), "E03-R08|H6|3\n")
            self.assertTrue((state / "HALTED").exists())

    def test_a_full_firing_retries_the_round_instead_of_healing_a_resolved_terra_wall(self) -> None:
        # The end-to-end regression for the ACTUAL production incident
        # (E03-R08 H6, 7th occurrence, 2026-08-02 18:45 UTC): by the time
        # this firing runs, an EARLIER firing already cleared the
        # `terra-budget-hold` (the daily cap just went unlimited, PR #72) —
        # so, unlike `test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`
        # above, there is NO hold file left. Only the stale `.pipeline/HALTED`
        # (written while the cap was still finite) remains. Pre-fix, the
        # driver's HALT branch doesn't re-check the condition and launches a
        # brand new self-heal session for a wall that no longer exists.
        #
        # SAFETY (same reasoning as the sibling test above): selfheal.count
        # is seeded AT the attempt budget (3), so IF the fix regresses and
        # the old code path is taken, `attempt_selfheal()` hits the
        # exhausted-budget short-circuit (logs "KIMERÜLT", returns 3) instead
        # of spawning a real tmux+claude session — this keeps a RED run of
        # this test safe to execute against this real repo.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            stub_bin = state / "bin"
            stub_bin.mkdir()
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            (state / "HALTED").write_text(
                "round=E03-R08\nhalt=H6\nsummary=auto-router DEFERRED: Terra's automatic "
                "daily budget is genuinely exhausted for utc_day=2026-08-02\n"
            )
            (state / "selfheal.count").write_text("E03-R08|H6|3\n")
            env = dict(os.environ)
            env.update(
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_SELFHEAL_MAX="3",
                PATH=f"{stub_bin}:{env['PATH']}",
            )

            result = self.run_command(["bash", str(script)], env=env)

            self.assertNotIn("ÖNJAVÍTÓ KÖR indul", result.stderr)
            self.assertNotIn("KIMERÜLT", result.stderr)
            self.assertIn("HALTED jelzés elavult volt", result.stderr)
            self.assertFalse((state / "HALTED").exists())
            self.assertFalse((state / "selfheal.count").exists())
            self.assertEqual(
                len(list(state.glob("healed-E03-R08-*.txt"))),
                1,
                "a stale halt-ot archiválni kell, nem eldobni",
            )

    def test_terra_hold_if_exhausted_writes_the_hold_file_when_terra_status_reports_exhausted(self) -> None:
        # MÉRT gyökérok (E03-R08 H6, 2. önjavítás, 2026-08-02, ugyanaz a halt
        # 4x egy nap alatt): `terra_hold_if_exhausted()`-ben a
        # `status_json=$(terra_status_json) || return 0` BÁRMILYEN nemnulla
        # exit-re kilépett — de a `model-router.py terra-status` a
        # DOKUMENTÁLT viselkedése szerint (HANDOFF.md) pontosan akkor tér
        # vissza nemnulla exit-tel, amikor exhausted=true. Emiatt a hold-fájl
        # SOHA nem íródott ki, holott három korábbi heal-session is azt
        # hitte (a saját szövegében), hogy a hold aktiválódik. Ez a teszt a
        # tényleges ÍRÓ függvényt (`terra_hold_if_exhausted`) hívja végig egy
        # PATH-stub `python3`-mal, ami a `terra-status` valódi mért
        # viselkedését szimulálja (exhausted JSON, exit 1) — a korábbi
        # `test_terra_hold_active_test_hook_matches_round_and_future_timestamp`
        # csak az OLVASÓ függvényt (`terra_hold_active_for`) tesztelte, kézzel
        # megírt hold-fájllal, ezért nem fogta meg ezt a hibát.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            stub_bin = directory / "bin"
            stub_bin.mkdir()
            next_epoch = int(time.time()) + 3600
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                f"    printf '{{\"exhausted\": true, \"next_reset_epoch\": {next_epoch}}}'\n"
                "    exit 1\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(directory)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-if-exhausted", "E03-R08"], env=env
            )

            hold_file = directory / "terra-budget-hold"
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(
                hold_file.exists(),
                "terra_hold_if_exhausted nem írta ki a hold-fájlt kimerült Terra-budget mellett",
            )
            content = hold_file.read_text()
            self.assertIn("round=E03-R08", content)
            self.assertIn(f"hold_until={next_epoch}", content)

    def test_terra_hold_writer_is_a_no_op_under_unlimited_policy(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            stub_bin = directory / "bin"
            stub_bin.mkdir()
            next_epoch = int(time.time()) + 3600
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                "    printf '{\"unlimited\": true, \"exhausted\": false, "
                f"\"next_reset_epoch\": {next_epoch}}}'\n"
                "    exit 0\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(directory)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                ["bash", str(script), "--terra-hold-if-exhausted", "E03-R08"], env=env
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((directory / "terra-budget-hold").exists())

    def test_first_halt_detection_writes_the_terra_hold_without_waiting_for_a_selfheal_retry(self) -> None:
        # MÉRT gyökérok (E03-R08 H6, 6. halt ugyanazon a napon, 2026-08-02
        # 14:26-16:38 UTC): a Terra napi-hold korábban KIZÁRÓLAG
        # attempt_selfheal() retry-ágából íródott ki, az önjavító session
        # LLM-jelentésének SZÖVEGÉRE string-matchelve (`*"Terra"*"budget"*`).
        # A 16:20-16:30-as heal-kör egy MÁSIK gyökérokot javított (magát a
        # hold-író `terra_hold_if_exhausted()` függvényt, PR #70) —
        # `outcome=fixed`, nem `retry` — így ez az ág NEM futott le, a
        # hold-fájl nem íródott ki, és a 16:35-ös következő firing UGYANAZT
        # a naptár-korlátozott Terra-falat érte el újra (6. halt 16:38-kor).
        # Ez a teszt a HALT ELSŐ észlelésének útvonalát (`handle_round_halt`,
        # a `round-status`-ban `outcome=halted`-öt jelentő ELSŐ futás) hívja
        # végig egy kimerült Terra-státuszt szimuláló python3-stubbal —
        # a holdnak MÁR ekkor, bármilyen self-heal session előtt ki kell
        # íródnia, nem várhat egy retry-klasszifikációra.
        script = ROOT / "tools" / "round-pipeline.sh"
        real_python3 = shutil.which("python3")
        self.assertIsNotNone(real_python3, "python3 kell a teszthez")
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            stub_bin = directory / "bin"
            stub_bin.mkdir()
            next_epoch = int(time.time()) + 3600
            stub = stub_bin / "python3"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *model-router.py*terra-status*)\n"
                f"    printf '{{\"exhausted\": true, \"next_reset_epoch\": {next_epoch}}}'\n"
                "    exit 1\n"
                "    ;;\n"
                "  *)\n"
                f"    exec {real_python3} \"$@\"\n"
                "    ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            status_file = directory / "round-status"
            status_file.write_text(
                "outcome=halted\n"
                "halt=H6\n"
                "summary=auto router task still DEFERRED (mandatory Terra high-risk review) "
                "— Terra's daily budget is genuinely exhausted for utc_day=2026-08-02\n"
            )
            session_log = directory / "session-E03-R08-test.log"
            session_log.write_text("")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(directory)
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = self.run_command(
                [
                    "bash",
                    str(script),
                    "--handle-round-halt",
                    "E03-R08",
                    str(status_file),
                    str(session_log),
                ],
                env=env,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((directory / "HALTED").exists())
            hold_file = directory / "terra-budget-hold"
            self.assertTrue(
                hold_file.exists(),
                "a HALT első észlelése nem írta ki a Terra-holdot — a következő firing "
                "önjavítási kísérlet elköltése nélkül újra nekifutna ugyanennek a falnak",
            )
            content = hold_file.read_text()
            self.assertIn("round=E03-R08", content)
            self.assertIn(f"hold_until={next_epoch}", content)

    def test_gate_fingerprint_covers_the_test_count_and_the_gate_artifacts(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        fingerprint = self.run_command(["bash", str(script), "--gate-fingerprint"])

        self.assertEqual(fingerprint.returncode, 0, fingerprint.stderr)
        count = int(fingerprint.stdout.split("tests=", 1)[1].split()[0])
        self.assertGreater(count, 100)
        for artifact in (
            "tools/round-gate.sh",
            ".github/workflows/build-apk.yml",
            ".github/workflows/router-ci.yml",
        ):
            self.assertIn(f"{artifact}:", fingerprint.stdout)
            self.assertNotIn(f"{artifact}:hiányzik", fingerprint.stdout)

    def make_fake_gh(self, directory: Path) -> Path:
        # A H-GATEGUARD-teszteknek NEM szabad élő hálózati `gh`-hívástól
        # függenie (a router-ci.yml futtatója nincs `gh auth`-olva) — ezért egy
        # PATH-on elé tolt stubot adunk, ami a valós `gh pr list`/`gh pr view`
        # helyett a FAKE_GH_* env-változókat visszhangozza. A git-diffek maguk
        # a VALÓDI repó VALÓDI, már merge-elt commitjain futnak (lásd lent).
        fake_gh = directory / "gh"
        fake_gh.write_text(
            "#!/usr/bin/env bash\n"
            "case \"$1 $2\" in\n"
            "  \"pr list\") printf '%s\\n' \"${FAKE_GH_PR_NUMBER:-}\" ;;\n"
            "  \"pr view\") printf '%s\\n' \"${FAKE_GH_MERGE_SHA:-}\" ;;\n"
            "  *) echo \"fake-gh: unsupported invocation: $*\" >&2; exit 1 ;;\n"
            "esac\n"
        )
        fake_gh.chmod(0o755)
        return directory

    def test_heal_pr_number_resolves_the_deterministic_heal_branch_via_gh_pr_list(self) -> None:
        # A heal branch neve determinisztikus (heal/{ROUND}-{HALT_CODE}-
        # {ATTEMPT}, docs/execution/pipeline-selfheal-prompt.md) -- ez a
        # H-GATEGUARD hamis-pozitívjának javítási alapja (lásd lent). A `gh`
        # hívást stuboljuk: a router-ci.yml futtatója nincs `gh auth`-olva,
        # élő hálózati hívástól a teszt nem függhet (mérve: e nélkül a
        # stub nélkül ez a teszt CI-ban `gh`-hiba miatt üresen bukik, nem a
        # függvény logikáján). Manuálisan, éles `gh`-val ELLENŐRIZVE (docs/
        # LESSONS.md L55): `heal/E03-R05-H6-1` valóban a #61 PR-re old fel.
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            bin_dir = self.make_fake_gh(Path(directory_name))
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")

            env["FAKE_GH_PR_NUMBER"] = "61"
            found = self.run_command(
                ["bash", str(script), "--heal-pr-number", "heal/E03-R05-H6-1"], env=env
            )
            self.assertEqual(found.stdout.strip(), "61", found.stdout + found.stderr)

            env["FAKE_GH_PR_NUMBER"] = ""
            missing = self.run_command(
                ["bash", str(script), "--heal-pr-number", "heal/does-not-exist-1"], env=env
            )
            self.assertEqual(missing.stdout.strip(), "", missing.stdout + missing.stderr)

    def make_gate_guard_fixture_commit(self, updates: dict[str, str]) -> str:
        # heal_pr_gate_violation() a `merge_sha^..merge_sha`-t EBBEN a
        # checkout-ban diffeli (repo_root a szkript saját helyére van
        # kötve) -- egy külön, ideiglenes git repó tehát nem adna neki
        # feldolgozható SHA-kat. Ehelyett egy VALÓDI, feloldható commit
        # OBJEKTUMOT építünk a checkout jelenlegi valódi HEAD-je fölé
        # plumbing-parancsokkal, egy privát GIT_INDEX_FILE-on át (a valódi
        # indexet/munkafát és minden ref/branch-et érintetlenül hagyva) --
        # ez CI shallow (fetch-depth=1) klónjában is működik, mert csak a
        # HEAD-re van szüksége, nem tetszőleges régi történelemre (a
        # `6d61e23`/`3b4707f` mért, valódi commitokra hivatkozó korábbi
        # verzió pont ezért bukott CI-ban: a shallow klón nem tartalmazta
        # őket — docs/LESSONS.md L55).
        with tempfile.TemporaryDirectory() as scratch_dir:
            index_file = Path(scratch_dir) / "index"
            env = dict(os.environ, GIT_INDEX_FILE=str(index_file))
            subprocess.run(
                ["git", "read-tree", "HEAD"], cwd=ROOT, env=env, check=True, capture_output=True
            )
            for path, content in updates.items():
                blob = subprocess.run(
                    ["git", "hash-object", "-w", "--stdin"],
                    cwd=ROOT, env=env, input=content, text=True, capture_output=True, check=True,
                ).stdout.strip()
                subprocess.run(
                    ["git", "update-index", "--add", "--cacheinfo", f"100644,{blob},{path}"],
                    cwd=ROOT, env=env, check=True, capture_output=True,
                )
            tree = subprocess.run(
                ["git", "write-tree"], cwd=ROOT, env=env, check=True, capture_output=True, text=True,
            ).stdout.strip()
            # `commit-tree` needs an author/committer identity; a fresh CI
            # runner has no `user.name`/`user.email` configured (mérve: ez a
            # 2. CI-only bukás, exit 128 "empty ident" a router-ci.yml
            # runneren), ezért explicit GIT_*_NAME/EMAIL-t adunk, nem a
            # környezet globális git configjára támaszkodva.
            commit_env = dict(
                os.environ,
                GIT_AUTHOR_NAME="gate-guard-test",
                GIT_AUTHOR_EMAIL="gate-guard-test@example.invalid",
                GIT_COMMITTER_NAME="gate-guard-test",
                GIT_COMMITTER_EMAIL="gate-guard-test@example.invalid",
            )
            commit = subprocess.run(
                ["git", "commit-tree", tree, "-p", "HEAD", "-m", "gate-guard test fixture (not a real round)"],
                cwd=ROOT, env=commit_env, check=True, capture_output=True, text=True,
            ).stdout.strip()
            return commit

    def test_heal_pr_gate_violation_ignores_a_clean_diff_and_catches_a_gate_touch(self) -> None:
        # RED-ELŐZMÉNY (E03-R05, a H6 heal UTÁNI H-GATEGUARD halt, mérve
        # 2026-08-02): a régi őrszem a teljes main előtte/utána ujjlenyomatát
        # hasonlította össze, ezért hamisan gyanúsította a H6 heal saját,
        # tiszta PR-jét (#61 -- valójában csak az orchestrátor-promptot, egy
        # tesztet és egy ÚJ segédscriptet módosított), mert a heal FUTÁSA
        # KÖZBEN egy tőle FÜGGETLEN, jogos commit (8715773, ADR 0115)
        # módosította a router-ci.yml-t. docs/LESSONS.md L55.
        #
        # Az új őrszem a heal SAJÁT PR-diffjét (merge_sha^..merge_sha) nézi,
        # ezért immunis erre. Két szintetikus, de a valós PR-alakot tükröző
        # fixture-commitot építünk a checkout valódi HEAD-je fölé (lásd
        # make_gate_guard_fixture_commit): az egyik csak egy saját, ártalmatlan
        # fájlt érint (mint a heal saját, tiszta PR-je), a másik a VALÓDI
        # tools/round-gate.sh-t módosítja (mint egy tényleg mércét gyengítő
        # diff).
        script = ROOT / "tools" / "round-pipeline.sh"
        clean_sha = self.make_gate_guard_fixture_commit(
            {"tools/tests/__gate_guard_fixture_clean__.md": "gate-guard test fixture: a clean heal PR\n"}
        )
        real_round_gate = (ROOT / "tools" / "round-gate.sh").read_text()
        violation_sha = self.make_gate_guard_fixture_commit(
            {"tools/round-gate.sh": real_round_gate + "\n# gate-guard test fixture touch\n"}
        )

        with tempfile.TemporaryDirectory() as directory_name:
            bin_dir = self.make_fake_gh(Path(directory_name))
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")

            env["FAKE_GH_MERGE_SHA"] = clean_sha
            clean = self.run_command(["bash", str(script), "--heal-pr-gate-violation", "999"], env=env)
            self.assertEqual(clean.returncode, 1, clean.stdout + clean.stderr)

            env["FAKE_GH_MERGE_SHA"] = violation_sha
            caught = self.run_command(["bash", str(script), "--heal-pr-gate-violation", "999"], env=env)
            self.assertEqual(caught.returncode, 0, caught.stdout + caught.stderr)
            self.assertIn("round-gate.sh", caught.stdout)

    def test_orchestrator_falls_back_to_terra_only_while_claude_is_blocked(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            block = state / "claude-blocked-until"

            default = self.run_command(["bash", str(script), "--orchestrator-engine"], env=env)
            block.write_text("4102444800\n")   # 2100-01-01: érvényes zárlat
            blocked = self.run_command(["bash", str(script), "--orchestrator-engine"], env=env)
            block.write_text("1000000000\n")   # 2001: lejárt zárlat
            expired = self.run_command(["bash", str(script), "--orchestrator-engine"], env=env)
            expired_file_cleaned = not block.exists()
            block.write_text("4102444800\n")
            switched_off = self.run_command(
                ["bash", str(script), "--orchestrator-engine"],
                env={**env, "PIPELINE_FALLBACK_ENGINE": "none"},
            )

            self.assertEqual(default.stdout.strip(), "claude")
            self.assertEqual(blocked.stdout.strip(), "terra")
            self.assertEqual(expired.stdout.strip(), "claude")
            self.assertTrue(expired_file_cleaned, "a lejárt zárlatot a driver takarítja")
            self.assertEqual(switched_off.stdout.strip(), "claude")

    def test_only_real_quota_messages_trigger_the_engine_switch(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        quota_logs = (
            "Claude usage limit reached. Your limit will reset at 3pm.",
            "Error: quota exceeded for this organization",
            "You are out of credits — upgrade to continue",
        )
        # Hamis pozitív ellen: a promptok maguk beszélnek kvótáról és limitről.
        innocent_logs = (
            "a kvóta helyreállása után ugyanaz a task folytatható",
            "MiniMax 429/quota/5xx esetén nem indíthatsz közvetlen fallbacket",
            "Traceback (most recent call last): RuntimeError: gate failed",
        )
        with tempfile.TemporaryDirectory() as directory_name:
            log_file = Path(directory_name) / "session.log"
            for text in quota_logs:
                with self.subTest(quota=text):
                    log_file.write_text(text)
                    hit = self.run_command(
                        ["bash", str(script), "--claude-limit-check", str(log_file)]
                    )
                    self.assertEqual(hit.returncode, 0)
            for text in innocent_logs:
                with self.subTest(innocent=text):
                    log_file.write_text(text)
                    miss = self.run_command(
                        ["bash", str(script), "--claude-limit-check", str(log_file)]
                    )
                    self.assertNotEqual(miss.returncode, 0)

    def test_codex_preamble_maps_the_claude_only_concepts(self) -> None:
        preamble = (
            ROOT / "docs" / "execution" / "pipeline-codex-orchestrator-preamble.md"
        ).read_text()
        # A Codexnek nincs skill-rendszere: a skilleket fájlként kell olvasnia.
        self.assertIn(".claude/skills/sdd-round-driver/SKILL.md", preamble)
        self.assertIn(".claude/skills/sdd-round-review/SKILL.md", preamble)
        self.assertIn("AGENTS.md", preamble)
        # A kapu és a jelzés-kötelezettség nem lazul a másik motoron sem.
        self.assertIn("zöld kapu", preamble)
        self.assertIn("kör-jelzés", preamble)

    def test_fallback_launches_terra_home_and_keeps_implementer_routing(self) -> None:
        driver = (ROOT / "tools" / "round-pipeline.sh").read_text()
        # A Terra a saját CODEX_HOME-jában él (ott a default gpt-5.6-terra).
        self.assertIn("CODEX_HOME=$codex_home", driver)
        self.assertIn(".codex-terra", driver)
        # MÉRVE 2026-08-02: `codex exec` a pane TTY-járól "Reading additional
        # input from stdin..."-nel VÁRAKOZIK, ha a stdin nyitva marad — a
        # tmux-ban indított fallback így örökre beragadna.
        self.assertIn("< /dev/null", driver.split("codex_bin exec", 1)[1][:200])
        # Az implementer-routing (sor `engine` oszlopa + ADR 0088 router) NEM
        # változhat a review-motor fallbackjétől — user-döntés 2026-08-02.
        self.assertIn("validate_engine \"$engine\"", driver)
        self.assertIn("ai-router-round.sh", driver)

    def make_fake_worktree(self, directory: Path) -> tuple[Path, Path, Path]:
        worktree = directory / "worktree"
        (worktree / "tools").mkdir(parents=True)
        (worktree / "docs" / "rounds").mkdir(parents=True)
        shutil.copy2(ROOT / "tools" / "ai-router-round.sh", worktree / "tools" / "ai-router-round.sh")
        shutil.copy2(ROOT / "tools" / "codex-signal.sh", worktree / "tools" / "codex-signal.sh")
        brief = worktree / "docs" / "rounds" / "e03-r01-fake.md"
        brief.write_text("# Fake task\n")
        fake_router = worktree / "tools" / "model-router.py"
        fake_router.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "counter = Path(os.environ[\"FAKE_ROUTER_COUNT\"])\n"
            "count = int(counter.read_text()) if counter.exists() else 0\n"
            "counter.write_text(str(count + 1))\n"
            "result = Path(sys.argv[sys.argv.index(\"--result-json\") + 1])\n"
            "status = os.environ.get(\"FAKE_ROUTER_STATUS\", \"READY_FOR_REVIEW\")\n"
            "reason = os.environ.get(\"FAKE_ROUTER_REASON\", \"fake result\")\n"
            "codes = {\"READY_FOR_REVIEW\": 0, \"STOPPED\": 20, \"DEFERRED\": 30, \"BLOCKED\": 40, \"INTERNAL_ERROR\": 50}\n"
            "result.parent.mkdir(parents=True, exist_ok=True)\n"
            "result.write_text(json.dumps({\"schema_version\": 1, \"status\": status, \"reason\": reason}))\n"
            "raise SystemExit(codes[status])\n"
        )
        fake_router.chmod(0o755)
        subprocess.run(["git", "init", "-q"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.email", "pipeline@example.invalid"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.name", "Pipeline Test"], cwd=worktree, check=True)
        subprocess.run(["git", "add", "."], cwd=worktree, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=worktree, check=True)
        return worktree, brief, fake_router

    def test_auto_adapter_dispatches_fake_router_once_and_redacts_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            worktree, brief, _ = self.make_fake_worktree(directory)
            counter = directory / "count"
            result_json = worktree / ".ai" / "runs" / "E03-R01" / "router-result.json"
            mirror = directory / "router-status"
            env = dict(os.environ)
            env.update(
                FAKE_ROUTER_COUNT=str(counter),
                FAKE_ROUTER_STATUS="READY_FOR_REVIEW",
                FAKE_ROUTER_REASON="Authorization: Bearer top-secret " + "x" * 800,
                PIPELINE_ROUTER_STATUS_FILE=str(mirror),
            )

            completed = self.run_command(
                [
                    "bash",
                    str(worktree / "tools" / "ai-router-round.sh"),
                    "run",
                    str(worktree),
                    str(brief.relative_to(worktree)),
                    str(result_json),
                ],
                cwd=worktree,
                env=env,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(counter.read_text(), "1")
            signal = (worktree / ".codex-round-status").read_text()
            self.assertIn("status=progress", signal)
            self.assertIn("router_status=READY_FOR_REVIEW", signal)
            self.assertNotIn("top-secret", signal)
            self.assertLess(len(signal), 1200)
            self.assertEqual(mirror.read_text(), signal)

    def test_signal_resolves_git_state_from_the_worktree_not_the_callers_cwd(self) -> None:
        # Mért reprodukció (E02-R21, H6, docs/LESSONS.md L42): az
        # orchestrátor a SAJÁT checkoutjából, `cd` nélkül, abszolút
        # útvonalon hívja a `codex-signal.sh`-t (lásd
        # `tools/ai-router-round.sh:50`) -- a `git rev-parse
        # --show-toplevel` a hívó folyamat öröklött cwd-jét oldja fel, nem a
        # munkapéldányt, ezért a `branch=`/`head=`/`dirty_files=` mezők a
        # ROSSZ repót mérték.
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            worktree, _, _ = self.make_fake_worktree(directory)
            subprocess.run(["git", "checkout", "-qb", "round-branch"], cwd=worktree, check=True)
            (worktree / "marker.txt").write_text("round work\n")
            subprocess.run(["git", "add", "marker.txt"], cwd=worktree, check=True)
            subprocess.run(["git", "commit", "-qm", "round work"], cwd=worktree, check=True)
            worktree_head = subprocess.run(
                ["git", "rev-parse", "--short", "HEAD"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()

            caller = directory / "caller-repo"
            caller.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=caller, check=True)
            subprocess.run(["git", "config", "user.email", "caller@example.invalid"], cwd=caller, check=True)
            subprocess.run(["git", "config", "user.name", "Caller"], cwd=caller, check=True)
            (caller / "readme.txt").write_text("unrelated repo\n")
            subprocess.run(["git", "add", "readme.txt"], cwd=caller, check=True)
            subprocess.run(["git", "commit", "-qm", "unrelated"], cwd=caller, check=True)

            script = worktree / "tools" / "codex-signal.sh"
            completed = self.run_command(
                ["bash", str(script), "progress", "safe summary"], cwd=caller
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            signal = (worktree / ".codex-round-status").read_text()
            self.assertIn("branch=round-branch", signal)
            self.assertIn(f"head={worktree_head}", signal)

    def test_router_status_mapping_is_stable(self) -> None:
        expected = {
            "READY_FOR_REVIEW": "progress",
            "STOPPED": "stopped",
            "DEFERRED": "blocked",
            "BLOCKED": "blocked",
            "INTERNAL_ERROR": "blocked",
        }
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            worktree, _, _ = self.make_fake_worktree(directory)
            script = worktree / "tools" / "codex-signal.sh"
            for router_status, signal_status in expected.items():
                with self.subTest(router_status=router_status):
                    completed = self.run_command(
                        ["bash", str(script), router_status, "safe summary"], cwd=worktree
                    )
                    self.assertEqual(completed.returncode, 0, completed.stderr)
                    signal = (worktree / ".codex-round-status").read_text()
                    self.assertIn(f"status={signal_status}", signal)
                    self.assertIn(f"router_status={router_status}", signal)

    def test_pipeline_status_only_prints_sanitized_router_signal(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            state = directory / "state"
            state.mkdir()
            (state / "router-status").write_text(
                "status=progress\nrouter_status=READY_FOR_REVIEW\nsummary=redacted safe\n"
                "unexpected_prompt=do not print me\n"
            )
            queue = directory / "queue.tsv"
            queue.write_text("E03-R01\tdocs/brief.md\tauto\t0089\tpending\n")
            env = dict(os.environ)
            env.update(PIPELINE_STATE_DIR=str(state), PIPELINE_QUEUE_FILE=str(queue))

            completed = self.run_command(
                ["bash", str(ROOT / "tools" / "pipeline-status.sh")], env=env
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("READY_FOR_REVIEW", completed.stdout)
            self.assertNotIn("do not print me", completed.stdout)


if __name__ == "__main__":
    unittest.main()
