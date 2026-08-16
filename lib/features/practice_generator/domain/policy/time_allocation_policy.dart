/// Versioned, deterministic configuration for the [TimeBudgetAllocator]
/// (ADR 0298, SDD Ch8 Kör 14).
///
/// The policy encodes the floor-rounding increment, the minimum block
/// length, the primary-focus minimum guarantee, the micro-plan threshold,
/// and the per-band reserve fragments. It never reads a clock and never
/// generates randomness. Every value is validated at construction and
/// exposed as an immutable field so a generated allocation can retain the
/// exact policy provenance after the values are tuned.
library;

import '../model/plan_enums.dart';

/// The slot shape a plan template expects for a given total budget.
///
/// Each template fixes the ordered [BlockKind] list and the per-slot minimum
/// in minutes. The allocator reserves fixed minutes for setup, reflection,
/// and the rest between adjacent blocks, then fills the remaining
/// active-playing minutes into these slots with floor-rounding and
/// exact-budget repair (ADR 0298 decision 2).
final class PlanTemplate {
  const PlanTemplate({
    required this.orderedKinds,
    required this.minimums,
    required this.setupMinutes,
    required this.reflectionMinutes,
    required this.restPerGapMinutes,
  });

  /// The ordered list of active-playing slot kinds. The first entry is
  /// treated as the primary focus for the minimum-guarantee policy.
  final List<BlockKind> orderedKinds;

  /// Per-slot minimum minutes, in the same order as [orderedKinds]. The
  /// list must have the same length as [orderedKinds].
  final List<int> minimums;

  /// Setup reserve minutes (instrument tuning, mic check, etc.).
  final int setupMinutes;

  /// Reflection reserve minutes.
  final int reflectionMinutes;

  /// Rest minutes between adjacent active-playing blocks.
  final int restPerGapMinutes;

  /// Number of rest gaps (one less than the number of active-playing slots).
  int get restGapCount => orderedKinds.length - 1;
}

/// Versioned, deterministic configuration for the [TimeBudgetAllocator]
/// (ADR 0298, SDD Ch8 Kör 14).
final class TimeAllocationPolicy {
  TimeAllocationPolicy({
    String version = 'time-allocation-policy-v1',
    Duration roundingIncrement = const Duration(minutes: 1),
    Duration minimumBlockLength = const Duration(minutes: 1),
    int primaryMinimumMinutes = 3,
    Duration microPlanThreshold = const Duration(minutes: 5),
    Duration ceilingMinutes = const Duration(minutes: 90),
  }) : version = _requireText(version, 'version'),
       roundingIncrement = _requirePositiveDuration(
         roundingIncrement,
         'roundingIncrement',
       ),
       minimumBlockLength = _requirePositiveDuration(
         minimumBlockLength,
         'minimumBlockLength',
       ),
       primaryMinimumMinutes = _requirePositiveInt(
         primaryMinimumMinutes,
         'primaryMinimumMinutes',
       ),
       microPlanThreshold = _requirePositiveDuration(
         microPlanThreshold,
         'microPlanThreshold',
       ),
       ceilingMinutes = _requirePositiveDuration(
         ceilingMinutes,
         'ceilingMinutes',
       ) {
    if (roundingIncrement > minimumBlockLength) {
      throw ArgumentError.value(
        roundingIncrement,
        'roundingIncrement',
        'must not exceed minimumBlockLength ($minimumBlockLength)',
      );
    }
  }

  /// Stable identifier retained by [TimeBudgetAllocator] as allocation
  /// provenance (ADR 0298 §5).
  final String version;

  /// The floor-rounding step applied to every planned block. The default
  /// `1 minute` matches the day's whole-minute granularity (ADR 0298 §2).
  final Duration roundingIncrement;

  /// The shortest block length the allocator will emit. Anything below
  /// this threshold is dropped (its minutes refund to the primary focus).
  final Duration minimumBlockLength;

  /// The minimum time the primary focus is guaranteed to receive when
  /// active-playing is non-empty (ADR 0298 §4, brief §5.4).
  final int primaryMinimumMinutes;

  /// The daily total below which the allocator switches to the micro-plan
  /// path: exactly one primary focus block, no reserves (ADR 0298 §3,
  /// brief §5.5).
  final Duration microPlanThreshold;

  /// The planned upper bound for any single day. Tomorrow's larger plans
  /// grow beyond it via repetition, not by extending a single day.
  final Duration ceilingMinutes;

  /// The micro-plan template — exactly one primary focus block, no reserves.
  static const PlanTemplate microTemplate = PlanTemplate(
    orderedKinds: <BlockKind>[BlockKind.primaryFocus],
    minimums: <int>[1],
    setupMinutes: 0,
    reflectionMinutes: 0,
    restPerGapMinutes: 0,
  );

  /// The small template — single primary focus block, setup + reflection.
  /// Active total between 6 and 12 minutes.
  static const PlanTemplate smallTemplate = PlanTemplate(
    orderedKinds: <BlockKind>[BlockKind.primaryFocus],
    minimums: <int>[1],
    setupMinutes: 1,
    reflectionMinutes: 1,
    restPerGapMinutes: 0,
  );

  /// The medium template — warmup + primary + secondary, short reserves.
  /// Active total between 13 and 30 minutes.
  static const PlanTemplate mediumTemplate = PlanTemplate(
    orderedKinds: <BlockKind>[
      BlockKind.warmup,
      BlockKind.primaryFocus,
      BlockKind.secondaryFocus,
    ],
    minimums: <int>[1, 3, 1],
    setupMinutes: 1,
    reflectionMinutes: 1,
    restPerGapMinutes: 1,
  );

  /// The large template — warmup + primary + secondary + maintenance,
  /// generous reserves.
  /// Active total between 31 and 60 minutes.
  static const PlanTemplate largeTemplate = PlanTemplate(
    orderedKinds: <BlockKind>[
      BlockKind.warmup,
      BlockKind.primaryFocus,
      BlockKind.secondaryFocus,
      BlockKind.maintenance,
    ],
    minimums: <int>[2, 5, 3, 2],
    setupMinutes: 2,
    reflectionMinutes: 2,
    restPerGapMinutes: 1,
  );

  /// The extra-large template — same shape as the large template plus a
  /// song block, with the same per-gap rest length.
  /// Active total above 60 minutes.
  static const PlanTemplate extraLargeTemplate = PlanTemplate(
    orderedKinds: <BlockKind>[
      BlockKind.warmup,
      BlockKind.primaryFocus,
      BlockKind.secondaryFocus,
      BlockKind.maintenance,
      BlockKind.song,
    ],
    minimums: <int>[2, 5, 3, 2, 2],
    setupMinutes: 2,
    reflectionMinutes: 2,
    restPerGapMinutes: 1,
  );

  /// Default policy for the day-allocation contract (ADR 0298 §5).
  static final TimeAllocationPolicy defaultPolicy = TimeAllocationPolicy(
    version: 'time-allocation-policy-v1',
    roundingIncrement: const Duration(minutes: 1),
    minimumBlockLength: const Duration(minutes: 1),
    primaryMinimumMinutes: 3,
    microPlanThreshold: const Duration(minutes: 5),
    ceilingMinutes: const Duration(minutes: 90),
  );

  /// Pick the template that fits a total elapsed budget. The cutoff points
  /// match the brief's §A2 reference frames (5/10/20/45/90 minutes).
  PlanTemplate templateFor(Duration totalElapsed) {
    final minutes = totalElapsed.inMinutes;
    if (minutes <= microPlanThreshold.inMinutes) return microTemplate;
    if (minutes <= 12) return smallTemplate;
    if (minutes <= 30) return mediumTemplate;
    if (minutes <= 60) return largeTemplate;
    return extraLargeTemplate;
  }
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

Duration _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}

int _requirePositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}
