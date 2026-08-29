// E13-R22 — A6: the Speed Builder result shows the STABLE best tempo
// (`SpeedBuilderState.highestStableTempo`, engine-confirmed via
// `requiredConsecutivePasses` in a row), never a lucky one-off peak
// attempt.
//
// Also guards the E13-R22 javító kör fix for review MAJOR-1: with no
// [SpeedBuilderState] to drive, the screen must show the honest
// "unavailable" state, never a Start/Record path that fabricates
// measurements for the engine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_policy.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_state.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/speed_builder_engine.dart';
import 'package:strumsight/features/practice/presentation/screens/speed_builder_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

AppLocalizations l10n() => AppLocalizationsEn();

const _engine = SpeedBuilderEngine();

PracticeAttemptResult _attempt({
  required int index,
  required double bpm,
  required bool pass,
}) {
  return PracticeAttemptResult(
    index: index,
    tempo: Tempo(bpm),
    metrics: PracticeMetrics(
      completion: MetricAvailable(pass ? 0.98 : 0.5),
      rhythm: MetricAvailable(pass ? 0.9 : 0.6),
      direction: const MetricNotApplicable(),
      chord: const MetricNotApplicable(),
      overall: MetricAvailable(pass ? 0.9 : 0.6),
      totalTargets: 8,
      resolvedTargets: pass ? 8 : 4,
      maxCombo: pass ? 8 : 2,
      scorePoints: pass ? 800 : 300,
      meanAbsoluteOffset: const Duration(milliseconds: 20),
      timingBias: Duration.zero,
    ),
    verdicts: const <PracticeVerdict>[],
    outcome: pass
        ? PracticeAttemptOutcome.passed
        : PracticeAttemptOutcome.failed,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const policy = SpeedBuilderPolicy(
    startBpm: Tempo(100),
    targetBpm: Tempo(200),
    stepBpm: 10,
  );

  Future<void> pump(WidgetTester tester, {SpeedBuilderState? initialState}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SpeedBuilderScreen(policy: policy, initialState: initialState),
        ),
      );

  group('A6 — stable tempo, not the peak attempt', () {
    testWidgets(
      'a one-off pass at a HIGH tempo never becomes "highest" — only a '
      'tempo reached with the required consecutive passes does',
      (tester) async {
        // 150 BPM passes exactly once (never consecutive) — must NOT be
        // reported as stable. 110 BPM passes twice in a row — IS stable,
        // even though it is lower than the 150 BPM one-off.
        var state = SpeedBuilderState.initial(policy);
        state = _engine.record(state, _attempt(index: 0, bpm: 150, pass: true));
        state = _engine.record(state, _attempt(index: 1, bpm: 110, pass: true));
        state = _engine.record(state, _attempt(index: 2, bpm: 110, pass: true));
        state = _engine.record(state, _attempt(index: 3, bpm: 90, pass: false));
        state = _engine.finish(state);

        expect(state.highestStableTempo, const Tempo(110));

        await pump(tester, initialState: state);
        await tester.pumpAndSettle();

        expect(
          find.text(l10n().speedBuilderHighestStable('110 BPM')),
          findsOneWidget,
        );
        // The one-off 150 BPM peak is never rendered as a "highest" value
        // anywhere on the result layout.
        expect(find.textContaining('150'), findsNothing);
        expect(find.text(l10n().speedBuilderResultAttempts(4)), findsOneWidget);
      },
    );

    testWidgets(
      'no attempt ever reached the required consecutive-pass streak → '
      '"not yet", not a fabricated value',
      (tester) async {
        var state = SpeedBuilderState.initial(policy);
        state = _engine.record(state, _attempt(index: 0, bpm: 150, pass: true));
        state = _engine.record(state, _attempt(index: 1, bpm: 90, pass: false));
        state = _engine.finish(state);

        expect(state.highestStableTempo, isNull);

        await pump(tester, initialState: state);
        await tester.pumpAndSettle();

        expect(
          find.text(
            l10n().speedBuilderHighestStable(l10n().speedBuilderNoStableBpm),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group(
    'no live session → no fabricated measurement (E13-R22 review MAJOR-1)',
    () {
      testWidgets(
        'with no initialState the screen never offers a Start/Record path — '
        'it states plainly that live measurement is unavailable',
        (tester) async {
          await pump(tester);
          await tester.pumpAndSettle();

          // The regression this cell guards against: a "Start" CTA that only
          // ever leads to a screen minting fabricated PracticeAttemptResults
          // for the real engine. Neither the entry CTA nor the record
          // affordances it used to unlock may appear.
          expect(find.text(l10n().speedBuilderStartCta), findsNothing);
          expect(find.text(l10n().speedBuilderRecordPass), findsNothing);
          expect(find.text(l10n().speedBuilderRecordFail), findsNothing);

          // The honest, ADR 0277-style unavailable state is shown instead.
          expect(
            find.text(l10n().speedBuilderUnavailableTitle),
            findsOneWidget,
          );

          // No result is ever produced without a real, engine-confirmed
          // measurement.
          expect(find.text(l10n().speedBuilderResultTitle), findsNothing);
          expect(find.textContaining('BPM'), findsNothing);
        },
      );
    },
  );
}
