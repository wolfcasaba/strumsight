import 'reward_reason.dart';

/// Component-level breakdown of a single reward.
///
/// Every reward produced by the E08-R06 policy is decomposed into the five
/// receipt-facing components the interface and audit trail require
/// (ADR 0341 §1). The component totals are summed into [totalXp] for ledger
/// matching, but the per-component view is mandatory — collapsing them
/// downstream is a §6.1 violation.
final class ExperiencePoints {
  ExperiencePoints._({
    required this.baseXp,
    required this.durationXp,
    required this.qualityXp,
    required this.improvementXp,
    required this.diversityXp,
    required List<RewardReason> reductionReasons,
  }) : reductionReasons = List<RewardReason>.unmodifiable(reductionReasons),
       totalXp = baseXp + durationXp + qualityXp + improvementXp + diversityXp;

  /// Builds a five-component reward, validating non-negativity.
  factory ExperiencePoints({
    int baseXp = 0,
    int durationXp = 0,
    int qualityXp = 0,
    int improvementXp = 0,
    int diversityXp = 0,
    List<RewardReason> reductionReasons = const <RewardReason>[],
  }) {
    for (final entry in <String, int>{
      'baseXp': baseXp,
      'durationXp': durationXp,
      'qualityXp': qualityXp,
      'improvementXp': improvementXp,
      'diversityXp': diversityXp,
    }.entries) {
      if (entry.value < 0) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'must not be negative',
        );
      }
    }
    return ExperiencePoints._(
      baseXp: baseXp,
      durationXp: durationXp,
      qualityXp: qualityXp,
      improvementXp: improvementXp,
      diversityXp: diversityXp,
      reductionReasons: reductionReasons,
    );
  }

  /// A zero, reduction-free reward — used when no component is granted.
  factory ExperiencePoints.empty() => ExperiencePoints();

  final int baseXp;
  final int durationXp;
  final int qualityXp;
  final int improvementXp;
  final int diversityXp;

  /// Sum of the five components. Always equal to
  /// `baseXp + durationXp + qualityXp + improvementXp + diversityXp`.
  final int totalXp;

  /// The reasons applied by the cap, repeat decay, or parent/child dedup
  /// layers. The gate layer (R05) emits its own [RewardReason] values; this
  /// list only tracks policy-side reductions so the two are auditable
  /// separately.
  final List<RewardReason> reductionReasons;

  ExperiencePoints operator +(ExperiencePoints other) => ExperiencePoints(
    baseXp: baseXp + other.baseXp,
    durationXp: durationXp + other.durationXp,
    qualityXp: qualityXp + other.qualityXp,
    improvementXp: improvementXp + other.improvementXp,
    diversityXp: diversityXp + other.diversityXp,
    reductionReasons: <RewardReason>[
      ...reductionReasons,
      ...other.reductionReasons,
    ],
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'baseXp': baseXp,
    'durationXp': durationXp,
    'qualityXp': qualityXp,
    'improvementXp': improvementXp,
    'diversityXp': diversityXp,
    'totalXp': totalXp,
    'reductionReasons': reductionReasons
        .map((reason) => reason.name)
        .toList(growable: false),
  };

  factory ExperiencePoints.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    final reasons = json['reductionReasons'];
    if (reasons is! List<Object?>) {
      throw ArgumentError.value(reasons, 'reductionReasons', 'must be a list');
    }
    return ExperiencePoints(
      baseXp: _requireInt(json, 'baseXp'),
      durationXp: _requireInt(json, 'durationXp'),
      qualityXp: _requireInt(json, 'qualityXp'),
      improvementXp: _requireInt(json, 'improvementXp'),
      diversityXp: _requireInt(json, 'diversityXp'),
      reductionReasons: <RewardReason>[
        for (final code in reasons) _reasonFromJson(code),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExperiencePoints &&
      baseXp == other.baseXp &&
      durationXp == other.durationXp &&
      qualityXp == other.qualityXp &&
      improvementXp == other.improvementXp &&
      diversityXp == other.diversityXp &&
      _sameReasons(reductionReasons, other.reductionReasons);

  @override
  int get hashCode => Object.hash(
    baseXp,
    durationXp,
    qualityXp,
    improvementXp,
    diversityXp,
    Object.hashAll(reductionReasons),
  );
}

int _requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw ArgumentError.value(value, key, 'must be an int');
  }
  return value;
}

RewardReason _reasonFromJson(Object? json) {
  if (json is! String) {
    throw ArgumentError.value(json, 'reductionReason', 'must be a string');
  }
  try {
    return RewardReason.values.byName(json);
  } on ArgumentError {
    throw ArgumentError.value(
      json,
      'reductionReason',
      'is not a supported reason code',
    );
  }
}

bool _sameReasons(List<RewardReason> left, List<RewardReason> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
