// The routed community feed / composer reach REAL seams, not the test-only
// throwing defaults.
//
// ## Why this needs a guard of its own
//
// E18-R19 routed the community screens, but `feedCacheProvider` and
// `communityFeedRepositoryProvider` (`feed_controller.dart`) kept their
// `UnimplementedError` bodies and `communityPostRepositoryProvider`,
// `communityKeyValueStoreProvider`, `communityLoggerProvider`
// (`post_composer_controller.dart`) their `StateError` — "must be
// overridden in production wiring". Riverpod folds a throwing provider into
// the reading controller's error state, so on a device the feed rendered
// its error card and the composer never hydrated, with no console exception
// (the E18-R01 finding F5 defect class, `docs/LESSONS.md` L652). Every widget
// test overrode the seams, so the suite was blind.
//
// These cells build the REAL production override list
// (`buildCommunityProductionOverrides`) and read the real providers through
// it, with only the config and (where the account layer is on) the session
// overridden. No network happens: building an `ApiClient` does not make a
// request, and the controllers do not fetch on construction.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/bootstrap/community_production_overrides.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/feed_controller.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/data/local/feed_cache.dart';
import 'package:strumsight/features/community/data/repositories/feed_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';

import '../../core/storage/in_memory_key_value_store.dart';

AppConfig _config({required bool accountEnabled}) => AppConfig(
  environment: AppEnvironment.development,
  // The shape the hosted backend is configured with: an origin plus the
  // gateway's mount point (`docs/operations/casaba-backend.md`).
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

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._user);
  final AuthUser? _user;
  @override
  Future<AuthUser?> build() async => _user;
}

/// Riverpod 3 wraps a provider-creation error in a [ProviderException]
/// (possibly nested); the cells below care about the ROOT cause.
Object _rootCause(Object error) {
  var current = error;
  while (current is ProviderException) {
    current = current.exception;
  }
  return current;
}

ProviderContainer _container({
  required AppConfig config,
  required InMemoryKeyValueStore store,
  required AppLogger logger,
  AuthUser? signedInAs,
  bool withOverrides = true,
}) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      if (signedInAs != null)
        // A signed-in session without the secure-store platform channel —
        // the real controller would read the token store on build.
        authControllerProvider.overrideWith(
          () => _FakeAuthController(signedInAs),
        ),
      if (withOverrides)
        ...buildCommunityProductionOverrides(
          keyValueStore: store,
          logger: logger,
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late InMemoryKeyValueStore store;
  const logger = NoopAppLogger();

  setUp(() {
    store = InMemoryKeyValueStore();
  });

  group('with the account layer ON — the casaba build', () {
    const user = AuthUser(id: 7, email: 'feed@strumsight.app');

    test('the feed + post repositories are the HTTP ones', () {
      final container = _container(
        config: _config(accountEnabled: true),
        store: store,
        logger: logger,
        signedInAs: user,
      );
      expect(
        container.read(communityFeedRepositoryProvider),
        isA<HttpCommunityFeedRepository>(),
        reason:
            'the routed feed reads this repository; a disabled stand-in here '
            'would let it render and never load',
      );
      expect(
        container.read(communityPostRepositoryProvider),
        isA<HttpCommunityPostRepository>(),
      );
    });

    test('the composer seams carry the injected store and logger', () {
      final container = _container(
        config: _config(accountEnabled: true),
        store: store,
        logger: logger,
        signedInAs: user,
      );
      expect(container.read(communityKeyValueStoreProvider), same(store));
      expect(container.read(communityLoggerProvider), same(logger));
    });

    test('the feed cache is partitioned by the signed-in user id', () async {
      final container = _container(
        config: _config(accountEnabled: true),
        store: store,
        logger: logger,
        signedInAs: user,
      );
      // The fake session resolves asynchronously; settle it so the
      // cache provider sees the user (it rebuilds on the auth change).
      await container.read(authControllerProvider.future);

      final cache = container.read(feedCacheProvider);
      expect(cache, isA<FeedCache>());
      await cache.write(const <CachedFeedItem>[]);
      expect(store.values.containsKey(FeedCache.storageKeyFor(7)), isTrue);
      expect(store.values.containsKey(FeedCache.storageKeyFor(0)), isFalse);
    });

    test('reading feedController + postComposerController does NOT '
        'throw', () async {
      final container = _container(
        config: _config(accountEnabled: true),
        store: store,
        logger: logger,
        signedInAs: user,
      );

      // The exact reads the screens perform on mount.
      final feed = container.read(feedControllerProvider);
      expect(feed.status, FeedStatus.initial);
      expect(container.read(feedControllerProvider.notifier), isNotNull);

      final subscription = container.listen(
        postComposerControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final composer = await container.read(
        postComposerControllerProvider.future,
      );
      expect(composer.isSubmitting, isFalse);
      expect(container.read(postComposerControllerProvider).hasError, isFalse);
    });
  });

  group('with the account layer OFF', () {
    test('the repositories are the DISABLED ones, not a crash and not a '
        'fake', () {
      final container = _container(
        config: _config(accountEnabled: false),
        store: store,
        logger: logger,
      );
      expect(
        container.read(communityFeedRepositoryProvider),
        isA<DisabledCommunityFeedRepository>(),
      );
      expect(
        container.read(communityPostRepositoryProvider),
        isA<DisabledCommunityPostRepository>(),
      );
      expect(container.read(communityFeedApiClientProvider), isNull);
      expect(container.read(communityPostApiClientProvider), isNull);
    });

    test('logged out, the cache binds to the never-read userId 0 '
        'partition — the draft-store fallback shape', () async {
      final container = _container(
        config: _config(accountEnabled: false),
        store: store,
        logger: logger,
      );
      // The real AuthController returns null without touching the
      // secure store when the account layer is off.
      await container.read(authControllerProvider.future);

      final cache = container.read(feedCacheProvider);
      await cache.write(const <CachedFeedItem>[]);
      expect(store.values.containsKey(FeedCache.storageKeyFor(0)), isTrue);
    });

    test('reading feedController + postComposerController does NOT '
        'throw', () async {
      final container = _container(
        config: _config(accountEnabled: false),
        store: store,
        logger: logger,
      );

      expect(container.read(feedControllerProvider).status, FeedStatus.initial);

      final subscription = container.listen(
        postComposerControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final composer = await container.read(
        postComposerControllerProvider.future,
      );
      expect(composer.isSubmitting, isFalse);
    });
  });

  group('WITHOUT the production overrides the same reads fail — the guard '
      'is not vacuous', () {
    test('the feed seams throw their UnimplementedError', () {
      final container = _container(
        config: _config(accountEnabled: true),
        store: store,
        logger: logger,
        withOverrides: false,
      );
      expect(
        () => container.read(communityFeedRepositoryProvider),
        throwsA(
          predicate<Object>(
            (error) => _rootCause(error) is UnimplementedError,
            'unwraps to an UnimplementedError',
          ),
        ),
      );
      expect(
        () => container.read(feedCacheProvider),
        throwsA(
          predicate<Object>(
            (error) => _rootCause(error) is UnimplementedError,
            'unwraps to an UnimplementedError',
          ),
        ),
      );
    });

    test('the composer seams throw their StateError', () {
      final container = _container(
        config: _config(accountEnabled: true),
        store: store,
        logger: logger,
        withOverrides: false,
      );
      expect(
        () => container.read(communityPostRepositoryProvider),
        throwsA(
          predicate<Object>(
            (error) => _rootCause(error) is StateError,
            'unwraps to a StateError',
          ),
        ),
      );
      expect(
        () => container.read(communityKeyValueStoreProvider),
        throwsA(
          predicate<Object>(
            (error) => _rootCause(error) is StateError,
            'unwraps to a StateError',
          ),
        ),
      );
      expect(
        () => container.read(communityLoggerProvider),
        throwsA(
          predicate<Object>(
            (error) => _rootCause(error) is StateError,
            'unwraps to a StateError',
          ),
        ),
      );
    });
  });
}
