import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/clip_recorder.dart';
import 'package:music_theory/features/analyze/providers/analyze_providers.dart';
import 'package:music_theory/features/analyze/screens/analyze_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 99 — Analyze mic-error parity (Live got it round 13, Tuner round
/// 68): a mic START failure (busy / platform error — distinct from a DENIED
/// permission) must surface a Retry UI, not throw out of the button handler
/// and leave the screen idling silently. The test environment's genuinely
/// missing audio channel IS the failing mic.
class _MicErrorStub extends AnalyzeController {
  @override
  AnalyzeState build() => const AnalyzeState(phase: AnalyzePhase.micError);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Plain test() + ensureInitialized (the round-68 engine-test pattern):
  // under testWidgets' FakeAsync the missing-plugin reply never gets pumped
  // and the await hangs; in a plain test it throws fast.
  test('a mic start failure surfaces as failed — no throw, no stuck '
      'recording flag', () async {
    final recorder = ClipRecorder();
    final result = await recorder.start();
    expect(result, MicStart.failed);
    expect(recorder.isRecording, isFalse,
        reason: 'a failed start must not leave the recorder "recording"');
    // Retrying still reports failure honestly (not a stuck "already on").
    expect(await recorder.start(), MicStart.failed);
  });

  testWidgets('the micError phase shows the retry UI, not the permission '
      'copy', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [analyzeControllerProvider.overrideWith(_MicErrorStub.new)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AnalyzeScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't start the microphone"),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('needs the microphone'), findsNothing,
        reason: 'a busy mic is not a permission problem');
  });
}
