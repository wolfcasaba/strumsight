/// The six task families the Accuracy Lab measures (SDD Ch14, ADR 0358).
enum LabTaskFamily {
  silence,
  backgroundNoise,
  singleChord,
  slowStrumDownUp,
  alternatePicking,
  fastPattern,
}

/// One capture prompt in a [LabTaskCatalog].
final class LabTask {
  const LabTask({
    required this.id,
    required this.family,
    required this.targetDurationSeconds,
  });

  /// Stable identifier, unique within its catalog.
  final String id;

  final LabTaskFamily family;

  /// Target recording length for this prompt, in whole seconds.
  final int targetDurationSeconds;
}

/// Thrown by [LabTaskCatalog.validated] when the task list falls outside
/// the 15-20 range mandated by ADR 0358 D6.
final class LabTaskRangeException implements Exception {
  const LabTaskRangeException(this.taskCount);

  final int taskCount;

  @override
  String toString() =>
      'LabTaskRangeException: $taskCount tasks is outside the required '
      '${LabTaskCatalog.minTasks}-${LabTaskCatalog.maxTasks} range';
}

/// A validated, immutable list of [LabTask]s.
final class LabTaskCatalog {
  const LabTaskCatalog._(this.tasks);

  /// Inclusive lower bound of the accepted task-list length.
  static const int minTasks = 15;

  /// Inclusive upper bound of the accepted task-list length.
  static const int maxTasks = 20;

  final List<LabTask> tasks;

  /// Validates an arbitrary [tasks] list against the 15-20 range
  /// (ADR 0358 D6): the check runs on whatever list it is given, not on a
  /// fixed constant, so it also rejects a hand-edited or future catalog
  /// that drifts outside the range.
  factory LabTaskCatalog.validated(List<LabTask> tasks) {
    if (tasks.length < minTasks || tasks.length > maxTasks) {
      throw LabTaskRangeException(tasks.length);
    }
    return LabTaskCatalog._(List.unmodifiable(tasks));
  }

  /// The catalog the app ships: all six task families, itself validated.
  static LabTaskCatalog standard() => LabTaskCatalog.validated(_standardTasks);
}

const _standardTasks = <LabTask>[
  LabTask(
    id: 'silence_room',
    family: LabTaskFamily.silence,
    targetDurationSeconds: 10,
  ),
  LabTask(
    id: 'noise_room_tone',
    family: LabTaskFamily.backgroundNoise,
    targetDurationSeconds: 10,
  ),
  LabTask(
    id: 'noise_talking',
    family: LabTaskFamily.backgroundNoise,
    targetDurationSeconds: 10,
  ),
  LabTask(
    id: 'chord_e_major_open',
    family: LabTaskFamily.singleChord,
    targetDurationSeconds: 6,
  ),
  LabTask(
    id: 'chord_a_major_open',
    family: LabTaskFamily.singleChord,
    targetDurationSeconds: 6,
  ),
  LabTask(
    id: 'chord_d_major_open',
    family: LabTaskFamily.singleChord,
    targetDurationSeconds: 6,
  ),
  LabTask(
    id: 'chord_g_major_open',
    family: LabTaskFamily.singleChord,
    targetDurationSeconds: 6,
  ),
  LabTask(
    id: 'chord_c_major_open',
    family: LabTaskFamily.singleChord,
    targetDurationSeconds: 6,
  ),
  LabTask(
    id: 'chord_e_minor_open',
    family: LabTaskFamily.singleChord,
    targetDurationSeconds: 6,
  ),
  LabTask(
    id: 'slow_strum_down_up_e_major',
    family: LabTaskFamily.slowStrumDownUp,
    targetDurationSeconds: 12,
  ),
  LabTask(
    id: 'slow_strum_down_up_a_minor',
    family: LabTaskFamily.slowStrumDownUp,
    targetDurationSeconds: 12,
  ),
  LabTask(
    id: 'slow_strum_down_up_g_major',
    family: LabTaskFamily.slowStrumDownUp,
    targetDurationSeconds: 12,
  ),
  LabTask(
    id: 'alternate_picking_single_string',
    family: LabTaskFamily.alternatePicking,
    targetDurationSeconds: 10,
  ),
  LabTask(
    id: 'alternate_picking_chord_tones',
    family: LabTaskFamily.alternatePicking,
    targetDurationSeconds: 10,
  ),
  LabTask(
    id: 'fast_pattern_eighth_notes',
    family: LabTaskFamily.fastPattern,
    targetDurationSeconds: 10,
  ),
  LabTask(
    id: 'fast_pattern_sixteenth_notes',
    family: LabTaskFamily.fastPattern,
    targetDurationSeconds: 10,
  ),
];
