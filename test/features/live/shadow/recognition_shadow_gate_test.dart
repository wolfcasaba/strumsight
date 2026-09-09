// E14-R23 — the two-part shadow gate (ADR 0548 D1).
//
// RED before this round: `RecognitionShadowGate` did not exist and PKG-D's
// flags had ZERO consumers in lib/**. These cells are the consumer contract
// the flag documentation promises.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/config/recognition_rollout_stage.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_gate.dart';

FeatureFlags _flags({
  bool strumSwitch = false,
  bool chordSwitch = false,
  RecognitionRolloutStage strumStage = RecognitionRolloutStage.off,
  RecognitionRolloutStage chordStage = RecognitionRolloutStage.off,
}) => FeatureFlags(
  recognitionShadowModeEnabled: strumSwitch,
  recognitionChordShadowModeEnabled: chordSwitch,
  strumModelRolloutStage: strumStage,
  chordModelRolloutStage: chordStage,
);

void main() {
  group('RecognitionShadowGate — the asymmetric AND', () {
    test('neither half alone opens the strum band', () {
      expect(
        RecognitionShadowGate.fromFlags(_flags(strumSwitch: true)).strumEnabled,
        isFalse,
        reason: 'the master switch alone must not run inference',
      );
      expect(
        RecognitionShadowGate.fromFlags(
          _flags(strumStage: RecognitionRolloutStage.shadow),
        ).strumEnabled,
        isFalse,
        reason: 'the rollout stage alone must not run inference',
      );
    });

    test('both halves together open it', () {
      final gate = RecognitionShadowGate.fromFlags(
        _flags(strumSwitch: true, strumStage: RecognitionRolloutStage.shadow),
      );
      expect(gate.strumEnabled, isTrue);
      expect(gate.chordEnabled, isFalse);
      expect(gate.runsAnything, isTrue);
    });

    test('the chord band is gated INDEPENDENTLY of the strum band', () {
      final gate = RecognitionShadowGate.fromFlags(
        _flags(
          strumSwitch: true,
          strumStage: RecognitionRolloutStage.shadow,
          chordSwitch: true,
        ),
      );
      expect(gate.strumEnabled, isTrue);
      expect(
        gate.chordEnabled,
        isFalse,
        reason: 'chordModelRolloutStage is still off',
      );
    });

    test('every stage that runs inference opens the band when switched on', () {
      for (final stage in RecognitionRolloutStage.values) {
        final gate = RecognitionShadowGate.fromFlags(
          _flags(chordSwitch: true, chordStage: stage),
        );
        expect(gate.chordEnabled, stage.runsInference, reason: stage.name);
      }
    });

    test('the closed gate is the fail-closed default shape', () {
      expect(
        RecognitionShadowGate.fromFlags(_flags()),
        RecognitionShadowGate.closed,
      );
      expect(RecognitionShadowGate.closed.runsAnything, isFalse);
      expect(RecognitionShadowGate.closed.anyBandUserVisible, isFalse);
    });

    test('a shadow-stage band is never user-visible', () {
      final gate = RecognitionShadowGate.fromFlags(
        _flags(
          strumSwitch: true,
          strumStage: RecognitionRolloutStage.shadow,
          chordSwitch: true,
          chordStage: RecognitionRolloutStage.shadow,
        ),
      );
      expect(gate.runsAnything, isTrue);
      expect(
        gate.anyBandUserVisible,
        isFalse,
        reason: 'shadow runs, shadow is never shown — the whole invariant',
      );
    });

    test('the SHIPPED flags close both bands in every environment', () {
      for (final environment in AppEnvironment.values) {
        final gate = RecognitionShadowGate.fromFlags(
          FeatureFlags.forEnvironment(environment, accountEnabled: false),
        );
        expect(gate.runsAnything, isFalse, reason: environment.name);
      }
    });

    test('value semantics — equal gates compare and hash equal', () {
      final a = RecognitionShadowGate.fromFlags(
        _flags(strumSwitch: true, strumStage: RecognitionRolloutStage.shadow),
      );
      final b = RecognitionShadowGate.fromFlags(
        _flags(strumSwitch: true, strumStage: RecognitionRolloutStage.shadow),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(RecognitionShadowGate.closed));
      expect(a.toString(), contains('shadow'));
    });
  });
}
