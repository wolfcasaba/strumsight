// E14-R13 — the ok-banner's own mercury: every RecognitionRejectReason value
// (ADR 0505 D3, the MERGED closed enum) must map to a non-empty, localized
// text, and the eleven texts must be pairwise distinct in EACH locale (ADR
// 0520 D2/D3). Iterating `RecognitionRejectReason.values` — not eleven
// copy-pasted cells — is what makes a future enum member fail this test at
// compile time (a new switch arm required) rather than silently.
//
// E17-R15 — the merged `signalQuality` reason became six typed ones, so the
// advice must also point the RIGHT WAY: the last group is ADR 0535 D3's
// content guard (never "move closer" for a too-loud or clipping signal, never
// "back away" for a too-quiet one).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/widgets/uncertainty_reason_banner.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _locales = [Locale('en'), Locale('hu')];

/// Advice that pulls the player TOWARDS the mic — harmful when the signal is
/// already too loud or clipping (ADR 0535 D3).
const _towardsMic = ['closer', 'közelebb'];

/// Advice that pushes the player AWAY from the mic — harmful when the signal
/// is too quiet (ADR 0535 D3).
const _awayFromMic = ['back', 'further', 'távolabb', 'távolodj'];

void main() {
  group(
    'UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2)',
    () {
      for (final locale in _locales) {
        final l10n = lookupAppLocalizations(locale);
        for (final reason in RecognitionRejectReason.values) {
          test(
            '${locale.languageCode}: $reason has a non-empty localized text',
            () {
              final text = UncertaintyReasonBanner.textFor(l10n, reason);
              expect(text, isNotEmpty);
            },
          );
        }
      }
    },
  );

  group('UncertaintyReasonBanner.textFor — distinctness (ADR 0520 D3)', () {
    for (final locale in _locales) {
      test(
        '${locale.languageCode}: the reason texts are pairwise distinct',
        () {
          final l10n = lookupAppLocalizations(locale);
          final texts = RecognitionRejectReason.values
              .map((reason) => UncertaintyReasonBanner.textFor(l10n, reason))
              .toSet();
          expect(texts.length, RecognitionRejectReason.values.length);
        },
      );
    }
  });

  group('ADR 0535 D3 — advice direction is never harmful', () {
    for (final locale in _locales) {
      final language = locale.languageCode;

      for (final reason in const [
        RecognitionRejectReason.signalTooLoud,
        RecognitionRejectReason.signalClipping,
      ]) {
        test('$language: $reason never advises moving closer to the mic', () {
          final l10n = lookupAppLocalizations(locale);
          final text = UncertaintyReasonBanner.textFor(l10n, reason);
          for (final phrase in _towardsMic) {
            expect(text.toLowerCase(), isNot(contains(phrase)));
          }
        });
      }

      test('$language: signalTooQuiet never advises backing away', () {
        final l10n = lookupAppLocalizations(locale);
        final text = UncertaintyReasonBanner.textFor(
          l10n,
          RecognitionRejectReason.signalTooQuiet,
        );
        for (final phrase in _awayFromMic) {
          expect(text.toLowerCase(), isNot(contains(phrase)));
        }
      });

      test('$language: signalTooQuiet and signalTooLoud read differently', () {
        final l10n = lookupAppLocalizations(locale);
        final quiet = UncertaintyReasonBanner.textFor(
          l10n,
          RecognitionRejectReason.signalTooQuiet,
        );
        final loud = UncertaintyReasonBanner.textFor(
          l10n,
          RecognitionRejectReason.signalTooLoud,
        );
        expect(quiet, isNot(loud));
      });
    }
  });

  testWidgets('the banner renders the reason text for a real widget tree', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: UncertaintyReasonBanner(
            reason: RecognitionRejectReason.signalTooQuiet,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      find.text(
        UncertaintyReasonBanner.textFor(
          l10n,
          RecognitionRejectReason.signalTooQuiet,
        ),
      ),
      findsOneWidget,
    );
  });
}
