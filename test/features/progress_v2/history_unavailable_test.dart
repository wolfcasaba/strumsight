// M9 (re-audit 2026-09-08) — an unreadable practice history is NEVER "you
// have never practiced".
//
// MEASURED before this round: `practiceHistoryV2ListProvider` mapped
// `Failure()` to `const <PracticeHistoryEntry>[]`, and the Progress V2
// composition layer then applied `.value ?? []` on top. A corrupt or
// unreadable history store therefore reached the dashboard as an empty
// history, and the dashboard greeted a learner with years of sessions as a
// brand new user — the same error class R18/R19/R20 closed on three routes
// and the Today Hub, one layer lower, at the source.
//
//   B1 — the read failure survives as an `AsyncError`, not as an empty list,
//   B2 — the composition layer marks it UNAVAILABLE, while a successful
//        empty read stays an honest (available) empty history,
//   B3 — the projection carries the bit, and a plain list still means
//        "this IS the history",
//   B4 — the dashboard renders the error card instead of the new-user hero,
//        and its retry actually re-reads the store,
//   B5 — a real empty history still renders the new-user hero (the state
//        every `e13_r*` golden was recorded in).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice/domain/repository/practice_history_repository.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// A history store that cannot be read — the shape a corrupt document
/// produces once `LocalPracticeHistoryRepository` has quarantined it.
final class _UnreadableHistoryRepository implements PracticeHistoryRepository {
  _UnreadableHistoryRepository();

  int loadCount = 0;

  @override
  Future<AppResult<List<PracticeHistoryEntry>>> load() async {
    loadCount++;
    return const Failure<List<PracticeHistoryEntry>>(
      StorageFailure(code: FailureCode.storageRead),
    );
  }

  @override
  Future<AppResult<void>> save(PracticeHistoryEntry entry) async =>
      const Success<void>(null);

  @override
  Future<AppResult<void>> clear() async => const Success<void>(null);
}

/// A store that reads fine and holds nothing — a genuinely new learner.
final class _EmptyHistoryRepository implements PracticeHistoryRepository {
  const _EmptyHistoryRepository();

  @override
  Future<AppResult<List<PracticeHistoryEntry>>> load() async =>
      const Success<List<PracticeHistoryEntry>>(<PracticeHistoryEntry>[]);

  @override
  Future<AppResult<void>> save(PracticeHistoryEntry entry) async =>
      const Success<void>(null);

  @override
  Future<AppResult<void>> clear() async => const Success<void>(null);
}

ProviderContainer _containerWith(PracticeHistoryRepository repository) {
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      practiceHistoryRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The router's own composition, verbatim (`app_router.dart`'s
/// `profileProgress` builder) — the failure has to travel this exact path.
class _DashboardHost extends ConsumerWidget {
  const _DashboardHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final projection = buildProgressOverviewProjection(
      milestoneCatalog: masteryMilestoneCatalogV1,
      practiceHistory: ref.watch(progressPracticeHistoryProvider),
      practiceCatalog: ref.watch(practiceCatalogProvider),
      now: ref.watch(progressNowProvider),
      isOffline: progressV2IsOffline,
      localize: (key) => progressV2LocalizedText(l10n, key),
    );
    return ProgressDashboardScreen(
      projection: projection,
      onOpenSkillDetail: (_) {},
      onGetStarted: () {},
    );
  }
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  PracticeHistoryRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        practiceHistoryRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const _DashboardHost(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('B1 a failed read surfaces as an error, not an empty list', () async {
    final container = _containerWith(_UnreadableHistoryRepository());

    await expectLater(
      container.read(practiceHistoryV2ListProvider.future),
      throwsA(isA<AppFailure>()),
    );
  });

  test('B2 the composition layer marks the failure UNAVAILABLE', () async {
    final container = _containerWith(_UnreadableHistoryRepository());

    await expectLater(
      container.read(practiceHistoryV2ListProvider.future),
      throwsA(isA<AppFailure>()),
    );
    final history = container.read(progressPracticeHistoryProvider);

    expect(history, isEmpty);
    expect(history, isA<ProgressPracticeHistory>());
    expect((history as ProgressPracticeHistory).isUnavailable, isTrue);
  });

  test('B2b a successful empty read stays AVAILABLE', () async {
    final container = _containerWith(const _EmptyHistoryRepository());

    await container.read(practiceHistoryV2ListProvider.future);
    final history = container.read(progressPracticeHistoryProvider);

    expect(history, isEmpty);
    expect((history as ProgressPracticeHistory).isUnavailable, isFalse);
  });

  group('B3 the projection carries the bit', () {
    ProgressOverviewProjection projectionOf(List<PracticeHistoryEntry> given) =>
        buildProgressOverviewProjection(
          milestoneCatalog: masteryMilestoneCatalogV1,
          practiceHistory: given,
          practiceCatalog: const <PracticeDefinition>[],
          now: DateTime.utc(2026, 9, 8),
          isOffline: false,
          localize: (key) => key,
        );

    test('an unavailable history is not a new user', () {
      final projection = projectionOf(ProgressPracticeHistory.unavailable());

      expect(projection.isUnavailable, isTrue);
      expect(
        projection.isNewUser,
        isTrue,
        reason:
            'no evidence accrues from an unread store — which is exactly '
            'why the screen must not believe `isNewUser` on its own',
      );
    });

    test('a plain list still means "this IS the history"', () {
      expect(
        projectionOf(const <PracticeHistoryEntry>[]).isUnavailable,
        isFalse,
      );
      expect(
        projectionOf(ProgressPracticeHistory.loaded(const [])).isUnavailable,
        isFalse,
      );
    });
  });

  testWidgets('B4 the dashboard says the read failed, and retries it', (
    tester,
  ) async {
    final repository = _UnreadableHistoryRepository();
    await _pumpDashboard(tester, repository);

    expect(
      find.byKey(const Key('progress-dashboard-history-unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('progress-dashboard-new-user')),
      findsNothing,
      reason: 'an unread store is not a fact about the learner',
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.progressV2HistoryUnavailableTitle), findsOneWidget);
    expect(find.text(l10n.progressV2NewUserTitle), findsNothing);

    final loadsBeforeRetry = repository.loadCount;
    await tester.tap(find.byKey(const Key('progress-dashboard-history-retry')));
    await tester.pumpAndSettle();

    expect(repository.loadCount, greaterThan(loadsBeforeRetry));
  });

  testWidgets('B5 a real empty history still renders the new-user hero', (
    tester,
  ) async {
    await _pumpDashboard(tester, const _EmptyHistoryRepository());

    expect(
      find.byKey(const Key('progress-dashboard-new-user')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('progress-dashboard-history-unavailable')),
      findsNothing,
    );
  });
}
