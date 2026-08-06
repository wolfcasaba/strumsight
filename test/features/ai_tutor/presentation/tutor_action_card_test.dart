import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/action_confirmation_service.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_action_validator.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_action.dart';
import 'package:strumsight/features/ai_tutor/presentation/widgets/tutor_action_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations _l10n() => AppLocalizationsEn();

class _RecordingExecutor implements TutorActionExecutor {
  _RecordingExecutor({this.error});

  final Object? error;
  final List<TutorAction> actions = <TutorAction>[];

  @override
  Future<void> execute(TutorAction action) async {
    actions.add(action);
    final error = this.error;
    if (error != null) throw error;
  }
}

class _GateExecutor implements TutorActionExecutor {
  final List<TutorAction> actions = <TutorAction>[];
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> execute(TutorAction action) async {
    actions.add(action);
    await gate.future;
  }
}

final _now = DateTime.utc(2026, 8, 5, 10);

TutorActionValidationContext _context({
  DateTime? now,
  Set<TutorActionCapability> capabilities = const <TutorActionCapability>{
    TutorActionCapability.updateProfile,
    TutorActionCapability.savePlan,
    TutorActionCapability.launchPracticeSession,
    TutorActionCapability.launchSongRange,
  },
}) => TutorActionValidationContext(
  now: now ?? _now,
  availableCapabilities: capabilities,
  activeSessionIds: const <String>{},
  songRevisions: const <String, TutorActionRevisionToken>{},
);

TutorActionMetadata _metadata({
  TutorActionCapability capability = TutorActionCapability.updateProfile,
  String clientActionId = 'action-1',
  DateTime? expiresAt,
}) => TutorActionMetadata(
  source: TutorActionSource.modelSuggestion,
  expiresAt: expiresAt ?? _now.add(const Duration(hours: 1)),
  requiredCapability: capability,
  clientActionId: clientActionId,
);

TutorProfileUpdateAction _profileAction({
  String clientActionId = 'action-1',
  DateTime? expiresAt,
}) => TutorProfileUpdateAction(
  metadata: _metadata(clientActionId: clientActionId, expiresAt: expiresAt),
  changes: const <String, Object?>{
    'preferredTempo': 120,
    'displayName': '<script>alert(1)</script>',
  },
);

Future<void> _pump(
  WidgetTester tester, {
  required TutorActionProposal proposal,
  required _RecordingExecutor executor,
  TutorActionValidationContext Function()? contextProvider,
  double textScale = 1,
}) async {
  final service = ActionConfirmationService(executor: executor);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: TutorActionCard(
            proposal: proposal,
            confirmationService: service,
            validationContext: contextProvider ?? () => _context(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'action card shows exact preview fields and confirm executes typed action',
    (tester) async {
      final executor = _RecordingExecutor();
      final action = _profileAction();
      await _pump(tester, proposal: action, executor: executor);

      expect(
        find.textContaining(_l10n().aiTutorActionFieldPreferredTempo),
        findsOneWidget,
      );
      expect(find.textContaining('120'), findsOneWidget);
      expect(find.textContaining('<script>'), findsNothing);
      expect(
        find.text(_l10n().aiTutorActionConfirmationRequired),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('tutor-action-confirm')));
      await tester.pumpAndSettle();

      expect(executor.actions, hasLength(1));
      expect(identical(executor.actions.single, action), isTrue);
      expect(find.text(_l10n().aiTutorActionConfirmed), findsOneWidget);
    },
  );

  testWidgets('reject leaves the typed executor untouched', (tester) async {
    final executor = _RecordingExecutor();
    await _pump(tester, proposal: _profileAction(), executor: executor);

    await tester.tap(find.byKey(const ValueKey('tutor-action-reject')));
    await tester.pump();

    expect(find.text(_l10n().aiTutorActionRejected), findsOneWidget);
    expect(executor.actions, isEmpty);
  });

  testWidgets('stale proposal is visible and never reaches executor', (
    tester,
  ) async {
    final executor = _RecordingExecutor();
    final action = _profileAction(
      expiresAt: _now.add(const Duration(seconds: 1)),
    );
    var current = _now;
    await _pump(
      tester,
      proposal: action,
      executor: executor,
      contextProvider: () => _context(now: current),
    );

    current = _now.add(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('tutor-action-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(_l10n().aiTutorActionStale), findsOneWidget);
    expect(executor.actions, isEmpty);
  });

  testWidgets('double tap is idempotent while confirmation is in flight', (
    tester,
  ) async {
    final executor = _GateExecutor();
    final service = ActionConfirmationService(executor: executor);
    final action = _profileAction();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TutorActionCard(
            proposal: action,
            confirmationService: service,
            validationContext: _context,
          ),
        ),
      ),
    );
    await tester.pump();

    final confirm = find.byKey(const ValueKey('tutor-action-confirm'));
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(executor.actions, hasLength(1));

    executor.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(_l10n().aiTutorActionConfirmed), findsOneWidget);
  });

  testWidgets(
    'invalid action is blocked before a confirmation button appears',
    (tester) async {
      final executor = _RecordingExecutor();
      final invalid = TutorRawRouteActionProposal(
        metadata: _metadata(
          capability: TutorActionCapability.launchPracticeSession,
        ),
        route: '/settings',
      );
      await _pump(tester, proposal: invalid, executor: executor);

      expect(find.text(_l10n().aiTutorActionInvalid), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor-action-confirm')), findsNothing);
      expect(executor.actions, isEmpty);
    },
  );

  testWidgets('executor failure renders a retryable failed state', (
    tester,
  ) async {
    final executor = _RecordingExecutor(error: StateError('not persisted'));
    await _pump(tester, proposal: _profileAction(), executor: executor);

    await tester.tap(find.byKey(const ValueKey('tutor-action-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(_l10n().aiTutorActionFailed), findsOneWidget);
    expect(find.byKey(const ValueKey('tutor-action-retry')), findsOneWidget);
  });

  testWidgets('action semantics and large text remain available', (
    tester,
  ) async {
    final executor = _RecordingExecutor();
    await _pump(
      tester,
      proposal: _profileAction(),
      executor: executor,
      textScale: 3,
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label?.contains(
                  _l10n().aiTutorActionPreviewTitle(
                    _l10n().aiTutorActionProfileUpdate,
                  ),
                ) ??
                false),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
