// E13-R22 — A3 (corrupt record isolation) / A4 (offline availability).
//
// `LocalPracticeHistoryRepository` already isolates a single undecodable
// record at read time (`JsonCollectionStore`, pinned separately by
// `test/features/practice/data/practice_history_repository_test.dart`
// group A7). This file proves the NEW `PracticeHistoryScreen` survives that
// same mixed-corruption input end to end: the good records still render,
// nothing throws, and the screen never needed a network provider to do it
// (A4 — the repository is local storage only).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/practice/data/practice_history_serializer.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/practice/domain/repository/practice_history_repository.dart';
import 'package:strumsight/features/practice/data/local_practice_history_repository.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_history_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/preference_store.dart';

class _FailingHistoryRepository implements PracticeHistoryRepository {
  const _FailingHistoryRepository();

  @override
  Future<AppResult<List<PracticeHistoryEntry>>> load() async =>
      const AppResult.failure(StorageFailure(code: FailureCode.storageRead));

  @override
  Future<AppResult<void>> save(PracticeHistoryEntry entry) async =>
      const AppResult.success(null);

  @override
  Future<AppResult<void>> clear() async => const AppResult.success(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Map<String, Object> seed) async {
    await tester.pumpWidget(
      ProviderScope(
        // Only the local key/value store is overridden — no Dio, no HTTP
        // client, no network provider of any kind. The screen still
        // renders the full list from this alone (A4).
        overrides: preferenceOverrides(seed),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PracticeHistoryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('A3 — a corrupt record is isolated, the rest of the list works', () {
    testWidgets('two good records render; the corrupt one is skipped, not '
        'thrown', (tester) async {
      final goodOne = const PracticeHistorySerializer().toJson(
        _entry('good-1', 'Quarter downstrokes'),
      );
      final goodTwo = const PracticeHistorySerializer().toJson(
        _entry('good-2', 'Alternating eighths'),
      );
      final envelope =
          '{"schemaVersion":1,"items":['
          '${jsonEncode(goodOne)},'
          '${jsonEncode(goodTwo)},'
          '{"v":1,"id":"bad","mode":"__never_heard__","source":"builtin",'
          '"createdAt":"2026-08-01T12:00:00.000Z","definitionId":"d",'
          '"displayTitle":"t","finishReason":"userFinished",'
          '"activeMs":0,"pausedMs":0,"attemptsCount":1,'
          '"final":{"completion":{"kind":"available","value":1.0},'
          '"rhythm":{"kind":"notApplicable"},"direction":{"kind":"notApplicable"},'
          '"chord":{"kind":"notApplicable"},"overall":{"kind":"notApplicable"}},'
          '"totalTargets":0,"resolvedTargets":0,"scorePoints":0,"maxCombo":0,'
          '"meanOffsetMicros":0,"timingBiasMicros":0,"coachingSummary":[],'
          '"skillTags":[],"details":[]}'
          ']}';

      await pump(tester, <String, Object>{
        StorageKeys.practiceHistoryV2: envelope,
      });

      expect(tester.takeException(), isNull);
      expect(find.text('Quarter downstrokes'), findsOneWidget);
      expect(find.text('Alternating eighths'), findsOneWidget);
      // The corrupt record never surfaces any row for `id: bad` — there is
      // nothing decoded to show, and the list is not empty because of it.
      expect(find.text('t'), findsNothing);
    });

    testWidgets('a history made ENTIRELY of corrupt records renders the empty state, '
        'not a crash', (tester) async {
      await pump(tester, <String, Object>{
        StorageKeys.practiceHistoryV2:
            '{"schemaVersion":1,"items":[{"v":1,"id":"bad","mode":'
            '"__never_heard__","source":"builtin",'
            '"createdAt":"2026-08-01T12:00:00.000Z","definitionId":"d",'
            '"displayTitle":"t","finishReason":"userFinished",'
            '"activeMs":0,"pausedMs":0,"attemptsCount":1,'
            '"final":{"completion":{"kind":"available","value":1.0},'
            '"rhythm":{"kind":"notApplicable"},"direction":{"kind":"notApplicable"},'
            '"chord":{"kind":"notApplicable"},"overall":{"kind":"notApplicable"}},'
            '"totalTargets":0,"resolvedTargets":0,"scorePoints":0,"maxCombo":0,'
            '"meanOffsetMicros":0,"timingBiasMicros":0,"coachingSummary":[],'
            '"skillTags":[],"details":[]}]}',
      });

      expect(tester.takeException(), isNull);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.practiceHistoryEmptyTitle), findsOneWidget);
    });
  });

  group('A4 — offline availability', () {
    testWidgets('a fresh install (no stored key at all) renders the empty '
        'state without a network dependency', (tester) async {
      await pump(tester, <String, Object>{});

      expect(tester.takeException(), isNull);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.practiceHistoryEmptyTitle), findsOneWidget);
    });

    testWidgets('local records render fully from the key/value store alone', (
      tester,
    ) async {
      final entryJson = const PracticeHistorySerializer().toJson(
        _entry('offline-1', 'Offline fixture'),
      );
      await pump(tester, <String, Object>{
        StorageKeys.practiceHistoryV2: jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'items': [entryJson],
        }),
      });

      expect(tester.takeException(), isNull);
      expect(find.text('Offline fixture'), findsOneWidget);
    });
  });

  group('E15-R04 — design-system migration', () {
    Future<void> pumpWithRepository(
      WidgetTester tester,
      PracticeHistoryRepository repository, {
      Locale locale = const Locale('en'),
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            practiceHistoryRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PracticeHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a load failure renders the SsFailureState with a working retry '
      'action, not a raw error',
      (tester) async {
        await pumpWithRepository(tester, const _FailingHistoryRepository());
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('ss-failure-state-retry')),
          findsOneWidget,
        );
      },
    );

    for (final locale in [const Locale('en'), const Locale('hu')]) {
      testWidgets('textScaler 2.0 renders the populated list without overflow '
          '(${locale.languageCode})', (tester) async {
        tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(
          tester.view.platformDispatcher.clearTextScaleFactorTestValue,
        );
        final entryJson = const PracticeHistorySerializer().toJson(
          _entry('scale-1', 'Scale fixture'),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: preferenceOverrides(<String, Object>{
              StorageKeys.practiceHistoryV2: jsonEncode(<String, Object?>{
                'schemaVersion': 1,
                'items': [entryJson],
              }),
            }),
            child: MaterialApp(
              theme: SsLightTheme.data(),
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const PracticeHistoryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('textScaler 2.0 renders the SsFailureState without overflow '
          '(${locale.languageCode})', (tester) async {
        tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(
          tester.view.platformDispatcher.clearTextScaleFactorTestValue,
        );
        await pumpWithRepository(
          tester,
          const _FailingHistoryRepository(),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

PracticeHistoryEntry _entry(String id, String title) {
  return PracticeHistoryEntry(
    id: id,
    modeCode: PracticeMode.strumPattern.code,
    sourceCode: PracticeSource.builtin.code,
    createdAt: DateTime.utc(2026, 8, 1, 12, 0),
    definitionId: 'd-$id',
    displayTitle: title,
    finishReasonCode: 'completedAllTargets',
    activeDuration: const Duration(seconds: 30),
    pausedDuration: Duration.zero,
    attemptsCount: 1,
    finalMetricSnapshot: const PracticeMetricSnapshot(
      completion: PracticeMetricDimensionAvailable(0.9),
      rhythm: PracticeMetricDimensionAvailable(0.85),
      direction: PracticeMetricDimensionAvailable(0.95),
      chord: PracticeMetricDimensionNotApplicable(),
      overall: PracticeMetricDimensionAvailable(0.9),
    ),
    totalTargets: 16,
    resolvedTargets: 14,
    scorePoints: 800,
    maxCombo: 12,
    meanAbsoluteOffset: const Duration(milliseconds: 18),
    timingBias: const Duration(milliseconds: -2),
    coachingSummary: const [],
    skillTags: const ['guard'],
    highestStableTempoBpm: null,
  );
}
