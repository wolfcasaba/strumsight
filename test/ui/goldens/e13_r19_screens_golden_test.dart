// Golden snapshots of the E13-R19 migrated Tuner and Metronome screens, at a
// compact portrait phone (412×915) and the same frame at textScaler 2.0 —
// the two frames the round brief §7/A8 requires. Pattern and sizing follow
// the merged `test/ui/goldens/e13_r18_screens_golden_test.dart` precedent:
// `AppTheme` (not `SsDarkTheme`), because that is the app's actual runtime
// theme — see that file's own comment, and the E13-R19 handoff (§10), for
// why the new tuner/metronome pieces stay palette-driven instead of
// depending on `SsColorScheme`.
//
// Every large, contiguous fill in these two screens comes from a CONSTANT
// colour source (`AppColors`/`context.palette`), never
// `Theme.of(context).colorScheme.*` (seed-derived HCT) — brief §0.0/R5.4,
// the measured box↔CI diff this round must not reintroduce.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/features/tuner/model/tuner_reading.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

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
      overrides: overrides,
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

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('tuner — $suffix', (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      await _pump(
        tester,
        const TunerScreen(),
        overrides: [
          ...preferenceOverrides(),
          tunerEngineProvider.overrideWithValue(engine),
        ],
        textScale: textScale,
      );
      engine.emit(const TunerReading(note: 'A', cents: 0, frequencyHz: 110));
      await tester.pumpAndSettle();
      await _expectGolden(tester, 'e13_r19_tuner_$suffix');
    });

    testWidgets('metronome — $suffix', (tester) async {
      await _pump(tester, const MetronomeScreen(), textScale: textScale);
      await _expectGolden(tester, 'e13_r19_metronome_$suffix');
    });
  }
}
