import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_progress_view.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'uses localized phase text and an accessible cancel action without a synthetic percentage',
    (tester) async {
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AnalysisProgressView(
              phase: AnalysisProgressPhase.preprocessing,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      expect(find.text('Preparing audio'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.bySemanticsLabel('Cancel analysis'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Cancel analysis'));
      expect(cancelled, isTrue);
    },
  );

  testWidgets('uses indeterminate progress when the total unit count is zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: AnalysisProgressView(
            phase: AnalysisProgressPhase.preprocessing,
            onCancel: _noop,
            completedUnits: 0,
            totalUnits: 0,
          ),
        ),
      ),
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, isNull);
  });
}

void _noop() {}
