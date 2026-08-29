// E13-R22 — A5: the reward comes from the ledger, and re-opening a result
// never duplicates it.
//
// The screen must NEVER call `RewardLedgerRepository.appendIfAbsent` (only
// the gamification write path does that) and must NEVER derive an XP number
// from the session's own metrics — it only reads whatever the ledger
// already has under the session's stable event id (ADR 0283 §Döntés 4).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice/application/gamification_practice_adapter.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/presentation/providers/practice_result_providers.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/preference_store.dart';

AppLocalizations l10n() => AppLocalizationsEn();

class _FakeRewardLedgerRepository implements RewardLedgerRepository {
  _FakeRewardLedgerRepository([List<RewardLedgerEntry>? seed])
    : entries = List<RewardLedgerEntry>.of(seed ?? const []);

  final List<RewardLedgerEntry> entries;

  /// Calls the screen must NEVER make — a positive count is itself a test
  /// failure (the UI-side "estimate the reward" regression the mérce-mátrix
  /// names).
  int appendCallCount = 0;

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) async {
    appendCallCount++;
    final exists = entries.any((e) => e.sourceEventId == entry.sourceEventId);
    if (exists) return false;
    entries.add(entry);
    return true;
  }

  @override
  bool hasProcessedEvent(String sourceEventId) =>
      entries.any((e) => e.sourceEventId == sourceEventId);

  @override
  RewardLedgerPage readPage({required int limit, String? cursor}) {
    var start = 0;
    if (cursor != null) {
      final index = entries.indexWhere((e) => e.sourceEventId == cursor);
      start = index < 0 ? entries.length : index + 1;
    }
    final end = (start + limit).clamp(0, entries.length);
    final page = entries.sublist(start, end);
    return RewardLedgerPage(
      entries: page,
      nextCursor: end < entries.length ? page.last.sourceEventId : null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpResult(
    WidgetTester tester,
    PracticeHistoryEntry entry,
    RewardLedgerRepository ledger,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          rewardLedgerRepositoryProvider.overrideWithValue(ledger),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PracticeResultScreen(entry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a ledger entry for the stable session event id renders its totalXp',
    (tester) async {
      final entry = _entry('session-1');
      final eventId = GamificationPracticeAdapter.stableEventId(entry.id);
      final ledger = _FakeRewardLedgerRepository([
        RewardLedgerEntry(
          ledgerId: 'ledger-1',
          sourceEventId: eventId,
          createdAt: DateTime.utc(2026, 8, 1),
          schemaVersion: rewardLedgerEntrySchemaVersion,
          policyVersion: 1,
          baseXp: 20,
          bonusXp: 5,
          totalXp: 25,
          reasonCodes: const [RewardReason.baseExperience],
        ),
      ]);

      await pumpResult(tester, entry, ledger);

      expect(find.text(l10n().practiceResultRewardXp(25)), findsOneWidget);
      expect(find.text(l10n().practiceResultRewardNone), findsNothing);
      // The screen never writes — only reads.
      expect(ledger.appendCallCount, 0);
    },
  );

  testWidgets('no ledger entry for this session renders "no reward" — never an '
      'estimated number', (tester) async {
    final entry = _entry('session-2');
    final ledger = _FakeRewardLedgerRepository();

    await pumpResult(tester, entry, ledger);

    expect(find.text(l10n().practiceResultRewardNone), findsOneWidget);
    expect(ledger.appendCallCount, 0);
  });

  testWidgets(
    'A5 — reopening the SAME result twice reads the identical reward both '
    'times, without the screen ever appending',
    (tester) async {
      final entry = _entry('session-3');
      final eventId = GamificationPracticeAdapter.stableEventId(entry.id);
      final ledger = _FakeRewardLedgerRepository([
        RewardLedgerEntry(
          ledgerId: 'ledger-3',
          sourceEventId: eventId,
          createdAt: DateTime.utc(2026, 8, 1),
          schemaVersion: rewardLedgerEntrySchemaVersion,
          policyVersion: 1,
          baseXp: 40,
          bonusXp: 0,
          totalXp: 40,
          reasonCodes: const [RewardReason.baseExperience],
        ),
      ]);

      // First open.
      await pumpResult(tester, entry, ledger);
      expect(find.text(l10n().practiceResultRewardXp(40)), findsOneWidget);

      // Simulate the user leaving and reopening the SAME session's result —
      // a fresh widget tree over the same ledger.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpResult(tester, entry, ledger);

      expect(find.text(l10n().practiceResultRewardXp(40)), findsOneWidget);
      // Still exactly one entry in the ledger — the reopen did not add a
      // second receipt, and the screen never called `appendIfAbsent`.
      expect(ledger.entries.length, 1);
      expect(ledger.appendCallCount, 0);
    },
  );
}

PracticeHistoryEntry _entry(String id) {
  return PracticeHistoryEntry(
    id: id,
    modeCode: PracticeMode.strumPattern.code,
    sourceCode: PracticeSource.builtin.code,
    createdAt: DateTime.utc(2026, 8, 1, 12, 0),
    definitionId: 'd-$id',
    displayTitle: 'fixture-$id',
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
    resolvedTargets: 16,
    scorePoints: 900,
    maxCombo: 16,
    meanAbsoluteOffset: const Duration(milliseconds: 12),
    timingBias: Duration.zero,
    coachingSummary: const [],
    skillTags: const ['guard'],
    highestStableTempoBpm: 110.0,
  );
}
