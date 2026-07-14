# StrumSight — UX/quality polish backlog

Prioritized (impact ÷ effort) by a scout sweep on 2026-07-14 (post-r185 Live
timeline). Work these round by round; tick as shipped. Real-guitar APK is the
final gate. Keep each round: builder agent(s) → Claude verifies → reviewer +
devil-advocate → fix → CI green → next.

| # | Item | Files | Effort | Status |
|---|------|-------|--------|--------|
| 1 | **Live hero shrinks as history fills** — keep hero fixed-size; only left history compresses/scrolls off (not a whole-strip FittedBox scaleDown) | `live/widgets/chord_timeline.dart` | M | ✅ r187 |
| 2 | **Haptic + visual feedback on pause/resume** (mic on/off is a privacy state, currently silent) | `live/screens/live_screen.dart` `_togglePause` | S | ✅ r188 |
| 3 | **Tab navigation abrupt swap** → AnimatedSwitcher / M3 fade-through | `app/home_shell.dart` | S | ☐ |
| 4 | **Analyze/Progress loading skeleton** (shimmer timeline while analyzing, not just a spinner) | `analyze/screens/analyze_screen.dart` | M | ☐ |
| 5 | **Hardcoded hero colors bypass theme tokens** (breaks the existing light theme) — add `onPrimary`/`inkOnAccent` to `AppPalette` | `live_screen.dart:255`, analyze, lesson_highway, streak_badge, strum_card | S-M | ☐ |
| 6 | **CustomPaint widgets missing semantics** (tuner needle, lesson highway invisible to screen readers) | `tuner/.../cents_gauge.dart`, `learn/.../lesson_highway.dart`, `hit_burst.dart`, `strum_arrow.dart` | M | ✅ r188 |
| 7 | **Songs delete has no confirm/undo** — SnackBar undo | `songs/screens/song_list_screen.dart:104` | S | ✅ r187 |
| 8 | **Metronome cramped in landscape/320px** — two-column landscape | `metronome/screens/metronome_screen.dart` | M | ✅ r188 |
| 9 | **First-run Live empty state** = bare text → icon + hint + subtle pulse | `live/widgets/chord_timeline.dart` (empty branch) | S | ✅ r187 |
| 10 | **Streak credited on first strum** (a stray noise credits the day) — gate on `_strokeCount >= N` or elapsed time | `live_screen.dart:109` | S | ✅ r188 |
| 11 | **`next` ghost never animates in/out** → AnimatedOpacity/fadeIn keyed on label | `live/widgets/chord_timeline.dart` `_nextGhost` | S | ✅ r187 |
| 12 | **Shared `EmptyState` widget** for consistent first-run across Analyze/Live/Library/Progress | `core/widgets/` + callers | S | ☐ |

Already good (scout): silent catches limited to intentional haptic/wakelock no-ops; providers dispose correctly; `ref` captured before dispose; strings go through ARB.
