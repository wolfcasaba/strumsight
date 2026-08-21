# Token-debt baseline

Measurements are static source counts, not a claim that every occurrence is a
visual defect. They identify the migration surface for later Chapter 13 rounds.

| Finding | Measurement | Follow-up direction |
| --- | ---: | --- |
| Direct feature `Color(0x…)` occurrences | 28 occurrences in 9 files | replace with semantic color tokens only after the compatibility layer exists |
| Direct `TextStyle(` construction | 174 occurrences | migrate repeated role styles to typography tokens |
| Direct `SizedBox`/`EdgeInsets` spacing construction | 817 occurrences | establish spacing/radius tokens before systematic replacement |
| Raw cross-feature screen/widget imports | none observed in a manual import audit | keep feature boundaries on public contracts |

The occurrence counters above are reproducible at the measured repository
HEAD with these exact commands:

```bash
rg -o 'Color\(0x[0-9A-Fa-f]+' lib/features | wc -l
rg -l 'Color\(0x[0-9A-Fa-f]+' lib/features | sort | wc -l
rg -o 'TextStyle\(' lib/features | wc -l
rg -o 'SizedBox\(|EdgeInsets\.' lib/features | wc -l
```

The first command measures direct-color occurrences (28); the second measures
the affected-file unit (9), rather than counting lines. The final two commands
measure source occurrences, not rendered token values. The cross-feature row
is deliberately a manual boundary audit rather than an implied automated count.

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
