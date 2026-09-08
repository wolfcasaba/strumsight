import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/audio_analysis/domain/rollout/analysis_rollout_stage.dart';

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

  // WP-G (repair plan 2026-09-06) — the SHIPPED resolution.
  //
  // The tester APK is what `.github/workflows/build-apk.yml` builds, and that
  // protected workflow passes exactly ONE define
  // (`--dart-define=STRUMSIGHT_ENV=development`). `flutter test` likewise
  // passes none, so calling `forShippedBuild` with no arguments measures the
  // REAL shipped resolution: every `bool? …Define` parameter defaults to the
  // compile-time define, which is `null` (ABSENT) here — exactly what the
  // tester APK's build command produces.
  group('WP-G — FeatureFlags.forShippedBuild', () {
    test('development without any define carries the full tester '
        'configuration', () {
      final flags = FeatureFlags.forShippedBuild(AppEnvironment.development);

      // The account layer is ON, so the app offers login + settings sync
      // against the live backend.
      expect(flags.accountEnabled, isTrue, reason: 'accountEnabled');
      expect(flags.usesNetwork, isTrue);

      // The four text-only Community surfaces are ON…
      expect(flags.communityEnabled, isTrue, reason: 'communityEnabled');
      expect(
        flags.communityWritesEnabled,
        isTrue,
        reason: 'communityWritesEnabled',
      );
      expect(
        flags.communityLeaderboardEnabled,
        isTrue,
        reason: 'communityLeaderboardEnabled',
      );
      expect(
        flags.communityClubsEnabled,
        isTrue,
        reason: 'communityClubsEnabled',
      );
      // …and media stays OFF (open R-SEC-01 / R-PRIV-01 blockers).
      expect(
        flags.communityMediaEnabled,
        isFalse,
        reason: 'communityMediaEnabled must stay define-only',
      );

      // The preview overlay is on, which is what turns Audio Analysis V2 and
      // its nine sub-capabilities, Vision and the AI Tutor's local half on.
      expect(flags.aiTutorEnabled, isTrue, reason: 'previewAll overlay');
      expect(flags.plannerAssistEnabled, isTrue);
      expect(
        flags.audioAnalysisV2Enabled,
        isTrue,
        reason: 'audioAnalysisV2Enabled is implied by the previewAll overlay',
      );
      expect(
        flags.analysisRolloutStage,
        AnalysisRolloutStage.v2OptIn,
        reason: 'the V2 route must actually be the resolved stage',
      );
      for (final entry in _previewOnVisionFlags(flags).entries) {
        expect(entry.value, isTrue, reason: entry.key);
      }
      for (final entry in _previewOnAnalysisFlags(flags).entries) {
        expect(entry.value, isTrue, reason: entry.key);
      }
      expect(flags.recognitionRecoveryEnabled, isTrue);
      expect(flags.newLiveStageEnabled, isTrue);

      // Unchanged non-production capabilities.
      expect(flags.diagnosticsEnabled, isTrue);
      expect(flags.labModeAvailable, isTrue);
      expect(flags.practiceEngineV2Enabled, isTrue);
      expect(flags.migratedLearnEnabled, isTrue);
      expect(flags.practiceDetailedHistoryEnabled, isTrue);
      expect(flags.songTrainerV2Enabled, isTrue);
      expect(flags.practiceGeneratorEnabled, isTrue);
      expect(flags.adaptiveShellEnabled, isTrue);

      // E-R29a: the cloud tutor's ROLLOUT GATE is on in the tester build.
      // Before this it was false in every shipped artifact, so
      // `selectTutorModelGateway` always chose `LocalTutorModelGatewayStub`
      // — a gateway whose `start()` always fails — and the Coach could not
      // answer a single question (2026-09-08 re-audit, BLOCKER B1).
      //
      // This is NOT a consent (ADR 0132 §1/§3): four fail-closed conditions
      // still decide every turn (`tutor_gateway_providers.dart`), which is
      // what `test/features/ai_tutor/presentation/
      // tutor_gateway_selection_test.dart` measures.
      expect(
        flags.aiTutorCloudEnabled,
        isTrue,
        reason: 'the rollout gate is open in the development tester build',
      );

      // The two surfaces the preview overlay still refuses to open,
      // unchanged by WP-G and by E-R29a: raw-frame persistence, and cost
      // without a visible surface.
      expect(flags.visionLabCaptureEnabled, isFalse);
      expect(flags.recognitionShadowModeEnabled, isFalse);
    });

    // Production is the fail-closed environment: WP-G must be invisible
    // there. Equality pins EVERY field at once (the operator compares all
    // 40), and toString pins them by name.
    test('production without any define is byte-identical to the pre-WP-G '
        'forEnvironment resolution', () {
      final shipped = FeatureFlags.forShippedBuild(AppEnvironment.production);
      final pinned = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(shipped, equals(pinned));
      expect(shipped.hashCode, equals(pinned.hashCode));
      expect(shipped.toString(), equals(pinned.toString()));

      // Spelled out as well, so a future change to `forEnvironment` cannot
      // make this cell vacuously true by moving both sides together.
      expect(shipped.accountEnabled, isFalse);
      expect(shipped.diagnosticsEnabled, isFalse);
      expect(shipped.labModeAvailable, isFalse);
      expect(shipped.practiceEngineV2Enabled, isFalse);
      expect(shipped.migratedLearnEnabled, isFalse);
      expect(shipped.practiceDetailedHistoryEnabled, isFalse);
      expect(shipped.songTrainerV2Enabled, isFalse);
      expect(shipped.practiceGeneratorEnabled, isFalse);
      expect(shipped.adaptiveShellEnabled, isFalse);
      expect(shipped.aiTutorEnabled, isFalse);
      expect(shipped.aiTutorCloudEnabled, isFalse);
      expect(shipped.plannerAssistEnabled, isFalse);
      for (final entry in _previewOnVisionFlags(shipped).entries) {
        expect(entry.value, isFalse, reason: entry.key);
      }
      expect(shipped.visionLabCaptureEnabled, isFalse);
      for (final entry in _previewOnAnalysisFlags(shipped).entries) {
        expect(entry.value, isFalse, reason: entry.key);
      }
      expect(shipped.recognitionRecoveryEnabled, isFalse);
      expect(shipped.recognitionShadowModeEnabled, isFalse);
      expect(shipped.newLiveStageEnabled, isFalse);
      _expectCommunityFlagsOff(shipped);
    });

    // WP-G adds NO production default: production stays purely
    // define-driven, exactly as ADR 0395's audited kill switch specifies. A
    // define passed to a production build resolves as it did before (that is
    // the pre-existing, deliberate way to build a Community-carrying
    // production artifact) — and the preview overlay still never applies.
    test('production has no WP-G default: it stays define-driven and never '
        'takes the preview overlay', () {
      final withDefines = FeatureFlags.forShippedBuild(
        AppEnvironment.production,
        previewAllDefine: true,
        communityDefine: true,
        communityWritesDefine: true,
        communityLeaderboardDefine: true,
        communityClubsDefine: true,
      );

      expect(
        withDefines.aiTutorEnabled,
        isFalse,
        reason: 'previewAll never applies in production',
      );
      expect(withDefines.visionEnabled, isFalse);
      expect(withDefines.audioAnalysisV2Enabled, isFalse);
      expect(withDefines.communityEnabled, isTrue, reason: 'ADR 0395 define');
      expect(withDefines.communityMediaEnabled, isFalse);

      // …while the ABSENT-define production build — the real release
      // artifact — resolves every one of them off.
      _expectCommunityFlagsOff(
        FeatureFlags.forShippedBuild(AppEnvironment.production),
      );
    });

    // …but the account define itself is NOT a WP-G default: it is the
    // pre-existing production build switch and must keep working.
    test('production still honours an explicit STRUMSIGHT_ACCOUNT define', () {
      final flags = FeatureFlags.forShippedBuild(
        AppEnvironment.production,
        accountDefine: true,
      );

      expect(flags.accountEnabled, isTrue);
      expect(flags.usesNetwork, isTrue);
    });

    test('lab without any define is byte-identical to the pre-WP-G '
        'forEnvironment resolution', () {
      final shipped = FeatureFlags.forShippedBuild(AppEnvironment.lab);
      final pinned = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      expect(shipped, equals(pinned));
      expect(shipped.hashCode, equals(pinned.hashCode));
      expect(shipped.toString(), equals(pinned.toString()));

      expect(shipped.accountEnabled, isFalse, reason: 'lab stays define-only');
      expect(shipped.aiTutorEnabled, isFalse, reason: 'no preview overlay');
      expect(shipped.audioAnalysisV2Enabled, isFalse);
      _expectCommunityFlagsOff(shipped);

      // Lab keeps its own define-driven path in both directions.
      final labWithDefines = FeatureFlags.forShippedBuild(
        AppEnvironment.lab,
        accountDefine: true,
        previewAllDefine: true,
        communityDefine: true,
        communityWritesDefine: true,
        communityLeaderboardDefine: true,
        communityClubsDefine: true,
      );
      expect(labWithDefines.accountEnabled, isTrue);
      expect(labWithDefines.aiTutorEnabled, isTrue);
      expect(labWithDefines.communityEnabled, isTrue);
      expect(labWithDefines.communityWritesEnabled, isTrue);
      expect(labWithDefines.communityLeaderboardEnabled, isTrue);
      expect(labWithDefines.communityClubsEnabled, isTrue);
      expect(labWithDefines.communityMediaEnabled, isFalse);
    });

    // An explicit define beats the development default — this is the kill
    // switch ADR 0395 requires, now spelled `=false` instead of "omit it".
    test('an explicit define wins over every development default', () {
      final flags = FeatureFlags.forShippedBuild(
        AppEnvironment.development,
        accountDefine: false,
        previewAllDefine: false,
        communityDefine: false,
        communityWritesDefine: false,
        communityLeaderboardDefine: false,
        communityClubsDefine: false,
        aiTutorCloudDefine: false,
      );

      expect(flags.accountEnabled, isFalse);
      expect(flags.aiTutorEnabled, isFalse, reason: 'no preview overlay');
      expect(
        flags.aiTutorCloudEnabled,
        isFalse,
        reason: 'E-R29a kill switch: an explicit `=false` refuses the gate',
      );
      expect(flags.audioAnalysisV2Enabled, isFalse);
      _expectCommunityFlagsOff(flags);

      // With every WP-G default explicitly refused, the shipped resolution
      // collapses onto the unchanged rollout boundary.
      expect(
        flags,
        equals(
          FeatureFlags.forEnvironment(
            AppEnvironment.development,
            accountEnabled: false,
          ),
        ),
      );
    });

    test('one explicit define turns off exactly one surface', () {
      final flags = FeatureFlags.forShippedBuild(
        AppEnvironment.development,
        communityWritesDefine: false,
      );

      expect(flags.communityEnabled, isTrue);
      expect(flags.communityWritesEnabled, isFalse, reason: 'read-only feed');
      expect(flags.communityLeaderboardEnabled, isTrue);
      expect(flags.communityClubsEnabled, isTrue);
      expect(flags.accountEnabled, isTrue);
    });

    // Media is the one Community flag WP-G leaves alone: it has no
    // development default at all, so it can only ever be a define.
    test('communityMediaEnabled has no development default and stays off', () {
      for (final environment in AppEnvironment.values) {
        expect(
          FeatureFlags.forShippedBuild(environment).communityMediaEnabled,
          isFalse,
          reason: '$environment',
        );
      }
    });

    // E-R29a — the full `aiTutorCloudEnabled` rollout matrix in ONE cell, so
    // the three environments cannot drift apart one test at a time.
    //
    // The old pin was "no dart-define or environment boundary can turn it
    // on"; that made the Coach unable to answer in every artifact anyone
    // could install (2026-09-08 re-audit, BLOCKER B1). The new truth is
    // narrower, not looser: development ON, lab define-only, production
    // closed to the define entirely.
    test('aiTutorCloudEnabled: development ON, lab define-only, production '
        'never — and production ignores the define outright', () {
      expect(
        FeatureFlags.forShippedBuild(
          AppEnvironment.development,
        ).aiTutorCloudEnabled,
        isTrue,
        reason: 'the tester APK passes no define — this IS its resolution',
      );
      expect(
        FeatureFlags.forShippedBuild(AppEnvironment.lab).aiTutorCloudEnabled,
        isFalse,
        reason: 'lab keeps its define-only path, exactly as before E-R29a',
      );
      expect(
        FeatureFlags.forShippedBuild(
          AppEnvironment.lab,
          aiTutorCloudDefine: true,
        ).aiTutorCloudEnabled,
        isTrue,
        reason: 'and an explicit define opens it there',
      );
      expect(
        FeatureFlags.forShippedBuild(
          AppEnvironment.production,
        ).aiTutorCloudEnabled,
        isFalse,
      );
      expect(
        FeatureFlags.forShippedBuild(
          AppEnvironment.production,
          aiTutorCloudDefine: true,
        ).aiTutorCloudEnabled,
        isFalse,
        reason:
            'production is the fail-closed environment: ga-scope.md keeps '
            'the capability postponed behind the open R-PRIV-01 blocker, so '
            'a define leaked into a release build command cannot open it',
      );

      // The rollout boundary itself is untouched: `forEnvironment` — what
      // `tool/release/verify_ga_scope.py` and the capability-rollout
      // coverage tests read — still resolves the flag off everywhere.
      for (final environment in AppEnvironment.values) {
        expect(
          FeatureFlags.forEnvironment(
            environment,
            accountEnabled: false,
          ).aiTutorCloudEnabled,
          isFalse,
          reason: '$environment: forEnvironment is unchanged by E-R29a',
        );
      }
    });

    // The flag is a ROLLOUT gate, not a consent, and nothing about the
    // student's consent lives in `FeatureFlags` at all — the type carries no
    // consent field to confuse it with (ADR 0132 §1/§3).
    test('the cloud rollout gate is not, and cannot be read as, a consent', () {
      final shipped = FeatureFlags.forShippedBuild(AppEnvironment.development);

      expect(shipped.toString(), contains('aiTutorCloudEnabled: true'));
      expect(
        shipped.toString(),
        isNot(contains('consent')),
        reason:
            'consent is a per-student runtime value in '
            'tutorConsentControllerProvider, never a build-time flag',
      );
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
