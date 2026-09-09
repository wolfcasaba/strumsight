// E14-R39 (ADR 0547) — the outdoor-readability half of the audit, as far as
// a test can take it.
//
// Real outdoor readability needs sunlight, three phones and a person
// standing 1–2 m from the fretboard; that stays a HUMAN measurement
// (docs/accessibility/ch14-r39-audit.md, "not measured here"). What IS
// machine-measurable is the thing sunlight punishes first: luminance
// contrast between what the stage screens paint and the surface they paint
// it on. This file measures exactly that, with the repo's canonical WCAG
// transform, and pins BOTH the tokens that pass and the ones that do not.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../tool/ui_contrast_check.dart';
import '../support/fake_audio.dart';
import '../support/fake_engines.dart';
import '../support/preference_store.dart';

/// WCAG 2.x contrast ratio, built on the same relative-luminance transform
/// `tool/ui_contrast_check.dart` pins (`ContrastCheck.relativeLuminance`),
/// so these numbers are the repo's numbers, not a second implementation.
double _ratio(Color fg, Color bg) {
  final a = ContrastCheck.relativeLuminance(fg.toARGB32());
  final b = ContrastCheck.relativeLuminance(bg.toARGB32());
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

/// WCAG AA for body text and for the icon/indicator level.
const _textFloor = 4.5;
const _nonTextFloor = 3.0;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the dark stage theme (the shipped default)', () {
    final colors = SsColorScheme.forBrightness(Brightness.dark);

    test('every text and status token clears the 4.5:1 text floor on the '
        'stage canvas', () {
      final tokens = <String, Color>{
        'textPrimary': colors.textPrimary,
        'textSecondary': colors.textSecondary,
        'brand': colors.brand,
        'success': colors.success,
        'warning': colors.warning,
        'danger': colors.danger,
        'info': colors.info,
      };

      for (final entry in tokens.entries) {
        expect(
          _ratio(entry.value, colors.canvas),
          greaterThanOrEqualTo(_textFloor),
          reason: '${entry.key} on canvas',
        );
      }
    });

    test('MEASURED GAP — confidenceLow clears the 3:1 indicator floor but '
        'NOT the 4.5:1 text floor, so it may mark a dot and must never be '
        'the colour a sentence is written in', () {
      final measured = _ratio(colors.confidenceLow, colors.canvas);

      expect(measured, greaterThanOrEqualTo(_nonTextFloor));
      expect(measured, lessThan(_textFloor));
      expect(measured, closeTo(4.04, 0.02));
    });
  });

  // The light theme is not a cosmetic preference here: it is the mode a
  // player switches to OUTDOORS, so its failures are outdoor failures.
  group('the light theme — the outdoor mode — MEASURED FAILURES', () {
    final colors = SsColorScheme.forBrightness(Brightness.light);

    test('the brand accent falls below even the 3:1 indicator floor '
        '(2.40:1) — and the tuner paints its direction readout in it', () {
      expect(_ratio(colors.brand, colors.canvas), closeTo(2.40, 0.02));
      expect(_ratio(colors.brand, colors.canvas), lessThan(_nonTextFloor));
    });

    test('the info/secondary amber is the worst token in the palette '
        '(1.93:1) — barely visible on the light canvas', () {
      expect(_ratio(colors.info, colors.canvas), closeTo(1.93, 0.02));
      expect(_ratio(colors.info, colors.canvas), lessThan(_nonTextFloor));
    });

    test('danger and success are indicator-legal but NOT text-legal', () {
      for (final token in <Color>[colors.danger, colors.success]) {
        final measured = _ratio(token, colors.canvas);
        expect(measured, greaterThanOrEqualTo(_nonTextFloor));
        expect(measured, lessThan(_textFloor));
      }
    });

    test('what still holds: both text tokens, warning and confidenceLow '
        'clear the text floor, so body copy is never the problem', () {
      for (final token in <Color>[
        colors.textPrimary,
        colors.textSecondary,
        colors.warning,
        colors.confidenceLow,
      ]) {
        expect(
          _ratio(token, colors.canvas),
          greaterThanOrEqualTo(_textFloor),
        );
      }
    });
  });

  group('what the High Contrast theme actually does', () {
    test('MEASURED: it thickens borders and drops decorative effects — it '
        'raises NO text or status contrast, and it exists only in dark, so '
        'it is not an answer to the light-mode outdoor gaps above', () {
      final plain = SsColorScheme.forBrightness(Brightness.dark);
      final hc = SsColorScheme.forBrightness(
        Brightness.dark,
        highContrast: true,
      );

      expect(hc.textPrimary, plain.textPrimary);
      expect(hc.textSecondary, plain.textSecondary);
      expect(hc.canvas, plain.canvas);
      expect(hc.brand, plain.brand);
      expect(
        hc.border,
        isNot(plain.border),
        reason: 'the ONE colour token High Contrast changes',
      );

      final theme = SsHighContrastTheme.data();
      final behavior = theme.extension<SsThemeBehavior>()!;
      final plainBehavior = SsDarkTheme.data().extension<SsThemeBehavior>()!;

      expect(theme.brightness, Brightness.dark, reason: 'dark-only');
      expect(behavior.borderWidth, greaterThan(plainBehavior.borderWidth));
      expect(
        behavior.focusRingWidth,
        greaterThan(plainBehavior.focusRingWidth),
      );
      expect(behavior.decorativeEffectsEnabled, isFalse);
    });
  });

  group('the stage screens render under the High Contrast theme', () {
    Future<void> pump(
      WidgetTester tester,
      Widget home,
      List<Override> extra,
    ) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          ...fakeAudioOverrides(),
          ...extra,
        ],
        child: MaterialApp(
          theme: SsHighContrastTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );

    testWidgets('Today hub', (tester) async {
      await pump(tester, TodayHubScreen(now: DateTime(2026, 8, 25, 18)), []);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('today-hub-primary-cta')),
        findsOneWidget,
      );
    });

    testWidgets('Tuner', (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      await pump(tester, const TunerScreen(), [
        tunerEngineProvider.overrideWithValue(engine),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      expect(tester.takeException(), isNull);
      expect(find.byType(TunerScreen), findsOneWidget);
    });
  });
}
