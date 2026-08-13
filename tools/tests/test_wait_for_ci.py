import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

# Mért gyökérok (E06-R25, H-NOSIGNAL önjavítás, 2026-08-13T13:55Z, session-napló
# .pipeline/session-E06-R25-20260813T123506-fallback.log): az orchestrátor egy
# kézzel írt `gh run list --workflow full-gate.yml ...` poll-ciklusban várt a
# CI-re (a sdd-round-driver SKILL.md §5 és a pipeline-orchestrator-prompt.md
# ajánlott mintája szerint -- `gh run watch <id>` VAGY `gh run list` ciklus,
# EGYIK sincs timeout-tal védve). 13 egymást követő hívás ~25,5s alatt tért
# vissza ("succeeded in 25478ms" .. "25643ms"), a 14. SOHA -- a session a hívás
# belsejében fagyott le, új sort többé nem írt a naplóba. A pipeline 20 perces
# log-mtime elakadás-őre (round-pipeline.sh ELAKADÁS-ŐR) csak KÍVÜLRŐL, a
# TELJES sessiont ölve tudta ezt észlelni, jóval azután, hogy a ténylegesen
# várt CI-futás (Full Gate, databaseId 31704364552) már zölden lezárult
# (13:33:34Z) -- a session 13:30 körül fagyott le, tehát a hang MAGÁBAN a
# `gh` hívásban történt, nem a workflow-ban. Két önjavító kör + több mint egy
# óra ment el emiatt.
#
# Ez a teszt EGYETLEN védtelen `gh` hívást szimulál: a fake `gh` sosem tér
# vissza magától. `tools/wait-for-ci.sh`-nak minden EGYES hívást saját
# `timeout`-tal kell védenie, hogy egy ilyen hang a HÍVÁST ölje meg, ne a
# teljes várakozást fagyassza le örökre.


def _fake_gh_hang_then_succeed(bin_dir: Path, counter_file: Path, hang_count: int) -> Path:
    fake_gh = bin_dir / "gh"
    fake_gh.write_text(
        "#!/usr/bin/env bash\n"
        "set -eu\n"
        f"counter_file={counter_file}\n"
        f"hang_count={hang_count}\n"
        "n=$(cat \"$counter_file\" 2>/dev/null || echo 0)\n"
        "n=$((n + 1))\n"
        "printf '%s' \"$n\" > \"$counter_file\"\n"
        "if [ \"$n\" -le \"$hang_count\" ]; then\n"
        "  sleep 100000\n"
        "else\n"
        "  printf 'completed\\tsuccess\\n'\n"
        "fi\n"
    )
    fake_gh.chmod(0o755)
    return fake_gh


def _fake_gh_always(bin_dir: Path, behavior: str) -> Path:
    fake_gh = bin_dir / "gh"
    body = {
        "hang": "sleep 100000\n",
        "in_progress": "printf 'in_progress\\t\\n'\n",
        "success": "printf 'completed\\tsuccess\\n'\n",
        "failure": "printf 'completed\\tfailure\\n'\n",
    }[behavior]
    fake_gh.write_text("#!/usr/bin/env bash\nset -eu\n" + body)
    fake_gh.chmod(0o755)
    return fake_gh


class WaitForCiTest(unittest.TestCase):
    def run_script(self, args, env_extra=None, timeout=20):
        env = dict(os.environ, **(env_extra or {}))
        return subprocess.run(
            ["bash", str(ROOT / "tools" / "wait-for-ci.sh"), *args],
            text=True,
            capture_output=True,
            env=env,
            timeout=timeout,
        )

    def test_a_hung_gh_call_is_killed_by_the_per_call_timeout_and_the_poll_recovers(self) -> None:
        # A MÉRT mintát reprodukálja fordítva: a fake `gh` az első 2 hívást
        # sosem fejezi be magától -- csak a szkript SAJÁT timeout-ja tudja
        # megszakítani. A 3. hívás sikeres. Ha a szkript nem védi a hívást
        # timeout-tal, ez a teszt lefagy (a subprocess.run(timeout=20) buktatja
        # explicit hibával, nem a tesztfutó egészét).
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            bin_dir = directory / "bin"
            bin_dir.mkdir()
            counter_file = directory / "gh-calls"
            _fake_gh_hang_then_succeed(bin_dir, counter_file, hang_count=2)

            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            completed = self.run_script(
                ["run-123", "30", "1"],
                env_extra={"PATH": env["PATH"], "WAIT_POLL_SECONDS": "1"},
            )

            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertIn("success", completed.stdout)
            self.assertEqual(counter_file.read_text().strip(), "3")

    def test_a_gh_call_that_never_recovers_fails_fast_and_distinctly_from_still_running(self) -> None:
        # A hang NEM ugyanaz, mint "a workflow még fut": a kilépési kódnak
        # külön kell jeleznie, hogy maga a `gh`/hálózat akadt el, és ezt
        # GYORSAN, a `max_wait` kivárása NÉLKÜL kell jeleznie.
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            bin_dir = directory / "bin"
            bin_dir.mkdir()
            _fake_gh_always(bin_dir, "hang")

            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            completed = self.run_script(
                ["run-123", "300", "1"],
                env_extra={
                    "PATH": env["PATH"],
                    "WAIT_POLL_SECONDS": "1",
                    "WAIT_CI_MAX_GH_FAILURES": "3",
                },
                timeout=20,
            )

            self.assertEqual(completed.returncode, 6, completed.stdout + completed.stderr)

    def test_still_in_progress_run_times_out_with_its_own_distinct_code(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            bin_dir = directory / "bin"
            bin_dir.mkdir()
            _fake_gh_always(bin_dir, "in_progress")

            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            completed = self.run_script(
                ["run-123", "2", "5"],
                env_extra={"PATH": env["PATH"], "WAIT_POLL_SECONDS": "1"},
            )

            self.assertEqual(completed.returncode, 4, completed.stdout + completed.stderr)
            self.assertIn("MÉG", completed.stderr)

    def test_a_completed_failure_conclusion_exits_one(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            bin_dir = directory / "bin"
            bin_dir.mkdir()
            _fake_gh_always(bin_dir, "failure")

            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            completed = self.run_script(
                ["run-123", "10", "5"],
                env_extra={"PATH": env["PATH"], "WAIT_POLL_SECONDS": "1"},
            )

            self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
            self.assertIn("failure", completed.stdout)

    def test_a_successful_run_exits_zero_promptly(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            bin_dir = directory / "bin"
            bin_dir.mkdir()
            _fake_gh_always(bin_dir, "success")

            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            completed = self.run_script(
                ["run-123", "10", "5"],
                env_extra={"PATH": env["PATH"], "WAIT_POLL_SECONDS": "1"},
            )

            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_missing_run_id_is_a_usage_error(self) -> None:
        completed = self.run_script([])
        self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()
