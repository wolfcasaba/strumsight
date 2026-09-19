/// Which Practice catalog entry a "Start plan" action opens (E17-R04,
/// ADR 0523 §5.1).
///
/// The Tutor never owns a session launcher of its own: the resolved
/// definition id is handed to the EXISTING `/practice/setup?id=` route —
/// the same URI shape `PracticeHubScreen._openSetup` builds — and the
/// Setup screen's own `PreparePractice` sink starts the session. This file
/// only answers "which definition", deterministically, from the compiled
/// plan and the live catalog; it imports no Flutter and no routing.
library;

import 'package:strumsight/features/practice/public.dart';

import '../../domain/models/practice_plan_block.dart';
import 'practice_plan_compiler.dart';

/// The catalog entry a plan launches into, and the block it stands for.
final class PracticePlanLaunchTarget {
  const PracticePlanLaunchTarget({
    required this.blockId,
    required this.definitionId,
  });

  final String blockId;
  final String definitionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticePlanLaunchTarget &&
          other.blockId == blockId &&
          other.definitionId == definitionId;

  @override
  int get hashCode => Object.hash(blockId, definitionId);

  @override
  String toString() =>
      'PracticePlanLaunchTarget(block: $blockId, definition: $definitionId)';
}

/// The deterministic block-type → catalog-mode mapping used for a block that
/// carries no explicit practice target (every block of the local
/// deterministic template is `PracticePlanBlock.basic`). Reflection and rest
/// blocks map to nothing: they are not playable exercises.
PracticeMode? practiceModeForPlanBlockType(String type) => switch (type) {
  PracticePlanBlockType.warmup ||
  PracticePlanBlockType.rhythm => PracticeMode.rhythmOnly,
  PracticePlanBlockType.technique ||
  PracticePlanBlockType.speedBuilder => PracticeMode.strumPattern,
  PracticePlanBlockType.chordChange => PracticeMode.chordChanges,
  PracticePlanBlockType.songRange => PracticeMode.chordProgression,
  PracticePlanBlockType.freePractice => PracticeMode.freePractice,
  _ => null,
};

/// Resolves the first launchable block of [plan], in plan order.
///
/// A block launches through its compiled definition when that definition is
/// a [catalog] entry (the Setup route looks the id up in the catalog, so a
/// song-derived definition — synthesised by the compiler, absent from the
/// catalog — cannot be launched this way and falls through to the mode
/// mapping). Otherwise the block type is mapped by
/// [practiceModeForPlanBlockType] and the first catalog entry of that mode
/// wins. Returns `null` when nothing in the plan is playable or the catalog
/// is empty (the caller reports "no exercise available" instead of
/// navigating to a route that cannot render).
PracticePlanLaunchTarget? resolvePracticePlanLaunchTarget({
  required CompiledPracticePlan plan,
  required List<PracticeDefinition> catalog,
}) {
  if (catalog.isEmpty) return null;
  for (final block in plan.blocks) {
    final definition = block.definition;
    if (definition != null &&
        catalog.any((entry) => entry.id == definition.id)) {
      return PracticePlanLaunchTarget(
        blockId: block.id,
        definitionId: definition.id,
      );
    }
    final mode = practiceModeForPlanBlockType(block.type);
    if (mode == null) continue;
    for (final entry in catalog) {
      if (entry.mode == mode) {
        return PracticePlanLaunchTarget(
          blockId: block.id,
          definitionId: entry.id,
        );
      }
    }
  }
  return null;
}
