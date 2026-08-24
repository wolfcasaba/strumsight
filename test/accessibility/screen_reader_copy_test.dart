import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// A2/A6 (§0.0/D2) — the tuner-cents and strum-direction screen-reader copy
/// is loaded through the REAL localization delegate for both supported
/// locales, and the two languages' output must differ — otherwise an
/// implementation wired to English only would still pass.
void main() {
  late AppLocalizations en;
  late AppLocalizations hu;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    hu = await AppLocalizations.delegate.load(const Locale('hu'));
  });

  group(
    'A2 — the tuner cents offset is readable as text, in both languages',
    () {
      test('a sharp reading speaks the magnitude and direction', () {
        final label = SsSemantics.tunerAccuracyLabel(
          en,
          cents: 18,
          inTune: false,
        );

        expect(label, '18 cents sharp');
        expect(label, isNotEmpty);
      });

      test('a flat reading speaks the magnitude and direction', () {
        final label = SsSemantics.tunerAccuracyLabel(
          en,
          cents: -18,
          inTune: false,
        );

        expect(label, '18 cents flat');
      });

      test('an in-tune reading speaks the achievement, not a number', () {
        final label = SsSemantics.tunerAccuracyLabel(
          en,
          cents: 3,
          inTune: true,
        );

        expect(label, 'In tune');
      });
    },
  );

  group('A2 — the strum direction is readable as text, in both languages', () {
    test('down reads as "Down"', () {
      expect(SsSemantics.strumDirectionLabel(en, isDown: true), 'Down');
    });

    test('up reads as "Up"', () {
      expect(SsSemantics.strumDirectionLabel(en, isDown: false), 'Up');
    });
  });

  group(
    'A6 — the screen-reader copy exists in English AND Hungarian, and the '
    'two languages differ (an English-only implementation must fail here)',
    () {
      test('tuner sharp/flat/in-tune copy differs between en and hu', () {
        final enSharp = SsSemantics.tunerAccuracyLabel(
          en,
          cents: 18,
          inTune: false,
        );
        final huSharp = SsSemantics.tunerAccuracyLabel(
          hu,
          cents: 18,
          inTune: false,
        );
        final enFlat = SsSemantics.tunerAccuracyLabel(
          en,
          cents: -18,
          inTune: false,
        );
        final huFlat = SsSemantics.tunerAccuracyLabel(
          hu,
          cents: -18,
          inTune: false,
        );
        final enInTune = SsSemantics.tunerAccuracyLabel(
          en,
          cents: 0,
          inTune: true,
        );
        final huInTune = SsSemantics.tunerAccuracyLabel(
          hu,
          cents: 0,
          inTune: true,
        );

        expect(huSharp, isNotEmpty);
        expect(huFlat, isNotEmpty);
        expect(huInTune, isNotEmpty);
        expect(huSharp, isNot(enSharp));
        expect(huFlat, isNot(enFlat));
        expect(huInTune, isNot(enInTune));
      });

      test('strum direction copy differs between en and hu', () {
        final enDown = SsSemantics.strumDirectionLabel(en, isDown: true);
        final huDown = SsSemantics.strumDirectionLabel(hu, isDown: true);
        final enUp = SsSemantics.strumDirectionLabel(en, isDown: false);
        final huUp = SsSemantics.strumDirectionLabel(hu, isDown: false);

        expect(huDown, isNotEmpty);
        expect(huUp, isNotEmpty);
        expect(huDown, isNot(enDown));
        expect(huUp, isNot(enUp));
        expect(huDown, 'Le');
        expect(huUp, 'Fel');
      });

      test(
        'within a single language, down and up never share the same text',
        () {
          expect(
            SsSemantics.strumDirectionLabel(hu, isDown: true),
            isNot(SsSemantics.strumDirectionLabel(hu, isDown: false)),
          );
        },
      );
    },
  );
}
