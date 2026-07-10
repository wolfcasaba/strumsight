import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/screens/latency_calibration_screen.dart';
import 'package:music_theory/features/settings/providers/input_latency_provider.dart';
import 'package:music_theory/features/settings/providers/visual_latency_provider.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LatencyCalibrationScreen(),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a consistent 8-tap run measures the offset and saves it',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Start'));
    await tester.pump();

    // Beats at 0.6 s intervals; "tap" 80 ms after each of 8 beats. The ticker
    // is driven deterministically by pump().
    for (var k = 1; k <= 8; k++) {
      // Advance to k*0.6 + 0.08 total elapsed.
      await tester.pump(const Duration(milliseconds: 600));
      if (k == 1) await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('TAP'));
      await tester.pump();
    }

    // Run complete: the result and the Save button are shown.
    expect(find.textContaining('80 ms'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Calibration saved'), findsOneWidget);

    final ctx = tester.element(find.byType(LatencyCalibrationScreen));
    final saved = ProviderScope.containerOf(ctx).read(inputLatencyProvider);
    expect(saved, 80);
  });

  testWidgets('progress counts taps and shows the running total',
      (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('0 / 8'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 640));
    await tester.tap(find.text('TAP'));
    await tester.pump();
    expect(find.text('1 / 8'), findsOneWidget);
  });

  testWidgets('Visual mode saves to the VISUAL latency provider',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Visual'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();

    for (var k = 1; k <= 8; k++) {
      await tester.pump(const Duration(milliseconds: 600));
      if (k == 1) await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.text('TAP'));
      await tester.pump();
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(LatencyCalibrationScreen));
    final container = ProviderScope.containerOf(ctx);
    expect(container.read(visualLatencyProvider), 40);
    expect(container.read(inputLatencyProvider), 0,
        reason: 'visual mode must not touch the audio offset');
  });
}
