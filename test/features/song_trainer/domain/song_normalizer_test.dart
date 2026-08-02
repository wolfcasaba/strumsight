import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

void main() {
  const normalizer = SongNormalizer();

  group('SongNormalizer — idempotence (acceptance criterion)', () {
    test(
      'normalize(normalize(x)) == normalize(x) on a track-shuffled document',
      () {
        final shuffled = _sample(
          tracks: <SongTrack>[
            StrumTrack(
              id: SongTrackId('s-1'),
              name: 'Strum',
              instrument: SongInstrument(name: 'Guitar'),
              events: <SongStrumEvent>[
                SongStrumEvent(
                  id: SongEventId('s-b'),
                  at: const Duration(milliseconds: 500),
                  direction: StrumDirection.down,
                ),
                SongStrumEvent(
                  id: SongEventId('s-a'),
                  at: Duration.zero,
                  direction: StrumDirection.up,
                ),
              ],
            ),
            ChordTrack(
              id: SongTrackId('c-1'),
              name: 'Chords',
              instrument: SongInstrument(name: 'Guitar'),
              events: <SongChordEvent>[
                SongChordEvent(
                  id: SongEventId('e-2'),
                  start: const Duration(seconds: 4),
                  duration: const Duration(seconds: 4),
                  symbol: const Chord('G'),
                ),
                SongChordEvent(
                  id: SongEventId('e-1'),
                  start: Duration.zero,
                  duration: const Duration(seconds: 4),
                  symbol: const Chord('C'),
                ),
              ],
            ),
          ],
        );

        final once = normalizer.normalize(shuffled);
        final twice = normalizer.normalize(once);
        expect(twice, equals(once));
        expect(twice.hashCode, once.hashCode);
      },
    );

    test('normalize is a no-op for a document already in canonical order', () {
      final canonical = _sample(
        tracks: <SongTrack>[
          ChordTrack(
            id: SongTrackId('c-1'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('e-1'),
                start: Duration.zero,
                duration: const Duration(seconds: 4),
                symbol: const Chord('C'),
              ),
            ],
          ),
        ],
        sections: <SongSection>[
          SongSection(
            id: SongSectionId('intro'),
            name: 'Intro',
            startMeasure: 0,
            endMeasureExclusive: 2,
          ),
        ],
        measures: <SongMeasure>[
          SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
          SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
        ],
        markers: <SongMarker>[
          SongMarker(SongMarkerId('m1'), 'Intro', 0, SongMarkerKind.note),
        ],
      );
      final normalized = normalizer.normalize(canonical);
      expect(normalized.tracks, equals(canonical.tracks));
      expect(normalized.sections, equals(canonical.sections));
      expect(normalized.measures, equals(canonical.measures));
      expect(normalized.markers, equals(canonical.markers));
    });

    test('preserves every original ID — no IDs are rewritten', () {
      final document = _sample(
        tracks: <SongTrack>[
          ChordTrack(
            id: SongTrackId('c-1'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('e-2'),
                start: const Duration(seconds: 4),
                duration: const Duration(seconds: 4),
                symbol: const Chord('G'),
              ),
              SongChordEvent(
                id: SongEventId('e-1'),
                start: Duration.zero,
                duration: const Duration(seconds: 4),
                symbol: const Chord('C'),
              ),
            ],
          ),
        ],
      );
      final normalized = normalizer.normalize(document);
      final track = normalized.tracks.single as ChordTrack;
      expect(track.id, SongTrackId('c-1'));
      expect(track.events.map((e) => e.id.value).toList(), <String>[
        'e-1',
        'e-2',
      ]);
      expect(document.id, normalized.id);
    });
  });

  group('SongNormalizer — canonical ordering', () {
    test('tracks are sorted by (kind, track.id) — chord before strum', () {
      final document = _sample(
        tracks: <SongTrack>[
          StrumTrack(
            id: SongTrackId('a'),
            name: 'Strum',
            instrument: SongInstrument(name: 'Guitar'),
            events: const <SongStrumEvent>[],
          ),
          ChordTrack(
            id: SongTrackId('b'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: const <SongChordEvent>[],
          ),
        ],
      );
      final normalized = normalizer.normalize(document);
      expect(normalized.tracks[0], isA<ChordTrack>());
      expect(normalized.tracks[1], isA<StrumTrack>());
    });

    test('chord events are sorted by start, then id', () {
      final document = _sample(
        tracks: <SongTrack>[
          ChordTrack(
            id: SongTrackId('c-1'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('late'),
                start: const Duration(seconds: 8),
                duration: const Duration(seconds: 4),
                symbol: const Chord('F'),
              ),
              SongChordEvent(
                id: SongEventId('mid'),
                start: const Duration(seconds: 4),
                duration: const Duration(seconds: 4),
                symbol: const Chord('G'),
              ),
              SongChordEvent(
                id: SongEventId('start'),
                start: Duration.zero,
                duration: const Duration(seconds: 4),
                symbol: const Chord('C'),
              ),
            ],
          ),
        ],
      );
      final normalized = normalizer.normalize(document);
      final events = (normalized.tracks.single as ChordTrack).events;
      expect(events.map((e) => e.id.value).toList(), <String>[
        'start',
        'mid',
        'late',
      ]);
    });

    test('note events are sorted by start, then id', () {
      final document = _sample(
        tracks: <SongTrack>[
          NoteTrack(
            id: SongTrackId('n-1'),
            name: 'Lead',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongNoteEvent>[
              SongNoteEvent(
                id: SongEventId('late'),
                start: const Duration(milliseconds: 1000),
                duration: const Duration(milliseconds: 500),
                midiPitch: 64,
              ),
              SongNoteEvent(
                id: SongEventId('mid'),
                start: const Duration(milliseconds: 500),
                duration: const Duration(milliseconds: 500),
                midiPitch: 62,
              ),
              SongNoteEvent(
                id: SongEventId('start'),
                start: Duration.zero,
                duration: const Duration(milliseconds: 500),
                midiPitch: 60,
              ),
            ],
          ),
        ],
      );
      final normalized = normalizer.normalize(document);
      final events = (normalized.tracks.single as NoteTrack).events;
      expect(events.map((e) => e.id.value).toList(), <String>[
        'start',
        'mid',
        'late',
      ]);
    });

    test('sections are sorted by startMeasure, then id', () {
      final document = _sample(
        sections: <SongSection>[
          SongSection(
            id: SongSectionId('verse'),
            name: 'Verse',
            startMeasure: 8,
            endMeasureExclusive: 16,
          ),
          SongSection(
            id: SongSectionId('intro'),
            name: 'Intro',
            startMeasure: 0,
            endMeasureExclusive: 8,
          ),
        ],
        measures: List<SongMeasure>.generate(
          16,
          (i) =>
              SongMeasure(index: i, durationBeats: BeatPosition.fromBeats(4)),
        ),
      );
      final normalized = normalizer.normalize(document);
      expect(normalized.sections.map((s) => s.id.value).toList(), <String>[
        'intro',
        'verse',
      ]);
    });

    test('measures are sorted by index ascending', () {
      final document = _sample(
        measures: <SongMeasure>[
          SongMeasure(index: 2, durationBeats: BeatPosition.fromBeats(4)),
          SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
          SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
        ],
      );
      final normalized = normalizer.normalize(document);
      expect(normalized.measures.map((m) => m.index).toList(), <int>[0, 1, 2]);
    });

    test('markers are sorted by measureIndex, then id', () {
      final document = _sample(
        markers: <SongMarker>[
          SongMarker(SongMarkerId('m-late'), 'Late', 8, SongMarkerKind.note),
          SongMarker(SongMarkerId('m-mid'), 'Mid', 4, SongMarkerKind.note),
          SongMarker(SongMarkerId('m-start'), 'Start', 0, SongMarkerKind.note),
        ],
      );
      final normalized = normalizer.normalize(document);
      expect(normalized.markers.map((m) => m.id.value).toList(), <String>[
        'm-start',
        'm-mid',
        'm-late',
      ]);
    });
  });

  group('SongNormalizer — determinism over randomized inputs', () {
    test('producing two normalizations of the same shuffle is equal', () {
      final original = _sample(
        tracks: <SongTrack>[
          NoteTrack(
            id: SongTrackId('n-1'),
            name: 'Lead',
            instrument: SongInstrument(name: 'Guitar'),
            events: List<SongNoteEvent>.generate(
              5,
              (i) => SongNoteEvent(
                id: SongEventId('e-$i'),
                start: Duration(milliseconds: 100 * (4 - i)),
                duration: const Duration(milliseconds: 50),
                midiPitch: 60 + i,
              ),
            ),
          ),
          ChordTrack(
            id: SongTrackId('c-1'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: List<SongChordEvent>.generate(
              4,
              (i) => SongChordEvent(
                id: SongEventId('c-$i'),
                start: Duration(milliseconds: 200 * (3 - i)),
                duration: const Duration(milliseconds: 100),
                symbol: Chord(['C', 'G', 'Am', 'F'][i]),
              ),
            ),
          ),
        ],
      );
      final a = normalizer.normalize(original);
      final b = normalizer.normalize(a);
      expect(b, equals(a));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SongDocument _sample({
  List<SongTrack>? tracks,
  List<SongSection>? sections,
  List<SongMeasure>? measures,
  List<SongMarker>? markers,
}) {
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('song-001'),
    revision: 1,
    metadata: SongMetadata(title: 'Test'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'song.strum',
      sha256: 'a' * 64,
      importedAt: DateTime.utc(2026, 1, 1, 12),
      importerVersion: '1.0.0',
    ),
    tracks: tracks,
    sections: sections,
    measures: measures,
    markers: markers,
    createdAt: DateTime.utc(2026, 1, 1, 12),
    updatedAt: DateTime.utc(2026, 1, 2, 12),
  );
}
