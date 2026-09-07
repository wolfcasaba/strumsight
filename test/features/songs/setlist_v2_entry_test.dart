// R12 (audit §5.2) — the Setlist V2 list finally has an ON-SCREEN entry.
//
// MEASURED gap: `/setlists/v2` has been registered since R10, but nothing
// in `lib/**` ever pushed it, so the ordered setlist run (each item
// launching the real Song Trainer session and waiting for it) did not exist
// for the user. These cells pin the ENTRY, not the route registration —
// the route is measured by `setlist_session_launch_test.dart`:
//
//   V1 — the legacy list renders the runner-entry card when empty,
//   V2 — tapping it navigates to `AppRoutes.setlistsV2`,
//   V3 — the entry sits above the existing setlist rows, which still render.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/songs/model/setlist.dart';
import 'package:strumsight/features/songs/providers/setlists_provider.dart';
import 'package:strumsight/features/songs/screens/setlist_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

const _entry = Key('setlist-open-v2');
const _target = 'setlist-v2-target';

class _SeededSetlists extends SetlistsController {
  _SeededSetlists(this._seed);

  final List<Setlist> _seed;

  @override
  List<Setlist> build() {
    super.build(); // opens the r150 write gate (mock prefs are empty)
    return _seed;
  }
}

Widget _app({List<Setlist> setlists = const []}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SetlistListScreen()),
      GoRoute(
        path: AppRoutes.setlistsV2,
        builder: (_, _) => const Scaffold(body: Text(_target)),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ...preferenceOverrides(),
      setlistsProvider.overrideWith(() => _SeededSetlists(setlists)),
    ],
    child: MaterialApp.router(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('V1 renders the setlist runner entry card', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byKey(_entry), findsOneWidget);
  });

  testWidgets('V2 the entry opens /setlists/v2', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_entry));
    await tester.pumpAndSettle();

    expect(find.text(_target), findsOneWidget);
  });

  testWidgets('V3 the entry sits above the setlists', (tester) async {
    const set = Setlist(id: 's', name: 'My Gig', songIds: ['a']);
    await tester.pumpWidget(_app(setlists: [set]));
    await tester.pumpAndSettle();

    final entry = find.byKey(_entry);
    final row = find.text('My Gig');
    expect(entry, findsOneWidget);
    expect(row, findsOneWidget);
    expect(tester.getTopLeft(entry).dy, lessThan(tester.getTopLeft(row).dy));
  });
}
