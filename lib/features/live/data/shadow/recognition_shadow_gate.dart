import 'package:meta/meta.dart';

import '../../../../app/config/feature_flags.dart';
import '../../../../app/config/recognition_rollout_stage.dart';

/// The ONE place the two-part shadow gate is evaluated (E14-R23, ADR 0548
/// D1) — the consumer PKG-D's `recognitionShadowModeEnabled` doc promises.
///
/// The contract, restated so it cannot be read two ways: a band's shadow
/// inference may run only when BOTH
///
/// * its rollout stage `.runsInference` is true, AND
/// * its master switch is true.
///
/// The AND is asymmetric — either half alone turns the path OFF, neither
/// half alone turns it ON — so killing shadow work in an incident is one
/// boolean, and promoting a stage cannot switch inference on by accident.
/// Both defaults are fail-closed (`off` / `false`), so a build that says
/// nothing runs nothing.
@immutable
class RecognitionShadowGate {
  const RecognitionShadowGate({
    required this.strumEnabled,
    required this.chordEnabled,
    required this.strumStage,
    required this.chordStage,
  });

  /// Reads the gate off the shipped flags. No other input: a Lab toggle, a
  /// debug build or a user preference must not be able to widen it.
  factory RecognitionShadowGate.fromFlags(FeatureFlags flags) =>
      RecognitionShadowGate(
        strumEnabled:
            flags.recognitionShadowModeEnabled &&
            flags.strumModelRolloutStage.runsInference,
        chordEnabled:
            flags.recognitionChordShadowModeEnabled &&
            flags.chordModelRolloutStage.runsInference,
        strumStage: flags.strumModelRolloutStage,
        chordStage: flags.chordModelRolloutStage,
      );

  /// Everything closed — the shape a build with no opinion gets.
  static const RecognitionShadowGate closed = RecognitionShadowGate(
    strumEnabled: false,
    chordEnabled: false,
    strumStage: RecognitionRolloutStage.off,
    chordStage: RecognitionRolloutStage.off,
  );

  final bool strumEnabled;
  final bool chordEnabled;
  final RecognitionRolloutStage strumStage;
  final RecognitionRolloutStage chordStage;

  /// True when at least one band may run. When this is false the shadow
  /// session must not construct a pipeline, parse a model or compute a
  /// single CQT frame — "zero extra inference", not "a cheap call whose
  /// result is dropped".
  bool get runsAnything => strumEnabled || chordEnabled;

  /// A shadow-stage band is never user-visible. Kept as a derived getter so
  /// a test can pin the invariant against the gate, not only against the
  /// enum.
  bool get anyBandUserVisible =>
      strumStage.isUserVisible || chordStage.isUserVisible;

  @override
  bool operator ==(Object other) =>
      other is RecognitionShadowGate &&
      other.strumEnabled == strumEnabled &&
      other.chordEnabled == chordEnabled &&
      other.strumStage == strumStage &&
      other.chordStage == chordStage;

  @override
  int get hashCode =>
      Object.hash(strumEnabled, chordEnabled, strumStage, chordStage);

  @override
  String toString() =>
      'RecognitionShadowGate(strum: $strumEnabled/${strumStage.name}, '
      'chord: $chordEnabled/${chordStage.name})';
}
