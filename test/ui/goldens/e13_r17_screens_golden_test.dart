// Golden snapshots of the E13-R17 Today/Practice/Profile hub screens, at a
// compact-portrait phone (412×915) and the same frame at textScaler 2.0 —
// the two frames the round brief §7 requires (A9). A REAL gate: unlike
// `test/features/live/chord_timeline_golden_test.dart` (an opt-in local
// visual tool gated on GOLDENS=1), these run — and must pass — on every
// `flutter test` of this file. Pattern and sizing follow the merged
// `test/ui/goldens/e13_r16_screens_golden_test.dart` precedent (brief
// §0.0/R6.3), with `AppTheme` instead of `SsDarkTheme`: these three screens
// are plain Material widgets, not `core/design_system` components (see
// `today_hub_screen.dart`'s doc comment for why).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [...preferenceOverrides()],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('today hub — $suffix', (tester) async {
      await _pump(
        tester,
        TodayHubScreen(now: DateTime(2026, 8, 25)),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r17_today_hub_$suffix');
    });

    testWidgets('practice area hub — $suffix', (tester) async {
      await _pump(tester, const PracticeAreaHubScreen(), textScale: textScale);
      await _expectGolden(tester, 'e13_r17_practice_area_hub_$suffix');
    });

    testWidgets('profile hub — $suffix', (tester) async {
      await _pump(tester, const ProfileHubScreen(), textScale: textScale);
      await _expectGolden(tester, 'e13_r17_profile_hub_$suffix');
    });
  }
}
