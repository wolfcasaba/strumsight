import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';

void main() {
  // WP-E (repair plan 2026-09-06) — `STRUMSIGHT_PREVIEW_ALL`.
  //
  // The define itself is a compile-time constant, so the *semantics* can
  // only be exercised through the `previewAll` parameter seam. `flutter
  // test` never passes the define, so `previewAll` defaults to false here
  // and every pre-existing cell in this file keeps measuring the shipped
  // defaults.
  group('STRUMSIGHT_PREVIEW_ALL preview overlay', () {
    test('development + previewAll turns the listed UI capabilities on and '
        'keeps the four excluded ones off', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: true,
        previewAll: true,
      );

      // ON — on-device surfaces the Lab APK must be able to show.
      expect(flags.aiTutorEnabled, isTrue, reason: 'aiTutorEnabled');
      expect(
        flags.plannerAssistEnabled,
        isTrue,
        reason: 'plannerAssistEnabled',
      );
      for (final entry in _previewOnVisionFlags(flags).entries) {
        expect(entry.value, isTrue, reason: entry.key);
      }
      for (final entry in _previewOnAnalysisFlags(flags).entries) {
        expect(entry.value, isTrue, reason: entry.key);
      }
      expect(
        flags.recognitionRecoveryEnabled,
        isTrue,
        reason: 'recognitionRecoveryEnabled',
      );
      expect(flags.newLiveStageEnabled, isTrue, reason: 'newLiveStageEnabled');

      // Already-`nonProd` capabilities are untouched by the overlay.
      expect(flags.diagnosticsEnabled, isTrue);
      expect(flags.labModeAvailable, isTrue);
      expect(flags.practiceEngineV2Enabled, isTrue);
      expect(flags.migratedLearnEnabled, isTrue);
      expect(flags.practiceDetailedHistoryEnabled, isTrue);
      expect(flags.songTrainerV2Enabled, isTrue);
      expect(flags.practiceGeneratorEnabled, isTrue);
      expect(flags.adaptiveShellEnabled, isTrue);
      expect(flags.accountEnabled, isTrue, reason: 'caller-supplied');

      // OFF by design — data egress / raw-frame persistence / cost.
      expect(
        flags.aiTutorCloudEnabled,
        isFalse,
        reason: 'aiTutorCloudEnabled sends user data off device (ADR 0132)',
      );
      expect(
        flags.visionLabCaptureEnabled,
        isFalse,
        reason: 'visionLabCaptureEnabled persists raw frames (ADR 0178 §4)',
      );
      expect(
        flags.recognitionShadowModeEnabled,
        isFalse,
        reason: 'shadow mode has no UI surface, only cost (ADR 0271)',
      );

      // Community stays define-driven (ADR 0395) — the overlay must not
      // become a second way to open the audited kill switch.
      _expectCommunityFlagsOff(flags);
    });

    test('production ignores previewAll entirely (identical flag set)', () {
      final withoutPreview = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: true,
      );
      final withPreview = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: true,
        previewAll: true,
      );

      expect(withPreview, equals(withoutPreview));
      expect(withPreview.hashCode, equals(withoutPreview.hashCode));
      expect(withPreview.toString(), equals(withoutPreview.toString()));
    });

    test(
      'lab + previewAll is a real change, i.e. the overlay is not a no-op',
      () {
        final plain = FeatureFlags.forEnvironment(
          AppEnvironment.lab,
          accountEnabled: false,
        );
        final preview = FeatureFlags.forEnvironment(
          AppEnvironment.lab,
          accountEnabled: false,
          previewAll: true,
        );

        expect(preview, isNot(equals(plain)));
        expect(preview.aiTutorEnabled, isTrue);
        expect(plain.aiTutorEnabled, isFalse);
      },
    );

    // Pins TODAY's development defaults so the parameter seam cannot
    // silently flip one of them: without the define, `forEnvironment` must
    // resolve exactly as it did before WP-E.
    test('development without previewAll is unchanged (pinned defaults)', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      expect(flags.accountEnabled, isFalse);
      expect(flags.diagnosticsEnabled, isTrue);
      expect(flags.labModeAvailable, isTrue);
      expect(flags.practiceEngineV2Enabled, isTrue);
      expect(flags.migratedLearnEnabled, isTrue);
      expect(flags.practiceDetailedHistoryEnabled, isTrue);
      expect(flags.songTrainerV2Enabled, isTrue);
      expect(flags.practiceGeneratorEnabled, isTrue);
      expect(flags.adaptiveShellEnabled, isTrue);

      expect(flags.aiTutorEnabled, isFalse);
      expect(flags.aiTutorCloudEnabled, isFalse);
      expect(flags.plannerAssistEnabled, isFalse);
      for (final entry in _previewOnVisionFlags(flags).entries) {
        expect(entry.value, isFalse, reason: entry.key);
      }
      expect(flags.visionLabCaptureEnabled, isFalse);
      for (final entry in _previewOnAnalysisFlags(flags).entries) {
        expect(entry.value, isFalse, reason: entry.key);
      }
      expect(flags.recognitionRecoveryEnabled, isFalse);
      expect(flags.recognitionShadowModeEnabled, isFalse);
      expect(flags.newLiveStageEnabled, isFalse);
      _expectCommunityFlagsOff(flags);
    });
  });

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

/// The ten Vision capabilities the preview overlay turns on —
/// `visionLabCaptureEnabled` is deliberately NOT in this map.
Map<String, bool> _previewOnVisionFlags(FeatureFlags flags) => <String, bool>{
  'visionEnabled': flags.visionEnabled,
  'visionSetupEnabled': flags.visionSetupEnabled,
  'visionHandTrackingEnabled': flags.visionHandTrackingEnabled,
  'visionPoseTrackingEnabled': flags.visionPoseTrackingEnabled,
  'visionGuitarGeometryEnabled': flags.visionGuitarGeometryEnabled,
  'visionPracticeIntegrationEnabled': flags.visionPracticeIntegrationEnabled,
  'visionSongIntegrationEnabled': flags.visionSongIntegrationEnabled,
  'visionTutorIntegrationEnabled': flags.visionTutorIntegrationEnabled,
  'visionAnalysisIntegrationEnabled': flags.visionAnalysisIntegrationEnabled,
  'visionExperimentalFineFretEnabled': flags.visionExperimentalFineFretEnabled,
};

/// The nine Audio Analysis V2 capabilities the preview overlay turns on.
Map<String, bool> _previewOnAnalysisFlags(FeatureFlags flags) => <String, bool>{
  'audioAnalysisV2Enabled': flags.audioAnalysisV2Enabled,
  'analysisBeatGridEnabled': flags.analysisBeatGridEnabled,
  'analysisPitchEnabled': flags.analysisPitchEnabled,
  'analysisPreprocessingExperimentalEnabled':
      flags.analysisPreprocessingExperimentalEnabled,
  'analysisExperimentalFusionEnabled': flags.analysisExperimentalFusionEnabled,
  'analysisTechniqueProxiesEnabled': flags.analysisTechniqueProxiesEnabled,
  'analysisComparisonEnabled': flags.analysisComparisonEnabled,
  'analysisPracticeIntegrationEnabled':
      flags.analysisPracticeIntegrationEnabled,
  'analysisTutorIntegrationEnabled': flags.analysisTutorIntegrationEnabled,
};

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
