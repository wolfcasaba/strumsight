import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/core/music/chord.dart';

import '../../domain/target/analysis_target.dart';
import '../../domain/target/expected_event.dart';

/// One Song-owned reference point captured as an Analysis-owned snapshot.
final class SongReferenceEvent {
  SongReferenceEvent({
    required this.id,
    required this.time,
    this.displayMidi,
    this.displayChord,
  }) {
    if (id.trim().isEmpty || time.isNegative) {
      throw ArgumentError('Song reference event must have an id and time.');
    }
    if (displayMidi == null && displayChord == null) {
      throw ArgumentError('A song reference event needs a note or chord.');
    }
    if (displayMidi != null && (displayMidi! < 0 || displayMidi! > 127)) {
      throw ArgumentError.value(displayMidi, 'displayMidi');
    }
  }

  final String id;
  final Duration time;
  final int? displayMidi;
  final String? displayChord;
}

/// Minimal Song input until Song Trainer publishes a domain contract (OD-01).
final class SongReferenceSnapshot {
  SongReferenceSnapshot({
    required this.documentId,
    required this.documentVersion,
    required this.sectionId,
    required List<Duration> beatGrid,
    required List<SongReferenceEvent> events,
    this.backingOffset = Duration.zero,
    this.playbackSpeed = 1,
    this.capo = 0,
    this.transposition = 0,
  }) : beatGrid = List<Duration>.unmodifiable(beatGrid),
       events = List<SongReferenceEvent>.unmodifiable(events) {
    if (documentId.trim().isEmpty || sectionId.trim().isEmpty) {
      throw ArgumentError('Song document and section IDs must be non-empty.');
    }
    if (documentVersion <= 0 ||
        backingOffset.isNegative ||
        !playbackSpeed.isFinite ||
        playbackSpeed <= 0 ||
        capo < 0) {
      throw ArgumentError('Invalid Song reference timing or version.');
    }
  }

  final String documentId;
  final int documentVersion;
  final String sectionId;
  final List<Duration> beatGrid;
  final List<SongReferenceEvent> events;
  final Duration backingOffset;
  final double playbackSpeed;
  final int capo;
  final int transposition;
}

/// Preserves the display value while putting the concert value into Analysis.
final class SongPitchContext {
  const SongPitchContext({
    required this.displayMidi,
    required this.concertMidi,
  });

  final int displayMidi;
  final int concertMidi;
}

final class SongAnalysisTarget {
  SongAnalysisTarget({
    required this.target,
    required List<SongPitchContext> pitches,
  }) : pitches = List<SongPitchContext>.unmodifiable(pitches);

  final AnalysisTarget target;
  final List<SongPitchContext> pitches;
}

/// Converts an OD-01 reference snapshot into a media-time Analysis target.
final class SongAnalysisAdapter {
  const SongAnalysisAdapter();

  SongAnalysisTarget toAnalysisTarget(SongReferenceSnapshot snapshot) {
    final pitches = <SongPitchContext>[];
    final expectedEvents = <ExpectedEvent>[];
    final expectedNotes = <int>[];
    final expectedChords = <String>[];

    for (final event in snapshot.events) {
      final time = _toAnalysisTime(event.time, snapshot);
      if (event.displayMidi case final displayMidi?) {
        final display = displayMidi + snapshot.transposition;
        final concert = display + snapshot.capo;
        if (display < 0 || display > 127 || concert < 0 || concert > 127) {
          throw ArgumentError.value(
            displayMidi,
            'displayMidi',
            'out of MIDI range',
          );
        }
        pitches.add(
          SongPitchContext(displayMidi: display, concertMidi: concert),
        );
        expectedNotes.add(concert);
        expectedEvents.add(
          ExpectedEvent(
            id: 'song:${event.id}:note',
            time: time,
            type: ExpectedEventType.noteOnset,
          ),
        );
      }
      if (event.displayChord case final displayChord?) {
        final display = Chord(
          displayChord,
        ).transposed(snapshot.transposition).label;
        final concert = Chord(display).transposed(snapshot.capo).label;
        expectedChords.add(concert);
        expectedEvents.add(
          ExpectedEvent(
            id: 'song:${event.id}:chord',
            time: time,
            type: ExpectedEventType.chordChange,
          ),
        );
      }
    }

    final beatEvents = <ExpectedEvent>[
      for (final (index, beat) in snapshot.beatGrid.indexed)
        ExpectedEvent(
          id: 'song:beat:$index',
          time: _toAnalysisTime(beat, snapshot),
          type: ExpectedEventType.beat,
        ),
    ];
    final allEvents = <ExpectedEvent>[...expectedEvents, ...beatEvents]
      ..sort((left, right) => left.time.compareTo(right.time));
    return SongAnalysisTarget(
      target: AnalysisTarget(
        id: snapshot.documentId,
        targetVersion: snapshot.documentVersion,
        kind: AnalysisTargetKind.song,
        timebase: AnalysisTargetTimebase.media,
        expectedEvents: allEvents,
        expectedChords: expectedChords,
        expectedNotes: expectedNotes,
        sections: <AnalysisTargetSection>[
          AnalysisTargetSection(
            id: snapshot.sectionId,
            start: Duration.zero,
            end: allEvents.isEmpty ? Duration.zero : allEvents.last.time,
          ),
        ],
      ),
      pitches: pitches,
    );
  }

  Duration _toAnalysisTime(Duration source, SongReferenceSnapshot snapshot) {
    final scaledMicroseconds = (source.inMicroseconds / snapshot.playbackSpeed)
        .round();
    return snapshot.backingOffset + Duration(microseconds: scaledMicroseconds);
  }
}

abstract interface class SongAnalysisAdapterFactory {
  SongAnalysisAdapter create();
}

final class _DefaultSongAnalysisAdapterFactory
    implements SongAnalysisAdapterFactory {
  const _DefaultSongAnalysisAdapterFactory();

  @override
  SongAnalysisAdapter create() => const SongAnalysisAdapter();
}

final songAnalysisAdapterFactoryProvider = Provider<SongAnalysisAdapterFactory>(
  (_) => const _DefaultSongAnalysisAdapterFactory(),
);

/// Song snapshots are dormant with the Practice integration flag OFF.
final songAnalysisAdapterProvider = Provider<SongAnalysisAdapter?>((ref) {
  if (!ref.watch(appConfigProvider).flags.analysisPracticeIntegrationEnabled) {
    return null;
  }
  return ref.watch(songAnalysisAdapterFactoryProvider).create();
});
