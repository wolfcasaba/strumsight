import 'practice_plan_block.dart';

enum PracticePlanSource { aiSuggestion, deterministicTemplate, userEdited }

final class PracticePlanDraft {
  PracticePlanDraft({
    required this.id,
    required this.title,
    required this.targetDuration,
    required List<PracticePlanBlock> blocks,
    required List<String> goalIds,
    required this.rationale,
    required this.source,
  }) : blocks = List<PracticePlanBlock>.unmodifiable(blocks),
       goalIds = List<String>.unmodifiable(goalIds);

  final String id;
  final String title;
  final Duration targetDuration;
  final List<PracticePlanBlock> blocks;
  final List<String> goalIds;
  final String rationale;
  final PracticePlanSource source;

  static PracticePlanDraft deterministicTemplate({
    required Duration targetDuration,
  }) {
    final minutes = targetDuration.inMinutes;
    final blockMinutes = switch (minutes) {
      5 => const <int>[1, 3, 1],
      10 => const <int>[2, 5, 3],
      20 => const <int>[3, 7, 7, 3],
      30 => const <int>[5, 10, 10, 5],
      _ => throw ArgumentError.value(
        targetDuration,
        'targetDuration',
        'Deterministic templates support 5, 10, 20, and 30 minutes.',
      ),
    };
    const types = <String>[
      PracticePlanBlockType.warmup,
      PracticePlanBlockType.technique,
      PracticePlanBlockType.rhythm,
      PracticePlanBlockType.reflection,
    ];
    final blocks = <PracticePlanBlock>[
      for (var index = 0; index < blockMinutes.length; index++)
        PracticePlanBlock.basic(
          id: 'template.$minutes.$index',
          type: types[index],
          duration: Duration(minutes: blockMinutes[index]),
        ),
    ];
    return PracticePlanDraft(
      id: 'template.$minutes',
      title: '$minutes-minute practice plan',
      targetDuration: targetDuration,
      blocks: blocks,
      goalIds: const <String>[],
      rationale: 'Deterministic duration template.',
      source: PracticePlanSource.deterministicTemplate,
    );
  }

  PracticePlanDraft copyWith({
    String? id,
    String? title,
    Duration? targetDuration,
    List<PracticePlanBlock>? blocks,
    List<String>? goalIds,
    String? rationale,
    PracticePlanSource? source,
  }) => PracticePlanDraft(
    id: id ?? this.id,
    title: title ?? this.title,
    targetDuration: targetDuration ?? this.targetDuration,
    blocks: blocks ?? this.blocks,
    goalIds: goalIds ?? this.goalIds,
    rationale: rationale ?? this.rationale,
    source: source ?? this.source,
  );
}
