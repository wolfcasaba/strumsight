import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Bounded, fixed-capacity, drop-oldest ring of shadow samples (E14-R23,
/// ADR 0548 D4).
///
/// The whole storage is allocated ONCE in the constructor and never grows:
/// [add] overwrites the oldest slot instead of appending. That is the
/// property the R22 performance guard measures — an unbounded `List` here
/// would turn "run the candidate model alongside production" into a memory
/// leak on a ten-minute session, which is exactly the failure mode SDD Ch14
/// Kör 22 asks about but cannot measure on this box.
///
/// [toList] is the only allocating operation, and it happens on READ (a Lab
/// snapshot), never on the recognition path.
class ShadowRingBuffer<T extends Object> {
  ShadowRingBuffer({this.capacity = defaultCapacity})
    : assert(capacity > 0, 'a shadow ring needs at least one slot'),
      _slots = List<T?>.filled(capacity, null);

  /// Default depth: roughly 8 s of emitted frames at the pipeline's ~15 Hz
  /// cadence. A REPORTING window size, not a DSP threshold.
  static const int defaultCapacity = 128;

  final int capacity;
  final List<T?> _slots;
  int _writeIndex = 0;
  int _length = 0;
  int _dropped = 0;

  /// How many samples are currently retained (never above [capacity]).
  int get length => _length;

  /// How many samples were overwritten because the ring was full. A non-zero
  /// value is normal and honest: it says the report is a WINDOW, not a total.
  int get dropped => _dropped;

  /// The allocated slot count — constant for the life of the ring. Public
  /// (not test-only) because the recorder reports it as part of its own
  /// allocation bound, and a test asserts it is unchanged after an arbitrary
  /// number of [add] calls.
  int get slotCount => _slots.length;

  void add(T value) {
    if (_length == capacity) _dropped++;
    _slots[_writeIndex] = value;
    _writeIndex = (_writeIndex + 1) % capacity;
    if (_length < capacity) _length++;
  }

  /// Oldest-first copy of the retained samples.
  List<T> toList() {
    if (_length == 0) return const [];
    final start = (_writeIndex - _length + capacity) % capacity;
    return <T>[
      for (var i = 0; i < _length; i++) _slots[(start + i) % capacity]!,
    ];
  }

  void clear() {
    for (var i = 0; i < capacity; i++) {
      _slots[i] = null;
    }
    _writeIndex = 0;
    _length = 0;
    _dropped = 0;
  }
}

/// How one shadow comparison came out. Closed on purpose: "the models
/// disagreed" and "one of them declined to answer" are different facts, and
/// collapsing them would let an abstention be reported as an agreement.
enum ShadowAgreement {
  /// Both sides produced a verdict and the verdicts match.
  agreed,

  /// Both sides produced a verdict and the verdicts differ.
  disagreed,

  /// The candidate declined (no-strum class, or a margin under the
  /// contract's uncertainty threshold) while production published one.
  candidateAbstained,

  /// Production published nothing for this event while the candidate did.
  productionAbstained,

  /// Neither side committed to a verdict.
  bothAbstained,
}

/// Verdict-latency histogram buckets. These are REPORTING bins, not gates:
/// nothing in the recognition path reads them, and no threshold is derived
/// from them. Boundaries follow SDD Ch14 §7's latency budget prose so a
/// report can be read against it without re-bucketing.
enum ShadowLatencyBucket {
  under20ms,
  under50ms,
  under100ms,
  under200ms,
  atLeast200ms,

  /// No usable latency: the producer did not stamp both clocks, or the
  /// difference was negative/non-finite. Never folded into a real bucket —
  /// an unknown latency must stay visibly unknown (ADR 0271).
  unknown;

  /// Buckets [seconds]; `null`, negative and non-finite values → [unknown].
  static ShadowLatencyBucket forSeconds(double? seconds) {
    if (seconds == null || !seconds.isFinite || seconds < 0) {
      return ShadowLatencyBucket.unknown;
    }
    final ms = seconds * 1000.0;
    if (ms < 20) return ShadowLatencyBucket.under20ms;
    if (ms < 50) return ShadowLatencyBucket.under50ms;
    if (ms < 100) return ShadowLatencyBucket.under100ms;
    if (ms < 200) return ShadowLatencyBucket.under200ms;
    return ShadowLatencyBucket.atLeast200ms;
  }
}

/// The quality half of a chord comparison class.
enum ShadowChordQuality {
  /// An explicit "no chord is sounding" verdict.
  noChord,

  /// The label carries a major third (majmin reduction).
  major,

  /// The label carries a minor third (majmin reduction).
  minor,

  /// The label exists but its ROOT could not be parsed. Deliberately NOT
  /// folded into [noChord]: "I could not read this label" and "there was no
  /// chord" are different findings, and merging them would silently inflate
  /// N.C. agreement.
  unknown,
}

/// One cell of the chord agreement matrix: a root pitch class plus a
/// majmin-reduced quality (E14-R26, ADR 0549 D3).
///
/// The class set is CLOSED (26 values), which is what keeps the confusion
/// matrix a fixed-size array rather than a map that grows with whatever
/// labels the two engines happen to emit.
@immutable
class ShadowChordClass {
  const ShadowChordClass._(this.rootIndex, this.quality);

  /// "No chord is sounding."
  static const ShadowChordClass noChord = ShadowChordClass._(
    -1,
    ShadowChordQuality.noChord,
  );

  /// "There was a label, but it is not one this taxonomy can read."
  static const ShadowChordClass unknown = ShadowChordClass._(
    -1,
    ShadowChordQuality.unknown,
  );

  /// 0..11 (C..B) for [ShadowChordQuality.major]/[ShadowChordQuality.minor],
  /// −1 for [ShadowChordQuality.noChord] and [ShadowChordQuality.unknown].
  final int rootIndex;

  final ShadowChordQuality quality;

  /// 1 (N.C.) + 1 (unknown) + 12 majors + 12 minors.
  static const int classCount = 26;

  static const List<String> _rootNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  /// Pitch classes, spelling-tolerant — mirrors `ml/chords/labels.py::PC`
  /// (and its Dart twin `MlChordDecoder`), pinned by a parity test cell
  /// rather than by an import: `features/live` must not depend on
  /// `features/analyze` (the dependency already runs the other way).
  static const Map<String, int> _pitchClasses = {
    'C': 0,
    'B#': 0,
    'C#': 1,
    'Db': 1,
    'D': 2,
    'D#': 3,
    'Eb': 3,
    'E': 4,
    'Fb': 4,
    'F': 5,
    'E#': 5,
    'F#': 6,
    'Gb': 6,
    'G': 7,
    'G#': 8,
    'Ab': 8,
    'A': 9,
    'A#': 10,
    'Bb': 10,
    'B': 11,
    'Cb': 11,
  };

  /// Dense index into the confusion matrix: 0 = N.C., 1 = unknown,
  /// 2..13 = majors, 14..25 = minors.
  int get index => switch (quality) {
    ShadowChordQuality.noChord => 0,
    ShadowChordQuality.unknown => 1,
    ShadowChordQuality.major => 2 + rootIndex,
    ShadowChordQuality.minor => 14 + rootIndex,
  };

  /// The canonical majmin label of this class (`N.C.`, `?`, `C`…`Bm`).
  String get label => switch (quality) {
    ShadowChordQuality.noChord => 'N.C.',
    ShadowChordQuality.unknown => '?',
    ShadowChordQuality.major => _rootNames[rootIndex],
    ShadowChordQuality.minor => '${_rootNames[rootIndex]}m',
  };

  /// Parses any chord label into a class.
  ///
  /// `null`, empty and the no-chord spellings map to [noChord]; a label with
  /// an unreadable root maps to [unknown] (NOT to [noChord]); everything else
  /// is majmin-reduced exactly like `ml/chords/labels.py::to_majmin_class`.
  static ShadowChordClass parse(String? label) {
    if (label == null) return noChord;
    final s = label.trim();
    if (s.isEmpty || s == 'N.C.' || s == 'N' || s == 'NC' || s == 'X') {
      return noChord;
    }
    final String root;
    final String rest;
    if (s.length >= 2 && (s[1] == '#' || s[1] == 'b')) {
      root = s.substring(0, 2);
      rest = s.substring(2);
    } else {
      root = s.substring(0, 1);
      rest = s.substring(1);
    }
    final pc = _pitchClasses[root];
    if (pc == null) return unknown;
    return _isMinorThird(rest)
        ? ShadowChordClass._(pc, ShadowChordQuality.minor)
        : ShadowChordClass._(pc, ShadowChordQuality.major);
  }

  /// Mirrors `ml/chords/labels.py::_is_minor_third`.
  static bool _isMinorThird(String rest) {
    var r = rest.split('/').first;
    r = r.replaceFirst(RegExp(r'^[-: ]+'), '');
    final low = r.toLowerCase();
    if (low.startsWith('maj') ||
        (r.isNotEmpty && r[0] == 'M' && !low.startsWith('min'))) {
      return false;
    }
    if (low.startsWith('min') ||
        low.startsWith('dim') ||
        low.startsWith('o') ||
        low.contains('hdim')) {
      return true;
    }
    return low.startsWith('m');
  }

  @override
  bool operator ==(Object other) =>
      other is ShadowChordClass &&
      other.rootIndex == rootIndex &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(rootIndex, quality);

  @override
  String toString() => 'ShadowChordClass($label)';
}

/// One recorded strum comparison. Deliberately tiny and value-typed: this is
/// what fills the bounded ring, so anything heavy here would defeat the
/// bound.
@immutable
class StrumShadowSample {
  const StrumShadowSample({
    required this.onsetTimeSec,
    required this.production,
    required this.candidate,
    required this.agreement,
    required this.latency,
  });

  /// The onset the two verdicts refer to, on the engine's sample clock.
  final double onsetTimeSec;

  /// What production actually PUBLISHED for this onset (`down`/`up`), or
  /// `null` when it published nothing.
  final ShadowStrumVerdict? production;

  /// What the candidate model said, or `null` when it abstained.
  final ShadowStrumVerdict? candidate;

  final ShadowAgreement agreement;
  final ShadowLatencyBucket latency;

  Map<String, Object?> toJson() => <String, Object?>{
    'onsetTimeSec': onsetTimeSec,
    'production': production?.name,
    'candidate': candidate?.name,
    'agreement': agreement.name,
    'latency': latency.name,
  };
}

/// The two directions a strum verdict can take. A separate enum from
/// `StrumDirection` so the shadow record stays framework- and model-free.
enum ShadowStrumVerdict { down, up }

/// One recorded chord comparison.
@immutable
class ChordShadowSample {
  const ChordShadowSample({
    required this.timeSec,
    required this.production,
    required this.candidate,
    required this.agreement,
  });

  final double timeSec;
  final ShadowChordClass production;
  final ShadowChordClass candidate;
  final ShadowAgreement agreement;

  Map<String, Object?> toJson() => <String, Object?>{
    'timeSec': timeSec,
    'production': production.label,
    'candidate': candidate.label,
    'agreement': agreement.name,
  };
}

/// Aggregated strum-band shadow statistics for one session window.
@immutable
class StrumShadowAggregate {
  const StrumShadowAggregate({
    required this.observedFrames,
    required this.candidateVerdicts,
    required this.comparedVerdicts,
    required this.agreed,
    required this.disagreed,
    required this.candidateAbstained,
    required this.productionAbstained,
    required this.bothAbstained,
    required this.candidateUnavailableFrames,
    required this.latencyHistogram,
  });

  static const StrumShadowAggregate empty = StrumShadowAggregate(
    observedFrames: 0,
    candidateVerdicts: 0,
    comparedVerdicts: 0,
    agreed: 0,
    disagreed: 0,
    candidateAbstained: 0,
    productionAbstained: 0,
    bothAbstained: 0,
    candidateUnavailableFrames: 0,
    latencyHistogram: <ShadowLatencyBucket, int>{},
  );

  /// Emitted frames the observer saw (whether or not they carried a verdict).
  final int observedFrames;

  /// Distinct candidate verdicts seen (a verdict held across several frames
  /// counts ONCE).
  final int candidateVerdicts;

  /// Verdicts where BOTH sides committed, i.e. the denominator of
  /// [agreementRate].
  final int comparedVerdicts;

  final int agreed;
  final int disagreed;
  final int candidateAbstained;
  final int productionAbstained;
  final int bothAbstained;

  /// Frames on which the candidate model produced nothing at all — the
  /// heuristic strum path is running, so there is no model verdict to
  /// compare. Counted, never silently treated as an abstention.
  final int candidateUnavailableFrames;

  final Map<ShadowLatencyBucket, int> latencyHistogram;

  /// `null` when nothing was compared. NOT 0.0 and NOT 1.0: an empty window
  /// has no agreement rate, and reporting one would be a fabricated number
  /// (ADR 0271).
  double? get agreementRate =>
      comparedVerdicts == 0 ? null : agreed / comparedVerdicts;

  /// Share of candidate verdicts that declined to answer, or `null` when
  /// there were none.
  double? get candidateAbstentionRate => candidateVerdicts == 0
      ? null
      : (candidateAbstained + bothAbstained) / candidateVerdicts;

  Map<String, Object?> toJson() => <String, Object?>{
    'observedFrames': observedFrames,
    'candidateVerdicts': candidateVerdicts,
    'comparedVerdicts': comparedVerdicts,
    'agreed': agreed,
    'disagreed': disagreed,
    'candidateAbstained': candidateAbstained,
    'productionAbstained': productionAbstained,
    'bothAbstained': bothAbstained,
    'candidateUnavailableFrames': candidateUnavailableFrames,
    'agreementRate': agreementRate,
    'candidateAbstentionRate': candidateAbstentionRate,
    'latency': <String, int>{
      for (final entry in latencyHistogram.entries)
        entry.key.name: entry.value,
    },
  };
}

/// Aggregated chord-band shadow statistics, including the root/quality
/// agreement matrix (E14-R26).
@immutable
class ChordShadowAggregate {
  ChordShadowAggregate({
    required this.observedFrames,
    required this.comparedFrames,
    required this.exactAgreed,
    required this.rootAgreed,
    required this.qualityAgreed,
    required this.bothNoChord,
    required this.productionNoChordOnly,
    required this.candidateNoChordOnly,
    required this.candidateUnavailableFrames,
    required List<int> confusion,
  }) : _confusion = List<int>.unmodifiable(confusion);

  ChordShadowAggregate.empty()
    : observedFrames = 0,
      comparedFrames = 0,
      exactAgreed = 0,
      rootAgreed = 0,
      qualityAgreed = 0,
      bothNoChord = 0,
      productionNoChordOnly = 0,
      candidateNoChordOnly = 0,
      candidateUnavailableFrames = 0,
      _confusion = const <int>[];

  final int observedFrames;

  /// Frames where BOTH sides produced a class (N.C. counts as a class — a
  /// silence agreement is a real agreement).
  final int comparedFrames;

  final int exactAgreed;
  final int rootAgreed;
  final int qualityAgreed;
  final int bothNoChord;
  final int productionNoChordOnly;
  final int candidateNoChordOnly;

  /// Frames where the chord CRNN had no verdict yet (its analysis window had
  /// not filled, or it never activated).
  final int candidateUnavailableFrames;

  final List<int> _confusion;

  double? get exactAgreementRate =>
      comparedFrames == 0 ? null : exactAgreed / comparedFrames;

  double? get rootAgreementRate =>
      comparedFrames == 0 ? null : rootAgreed / comparedFrames;

  double? get qualityAgreementRate =>
      comparedFrames == 0 ? null : qualityAgreed / comparedFrames;

  /// How many frames had [production] on one axis and [candidate] on the
  /// other. 0 for an empty aggregate.
  int countFor(ShadowChordClass production, ShadowChordClass candidate) {
    if (_confusion.isEmpty) return 0;
    return _confusion[production.index * ShadowChordClass.classCount +
        candidate.index];
  }

  /// The non-zero cells only — a 26×26 dense matrix in a report would be
  /// 676 mostly-zero numbers.
  Map<String, int> get confusionCells {
    final out = <String, int>{};
    if (_confusion.isEmpty) return out;
    for (var p = 0; p < ShadowChordClass.classCount; p++) {
      for (var c = 0; c < ShadowChordClass.classCount; c++) {
        final n = _confusion[p * ShadowChordClass.classCount + c];
        if (n == 0) continue;
        out['${_labelForIndex(p)}->${_labelForIndex(c)}'] = n;
      }
    }
    return out;
  }

  static String _labelForIndex(int index) {
    if (index == 0) return ShadowChordClass.noChord.label;
    if (index == 1) return ShadowChordClass.unknown.label;
    if (index < 14) return ShadowChordClass._rootNames[index - 2];
    return '${ShadowChordClass._rootNames[index - 14]}m';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'observedFrames': observedFrames,
    'comparedFrames': comparedFrames,
    'exactAgreed': exactAgreed,
    'rootAgreed': rootAgreed,
    'qualityAgreed': qualityAgreed,
    'bothNoChord': bothNoChord,
    'productionNoChordOnly': productionNoChordOnly,
    'candidateNoChordOnly': candidateNoChordOnly,
    'candidateUnavailableFrames': candidateUnavailableFrames,
    'exactAgreementRate': exactAgreementRate,
    'rootAgreementRate': rootAgreementRate,
    'qualityAgreementRate': qualityAgreementRate,
    'confusion': confusionCells,
  };
}

/// A dense 26×26 counter, allocated once. Used by the recorder; lives here
/// so the matrix layout and its reader ([ChordShadowAggregate.countFor]) sit
/// in one file.
Int32List newChordConfusionMatrix() =>
    Int32List(ShadowChordClass.classCount * ShadowChordClass.classCount);
