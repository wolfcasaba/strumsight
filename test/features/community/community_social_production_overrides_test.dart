// The social-side community seams reach the REAL HTTP implementations
// through the production overrides — the sibling of
// `community_production_chain_test.dart` for the four seams
// `buildCommunitySocialProductionOverrides` binds.
//
// ## Why this needs a guard of its own
//
// The inbox, challenge and club screens read seam providers whose
// defaults throw `StateError` ("must be overridden in production
// wiring"). Riverpod folds the throw into the controller's /
// `FutureProvider`'s error state, so a build that forgets the override
// renders an error card with no console exception — the E18-R01
// finding F5 defect class (`docs/LESSONS.md` L652). Every widget test
// overrides the seams, so the suite alone would never see it.
//
// These cells build a container from the REAL providers plus the
// production overrides, with only the config overridden. No network
// happens: building an `ApiClient` does not make a request.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/bootstrap/community_social_production_overrides.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/community/application/controllers/challenge_controller.dart';
import 'package:strumsight/features/community/application/controllers/challenge_result_controller.dart';
import 'package:strumsight/features/community/application/controllers/notification_controller.dart';
import 'package:strumsight/features/community/data/repositories/challenge_repository_impl.dart'
    show DisabledCommunityChallengeRepository, HttpCommunityChallengeRepository;
import 'package:strumsight/features/community/data/repositories/club_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/notification_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/social_graph_repository_impl.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_list_screen.dart'
    show communityClubRepositoryProvider;

import '../../core/storage/in_memory_key_value_store.dart';

AppConfig _config({required bool accountEnabled}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'https://casaba.app/strumsight',
  flags: FeatureFlags(
    accountEnabled: accountEnabled,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    communityEnabled: true,
    communityWritesEnabled: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

ProviderContainer _container({
  required bool accountEnabled,
  required bool withOverrides,
}) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        _config(accountEnabled: accountEnabled),
      ),
      if (withOverrides)
        ...buildCommunitySocialProductionOverrides(
          keyValueStore: InMemoryKeyValueStore(),
          logger: const NoopAppLogger(),
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('with the account layer ON — the casaba build', () {
    test('every social seam resolves its HTTP implementation', () {
      final container = _container(accountEnabled: true, withOverrides: true);

      expect(
        container.read(communityNotificationRepositoryProvider),
        isA<HttpCommunityNotificationRepository>(),
      );
      expect(
        container.read(communityChallengeRepositoryProvider),
        isA<HttpCommunityChallengeRepository>(),
        reason:
            'the controller seam in challenge_controller.dart is the one '
            'the challenges screen reads — not the impl-file provider',
      );
      expect(
        container.read(communityChallengeResultRepositoryProvider),
        isA<HttpCommunityChallengeRepository>(),
      );
      expect(
        container.read(communityClubRepositoryProvider),
        isA<HttpCommunityClubRepository>(),
      );
      expect(
        container.read(socialGraphRepositoryProvider),
        isA<HttpCommunitySocialGraphRepository>(),
        reason:
            'the cursor-forwarding decorator replaces the self-resolving '
            'HttpSocialGraphRepository, which drops limit + cursor',
      );
    });

    test('reading the notification + challenge controllers does not throw', () {
      final container = _container(accountEnabled: true, withOverrides: true);

      expect(
        () => container.read(notificationControllerProvider),
        returnsNormally,
      );
      expect(
        () => container.read(notificationControllerProvider.notifier),
        returnsNormally,
      );
      expect(
        () => container.read(challengeControllerProvider),
        returnsNormally,
      );
      expect(
        () => container.read(challengeControllerProvider.notifier),
        returnsNormally,
      );
      expect(
        () => container.read(communityChallengeSubmissionControllerProvider),
        returnsNormally,
      );
    });
  });

  group('with the account layer OFF', () {
    test('every seam is the DISABLED one — not a crash, not a fake', () {
      final container = _container(accountEnabled: false, withOverrides: true);

      expect(
        container.read(communityNotificationRepositoryProvider),
        isA<DisabledCommunityNotificationRepository>(),
      );
      expect(
        container.read(communityChallengeRepositoryProvider),
        isA<DisabledCommunityChallengeRepository>(),
      );
      expect(
        container.read(communityChallengeResultRepositoryProvider),
        isA<DisabledCommunityChallengeRepository>(),
      );
      expect(
        container.read(communityClubRepositoryProvider),
        isA<DisabledCommunityClubRepository>(),
      );
      expect(
        container.read(socialGraphRepositoryProvider),
        isA<DisabledSocialGraphRepository>(),
      );
    });
  });

  group('without the overrides', () {
    test('the seams throw instead of returning a silent stand-in', () {
      // The honest default: a missing production override is a visible
      // failure (Riverpod surfaces it as the reading widget's error),
      // never an empty inbox / club list that looks like "no data".
      final container = _container(accountEnabled: true, withOverrides: false);

      expect(
        () => container.read(communityNotificationRepositoryProvider),
        throwsA(anything),
      );
      expect(
        () => container.read(communityChallengeRepositoryProvider),
        throwsA(anything),
      );
      expect(
        () => container.read(communityClubRepositoryProvider),
        throwsA(anything),
      );
    });
  });
}
