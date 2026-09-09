/// Controlled rollout stages bound to the release gate (E14-R24 strum,
/// E14-R33 chord; ADR 0537/0541).
///
/// The rule this file exists to enforce: **a rollout flag can never exceed
/// what the gate licenses.** The flag is a REQUEST; the effective stage is
/// the request clamped by [RecognitionGateVerdict]. A stage is licensed only
/// when every threshold row that guards it is (a) enabled and (b) passing —
/// so a stage whose rows ship DISABLED (the SDD Ch14 §7.3/§7.5 Beta rows
/// today) is unreachable no matter what the flag says. Missing evidence
/// never reads as permission (ADR 0511 D1, extended to rollout).
///
/// **Flag ownership.** The two flags this clamp reads are declared and owned
/// by the feature-flag registry (`lib/core/feature_flags/…`, PKG-D). This
/// file names them as STRINGS only ([recognitionRolloutFlagNames]) and never
/// imports the registry: the evaluation layer must stay Flutter- and
/// provider-free, and the coupling stays a name, not a dependency.
library;

import 'recognition_release_gate.dart';

/// The rollout ladder. Ordered: a later value is a wider audience.
enum RecognitionRolloutStage {
  /// Nobody gets the new model. The fail-closed floor.
  off,

  /// The internal Alpha group (SDD Ch14 §7.2/§7.4 gates).
  internalAlpha,

  /// The opt-in public Beta (SDD Ch14 §7.3/§7.5 gates).
  optInBeta,

  /// A percentage rollout of the general population. Requires the same
  /// measured evidence as [optInBeta]; the additional human sign-off (the
  /// R40 field study) is a process step this evaluator cannot and does not
  /// represent.
  percentageRollout;

  /// Ladder position — `off` is 0.
  int get rank => index;

  /// Parses a flag value. An unrecognised value returns `null`, and
  /// [clampRolloutStage] then treats the request as [off] — an unknown
  /// stage is never optimistically resolved to the nearest known one.
  static RecognitionRolloutStage? tryParseFlagValue(String? value) {
    for (final stage in RecognitionRolloutStage.values) {
      if (stage.name == value) return stage;
    }
    return null;
  }

  String toJson() => name;
}

/// The flag names PKG-D's registry declares, quoted here for coordination.
/// Changing a name here without changing the registry breaks nothing at
/// compile time, so the round's rollout test pins both spellings.
const Map<RecognitionGateBand, String> recognitionRolloutFlagNames =
    <RecognitionGateBand, String>{
      RecognitionGateBand.strum: 'strumModelRolloutStage',
      RecognitionGateBand.chord: 'chordModelRolloutStage',
    };

/// Which gate stage a rollout stage requires. `off` requires nothing.
RecognitionGateStage? requiredGateStageFor(RecognitionRolloutStage stage) =>
    switch (stage) {
      RecognitionRolloutStage.off => null,
      RecognitionRolloutStage.internalAlpha => RecognitionGateStage.alpha,
      RecognitionRolloutStage.optInBeta => RecognitionGateStage.beta,
      RecognitionRolloutStage.percentageRollout => RecognitionGateStage.beta,
    };

/// Why a rollout stage was not licensed.
enum RolloutClampReason {
  /// The request was already licensed — nothing was clamped.
  notClamped,

  /// The flag value was not a known stage.
  unrecognisedFlagValue,

  /// A row guarding the requested stage is below its threshold or missing.
  gateRowFailing,

  /// A row guarding the requested stage ships disabled (informational), so
  /// the stage has no evidence to stand on.
  gateRowDisabled,

  /// The gate declares no row at all for the requested stage — an empty
  /// requirement is not a passed requirement.
  noGateRowForStage,
}

/// The clamp result: what was asked for, what is actually permitted, and the
/// findings that limited it (named, so the answer is auditable).
final class RolloutDecision {
  const RolloutDecision({
    required this.band,
    required this.requested,
    required this.effective,
    required this.reason,
    required this.limitingMetricPaths,
  });

  final RecognitionGateBand band;

  /// `null` when the flag value was not a known stage.
  final RecognitionRolloutStage? requested;

  final RecognitionRolloutStage effective;
  final RolloutClampReason reason;

  /// The `metricPath`s that blocked the request, sorted. Empty when nothing
  /// was clamped.
  final List<String> limitingMetricPaths;

  bool get wasClamped => requested == null || effective != requested;

  Map<String, Object?> toJson() => <String, Object?>{
    'band': band.toJson(),
    'requested': requested?.toJson(),
    'effective': effective.toJson(),
    'reason': reason.name,
    'limitingMetricPaths': limitingMetricPaths,
  };
}

/// Clamps a requested rollout [flagValue] for [band] against [verdict].
///
/// The walk is bottom-up: the highest stage whose gate rows are all enabled
/// and passing wins, and the answer is then capped at the request. So a flag
/// asking for `percentageRollout` on a gate that only licenses
/// `internalAlpha` yields `internalAlpha` (with the blocking metric paths
/// named), and a flag asking for `off` always yields `off` — the clamp can
/// only ever REDUCE exposure.
RolloutDecision clampRolloutStage({
  required RecognitionGateBand band,
  required String? flagValue,
  required RecognitionGateVerdict verdict,
}) {
  final requested = RecognitionRolloutStage.tryParseFlagValue(flagValue);
  if (requested == null) {
    return RolloutDecision(
      band: band,
      requested: null,
      effective: RecognitionRolloutStage.off,
      reason: RolloutClampReason.unrecognisedFlagValue,
      limitingMetricPaths: const <String>[],
    );
  }
  if (requested == RecognitionRolloutStage.off) {
    return RolloutDecision(
      band: band,
      requested: requested,
      effective: RecognitionRolloutStage.off,
      reason: RolloutClampReason.notClamped,
      limitingMetricPaths: const <String>[],
    );
  }

  var effective = RecognitionRolloutStage.off;
  var reason = RolloutClampReason.notClamped;
  var limiting = const <String>[];
  for (final candidate in RecognitionRolloutStage.values) {
    if (candidate == RecognitionRolloutStage.off) continue;
    if (candidate.rank > requested.rank) break;
    final licence = _licenceFor(band, candidate, verdict);
    if (licence.granted) {
      effective = candidate;
      continue;
    }
    reason = licence.reason;
    limiting = licence.limitingMetricPaths;
    break;
  }
  return RolloutDecision(
    band: band,
    requested: requested,
    effective: effective,
    reason: effective == requested ? RolloutClampReason.notClamped : reason,
    limitingMetricPaths: effective == requested ? const <String>[] : limiting,
  );
}

final class _StageLicence {
  const _StageLicence(this.granted, this.reason, this.limitingMetricPaths);

  final bool granted;
  final RolloutClampReason reason;
  final List<String> limitingMetricPaths;
}

_StageLicence _licenceFor(
  RecognitionGateBand band,
  RecognitionRolloutStage stage,
  RecognitionGateVerdict verdict,
) {
  final requiredStage = requiredGateStageFor(stage);
  if (requiredStage == null) {
    return const _StageLicence(true, RolloutClampReason.notClamped, []);
  }
  final rows = <RecognitionGateFinding>[
    for (final finding in verdict.findings)
      if (finding.stage == requiredStage && finding.band.constrains(band))
        finding,
  ];
  if (rows.isEmpty) {
    return const _StageLicence(false, RolloutClampReason.noGateRowForStage, []);
  }
  final disabled = <String>[];
  final failing = <String>[];
  for (final row in rows) {
    if (!row.enabled) {
      disabled.add(row.metricPath);
    } else if (!row.passed) {
      failing.add(row.metricPath);
    }
  }
  disabled.sort();
  failing.sort();
  if (disabled.isNotEmpty) {
    return _StageLicence(false, RolloutClampReason.gateRowDisabled, disabled);
  }
  if (failing.isNotEmpty) {
    return _StageLicence(false, RolloutClampReason.gateRowFailing, failing);
  }
  return const _StageLicence(true, RolloutClampReason.notClamped, []);
}
