import 'package:flutter/foundation.dart';

import '../../learn/model/lesson.dart';
import '../../live/model/strum.dart';

/// A user-created song: a chord-per-bar progression + a repeating 8-slot strum
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
  });

  final String id;
  final String name;

  /// One chord label per bar, in play order.
  final List<String> chords;

  /// An 8-slot (eighth-note) strum pattern; `null` = a rest on that slot.
  final List<StrumDirection?> pattern;

  final int bpm;

  Song copyWith({
    String? name,
    List<String>? chords,
    List<StrumDirection?>? pattern,
    int? bpm,
  }) =>
      Song(
        id: id,
        name: name ?? this.name,
        chords: chords ?? this.chords,
        pattern: pattern ?? this.pattern,
        bpm: bpm ?? this.bpm,
      );

  /// A playable/scorable lesson (Learn engine + live scoring feed the streak +
  /// Progress dashboard just like a built-in lesson).
  Lesson toLesson() => Lesson(
        id: 'song_$id',
        name: name,
        bpm: bpm.toDouble(),
        chords: chords,
        pattern: pattern,
      );

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
      };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'] as String,
        name: j['name'] as String,
        chords: (j['chords'] as List).map((e) => e as String).toList(),
        pattern:
            (j['pat'] as String).split('').map(Song._unslot).toList(),
        bpm: (j['bpm'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is Song &&
      other.id == id &&
      other.name == name &&
      listEquals(other.chords, chords) &&
      listEquals(other.pattern, pattern) &&
      other.bpm == bpm;

  @override
  int get hashCode =>
      Object.hash(id, name, Object.hashAll(chords), Object.hashAll(pattern), bpm);
}
