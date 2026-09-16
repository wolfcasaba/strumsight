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

import 'dart:io';

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

/// A `communityEnabled` alatt SAJÁT al-zászlóval regisztrált útvonalak.
/// MÉRT hiba (2026-09-06 review, MINOR-6): a képernyők doc-kommentjei ezt
/// ÁLLÍTOTTÁK, a router viszont mindhármat pusztán `communityEnabled` alatt
/// hozta létre — egy kikapcsolt al-zászló mellett a gomb eltűnt, az útvonal
/// viszont maradt.
const String _writesPath = AppRoutes.communityCompose;
const List<String> _clubsPaths = <String>[
  AppRoutes.communityClubs,
  AppRoutes.communityClubDetail,
];
const String _leaderboardPath = AppRoutes.communityLeaderboard;

Set<String> _registeredPaths({
  required bool communityEnabled,
  bool writesEnabled = true,
  bool clubsEnabled = true,
  bool leaderboardEnabled = true,
}) {
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
            communityWritesEnabled: writesEnabled,
            communityClubsEnabled: clubsEnabled,
            communityLeaderboardEnabled: leaderboardEnabled,
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

  group('az al-zászlók saját kapui (2026-09-06 review, MINOR-6)', () {
    test('E9 — kikapcsolt communityWritesEnabled: a /community/compose NINCS '
        'regisztrálva, a többi marad', () {
      final paths = _registeredPaths(
        communityEnabled: true,
        writesEnabled: false,
      );

      expect(paths, isNot(contains(_writesPath)));
      for (final path in _communityPaths) {
        if (path == _writesPath) continue;
        expect(paths, contains(path), reason: 'túlkapuzott útvonal: $path');
      }
    });

    test('E10 — kikapcsolt communityClubsEnabled: a klub-lista ÉS a '
        'klub-részlet is eltűnik, a többi marad', () {
      final paths = _registeredPaths(
        communityEnabled: true,
        clubsEnabled: false,
      );

      for (final path in _clubsPaths) {
        expect(paths, isNot(contains(path)), reason: 'szivárgó útvonal: $path');
      }
      for (final path in _communityPaths) {
        if (_clubsPaths.contains(path)) continue;
        expect(paths, contains(path), reason: 'túlkapuzott útvonal: $path');
      }
    });

    test('E11 — kikapcsolt communityLeaderboardEnabled: a ranglista NINCS '
        'regisztrálva, a többi marad', () {
      final paths = _registeredPaths(
        communityEnabled: true,
        leaderboardEnabled: false,
      );

      expect(paths, isNot(contains(_leaderboardPath)));
      for (final path in _communityPaths) {
        if (path == _leaderboardPath) continue;
        expect(paths, contains(path), reason: 'túlkapuzott útvonal: $path');
      }
    });
  });

  group('a belépési pont', () {
    test('E6 — a Profil hub a community kapu-képernyőre visz', () {
      // MÉRT hiba a saját munkámban (2026-09-05): a 13 route létezett, de a
      // szállított felületről SEMMI nem vezetett hozzájuk. A
      // `check_screen_reachability` ezt NEM fogja meg: az egy regisztrált
      // GoRoute-ot elérhetőnek számol akkor is, ha semmi nem navigál oda.
      final source = File(
        'lib/features/profile_hub/screens/profile_hub_screen.dart',
      ).readAsStringSync();

      expect(source, contains('AppRoutes.community'));
      // Az entry a kapu alatt áll: kikapcsolt community mellett nincs
      // gomb egy nem létező útvonalra.
      expect(source, contains('if (communityEnabled)'));
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

  group('a bejövő hivatkozások — a felület tényleg elér oda', () {
    test('E7 — mind a 14 community útvonal-konstansra mutat a felületről '
        'legalább egy hivatkozás', () {
      // MÉRT hiba (2026-09-06, WP-C): a 14 útvonal REGISZTRÁLVA volt, a
      // `check_screen_reachability` mind a 13 képernyőt `reachable: true`
      // -nek mérte — miközben a szállított felületről EGYETLEN
      // `context.push` sem vezetett hozzájuk. Egy regisztrált route,
      // amire semmi nem navigál, ajtó kilincs nélkül.
      //
      // A cella a MÁSIK irányt méri: a `lib/` fában — a konstans-fájlt és
      // magát a router-táblát kizárva — van-e `AppRoutes.<név>` említés.
      final names = <String, String>{
        'community': AppRoutes.community,
        'communityFeed': AppRoutes.communityFeed,
        'communityCompose': AppRoutes.communityCompose,
        'communityComments': AppRoutes.communityComments,
        'communityBookmarks': AppRoutes.communityBookmarks,
        'communityNotifications': AppRoutes.communityNotifications,
        'communitySearch': AppRoutes.communitySearch,
        'communityFollowers': AppRoutes.communityFollowers,
        'communityFollowing': AppRoutes.communityFollowing,
        'communityChallenges': AppRoutes.communityChallenges,
        'communityLeaderboard': AppRoutes.communityLeaderboard,
        'communitySafety': AppRoutes.communitySafety,
        'communityClubs': AppRoutes.communityClubs,
        'communityClubDetail': AppRoutes.communityClubDetail,
      };
      final sources = _libSourcesOutsideRouting();
      final withoutIncoming = <String>[
        for (final name in names.keys)
          if (!sources.any((source) => source.contains('AppRoutes.$name')))
            name,
      ];

      expect(
        withoutIncoming,
        isEmpty,
        reason:
            'ezekre az útvonal-konstansokra a felületről semmi nem mutat: '
            '$withoutIncoming',
      );
    });

    test('E8 — a próba valódi sértést fog: egy kitalált konstansra '
        'nincs hivatkozás', () {
      // Kontroll-cella: e nélkül az E7 akkor is zöld lenne, ha a
      // forrás-beolvasás üres halmazt adna vissza.
      final sources = _libSourcesOutsideRouting();
      expect(sources, isNotEmpty);
      expect(
        sources.any((s) => s.contains('AppRoutes.communityNoSuchRoute')),
        isFalse,
      );
    });
  });
}

/// Minden `lib/` alatti Dart forrás, KIVÉVE az útvonal-konstansok
/// deklarációját és magát a router-táblát: azokban a konstanst nevezni
/// az, ami LÉTREHOZZA a route-ot, nem az, ami ELÉRI.
List<String> _libSourcesOutsideRouting() {
  const excluded = <String>{
    'lib/app/routing/app_route.dart',
    'lib/app/routing/app_router.dart',
  };
  final root = Directory.current.path;
  return <String>[
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        if (!excluded.contains(
          entity.absolute.path
              .substring(root.length + 1)
              .replaceAll(r'\\', '/'),
        ))
          entity.readAsStringSync(),
  ];
}
