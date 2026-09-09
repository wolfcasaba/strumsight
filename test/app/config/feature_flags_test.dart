import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/config/recognition_rollout_stage.dart';
import 'package:strumsight/core/feature_flags/public.dart';

void main() {
  ch14Main();

  group('Practice Generator feature flags', () {
    test('constructor defaults are off at the rollout boundary', () {
      const flags = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );

      expect(flags.practiceGeneratorEnabled, isFalse);
      expect(flags.plannerAssistEnabled, isFalse);
      expect(flags.toString(), contains('practiceGeneratorEnabled: false'));
      expect(flags.toString(), contains('plannerAssistEnabled: false'));
    });

    test('factory keeps both flags off in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(flags.practiceGeneratorEnabled, isFalse);
      expect(flags.plannerAssistEnabled, isFalse);
    });

    // E15-R07 F1 (ADR 0491 D2) — the rollout boundary moved: outside
    // production, `practiceGeneratorEnabled` now follows the same `nonProd`
    // pattern as `practiceEngineV2Enabled`. `plannerAssistEnabled`
    // (model-assisted suggestions) is a separate rollout decision and stays
    // OFF everywhere, including non-production.
    test(
      'factory turns practiceGeneratorEnabled on but keeps plannerAssistEnabled '
      'off in non-production (ADR 0491)',
      () {
        final flags = FeatureFlags.forEnvironment(
          AppEnvironment.development,
          accountEnabled: false,
        );

        expect(flags.practiceGeneratorEnabled, isTrue);
        expect(flags.plannerAssistEnabled, isFalse);
      },
    );
  });

  group('Recognition recovery feature flags', () {
    test('constructor defaults are off and participate in value semantics', () {
      const defaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      const recoveryEnabled = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        recognitionRecoveryEnabled: true,
      );

      expect(defaults.recognitionRecoveryEnabled, isFalse);
      expect(defaults.recognitionShadowModeEnabled, isFalse);
      expect(defaults.newLiveStageEnabled, isFalse);
      expect(
        defaults.toString(),
        contains('recognitionRecoveryEnabled: false'),
      );
      expect(
        defaults.toString(),
        contains('recognitionShadowModeEnabled: false'),
      );
      expect(defaults.toString(), contains('newLiveStageEnabled: false'));
      expect(recoveryEnabled, isNot(equals(defaults)));
      expect(recoveryEnabled.hashCode, isNot(equals(defaults.hashCode)));
    });

    test('factory keeps all flags off in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      _expectRecognitionRecoveryFlagsOff(flags);
    });

    test('factory keeps all flags off in lab', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      _expectRecognitionRecoveryFlagsOff(flags);
    });

    test('factory keeps all flags off in development', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      _expectRecognitionRecoveryFlagsOff(flags);
    });
  });

  group('Community feature flags (E09-R01, ADR 0395)', () {
    // All five new flags default OFF at the rollout boundary — no Community
    // surface area should be reachable from a flag set built without an
    // explicit override.
    test(
      'constructor defaults are all off and participate in value semantics',
      () {
        const defaults = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
        );

        _expectCommunityFlagsOff(defaults);

        // toString surfaces every new flag — regression guard for the matrix.
        expect(defaults.toString(), contains('communityEnabled: false'));
        expect(defaults.toString(), contains('communityWritesEnabled: false'));
        expect(defaults.toString(), contains('communityMediaEnabled: false'));
        expect(
          defaults.toString(),
          contains('communityLeaderboardEnabled: false'),
        );
        expect(defaults.toString(), contains('communityClubsEnabled: false'));

        // Value semantics — a flag set with one Community flag flipped must
        // compare unequal and hash differently.
        const withMaster = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          communityEnabled: true,
        );
        expect(withMaster, isNot(equals(defaults)));
        expect(withMaster.hashCode, isNot(equals(defaults.hashCode)));
        expect(withMaster.communityEnabled, isTrue);
        expect(withMaster.communityWritesEnabled, isFalse);
      },
    );

    // A1 / A2 — the kill switch. Production MUST resolve every Community flag
    // to `false` regardless of any accidental compile-time state, because the
    // dart-defines have no default value.
    test('factory keeps all five flags OFF in production (A1)', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      _expectCommunityFlagsOff(flags);
    });

    // A2 — development/lab are gated by an explicit compile-time kill switch,
    // so the factory without any dart-defines also stays OFF in those
    // environments. A developer who wants Community in dev must pass the
    // define at build time (which `flutter test` does not do).
    test('factory keeps all five flags OFF in development (A2)', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      _expectCommunityFlagsOff(flags);
    });

    test('factory keeps all five flags OFF in lab (A2)', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      _expectCommunityFlagsOff(flags);
    });

    // Explicit overrides through the named constructor must be honoured
    // verbatim — the kill switch property lives at the *factory* layer
    // (because that is where the dart-define read happens), not at the
    // constructor layer. A caller that builds a flags instance explicitly
    // is opting in.
    test('explicit communityEnabled=true is honoured by the constructor', () {
      const flags = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        communityEnabled: true,
        communityWritesEnabled: true,
        communityMediaEnabled: false,
        communityLeaderboardEnabled: false,
        communityClubsEnabled: false,
      );

      expect(flags.communityEnabled, isTrue);
      expect(flags.communityWritesEnabled, isTrue);
      expect(flags.communityMediaEnabled, isFalse);
      expect(flags.communityLeaderboardEnabled, isFalse);
      expect(flags.communityClubsEnabled, isFalse);
    });
  });
}

void _expectRecognitionRecoveryFlagsOff(FeatureFlags flags) {
  expect(flags.recognitionRecoveryEnabled, isFalse);
  expect(flags.recognitionShadowModeEnabled, isFalse);
  expect(flags.newLiveStageEnabled, isFalse);
}

void _expectCommunityFlagsOff(FeatureFlags flags) {
  expect(flags.communityEnabled, isFalse, reason: 'communityEnabled');
  expect(
    flags.communityWritesEnabled,
    isFalse,
    reason: 'communityWritesEnabled',
  );
  expect(flags.communityMediaEnabled, isFalse, reason: 'communityMediaEnabled');
  expect(
    flags.communityLeaderboardEnabled,
    isFalse,
    reason: 'communityLeaderboardEnabled',
  );
  expect(flags.communityClubsEnabled, isFalse, reason: 'communityClubsEnabled');
}

// ---------------------------------------------------------------------------
// E14-R23/R24/R33/R40/R41 (ADR 0542) — the recognition rollout flag surface.
// ---------------------------------------------------------------------------

void _expectCh14FlagsOff(FeatureFlags flags) {
  expect(
    flags.recognitionChordShadowModeEnabled,
    isFalse,
    reason: 'recognitionChordShadowModeEnabled',
  );
  expect(
    flags.recognitionPreprocessingEnabled,
    isFalse,
    reason: 'recognitionPreprocessingEnabled',
  );
  expect(
    flags.recognitionFieldSessionTaggingEnabled,
    isFalse,
    reason: 'recognitionFieldSessionTaggingEnabled',
  );
  expect(
    flags.strumModelRolloutStage,
    RecognitionRolloutStage.off,
    reason: 'strumModelRolloutStage',
  );
  expect(
    flags.chordModelRolloutStage,
    RecognitionRolloutStage.off,
    reason: 'chordModelRolloutStage',
  );
}

void ch14Main() {
  group('RecognitionRolloutStage — the ladder is closed and ordered', () {
    test('only `off` runs nothing', () {
      final running = RecognitionRolloutStage.values
          .where((stage) => stage.runsInference)
          .toSet();
      expect(running, isNot(contains(RecognitionRolloutStage.off)));
      expect(running, hasLength(RecognitionRolloutStage.values.length - 1));
    });

    test('shadow RUNS but is never user-visible — the one invariant the '
        'whole shadow mode rests on', () {
      expect(RecognitionRolloutStage.shadow.runsInference, isTrue);
      expect(RecognitionRolloutStage.shadow.isUserVisible, isFalse);
    });

    test('exactly alpha, beta and ga are user-visible', () {
      final visible = RecognitionRolloutStage.values
          .where((stage) => stage.isUserVisible)
          .toList();
      expect(visible, <RecognitionRolloutStage>[
        RecognitionRolloutStage.alpha,
        RecognitionRolloutStage.beta,
        RecognitionRolloutStage.ga,
      ]);
    });

    test('beta and ga require the Beta thresholds, everything below does '
        'not', () {
      final betaBar = RecognitionRolloutStage.values
          .where((stage) => stage.requiresBetaThresholds)
          .toList();
      expect(betaBar, <RecognitionRolloutStage>[
        RecognitionRolloutStage.beta,
        RecognitionRolloutStage.ga,
      ]);
    });

    test('tryParse is fail-closed: an unknown or misspelled stage is null, '
        'never a more permissive neighbour', () {
      expect(RecognitionRolloutStage.tryParse(null), isNull);
      expect(RecognitionRolloutStage.tryParse(''), isNull);
      expect(RecognitionRolloutStage.tryParse('GA'), isNull);
      expect(RecognitionRolloutStage.tryParse('generalAvailability'), isNull);
      expect(
        RecognitionRolloutStage.tryParse('shadow'),
        RecognitionRolloutStage.shadow,
      );
    });
  });

  group('Ch14 recognition rollout flags', () {
    test('the constructor defaults every Ch14 gate to off/none', () {
      const flags = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );

      _expectCh14FlagsOff(flags);
      expect(flags.recognitionShadowModeEnabled, isFalse);
      expect(flags.betaTelemetryEnabled, isFalse);
    });

    test('production resolves every Ch14 gate to off, beta telemetry '
        'included', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      _expectCh14FlagsOff(flags);
      expect(flags.recognitionShadowModeEnabled, isFalse);
      expect(flags.betaTelemetryEnabled, isFalse);
    });

    test('NON-production also resolves every recognition gate to off — no '
        'Ch14 §7 threshold is green on the measured baseline, so a dev '
        'build must not claim a rollout level either', () {
      for (final environment in <AppEnvironment>[
        AppEnvironment.development,
        AppEnvironment.lab,
      ]) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );

        _expectCh14FlagsOff(flags);
        expect(
          flags.recognitionShadowModeEnabled,
          isFalse,
          reason: '${environment.name}: recognitionShadowModeEnabled',
        );
      }
    });

    test('betaTelemetryEnabled follows the diagnostics boundary: available '
        'outside production, absent inside it', () {
      final development = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );
      final production = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(development.betaTelemetryEnabled, isTrue);
      expect(development.diagnosticsEnabled, isTrue);
      expect(production.betaTelemetryEnabled, isFalse);
      expect(production.diagnosticsEnabled, isFalse);
    });

    test('the new flags participate in value semantics and toString — a '
        'flag the equality forgets is a flag a config diff cannot show', () {
      const defaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      const chordShadow = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        recognitionChordShadowModeEnabled: true,
      );
      const strumShadowStage = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        strumModelRolloutStage: RecognitionRolloutStage.shadow,
      );
      const strumGaStage = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        strumModelRolloutStage: RecognitionRolloutStage.ga,
      );

      expect(chordShadow, isNot(equals(defaults)));
      expect(strumShadowStage, isNot(equals(defaults)));
      expect(
        strumShadowStage,
        isNot(equals(strumGaStage)),
        reason: 'two different non-off stages are two different configs',
      );
      expect(
        strumShadowStage.hashCode,
        isNot(equals(strumGaStage.hashCode)),
        reason:
            'the stage must reach the hash, not just the "is it off" bit',
      );
      expect(
        defaults.toString(),
        contains('strumModelRolloutStage: off'),
      );
      expect(
        defaults.toString(),
        contains('chordModelRolloutStage: off'),
      );
      expect(defaults.toString(), contains('betaTelemetryEnabled: false'));
    });
  });

  group('featureFlagRegistry — the Ch14 additions are catalogued, and the '
      'enum fields deliberately are NOT (ADR 0542 D4)', () {
    Set<String> keysOf() => featureFlagRegistry.map((d) => d.key).toSet();

    test('every new BOOL flag has a catalog entry with an owner and a '
        'kill-switch path', () {
      for (final key in <String>[
        'recognitionChordShadowModeEnabled',
        'recognitionPreprocessingEnabled',
        'recognitionFieldSessionTaggingEnabled',
        'betaTelemetryEnabled',
      ]) {
        final entry = featureFlagRegistry.singleWhere((d) => d.key == key);
        expect(entry.owner.trim(), isNotEmpty, reason: key);
        expect(entry.killSwitchPath.trim(), isNotEmpty, reason: key);
        expect(entry.failClosedDefault, isFalse, reason: key);
      }
    });

    test('the two rollout-stage ENUM fields have no catalog entry — the '
        'registry audit parses `final bool` declarations, so an entry for '
        'a non-bool field would report unknownCatalogEntry forever', () {
      expect(keysOf(), isNot(contains('strumModelRolloutStage')));
      expect(keysOf(), isNot(contains('chordModelRolloutStage')));
    });

    test('the registry stays in sync with the SOURCE in both directions — '
        'the same parse tool/check_feature_flags.dart performs, repeated '
        'here so a missing entry is red in the unit suite too', () {
      final source = File(
        'lib/app/config/feature_flags.dart',
      ).readAsStringSync();
      final fieldNames = RegExp(
        r'^\s*final bool\??\s+(\w+)\s*(?:;|=)',
        multiLine: true,
      ).allMatches(source).map((match) => match.group(1)!).toSet();

      expect(fieldNames.difference(keysOf()), isEmpty);
      expect(keysOf().difference(fieldNames), isEmpty);
      expect(
        fieldNames,
        contains('betaTelemetryEnabled'),
        reason: 'the parse must actually see the new fields',
      );
    });

    test('the beta-telemetry entry names all three gates in its prose, not '
        'just the flag — an operator reading only this entry must not '
        'conclude the flag alone sends data', () {
      final entry = featureFlagRegistry.singleWhere(
        (d) => d.key == 'betaTelemetryEnabled',
      );

      expect(entry.killSwitchPath, contains('diagnosticsEnabled'));
      expect(entry.killSwitchPath, contains('consent'));
      expect(entry.risk, FeatureFlagRisk.high);
    });
  });
}
