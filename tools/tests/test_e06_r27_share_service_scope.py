"""Regression guard for the E06-R27 self-heal (ADR 0112, halt H3, 2026-08-13).

Measured root cause of the halt: the PREPARED E06-R27 brief (export, share
and privacy controls) makes a ShareService-mediated, both-paths-cleaned-up
JSON export share MANDATORY -- its own §5.1 OD-01 default resolution reads
"...majd a MEGLEVO share szolgaltatason at megosztasi intentbe; a temp fajl
a megosztas utan (vagy hiba eseten) TORLODIK, es ezt teszt meri" (share via
the EXISTING share service; the temp file is deleted after the share, or on
failure, and a test measures it) -- while §3/§4 declared the whole
`lib/features/share/**` directory out of scope ("Kivul -- TILOS: a share
feature modositasa") and the brief's `allowed_paths` named none of its
files.

Measured (`lib/features/share/share_service.dart`, 103 lines, before this
fix): only `shareCard`/`shareImage`/`shareText` are public, all three built
around capturing an on-screen widget to a PNG (or falling back to text); the
private `_writeTemp` writes into `Directory.systemTemp` and NONE of the three
methods clean up the temp file after the share call, on success or on
failure. There is no public surface that accepts an arbitrary caller-built
file (e.g. the redacted JSON export) and guarantees its cleanup either way.
The mandatory OD-01 flow was therefore structurally impossible without an
additive change to this file -- the first dispatch (Terra orchestration,
sonnet-impl) correctly reported `stopped` (H3) after zero file changes
rather than exceed its declared scope.

This guard encodes the fix (allowed_paths + gate_tests widened) as a machine
check so the same halt cannot silently return to this brief.
"""

import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e06-r27-export-share-and-privacy-controls.md"
SHARE_SERVICE = REPO_ROOT / "lib" / "features" / "share" / "share_service.dart"

SHARE_SERVICE_PATH = "lib/features/share/share_service.dart"
SHARE_SERVICE_TEST_PATH = "test/features/share/share_service_test.dart"
SHARE_GATE_DIR = "test/features/share"

# Existing public methods the fix's reasoning depends on -- built around
# on-screen widget capture, not arbitrary-file sharing (measured pre-fix).
EXISTING_PUBLIC_METHODS = ("shareCard", "shareImage", "shareText")


class E06R27ShareServiceScopeTest(unittest.TestCase):
    def test_brief_declares_share_service_and_its_test_in_allowed_paths(self) -> None:
        """The halt trigger: OD-01's cleaned-up JSON share needs ShareService in scope."""
        metadata = load_brief_metadata(BRIEF)
        missing = {SHARE_SERVICE_PATH, SHARE_SERVICE_TEST_PATH} - set(metadata.allowed_paths)
        self.assertEqual(
            missing,
            set(),
            "E06-R27 allowed_paths is missing the share-service file(s) the "
            f"mandatory cleaned-up export share requires (halt H3 recurrence): {sorted(missing)}",
        )

    def test_share_test_directory_is_covered_by_the_rounds_own_gate(self) -> None:
        """Without this, share_service_test.dart would silently not run under §7."""
        metadata = load_brief_metadata(BRIEF)
        self.assertIn(
            SHARE_GATE_DIR,
            metadata.gate_tests,
            "the round's own §7 round-gate command would not execute "
            "test/features/share/share_service_test.dart without "
            "test/features/share in gate_tests",
        )

    def test_share_service_is_still_the_narrow_surface_the_fix_reasons_about(self) -> None:
        """Measured facts the fix relies on -- catch them drifting silently."""
        text = SHARE_SERVICE.read_text(encoding="utf-8")
        self.assertIn(
            "class ShareService",
            text,
            "ShareService class moved -- re-measure the H3 fix before trusting this guard",
        )
        for method in EXISTING_PUBLIC_METHODS:
            self.assertIn(
                f"Future<void> {method}",
                text,
                f"ShareService.{method} moved/renamed -- re-measure the H3 fix "
                "before trusting this guard",
            )
        self.assertIn(
            "Directory.systemTemp",
            text,
            "ShareService no longer writes shared files into the system temp "
            "dir -- re-measure the H3 fix before trusting this guard",
        )


if __name__ == "__main__":
    unittest.main()
