import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class RoundPipelineQueuePendingPrGuardTest(unittest.TestCase):
    """The "nyitott PR van" / "fut egy workflow" foreign-branch guards
    (round-pipeline.sh precondition section 3, `count_foreign`) only ever
    recognised a round as "ours" via `inflight_rounds()` -- which is
    populated ONLY while a session for that round is actively running, and
    is unconditionally cleared on every script exit (`trap 'inflight_remove
    ...' EXIT`).

    Measured (E99-R13, second H3 self-heal, 2026-08-15): the round's own
    orchestrator session pushed, opened PR #266, got it reviewed, then
    halted (H3) on a Router CI failure BEFORE merging -- leaving PR #266
    open when the session exited. On the very NEXT cron firing,
    `inflight_rounds()` is empty (no session is running yet -- picking which
    round to dispatch happens LATER, in section 4, well after this
    precondition already ran). `own_branches` was therefore empty, PR #266's
    branch (`sonnet-impl/e99-r13-...`) matched `ROUND_BRANCH_PATTERN`, and
    `count_foreign` counted it as foreign -- `die "nyitott PR van"` (exit 4,
    a silent, non-HALT, non-notified stall per the file's own header
    comment) on EVERY future firing, forever, since nothing under `tools/`
    ever closes a leftover PR. Fixing only the Router CI test (the halt's
    literal, reported root cause) would have left the chain silently wedged
    the moment it next tried to resume -- reproduced below against the
    pre-fix script (own_branches=[], count=1) and the fixed one
    (own_branches=[e99-r13], count=0), using the round's own real branch
    name and its real, currently-`pending` queue row.

    The fix: `docs/execution/pipeline-queue.tsv`'s own, PERSISTENT
    non-`done` row for a round is an equally valid "this is ours" signal,
    and unlike `inflight_rounds()` it survives a session boundary.
    `queue_active_branch_pattern()` folds every non-`done` queue round into
    `own_branches` alongside `inflight_branch_pattern()`'s ephemeral set.
    """

    def _run(self, directory: Path, *, queue_rows, pr_branches: str, inflight_rounds=()):
        inflight_dir = directory / "inflight"
        inflight_dir.mkdir()
        for round_id in inflight_rounds:
            (inflight_dir / round_id).touch()

        queue_file = directory / "pipeline-queue.tsv"
        queue_file.write_text("\n".join("\t".join(row) for row in queue_rows) + "\n")

        script = ROOT / "tools" / "round-pipeline.sh"
        source_functions = (
            'inflight_dir="$FAKE_INFLIGHT_DIR"\n'
            'queue_file="$FAKE_QUEUE_FILE"\n'
            "source <(sed -n '/^inflight_rounds() {/p' \"$PIPELINE_SCRIPT\")\n"
            "source <(sed -n '/^inflight_branch_pattern() {/,/^open_pr_branches=/"
            "{/^open_pr_branches=/!p}' \"$PIPELINE_SCRIPT\")\n"
            'echo "OWN_BRANCHES=$own_branches" >&2\n'
            'printf "%s\\n" "$FAKE_PR_BRANCHES" | count_foreign\n'
        )

        environment = dict(os.environ)
        environment.update(
            PIPELINE_SCRIPT=str(script),
            FAKE_INFLIGHT_DIR=str(inflight_dir),
            FAKE_QUEUE_FILE=str(queue_file),
            FAKE_PR_BRANCHES=pr_branches,
        )
        return subprocess.run(
            ["bash", "-c", source_functions],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_queue_pending_rounds_own_pr_is_not_foreign(self) -> None:
        # Real measured scenario (2026-08-15): E99-R13 is `pending` in the
        # queue, no session is currently running (empty inflight dir -- the
        # state right after a self-heal exits and before the next firing
        # picks a round), and its own halted-round PR branch is open.
        with tempfile.TemporaryDirectory() as directory_name:
            completed = self._run(
                Path(directory_name),
                queue_rows=[
                    (
                        "E99-R13",
                        "docs/rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md",
                        "codex",
                        "0254",
                        "pending",
                    )
                ],
                pr_branches="sonnet-impl/e99-r13-gov-30c-5-runner-audio-path-and-wiring",
            )
            self.assertEqual(
                completed.stdout.strip(),
                "0",
                "own pending-queue round's PR wrongly counted as foreign "
                "(this is the E99-R13 deadlock: die \"nyitott PR van\" would "
                f"fire on every future firing); stdout={completed.stdout!r} "
                f"stderr={completed.stderr!r}",
            )

    def test_done_rounds_stray_pr_is_still_foreign(self) -> None:
        # Negative control: a round already marked `done` getting a NEW,
        # unrelated open PR is still surprising and should still block --
        # the fix must not make the guard toothless.
        with tempfile.TemporaryDirectory() as directory_name:
            completed = self._run(
                Path(directory_name),
                queue_rows=[("E01-R01", "docs/rounds/e01-r01-x.md", "codex", "0001", "done")],
                pr_branches="codex/e01-r01-something-stray",
            )
            self.assertEqual(
                completed.stdout.strip(),
                "1",
                f"a done round's stray PR should still count as foreign; "
                f"stdout={completed.stdout!r} stderr={completed.stderr!r}",
            )

    def test_branch_absent_from_queue_entirely_is_still_foreign(self) -> None:
        # Negative control: a round-shaped branch that is not in OUR queue
        # at all (nor inflight) is exactly the "another driver instance is
        # running a round" case the guard exists for -- must remain foreign.
        with tempfile.TemporaryDirectory() as directory_name:
            completed = self._run(
                Path(directory_name),
                queue_rows=[
                    (
                        "E99-R13",
                        "docs/rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md",
                        "codex",
                        "0254",
                        "pending",
                    )
                ],
                pr_branches="codex/e50-r01-unrelated-round",
            )
            self.assertEqual(
                completed.stdout.strip(),
                "1",
                f"a round absent from the queue should still count as foreign; "
                f"stdout={completed.stdout!r} stderr={completed.stderr!r}",
            )


if __name__ == "__main__":
    unittest.main()
