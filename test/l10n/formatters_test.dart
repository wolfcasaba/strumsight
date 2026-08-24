import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Locale-aware formatter output (A4) and pseudo-locale overflow resilience
/// (A6) — ADR 0424 §5.3/§5.4/§5.9. Every expected string below was measured
/// directly against `package:intl` (en/hu CLDR data), not guessed.
void main() {
  late AppLocalizations en;
  late AppLocalizations hu;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    hu = await AppLocalizations.delegate.load(const Locale('hu'));
  });

  group('A4 — locale-aware formatters', () {
    test('duration: decimal separator differs (en "." vs hu ",")', () {
      const value = Duration(seconds: 750); // 12.5 minutes
      expect(SsFormatters.duration(value, localeName: 'en'), '12.5');
      expect(SsFormatters.duration(value, localeName: 'hu'), '12,5');
    });

    test('bpm: grouping AND decimal separators differ for large values', () {
      expect(SsFormatters.bpm(1234.5, localeName: 'en'), '1,234.5');
      expect(SsFormatters.bpm(1234.5, localeName: 'hu'), '1 234,5');
    });

    test('bpm: typical tuner range renders identically in shape', () {
      expect(SsFormatters.bpm(128, localeName: 'en'), '128');
      expect(SsFormatters.bpm(128, localeName: 'hu'), '128');
    });

    test('cents: signed decimal, locale decimal separator (F9 guard)', () {
      expect(SsFormatters.cents(-7.4, localeName: 'en'), '-7.4');
      expect(SsFormatters.cents(-7.4, localeName: 'hu'), '-7,4');
      expect(SsFormatters.cents(0, localeName: 'en'), '+0.0');
      expect(SsFormatters.cents(0, localeName: 'hu'), '+0,0');
    });

    test('percent: fractional percentages expose the locale decimal comma', () {
      expect(
        SsFormatters.percent(0.4567, localeName: 'en', decimalDigits: 1),
        '45.7%',
      );
      expect(
        SsFormatters.percent(0.4567, localeName: 'hu', decimalDigits: 1),
        '45,7%',
      );
      expect(SsFormatters.percent(0.12, localeName: 'en'), '12%');
      expect(SsFormatters.percent(0.12, localeName: 'hu'), '12%');
    });

    test(
      'date: en and hu use entirely different calendar layouts (F8 guard)',
      () {
        final date = DateTime(2026, 8, 24);
        expect(SsFormatters.date(date, localeName: 'en'), 'Aug 24, 2026');
        expect(SsFormatters.date(date, localeName: 'hu'), '2026. aug. 24.');
      },
    );
  });

  group('pseudo-locale transform (F10/F11)', () {
    const expectedMinLengths = {10: 16, 20: 32, 40: 64, 80: 128};

    for (final MapEntry(key: inputLength, value: minOutputLength)
        in expectedMinLengths.entries) {
      test(
        'input length $inputLength expands to at least $minOutputLength chars',
        () {
          final sample = _labelOfLength(inputLength);
          final result = ssPseudoLocalize(sample);
          expect(
            result.length,
            greaterThanOrEqualTo(minOutputLength),
            reason:
                'ssPseudoLocalize must reach at least '
                '${ssPseudoLocaleExpansionFactor}x the input length',
          );
        },
      );
    }

    test('placeholder tokens survive untouched, in order (F11)', () {
      const input = 'Hello {name}, you unlocked {count} chords today';
      final result = ssPseudoLocalize(input);

      expect(result, contains('{name}'));
      expect(result, contains('{count}'));
      expect(result.indexOf('{name}'), lessThan(result.indexOf('{count}')));
    });

    test('empty input stays empty', () {
      expect(ssPseudoLocalize(''), isEmpty);
    });
  });

  group(
    'A6 — critical component resists clipping under length + scale stress',
    () {
      // SsFieldError (public.dart → components/inputs/ss_validation_summary.dart)
      // is the chosen carrier: a real, translated, single-line-unbounded label
      // (Row(icon, Expanded(Text(...)))) with no `maxLines`/height cap, so it
      // wraps instead of silently ellipsizing when a translation runs long.
      //
      // F3 fix: `SsFieldError` alone as `Scaffold(body:)` can NEVER report an
      // overflow exception — its Row's main axis (horizontal) is fully
      // absorbed by `Expanded`, and Row never checks its CROSS axis
      // (vertical) for overflow, so no amount of wrapped text throws,
      // regardless of how tall it grows (measured: even 4000 chars produced
      // `takeException() == null`, both with and without an enclosing
      // `SizedBox(height:)`). That made the three cells below unfalsifiable —
      // they could never have gone red, whatever the implementation did.
      //
      // Adding an intervening `Column` (below, in `pumpAtSize`) fixes this
      // without touching production code: a `Column`'s MAIN axis is vertical,
      // so it DOES run RenderFlex's non-flex-child overflow check against the
      // real ceiling `Scaffold` already imposes on its body (the device's
      // screen height) — measured (see the `Column` comment below): 46/52/64
      // chars need only 220–308px and stay far under an 852px-tall screen
      // (no exception), while a 200-char message needs 1056px and DOES throw
      // ("A RenderFlex overflowed by 204 pixels on the bottom"). The
      // 'falsifiability proof' cell below exercises exactly that.
      const logicalSize = Size(393, 852); // a representative modern phone
      const devicePixelRatio = 3.0;

      Future<Size> pumpAtSize(WidgetTester tester, String message) async {
        tester.view.physicalSize = logicalSize * devicePixelRatio;
        tester.view.devicePixelRatio = devicePixelRatio;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ssPseudoLocaleTestHarness(
            textScale: 2.0,
            child: Theme(
              data: SsLightTheme.data(),
              // The `Column` is the F3 fix (see group comment): it gives
              // RenderFlex a vertical main axis to enforce Scaffold's own
              // bounded body height against, which `SsFieldError` alone does
              // not.
              child: Column(
                children: [SsFieldError(l10n: en, message: message)],
              ),
            ),
          ),
        );
        await tester.pump();

        // F12 (L452 closure): prove the declared geometry actually reached the
        // render tree — a `MediaQuery(size:)`-only setup would leave this at
        // the flutter_test default (800×600) no matter what we assert above.
        // The `Scaffold`'s own reported size is unaffected by a descendant
        // overflowing (overflow paints outside its box; it doesn't resize an
        // ancestor already laid out with a bounded constraint) — this holds
        // in the falsifiability-proof cell below too, which asserts it
        // alongside a non-null exception.
        return tester.getSize(find.byType(Scaffold));
      }

      testWidgets('below the +30% reserve threshold (46 chars, +15%)', (
        tester,
      ) async {
        final measuredSize = await pumpAtSize(tester, _labelOfLength(46));
        expect(tester.takeException(), isNull);
        expect(measuredSize, logicalSize);
      });

      testWidgets('at the mandatory +30% reserve threshold (52 chars)', (
        tester,
      ) async {
        final measuredSize = await pumpAtSize(tester, _labelOfLength(52));
        expect(tester.takeException(), isNull);
        expect(measuredSize, logicalSize);
      });

      testWidgets('above threshold via the pseudo-locale transform (+60%)', (
        tester,
      ) async {
        final expanded = ssPseudoLocalize(_labelOfLength(40));
        expect(expanded.length, greaterThanOrEqualTo(64));

        final measuredSize = await pumpAtSize(tester, expanded);
        expect(tester.takeException(), isNull);
        expect(measuredSize, logicalSize);
      });

      testWidgets('Hungarian locale at the same stress point does not clip', (
        tester,
      ) async {
        final measuredSize = await pumpAtSize(
          tester,
          _repeat(hu.dsValidationSummaryTitle, 3),
        );
        expect(tester.takeException(), isNull);
        expect(measuredSize, logicalSize);
      });

      testWidgets(
        'falsifiability proof: a genuinely too-long message DOES overflow '
        'on this same carrier + context (F3)',
        (tester) async {
          // 200 chars is 5x the 40-char baseline — far beyond any realistic
          // translation growth (pseudo-locale worst case is +60%, i.e. 64
          // chars) — a deliberate stress input, not a plausible translation.
          // Measured: needs 1056px, the Scaffold's body offers ~852px, so
          // this overflows by 204px on the bottom. Without this cell, the
          // three cells above could pass vacuously even if a future change
          // made `SsFieldError` clip for real (ADR 0424 §5.9 falsifiability).
          final measuredSize = await pumpAtSize(tester, _labelOfLength(200));
          expect(tester.takeException(), isNotNull);
          expect(measuredSize, logicalSize);
        },
      );
    },
  );
}

/// A deterministic, exactly-[length]-character synthetic label — the brief's
/// "40-character English label" baseline is generic by design (ADR 0424
/// §6.2), not tied to any single real ARB string.
String _labelOfLength(int length) {
  const cycle = 'Practice reminder settings label ';
  final repeatCount = (length / cycle.length).ceil() + 1;
  return List.filled(repeatCount, cycle).join().substring(0, length);
}

String _repeat(String value, int times) => List.filled(times, value).join(' ');
