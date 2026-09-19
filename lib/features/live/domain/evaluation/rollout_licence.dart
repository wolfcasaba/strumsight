/// What the release gate LICENSES for a controlled rollout (E14-R24 strum,
/// E14-R33 chord; ADR 0537/0541).
///
/// The rule this file enforces: **a rollout stage can never exceed what the
/// gate licenses.** The configured stage is a REQUEST; the effective stage is
/// that request clamped by a [RecognitionGateVerdict]. A stage is licensed
/// only when every threshold row guarding it is (a) enabled and (b) passing —
/// so a stage whose rows ship DISABLED (the SDD Ch14 §7.3/§7.5 Beta rows
/// today) is unreachable no matter what the configuration says. Missing
/// evidence never reads as permission (ADR 0511 D1, extended to rollout).
///
/// **Ownership and the mirror.** The rollout ladder itself is PKG-D's
/// `lib/app/config/recognition_rollout_stage.dart` (ADR 0542): the enum, the
/// two `FeatureFlags` fields (`strumModelRolloutStage`,
/// `chordModelRolloutStage`) and the reviewed record in
/// `docs/release/ch14-recognition-rollout.md`. The evaluation layer must stay
/// Flutter-, provider- and app-independent, so it does NOT import that type;
/// [LicensedRolloutStage] mirrors it **by name**, value for value, and the
/// round's test pins that mirror against the real enum. Callers pass the
/// stage's `name` and read the effective stage's `name` back.
library;

import 'recognition_release_gate.dart';

/// The rollout ladder, mirroring `RecognitionRolloutStage`
/// (`lib/app/config/recognition_rollout_stage.dart`) name for name.
///
/// Ordered: a later value reaches a wider audience.
enum LicensedRolloutStage {
  /// The band does not run at all.
  off,

  /// The band runs alongside the shipped path, but nothing it produces may
  /// reach a `LiveFrame`, a score or a pixel. Because it is never
  /// user-visible, an ACCURACY gate does not license it — the shadow master
  /// switch does (`FeatureFlags.recognitionShadowModeEnabled` /
  /// `recognitionChordShadowModeEnabled`, ADR 0542 D2).
  shadow,

  /// User-visible in team-controlled builds. SDD Ch14 §7.2/§7.4 Alpha rows.
  alpha,

  /// User-visible for opted-in beta testers. SDD Ch14 §7.3/§7.5 Beta rows.
  beta,

  /// User-visible for everyone the build reaches. Same MEASURED bar as
  /// [beta]; the additional human sign-off (the R40 field study, the
  /// rollback drill) is a process step this evaluator does not represent.
  ga;

  /// Ladder position — `off` is 0.
  int get rank => index;

  /// Parses a stage name (the flag value's `name`). An unrecognised value
  /// returns `null`, and [clampRolloutStage] then treats the request as
  /// [off] — an unknown stage is never optimistically resolved to the
  /// nearest known one.
  static LicensedRolloutStage? tryParseName(String? name) {
    for (final stage in LicensedRolloutStage.values) {
      if (stage.name == name) return stage;
    }
    return null;
  }

  String toJson() => name;
}

/// The `FeatureFlags` field names PKG-D's configuration declares, quoted here
/// for coordination only. This file never imports the flags; the round's test
/// pins both spellings.
const Map<RecognitionGateBand, String> recognitionRolloutFlagNames =
    <RecognitionGateBand, String>{
      RecognitionGateBand.strum: 'strumModelRolloutStage',
      RecognitionGateBand.chord: 'chordModelRolloutStage',
    };

/// Which gate stage a rollout stage requires, or `null` when accuracy rows do
/// not license it at all ([LicensedRolloutStage.off],
/// [LicensedRolloutStage.shadow]).
///
/// This is the machine mirror of `RecognitionRolloutStage
/// .requiresBetaThresholds`: `alpha` needs the Alpha rows, `beta` and `ga`
/// need the Beta rows.
RecognitionGateStage? requiredGateStageFor(LicensedRolloutStage stage) =>
    switch (stage) {
      LicensedRolloutStage.off => null,
      LicensedRolloutStage.shadow => null,
      LicensedRolloutStage.alpha => RecognitionGateStage.alpha,
      LicensedRolloutStage.beta => RecognitionGateStage.beta,
      LicensedRolloutStage.ga => RecognitionGateStage.beta,
    };

/// Why a rollout stage was not licensed.
enum RolloutClampReason {
  /// The request was already licensed — nothing was clamped.
  notClamped,

  /// The configured value was not a known stage name.
  unrecognisedStageName,

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

  /// `null` when the configured value was not a known stage name.
  final LicensedRolloutStage? requested;

  final LicensedRolloutStage effective;
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

/// Clamps a requested rollout [stageName] for [band] against [verdict].
///
/// The walk is bottom-up: the highest stage whose gate rows are all enabled
/// and passing wins, and the answer is then capped at the request. So a
/// configuration asking for `ga` on a gate that only licenses `alpha` yields
/// `alpha` (with the blocking metric paths named), and a configuration asking
/// for `off` always yields `off` — the clamp can only ever REDUCE exposure.
RolloutDecision clampRolloutStage({
  required RecognitionGateBand band,
  required String? stageName,
  required RecognitionGateVerdict verdict,
}) {
  final requested = LicensedRolloutStage.tryParseName(stageName);
  if (requested == null) {
    return RolloutDecision(
      band: band,
      requested: null,
      effective: LicensedRolloutStage.off,
      reason: RolloutClampReason.unrecognisedStageName,
      limitingMetricPaths: const <String>[],
    );
  }

  var effective = LicensedRolloutStage.off;
  var reason = RolloutClampReason.notClamped;
  var limiting = const <String>[];
  for (final candidate in LicensedRolloutStage.values) {
    if (candidate == LicensedRolloutStage.off) continue;
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
  LicensedRolloutStage stage,
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
