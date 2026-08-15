"""Regression guard for the E99-R13 self-heal (ADR 0112, halt H3, 2026-08-15).

Measured root cause of the halt: ADR 0254 §5.1 changes `AnalysisRunner.start`'s
parameter from `AnalysisDocument` to the new `AnalysisRunRequest` type. Dart
requires every class that `implements AnalysisRunner` to update its override
signature in lockstep for the package to compile at all -- there is no
partial-migration state. The brief's `allowed_paths` accounted for two of the
three test-side fakes (`shadow_analysis_runner_test.dart`'s `_Runner`, and,
after the halted round's own uncommitted pre-flight revision,
`analysis_cancellation_test.dart`'s `_SingleRunRunner`) but missed a third:
`analysis_controller_test.dart`'s `_QueueRunner`. The implementer (sonnet-impl)
made the one-line, compile-forced signature fix to that fake (measured via
`git -C /home/ubuntu/ss-sonnet-impl-e99-r13 diff -- test/features/audio_analysis/
application/analysis_controller_test.dart`, 2026-08-15) and the orchestrator
correctly halted (H3) rather than accept a diff outside the committed brief.

Separately, the pre-halt brief still named
`test/features/audio_analysis/application/analysis_isolate_runner_test.dart`
as the isolate-boundary test in `allowed_paths`/`gate_tests`/§7 -- that file
does not exist anywhere in this repo (measured: `find` for it returns
nothing). The halted round's own orchestrator had already found this and
locally corrected it (uncommitted upstream, commit 245116d3 "docs(round):
correct E99-R13 pre-flight test target" in the abandoned
`ss-sonnet-impl-e99-r13` worktree) before dispatching the implementer, in
favour of the test file that actually measures that contract,
`analysis_cancellation_test.dart`. This heal folds that already-measured,
already-verified correction in too -- leaving it out would hand the next
fresh dispatch a brief that still points at a nonexistent file.

This guard encodes both measured facts as a machine check: every file that
`implements AnalysisRunner` must be listed in the brief's `allowed_paths`, and
the pinned baseline set may not silently shrink.

Correction (self-heal, halt H3 recurrence, 2026-08-15, second occurrence same
day): the first version of this guard pinned `KNOWN_IMPLEMENTORS` with a full
`assertEqual`, including the "a new implementor appearing later must fail
here too" direction. That is structurally incompatible with this repo's own
round lifecycle: E99-R13's implementer (sonnet-impl) went on to add a
genuinely new, brief-sanctioned implementor,
`lib/features/audio_analysis/application/v2_analysis_runner.dart` (already
present in this brief's `allowed_paths` since the FIRST H3 self-heal, commit
1636b40d), on its own branch -- which is, by definition, always ahead of
`main` while a round is in flight. Measured
(`gh run view 31884234750 --log-failed`): Router CI failed on the round's own
branch (PR #266) because `KNOWN_IMPLEMENTORS` (4 entries, `main`'s actual
state) no longer equalled the round branch's actual 5-file set. Editing
`KNOWN_IMPLEMENTORS` to 5 entries would have "fixed" the round branch but
broken `main`'s OWN post-merge Router CI (main's tree genuinely has only 4
implementors until v2_analysis_runner.dart is actually merged) -- trading one
red for a worse one that blocks every future round dispatch, not just this
one. The "new implementor" direction is redundant anyway:
`test_brief_allows_every_analysisrunner_implementor` below already requires
EVERY actual implementor (baseline or newly-added) to be in the round's own
`allowed_paths`, on any branch, without needing a hardcoded snapshot. So this
guard now only asserts the non-redundant, branch-invariant half: none of the
pinned baseline implementors may silently disappear.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e99-r13-gov-30c-5-runner-audio-path-and-wiring.md"

IMPLEMENTS_ANALYSIS_RUNNER = re.compile(r"implements AnalysisRunner\b")

SEARCH_ROOTS = (
    REPO_ROOT / "lib" / "features" / "audio_analysis",
    REPO_ROOT / "test" / "features" / "audio_analysis",
)

# Measured 2026-08-15 against baseline `main` (b710d5ca) -- see module docstring.
KNOWN_IMPLEMENTORS = (
    "lib/features/audio_analysis/application/analysis_isolate_runner.dart",
    "test/features/audio_analysis/application/analysis_cancellation_test.dart",
    "test/features/audio_analysis/application/analysis_controller_test.dart",
    "test/features/audio_analysis/application/shadow_analysis_runner_test.dart",
)


def _files_implementing_analysis_runner() -> list[str]:
    hits = []
    for root in SEARCH_ROOTS:
        for path in sorted(root.rglob("*.dart")):
            if IMPLEMENTS_ANALYSIS_RUNNER.search(path.read_text(encoding="utf-8")):
                hits.append(path.relative_to(REPO_ROOT).as_posix())
    return sorted(hits)


class E99R13RunnerScopeTest(unittest.TestCase):
    def test_measured_analysisrunner_implementor_set(self) -> None:
        """Pin the baseline -- none of the founding implementors may
        silently disappear. (Deliberately one-directional: see the module
        docstring's "Correction" section for why asserting the OTHER
        direction -- no new implementor beyond this set -- breaks `main`'s
        own Router CI the moment a round legitimately adds one on its own,
        still-unmerged branch. That direction is covered, branch-safely, by
        test_brief_allows_every_analysisrunner_implementor below.)"""
        missing = [
            path
            for path in KNOWN_IMPLEMENTORS
            if path not in _files_implementing_analysis_runner()
        ]
        self.assertEqual(
            missing, [], f"AnalysisRunner implementor(s) disappeared: {missing}"
        )

    def test_brief_allows_every_analysisrunner_implementor(self) -> None:
        """The halt trigger: allowed_paths must cover every implementor,
        since ADR 0254 §5.1's AnalysisRunner.start signature change forces
        ALL of them -- production and every test fake -- to move together."""
        metadata = load_brief_metadata(BRIEF)
        allowed = set(metadata.allowed_paths)
        missing = [p for p in _files_implementing_analysis_runner() if p not in allowed]
        self.assertEqual(
            missing,
            [],
            "AnalysisRunner implementor(s) missing from E99-R13 allowed_paths "
            f"(halt H3 recurrence): {missing}",
        )


if __name__ == "__main__":
    unittest.main()
