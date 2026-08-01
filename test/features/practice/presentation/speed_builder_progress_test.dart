import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_policy.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_state.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/widgets/adaptive_suggestion_banner.dart';
import 'package:strumsight/features/practice/presentation/widgets/speed_builder_progress.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'A8 — progress shows BPM, streak, attempts, loop, and no stable BPM',
    (tester) async {
      final policy = SpeedBuilderPolicy(
        startBpm: const Tempo(80),
        targetBpm: const Tempo(120),
        stepBpm: 10,
        requiredConsecutivePasses: 2,
        maxAttempts: 20,
      );
      final state = SpeedBuilderState.initial(
        policy,
      ).copyWith(successStreak: 1, attempts: const []);

      await tester.pumpWidget(
        _app(SpeedBuilderProgress(state: state, currentLoop: 2, totalLoops: 4)),
      );

      expect(find.text('Current: 80 BPM'), findsOneWidget);
      expect(find.text('Target: 120 BPM'), findsOneWidget);
      expect(find.text('Pass streak: 1 of 2'), findsOneWidget);
      expect(find.text('Next step: 90 BPM'), findsOneWidget);
      expect(find.text('Attempt: 1 of 20'), findsOneWidget);
      expect(find.text('Highest stable BPM: Not yet'), findsOneWidget);
      expect(find.text('Loop: 2 of 4'), findsOneWidget);
      expect(find.text('Highest stable BPM: 0 BPM'), findsNothing);
    },
  );

  testWidgets('A8 — progress shows highest stable BPM when available', (
    tester,
  ) async {
    final policy = SpeedBuilderPolicy(
      startBpm: const Tempo(80),
      targetBpm: const Tempo(120),
      stepBpm: 10,
    );
    final state = SpeedBuilderState.initial(
      policy,
    ).copyWith(highestStableTempo: const Tempo(90));

    await tester.pumpWidget(_app(SpeedBuilderProgress(state: state)));

    expect(find.text('Highest stable BPM: 90 BPM'), findsOneWidget);
  });

  testWidgets('A9 — rendering and dismissing never apply a suggestion', (
    tester,
  ) async {
    final commands = <AdaptiveSuggestion>[];
    const suggestion = AdaptiveSuggestion(
      reason: AdaptiveSuggestionReason.lowCompletion,
      kind: AdaptiveSuggestionKind.reduceTempo,
      suggestedTempo: Tempo(90),
    );

    await tester.pumpWidget(
      _app(
        AdaptiveSuggestionBanner(
          suggestion: suggestion,
          onAccept: commands.add,
          onDismiss: () {},
        ),
      ),
    );
    expect(commands, isEmpty);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(commands, isEmpty);
  });

  testWidgets('A9 — accepting emits exactly one command', (tester) async {
    final commands = <AdaptiveSuggestion>[];
    const suggestion = AdaptiveSuggestion(
      reason: AdaptiveSuggestionReason.directionError,
      kind: AdaptiveSuggestionKind.focusDirection,
    );

    await tester.pumpWidget(
      _app(
        AdaptiveSuggestionBanner(
          suggestion: suggestion,
          onAccept: commands.add,
          onDismiss: () {},
        ),
      ),
    );
    await tester.tap(find.text('Apply'));
    await tester.pump();

    expect(commands, <AdaptiveSuggestion>[suggestion]);
  });
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
