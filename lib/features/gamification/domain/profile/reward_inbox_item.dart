/// Stable categories of reward events that may be presented in the inbox or
/// consolidated into a celebration summary.
///
/// The ordering of these values defines the deterministic priority used by
/// the [CelebrationCoordinator]: a higher index wins (mastery milestones
/// outrank level-ups, which outrank quest/challenge completions, which outrank
/// the daily reward). The coordinator never depends on `Map` iteration order
/// — the priority surface is the explicit enum order plus a stable per-kind
/// comparator in [rewardPriorityIndex].
enum RewardKind {
  /// XP credited for a regular practice activity, outside any quest/challenge.
  dailyReward,

  /// A weekly or daily quest was completed.
  questCompleted,

  /// A daily challenge or live challenge was completed.
  challengeCompleted,

  /// The profile crossed one or more [LevelDefinition] thresholds.
  levelUp,

  /// A multi-session mastery milestone was unlocked.
  masteryMilestone,
}

/// Immutable, caller-fed description of one reward that has ALREADY been
/// written to the append-only ledger (ADR 0389 §1 — the coordinator never
/// writes or re-decides eligibility). The coordinator consumes this as a
/// fact and decides only when and how to surface it to the user.
final class RewardEvent {
  RewardEvent({
    required this.id,
    required this.kind,
    required this.titleKey,
    required this.bodyKey,
    required this.earnedXp,
    required this.earnedAt,
    required this.sourceLedgerId,
    List<int> crossedLevelNumbers = const <int>[],
  }) : crossedLevelNumbers = List<int>.unmodifiable(crossedLevelNumbers) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be blank');
    }
    if (titleKey.trim().isEmpty) {
      throw ArgumentError.value(titleKey, 'titleKey', 'must not be blank');
    }
    if (bodyKey.trim().isEmpty) {
      throw ArgumentError.value(bodyKey, 'bodyKey', 'must not be blank');
    }
    if (earnedXp < 0) {
      throw ArgumentError.value(earnedXp, 'earnedXp', 'must not be negative');
    }
    if (earnedAt.microsecondsSinceEpoch == 0) {
      throw ArgumentError.value(earnedAt, 'earnedAt', 'must be set');
    }
    if (sourceLedgerId.trim().isEmpty) {
      throw ArgumentError.value(
        sourceLedgerId,
        'sourceLedgerId',
        'must reference an already-written ledger entry',
      );
    }
    for (final number in crossedLevelNumbers) {
      if (number < 1) {
        throw ArgumentError.value(
          number,
          'crossedLevelNumbers',
          'must be positive',
        );
      }
    }
  }

  /// Stable identifier for de-duplication across replays.
  final String id;

  /// What kind of reward this is — drives the deterministic priority sort.
  final RewardKind kind;

  /// Localization key for the headline text. The coordinator does not resolve
  /// it — that is the widget's job.
  final String titleKey;

  /// Localization key for the supporting text.
  final String bodyKey;

  /// XP credited to the ledger for this event (informational; the reward is
  /// already credited).
  final int earnedXp;

  /// When the ledger entry was created by the evaluator.
  final DateTime earnedAt;

  /// The id of the already-written [RewardLedgerEntry]. The coordinator uses
  /// it only as a stable reference — it never reads or writes the ledger
  /// itself (ADR 0389 §1).
  final String sourceLedgerId;

  /// For [RewardKind.levelUp] events, the levels crossed in this single
  /// reward (one entry can climb multiple levels at once). Empty for other
  /// kinds.
  final List<int> crossedLevelNumbers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RewardEvent &&
          id == other.id &&
          kind == other.kind &&
          titleKey == other.titleKey &&
          bodyKey == other.bodyKey &&
          earnedXp == other.earnedXp &&
          earnedAt == other.earnedAt &&
          sourceLedgerId == other.sourceLedgerId &&
          _sameInts(crossedLevelNumbers, other.crossedLevelNumbers);

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    titleKey,
    bodyKey,
    earnedXp,
    earnedAt,
    sourceLedgerId,
    Object.hashAll(crossedLevelNumbers),
  );
}

/// Immutable postaláda entry. The item is a presentation-side mirror of a
/// [RewardEvent] — it never owns ledger state and never carries an expiry
/// (ADR 0389 §4 / brief §5.2). The only mutable presentation concern is the
/// `seen` flag, which is exposed as a separate copy operation to keep the
/// type immutable.
final class RewardInboxItem {
  RewardInboxItem({
    required this.id,
    required this.event,
    required this.addedAt,
    this.seen = false,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be blank');
    }
  }

  /// Stable identifier — usually equals [RewardEvent.id] so replays collapse.
  final String id;

  /// The already-jóváírt reward event that produced this item.
  final RewardEvent event;

  /// When the item was added to the inbox (UTC). Persisted so the screen can
  /// render the "earned" label deterministically without a clock dependency.
  final DateTime addedAt;

  /// Whether the user has opened this item at least once. Display state only
  /// — not a claim, not an expiry, not a precondition for anything.
  final bool seen;

  /// Returns a copy with [seen] set to the supplied value. Keeps the type
  /// fully immutable.
  RewardInboxItem markSeen({required bool isSeen}) => isSeen == seen
      ? this
      : RewardInboxItem(id: id, event: event, addedAt: addedAt, seen: isSeen);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': rewardInboxItemSchemaVersion,
    'id': id,
    'addedAt': addedAt.toIso8601String(),
    'seen': seen,
    'event': _eventToJson(event),
  };

  factory RewardInboxItem.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    final addedAtRaw = json['addedAt'];
    final DateTime addedAt;
    if (addedAtRaw is String) {
      final parsed = DateTime.tryParse(addedAtRaw);
      if (parsed == null) {
        throw ArgumentError.value(addedAtRaw, 'addedAt', 'must be ISO 8601');
      }
      addedAt = parsed;
    } else {
      throw ArgumentError.value(addedAtRaw, 'addedAt', 'must be a string');
    }
    final seenRaw = json['seen'];
    if (seenRaw is! bool) {
      throw ArgumentError.value(seenRaw, 'seen', 'must be a boolean');
    }
    final eventJson = json['event'];
    return RewardInboxItem(
      id: _requireString(json, 'id'),
      addedAt: addedAt,
      seen: seenRaw,
      event: _eventFromJson(eventJson),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RewardInboxItem &&
          id == other.id &&
          event == other.event &&
          addedAt == other.addedAt &&
          seen == other.seen;

  @override
  int get hashCode => Object.hash(id, event, addedAt, seen);
}

/// Current persistence schema for [RewardInboxItem]. Bumped when the
/// serialized shape changes.
const int rewardInboxItemSchemaVersion = 1;

/// Index used to sort rewards by priority. Higher index = higher priority
/// (renders first inside a consolidated summary). Exposed for the coordinator
/// and its tests.
int rewardPriorityIndex(RewardKind kind) => switch (kind) {
  RewardKind.dailyReward => 0,
  RewardKind.questCompleted => 1,
  RewardKind.challengeCompleted => 1,
  RewardKind.levelUp => 2,
  RewardKind.masteryMilestone => 3,
};

Map<String, Object?> _eventToJson(RewardEvent event) => <String, Object?>{
  'id': event.id,
  'kind': event.kind.name,
  'titleKey': event.titleKey,
  'bodyKey': event.bodyKey,
  'earnedXp': event.earnedXp,
  'earnedAt': event.earnedAt.toIso8601String(),
  'sourceLedgerId': event.sourceLedgerId,
  'crossedLevelNumbers': <int>[...event.crossedLevelNumbers],
};

RewardEvent _eventFromJson(Object? json) {
  if (json is! Map<String, Object?>) {
    throw ArgumentError.value(json, 'event', 'must be an object');
  }
  final kindRaw = json['kind'];
  if (kindRaw is! String) {
    throw ArgumentError.value(kindRaw, 'kind', 'must be a string');
  }
  final kind = RewardKind.values.byName(kindRaw);
  final earnedAtRaw = json['earnedAt'];
  final DateTime earnedAt;
  if (earnedAtRaw is String) {
    final parsed = DateTime.tryParse(earnedAtRaw);
    if (parsed == null) {
      throw ArgumentError.value(earnedAtRaw, 'earnedAt', 'must be ISO 8601');
    }
    earnedAt = parsed;
  } else {
    throw ArgumentError.value(earnedAtRaw, 'earnedAt', 'must be a string');
  }
  final crossedRaw = json['crossedLevelNumbers'];
  if (crossedRaw is! List<Object?>) {
    throw ArgumentError.value(
      crossedRaw,
      'crossedLevelNumbers',
      'must be a list',
    );
  }
  return RewardEvent(
    id: _requireString(json, 'id'),
    kind: kind,
    titleKey: _requireString(json, 'titleKey'),
    bodyKey: _requireString(json, 'bodyKey'),
    earnedXp: _requireInt(json, 'earnedXp'),
    earnedAt: earnedAt,
    sourceLedgerId: _requireString(json, 'sourceLedgerId'),
    crossedLevelNumbers: <int>[
      for (final value in crossedRaw)
        if (value is int)
          value
        else
          throw ArgumentError.value(
            value,
            'crossedLevelNumbers',
            'must contain only ints',
          ),
    ],
  );
}

String _requireString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be a string');
}

int _requireInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer');
}

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
