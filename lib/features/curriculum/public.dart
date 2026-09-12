/// Public domain contract for cross-feature Curriculum consumers.
library;

export 'application/curriculum_progress.dart';
export 'application/mission_goal.dart';
export 'data/beginner_course.dart';
export 'domain/chord_evidence.dart';
export 'domain/chord_grading.dart';
export 'domain/course.dart';
export 'domain/device_capabilities.dart';
export 'domain/metronome_pulse.dart';
export 'domain/mission_availability.dart';
export 'domain/next_step.dart';
export 'domain/mission_chords.dart';
export 'domain/rhythm_assignment.dart';
export 'domain/rhythm_countin.dart';
export 'domain/rhythm_evidence.dart';
export 'domain/rhythm_grading.dart';
export 'domain/rhythm_grid.dart';
export 'domain/rhythm_mode.dart';
export 'domain/skill_metrics.dart';
export 'domain/unlock_rule.dart';
// The learner-facing names. Exported because a surface OUTSIDE the feature now
// shows a rung — the Today hub's recommendation — and it must not print the
// persistence id (E18-R14).
export 'presentation/curriculum_names.dart';
export 'presentation/providers/curriculum_progress_providers.dart';
