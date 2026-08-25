// Golden snapshots of the E13-R18 migrated Live Stage screen, at a compact
// portrait phone (412×915) and the same frame at textScaler 2.0 — the two
// frames the round brief §7 requires (A9). A REAL gate: unlike
// `test/features/live/chord_timeline_golden_test.dart` (an opt-in local
// visual tool gated on GOLDENS=1), this runs — and must pass — on every
// `flutter test` of this file. Pattern and sizing follow the merged
// `test/ui/goldens/e13_r17_screens_golden_test.dart` precedent, with
// `AppTheme` (not `SsDarkTheme`): the Live screen is themed by the app's
// actual runtime theme (`lib/app/strumsight_app.dart`), which does not
// register the `SsTypography`/`SsColorScheme` extensions — see the round
// handoff (§10) for why the new music components stay palette-driven
// instead of depending on them.
//
// The screen is snapshotted at its DEFAULT (freshly-mounted, no frame yet
// emitted) state so the PNG is deterministic — no animation/timer race.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

Future<void> _pump(WidgetTester tester, {double textScale = 1.0}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
      ],
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
        home: const LiveScreen(),
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

    testWidgets('live stage — $suffix', (tester) async {
      await _pump(tester, textScale: textScale);
      await _expectGolden(tester, 'e13_r18_live_stage_$suffix');
    });
  }
}
