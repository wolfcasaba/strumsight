import 'package:flutter/foundation.dart';

import '../../learn/model/lesson.dart';
import 'song.dart';

/// An ordered practice set of songs — a gig/practice-routine grouping. Stores
/// only song *ids*; the concrete songs are resolved from the songbook at play
/// time (so editing a song updates every setlist it's in).
@immutable
class Setlist {
  const Setlist({
    required this.id,
    required this.name,
    required this.songIds,
  });

  final String id;
  final String name;

  /// Songs in play order, by id (may reference a since-deleted song → skipped).
  final List<String> songIds;

  Setlist copyWith({String? name, List<String>? songIds}) => Setlist(
        id: id,
        name: name ?? this.name,
        songIds: songIds ?? this.songIds,
      );

  /// Resolve this setlist's ids to concrete [Song]s (order preserved, missing
  /// ids dropped) against the current songbook.
  List<Song> resolve(List<Song> library) {
    final byId = {for (final s in library) s.id: s};
    return [
      for (final id in songIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// Concatenate [songs] into ONE continuous, scorable [Lesson] that plays
  /// back-to-back through the normal Learn pipeline. The combined lesson has a
  /// single playback tempo (the first song's), but **each song keeps its own
  /// tempo**: a song's beats are time-warped by `refBpm / songBpm` so that, at
  /// the reference tempo, every song's events land at their true real-time
  /// positions. (A slower song's segment therefore spans more reference beats,
  /// a faster song's fewer.) The running offset accumulates each warped length.
  Lesson combine(List<Song> songs) {
    final refBpm = songs.isEmpty ? 90.0 : songs.first.bpm.toDouble();
    final events = <LessonEvent>[];
    var beatOffset = 0.0;
    for (final song in songs) {
      final lesson = song.toLesson();
      // Warp this song's beats to the reference tempo (1.0 for the first song).
      final warp = song.bpm <= 0 ? 1.0 : refBpm / song.bpm;
      for (final e in lesson.events) {
        events.add(LessonEvent(
          beat: e.beat * warp + beatOffset,
          chord: e.chord,
          direction: e.direction,
        ));
      }
      beatOffset += lesson.totalBeats * warp;
    }
    return Lesson.fromEvents(
      id: 'setlist_$id',
      name: name,
      bpm: refBpm,
      events: events,
      totalBeats: beatOffset,
    );
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'songs': songIds};

  factory Setlist.fromJson(Map<String, dynamic> j) => Setlist(
        id: j['id'] as String,
        name: j['name'] as String,
        songIds: (j['songs'] as List).map((e) => e as String).toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is Setlist &&
      other.id == id &&
      other.name == name &&
      listEquals(other.songIds, songIds);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(songIds));
}
