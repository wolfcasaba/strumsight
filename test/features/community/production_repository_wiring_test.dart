// A community repository-providerek PRODUKCIÓS bekötésének őre.
//
// MÉRT hibaosztály (2026-09-05): a `communityChallengeRepositoryProvider`
// KÉT helyen volt definiálva — egy valódi, Dio-alapú impl a Kör 21
// `challenge_repository_impl.dart`-jában, és egy `UnimplementedError`-t dobó
// seam a `challenge_controller.dart`-ban, UGYANAZZAL a névvel. Amelyik fájlt
// egy hívó importálta, azt a providert kapta:
//
//   * `leaderboard_screen.dart`  → a data-réteg VALÓDI providerét  (működött)
//   * `community_challenges_screen.dart` → a controller SEAM-jét   (dobott)
//
// A meglévő widget-tesztek ezt NEM tudták megfogni, mert MINDIG felülírják a
// providert egy fake-kel — és mindegyik ugyanabból a fájlból importálta, mint
// a képernyője, tehát önmagában konzisztens volt. A hiba csak ÉLES
// használatban jelent volna meg, `UnimplementedError`-ként.
//
// Ez a teszt ezért NEM fake-kel dolgozik: a SZÁLLÍTOTT kompozíciót olvassa
// (`ProviderContainer` override NÉLKÜL), és azt méri, hogy a provider ad-e
// használható repository-t. A fiók-réteg kikapcsolt állapotában a `Disabled*`
// változat a HELYES válasz — az is repository, nem kivétel.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/community/application/controllers/challenge_result_controller.dart';
import 'package:strumsight/features/community/application/controllers/feed_controller.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/data/repositories/challenge_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/club_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/notification_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';

import '../../core/storage/in_memory_key_value_store.dart';

void main() {
  group(
    'a szállított kompozíció minden bekötött community-repository-t felold',
    () {
      late ProviderContainer container;

      setUp(() {
        // Override NÉLKÜL: pontosan azt olvassuk, amit egy éles build kapna.
        container = ProviderContainer();
      });

      tearDown(() => container.dispose());

      test('communityChallengeRepositoryProvider nem dob', () {
        // A hibaosztály mércéje: a duplikált seam visszavezetése esetén ez a
        // cella `UnimplementedError`-ral pirosra vált.
        expect(
          () => container.read(communityChallengeRepositoryProvider),
          returnsNormally,
        );
        expect(container.read(communityChallengeRepositoryProvider), isNotNull);
      });

      test('communityFeedRepositoryProvider nem dob', () {
        // 2026-09-05: itt UGYANAZ a duplikált seam állt, mint a
        // kihívásoknál — a `feed_controller.dart` egy dobó providert
        // definiált ugyanezen a néven, tehát a feed-képernyő a valódi
        // implementáció megírása UTÁN is azt kapta volna.
        expect(
          () => container.read(communityFeedRepositoryProvider),
          returnsNormally,
        );
        expect(container.read(communityFeedRepositoryProvider), isNotNull);
      });

      test('communityNotificationRepositoryProvider nem dob', () {
        expect(
          () => container.read(communityNotificationRepositoryProvider),
          returnsNormally,
        );
        expect(
          container.read(communityNotificationRepositoryProvider),
          isNotNull,
        );
      });

      test('communityProfileRepositoryProvider nem dob', () {
        expect(
          () => container.read(communityProfileRepositoryProvider),
          returnsNormally,
        );
      });

      test('socialGraphRepositoryProvider nem dob', () {
        expect(
          () => container.read(socialGraphRepositoryProvider),
          returnsNormally,
        );
      });

      test('communityPostRepositoryProvider nem dob', () {
        // 2026-09-06: ugyanaz a duplikált seam, mint a kihívásoknál és a
        // feednél — a `post_composer_controller.dart` egy `StateError`-t
        // dobó providert definiált ugyanezen a néven, és a szállított
        // kompozícióban senki nem írta felül. A feed-kártya, a szerkesztő,
        // a komment-lista és a reakció-sáv is ezt kapta volna.
        expect(
          () => container.read(communityPostRepositoryProvider),
          returnsNormally,
        );
        expect(
          container.read(communityPostRepositoryProvider),
          isA<DisabledCommunityPostRepository>(),
        );
      });

      test('communityClubRepositoryProvider nem dob', () {
        // A `club_list_screen.dart` `UnimplementedError`-t dobó seamje —
        // mind a három klub-képernyő az első olvasásnál elszállt volna.
        expect(
          () => container.read(communityClubRepositoryProvider),
          returnsNormally,
        );
        expect(
          container.read(communityClubRepositoryProvider),
          isA<DisabledCommunityClubRepository>(),
        );
      });

      test('communityChallengeResultRepositoryProvider nem dob', () {
        // A kihívás-eredmény beküldése SAJÁT, dobó providert olvasott,
        // miközben a Kör 21 valódi bekötése ott állt mellette. Innentől a
        // kettő UGYANAZ a definíció.
        expect(
          () => container.read(communityChallengeResultRepositoryProvider),
          returnsNormally,
        );
        expect(
          container.read(communityChallengeResultRepositoryProvider),
          same(container.read(communityChallengeRepositoryProvider)),
        );
      });

      test(
        'a fiók-réteg nélküli buildben a Disabled* változat jön, nem kivétel',
        () {
          // A `Disabled*` repository a HELYES válasz kikapcsolt fiók-rétegnél:
          // a hívó egyenletes kódúton marad (ConfigurationFailure), nem kell
          // külön ágat írnia a kikapcsolt buildre.
          final repo = container.read(communityChallengeRepositoryProvider);
          expect(repo, isA<DisabledCommunityChallengeRepository>());
        },
      );
    },
  );

  group('a helyi tárra épülő community-seamek is feloldanak', () {
    // Itt EGYETLEN override van: a `keyValueStoreProvider`. Pontosan ezt
    // teszi a `main.dart` is — a bootstrap által megnyitott tárat köti be —,
    // tehát ez a container a SZÁLLÍTOTT kompozíció hű mása erre a három
    // providerre. A community NEM kap saját tárat: a kulcsai már
    // névtérrel elválasztottak (`ss.community.*`), egy második tár csak egy
    // második, felülírandó bekötési pont volna.
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('feedCacheProvider nem dob', () {
      // 2026-09-06: `UnimplementedError`-t dobott, és senki nem írta felül —
      // a feed-képernyő az első `load()` első során (`_cache.read()`)
      // elszállt.
      expect(() => container.read(feedCacheProvider), returnsNormally);
      expect(container.read(feedCacheProvider), isNotNull);
    });

    test('communityKeyValueStoreProvider az app-szintű tárat adja', () {
      expect(
        () => container.read(communityKeyValueStoreProvider),
        returnsNormally,
      );
      expect(
        container.read(communityKeyValueStoreProvider),
        same(container.read(keyValueStoreProvider)),
      );
    });

    test('communityLoggerProvider nem dob', () {
      expect(() => container.read(communityLoggerProvider), returnsNormally);
      expect(container.read(communityLoggerProvider), isNotNull);
    });

    test('a piszkozat-tár és a kimenő sor is felépül', () {
      // A két fogyasztó, ami a fenti három providert olvassa. Ha bármelyik
      // seam visszakerül dobó változatra, ez a cella pirosra vált.
      expect(
        () => container.read(communityDraftStoreProvider),
        returnsNormally,
      );
      expect(() => container.read(communityOutboxProvider), returnsNormally);
    });
  });
}
