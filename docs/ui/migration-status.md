# Screen migration status

Measured by `dart run tool/ui_inventory.dart` at E08-R15: 60 production screen
sources, 97 reusable widget/view sources, and 16 dialog or bottom-sheet
sources. All are legacy baseline entries: no Chapter 13 design-system migration
is claimed in this round.

## Canonical token source by migration phase

| Phase | Canonical source | Compatibility rule |
| --- | --- | --- |
| E13-R02 foundation | `lib/core/theme/AppColors`, `AppPalette`, and `AppTheme` | `core/design_system` reads the legacy theme through its adapter; it does not copy color values. |
| Later semantic color and theme migration | `core/design_system` semantic theme extensions | The legacy theme becomes an adapter only after its designated consumers migrate. |
| Later component and screen migration | Design-system component tokens | A screen migrates only in its assigned round; all unassigned screens remain on the legacy theme. |

| Source | Status |
| --- | --- |
| ai_tutor: practice plan preview, tutor chat, data, home, privacy, profile | legacy / migration pending |
| analyze: analyze | legacy / migration pending |
| audio_analysis: compare, export, metric detail, overview, timeline | legacy / migration pending |
| auth: login | legacy / migration pending |
| chords: chord library | legacy / migration pending |
| gamification: achievements, achievement detail, streak detail | legacy / migration pending |
| learn: latency calibration, player, lesson list, score preview | legacy / migration pending |
| library: library, session detail | legacy / migration pending |
| live: live | legacy / migration pending |
| metronome: metronome | legacy / migration pending |
| onboarding: onboarding | legacy / migration pending |
| practice: hub, result, session, setup | legacy / migration pending |
| practice_generator: change review, preview, privacy, setup, today, weekly plan | legacy / migration pending |
| progress: progress | legacy / migration pending |
| settings: settings, vision privacy | legacy / migration pending |
| share: preview, strum reel, wrapped preview | legacy / migration pending |
| song_trainer: setlist session, editor, import preview, import, library, overview, result, trainer, setup | legacy / migration pending |
| songs: setlist detail, setlist list, builder, list | legacy / migration pending |
| streak: streak | legacy / migration pending |
| tuner: tuner | legacy / migration pending |
| vision: guitar calibration, session, setup | legacy / migration pending |

The canonical per-file list of screens, reusable widget/view sources, and
dialog/bottom-sheet sources is the deterministic generator output in
`tool/ui_inventory.dart`; its test holds the measured screen count at 60 and
guards against traversal-order drift.
