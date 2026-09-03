// E04-R22 §6 — Tutor Data screen matrix.
//
// RED-first. Compiles only after `tutor_data_screen.dart`,
// `tutor_privacy_providers.dart` and the screen-local notifiers land with
// the exact public names referenced here. Cells:
//   * R22-F2 — delete-all confirmation button must call
//     `deleteAllAiData()`; the displayed scope-list must match
//     `StorageKeys.tutorAiData` exactly (mirrors R22-F1 in privacy).
//   * R22-DA3 — the redacted memory export calls `exportRedacted()` and
//     surfaces the literal '[redacted]' marker.
//   * R22-DA4 — conversation list shows items from the conversation
//     repository and delete removes them.
//   * R22-DA5 — memory-fact edit/delete round-trip through the repo.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/components/feedback/ss_failure_state.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_conversation.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_memory_fact.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/domain/repositories/tutor_conversation_repository.dart';
import 'package:strumsight/features/ai_tutor/domain/repositories/tutor_memory_repository.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_data_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/l10n/app_localizations_hu.dart';

import '../../../support/preference_store.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();
AppLocalizations l10nHu() => AppLocalizationsHu();

AppConfig _config({bool aiTutorEnabled = true}) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    aiTutorEnabled: aiTutorEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

class _FakeMemoryRepository implements TutorMemoryRepository {
  _FakeMemoryRepository({
    List<TutorMemoryFact> facts = const <TutorMemoryFact>[],
  }) {
    _facts.addAll(facts);
  }

  final List<TutorMemoryFact> _facts = <TutorMemoryFact>[];
  int deleteAllCalls = 0;
  int exportRedactedCalls = 0;
  String? lastExportPayload;
  final List<String> deletedFactIds = <String>[];
  final List<TutorMemoryFact> updatedFacts = <TutorMemoryFact>[];
  bool rejectSensitiveUpdates = false;
  int listCalls = 0;

  /// R22-DA8 (§0.0.A real-violation probe): when true, `list()` throws
  /// instead of returning an `AppResult`, exercising the
  /// `memoryFacts.when(error: ...)` branch for real (the provider only
  /// reaches `error` on a genuine throw — a returned `Failure` is
  /// swallowed to an empty list, see `tutor_privacy_providers.dart`).
  bool throwOnList = false;

  @override
  Future<AppResult<List<TutorMemoryFact>>> list() async {
    listCalls++;
    if (throwOnList) {
      throw StateError('memory repository unavailable');
    }
    return Success<List<TutorMemoryFact>>(
      List<TutorMemoryFact>.unmodifiable(_facts),
    );
  }

  @override
  Future<AppResult<TutorMemoryFact>> saveCandidate(
    TutorMemoryCandidate candidate,
  ) async => Success<TutorMemoryFact>(
    TutorMemoryFact(
      id: candidate.id,
      content: candidate.content,
      conversationId: candidate.conversationId,
      messageId: candidate.messageId,
      createdAt: candidate.createdAt,
      updatedAt: candidate.createdAt,
      expiresAt: candidate.expiresAt,
    ),
  );

  @override
  Future<AppResult<void>> update(TutorMemoryFact fact) async {
    if (rejectSensitiveUpdates &&
        fact.content.toLowerCase().contains('password')) {
      return const Failure<void>(
        ValidationFailure(code: FailureCode.validationInvalidInput),
      );
    }
    final index = _facts.indexWhere((item) => item.id == fact.id);
    if (index == -1) {
      return const Failure<void>(
        ValidationFailure(code: FailureCode.validationInvalidInput),
      );
    }
    _facts[index] = fact;
    updatedFacts.add(fact);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> delete(String factId) async {
    _facts.removeWhere((item) => item.id == factId);
    deletedFactIds.add(factId);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> purgeExpired(DateTime now) async =>
      const Success<void>(null);

  @override
  Future<AppResult<String>> exportRedacted() async {
    exportRedactedCalls++;
    lastExportPayload =
        '{"schemaVersion":1,"facts":[{"id":"x","content":"[redacted]"}]}';
    return Success<String>(lastExportPayload!);
  }

  @override
  Future<AppResult<void>> deleteAllAiData() async {
    deleteAllCalls++;
    _facts.clear();
    return const Success<void>(null);
  }
}

class _FakeConversationRepository implements TutorConversationRepository {
  _FakeConversationRepository({
    List<TutorConversation> conversations = const <TutorConversation>[],
  }) {
    _conversations.addAll(conversations);
  }

  final List<TutorConversation> _conversations = <TutorConversation>[];
  final List<TutorConversationId> deletedIds = <TutorConversationId>[];

  @override
  Future<AppResult<void>> save(TutorConversation conversation) async {
    _conversations.add(conversation);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<TutorConversation?>> get(TutorConversationId id) async =>
      Success<TutorConversation?>(
        _conversations.cast<TutorConversation?>().firstWhere(
          (item) => item?.id == id,
          orElse: () => null,
        ),
      );

  @override
  Future<AppResult<TutorConversationPage>> list({
    int offset = 0,
    int limit = 20,
  }) async {
    final end = (offset + limit).clamp(0, _conversations.length);
    final page = offset >= _conversations.length
        ? const <TutorConversation>[]
        : _conversations.sublist(offset, end);
    return Success<TutorConversationPage>(
      TutorConversationPage(
        items: page,
        offset: offset,
        total: _conversations.length,
      ),
    );
  }

  @override
  Future<AppResult<TutorConversationSummary?>> summary(
    TutorConversationId id,
  ) async {
    for (final c in _conversations) {
      if (c.id == id) {
        return Success<TutorConversationSummary?>(
          TutorConversationSummary(
            conversationId: c.id,
            messageCount: c.messages.length,
            messageProvenance: const <TutorMessageProvenance>[],
          ),
        );
      }
    }
    return const Success<TutorConversationSummary?>(null);
  }

  @override
  Future<AppResult<void>> delete(TutorConversationId id) async {
    _conversations.removeWhere((item) => item.id == id);
    deletedIds.add(id);
    return const Success<void>(null);
  }
}

TutorMemoryFact _fact(String id, String content) => TutorMemoryFact(
  id: id,
  content: content,
  conversationId: TutorConversationId('c-1'),
  messageId: TutorMessageId('m-1'),
  createdAt: DateTime.utc(2026, 8, 5),
  updatedAt: DateTime.utc(2026, 8, 5),
);

TutorConversation _conversation(TutorConversationId id) => TutorConversation(
  schemaVersion: 1,
  id: id,
  createdAt: DateTime.utc(2026, 8, 5),
  updatedAt: DateTime.utc(2026, 8, 5),
  locale: 'en',
  status: TutorConversationStatus.active,
  messages: <TutorMessage>[],
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  _FakeMemoryRepository? memory,
  _FakeConversationRepository? conversations,
  Locale locale = const Locale('en'),
}) async {
  final memRepo = memory ?? _FakeMemoryRepository();
  final convoRepo = conversations ?? _FakeConversationRepository();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      appConfigProvider.overrideWithValue(_config()),
      tutorMemoryRepositoryProvider.overrideWithValue(memRepo),
      tutorConversationRepositoryProvider.overrideWithValue(convoRepo),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SsLightTheme.data(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TutorDataScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -----------------------------------------------------------------
  // Delete-all — falszifikációs cella (R22-F2). A scope-lista PONTOSAN
  // a `StorageKeys.tutorAiData` három kulcsa + karanténjaik legyenek.
  // -----------------------------------------------------------------
  testWidgets(
    'R22-F2: delete-all scope list matches StorageKeys.tutorAiData exactly',
    (tester) async {
      await _pump(tester);
      final scopeList = find.byKey(const Key('tutorDataDeleteAllScopeList'));
      expect(scopeList, findsOneWidget);
      expect(
        find.descendant(of: scopeList, matching: find.byType(Padding)),
        findsNWidgets(StorageKeys.tutorAiData.length * 2),
        reason: 'scope rows must include every key and quarantine exactly once',
      );
      for (final key in StorageKeys.tutorAiData) {
        expect(find.text(key), findsOneWidget, reason: 'missing key $key');
      }
      for (final key in StorageKeys.tutorAiData) {
        final quarantine = StorageKeys.quarantineOf(key);
        expect(
          find.text(quarantine),
          findsOneWidget,
          reason: 'missing quarantine $quarantine',
        );
      }
      // Consent/profile/auth token must NOT be in the deleted list.
      expect(
        find.text('tutorConsent.profile'),
        findsNothing,
        reason: 'consent/profile must not be in the deleted list',
      );
      expect(
        find.text(StorageKeys.secureAuthToken),
        findsNothing,
        reason: 'auth token must not be in the deleted list',
      );
    },
  );

  testWidgets(
    'R22-DA2: confirming delete-all calls repository.deleteAllAiData exactly once',
    (tester) async {
      final memory = _FakeMemoryRepository();
      await _pump(tester, memory: memory);
      // The trigger button is at the bottom of the screen — scroll it
      // into view before tapping so the hit-test lands on it.
      await tester.scrollUntilVisible(
        find.byKey(const Key('tutorDataDeleteAllTrigger')),
        300,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.byKey(const Key('tutorDataDeleteAllTrigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tutorDataDeleteAllConfirm')));
      // Dialog pop + repo call + invalidate + snackbar — let it all flush.
      await tester.pumpAndSettle();
      expect(memory.deleteAllCalls, 1);
    },
  );

  testWidgets(
    'R22-DA3: redacted export calls repository.exportRedacted and surfaces the marker',
    (tester) async {
      final memory = _FakeMemoryRepository();
      await _pump(tester, memory: memory);
      await tester.tap(find.byKey(const Key('tutorDataExportRedacted')));
      await tester.pump();
      expect(memory.exportRedactedCalls, 1);
      // The literal redacted marker is shown somewhere on the data screen.
      expect(find.textContaining('[redacted]'), findsWidgets);
    },
  );

  testWidgets(
    'R22-DA4: conversation list shows items; delete removes the row',
    (tester) async {
      final id = TutorConversationId('c-1');
      final conversations = _FakeConversationRepository(
        conversations: [_conversation(id)],
      );
      await _pump(tester, conversations: conversations);
      expect(find.byType(TutorDataScreen), findsOneWidget);
      // The conversation id is rendered at least once (list tile + delete row).
      expect(find.text(id.value), findsWidgets);
      // Tap delete -> removed from the repo.
      await tester.tap(
        find.byKey(Key('tutorDataConversationDelete:${id.value}')),
      );
      await tester.pump();
      expect(conversations.deletedIds, contains(id));
    },
  );

  testWidgets(
    'R22-DA5: memory-fact delete calls repository.delete with the fact id',
    (tester) async {
      final memory = _FakeMemoryRepository(
        facts: [_fact('f-1', 'Prefers slow warm-ups.')],
      );
      await _pump(tester, memory: memory);
      expect(find.text('Prefers slow warm-ups.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tutorDataMemoryDelete:f-1')));
      await tester.pump();
      expect(memory.deletedFactIds, contains('f-1'));
    },
  );

  testWidgets(
    'R22-DA5b: editing a memory fact updates the repository with new content',
    (tester) async {
      final memory = _FakeMemoryRepository(
        facts: [_fact('f-1', 'Prefers slow warm-ups.')],
      );
      await _pump(tester, memory: memory);

      await tester.tap(find.byKey(const Key('tutorDataMemoryEdit:f-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('tutorDataMemoryEditField:f-1')),
        'Prefers gentle warm-ups.',
      );
      await tester.tap(find.byKey(const Key('tutorDataMemoryEditSave:f-1')));
      await tester.pumpAndSettle();

      expect(memory.updatedFacts, hasLength(1));
      expect(memory.updatedFacts.single.id, 'f-1');
      expect(memory.updatedFacts.single.content, 'Prefers gentle warm-ups.');
    },
  );

  testWidgets(
    'R22-DA5c: sensitive memory edit surfaces a localized validation error',
    (tester) async {
      final memory = _FakeMemoryRepository(
        facts: [_fact('f-2', 'Prefers slow warm-ups.')],
      )..rejectSensitiveUpdates = true;
      await _pump(tester, memory: memory);

      await tester.tap(find.byKey(const Key('tutorDataMemoryEdit:f-2')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('tutorDataMemoryEditField:f-2')),
        'My password is private.',
      );
      await tester.tap(find.byKey(const Key('tutorDataMemoryEditSave:f-2')));
      await tester.pumpAndSettle();

      expect(memory.updatedFacts, isEmpty);
      expect(find.text(l10nEn().tutorDataMemoryEditSensitive), findsOneWidget);
    },
  );

  testWidgets('R22-DA6: hu locale renders the Hungarian data copy', (
    tester,
  ) async {
    await _pump(tester, locale: const Locale('hu'));
    expect(find.text(l10nHu().tutorDataTitle), findsOneWidget);
  });

  testWidgets('R22-DA7: data screen exposes a screen-level semantics label', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      find.bySemanticsLabel(l10nEn().tutorDataScreenSemantics),
      findsOneWidget,
    );
  });

  // -------------------------------------------------------------------
  // E15-R09 §0.0.A/R6 + §6.1 real-violation probe: the memory-facts load
  // failure is a design-system `SsFailureState`, not raw `Text` — and its
  // retry action re-invokes the repository (`ref.invalidate`).
  // -------------------------------------------------------------------
  testWidgets(
    'R22-DA8: memory-facts load failure renders SsFailureState with a working retry',
    (tester) async {
      final memory = _FakeMemoryRepository()..throwOnList = true;
      await _pump(tester, memory: memory);
      expect(find.byType(SsFailureState), findsOneWidget);
      expect(memory.listCalls, 1);

      await tester.tap(find.byKey(const ValueKey('ss-failure-state-retry')));
      await tester.pump();
      expect(memory.listCalls, 2);
    },
  );
}
