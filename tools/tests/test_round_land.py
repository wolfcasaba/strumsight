"""Hermetikus mérce az ADR 0313 szerinti kör-landolóhoz.

A fixture helyi bare ``origin``-t és ``gh``/gate csonkokat használ. Így a
tesztek nem érintik az élő munkafát, hálózatot vagy GitHubot.
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAND = ROOT / "tools" / "round-land.sh"
ROUND = "E99-R20"


def git(repo: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", *arguments], cwd=repo, check=True, capture_output=True, text=True
    )
    return completed.stdout.strip()


def write_commit(repo: Path, relative: str, text: str, message: str) -> None:
    path = repo / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    git(repo, "add", relative)
    git(repo, "commit", "-q", "-m", message)


class RoundLandTest(unittest.TestCase):
    maxDiff = None

    def _fixture(self) -> tuple[Path, Path, Path, dict[str, str]]:
        self.assertTrue(LAND.exists(), "RED: a round-land.sh még nem létezik")
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        seed = root / "seed"
        seed.mkdir()
        git(seed, "init", "-q", "-b", "main")
        git(seed, "config", "user.email", "land@example.invalid")
        git(seed, "config", "user.name", "Land Test")

        for name in ("round-land.sh", "round-merge-lock.sh", "safe-force-push.sh", "codex-signal.sh"):
            destination = seed / "tools" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / "tools" / name, destination)
            destination.chmod(0o755)
        (seed / "tools" / "round-gate.sh").write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "printf 'gate %s\\n' \"$*\" >> \"$LAND_EVENTS\"\n"
            "exit \"${ROUND_LAND_GATE_EXIT:-0}\"\n",
            encoding="utf-8",
        )
        (seed / "tools" / "round-gate.sh").chmod(0o755)
        for relative, text in {
            ".gitignore": ".codex-round-status\n.pipeline/\n",
            "HANDOFF.md": "base handoff\n",
            "docs/LESSONS.md": "base lesson\n",
            "docs/rounds/e99-r20-test.md": "base brief\n",
            "tools/round-pipeline.sh": "base pipeline\n",
            "lib/example.dart": "base source\n",
            "docs/execution/new.md": "base document\n",
        }.items():
            path = seed / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        git(seed, "add", ".gitignore", "tools", "HANDOFF.md", "docs", "lib")
        git(seed, "commit", "-q", "-m", "base")

        bare = root / "origin.git"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], check=True)
        git(seed, "remote", "add", "origin", str(bare))
        git(seed, "push", "-q", "-u", "origin", "main")
        work = root / "work"
        subprocess.run(["git", "clone", "-q", str(bare), str(work)], check=True)
        git(work, "config", "user.email", "work@example.invalid")
        git(work, "config", "user.name", "Work Test")
        git(work, "checkout", "-q", "-b", "round")
        git(work, "push", "-q", "-u", "origin", "round")

        bin_dir = root / "bin"
        bin_dir.mkdir()
        (bin_dir / "gh").write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "printf 'gh %s\\n' \"$*\" >> \"$LAND_EVENTS\"\n"
            "if [ \"${1:-}\" = pr ] && [ \"${2:-}\" = view ]; then\n"
            "  base=${GH_PR_BASE_REF:-main}\n"
            "  head_ref=${GH_PR_HEAD_REF:-round}\n"
            "  head_oid=${GH_PR_HEAD_OID:-$(git rev-parse HEAD)}\n"
            "  if [[ \" $* \" == *\" --jq \"* ]]; then\n"
            "    printf '%s\\t%s\\t%s\\n' \"$base\" \"$head_ref\" \"$head_oid\"\n"
            "  else\n"
            "    printf '{\\\"baseRefName\\\":\\\"%s\\\",\\\"headRefName\\\":\\\"%s\\\",\\\"headRefOid\\\":\\\"%s\\\"}\\n' \"$base\" \"$head_ref\" \"$head_oid\"\n"
            "  fi\n"
            "  exit 0\n"
            "fi\n",
            encoding="utf-8",
        )
        (bin_dir / "gh").chmod(0o755)
        events = root / "events.log"
        environment = dict(
            os.environ,
            PATH=f"{bin_dir}:{os.environ['PATH']}",
            LAND_EVENTS=str(events),
            PIPELINE_STATE_DIR=str(root / ".pipeline"),
            ROUND_MERGE_LOCK_WAIT="1",
            GIT_EDITOR="true",
        )
        return root, bare, work, environment

    def _other(self, root: Path, bare: Path, branch: str = "main") -> Path:
        other = root / f"other-{branch}"
        subprocess.run(["git", "clone", "-q", str(bare), str(other)], check=True)
        git(other, "config", "user.email", "other@example.invalid")
        git(other, "config", "user.name", "Other Test")
        git(other, "checkout", "-q", branch)
        return other

    def _run(self, work: Path, environment: dict[str, str], *gate_tests: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", "tools/round-land.sh", "--pr", "42", "--round", ROUND, *gate_tests],
            cwd=work,
            text=True,
            capture_output=True,
            env=environment,
            timeout=60,
        )

    @staticmethod
    def _events(root: Path) -> str:
        path = root / "events.log"
        return path.read_text(encoding="utf-8") if path.exists() else ""

    def _assert_blocked_without_merge(self, root: Path, work: Path, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("gh pr merge", self._events(root))
        signal = (work / ".codex-round-status").read_text(encoding="utf-8")
        self.assertIn("status=blocked", signal)

    def test_clean_branch_skips_rebase_runs_default_gate_and_merges(self) -> None:
        root, _bare, work, environment = self._fixture()
        write_commit(work, "feature.txt", "round change\n", "round change")

        result = self._run(work, environment)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self._events(root)
        self.assertIn("gh pr view 42 --json baseRefName,headRefName,headRefOid", events)
        self.assertIn("gate test/tooling/architecture_allowlist_guard_test.dart", events)
        self.assertIn("gh pr merge 42 --squash --delete-branch", events)
        signal = (work / ".codex-round-status").read_text(encoding="utf-8")
        self.assertIn("status=done", signal)
        self.assertIn("mechanikusan feloldva: nincs", signal)

    def test_rebase_requires_a_fresh_exact_sha_ci_before_merging(self) -> None:
        root, bare, work, environment = self._fixture()
        write_commit(work, "feature.txt", "round change\n", "round change")
        measured_head = git(work, "rev-parse", "HEAD")
        other = self._other(root, bare)
        write_commit(other, "main.txt", "upstream change\n", "upstream change")
        git(other, "push", "-q", "origin", "main")

        result = self._run(work, environment)

        self._assert_blocked_without_merge(root, work, result)
        self.assertNotEqual(git(work, "rev-parse", "HEAD"), measured_head)
        self.assertIn("gate test/tooling/architecture_allowlist_guard_test.dart", self._events(root))
        signal = (work / ".codex-round-status").read_text(encoding="utf-8")
        self.assertIn("exact-SHA CI", signal)

    def test_mismatched_pr_metadata_blocks_before_landing_actions(self) -> None:
        mismatches = (
            ("base", {"GH_PR_BASE_REF": "release"}),
            ("head branch", {"GH_PR_HEAD_REF": "different-round"}),
            ("head SHA", {"GH_PR_HEAD_OID": "0" * 40}),
        )
        for name, overrides in mismatches:
            with self.subTest(name=name):
                root, _bare, work, environment = self._fixture()
                write_commit(work, "feature.txt", "round change\n", "round change")
                measured_head = git(work, "rev-parse", "HEAD")
                environment.update(overrides)

                result = self._run(work, environment)

                self._assert_blocked_without_merge(root, work, result)
                self.assertEqual(git(work, "rev-parse", "HEAD"), measured_head)
                events = self._events(root)
                self.assertIn("gh pr view 42 --json baseRefName,headRefName,headRefOid", events)
                self.assertNotIn("gate ", events)

    def test_handoff_conflict_unions_both_sections_without_markers(self) -> None:
        root, bare, work, environment = self._fixture()
        other = self._other(root, bare)
        write_commit(other, "HANDOFF.md", "main handoff\n", "main handoff")
        git(other, "push", "-q", "origin", "main")
        write_commit(work, "HANDOFF.md", "round handoff\n", "round handoff")

        result = self._run(work, environment)

        self._assert_blocked_without_merge(root, work, result)
        text = (work / "HANDOFF.md").read_text(encoding="utf-8")
        self.assertIn("main handoff", text)
        self.assertIn("round handoff", text)
        self.assertNotIn("<<<<<<<", text)
        self.assertIn("gate test/tooling/architecture_allowlist_guard_test.dart", self._events(root))
        signal = (work / ".codex-round-status").read_text(encoding="utf-8")
        self.assertIn("mechanikusan feloldva: HANDOFF.md", signal)
        self.assertIn("exact-SHA CI", signal)

    def test_own_brief_conflict_keeps_the_fresh_main_version(self) -> None:
        root, bare, work, environment = self._fixture()
        other = self._other(root, bare)
        write_commit(other, "docs/rounds/e99-r20-test.md", "main brief\n", "main brief")
        git(other, "push", "-q", "origin", "main")
        write_commit(work, "docs/rounds/e99-r20-test.md", "round brief\n", "round brief")

        result = self._run(work, environment)

        self._assert_blocked_without_merge(root, work, result)
        self.assertEqual((work / "docs/rounds/e99-r20-test.md").read_text(encoding="utf-8"), "main brief\n")
        self.assertIn("exact-SHA CI", (work / ".codex-round-status").read_text(encoding="utf-8"))

    def test_semantic_tool_conflict_aborts_rebase_and_blocks(self) -> None:
        root, bare, work, environment = self._fixture()
        other = self._other(root, bare)
        write_commit(other, "tools/round-pipeline.sh", "main pipeline\n", "main pipeline")
        git(other, "push", "-q", "origin", "main")
        write_commit(work, "tools/round-pipeline.sh", "round pipeline\n", "round pipeline")

        result = self._run(work, environment)

        self._assert_blocked_without_merge(root, work, result)
        self.assertFalse((work / ".git" / "rebase-merge").exists())
        self.assertEqual(git(work, "status", "--porcelain"), "")

    def test_mixed_mechanical_and_source_conflicts_are_semantic(self) -> None:
        root, bare, work, environment = self._fixture()
        other = self._other(root, bare)
        write_commit(other, "HANDOFF.md", "main handoff\n", "main handoff")
        write_commit(other, "lib/example.dart", "main source\n", "main source")
        git(other, "push", "-q", "origin", "main")
        write_commit(work, "HANDOFF.md", "round handoff\n", "round handoff")
        write_commit(work, "lib/example.dart", "round source\n", "round source")

        self._assert_blocked_without_merge(root, work, self._run(work, environment))

    def test_unknown_document_conflict_is_fail_closed(self) -> None:
        root, bare, work, environment = self._fixture()
        other = self._other(root, bare)
        write_commit(other, "docs/execution/new.md", "main document\n", "main document")
        git(other, "push", "-q", "origin", "main")
        write_commit(work, "docs/execution/new.md", "round document\n", "round document")

        self._assert_blocked_without_merge(root, work, self._run(work, environment))

    def test_red_gate_blocks_before_push_or_merge(self) -> None:
        root, _bare, work, environment = self._fixture()
        write_commit(work, "feature.txt", "round change\n", "round change")
        environment["ROUND_LAND_GATE_EXIT"] = "9"

        self._assert_blocked_without_merge(root, work, self._run(work, environment, "--gate-test", "test/custom_test.dart"))
        self.assertIn("gate test/custom_test.dart", self._events(root))

    def test_safe_push_remote_only_refusal_blocks_without_merge(self) -> None:
        root, bare, work, environment = self._fixture()
        other = self._other(root, bare, "round")
        write_commit(other, "remote.txt", "remote-only\n", "remote only")
        git(other, "push", "-q", "origin", "round")
        write_commit(work, "local.txt", "local-only\n", "local only")

        self._assert_blocked_without_merge(root, work, self._run(work, environment))


class OrchestratorPromptLandTest(unittest.TestCase):
    def test_merge_instruction_delegates_to_the_land_script(self) -> None:
        prompt = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text(encoding="utf-8")
        self.assertIn("tools/round-land.sh --pr <PR> --round {{ROUND}}", prompt)
        self.assertIn("mechanikus konfliktus-osztály", prompt)


if __name__ == "__main__":
    unittest.main()
