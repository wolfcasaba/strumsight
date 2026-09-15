import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/share/model/weekly_recap.dart';
import 'package:strumsight/features/share/screens/share_preview_screen.dart';
import 'package:strumsight/features/share/screens/wrapped_preview_screen.dart';
import 'package:strumsight/features/share/share_service.dart';
import 'package:strumsight/features/share/widgets/strum_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Ch18 spec §12 — the Strum Card and the Wrapped recap build up in the
/// preview; the image share is gated on the final frame (the capture is
/// never a half-built card); reduced motion is complete at once; and a
/// card rendered with no reveal above it (the export path, the card tests)
/// is untouched.
class _LogShareService extends ShareService {
  const _LogShareService(this.log);
  final List<String> log;

  @override
  Future<void> shareCard({
    required GlobalKey boundaryKey,
    required AnalyzeResult result,
    int capo = 0,
    String? title,
    bool includeTitle = false,
    Rect? sharePositionOrigin,
  }) async => log.add('card');

  @override
  Future<void> shareImage({
    required GlobalKey boundaryKey,
    required String caption,
    required String fileName,
    String? fallbackText,
    Rect? sharePositionOrigin,
  }) async => log.add('image');
}

final _result = AnalyzeResult(
  durationSec: 8,
  bpm: 100,
  chords: const [TimelineChord(label: 'C', startSec: 0, endSec: 4)],
  strums: [
    for (var i = 0; i < 4; i++)
      TimelineStrum(
        direction: i.isEven ? StrumDirection.down : StrumDirection.up,
        timeSec: i.toDouble(),
        confidence: 1,
      ),
  ],
);

Widget _app(Widget home, {bool reducedMotion = false}) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: home,
  ),
);

SsButton _button(WidgetTester tester, String label) => tester.widget<SsButton>(
  find.byWidgetPredicate((w) => w is SsButton && w.label == label),
);

void main() {
  testWidgets('the card share waits for the reveal, then shares', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        SharePreviewScreen(
          result: _result,
          shareService: _LogShareService(log),
        ),
      ),
    );

    // Mid-reveal: the wordmark is still fading in; the image share is off.
    expect(find.byType(SsShareReveal), findsOneWidget);
    expect(_button(tester, 'Share card').onPressed, isNull);
    await tester.pump(SsMotion.celebration ~/ 4);
    expect(_button(tester, 'Share card').onPressed, isNull);

    // Final frame: every slot is inert and the share is live.
    await tester.pumpAndSettle();
    expect(_button(tester, 'Share card').onPressed, isNotNull);
    expect(
      find.descendant(
        of: find.byType(StrumCard),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    // The moat visual survives the reveal: one arrow per strum.
    expect(find.byIcon(Icons.arrow_downward), findsNWidgets(2));
    expect(find.byIcon(Icons.arrow_upward), findsNWidgets(2));

    await tester.ensureVisible(find.text('Share card'));
    await tester.tap(find.text('Share card'));
    await tester.pumpAndSettle();
    expect(log, ['card']);
  });

  testWidgets('the text share never waits for pixels', (tester) async {
    await tester.pumpWidget(
      _app(
        SharePreviewScreen(result: _result, shareService: _LogShareService([])),
      ),
    );
    expect(_button(tester, 'Share as text').onPressed, isNotNull);
  });

  testWidgets('reduced motion: the card is final and shareable at once', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SharePreviewScreen(result: _result, shareService: _LogShareService([])),
        reducedMotion: true,
      ),
    );
    expect(
      find.descendant(
        of: find.byType(StrumCard),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    // The completion is posted after the first frame.
    await tester.pump();
    expect(_button(tester, 'Share card').onPressed, isNotNull);
  });

  testWidgets('the Wrapped recap reveals and gates its share the same way', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        WrappedPreviewScreen(
          recap: const WeeklyRecap(
            minutes: 42,
            sessions: 5,
            strokes: 980,
            daysPracticed: 5,
            bestDay: 100,
            averageAccuracy: 0.87,
            streak: 6,
          ),
          weekLabel: 'Jul 6 – Jul 12',
          today: 100,
          shareService: _LogShareService(log),
        ),
      ),
    );
    expect(_button(tester, 'Share card').onPressed, isNull);
    await tester.pumpAndSettle();
    expect(_button(tester, 'Share card').onPressed, isNotNull);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('🔥 6-day streak'), findsOneWidget);

    await tester.tap(find.text('Share card'));
    await tester.pumpAndSettle();
    expect(log, ['image']);
  });
}
