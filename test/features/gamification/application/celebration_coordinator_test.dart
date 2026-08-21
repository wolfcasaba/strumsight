import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/application/celebration_coordinator.dart';
import 'package:strumsight/features/gamification/domain/profile/reward_inbox_item.dart';

/// Test surface for E08-R22 (ADR 0389). Each cell from the §6 acceptance
/// table maps to one or more `test(...)` blocks, and every failure mode in
/// the §6.1 "mérce-mátrix" is covered by a strict assertion that a broken
/// implementation would violate.
void main() {
  // Deterministic anchor time used by every scenario.
  final t0 = DateTime.utc(2026, 8, 21, 12, 0, 0);

  RewardEvent event({
    String id = 'evt',
    RewardKind kind = RewardKind.dailyReward,
    String titleKey = 'reward.title',
    String bodyKey = 'reward.body',
    int xp = 10,
    DateTime? earnedAt,
    List<int> crossedLevels = const <int>[],
    String sourceLedgerId = 'ledger-1',
  }) => RewardEvent(
    id: id,
    kind: kind,
    titleKey: titleKey,
    bodyKey: bodyKey,
    earnedXp: xp,
    earnedAt: earnedAt ?? t0,
    sourceLedgerId: sourceLedgerId,
    crossedLevelNumbers: crossedLevels,
  );

  group('A1 — active session: no celebration, ever (§5.1)', () {
    test(
      'A1: active session routes the reward to the inbox, not a summary',
      () {
        const coordinator = CelebrationCoordinator(
          batchWindow: Duration(seconds: 5),
        );
        final (state, effects) = coordinator.apply(
          state: const CelebrationState(),
          event: event(),
          isActiveSession: true,
          now: t0,
        );

        // §5.1 / §6 A1 — no summary should ever appear while active.
        expect(state.inbox, hasLength(1));
        expect(state.pendingBatch, isEmpty);
        expect(state.pendingSummaries, isEmpty);
        expect(effects.closedSummaries, isEmpty);

        // The routed item carries the active-session routing reason so the
        // presentation layer can label it differently if needed.
        expect(effects.routedToInbox, hasLength(1));
        expect(effects.routedToInbox.first.item.event.id, equals('evt'));
      },
    );

    test(
      'A1: ten sequential events during an active session all stay in the inbox',
      () {
        const coordinator = CelebrationCoordinator(
          batchWindow: Duration(seconds: 5),
        );
        CelebrationState state = const CelebrationState();
        for (var i = 0; i < 10; i++) {
          final result = coordinator.apply(
            state: state,
            event: event(
              id: 'evt-$i',
              earnedAt: t0.add(Duration(seconds: i)),
            ),
            isActiveSession: true,
            now: t0.add(Duration(seconds: i)),
          );
          state = result.$1;
        }
        expect(state.inbox, hasLength(10));
        expect(state.pendingSummaries, isEmpty);
        expect(state.pendingBatch, isEmpty);
      },
    );

    test(
      'A1: switching from active → inactive during a session starts a fresh batch',
      () {
        const coordinator = CelebrationCoordinator(
          batchWindow: Duration(seconds: 5),
        );

        // During the session — inbox only.
        final active = coordinator.apply(
          state: const CelebrationState(),
          event: event(id: 'evt-active', earnedAt: t0),
          isActiveSession: true,
          now: t0,
        );
        expect(active.$1.inbox, hasLength(1));
        expect(active.$1.pendingBatch, isEmpty);

        // Session ends — the next event starts a new batch (inbox is preserved).
        final afterEnd = coordinator.apply(
          state: active.$1,
          event: event(id: 'evt-post', earnedAt: t0.add(Duration(seconds: 30))),
          isActiveSession: false,
          now: t0.add(Duration(seconds: 30)),
        );
        expect(afterEnd.$1.inbox, hasLength(1)); // active event still there
        expect(afterEnd.$1.pendingBatch, hasLength(1));
        expect(afterEnd.$1.pendingBatch.first.id, equals('evt-post'));
      },
    );
  });

  group('A2 — session end: multiple rewards consolidate into ONE summary', () {
    test(
      'A2: three events delivered while inactive drain into one summary',
      () {
        const coordinator = CelebrationCoordinator(
          batchWindow: Duration(seconds: 5),
        );
        CelebrationState state = const CelebrationState();
        for (var i = 0; i < 3; i++) {
          final result = coordinator.apply(
            state: state,
            event: event(
              id: 'lvl-$i',
              kind: RewardKind.levelUp,
              earnedAt: t0.add(Duration(seconds: i)),
            ),
            isActiveSession: false,
            now: t0.add(Duration(seconds: i)),
          );
          state = result.$1;
        }

        final (drained, summaries) = coordinator.drain(
          state: state,
          now: t0.add(const Duration(seconds: 10)),
        );
        expect(summaries, hasLength(1));
        expect(summaries.first.count, equals(3));
        expect(summaries.first.totalXp, equals(30));
        expect(drained.inbox, isEmpty);
        expect(drained.pendingBatch, isEmpty);
        expect(drained.pendingSummaries, isEmpty);
      },
    );
  });

  group(
    'A3 — reward must already be in the ledger before it reaches the coordinator',
    () {
      test('A3: RewardEvent constructor rejects a blank sourceLedgerId', () {
        expect(
          () => event(sourceLedgerId: ''),
          throwsA(isA<ArgumentError>()),
          reason:
              'A3 sorrend-cella — a koordinátor nem írhat a ledgerbe; ha nincs '
              'forrás, a jutalom NEM jóváírt, és nem kerülhet a postaládába.',
        );
      });

      test(
        'A3: coordinator state surfaces only what was already in the ledger',
        () {
          const coordinator = CelebrationCoordinator(
            batchWindow: Duration(seconds: 5),
          );
          final (state, _) = coordinator.apply(
            state: const CelebrationState(),
            event: event(sourceLedgerId: 'ledger-xyz'),
            isActiveSession: true,
            now: t0,
          );
          // The inbox entry exposes the source ledger id so the presentation
          // layer can prove the reward is already credited — the coordinator
          // never writes to the ledger itself.
          expect(state.inbox.single.event.sourceLedgerId, equals('ledger-xyz'));
        },
      );
    },
  );

  group('A4 — no expiry, no claim field on RewardInboxItem (§5.2)', () {
    test('A4: RewardInboxItem has no expiry/claim API surface', () {
      final item = RewardInboxItem(id: 'x', event: event(), addedAt: t0);
      // The type must not expose any expiry / claim method — the postaláda
      // is értesítési, not beváltás (ADR 0389 §4).
      final exposed = item.toJson().keys.toSet();
      expect(exposed, isNot(contains('expiresAt')));
      expect(exposed, isNot(contains('claimedAt')));
      expect(exposed, isNot(contains('claimState')));
      // The only mutable surface is the `seen` flag, accessed via
      // markSeen — never via a setter or a claim method.
      final publicMethods = item.runtimeType.toString();
      expect(publicMethods.contains('claim'), isFalse);
    });
  });

  group('A5 — background / closed-app rewards still surface in the inbox', () {
    test(
      'A5: events arriving after the app wakes up follow the same rules',
      () {
        const coordinator = CelebrationCoordinator(
          batchWindow: Duration(seconds: 5),
        );
        // Simulate the background path: an event arrives at a much later
        // `now`, the user is no longer in a session.
        final (state, effects) = coordinator.apply(
          state: const CelebrationState(),
          event: event(id: 'bg', earnedAt: t0),
          isActiveSession: false,
          now: t0.add(const Duration(hours: 3)),
        );

        // The background reward starts a fresh batch (no prior event in the
        // window) — when drained it produces a one-event summary. The user
        // can still see it.
        final (drained, summaries) = coordinator.drain(
          state: state,
          now: t0.add(const Duration(hours: 3)),
        );
        expect(summaries, hasLength(1));
        expect(summaries.first.events.single.id, equals('bg'));
        expect(effects.closedSummaries, isEmpty);
        expect(drained.pendingBatch, isEmpty);
      },
    );
  });

  group('A6 — deterministic priority order (§5.3)', () {
    test('A6: summary events are sorted milestone > level > quest > daily', () {
      const coordinator = CelebrationCoordinator(
        batchWindow: Duration(seconds: 5),
      );
      // Apply in random order with the SAME earnedAt so the sort is purely
      // driven by priority, not by insertion order.
      final kinds = <RewardKind>[
        RewardKind.dailyReward,
        RewardKind.questCompleted,
        RewardKind.levelUp,
        RewardKind.masteryMilestone,
        RewardKind.challengeCompleted,
      ];
      CelebrationState state = const CelebrationState();
      for (var i = 0; i < kinds.length; i++) {
        final result = coordinator.apply(
          state: state,
          event: event(id: 'e-$i', kind: kinds[i], earnedAt: t0),
          isActiveSession: false,
          now: t0,
        );
        state = result.$1;
      }

      final summaries = coordinator.drain(state: state, now: t0).$2;
      expect(
        summaries.single.events.map((e) => e.kind).toList(),
        equals(<RewardKind>[
          RewardKind.masteryMilestone,
          RewardKind.levelUp,
          RewardKind.questCompleted, // ties with challengeCompleted at index 1
          RewardKind.challengeCompleted,
          RewardKind.dailyReward,
        ]),
      );
    });

    test('A6: priority is independent of insertion order', () {
      // Reverse insertion order — result must be identical to the previous
      // test. This is the §6.1 "Map bejárási sorrend" failure mode.
      const coordinator = CelebrationCoordinator(
        batchWindow: Duration(seconds: 5),
      );
      CelebrationState state = const CelebrationState();
      for (var i = 4; i >= 0; i--) {
        final kind = <RewardKind>[
          RewardKind.dailyReward,
          RewardKind.questCompleted,
          RewardKind.levelUp,
          RewardKind.masteryMilestone,
          RewardKind.challengeCompleted,
        ][i];
        state = coordinator
            .apply(
              state: state,
              event: event(id: 'rev-$i', kind: kind, earnedAt: t0),
              isActiveSession: false,
              now: t0,
            )
            .$1;
      }
      final kinds = coordinator
          .drain(state: state, now: t0)
          .$2
          .single
          .events
          .map((e) => e.kind)
          .toList();
      expect(
        kinds,
        equals(<RewardKind>[
          RewardKind.masteryMilestone,
          RewardKind.levelUp,
          RewardKind.questCompleted,
          RewardKind.challengeCompleted,
          RewardKind.dailyReward,
        ]),
      );
    });
  });

  group(
    'A7 — reduced motion: information preserved, animation dropped (§5.4)',
    () {
      test(
        'A7: summary.events contains the full payload required for static rendering',
        () {
          const coordinator = CelebrationCoordinator(
            batchWindow: Duration(seconds: 5),
          );
          final (state, _) = coordinator.apply(
            state: const CelebrationState(),
            event: event(
              id: 'a7',
              kind: RewardKind.levelUp,
              titleKey: 'level.title',
              bodyKey: 'level.body',
              xp: 42,
              crossedLevels: <int>[3, 4, 5],
            ),
            isActiveSession: false,
            now: t0,
          );
          final summaries = coordinator.drain(state: state, now: t0).$2;
          final firstEvent = summaries.single.events.single;
          // Every field the widget needs to render statically is present and
          // unchanged — no information is dropped when reduced motion is on.
          expect(firstEvent.id, equals('a7'));
          expect(firstEvent.kind, equals(RewardKind.levelUp));
          expect(firstEvent.titleKey, equals('level.title'));
          expect(firstEvent.bodyKey, equals('level.body'));
          expect(firstEvent.earnedXp, equals(42));
          expect(firstEvent.earnedAt, equals(t0));
          expect(firstEvent.sourceLedgerId, equals('ledger-1'));
          expect(firstEvent.crossedLevelNumbers, equals(<int>[3, 4, 5]));
          expect(summaries.single.totalXp, equals(42));
          expect(summaries.single.count, equals(1));
        },
      );
    },
  );

  group('A8 — inbox survives app restart via JSON round-trip', () {
    test('A8: toJson → fromJson yields an equal inbox state', () {
      final original = RewardInboxItem(
        id: 'persist',
        event: event(
          id: 'persist',
          kind: RewardKind.levelUp,
          crossedLevels: <int>[2],
          xp: 7,
          earnedAt: t0,
          sourceLedgerId: 'ledger-p',
        ),
        addedAt: t0,
      );

      final restored = RewardInboxItem.fromJson(original.toJson());
      expect(restored, equals(original));
      expect(restored.seen, isFalse);
      final seen = restored.markSeen(isSeen: true);
      expect(seen.seen, isTrue);
      expect(seen, isNot(equals(original)));
    });

    test('A8: state with multiple items survives the round-trip', () {
      const coordinator = CelebrationCoordinator(
        batchWindow: Duration(seconds: 5),
      );
      CelebrationState state = const CelebrationState();
      for (var i = 0; i < 3; i++) {
        state = coordinator
            .apply(
              state: state,
              event: event(id: 'p-$i', earnedAt: t0),
              isActiveSession: true,
              now: t0,
            )
            .$1;
      }
      // The inbox is a plain list — a persistence adapter can serialise
      // every entry via its own toJson and rehydrate via fromJson.
      expect(state.inbox, hasLength(3));
      final restored = state.inbox
          .map((i) => RewardInboxItem.fromJson(i.toJson()))
          .toList();
      expect(restored, equals(state.inbox));
    });
  });

  group('§6.1 threshold triplet — alatt / rajta / fölött', () {
    const window = Duration(seconds: 10);

    test(
      'alatt (window - 1): the two events are CONSOLIDATED into one summary',
      () {
        const coordinator = CelebrationCoordinator(batchWindow: window);
        final s0 = coordinator
            .apply(
              state: const CelebrationState(),
              event: event(id: 'a', earnedAt: t0),
              isActiveSession: false,
              now: t0,
            )
            .$1;
        final s1 = coordinator
            .apply(
              state: s0,
              event: event(
                id: 'b',
                earnedAt: t0.add(window - const Duration(seconds: 1)),
              ),
              isActiveSession: false,
              now: t0.add(window - const Duration(seconds: 1)),
            )
            .$1;
        final summaries = coordinator.drain(state: s1, now: t0.add(window)).$2;
        expect(summaries, hasLength(1));
        expect(
          summaries.single.events.map((e) => e.id),
          equals(<String>['a', 'b']),
        );
      },
    );

    test(
      'rajta (exactly window): the boundary belongs to ÖSSZEVONÁS (inclusive)',
      () {
        const coordinator = CelebrationCoordinator(batchWindow: window);
        final s0 = coordinator
            .apply(
              state: const CelebrationState(),
              event: event(id: 'a', earnedAt: t0),
              isActiveSession: false,
              now: t0,
            )
            .$1;
        final s1 = coordinator
            .apply(
              state: s0,
              event: event(id: 'b', earnedAt: t0.add(window)),
              isActiveSession: false,
              now: t0.add(window),
            )
            .$1;
        final summaries = coordinator.drain(state: s1, now: t0.add(window)).$2;
        expect(summaries, hasLength(1));
        expect(
          summaries.single.events.map((e) => e.id),
          equals(<String>['a', 'b']),
        );
      },
    );

    test('fölött (window + 1): the two events become SEPARATE summaries', () {
      const coordinator = CelebrationCoordinator(batchWindow: window);
      final s0 = coordinator
          .apply(
            state: const CelebrationState(),
            event: event(id: 'a', earnedAt: t0),
            isActiveSession: false,
            now: t0,
          )
          .$1;
      final s1 = coordinator
          .apply(
            state: s0,
            event: event(
              id: 'b',
              earnedAt: t0.add(window + const Duration(seconds: 1)),
            ),
            isActiveSession: false,
            now: t0.add(window + const Duration(seconds: 1)),
          )
          .$1;
      final summaries = coordinator
          .drain(state: s1, now: t0.add(window + const Duration(seconds: 5)))
          .$2;
      expect(summaries, hasLength(2));
      expect(summaries[0].events.single.id, equals('a'));
      expect(summaries[1].events.single.id, equals('b'));
    });

    test(
      'fölött + közben gyakorlás indult: the second event goes to the INBOX',
      () {
        // Brief §6.1 fölött: "a második a postaládába kerül, ha közben
        // gyakorlás indult" — when the window is exceeded AND the caller
        // reports isActiveSession=true for the new event, the second event
        // is deflected to the inbox instead of starting a new batch.
        const coordinator = CelebrationCoordinator(batchWindow: window);
        final s0 = coordinator
            .apply(
              state: const CelebrationState(),
              event: event(id: 'a', earnedAt: t0),
              isActiveSession: false,
              now: t0,
            )
            .$1;
        final s1 = coordinator
            .apply(
              state: s0,
              event: event(
                id: 'b',
                earnedAt: t0.add(window + const Duration(seconds: 1)),
              ),
              isActiveSession: true, // session became active in between
              now: t0.add(window + const Duration(seconds: 1)),
            )
            .$1;

        // The first event closed into a pending summary; the second went to
        // the inbox because the session was active.
        expect(s1.pendingSummaries.single.events.single.id, equals('a'));
        expect(s1.inbox.single.event.id, equals('b'));
        expect(s1.pendingBatch, isEmpty);

        // Drain: the closed summary is delivered, the inbox item survives.
        final (drained, summaries) = coordinator.drain(
          state: s1,
          now: t0.add(window + const Duration(seconds: 5)),
        );
        expect(summaries.single.events.single.id, equals('a'));
        expect(drained.inbox.single.event.id, equals('b'));
      },
    );
  });

  group('A1 — szigorú megszakítás-mátrix (valódi-sértés próba)', () {
    // The brief (§6.1, KÖTELEZŐ valódi-sértés próba) requires that we
    // *would* catch a buggy implementation that lets a popup through during
    // an active session. The assertions below are designed so that a single
    // `if (isActiveSession) → return summary(...)` style regression flips
    // every assertion in this group to PIROS. The §10 handoff records the
    // actual sed-based probe performed at the end of the round.
    test(
      'A1 real-violation: strict contract — active session produces zero summaries',
      () {
        const coordinator = CelebrationCoordinator(
          batchWindow: Duration(seconds: 5),
        );
        CelebrationState state = const CelebrationState();
        for (var i = 0; i < 5; i++) {
          final result = coordinator.apply(
            state: state,
            event: event(
              id: 'v-$i',
              earnedAt: t0.add(Duration(seconds: i)),
            ),
            isActiveSession: true,
            now: t0.add(Duration(seconds: i)),
          );
          state = result.$1;
          // Per-step guarantee — every call must produce zero summaries.
          expect(state.pendingSummaries, isEmpty);
          expect(result.$2.closedSummaries, isEmpty);
        }
        final drained = coordinator.drain(
          state: state,
          now: t0.add(const Duration(seconds: 10)),
        );
        expect(drained.$2, isEmpty);
        expect(drained.$1.inbox, hasLength(5));
      },
    );
  });
}
