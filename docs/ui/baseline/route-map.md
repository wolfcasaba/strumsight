# Route baseline and migration map

The current catalogue contains 40 `AppRoutes` constants and the production
router registers 40 `GoRoute`s when every feature flag is enabled. Flag-gated
routes are intentionally recorded: their deep links are not currently
registered when their owning flag is off.

E08-R15 adds the presentation-only
`achievements_screen.dart` and `achievement_detail_screen.dart` inventory
entries. They intentionally have no `AppRoutes` or `GoRoute` registration
until E08-R30 route wiring, so the route catalogue remains at 40. Until then,
there is no registered deep link to either screen; a direct deep-link attempt
cannot reach the achievement list or detail UI.

| Current route | Chapter 13 target / disposition | Deep-link or redirect risk |
| --- | --- | --- |
| `/welcome` | onboarding retained; then `/today` | first-run redirect must not loop |
| `/live` | `/practice/live` | preserve shell and mic-release lifecycle |
| `/analyze` | `/practice/analyze` or `/profile/library` | analysis result needs an ID before deep-linking |
| `/learn` | `/practice/learn` | legacy lesson selection has no route parameter |
| `/library` | `/profile/library` | retain existing saved-session links |
| `/settings` | `/profile/settings` | retain preference ownership |
| `/tuner` | `/practice/tuner` | preserve microphone exclusivity |
| `/metronome` | `/practice/metronome` | retain current standalone route |
| `/calibrate` | `/practice/calibration` | preserve measured latency state |
| `/streak` | `/profile/rewards` | legacy reward deep links need an alias |
| `/progress` | `/profile/progress` | history and quality must not be conflated |
| `/songs` | `/songs` | becomes the Songs primary tab |
| `/setlists` | `/songs/setlists` | retain list/bookmark deep links |
| `/chords` | `/practice/chords` | chord IDs need a stable target route |
| `/login` | `/profile/account` | account capability remains optional |
| `/library/session` | `/profile/library/session/:sessionId` | current route relies on `extra`, so URL alone redirects |
| `/practice` | `/practice` | currently feature-flag gated |
| `/practice/setup` | `/practice/session/setup` | route arguments need serialized equivalents |
| `/practice/session` | `/practice/session/:sessionId` | current route arguments are not URL-safe |
| `/practice/result` | `/practice/session/:sessionId/result` | current fallback has no stable session ID |
| `/song-trainer` | `/songs` | currently feature-flag gated |
| `/song-trainer/import` | `/songs/import` | import draft identity must survive redirect |
| `/song-trainer/editor/new` | `/songs/new` | keep unsaved-document recovery |
| `/song-trainer/editor/:songId` | `/songs/:songId/edit` | parameter mapping required |
| `/song-trainer/overview/:songId` | `/songs/:songId` | parameter mapping required |
| `/song-trainer/setup/:songId` | `/songs/:songId/train/setup` | parameter mapping required |
| `/song-trainer/session/:songId` | `/songs/:songId/train` | current `extra` inputs are required |
| `/song-trainer/result/:songId` | `/songs/:songId/result/:sessionId` | preserve the `songId` path parameter and the typed `SongTrainerResult` `extra`; either missing value makes a deep link incomplete |
| `/tutor/home` | `/coach` | currently feature-flag gated |
| `/tutor/chat` | `/coach/tutor/:conversationId?` | conversation ID is absent today |
| `/tutor/profile` | `/profile` | retain account and consent boundary |
| `/tutor/privacy` | `/profile/settings/ai` | preserve data-control deep links |
| `/tutor/data` | `/profile/settings/data` | preserve export/delete confirmation flow |
| `/vision/setup` | `/coach/vision/setup` | two flags control registration |
| `/vision/guitar-geometry` | `/coach/vision/setup` | geometry capability needs an explicit fallback |
| `/vision/session` | `/coach/vision/session/:sessionId` | currently feature-flag gated |
| `/analysis/overview` | `/practice/analyze/:analysisId` | current route redirects without `AnalysisDocument` extra |
| `/analysis/metric-detail` | `/practice/analyze/:analysisId/details` | current route redirects without typed `extra` |
| `/analysis/timeline` | `/practice/analyze/:analysisId/timeline` | current route redirects without `AnalysisDocument` extra |
| `/analysis/compare` | `/profile/progress/analysis-compare` | current route redirects without comparison `extra` |

The primary-navigation migration is therefore explicit: Live → Practice,
Analyze → Practice or Library, Learn → Practice, Library → Profile, Settings
→ Profile; the new primary destinations are Today, Practice, Songs, Coach, and
Profile. Redirects remain a later migration deliverable, not an E13-R01 code
change.
