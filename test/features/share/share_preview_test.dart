import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/share/screens/share_preview_screen.dart';
import 'package:music_theory/features/share/share_service.dart';
import 'package:music_theory/l10n/app_localizations.dart';

/// Records which share path was taken instead of hitting the OS share sheet.
class FakeShareService extends ShareService {
  const FakeShareService(this.log);
  final List<String> log;

  @override
  Future<void> shareCard({
    required GlobalKey boundaryKey,
    required AnalyzeResult result,
    int capo = 0,
    Rect? sharePositionOrigin,
  }) async =>
      log.add('card:${result.strums.length}:capo$capo');

  @override
  Future<void> shareText(
    AnalyzeResult result, {
    int capo = 0,
    Rect? sharePositionOrigin,
  }) async =>
      log.add('text');
}

final _result = AnalyzeResult(
  durationSec: 8,
  bpm: 100,
  chords: const [TimelineChord(label: 'C', startSec: 0, endSec: 4)],
  strums: [
    for (var i = 0; i < 3; i++)
      TimelineStrum(
          direction: StrumDirection.down, timeSec: i.toDouble(), confidence: 1),
  ],
);

Future<void> _pump(WidgetTester tester, List<String> log, {int capo = 0}) =>
    tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SharePreviewScreen(
        result: _result,
        capo: capo,
        shareService: FakeShareService(log),
      ),
    ));

void main() {
  testWidgets('previews the card and shares the image on tap', (tester) async {
    final log = <String>[];
    await _pump(tester, log, capo: 2);
    await tester.pumpAndSettle();

    // The card is previewed.
    expect(find.text('StrumSight'), findsOneWidget);

    await tester.tap(find.text('Share card'));
    await tester.pumpAndSettle();
    expect(log, ['card:3:capo2']);
  });

  testWidgets('the text-only fallback shares just the caption', (tester) async {
    final log = <String>[];
    await _pump(tester, log);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share as text'));
    await tester.pumpAndSettle();
    expect(log, ['text']);
  });
}
