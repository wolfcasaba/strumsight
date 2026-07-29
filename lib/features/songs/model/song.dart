import 'package:flutter/foundation.dart';

import '../../../core/foundation/json_validation.dart';
import '../../analyze/model/analyze_result.dart';
import '../../learn/model/lesson.dart';
import '../../live/model/strum.dart';

/// Bound on a persisted song's progression (Kör 7 §7.1). Generous next to any
/// authored song — it exists to reject a corrupt record, not to limit writing.
const int maxSongBars = 512;

/// A user-created song: a chord-per-bar progression + a repeating strum
/// pattern (the ↓/↑ hand — our moat, now author-able) + a tempo. Persisted
/// locally; playable/scorable by turning it into a [Lesson] via [toLesson].
@immutable
class Song {
  const Song({
    required this.id,
    required this.name,
    required this.chords,
    required this.pattern,
    required this.bpm,
    this.beatsPerBar = 4,
  });

  final String id;
  final String name;

  /// One chord label per bar, in play order.
  final List<String> chords;

  /// An eighth-note strum pattern spanning ONE bar ([beatsPerBar] × 2 slots —
  /// 8 in 4/4, 6 in 3/4); `null` = a rest on that slot.
  final List<StrumDirection?> pattern;

  final int bpm;

  /// The song's metre (round 116 — the builder can author a 3/4 waltz).
  final int beatsPerBar;

  Song copyWith({
    String? name,
    List<String>? chords,
    List<StrumDirection?>? pattern,
    int? bpm,
    int? beatsPerBar,
  }) => Song(
    id: id,
    name: name ?? this.name,
    chords: chords ?? this.chords,
    pattern: pattern ?? this.pattern,
    bpm: bpm ?? this.bpm,
    beatsPerBar: beatsPerBar ?? this.beatsPerBar,
  );

  /// A playable/scorable lesson (Learn engine + live scoring feed the streak +
  /// Progress dashboard just like a built-in lesson).
  Lesson toLesson() => Lesson(
    id: 'song_$id',
    name: name,
    bpm: bpm.toDouble(),
    chords: chords,
    pattern: pattern,
    beatsPerBar: beatsPerBar,
  );

  /// A synthetic [AnalyzeResult] for this song so it can flow through the whole
  /// share pipeline (Strum Card + Strum Reel) exactly like a recorded clip —
  /// the chords + ↓/↑ pattern become a shareable, moat-showcasing post.
  AnalyzeResult toAnalyzeResult() {
    final spb = bpm > 0 ? 60.0 / bpm : 0.5;
    final strums = [
      for (final e in toLesson().events)
        TimelineStrum(
          direction: e.direction,
          timeSec: e.beat * spb,
          confidence: 1,
        ),
    ];
    final timeline = [
      for (var bar = 0; bar < chords.length; bar++)
        TimelineChord(
          label: chords[bar],
          startSec: bar * beatsPerBar * spb,
          endSec: (bar + 1) * beatsPerBar * spb,
        ),
    ];
    return AnalyzeResult(
      durationSec: chords.length * beatsPerBar * spb,
      bpm: bpm.toDouble(),
      chords: timeline,
      strums: strums,
      beatsPerBar: beatsPerBar,
    );
  }

  static String _slot(StrumDirection? d) => switch (d) {
    StrumDirection.down => 'd',
    StrumDirection.up => 'u',
    null => '-',
  };

  static StrumDirection? _unslot(String s) => switch (s) {
    'd' => StrumDirection.down,
    'u' => StrumDirection.up,
    _ => null,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'chords': chords,
    'pat': pattern.map(_slot).join(),
    'bpm': bpm,
    'bpb': beatsPerBar,
  };

  factory Song.fromJson(Map<String, dynamic> j) {
    // Records saved before round 116 are all 4/4.
    final beatsPerBar = optionalInt(j, 'bpb', fallback: 4, min: 1, max: 16);
    final pattern = requireString(
      j,
      'pat',
      allowEmpty: true,
      maxLength: maxSongBars,
    ).split('').map(Song._unslot).toList();
    return Song(
      id: requireString(j, 'id'),
      // A song the user never named is still the user's song.
      name: requireString(j, 'name', allowEmpty: true),
      // A bar with no chord label would render as a blank cell and score as
      // nothing — the record is rejected instead (§7.1).
      chords: requireStringList(j, 'chords', maxLength: maxSongBars),
      // A corrupt/hand-edited record could carry a pattern whose length
      // doesn't match the metre; the release build has no assert to catch it,
      // and a mismatch would spill slots into the next bar (round 130, R1). Fit
      // the pattern to exactly beatsPerBar*2 slots (truncate / pad with rests).
      pattern: _fitToMeter(pattern, beatsPerBar),
      bpm: requireInt(j, 'bpm', min: 1, max: 400),
      beatsPerBar: beatsPerBar,
    );
  }

  /// Force [pattern] to exactly `beatsPerBar * 2` slots — the one-bar contract
  /// [Lesson._expand] relies on. Longer is truncated, shorter is rest-padded.
  static List<StrumDirection?> _fitToMeter(
    List<StrumDirection?> pattern,
    int beatsPerBar,
  ) {
    final want = beatsPerBar * 2;
    if (pattern.length == want) return pattern;
    return [
      for (var i = 0; i < want; i++) i < pattern.length ? pattern[i] : null,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is Song &&
      other.id == id &&
      other.name == name &&
      listEquals(other.chords, chords) &&
      listEquals(other.pattern, pattern) &&
      other.bpm == bpm &&
      other.beatsPerBar == beatsPerBar;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(chords),
    Object.hashAll(pattern),
    bpm,
    beatsPerBar,
  );
}
