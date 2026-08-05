import '../models/practice_plan_block.dart';
import '../models/practice_plan_draft.dart';
import '../models/skill_node.dart';

abstract final class PracticePlanValidationCode {
  static const String durationTargetNonPositive =
      'practicePlan.duration.targetNonPositive';
  static const String durationBlockNonPositive =
      'practicePlan.duration.blockNonPositive';
  static const String durationMismatch = 'practicePlan.duration.mismatch';
  static const String unsupportedBlockType =
      'practicePlan.blockType.unsupported';
  static const String tempoOutOfRange = 'practicePlan.tempo.outOfRange';
  static const String practiceTargetMissing =
      'practicePlan.practiceTarget.missing';
  static const String songMissing = 'practicePlan.song.missing';
  static const String tuningMismatch = 'practicePlan.tuning.mismatch';
  static const String userAvoidConflict = 'practicePlan.userAvoid.conflict';
  static const String capabilityUnavailable =
      'practicePlan.capability.unavailable';
  static const String skillUnavailable = 'practicePlan.skill.unavailable';
}

final class PracticePlanValidationContext {
  PracticePlanValidationContext({
    required Set<String> songIds,
    required Set<String> practiceTargetIds,
    required Set<String> userAvoidList,
    required List<String> activeTuning,
    required Set<PracticePlanCapability> capabilities,
    required Set<SkillId> availableSkillIds,
  }) : songIds = Set<String>.unmodifiable(songIds),
       practiceTargetIds = Set<String>.unmodifiable(practiceTargetIds),
       userAvoidList = Set<String>.unmodifiable(userAvoidList),
       activeTuning = List<String>.unmodifiable(activeTuning),
       capabilities = Set<PracticePlanCapability>.unmodifiable(capabilities),
       availableSkillIds = Set<SkillId>.unmodifiable(availableSkillIds);

  final Set<String> songIds;
  final Set<String> practiceTargetIds;
  final Set<String> userAvoidList;
  final List<String> activeTuning;
  final Set<PracticePlanCapability> capabilities;
  final Set<SkillId> availableSkillIds;
}

final class PracticePlanValidationResult {
  PracticePlanValidationResult(List<String> codes)
    : codes = List<String>.unmodifiable(codes);

  final List<String> codes;

  bool get isValid => codes.isEmpty;
}

final class PracticePlanValidator {
  const PracticePlanValidator();

  static const double minimumTempoBpm = 30;
  static const double maximumTempoBpm = 300;

  PracticePlanValidationResult validate(
    PracticePlanDraft draft, {
    required PracticePlanValidationContext context,
  }) {
    final codes = <String>[];
    if (draft.targetDuration <= Duration.zero) {
      codes.add(PracticePlanValidationCode.durationTargetNonPositive);
    }

    var totalDuration = Duration.zero;
    for (final block in draft.blocks) {
      totalDuration += block.duration;
      _validateBlock(block, context: context, codes: codes);
    }
    if (totalDuration != draft.targetDuration) {
      codes.add(PracticePlanValidationCode.durationMismatch);
    }
    return PracticePlanValidationResult(codes);
  }

  void _validateBlock(
    PracticePlanBlock block, {
    required PracticePlanValidationContext context,
    required List<String> codes,
  }) {
    if (block.duration <= Duration.zero) {
      codes.add(PracticePlanValidationCode.durationBlockNonPositive);
    }
    if (!PracticePlanBlockType.supported.contains(block.type)) {
      codes.add(PracticePlanValidationCode.unsupportedBlockType);
    }
    final tempoBpm = block.tempoBpm;
    if (tempoBpm != null &&
        (!tempoBpm.isFinite ||
            tempoBpm < minimumTempoBpm ||
            tempoBpm > maximumTempoBpm)) {
      codes.add(PracticePlanValidationCode.tempoOutOfRange);
    }
    if (block.requiredTuning.isNotEmpty &&
        !_sameTuning(block.requiredTuning, context.activeTuning)) {
      codes.add(PracticePlanValidationCode.tuningMismatch);
    }
    if (context.userAvoidList.contains(block.type)) {
      codes.add(PracticePlanValidationCode.userAvoidConflict);
    }
    if (!context.capabilities.containsAll(block.requiredCapabilities)) {
      codes.add(PracticePlanValidationCode.capabilityUnavailable);
    }
    if (!context.availableSkillIds.containsAll(block.requiredSkillIds)) {
      codes.add(PracticePlanValidationCode.skillUnavailable);
    }

    switch (block.adapter) {
      case PracticePlanBlockAdapter.none:
        return;
      case PracticePlanBlockAdapter.practiceTarget:
        if (block.practiceTargetId == null ||
            !context.practiceTargetIds.contains(block.practiceTargetId)) {
          codes.add(PracticePlanValidationCode.practiceTargetMissing);
        }
      case PracticePlanBlockAdapter.song:
        if (block.songId == null || !context.songIds.contains(block.songId)) {
          codes.add(PracticePlanValidationCode.songMissing);
        }
    }
  }
}

bool _sameTuning(List<String> required, List<String> active) {
  if (required.length != active.length) return false;
  for (var index = 0; index < required.length; index++) {
    if (required[index].trim().toLowerCase() !=
        active[index].trim().toLowerCase()) {
      return false;
    }
  }
  return true;
}
