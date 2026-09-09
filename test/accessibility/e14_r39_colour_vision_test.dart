// E14-R39 (ADR 0547) — the grayscale / colour-vision cell the R39 audit was
// missing.
//
// The existing suite already has a "no state is conveyed by colour ALONE"
// cell. This file measures the other half: WHICH semantic colours actually
// collapse when hue is removed (a grayscale reader, or a deuteranope reading
// a warm palette), and proves that for every collapsing pair the state is
// still carried by a channel that survives — icon and label.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/tuner/model/tuner_reading.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../tool/ui_contrast_check.dart';
import '../support/fake_audio.dart';
import '../support/fake_engines.dart';
import '../support/preference_store.dart';

/// WCAG contrast between two colours, computed from the canonical sRGB
/// relative-luminance transform the repo already pins
/// (`tool/ui_contrast_check.dart`). In GRAYSCALE this ratio is the whole
/// story: hue is gone, so two colours are distinguishable only if their
/// luminances differ.
double _grayscaleSeparation(Color a, Color b) {
  final la = ContrastCheck.relativeLuminance(a.toARGB32());
  final lb = ContrastCheck.relativeLuminance(b.toARGB32());
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The separation below which two colours are the same shade of grey to a
/// reader with no hue discrimination — the WCAG non-text floor (3:1).
const _nonTextFloor = 3.0;

/// A grayscale colour-vision simulation: the whole subtree is painted
/// through the luminance matrix. It proves the tree RENDERS under total hue
/// loss; the icon/label assertions below are what prove the STATE survives
/// it.
Widget _grayscale(Widget child) => ColorFiltered(
  colorFilter: const ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]),
  child: child,
);

Future<FakeTunerEngine> _pumpTuner(WidgetTester tester) async {
  final engine = FakeTunerEngine();
  addTearDown(engine.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(),
        tunerEngineProvider.overrideWithValue(engine),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _grayscale(const TunerScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return engine;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('which semantic colours collapse in grayscale (MEASURED)', () {
    test(
      'no pair of confidence tokens reaches even the 3:1 non-text floor in '
      'either theme — hue is doing all the work, so hue must never be the '
      'only channel anywhere they appear',
      () {
        for (final brightness in Brightness.values) {
          final colors = SsColorScheme.forBrightness(brightness);
          final pairs = <String, double>{
            'high-medium': _grayscaleSeparation(
              colors.confidenceHigh,
              colors.confidenceMedium,
            ),
            'high-low': _grayscaleSeparation(
              colors.confidenceHigh,
              colors.confidenceLow,
            ),
            'medium-low': _grayscaleSeparation(
              colors.confidenceMedium,
              colors.confidenceLow,
            ),
          };
          for (final entry in pairs.entries) {
            expect(
              entry.value,
              lessThan(_nonTextFloor),
              reason:
                  'MEASURED FINDING (docs/accessibility/ch14-r39-audit.md): '
                  '$brightness ${entry.key} separates by only '
                  '${entry.value.toStringAsFixed(2)}:1 in grayscale. This '
                  'cell pins the measurement — if a future palette round '
                  'fixes it, THIS expectation is what must be updated, so '
                  'the audit can never keep claiming a defect that is gone.',
            );
          }
        }
      },
    );

    test('the worst pair is a total collapse: high-medium on the dark stage '
        'theme is 1.01:1 — visually one shade of grey', () {
      final colors = SsColorScheme.forBrightness(Brightness.dark);

      expect(
        _grayscaleSeparation(colors.confidenceHigh, colors.confidenceMedium),
        closeTo(1.01, 0.01),
      );
    });

    test('the metric itself is falsifiable: black vs white is the maximum '
        '21:1 and a colour against itself is 1:1', () {
      expect(
        _grayscaleSeparation(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
      expect(
        _grayscaleSeparation(const Color(0xFF3ED598), const Color(0xFF3ED598)),
        closeTo(1, 1e-9),
      );
    });
  });

  group('the non-colour channel that carries the collapsing states', () {
    test('every status-marker kind has its OWN icon', () {
      final icons = <IconData>{
        for (final kind in SsStatusMarkerKind.values)
          SsStatusMarkers.forKind(kind).icon,
      };

      expect(icons, hasLength(SsStatusMarkerKind.values.length));
    });

    testWidgets(
      'the confidence badge distinguishes high/medium/low by LABEL, and '
      'paints its icon in the readable text token rather than the '
      'grayscale-identical status hue',
      (tester) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
        final theme = SsDarkTheme.data();
        final textPrimary = theme.extension<SsColorScheme>()!.textPrimary;
        final cells = <SsStatusBadgeKind, String>{
          SsStatusBadgeKind.confidenceHigh: l10n.dsStatusBadgeConfidenceHigh,
          SsStatusBadgeKind.confidenceMedium:
              l10n.dsStatusBadgeConfidenceMedium,
          SsStatusBadgeKind.confidenceLow: l10n.dsStatusBadgeConfidenceLow,
        };

        expect(
          cells.values.toSet(),
          hasLength(cells.length),
          reason:
              'three grayscale-identical colours need three distinct labels',
        );

        for (final entry in cells.entries) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: _grayscale(SsStatusBadge(l10n: l10n, kind: entry.key)),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text(entry.value), findsOneWidget);
          expect(
            tester.widget<Icon>(find.byType(Icon)).color,
            textPrimary,
            reason: 'the badge must not paint state in a status hue',
          );
        }
      },
    );
  });

  group('the tuner keeps its state under total hue loss', () {
    testWidgets(
      'in tune and out of tune differ by ICON, not only by the green/copper '
      'hue a colour-blind player cannot separate',
      (tester) async {
        final engine = await _pumpTuner(tester);

        engine.emit(const TunerReading(note: 'A', cents: 0, frequencyHz: 110));
        await tester.pumpAndSettle();
        expect(
          find.byIcon(Icons.check_circle),
          findsOneWidget,
          reason: 'in tune is announced by a check glyph, not by green alone',
        );

        engine.emit(
          const TunerReading(note: 'A', cents: 30, frequencyHz: 111.9),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.check_circle), findsNothing);
        expect(
          find.byIcon(Icons.arrow_upward),
          findsOneWidget,
          reason: 'sharp is a direction glyph plus a cents number',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
