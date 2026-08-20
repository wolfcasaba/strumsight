"""Reviewer-independence resolver tests (ADR 0138).

Measured 2026-08-05: the legacy implementer (`codex exec`, `~/.codex`) and the
orchestrator fallback (`~/.codex-terra`) are the same `gpt-5.6-terra` model, so
under a Claude quota block Terra would review its own diff.  The driver must
move the implementer to the other engine instead, and halt rather than merge
self-reviewed work when no other engine exists.
"""

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-pipeline.sh"


class ReviewerIndependenceTest(unittest.TestCase):
    def resolve(
        self,
        queue_engine: str,
        *,
        claude_blocked: bool,
        minimax_available: bool = True,
        fallback_engine: str = "terra",
    ) -> str:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            state = directory / "state"
            home = directory / "home"
            state.mkdir()
            home.mkdir()

            if claude_blocked:
                (state / "claude-blocked-until").write_text(str(int(time.time()) + 9999))
            if minimax_available:
                (home / ".mmx").mkdir()
                (home / ".mmx" / "config.json").write_text('{"api_key": "fixture"}')

            # Ugyanaz a szivárgás, mint a rotációs tesztekben (E99-R14 H3):
            # az ambiens `PIPELINE_*` override elmozdítaná a mért alapértelmezést.
            environment = {
                key: value
                for key, value in os.environ.items()
                if not key.startswith("PIPELINE_")
            }
            environment.pop("MINIMAX_API_KEY", None)
            environment["HOME"] = str(home)
            environment["PIPELINE_STATE_DIR"] = str(state)
            environment["PIPELINE_FALLBACK_ENGINE"] = fallback_engine
            # A kvóta-fallback gépezetét (ADR 0115/0138) az `alternate`
            # rotáció alatt mérjük: a 2026-08-20-i Sol-pin default alatt a
            # reviewer a Sol, akivel a codex/terra implementer nem ütközik,
            # így ez az út nem is futna.
            environment["PIPELINE_ORCH_ROTATION"] = "alternate"

            completed = subprocess.run(
                [str(SCRIPT), "--independent-engine", queue_engine],
                capture_output=True,
                text=True,
                env=environment,
                cwd=ROOT,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            return completed.stdout.strip()

    def test_without_a_claude_block_the_queue_engine_is_untouched(self) -> None:
        for engine in ("codex", "minimax", "auto"):
            with self.subTest(engine=engine):
                self.assertEqual(self.resolve(engine, claude_blocked=False), engine)

    def test_claude_block_moves_the_codex_implementer_off_terra(self) -> None:
        # A reviewer ilyenkor Terra; az implementer nem maradhat szintén Terra.
        self.assertEqual(self.resolve("codex", claude_blocked=True), "minimax")

    def test_claude_block_leaves_an_already_independent_pairing_alone(self) -> None:
        # MiniMax implementer + Terra reviewer már független — nincs teendő.
        self.assertEqual(self.resolve("minimax", claude_blocked=True), "minimax")

    def test_auto_is_left_to_the_router_contract(self) -> None:
        self.assertEqual(self.resolve("auto", claude_blocked=True), "auto")

    def test_halt_rather_than_self_review_when_no_other_engine_exists(self) -> None:
        verdict = self.resolve("codex", claude_blocked=True, minimax_available=False)

        self.assertEqual(verdict, "HALT_INDEP")

    def test_disabled_fallback_keeps_the_queue_engine(self) -> None:
        # fallback_engine=none esetén a review-t nem a Terra viszi, tehát
        # nincs függetlenségi ütközés.
        verdict = self.resolve("codex", claude_blocked=True, fallback_engine="none")

        self.assertEqual(verdict, "codex")


class NonHealableHaltTest(unittest.TestCase):
    """`H-INDEP` and `H-GATEGUARD` must never be handed to the self-heal loop."""

    def test_both_codes_are_listed_as_non_healable(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("H-GATEGUARD | H-INDEP)", source)


if __name__ == "__main__":
    unittest.main()
