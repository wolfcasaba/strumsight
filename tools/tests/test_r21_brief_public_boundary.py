"""Regression guard for the E04-R21 self-heal (ADR 0112, halt H3, 2026-08-06).

Measured root cause of the halt: the PREPARED E04-R21 brief assumed the Song
Trainer *public* boundary exposes a practice-result + range surface
(`SongPracticeResult`, `TrainerRange`, ...) and that the setup route accepts a
range parameter. None of that exists — those types live only inside the
song_trainer feature and are NOT re-exported by the public boundary, and the
brief's `allowed_paths` contains no song_trainer file, so an implementer could
never expose them without touching the forbidden zone.

This guard encodes that measured truth as a machine check so the same halt
cannot silently return:

  * the deferred result/range/setlist symbols are provably absent from the
    song_trainer public export set (the contract R21 must degrade around);
  * the re-scoped R21 brief no longer presents any of those non-public symbols
    as an input it consumes.

If a future prerequisite round additively exposes these symbols on the public
boundary, this test turns red on assertion (1) and forces the brief to be
re-expanded deliberately — that is the intended forcing function, not a
regression.
"""

import re
import unittest
from pathlib import Path

# tools/tests/<this file> -> repo root is two parents up from tools/.
REPO_ROOT = Path(__file__).resolve().parents[2]
SONG_TRAINER = REPO_ROOT / "lib" / "features" / "song_trainer"
R21_BRIEF = REPO_ROOT / "docs" / "rounds" / "e04-r21-song-trainer-debrief-range-actions.md"

# Public boundary barrels. Symbols reachable through these are the ONLY
# song_trainer types an ai_tutor adapter may consume (source-internal imports
# are forbidden by every round brief).
PUBLIC_BARRELS = (
    SONG_TRAINER / "public.dart",
    SONG_TRAINER / "domain" / "public.dart",
)

# Measured 2026-08-06: these types define the practice-result / range / setlist
# surface the halted brief assumed was public. Each lives OUTSIDE the public
# barrels (verified by `grep -rn "class ..." lib/features/song_trainer`):
#   SongTrainerResult   application/trainer/song_trainer_result.dart   (in-mem)
#   SongPracticeRecord  domain/models/song_practice_record.dart        (persisted)
#   TrainerRange /      domain/models/trainer_range.dart
#     MeasureRange
#   SongSetlist         domain/models/song_setlist.dart
#   SongPracticeResult  (does not exist anywhere — 0 refs)
DEFERRED_SYMBOLS = frozenset(
    {
        "SongPracticeResult",
        "SongTrainerResult",
        "SongPracticeRecord",
        "TrainerRange",
        "MeasureRange",
        "SongSetlist",
        "SongSetlistItem",
    }
)

_EXPORT_RE = re.compile(r"""export\s+['"]([^'"]+\.dart)['"]""")
_DECL_RE = re.compile(
    r"^\s*(?:final\s+|sealed\s+|abstract\s+|base\s+|interface\s+|mixin\s+)*"
    r"(?:class|enum|mixin|typedef|extension\s+type)\s+([A-Z]\w*)",
    re.MULTILINE,
)


def _public_export_symbols() -> set[str]:
    """Every top-level type name reachable through the public barrels."""
    symbols: set[str] = set()
    for barrel in PUBLIC_BARRELS:
        text = barrel.read_text(encoding="utf-8")
        for rel in _EXPORT_RE.findall(text):
            target = (barrel.parent / rel).resolve()
            if not target.is_file():
                continue
            symbols.update(_DECL_RE.findall(target.read_text(encoding="utf-8")))
    return symbols


class R21BriefPublicBoundaryTest(unittest.TestCase):
    def test_deferred_symbols_are_not_publicly_exported(self) -> None:
        """Measured contract: the result/range/setlist surface is not public."""
        public = _public_export_symbols()
        # Sanity: the structure+capability slice R21 was re-scoped onto IS public.
        for expected in ("SongDocument", "SongCapabilityReport", "SongSection", "SongMeasure"):
            self.assertIn(expected, public, f"{expected} must be publicly exported")
        leaked = DEFERRED_SYMBOLS & public
        self.assertEqual(
            leaked,
            set(),
            "Deferred song_trainer symbols became public; a prerequisite round "
            f"landed — re-expand the R21 brief deliberately. Leaked: {sorted(leaked)}",
        )

    def test_r21_scope_in_block_lists_no_non_public_symbol(self) -> None:
        """The §3 "Benne:" (in-scope inputs) block must name no deferred symbol.

        The original halt trigger was the §3 in-scope declaration presenting
        `SongPracticeResult` (a type that exists nowhere) as the adapter input.
        The §0.0 self-heal record and grep-evidence lines legitimately *name*
        the deferred internal types to document what was deferred — that is
        honest documentation, not an input claim — so the guard is scoped to
        the in-scope block, where a non-public input would actually appear.
        """
        brief = R21_BRIEF.read_text(encoding="utf-8")
        block = self._scope_in_block(brief)
        self.assertTrue(block, "§3 '**Benne:**' in-scope block not found in brief")
        referenced = {sym for sym in DEFERRED_SYMBOLS if re.search(rf"\b{sym}\b", block)}
        self.assertEqual(
            referenced,
            set(),
            "E04-R21 §3 in-scope block claims song_trainer symbols that are not "
            f"on the public boundary (halt H3 recurrence): {sorted(referenced)}",
        )

    @staticmethod
    def _scope_in_block(brief: str) -> str:
        """Text from the §3 '**Benne:**' marker up to '**Kívül' or next heading."""
        start = brief.find("**Benne:**")
        if start == -1:
            return ""
        rest = brief[start:]
        end = len(rest)
        for marker in ("**Kívül", "\n## "):
            hit = rest.find(marker)
            if hit != -1:
                end = min(end, hit)
        return rest[:end]


if __name__ == "__main__":
    unittest.main()
