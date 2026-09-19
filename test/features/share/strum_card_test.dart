import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/share/widgets/strum_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

AnalyzeResult _result(int nStrums) => AnalyzeResult(
  durationSec: 12,
  bpm: 96,
  chords: const [
    TimelineChord(label: 'C', startSec: 0, endSec: 3),
    TimelineChord(label: 'G', startSec: 3, endSec: 6),
  ],
  strums: [
    for (var i = 0; i < nStrums; i++)
      TimelineStrum(
        direction: i.isEven ? StrumDirection.down : StrumDirection.up,
        timeSec: i.toDouble(),
        confidence: 0.9,
      ),
  ],
);

/// MI-H (E09, R-handoff) — pump the card under a localized MaterialApp so
/// `AppLocalizations.of(context)` resolves the `shareCard*` keys added to
/// `community_{en,hu}.arb`. The original tests pumped under a bare
/// `MaterialApp` and asserted on English literals directly; those literals
/// are no longer hard-coded in the widget tree.
Future<void> _pump(
  WidgetTester tester,
  AnalyzeResult r, {
  int capo = 0,
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  MaterialApp(
    theme: SsLightTheme.data(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: StrumCard(result: r, capo: capo),
      ),
    ),
  ),
);

void main() {
  testWidgets('renders brand, chords and the strum-direction arrows', (
    tester,
  ) async {
    await _pump(tester, _result(4));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text('StrumSight'), findsOneWidget);
    expect(find.text('C · G'), findsOneWidget);
    // The moat visual: one arrow per strum (2 down, 2 up).
    expect(find.byIcon(Icons.arrow_downward), findsNWidgets(2));
    expect(find.byIcon(Icons.arrow_upward), findsNWidgets(2));
    // Stat chips — labels now resolve through l10n (MI-H).
    expect(find.text('96'), findsOneWidget); // BPM value
    expect(find.text(l10n.shareCardDownLabel), findsOneWidget);
    expect(find.text(l10n.shareCardUpLabel), findsOneWidget);
  });

  testWidgets('caps the arrow row at 16 and marks truncation', (tester) async {
    await _pump(tester, _result(40));
    // 40 strums alternate down/up → capped at 16 shown (8 down, 8 up) + "…".
    expect(find.byIcon(Icons.arrow_downward), findsNWidgets(8));
    expect(find.byIcon(Icons.arrow_upward), findsNWidgets(8));
    expect(find.text('…'), findsOneWidget);
  });

  testWidgets('capo shifts the chord label on the card', (tester) async {
    await _pump(tester, _result(2), capo: 2);
    expect(find.text('A# · F'), findsOneWidget);
  });

  testWidgets('a strum-less result shows a graceful placeholder', (
    tester,
  ) async {
    await _pump(tester, AnalyzeResult.empty);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.shareCardNoStrumsPlaceholder), findsOneWidget);
    expect(find.text(l10n.shareCardMyRiffFallback), findsOneWidget);
  });

  // MI-H — the localized labels resolve under hu too. Same widget, the
  // underlying ARB-driven strings must differ (regression guard for the
  // parity rule in `test/l10n/arb_parity_test.dart`).
  for (final locale in [const Locale('en'), const Locale('hu')]) {
    testWidgets(
      'MI-H: StrumCard labels resolve through l10n (${locale.languageCode})',
      (tester) async {
        await _pump(tester, _result(4), locale: locale);
        final l10n = await AppLocalizations.delegate.load(locale);
        expect(find.text(l10n.shareCardDownLabel), findsOneWidget);
        expect(find.text(l10n.shareCardUpLabel), findsOneWidget);
        expect(find.text(l10n.shareCardChordsLabel), findsOneWidget);
        expect(find.text(l10n.shareCardBpmLabel), findsOneWidget);
        expect(find.text(l10n.shareCardLengthLabel), findsOneWidget);
      },
    );
  }
}
