import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/analyze/engine/clip_recorder.dart';
import 'package:strumsight/features/analyze/providers/analyze_providers.dart';
import 'package:strumsight/features/analyze/screens/analyze_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio.dart';

/// Round 99 — Analyze mic-error parity (Live got it round 13, Tuner round
/// 68): a mic START failure (busy / platform error — distinct from a DENIED
/// permission) must surface a Retry UI, not throw out of the button handler
/// and leave the screen idling silently. E01-R09: the failing mic is now an
/// injected capture that throws — deterministic, no platform channel needed.
class _MicErrorStub extends AnalyzeController {
  @override
  AnalyzeState build() => const AnalyzeState(phase: AnalyzePhase.micError);
}

class _MicDeniedStub extends AnalyzeController {
  @override
  AnalyzeState build() => const AnalyzeState(phase: AnalyzePhase.micDenied);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a mic start failure surfaces as failed — no throw, no stuck '
      'recording flag', () async {
    final recorder = ClipRecorder(
      mic: fakeMicCapture(
        owner: AudioOwner.analyzeRecorder,
        capture: FakeAudioCapture(failWith: StateError('mic busy')),
      ),
    );
    final result = await recorder.start();
    expect(result, MicStart.failed);
    expect(
      recorder.isRecording,
      isFalse,
      reason: 'a failed start must not leave the recorder "recording"',
    );
    // Retrying still reports failure honestly (not a stuck "already on").
    expect(await recorder.start(), MicStart.failed);
  });

  testWidgets('the micError phase shows the retry UI, not the permission '
      'copy', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [analyzeControllerProvider.overrideWith(_MicErrorStub.new)],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AnalyzeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Couldn't start the microphone"),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.textContaining('needs the microphone'),
      findsNothing,
      reason: 'a busy mic is not a permission problem',
    );
  });

  testWidgets(
    'the micDenied phase shows the design-system empty state with the '
    'open-settings action',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyzeControllerProvider.overrideWith(_MicDeniedStub.new),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AnalyzeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SsEmptyState), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    },
  );

  group('§0.0.A/R11 — textScaler 2.0, en/hu, no overflow', () {
    for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
      testWidgets('AnalyzeScreen idle — ${locale.languageCode}', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: SsLightTheme.data(),
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: AnalyzeScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('AnalyzeScreen micDenied — ${locale.languageCode}', (
        tester,
      ) async {
        // m6 — the idle phase already had 2.0 coverage; micDenied (a
        // different SsEmptyState instance, §10.5 sibling-instance rule /
        // L559) did not.
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              analyzeControllerProvider.overrideWith(_MicDeniedStub.new),
            ],
            child: MaterialApp(
              theme: SsLightTheme.data(),
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: AnalyzeScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
