import 'package:flutter_riverpod/misc.dart' show Override;

import '../../core/logging/app_logger.dart';
import '../../core/storage/key_value_store.dart';
import '../../features/auth/public.dart';
import '../../features/community/public.dart';

/// The Community seam providers the production `ProviderScope` must wire.
///
/// E18-R19 routed the community screens, but their data seams stayed the
/// test-only defaults: `feedCacheProvider` and
/// `communityFeedRepositoryProvider` (`feed_controller.dart`) throw
/// `UnimplementedError`, `communityPostRepositoryProvider`,
/// `communityKeyValueStoreProvider` and `communityLoggerProvider`
/// (`post_composer_controller.dart`) throw `StateError` — "must be
/// overridden in production wiring". Riverpod folds a throwing provider
/// into the reading controller's error state, so on a device the feed
/// rendered its error card and the composer never hydrated, with no
/// console exception (the E18-R01 finding F5 defect class, `docs/LESSONS.md`
/// L652). Every widget test overrode the seams, so the suite was blind.
///
/// What each override binds:
///
/// * `communityKeyValueStoreProvider` → the store `AppBootstrap` opened
///   (the same instance `keyValueStoreProvider` carries).
/// * `communityLoggerProvider` → the shared app logger.
/// * `communityFeedRepositoryProvider` / `communityPostRepositoryProvider`
///   → the HTTP implementations over the shared `accountApiClientProvider`
///   (JWT + base URL in one place); the disabled stand-ins when the account
///   layer is off — the `socialGraphRepositoryProvider` shape.
/// * `feedCacheProvider` → `FeedCache.open` partitioned by the signed-in
///   user's id (account isolation, A2). The id is only known once
///   `authControllerProvider` settles, so the cache is resolved lazily
///   through `ref.watch`: it rebuilds on every session change and, while
///   logged out, binds to the never-read `userId 0` partition — the same
///   fallback `communityDraftStoreProvider` uses. The gate keeps the feed
///   behind sign-in, so the `0` partition is never rendered.
///
/// `communityProfileRepositoryProvider` and `socialGraphRepositoryProvider`
/// need no entry here: their providers already resolve the HTTP
/// implementation from `accountApiClientProvider` on their own.
///
/// No auth / session value is taken as a parameter on purpose: the profile
/// implementation (and the two impls wired here) read the account client
/// through the provider graph, and the session user comes from
/// `authControllerProvider` — both are resolved inside the overrides, so
/// the caller only supplies what exists before the container does.
List<Override> buildCommunityProductionOverrides({
  required KeyValueStore keyValueStore,
  required AppLogger logger,
}) {
  return <Override>[
    communityKeyValueStoreProvider.overrideWithValue(keyValueStore),
    communityLoggerProvider.overrideWithValue(logger),
    communityFeedRepositoryProvider.overrideWith(
      (ref) => createCommunityFeedRepository(
        ref.watch(communityFeedApiClientProvider),
      ),
    ),
    communityPostRepositoryProvider.overrideWith(
      (ref) => createCommunityPostRepository(
        ref.watch(communityPostApiClientProvider),
      ),
    ),
    feedCacheProvider.overrideWith((ref) {
      final user = ref.watch(authControllerProvider).value;
      return FeedCache.open(
        store: keyValueStore,
        logger: logger,
        userId: user?.id ?? 0,
      );
    }),
  ];
}
