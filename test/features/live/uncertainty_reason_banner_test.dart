// E14-R13 — the ok-banner's own mercury: every RecognitionRejectReason value
// (ADR 0505 D3, the MERGED closed enum) must map to a non-empty, localized
// text, and the six texts must be pairwise distinct in EACH locale (ADR 0520
// D2/D3). Iterating `RecognitionRejectReason.values` — not six copy-pasted
// cells — is what makes a future enum member fail this test at compile time
// (a new switch arm required) rather than silently.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/widgets/uncertainty_reason_banner.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _locales = [Locale('en'), Locale('hu')];

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
        '${locale.languageCode}: the six reason texts are pairwise distinct',
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

  testWidgets('the banner renders the reason text for a real widget tree', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: UncertaintyReasonBanner(
            reason: RecognitionRejectReason.signalQuality,
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
          RecognitionRejectReason.signalQuality,
        ),
      ),
      findsOneWidget,
    );
  });
}
