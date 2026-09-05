import datetime as dt
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-pipeline.sh"


class SelfhealEscalationTest(unittest.TestCase):
    """GOV-09: the final self-heal attempt varies its engine; halt alerts throttle.

    A cellák a Sol-pin ELŐTTI, kvóta-tudatos Claude→Terra heal-utat mérik,
    ezért explicit env-pinnel futnak (`PIPELINE_ORCH_ROTATION_FILE=/dev/null`
    + `PIPELINE_ORCH_ROTATION=alternate`). Pin nélkül a commitolt
    `docs/execution/orchestrator-rotation` (`sol`, user-döntés 2026-08-20)
    érvényesülne, és a heal rögzített identitása a nyilvántartás `sol` sora
    lenne — azt a Sol-pines utat a `test_sol_terra_both_slots.py` méri.
    """

    def run_attempt(
        self,
        state: Path,
        *,
        attempts: int,
        now: int,
        halted_at: int | None = None,
        last_reminder: int | None = None,
    ) -> tuple[subprocess.CompletedProcess[str], list[str], Path]:
        halt_epoch = halted_at if halted_at is not None else now - 60
        halted_at_text = dt.datetime.fromtimestamp(halt_epoch, tz=dt.timezone.utc).isoformat()
        (state / "HALTED").write_text(
            "round=E99-R15\n"
            "halt=H-NOSIGNAL\n"
            "summary=fixture halt\n"
            f"halted_at={halted_at_text}\n",
            encoding="utf-8",
        )
        (state / "selfheal.count").write_text(
            f"E99-R15|H-NOSIGNAL|{attempts}\n", encoding="utf-8"
        )
        if last_reminder is not None:
            (state / "halt-reminder-last").write_text(
                f"E99-R15|H-NOSIGNAL|{last_reminder}\n", encoding="utf-8"
            )

        registry = state / "engine-registry.tsv"
        sonnet_config = state / "sonnet"
        codex_config = state / "codex"
        terra_config = state / "terra"
        for config in (sonnet_config, codex_config, terra_config):
            config.mkdir()
        registry.write_text(
            "name\tharness\tconfig_dir\tmodel\tauth_env\tauth_file\n"
            f"sonnet-impl\tclaude\t{sonnet_config}\tclaude-sonnet-5\t-\t-\n"
            f"terra\tcodex\t{terra_config}\tgpt-5.6-terra\t-\t-\n"
            f"codex\tcodex\t{codex_config}\tgpt-5.6-terra\t-\t-\n",
            encoding="utf-8",
        )
        notifications = state / "notifications"
        launched_engine = state / "launched-engine"
        prompt_copy = state / "prompt-copy.md"
        shell = f'''\
source <(sed -n '1,/^# --- Reviewer-függetlenség/p' "$PIPELINE_SCRIPT")
repo_root="$PIPELINE_ROOT"
heal_template="$repo_root/docs/execution/pipeline-selfheal-prompt.md"
notify() {{ printf '%s|%s|%s\\n' "$1" "$2" "${{3:-default}}" >> "$NOTIFICATIONS"; }}
inflight_add() {{ :; }}
inflight_remove() {{ :; }}
git() {{ :; }}
run_selfheal_session() {{
  printf '%s\\n' "$1" > "$LAUNCHED_ENGINE"
  cp "$3" "$PROMPT_COPY"
  printf 'outcome=retry\\nsummary=fixture retry\\n' > "$heal_status_file"
}}
run_orchestrator_session() {{
  printf 'legacy-runner\\n' > "$LAUNCHED_ENGINE"
  cp "$2" "$PROMPT_COPY"
  printf 'outcome=retry\\nsummary=fixture retry\\n' > "$heal_status_file"
}}
attempt_selfheal
'''
        environment = dict(os.environ)
        environment.update(
            PIPELINE_SCRIPT=str(SCRIPT),
            PIPELINE_ROOT=str(ROOT),
            PIPELINE_STATE_DIR=str(state),
            PIPELINE_ENGINE_REGISTRY=str(registry),
            PIPELINE_SELFHEAL_MAX="3",
            # A halt-aláírás RAG-visszakeresése (ADR 0312) MÉRVE 27,0 s / hívás,
            # ebből 24,9 s CPU; ez a cella a MOTORVÁLASZTÁST méri, nem a
            # visszakeresést. A driver élesben változatlanul futtatja
            # (E14-R13/H5 önjavító kör, 2026-09-05).
            PIPELINE_HEAL_RAG="0",
            PIPELINE_HALT_REMINDER_MIN="60",
            PIPELINE_HALT_REMINDER_MAX_H="24",
            PIPELINE_TEST_NOW=str(now),
            PIPELINE_ORCH_ROTATION_FILE="/dev/null",
            PIPELINE_ORCH_ROTATION="alternate",
            NOTIFICATIONS=str(notifications),
            LAUNCHED_ENGINE=str(launched_engine),
            PROMPT_COPY=str(prompt_copy),
        )
        completed = subprocess.run(
            ["bash", "-c", shell],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        sent = notifications.read_text(encoding="utf-8").splitlines() if notifications.exists() else []
        return completed, sent, prompt_copy

    def test_first_two_attempts_keep_the_legacy_runner_and_last_attempt_uses_a_different_model(self) -> None:
        now = int(time.time())
        expected = {0: "legacy-runner", 1: "legacy-runner", 2: "terra"}
        with tempfile.TemporaryDirectory() as directory_name:
            for previous_attempts, engine in expected.items():
                with self.subTest(previous_attempts=previous_attempts):
                    state = Path(directory_name) / str(previous_attempts)
                    state.mkdir()
                    completed, sent, prompt_copy = self.run_attempt(
                        state, attempts=previous_attempts, now=now
                    )
                    self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
                    self.assertEqual(
                        (state / "launched-engine").read_text(encoding="utf-8").strip(),
                        engine,
                    )
                    if previous_attempts == 2:
                        switch_notifications = [
                            line for line in sent if "ÖNJAVÍTÓ MOTORVÁLTÁS" in line
                        ]
                        self.assertEqual(len(switch_notifications), 1)
                        self.assertIn("sonnet-impl", switch_notifications[0])
                        self.assertIn("terra", switch_notifications[0])
                        self.assertIn("ÖNJAVÍTÓ MOTORVÁLTÁS", completed.stderr)
                        prompt = prompt_copy.read_text(encoding="utf-8")
                        self.assertIn("MÁS MOTOR", prompt)
                        self.assertIn(".pipeline/heal-*.log", prompt)

    def test_first_attempt_keeps_the_legacy_terra_fallback_when_claude_is_blocked(self) -> None:
        now = int(time.time())
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            halted_at = dt.datetime.fromtimestamp(now - 60, tz=dt.timezone.utc).isoformat()
            (state / "HALTED").write_text(
                "round=E99-R15\n"
                "halt=H-NOSIGNAL\n"
                "summary=fixture halt\n"
                f"halted_at={halted_at}\n",
                encoding="utf-8",
            )
            (state / "selfheal.count").write_text("E99-R15|H-NOSIGNAL|0\n", encoding="utf-8")

            registry = state / "engine-registry.tsv"
            sonnet_config = state / "sonnet"
            terra_config = state / "terra"
            for config in (sonnet_config, terra_config):
                config.mkdir()
            registry.write_text(
                "name\tharness\tconfig_dir\tmodel\tauth_env\tauth_file\n"
                f"sonnet-impl\tclaude\t{sonnet_config}\tclaude-sonnet-5\t-\t-\n"
                f"terra\tcodex\t{terra_config}\tgpt-5.6-terra\t-\t-\n",
                encoding="utf-8",
            )
            dispatch_kind = state / "dispatch-kind"
            fallback_command = state / "fallback-command"
            shell = f'''\
source <(sed -n '1,/^# --- Reviewer-függetlenség/p' "$PIPELINE_SCRIPT")
repo_root="$PIPELINE_ROOT"
heal_template="$repo_root/docs/execution/pipeline-selfheal-prompt.md"
notify() {{ :; }}
inflight_add() {{ :; }}
inflight_remove() {{ :; }}
git() {{ :; }}
claude_unavailable_until() {{ printf '%s\\n' "$(( PIPELINE_TEST_NOW + 3600 ))"; }}
run_tmux_session() {{
  printf 'terra-fallback\\n' > "$DISPATCH_KIND"
  printf '%s\\n' "$2" > "$FALLBACK_COMMAND"
  printf 'outcome=retry\\nsummary=fixture retry\\n' > "$4"
}}
run_selfheal_session() {{
  printf 'new-runner\\n' > "$DISPATCH_KIND"
  printf 'outcome=retry\\nsummary=fixture retry\\n' > "$5"
}}
attempt_selfheal
'''
            environment = dict(os.environ)
            environment.update(
                PIPELINE_SCRIPT=str(SCRIPT),
                PIPELINE_ROOT=str(ROOT),
                PIPELINE_STATE_DIR=str(state),
                PIPELINE_ENGINE_REGISTRY=str(registry),
                PIPELINE_SELFHEAL_MAX="3",
            # A halt-aláírás RAG-visszakeresése (ADR 0312) MÉRVE 27,0 s / hívás,
            # ebből 24,9 s CPU; ez a cella a MOTORVÁLASZTÁST méri, nem a
            # visszakeresést. A driver élesben változatlanul futtatja
            # (E14-R13/H5 önjavító kör, 2026-09-05).
            PIPELINE_HEAL_RAG="0",
                PIPELINE_TEST_NOW=str(now),
                PIPELINE_ORCH_ROTATION_FILE="/dev/null",
                PIPELINE_ORCH_ROTATION="alternate",
                # 2026-08-21 óta a script-default `none` (a GPT-kvóta
                # elfogyott); ez a cella ÉPPEN az örökölt Terra-fallback
                # gépezetét méri, ezért explicit env-vel éleszti fel.
                PIPELINE_FALLBACK_ENGINE="terra",
                PIPELINE_FALLBACK_CODEX_HOME=str(terra_config),
                CODEX_BIN="true",
                DISPATCH_KIND=str(dispatch_kind),
                FALLBACK_COMMAND=str(fallback_command),
            )

            completed = subprocess.run(
                ["bash", "-c", shell],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(dispatch_kind.read_text(encoding="utf-8").strip(), "terra-fallback")
            self.assertIn(
                f"CODEX_HOME={terra_config}",
                fallback_command.read_text(encoding="utf-8"),
            )

    def test_halt_reminders_throttle_at_the_configured_boundaries(self) -> None:
        now = int(time.time())
        cases = (
            ("below", now - 59 * 60, now - 60, 0),
            ("at", now - 60 * 60, now - 60, 1),
            ("above", now - 60 * 60, now - 25 * 60 * 60, 0),
        )
        with tempfile.TemporaryDirectory() as directory_name:
            for label, last_reminder, halted_at, expected_notifications in cases:
                with self.subTest(label=label):
                    state = Path(directory_name) / label
                    state.mkdir()
                    completed, sent, _prompt = self.run_attempt(
                        state,
                        attempts=3,
                        now=now,
                        halted_at=halted_at,
                        last_reminder=last_reminder,
                    )
                    self.assertEqual(completed.returncode, 3, completed.stdout + completed.stderr)
                    reminders = [line for line in sent if "önjavítás kimerült" in line]
                    self.assertEqual(len(reminders), expected_notifications)
                    self.assertIn("KIMERÜLT", completed.stderr)
                    if expected_notifications:
                        self.assertIn("E99-R15", reminders[0])
                        self.assertIn("H-NOSIGNAL", reminders[0])
                        self.assertIn("tools/pipeline-status.sh --resume", reminders[0])


if __name__ == "__main__":
    unittest.main()
