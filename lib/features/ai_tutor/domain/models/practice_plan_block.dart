import 'skill_node.dart';

abstract final class PracticePlanBlockType {
  static const String warmup = 'warmup';
  static const String technique = 'technique';
  static const String rhythm = 'rhythm';
  static const String chordChange = 'chordChange';
  static const String songRange = 'songRange';
  static const String speedBuilder = 'speedBuilder';
  static const String freePractice = 'freePractice';
  static const String reflection = 'reflection';
  static const String rest = 'rest';

  static const Set<String> supported = <String>{
    warmup,
    technique,
    rhythm,
    chordChange,
    songRange,
    speedBuilder,
    freePractice,
    reflection,
    rest,
  };
}

enum PracticePlanBlockAdapter { none, practiceTarget, song }

enum PracticePlanCapability { practiceTarget, songRange }

final class PracticePlanBlock {
  PracticePlanBlock.basic({
    required this.id,
    required this.type,
    required this.duration,
    this.tempoBpm,
    List<String> requiredTuning = const <String>[],
    List<SkillId> requiredSkillIds = const <SkillId>[],
    Set<PracticePlanCapability> requiredCapabilities =
        const <PracticePlanCapability>{},
    this.assetAvailableLocally = true,
  }) : adapter = PracticePlanBlockAdapter.none,
       requiredTuning = List<String>.unmodifiable(requiredTuning),
       requiredSkillIds = List<SkillId>.unmodifiable(requiredSkillIds),
       requiredCapabilities = Set<PracticePlanCapability>.unmodifiable(
         requiredCapabilities,
       ),
       practiceTargetId = null,
       songId = null;

  PracticePlanBlock.practiceTarget({
    required this.id,
    required this.type,
    required this.duration,
    required this.practiceTargetId,
    this.tempoBpm,
    List<String> requiredTuning = const <String>[],
    List<SkillId> requiredSkillIds = const <SkillId>[],
    Set<PracticePlanCapability> requiredCapabilities =
        const <PracticePlanCapability>{},
    this.assetAvailableLocally = true,
  }) : adapter = PracticePlanBlockAdapter.practiceTarget,
       requiredTuning = List<String>.unmodifiable(requiredTuning),
       requiredSkillIds = List<SkillId>.unmodifiable(requiredSkillIds),
       requiredCapabilities = Set<PracticePlanCapability>.unmodifiable(
         requiredCapabilities,
       ),
       songId = null;

  PracticePlanBlock.song({
    required this.id,
    this.type = PracticePlanBlockType.songRange,
    required this.duration,
    required this.songId,
    this.tempoBpm,
    List<String> requiredTuning = const <String>[],
    List<SkillId> requiredSkillIds = const <SkillId>[],
    Set<PracticePlanCapability> requiredCapabilities =
        const <PracticePlanCapability>{},
    this.assetAvailableLocally = true,
  }) : adapter = PracticePlanBlockAdapter.song,
       requiredTuning = List<String>.unmodifiable(requiredTuning),
       requiredSkillIds = List<SkillId>.unmodifiable(requiredSkillIds),
       requiredCapabilities = Set<PracticePlanCapability>.unmodifiable(
         requiredCapabilities,
       ),
       practiceTargetId = null;

  final String id;
  final String type;
  final Duration duration;
  final PracticePlanBlockAdapter adapter;
  final double? tempoBpm;
  final List<String> requiredTuning;
  final List<SkillId> requiredSkillIds;
  final Set<PracticePlanCapability> requiredCapabilities;
  final bool assetAvailableLocally;
  final String? practiceTargetId;
  final String? songId;

  PracticePlanBlock copyWith({
    String? id,
    String? type,
    Duration? duration,
    double? tempoBpm,
    List<String>? requiredTuning,
    List<SkillId>? requiredSkillIds,
    Set<PracticePlanCapability>? requiredCapabilities,
    bool? assetAvailableLocally,
  }) => switch (adapter) {
    PracticePlanBlockAdapter.none => PracticePlanBlock.basic(
      id: id ?? this.id,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      requiredTuning: requiredTuning ?? this.requiredTuning,
      requiredSkillIds: requiredSkillIds ?? this.requiredSkillIds,
      requiredCapabilities: requiredCapabilities ?? this.requiredCapabilities,
      assetAvailableLocally:
          assetAvailableLocally ?? this.assetAvailableLocally,
    ),
    PracticePlanBlockAdapter.practiceTarget => PracticePlanBlock.practiceTarget(
      id: id ?? this.id,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      practiceTargetId: practiceTargetId!,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      requiredTuning: requiredTuning ?? this.requiredTuning,
      requiredSkillIds: requiredSkillIds ?? this.requiredSkillIds,
      requiredCapabilities: requiredCapabilities ?? this.requiredCapabilities,
      assetAvailableLocally:
          assetAvailableLocally ?? this.assetAvailableLocally,
    ),
    PracticePlanBlockAdapter.song => PracticePlanBlock.song(
      id: id ?? this.id,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      songId: songId!,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      requiredTuning: requiredTuning ?? this.requiredTuning,
      requiredSkillIds: requiredSkillIds ?? this.requiredSkillIds,
      requiredCapabilities: requiredCapabilities ?? this.requiredCapabilities,
      assetAvailableLocally:
          assetAvailableLocally ?? this.assetAvailableLocally,
    ),
  };
}
