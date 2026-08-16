/// The five typed amounts that make up one day of practice time
/// (SDD Ch8 §21.1, ADR 0298 decision 1).
///
/// A valid `TimeBudget` always satisfies
/// `elapsedSession == activePlaying + rest + setup + reflection`, and the
/// list of `segments` accounts for the entire `activePlaying` portion. The
/// `warmup` kind lives inside `activePlaying` — it is not a sixth budget
/// category (ADR 0298 decision 1).
library;

import 'plan_enums.dart';

/// One planned active-playing segment within a [TimeBudget].
///
/// The kind is restricted to the active-playing categories declared by the
/// generated-plan contract (SDD Ch8 §16.4, `BlockKind`): [BlockKind.warmup],
/// [BlockKind.primaryFocus], [BlockKind.secondaryFocus],
/// [BlockKind.maintenance], [BlockKind.song]. Reserves ([BlockKind.rest],
/// [BlockKind.cooldown], [BlockKind.reflection]) are not active-playing
/// segments and are tracked by the typed fields on [TimeBudget].
final class PlannedActiveSegment {
  PlannedActiveSegment({required BlockKind kind, required Duration duration})
    : kind = _requireActiveKind(kind),
      duration = _requireNonNegativeDuration(duration, 'duration');

  final BlockKind kind;
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlannedActiveSegment &&
          other.kind == kind &&
          other.duration == duration;

  @override
  int get hashCode => Object.hash(kind, duration);

  @override
  String toString() => 'PlannedActiveSegment(${kind.code}, $duration)';
}

/// The five typed amounts that make up one day of practice time
/// (SDD Ch8 §21.1, ADR 0298 decision 1).
///
/// Sum invariant: `elapsedSession == activePlaying + rest + setup +
/// reflection`. The `segments` list, when present, accounts for the entire
/// `activePlaying` portion — the allocator reparents any rounding remainder
/// so the sum is exact, not approximate (ADR 0298 decision 2).
final class TimeBudget {
  TimeBudget({
    required Duration activePlaying,
    required Duration rest,
    required Duration setup,
    required Duration reflection,
    Iterable<PlannedActiveSegment>? segments,
  }) : activePlaying = _requireNonNegativeDuration(
         activePlaying,
         'activePlaying',
       ),
       rest = _requireNonNegativeDuration(rest, 'rest'),
       setup = _requireNonNegativeDuration(setup, 'setup'),
       reflection = _requireNonNegativeDuration(reflection, 'reflection'),
       segments = List<PlannedActiveSegment>.unmodifiable(
         segments ?? const <PlannedActiveSegment>[],
       ) {
    final elapsed = activePlaying + rest + setup + reflection;
    if (elapsed <= Duration.zero) {
      throw ArgumentError.value(
        elapsed,
        'elapsedSession',
        'must be positive (no zero-minute day)',
      );
    }
    if (this.segments.isNotEmpty) {
      var sum = Duration.zero;
      for (final segment in this.segments) {
        sum += segment.duration;
      }
      if (sum != activePlaying) {
        throw ArgumentError.value(
          sum,
          'segments',
          'must sum to activePlaying ($activePlaying) but sums to $sum',
        );
      }
    }
  }

  final Duration activePlaying;
  final Duration rest;
  final Duration setup;
  final Duration reflection;
  final List<PlannedActiveSegment> segments;

  /// The total session wall-clock time including every typed reserve
  /// (ADR 0298 decision 1).
  Duration get elapsedSession => activePlaying + rest + setup + reflection;

  /// Whether the planned segments account for the entire active-playing
  /// portion. When `false` the budget carries only the typed totals.
  bool get hasSegments => segments.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeBudget &&
          other.activePlaying == activePlaying &&
          other.rest == rest &&
          other.setup == setup &&
          other.reflection == reflection &&
          _sameList(other.segments, segments);

  @override
  int get hashCode => Object.hash(
    activePlaying,
    rest,
    setup,
    reflection,
    Object.hashAll(segments),
  );
}

Duration _requireNonNegativeDuration(Duration value, String name) {
  if (value.isNegative) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
  return value;
}

BlockKind _requireActiveKind(BlockKind kind) {
  switch (kind) {
    case BlockKind.warmup:
    case BlockKind.primaryFocus:
    case BlockKind.secondaryFocus:
    case BlockKind.maintenance:
    case BlockKind.song:
      return kind;
    case BlockKind.readiness:
    case BlockKind.assessment:
    case BlockKind.freePlay:
    case BlockKind.reflection:
    case BlockKind.rest:
    case BlockKind.cooldown:
      throw ArgumentError.value(
        kind.code,
        'kind',
        'is not an active-playing segment — use a typed reserve field',
      );
  }
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
