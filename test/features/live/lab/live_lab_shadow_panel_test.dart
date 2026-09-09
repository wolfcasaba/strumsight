// E14-R23 / E14-R26 — the Lab-visible shadow report.
//
// RED before this round: `LiveLabState` had no `shadow` field and the panel
// had no shadow section. What these cells PIN:
//   1. a build with both gates closed says so, instead of rendering an
//      empty report that reads like a zero result;
//   2. a chord-band failure is shown as LOCALIZED copy — the raw
//      `FallbackReason` enum name never reaches a reader;
//   3. an empty comparison window shows "nothing comparable", never 0%.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/recognition_rollout_stage.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_recorder.dart';
import 'package:strumsight/features/live/data/shadow/shadow_metrics.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_mode.dart';
import 'package:strumsight/features/live/model/recognition_runtime_info.dart';
import 'package:strumsight/features/live/providers/live_lab_provider.dart';
import 'package:strumsight/features/live/widgets/live_lab_panel.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// A Lab controller parked in a fixed state — the panel is the unit here,
/// not the capture pipeline.
class _FixedLab extends LiveLabController {
  _FixedLab(this._state);

  final LiveLabState _state;

  @override
  LiveLabState build() => _state;
}

Future<AppLocalizations> _pump(WidgetTester tester, LiveLabState state) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [liveLabProvider.overrideWith(() => _FixedLab(state))],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return const SingleChildScrollView(child: LiveLabPanel());
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

RecognitionShadowSnapshot _snapshot({
  required bool strumEnabled,
  required bool chordEnabled,
  StrumShadowAggregate strum = StrumShadowAggregate.empty,
  ChordShadowAggregate? chord,
  FallbackReason? chordFallbackReason,
}) => RecognitionShadowSnapshot(
  mode: RecognitionMode.free,
  strumShadowEnabled: strumEnabled,
  chordShadowEnabled: chordEnabled,
  strumStage: strumEnabled
      ? RecognitionRolloutStage.shadow
      : RecognitionRolloutStage.off,
  chordStage: chordEnabled
      ? RecognitionRolloutStage.shadow
      : RecognitionRolloutStage.off,
  chordFallbackReason: chordFallbackReason,
  strum: strum,
  chord: chord ?? ChordShadowAggregate.empty(),
  strumSamples: const [],
  chordSamples: const [],
  ringCapacity: 16,
  droppedStrumSamples: 0,
  droppedChordSamples: 0,
);

void main() {
  testWidgets('no shadow snapshot renders no shadow section', (tester) async {
    final l10n = await _pump(tester, LiveLabState.initial);
    expect(find.text(l10n.liveLabShadowTitle), findsNothing);
  });

  testWidgets('both gates closed says so, and never shows a rate', (
    tester,
  ) async {
    final l10n = await _pump(
      tester,
      LiveLabState(
        shadow: RecognitionShadowSnapshot.disabled(mode: RecognitionMode.free),
      ),
    );
    expect(find.text(l10n.liveLabShadowTitle), findsOneWidget);
    expect(find.text(l10n.liveLabShadowOff), findsOneWidget);
    expect(find.text(l10n.liveLabShadowNeverShown), findsOneWidget);
  });

  testWidgets('an empty strum window says "nothing comparable", not 0%', (
    tester,
  ) async {
    final l10n = await _pump(
      tester,
      LiveLabState(
        shadow: _snapshot(strumEnabled: true, chordEnabled: false),
      ),
    );
    expect(find.text(l10n.liveLabShadowStrumNoData), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('a populated strum window shows the real fraction', (
    tester,
  ) async {
    final l10n = await _pump(
      tester,
      LiveLabState(
        shadow: _snapshot(
          strumEnabled: true,
          chordEnabled: false,
          strum: const StrumShadowAggregate(
            observedFrames: 40,
            candidateVerdicts: 6,
            comparedVerdicts: 4,
            agreed: 3,
            disagreed: 1,
            candidateAbstained: 2,
            productionAbstained: 0,
            bothAbstained: 0,
            candidateUnavailableFrames: 0,
            latencyHistogram: <ShadowLatencyBucket, int>{},
          ),
        ),
      ),
    );
    expect(find.text(l10n.liveLabShadowStrumAgreement(3, 4)), findsOneWidget);
    expect(find.text(l10n.liveLabShadowStrumAbstained(2, 6)), findsOneWidget);
  });

  testWidgets('a chord-band failure shows localized copy, not the enum', (
    tester,
  ) async {
    final l10n = await _pump(
      tester,
      LiveLabState(
        shadow: _snapshot(
          strumEnabled: false,
          chordEnabled: true,
          chordFallbackReason: FallbackReason.parseFailed,
        ),
      ),
    );
    expect(
      find.text(l10n.liveLabShadowChordFallbackParse),
      findsOneWidget,
    );
    expect(
      find.textContaining('parseFailed'),
      findsNothing,
      reason: 'a raw enum name must never reach a reader',
    );
  });
}
