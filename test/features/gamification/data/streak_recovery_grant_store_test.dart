// R34 — the streak RECOVERY grant (audit §5.6 remainder,
// `docs/ui/legacy-backlog.md` §6.2).
//
// Measured before this round: `StreakEvaluationRequest.recoveryEligible` —
// the domain's only recovery concept, a LOWER qualification threshold for one
// session — was never `true` anywhere in `lib/`. R22 wired the broken-streak
// CTA to the practice hub, which is where such a session starts, but nothing
// credited the easier threshold, so the CTA's own promise ("Start a recovery
// practice") was navigation and nothing else.
//
// These cells drive the persisted grant against the same in-memory
// `KeyValueStore` production reads, and pin the three properties that make it
// a grant rather than a currency: it survives a restart, it is spent exactly
// once, and it is only spent by a day that could actually use it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/data/streak_recovery_grant_store.dart';
import 'package:strumsight/features/gamification/domain/activity/activity_source.dart';
import 'package:strumsight/features/gamification/domain/activity/evidence_trust.dart';
import 'package:strumsight/features/gamification/domain/activity/learning_activity_event.dart';
import 'package:strumsight/features/gamification/domain/streak/streak_state.dart';
import 'package:strumsight/features/gamification/infrastructure/default_streak_policy.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const int _today = 20705;

StreakState _state() => StreakState(
  current: 4,
  longest: 4,
  lastQualifiedDay: _today - 2,
  totalQualifiedDays: 4,
  freezes: 0,
);

/// A session SHORTER than the full qualifying minimum but at least the
/// recovery minimum — the only window in which the grant changes anything.
LearningActivityEvent _shortSession(int epochDay) {
  final config = DefaultStreakPolicyConfig.standard();
  return PracticeActivityEvent(
    eventId: 'recovery-session-$epochDay',
    occurredAt: DateTime.utc(2026, 9, 8),
    epochDay: epochDay,
    source: ActivitySource.practice,
    trust: EvidenceTrust.scored,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: config.minRecoveryDuration,
    score: 1,
  );
}

void main() {
  test('a session with NO grant carries the full threshold', () async {
    final store = InMemoryKeyValueStore();
    final grants = StreakRecoveryGrantStore(store: store);

    final request = await grants.requestFor(
      previous: _state(),
      epochDay: _today,
      activity: _shortSession(_today),
    );

    expect(request.recoveryEligible, isFalse);
  });

  test('a granted recovery lowers the NEXT session\'s threshold and is spent '
      'exactly once', () async {
    final store = InMemoryKeyValueStore();
    final grants = StreakRecoveryGrantStore(store: store);
    await grants.grant(_today);

    final first = await grants.requestFor(
      previous: _state(),
      epochDay: _today,
      activity: _shortSession(_today),
    );
    final second = await grants.requestFor(
      previous: _state(),
      epochDay: _today + 1,
      activity: _shortSession(_today + 1),
    );

    expect(first.recoveryEligible, isTrue);
    expect(
      second.recoveryEligible,
      isFalse,
      reason:
          'a recovery is a single credit — a grant that kept applying would '
          'lower every future day\'s bar for one tap of the CTA',
    );
    expect(grants.grantedOnEpochDay(), isNull);
  });

  test('a day with no measured activity does NOT burn the grant', () async {
    final store = InMemoryKeyValueStore();
    final grants = StreakRecoveryGrantStore(store: store);
    await grants.grant(_today);

    final idleDay = await grants.requestFor(
      previous: _state(),
      epochDay: _today,
    );

    expect(
      idleDay.recoveryEligible,
      isFalse,
      reason: 'the request type itself refuses recovery without an activity',
    );
    expect(
      grants.grantedOnEpochDay(),
      _today,
      reason:
          'no threshold could apply on a day with nothing measured, so '
          'spending the credit there would take the recovery away for nothing',
    );

    final later = await grants.requestFor(
      previous: _state(),
      epochDay: _today + 3,
      activity: _shortSession(_today + 3),
    );
    expect(later.recoveryEligible, isTrue);
  });

  test('a grant never reaches back to a day BEFORE it was made', () async {
    final store = InMemoryKeyValueStore();
    final grants = StreakRecoveryGrantStore(store: store);
    await grants.grant(_today);

    expect(grants.appliesTo(_today - 1), isFalse);
    expect(grants.appliesTo(_today), isTrue);
    expect(grants.appliesTo(_today + 1), isTrue);
  });

  test('granting twice is one recovery, not two', () async {
    final store = InMemoryKeyValueStore();
    final grants = StreakRecoveryGrantStore(store: store);
    await grants.grant(_today);
    await grants.grant(_today);

    final first = await grants.requestFor(
      previous: _state(),
      epochDay: _today,
      activity: _shortSession(_today),
    );
    final second = await grants.requestFor(
      previous: _state(),
      epochDay: _today,
      activity: _shortSession(_today),
    );

    expect(first.recoveryEligible, isTrue);
    expect(second.recoveryEligible, isFalse);
  });

  test('the grant is PERSISTED — a fresh store over the same bytes still '
      'sees it', () async {
    final store = InMemoryKeyValueStore();
    await StreakRecoveryGrantStore(store: store).grant(_today);

    // A new instance over the same key-value store is what a restart looks
    // like: the grant must not live in the object that made it.
    final afterRestart = StreakRecoveryGrantStore(store: store);
    expect(afterRestart.grantedOnEpochDay(), _today);
    expect(
      store.readInt(StreakRecoveryGrantStore.storageKey),
      _today,
      reason: 'production reads the same key this cell asserts on',
    );
  });

  test('the lower threshold is what the policy actually applies', () {
    final config = DefaultStreakPolicyConfig.standard();
    final policy = DefaultStreakPolicy(config: config);
    final session = _shortSession(_today);

    expect(
      policy.qualifies(session, recoveryEligible: false),
      isFalse,
      reason: 'the fixture sits below the full minimum on purpose',
    );
    expect(
      policy.qualifies(session, recoveryEligible: true),
      isTrue,
      reason:
          'without this the grant would be a flag nothing reads — the whole '
          'point of the credit is this one verdict flipping',
    );
  });
}
