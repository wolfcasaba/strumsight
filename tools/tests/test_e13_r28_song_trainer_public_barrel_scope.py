"""Regression guard for the E13-R28 self-heal (ADR 0112, halt H3, 2026-08-27).

Measured root cause: the round's §3 scope lists the **song** and **setlist**
item types in the unified library, but `lib/features/song_trainer/public.dart`
exports only two screens -- neither the `SongRepository` / `SetlistRepository`
contracts (`domain/repositories/**`) nor the two Riverpod providers
(`application/song_trainer_providers.dart`). The nested domain barrel
(ADR 0089 / ADR 0176, `lib/features/song_trainer/domain/public.dart`) does not
close the gap either: it re-exports `domain/models/**` and `domain/services/**`
only. So the implementer could not write a boundary-legal cross-feature import
from inside its own `allowed_paths`, and the architecture guard stopped the
round with exactly three violations (`.pipeline/HALTED`, halt=H3,
halted_at=2026-08-27T02:07:38+00:00).

Reproduced independently in the round's own working copy
(`/home/ubuntu/ss-sonnet-impl-e13-r28`, HEAD 090990f2):

    dart run tool/check_architecture.dart
    # Architecture dependency check failed.
    #  - lib/features/library_v2/data/setlist_item_source.dart
    #      -> lib/features/song_trainer/domain/repositories/setlist_repository.dart
    #  - lib/features/library_v2/data/song_item_source.dart
    #      -> lib/features/song_trainer/domain/repositories/song_repository.dart
    #  - lib/features/library_v2/providers/library_v2_providers.dart
    #      -> lib/features/song_trainer/application/song_trainer_providers.dart

and the fix was measured on the same copy (patch reverted afterwards -- the
code work belongs to the resumed round): three additive `show`-scoped export
lines on the root barrel plus the three re-pointed imports give
`Architecture dependencies OK (12 allowlisted deviation(s))`,
`flutter analyze lib/` -> `No issues found!` and
`flutter test test/core/architecture_dependency_test.dart` -> `+44`.

This guard drives `tools.ai_router.legacy_scope.audit_legacy_scope` -- the
exact function `tools/scope-audit.py` calls for the implementer path this
round runs on -- against the REAL, currently committed brief, so a regression
in either direction shows up here first:

  * every path the measured fix has to touch (the three `library_v2` files
    plus the `song_trainer` root barrel) must now be in scope;
  * the widening must stay a ONE-FILE exception: sibling `song_trainer`
    internals -- the repository the barrel re-exports, the provider file, and
    the nested domain barrel -- must keep violating, otherwise the self-heal
    would have legalized the whole feature instead of its public surface.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e13-r28-unified-library.md"

# The barrel the fix extends -- the single file the §0.0/R5 revision adds.
BARREL_PATH = "lib/features/song_trainer/public.dart"

# Reproduced verbatim from `dart run tool/check_architecture.dart` on the
# halted round branch (E13-R28, H3, 2026-08-27) -- real measured data, not an
# invented fixture. These are the importing files whose import lines the
# resumed round re-points at the barrel.
MEASURED_HALT_SOURCE_PATHS = (
    "lib/features/library_v2/data/setlist_item_source.dart",
    "lib/features/library_v2/data/song_item_source.dart",
    "lib/features/library_v2/providers/library_v2_providers.dart",
)

# The import TARGETS from the same measurement: `song_trainer` internals that
# must stay out of scope. Widening to any of them would mean the round can
# edit the feature it is only allowed to consume through `public.dart`.
SIBLING_OUT_OF_SCOPE_PATHS = (
    "lib/features/song_trainer/domain/repositories/song_repository.dart",
    "lib/features/song_trainer/domain/repositories/setlist_repository.dart",
    "lib/features/song_trainer/application/song_trainer_providers.dart",
    "lib/features/song_trainer/domain/public.dart",
)

# No protected-path fragment of the real `.ai/router.toml` touches any
# candidate path; an empty tuple keeps this guard focused on `allowed_paths`.
PROTECTED = ()


class E13R28SongTrainerPublicBarrelScopeTest(unittest.TestCase):
    def make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "heal@example.invalid"], cwd=root, check=True
        )
        subprocess.run(["git", "config", "user.name", "Heal Test"], cwd=root, check=True)
        (root / ".gitignore").write_text("build/\n")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
        return root

    def head(self, root: Path) -> str:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
        ).stdout.strip()

    def audit_untracked(self, root: Path, base: str, *relatives: str):
        for relative in relatives:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("cross-feature import re-pointed at the public barrel\n")
        allowed = load_brief(BRIEF).metadata.allowed_paths
        return audit_legacy_scope(
            root, base=base, allowed_paths=allowed, protected_paths=PROTECTED
        )

    def test_measured_fix_paths_are_in_scope(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        audit = self.audit_untracked(
            root, base, BARREL_PATH, *MEASURED_HALT_SOURCE_PATHS
        )

        self.assertTrue(
            audit.ok,
            "E13-R28 allowed_paths must cover the song_trainer public barrel and "
            f"the three measured importers (halt H3, 2026-08-27) -- got "
            f"violations: {audit.violations}",
        )
        self.assertIn(BARREL_PATH, audit.changed_paths)
        for path in MEASURED_HALT_SOURCE_PATHS:
            self.assertIn(path, audit.changed_paths)

    def test_song_trainer_internals_remain_out_of_scope(self) -> None:
        """The widening is exactly one file: `song_trainer/public.dart`.

        The repositories and providers the barrel re-exports -- and the nested
        domain barrel -- must still violate, so the round can only consume the
        feature through its reviewed public surface.
        """
        for path in SIBLING_OUT_OF_SCOPE_PATHS:
            with self.subTest(path=path):
                root = self.make_repo()
                base = self.head(root)

                audit = self.audit_untracked(root, base, path)

                self.assertFalse(audit.ok)
                self.assertIn(f"path outside allowed scope: {path}", audit.violations)


if __name__ == "__main__":
    unittest.main()
