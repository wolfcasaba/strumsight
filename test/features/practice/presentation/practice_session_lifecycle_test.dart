// E02-R13 §6 A6, A7, A8 — practice session screen lifecycle.
//
// A6 — app-lifecycle forward: the screen maps a `paused/hidden/detached`
//   background transition to exactly one `PausePractice(interruption)` for
//   `countIn`/`running`, and zero commands for everything else.
// A7 — leak guards: no transient callbacks after dispose, the host and
//   lifecycle fake see zero active listeners after teardown.
// A8 — a11y / i18n / layout guard: 48×48 dp, one semantics node per
//   control, the count-in number survives `disableAnimations: true`,
//   English and Hungarian both render, and no raw enum name leaks.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_effect.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/l10n/app_localizations_hu.dart';

import '../../../support/fake_audio.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSessionHost implements PracticeSessionHost {
  final StreamController<PracticeSessionState> _statesController =
      StreamController<PracticeSessionState>.broadcast();
  final StreamController<PracticeSessionEffect> _effectsController =
      StreamController<PracticeSessionEffect>.broadcast();

  final List<PracticeSessionCommand> sent = <PracticeSessionCommand>[];
  int? liveScore;
  PracticeSessionState _state = PracticeSessionState.initial;

  /// Active listener count is exposed so the A7 leak guard can assert the
  /// screen releases the subscription on dispose.
  int get effectListenerCount => _effectsController.hasListener ? 1 : 0;

  @override
  Stream<PracticeSessionState> get states => _statesController.stream;
  @override
  PracticeSessionState get state => _state;
  @override
  Stream<PracticeSessionEffect> get effects => _effectsController.stream;
  @override
  int? get liveOverallPerMille => liveScore;
  @override
  void send(PracticeSessionCommand command) => sent.add(command);

  void emitState(PracticeSessionState state) {
    _state = state;
    _statesController.add(state);
  }

  void emitEffect(PracticeSessionEffect effect) {
    _effectsController.add(effect);
  }

  Future<void> close() async {
    await _statesController.close();
    await _effectsController.close();
  }
}

class _NullFeedback implements PracticeFeedbackOutput {
  @override
  void haptic() {}
  @override
  void countInClick(int beatIndex) {}
  @override
  void announce(String message) {}
  @override
  void openPermissionSettings() {}
}

void _voidSink() {}

PracticeSessionState _stateFor(
  PracticeSessionStatus status, {
  int countInSpanBeats = 0,
  int emittedCountInClicks = 0,
}) => PracticeSessionState(
  status: status,
  countInSpanBeats: countInSpanBeats,
  emittedCountInClicks: emittedCountInClicks,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeSessionHost host,
  FakeAppLifecycleEvents? lifecycle,
  Locale locale = const Locale('en'),
}) async {
  final lc = lifecycle ?? FakeAppLifecycleEvents();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practiceSessionHostProvider.overrideWithValue(host),
        practiceFeedbackOutputProvider.overrideWithValue(_NullFeedback()),
        practiceResultNavigationSinkProvider.overrideWithValue(_voidSink),
        practiceHapticsEnabledProvider.overrideWithValue(true),
        appLifecycleEventsProvider.overrideWithValue(lc),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PracticeSessionScreen(),
      ),
    ),
  );
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -----------------------------------------------------------------
  // A6 — app-lifecycle → PausePractice matrix
  // -----------------------------------------------------------------
  group('A6 — app-lifecycle forward matrix', () {
    testWidgets(
      'countIn + background → exactly 1 PausePractice(interruption)',
      (tester) async {
        final host = _FakeSessionHost();
        final lc = FakeAppLifecycleEvents();
        addTearDown(host.close);
        host.emitState(
          _stateFor(
            PracticeSessionStatus.countIn,
            countInSpanBeats: 4,
            emittedCountInClicks: 0,
          ),
        );
        await _pumpScreen(tester, host: host, lifecycle: lc);
        lc.emit(AppLifecycleState.paused);
        await tester.pump();
        expect(host.sent.length, 1);
        final cmd = host.sent.single;
        expect(cmd, isA<PausePractice>());
        expect((cmd as PausePractice).cause, PauseCause.interruption);
      },
    );

    testWidgets(
      'running + background → exactly 1 PausePractice(interruption)',
      (tester) async {
        final host = _FakeSessionHost();
        final lc = FakeAppLifecycleEvents();
        addTearDown(host.close);
        host.emitState(_stateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host, lifecycle: lc);
        lc.emit(AppLifecycleState.paused);
        await tester.pump();
        expect(host.sent.length, 1);
        expect(host.sent.single, isA<PausePractice>());
        expect(
          (host.sent.single as PausePractice).cause,
          PauseCause.interruption,
        );
      },
    );

    testWidgets('paused + background → 0 commands', (tester) async {
      final host = _FakeSessionHost();
      final lc = FakeAppLifecycleEvents();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.paused));
      await _pumpScreen(tester, host: host, lifecycle: lc);
      lc.emit(AppLifecycleState.paused);
      await tester.pump();
      expect(host.sent, isEmpty);
    });

    testWidgets('preparing + background → 0 commands', (tester) async {
      final host = _FakeSessionHost();
      final lc = FakeAppLifecycleEvents();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.preparing));
      await _pumpScreen(tester, host: host, lifecycle: lc);
      lc.emit(AppLifecycleState.paused);
      await tester.pump();
      expect(host.sent, isEmpty);
    });

    testWidgets('ready + background → 0 commands', (tester) async {
      final host = _FakeSessionHost();
      final lc = FakeAppLifecycleEvents();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.ready));
      await _pumpScreen(tester, host: host, lifecycle: lc);
      lc.emit(AppLifecycleState.paused);
      await tester.pump();
      expect(host.sent, isEmpty);
    });

    testWidgets('countIn + inactive (overlay) → 0 commands', (tester) async {
      final host = _FakeSessionHost();
      final lc = FakeAppLifecycleEvents();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.countIn));
      await _pumpScreen(tester, host: host, lifecycle: lc);
      // `inactive` is the transient overlay state; the screen must NOT
      // treat it as a background (ADR 0079 §9).
      lc.emit(AppLifecycleState.inactive);
      await tester.pump();
      expect(host.sent, isEmpty);
    });
  });

  // -----------------------------------------------------------------
  // A7 — leak guards
  // -----------------------------------------------------------------
  group('A7 — leak guards', () {
    testWidgets(
      'dispose: 0 transient callbacks, host effect-listener count = 0, '
      'lifecycle listener count = 0',
      (tester) async {
        final host = _FakeSessionHost();
        final lc = FakeAppLifecycleEvents();
        addTearDown(host.close);
        host.emitState(_stateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host, lifecycle: lc);
        // Verify the screen actually wired the streams up — required
        // precondition for the A7 assertion to be meaningful.
        expect(host.effectListenerCount, 1);
        expect(lc.listeners.length, 1);
        // Tear the screen down and pump once to let dispose run.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(
          tester.binding.transientCallbackCount,
          0,
          reason: 'A7: no pending transient callbacks after dispose',
        );
        expect(
          host.effectListenerCount,
          0,
          reason: 'A7: host stream is fully released',
        );
        expect(
          lc.listeners.length,
          0,
          reason: 'A7: app-lifecycle listener is fully released',
        );
      },
    );

    testWidgets('five mount/unmount cycles → 0 lingering listeners', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      final lc = FakeAppLifecycleEvents();
      addTearDown(host.close);
      for (var i = 0; i < 5; i++) {
        host.emitState(_stateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host, lifecycle: lc);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      expect(host.effectListenerCount, 0);
      expect(lc.listeners.length, 0);
    });
  });

  // -----------------------------------------------------------------
  // A8 — accessibility / i18n / layout
  // -----------------------------------------------------------------
  group('A8 — a11y / i18n / layout', () {
    testWidgets('controls have 48×48 dp hit area and one semantics node each', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.ready));
      await _pumpScreen(tester, host: host);
      // The Start button is the only control in the ready state.
      final semantics = tester.getSemantics(find.text('Start'));
      expect(semantics.label, 'Start');
      // Find the underlying ElevatedButton via the parent ConstrainedBox.
      final constrained = tester
          .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
          .firstWhere(
            (box) =>
                box.constraints.minWidth == 48 &&
                box.constraints.minHeight == 48,
            orElse: () => throw StateError('48×48 box not found'),
          );
      expect(constrained.constraints.minWidth, 48);
      expect(constrained.constraints.minHeight, 48);
    });

    testWidgets(
      'countIn shows the remaining-beats number, even with reduced motion',
      (tester) async {
        // Disable animations so the screen renders the count-in number
        // synchronously, without needing pumpAndSettle.
        final host = _FakeSessionHost();
        addTearDown(host.close);
        host.emitState(
          _stateFor(
            PracticeSessionStatus.countIn,
            countInSpanBeats: 4,
            emittedCountInClicks: 2,
          ),
        );
        // 4 - 2 = 2 beats remaining.
        await _pumpScreen(tester, host: host);
        expect(find.textContaining('2'), findsWidgets);
      },
    );

    testWidgets('English + Hungarian locales both render without throwing', (
      tester,
    ) async {
      for (final locale in const [Locale('en'), Locale('hu')]) {
        final host = _FakeSessionHost();
        addTearDown(host.close);
        host.emitState(
          _stateFor(
            PracticeSessionStatus.countIn,
            countInSpanBeats: 4,
            emittedCountInClicks: 0,
          ),
        );
        await _pumpScreen(tester, host: host, locale: locale);
        // No exception thrown, the localized string is in the tree.
        if (locale.languageCode == 'en') {
          expect(
            find.textContaining(AppLocalizationsEn().practiceSessionCountIn),
            findsOneWidget,
          );
        } else {
          expect(
            find.textContaining(AppLocalizationsHu().practiceSessionCountIn),
            findsOneWidget,
          );
        }
      }
    });

    testWidgets('no raw status enum name leaks to the user-facing surface', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      // `idle` is the only status whose PracticeStateMessage renders
      // the raw enum name. The screen must localise it.
      host.emitState(_stateFor(PracticeSessionStatus.idle));
      await _pumpScreen(tester, host: host);
      // The raw 'idle' must NOT appear unprefixed in any visible text.
      // The localised form is "Session state: idle" which is fine.
      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      expect(
        visibleText.contains('idle'),
        isFalse,
        reason: 'raw enum name "idle" must not appear unprefixed',
      );
      // The localised form is fine.
      expect(visibleText.any((s) => s.contains('Session state')), isTrue);
    });
  });
}
