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
import 'package:strumsight/features/community/data/repositories/challenge_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';

void main() {
  group('a szállított kompozíció minden bekötött community-repository-t felold',
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
  });
}
