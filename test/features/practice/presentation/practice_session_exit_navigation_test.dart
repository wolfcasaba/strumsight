// A2a (1) — the session screen's exit must never pop the LAST go_router page.
//
// `practice_setup_screen.dart` reaches the session with
// `context.go(AppRoutes.practiceSession)`, and `practiceSession` is a
// top-level `GoRoute` in `app_router.dart`. `go` REPLACES the stack, so the
// session screen is then the only page on it. The pre-fix `_requestExit`
// called `Navigator.of(context).pop()` unconditionally, which pops that last
// page — an assertion in debug, a blank router in release.
//
// The screen must fall back to the Practice hub when there is nothing to pop,
// and must keep the plain-`Navigator` contract when no GoRouter is above it
// (the way `practice_session_screen_test.dart` mounts it).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_effect.dart';
import 'package:strumsight/features/practice/application/practice_strum_feedback.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../support/fake_audio.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();

/// Minimal [PracticeSessionHost] — only what the exit path reads.
class _FakeSessionHost implements PracticeSessionHost {
  final StreamController<PracticeSessionState> _statesController =
      StreamController<PracticeSessionState>.broadcast();
  final StreamController<PracticeSessionEffect> _effectsController =
      StreamController<PracticeSessionEffect>.broadcast();

  final List<PracticeSessionCommand> sent = <PracticeSessionCommand>[];
  PracticeSessionState _state = PracticeSessionState.initial;

  @override
  Stream<PracticeSessionState> get states => _statesController.stream;

  @override
  PracticeSessionState get state => _state;

  @override
  Stream<PracticeSessionEffect> get effects => _effectsController.stream;

  @override
  Stream<PracticeStrumFeedback> get strumFeedback => const Stream.empty();

  @override
  int? get liveOverallPerMille => null;

  @override
  void send(PracticeSessionCommand command) => sent.add(command);

  void emitState(PracticeSessionState state) {
    _state = state;
    _statesController.add(state);
  }

  Future<void> close() async {
    await _statesController.close();
    await _effectsController.close();
  }
}

class _SilentFeedback implements PracticeFeedbackOutput {
  @override
  void haptic() {}
  @override
  void countInClick(int beatIndex) {}
  @override
  void announce(String message) {}
  @override
  void openPermissionSettings() {}
}

const _hubMarker = 'practice-hub-landing';

List<Override> _overrides(_FakeSessionHost host) => [
  practiceSessionHostProvider.overrideWithValue(host),
  practiceFeedbackOutputProvider.overrideWithValue(_SilentFeedback()),
  practiceResultNavigationSinkProvider.overrideWithValue(() {}),
  practiceHapticsEnabledProvider.overrideWithValue(false),
  appLifecycleEventsProvider.overrideWithValue(FakeAppLifecycleEvents()),
];

/// The compact portrait phone surface the other session-screen tests pin —
/// `SsStageScaffold` picks its layout from the viewport (ADR 0276).
void _pinPhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Mounts the session screen as the router's ONLY page — exactly the stack
/// `context.go(AppRoutes.practiceSession)` from Setup leaves behind.
Future<GoRouter> _pumpSessionUnderRouter(
  WidgetTester tester,
  _FakeSessionHost host,
) async {
  _pinPhoneSurface(tester);
  final router = GoRouter(
    initialLocation: AppRoutes.practiceSession,
    routes: [
      GoRoute(
        path: AppRoutes.practiceSession,
        builder: (_, _) => const PracticeSessionScreen(),
      ),
      GoRoute(
        path: AppRoutes.practiceHub,
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text(_hubMarker))),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(host),
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  return router;
}

Future<void> _drainExit(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'exit on a 1-deep go_router stack lands on the Practice hub instead of '
    'popping the last page',
    (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(
        const PracticeSessionState(status: PracticeSessionStatus.ready),
      );
      final router = await _pumpSessionUnderRouter(tester, host);

      expect(
        router.state.uri.path,
        AppRoutes.practiceSession,
        reason: 'precondition: the session is the only page on the stack',
      );

      await tester.tap(find.text(l10nEn().practiceSessionExit));
      await _drainExit(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: 'popping the last go_router page must not be attempted',
      );
      expect(router.state.uri.path, AppRoutes.practiceHub);
      expect(find.text(_hubMarker), findsOneWidget);
      expect(host.sent.single, isA<CancelPractice>());
    },
  );

  testWidgets('exit still pops when the router CAN pop (pushed session)', (
    tester,
  ) async {
    final host = _FakeSessionHost();
    addTearDown(host.close);
    host.emitState(
      const PracticeSessionState(status: PracticeSessionStatus.ready),
    );
    _pinPhoneSurface(tester);

    final router = GoRouter(
      initialLocation: AppRoutes.practiceHub,
      routes: [
        GoRoute(
          path: AppRoutes.practiceHub,
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text(_hubMarker))),
        ),
        GoRoute(
          path: AppRoutes.practiceSession,
          builder: (_, _) => const PracticeSessionScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(host),
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    router.push(AppRoutes.practiceSession);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.practiceSession);

    await tester.tap(find.text(l10nEn().practiceSessionExit));
    await _drainExit(tester);

    expect(tester.takeException(), isNull);
    expect(router.state.uri.path, AppRoutes.practiceHub);
    expect(find.text(_hubMarker), findsOneWidget);
  });

  testWidgets('without a GoRouter above it the screen keeps popping the '
      'plain Navigator', (tester) async {
    final host = _FakeSessionHost();
    addTearDown(host.close);
    host.emitState(
      const PracticeSessionState(status: PracticeSessionStatus.ready),
    );
    _pinPhoneSurface(tester);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(host),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Center(child: Text(_hubMarker))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const PracticeSessionScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10nEn().practiceSessionExit), findsOneWidget);

    await tester.tap(find.text(l10nEn().practiceSessionExit));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_hubMarker), findsOneWidget);
    expect(find.text(l10nEn().practiceSessionExit), findsNothing);
  });
}
