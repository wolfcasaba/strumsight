// Golden snapshots of the E13-R20 chord library, chord detail and learning
// path screens, at a compact portrait phone (412×915) and the same frame at
// textScaler 2.0 — the two frames the round brief §7/A9 requires. Pattern
// and sizing follow the merged
// `test/ui/goldens/e13_r19_screens_golden_test.dart` precedent: `AppTheme`
// (the app's actual runtime theme). §0.0/E15-R04: `LessonListScreen` now
// reads `Theme.of(context).extension<SsColorScheme/SsTypography>()!`
// (migrated in this round) — `SsDarkTheme.data()` layers exactly those two
// extensions on top of the SAME `AppTheme.dark()` base (colorScheme/
// textTheme untouched), so the un-migrated chord screens render pixel-
// identically while `LessonListScreen` stops null-check-crashing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/themes/ss_dark_theme.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/chords/widgets/chord_detail_view.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

AppConfig _config() => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: const FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        appConfigProvider.overrideWithValue(_config()),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SsDarkTheme.data(),
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

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('chord library — $suffix', (tester) async {
      await _pump(tester, const ChordLibraryScreen(), textScale: textScale);
      await _expectGolden(tester, 'e13_r20_chord_library_$suffix');
    });

    testWidgets('chord detail — $suffix', (tester) async {
      await _pump(
        tester,
        const ChordDetailView(label: 'C'),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r20_chord_detail_$suffix');
    });

    testWidgets('learning path — $suffix', (tester) async {
      await _pump(
        tester,
        LessonListScreen(now: DateTime(2026, 8, 26)),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r20_learning_path_$suffix');
    });
  }
}
