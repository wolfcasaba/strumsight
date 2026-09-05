// A 13 community képernyő ÚTVONALAINAK őre.
//
// MÉRT hiány (2026-09-05): mind a 13 community képernyő `reachable: false`
// volt — a fa legnagyobb egyben lévő halott halmaza. Maga a
// `CommunityGateScreen`, a feature belépési szűrője is köztük volt: a kapu
// sem volt elérhető.
//
// Ez a teszt a REGISZTRÁCIÓS szintet méri, nem a képernyők tartalmát (azoknak
// saját widget-tesztjük van). A kapu KI állásán az útvonalak NEM léteznek —
// ugyanaz a mintázat, amit a Practice és a Vision kapuja használ, és a
// szerver-oldali ADR 0497 D1 („a route nincs regisztrálva, nem futásidejű
// 403") kliens-oldali párja.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';

/// A community útvonalak — a `AppRoutes` konstansaiból, NEM újragépelve.
/// Egy kézzel bemásolt lista együtt csúszna el a hibával.
const List<String> _communityPaths = <String>[
  AppRoutes.community,
  AppRoutes.communityFeed,
  AppRoutes.communityCompose,
  AppRoutes.communityComments,
  AppRoutes.communityBookmarks,
  AppRoutes.communityNotifications,
  AppRoutes.communitySearch,
  AppRoutes.communityFollowers,
  AppRoutes.communityFollowing,
  AppRoutes.communityChallenges,
  AppRoutes.communityLeaderboard,
  AppRoutes.communitySafety,
  AppRoutes.communityClubs,
  AppRoutes.communityClubDetail,
];

Set<String> _registeredPaths({required bool communityEnabled}) {
  final container = ProviderContainer(
    overrides: [
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: true,
            diagnosticsEnabled: true,
            labModeAvailable: true,
            communityEnabled: communityEnabled,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final paths = <String>{};
  void walk(List<RouteBase> routes) {
    for (final route in routes) {
      if (route is GoRoute) paths.add(route.path);
      walk(route.routes);
    }
  }

  walk(container.read(routerProvider).configuration.routes);
  return paths;
}

void main() {
  group('community route-ok a kapu alatt', () {
    test('E1 — bekapcsolt kapun mind a 14 útvonal regisztrálva van', () {
      final paths = _registeredPaths(communityEnabled: true);

      for (final path in _communityPaths) {
        expect(paths, contains(path), reason: 'hiányzó útvonal: $path');
      }
    });

    test('E2 — kikapcsolt kapun EGYIK sem létezik', () {
      // Nem futásidejű tiltás: az útvonal nincs regisztrálva, tehát egy
      // `/community*` cím a router `onException`-jére fut és a belépési
      // pontra esik vissza.
      final paths = _registeredPaths(communityEnabled: false);

      for (final path in _communityPaths) {
        expect(paths, isNot(contains(path)), reason: 'szivárgó útvonal: $path');
      }
    });

    test('E3 — a kapu KIZÁRÓLAG a community útvonalakat mozdítja', () {
      // Kontroll-cella: e nélkül az E2 akkor is zöld lenne, ha a kapu
      // véletlenül az egész route-táblát kiürítené.
      final on = _registeredPaths(communityEnabled: true);
      final off = _registeredPaths(communityEnabled: false);

      expect(on.difference(off), unorderedEquals(_communityPaths));
      expect(off.difference(on), isEmpty);
    });
  });

  group('a mély-linkek paraméterei', () {
    test('E4 — a négy paraméteres útvonal NEVESÍTETT paramétert visz', () {
      // Egy paraméter nélküli útvonal (pl. `/community/clubs/detail`) némán
      // 404-elne minden mély-linkre, és a lista → részletek navigáció sem
      // tudná átadni az azonosítót.
      expect(AppRoutes.communityComments, contains(':postId'));
      expect(AppRoutes.communityClubDetail, contains(':clubId'));
      expect(AppRoutes.communityLeaderboard, contains(':challengeId'));
      expect(AppRoutes.communityFollowers, contains(':profileId'));
      expect(AppRoutes.communityFollowing, contains(':profileId'));
    });

    test('E5 — a követők és a követettek KÜLÖN útvonal', () {
      // Egy közös útvonal query-paraméterrel azt jelentené, hogy egy
      // elhagyott paraméter némán a MÁSIK listát mutatja.
      expect(AppRoutes.communityFollowers, isNot(AppRoutes.communityFollowing));
      final paths = _registeredPaths(communityEnabled: true);
      expect(paths, contains(AppRoutes.communityFollowers));
      expect(paths, contains(AppRoutes.communityFollowing));
    });
  });
}
