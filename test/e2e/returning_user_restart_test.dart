// E12-R11 — E2E flow 2: returning user survives an app restart (ADR 0472).
// The "restart" is the §0.0/R6 kötött alak: pumpWidget(SizedBox.shrink()) ->
// dispose the FIRST ProviderContainer -> a NEW container + NEW router on the
// SAME InMemoryKeyValueStore instance -> pump the real StrumSightApp again.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/e2e_harness.dart';

void main() {
  group(
    'A2 — returning user survives an app restart (real StrumSightApp tree)',
    () {
      testWidgets(
        'a practiced session persists across pumpWidget(shrink) -> dispose -> '
        'fresh container/router on the same store',
        (tester) async {
          final store = InMemoryKeyValueStore();
          var session = await bootE2eApp(
            tester,
            store: store,
            onboardingSeen: true,
          );

          await runFirstPracticeSession(tester, session);
          final before = await loadPracticeHistory(session.container);
          expect(before, hasLength(1));

          session = await restartE2eApp(
            tester,
            session,
            store: store,
            onboardingSeen: true,
          );

          // A returning user (onboardingSeen already true in the shared
          // store) must not see onboarding again after the restart.
          expect(find.text('Skip'), findsNothing);

          final after = await loadPracticeHistory(session.container);
          expect(
            after,
            hasLength(1),
            reason:
                'the pre-restart history must still be there — same '
                'store instance, new container',
          );
          expect(
            snapshotHistoryEntry(after.single),
            equals(snapshotHistoryEntry(before.single)),
            reason:
                'the restored record must match the one recorded before '
                'the restart field-for-field (createdAt aside)',
          );

          await session.dispose(tester);
          // ADR 0472 D6 / brief §9 — flutter_animate's teardown timer.
          await tester.pump(const Duration(milliseconds: 400));
        },
      );
    },
  );

  group('A4 — determinism: two independent restart runs agree', () {
    testWidgets(
      'two independent runs of the practice-then-restart flow produce '
      'identical before/after snapshots',
      (tester) async {
        final first = await _runOnceAndSnapshot(tester);
        final second = await _runOnceAndSnapshot(tester);

        expect(
          second,
          equals(first),
          reason:
              'same deterministic inputs must reproduce the same '
              'pre- and post-restart snapshots',
        );

        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('A5 — the harness source never hides a real clock or a real RNG', () {
    test('fake_clock.dart, fake_network_guard.dart, e2e_harness.dart contain '
        'no DateTime.now( and no Random(', () {
      for (final relativePath in const [
        'test/support/fake_clock.dart',
        'test/support/fake_network_guard.dart',
        'test/support/e2e_harness.dart',
      ]) {
        final file = File(relativePath);
        expect(file.existsSync(), isTrue, reason: '$relativePath must exist');
        final source = file.readAsStringSync();

        expect(
          source.contains('DateTime.now('),
          isFalse,
          reason:
              '$relativePath must not read the ambient wall clock '
              '(ADR 0472 D3/D4)',
        );
        expect(
          source.contains('Random('),
          isFalse,
          reason:
              '$relativePath must not construct a real random generator '
              '(ADR 0472 D3/D4)',
        );
      }
    });
  });
}

/// Runs practice-then-restart once on a brand-new store/container pair and
/// returns the before/after [PracticeHistorySnapshot]s the A4 cell above
/// compares.
Future<({PracticeHistorySnapshot before, PracticeHistorySnapshot after})>
_runOnceAndSnapshot(WidgetTester tester) async {
  final store = InMemoryKeyValueStore();
  var session = await bootE2eApp(tester, store: store, onboardingSeen: true);

  await runFirstPracticeSession(tester, session);
  final beforeHistory = await loadPracticeHistory(session.container);
  final before = snapshotHistoryEntry(beforeHistory.single);

  session = await restartE2eApp(
    tester,
    session,
    store: store,
    onboardingSeen: true,
  );
  final afterHistory = await loadPracticeHistory(session.container);
  final after = snapshotHistoryEntry(afterHistory.single);

  await session.dispose(tester);
  return (before: before, after: after);
}
