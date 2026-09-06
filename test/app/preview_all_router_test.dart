import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_router.dart';

import '../support/preference_store.dart';

/// WP-E (repair plan 2026-09-06) — the `STRUMSIGHT_PREVIEW_ALL` overlay
/// registers ~20 previously flag-gated route groups at once (AI Tutor,
/// Vision, Analysis V2 + comparison, the new Live stage). `GoRouter` asserts
/// on a duplicate path AT CONSTRUCTION, so building the router with the
/// preview flag set is the measurement that the flip does not collide with
/// an already-registered path.
GoRouter _buildRouter(FeatureFlags flags) {
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: flags,
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container.read(routerProvider);
}

/// Every fully-resolved `GoRoute` path in the configuration, parent prefixes
/// applied, so a relative child path can still be compared with an absolute
/// one declared elsewhere.
List<String> _allPaths(List<RouteBase> routes, [String prefix = '']) {
  final paths = <String>[];
  for (final route in routes) {
    var childPrefix = prefix;
    if (route is GoRoute) {
      final path = route.path.startsWith('/')
          ? route.path
          : '${prefix.endsWith('/') ? prefix : '$prefix/'}${route.path}';
      paths.add(path);
      childPrefix = path;
    }
    paths.addAll(_allPaths(route.routes, childPrefix));
  }
  return paths;
}

void _expectNoDuplicatePaths(GoRouter router) {
  final paths = _allPaths(router.configuration.routes);
  expect(paths, isNotEmpty, reason: 'the router registered no routes at all');
  final seen = <String>{};
  final duplicates = <String>{};
  for (final path in paths) {
    if (!seen.add(path)) duplicates.add(path);
  }
  expect(duplicates, isEmpty, reason: 'duplicate route path(s): $duplicates');
}

void main() {
  test('the preview-all flag set builds a router without a duplicate path', () {
    late final GoRouter router;
    expect(
      () => router = _buildRouter(
        FeatureFlags.forEnvironment(
          AppEnvironment.development,
          accountEnabled: true,
          previewAll: true,
        ),
      ),
      returnsNormally,
    );
    _expectNoDuplicatePaths(router);
  });

  // The shipped Lab APK (`lab_build.json`) combines the preview overlay with
  // the Community dart-defines, which `flutter test` cannot pass. Building
  // the same flag set explicitly covers the widest route registration the
  // build can produce.
  test('preview-all + the Community defines still has no duplicate path', () {
    late final GoRouter router;
    expect(() => router = _buildRouter(_labBuildFlags()), returnsNormally);
    _expectNoDuplicatePaths(router);
  });

  test(
    'the shipped default flag set is unchanged and still collision-free',
    () {
      late final GoRouter router;
      expect(
        () => router = _buildRouter(
          FeatureFlags.forEnvironment(
            AppEnvironment.development,
            accountEnabled: false,
          ),
        ),
        returnsNormally,
      );
      _expectNoDuplicatePaths(router);
    },
  );
}

/// `lab_build.json`'s flag set: the preview overlay plus the FOUR Community
/// defines the shipped artifact actually carries
/// (`STRUMSIGHT_COMMUNITY`, `_WRITES`, `_CLUBS`, `_LEADERBOARD`).
///
/// `communityMediaEnabled` is deliberately FALSE — `lab_build.json` has no
/// `STRUMSIGHT_COMMUNITY_MEDIA` define, because media upload still carries
/// the open security blockers R-SEC-01 / R-PRIV-01. This fixture previously
/// claimed "five Community defines" and switched media ON, so it measured a
/// build that is not the one we ship (2026-09-06 review, MAJOR-5).
/// `aiTutorCloudEnabled`, `visionLabCaptureEnabled` and
/// `recognitionShadowModeEnabled` stay OFF exactly as the overlay leaves
/// them (data egress / raw-frame persistence / cost).
FeatureFlags _labBuildFlags() => const FeatureFlags(
  accountEnabled: true,
  diagnosticsEnabled: true,
  labModeAvailable: true,
  practiceEngineV2Enabled: true,
  migratedLearnEnabled: true,
  practiceDetailedHistoryEnabled: true,
  songTrainerV2Enabled: true,
  aiTutorEnabled: true,
  practiceGeneratorEnabled: true,
  plannerAssistEnabled: true,
  visionEnabled: true,
  visionSetupEnabled: true,
  visionHandTrackingEnabled: true,
  visionPoseTrackingEnabled: true,
  visionGuitarGeometryEnabled: true,
  visionPracticeIntegrationEnabled: true,
  visionSongIntegrationEnabled: true,
  visionTutorIntegrationEnabled: true,
  visionAnalysisIntegrationEnabled: true,
  visionExperimentalFineFretEnabled: true,
  audioAnalysisV2Enabled: true,
  analysisBeatGridEnabled: true,
  analysisPitchEnabled: true,
  analysisPreprocessingExperimentalEnabled: true,
  analysisExperimentalFusionEnabled: true,
  analysisTechniqueProxiesEnabled: true,
  analysisComparisonEnabled: true,
  analysisPracticeIntegrationEnabled: true,
  analysisTutorIntegrationEnabled: true,
  recognitionRecoveryEnabled: true,
  newLiveStageEnabled: true,
  communityEnabled: true,
  communityWritesEnabled: true,
  communityMediaEnabled: false,
  communityLeaderboardEnabled: true,
  communityClubsEnabled: true,
  adaptiveShellEnabled: true,
);
