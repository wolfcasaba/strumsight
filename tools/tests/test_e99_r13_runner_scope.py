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
the currently-measured set is pinned so a new implementor appearing later (or
the set silently shrinking) is a visible test failure here, not a fresh H3
halt three commands into a round.
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
        """Pin the currently measured set -- a NEW implementor appearing
        later must fail loudly here, not surface as a fresh H3 halt."""
        self.assertEqual(_files_implementing_analysis_runner(), sorted(KNOWN_IMPLEMENTORS))

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
