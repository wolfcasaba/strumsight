# Token-debt baseline

Measurements are static source counts, not a claim that every occurrence is a
visual defect. They identify the migration surface for later Chapter 13 rounds.

| Finding | Measurement | Follow-up direction |
| --- | ---: | --- |
| Direct feature `Color(0x…)` files | 9 files / 26 occurrences | replace with semantic color tokens only after the compatibility layer exists |
| Direct `TextStyle(` construction | 174 occurrences | migrate repeated role styles to typography tokens |
| Direct `SizedBox`/`EdgeInsets` spacing construction | 752 occurrences | establish spacing/radius tokens before systematic replacement |
| Raw cross-feature screen/widget imports | 0 observed | keep feature boundaries on public contracts |

The nine files with direct hex colors are:

- `audio_analysis/presentation/widgets/timeline_lane.dart`
- `learn/widgets/lesson_highway.dart`
- `learn/widgets/lesson_score_card.dart`
- `practice/presentation/views/chord_change_view.dart`
- `practice/presentation/widgets/practice_highway.dart`
- `share/screens/strum_reel_screen.dart`
- `share/widgets/strum_card.dart`
- `share/widgets/wrapped_card.dart`
- `streak/screens/streak_screen.dart`

Repeated local patterns include card variants in Live, Learn, Practice,
Practice Generator, Progress, Audio Analysis, Gamification and Share; action
buttons in Analyze and Live; and feature-local empty states in Songs, Tutor and
Practice Generator. These are candidates for the later component rounds, not
authorization to refactor this baseline.
