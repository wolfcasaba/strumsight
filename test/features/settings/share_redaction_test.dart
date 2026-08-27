// E13-R35 — A7 (§5.5 ADR 0292): the share preview leaves the device with
// minimal data by default, itemizes exactly what that is, and the user can
// only EXPAND what leaves (never shrink the always-shared core).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/share/screens/share_preview_screen.dart';
import 'package:strumsight/features/share/share_service.dart';
import 'package:strumsight/l10n/app_localizations.dart';

class _FakeShareService extends ShareService {
  const _FakeShareService(this.log);
  final List<String> log;

  @override
  Future<void> shareCard({
    required GlobalKey boundaryKey,
    required AnalyzeResult result,
    int capo = 0,
    String? title,
    bool includeTitle = false,
    Rect? sharePositionOrigin,
  }) async => log.add('card:includeTitle=$includeTitle:title=$title');

  @override
  Future<void> shareText(
    AnalyzeResult result, {
    int capo = 0,
    String? title,
    bool includeTitle = false,
    Rect? sharePositionOrigin,
  }) async => log.add('text:includeTitle=$includeTitle:title=$title');
}

final _result = AnalyzeResult(
  durationSec: 8,
  bpm: 100,
  chords: const [TimelineChord(label: 'C', startSec: 0, endSec: 4)],
  strums: [
    for (var i = 0; i < 3; i++)
      TimelineStrum(
        direction: StrumDirection.down,
        timeSec: i.toDouble(),
        confidence: 1,
      ),
  ],
);

Future<void> _pump(WidgetTester tester, List<String> log, {String? title}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SharePreviewScreen(
          result: _result,
          title: title,
          shareService: _FakeShareService(log),
        ),
      ),
    );

void main() {
  testWidgets('the always-shared core is itemized on screen', (tester) async {
    await _pump(tester, <String>[], title: 'My riff session');
    await tester.pumpAndSettle();

    expect(find.text("What you're sharing"), findsOneWidget);
    expect(find.text('Chord progression'), findsOneWidget);
    expect(find.text('Strum pattern'), findsOneWidget);
    expect(find.text('Tempo (BPM)'), findsOneWidget);
  });

  testWidgets(
    'by default the title is NOT rendered on the card and NOT in the shared '
    'caption — minimal by default (A7)',
    (tester) async {
      final log = <String>[];
      await _pump(tester, log, title: 'Secret session name');
      await tester.pumpAndSettle();

      expect(find.text('Secret session name'), findsNothing);

      // The share actions can sit below the fold once the body scrolls (A9 —
      // the screen no longer forces its content into a fixed-height Column).
      await tester.ensureVisible(find.text('Share as text'));
      await tester.tap(find.text('Share as text'));
      await tester.pumpAndSettle();
      expect(log, ['text:includeTitle=false:title=Secret session name']);
    },
  );

  testWidgets(
    'the user can EXPAND to include the title — never the other way around',
    (tester) async {
      final log = <String>[];
      await _pump(tester, log, title: 'Secret session name');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shareIncludeTitleToggle')), findsOneWidget);
      await tester.tap(find.byKey(const Key('shareIncludeTitleToggle')));
      await tester.pumpAndSettle();

      // Now visible on the card itself too.
      expect(find.text('Secret session name'), findsOneWidget);

      // The share actions can sit below the fold once the body scrolls (A9 —
      // the screen no longer forces its content into a fixed-height Column).
      await tester.ensureVisible(find.text('Share as text'));
      await tester.tap(find.text('Share as text'));
      await tester.pumpAndSettle();
      expect(log, ['text:includeTitle=true:title=Secret session name']);
    },
  );

  testWidgets(
    'no title supplied: the toggle is not offered at all (nothing to expand)',
    (tester) async {
      await _pump(tester, <String>[]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shareIncludeTitleToggle')), findsNothing);
    },
  );
}
