import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/music/tuning.dart';
import 'package:strumsight/features/song_trainer/data/local/song_document_codec.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_marker.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_note_technique.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';

const _codec = SongDocumentCodec();

void main() {
  const codec = _codec;

  group('SongDocumentCodec — track + event round-trip', () {
    test(
      'round-trips a ChordTrack with chord events including unsupported display',
      () {
        final document = _sampleDocument(
          tracks: <SongTrack>[
            ChordTrack(
              id: SongTrackId('chord-track'),
              name: 'Chords',
              instrument: SongInstrument(name: 'Guitar'),
              events: <SongChordEvent>[
                SongChordEvent(
                  id: SongEventId('c-1'),
                  start: Duration.zero,
                  duration: const Duration(seconds: 2),
                  symbol: const Chord('C'),
                ),
                SongChordEvent(
                  id: SongEventId('c-2'),
                  start: const Duration(seconds: 2),
                  duration: const Duration(seconds: 2),
                  symbol: const Chord('Am'),
                  displayText: 'A min (custom)',
                ),
              ],
            ),
          ],
        );
        final decoded = codec.decode(codec.encode(document));
        expect(decoded.tracks, hasLength(1));
        final track = decoded.tracks.single as ChordTrack;
        expect(track.events, hasLength(2));
        expect(track.events[0].symbol.label, 'C');
        expect(track.events[1].displayText, 'A min (custom)');
        expect(decoded, equals(document));
      },
    );

    test('round-trips a StrumTrack with null direction (= unknown)', () {
      final document = _sampleDocument(
        tracks: <SongTrack>[
          StrumTrack(
            id: SongTrackId('strum-track'),
            name: 'Strum',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('s-1'),
                at: Duration.zero,
                direction: StrumDirection.down,
                accent: true,
              ),
              SongStrumEvent(
                id: SongEventId('s-2'),
                at: Duration(milliseconds: 500),
                direction: null,
                muted: true,
              ),
            ],
          ),
        ],
      );
      final decoded = codec.decode(codec.encode(document));
      final track = decoded.tracks.single as StrumTrack;
      expect(track.events, hasLength(2));
      expect(track.events[0].direction, StrumDirection.down);
      expect(track.events[0].accent, isTrue);
      expect(track.events[1].direction, isNull);
      expect(track.events[1].muted, isTrue);
    });

    test(
      'round-trips a NoteTrack with known + unknown techniques and tie groups',
      () {
        final document = _sampleDocument(
          tracks: <SongTrack>[
            NoteTrack(
              id: SongTrackId('note-track'),
              name: 'Lead',
              instrument: SongInstrument(
                name: 'Guitar',
                tuning: Tunings.standard,
              ),
              events: <SongNoteEvent>[
                SongNoteEvent(
                  id: SongEventId('n-1'),
                  start: Duration.zero,
                  duration: const Duration(milliseconds: 500),
                  midiPitch: 60,
                  velocity: 100,
                  stringIndex: 5,
                  fret: 3,
                  techniques: <SongNoteTechnique>{
                    SongNoteTechnique.known(SongNoteTechniqueKind.hammerOn),
                    SongNoteTechnique.unknown(
                      rawCode: 'fingerstyle.tap',
                      displayText: 'tap',
                    ),
                  },
                ),
                SongNoteEvent(
                  id: SongEventId('n-2'),
                  start: const Duration(milliseconds: 500),
                  duration: const Duration(milliseconds: 500),
                  midiPitch: 60,
                  tieGroupId: 'g1',
                ),
                SongNoteEvent(
                  id: SongEventId('n-3'),
                  start: const Duration(seconds: 1),
                  duration: const Duration(milliseconds: 500),
                  midiPitch: 62,
                  tieGroupId: 'g1',
                ),
              ],
            ),
          ],
        );
        final decoded = codec.decode(codec.encode(document));
        final track = decoded.tracks.single as NoteTrack;
        expect(track.events, hasLength(3));
        expect(track.events[0].techniques, hasLength(2));
        expect(
          track.events[0].techniques
              .where(
                (t) => t.isKnown && t.kind == SongNoteTechniqueKind.hammerOn,
              )
              .length,
          1,
        );
        expect(
          track.events[0].techniques.where((t) => !t.isKnown).first.rawCode,
          'fingerstyle.tap',
        );
        expect(track.events[1].tieGroupId, 'g1');
        expect(track.events[2].tieGroupId, 'g1');
        expect(track.events[0].stringIndex, 5);
        expect(track.events[0].fret, 3);
        expect(track.instrument.tuning, Tunings.standard);
      },
    );

    test('round-trips LyricsTrack and MarkerTrack events', () {
      final document = _sampleDocument(
        tracks: <SongTrack>[
          LyricsTrack(
            id: SongTrackId('lyrics-track'),
            name: 'Words',
            instrument: SongInstrument(name: 'Vocals'),
            events: <SongLyricEvent>[
              SongLyricEvent(
                id: SongEventId('l-1'),
                at: Duration.zero,
                text: 'Hello',
              ),
              SongLyricEvent(
                id: SongEventId('l-2'),
                at: Duration(seconds: 2),
                text: 'World',
              ),
            ],
          ),
          MarkerTrack(
            id: SongTrackId('marker-track'),
            name: 'Section',
            instrument: SongInstrument(name: 'Routing'),
            events: <SongMarkerEvent>[
              SongMarkerEvent(
                id: SongEventId('mk-1'),
                at: Duration.zero,
                label: 'Verse',
                kind: 'rehearsal',
              ),
            ],
          ),
        ],
      );
      final decoded = codec.decode(codec.encode(document));
      expect(decoded.tracks, hasLength(2));
      final lyrics = decoded.tracks[0] as LyricsTrack;
      expect(lyrics.events[0].text, 'Hello');
      expect(lyrics.events[1].text, 'World');
      final marker = decoded.tracks[1] as MarkerTrack;
      expect(marker.events.single.label, 'Verse');
      expect(marker.events.single.kind, 'rehearsal');
    });

    test('round-trips a BackingAudioTrack with assetId and gridOffset', () {
      final document = _sampleDocument(
        tracks: <SongTrack>[
          BackingAudioTrack(
            id: SongTrackId('backing-track'),
            name: 'Backing',
            instrument: SongInstrument(name: 'Backing'),
            assetId: SongAssetId('asset-back'),
            gridOffset: const Duration(milliseconds: 250),
            gainDb: -3.5,
          ),
        ],
      );
      final decoded = codec.decode(codec.encode(document));
      final backing = decoded.tracks.single as BackingAudioTrack;
      expect(backing.assetId, SongAssetId('asset-back'));
      expect(backing.gridOffset, const Duration(milliseconds: 250));
      expect(backing.gainDb, -3.5);
    });

    test('preserves the canonical event ordering on the wire', () {
      // Authored out-of-order; codec + canonical sort must serialise in
      // (start, track, id) order and re-decode into that order.
      final document = _sampleDocument(
        tracks: <SongTrack>[
          ChordTrack(
            id: SongTrackId('chord-track'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('c-late'),
                start: const Duration(seconds: 4),
                duration: const Duration(seconds: 2),
                symbol: const Chord('G'),
              ),
              SongChordEvent(
                id: SongEventId('c-early'),
                start: Duration.zero,
                duration: const Duration(seconds: 2),
                symbol: const Chord('C'),
              ),
              SongChordEvent(
                id: SongEventId('c-middle'),
                start: const Duration(seconds: 2),
                duration: const Duration(seconds: 2),
                symbol: const Chord('Am'),
              ),
            ],
          ),
        ],
      );
      final bytes = codec.encode(document);
      final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final tracksJson = raw['tracks'] as List;
      final eventsJson =
          (tracksJson.single as Map<String, dynamic>)['events'] as List;
      final ids = eventsJson
          .map((e) => (e as Map<String, dynamic>)['id'] as String)
          .toList();
      expect(ids, <String>['c-early', 'c-middle', 'c-late']);
    });
  });

  group('SongDocumentCodec — deterministic encoding', () {
    test('two encodes of the same document are byte-identical', () {
      final document = _sampleDocument(
        tracks: <SongTrack>[
          ChordTrack(
            id: SongTrackId('chord-track'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('c-1'),
                start: Duration.zero,
                duration: const Duration(seconds: 2),
                symbol: const Chord('C'),
              ),
            ],
          ),
        ],
      );
      final a = codec.encode(document);
      final b = codec.encode(document);
      expect(utf8.decode(a), utf8.decode(b));
    });

    test('decoded event list is unmodifiable', () {
      final document = _sampleDocument(
        tracks: <SongTrack>[
          ChordTrack(
            id: SongTrackId('chord-track'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('c-1'),
                start: Duration.zero,
                duration: const Duration(seconds: 1),
                symbol: const Chord('C'),
              ),
            ],
          ),
        ],
      );
      final decoded = codec.decode(codec.encode(document));
      final track = decoded.tracks.single as ChordTrack;
      expect(
        () => track.events.add(
          SongChordEvent(
            id: SongEventId('x'),
            start: Duration.zero,
            duration: const Duration(seconds: 1),
            symbol: const Chord('X'),
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('SongDocumentCodec — fail-loud on unknown subtypes', () {
    test('unknown track kind throws with stable error code', () {
      final json = jsonEncode(<String, dynamic>{
        'schemaVersion': 1,
        'id': 'song-001',
        'revision': 1,
        'metadata': _metadataJson(),
        'source': _sourceJson(),
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'midi-mono',
            'id': 't-unknown',
            'name': 'Unknown',
            'instrument': <String, dynamic>{'name': 'Mystery'},
            'enabled': true,
          },
        ],
        'assets': <Object?>[],
        'markers': <Object?>[],
        'createdAt': '2026-01-01T12:00:00Z',
        'updatedAt': '2026-01-02T12:00:00Z',
      });
      expect(
        () => codec.decode(utf8.encode(json)),
        throwsA(
          isA<SongDocumentCodecException>().having(
            (e) => e.code,
            'code',
            SongDocumentCodecErrorCode.trackTypeUnknown,
          ),
        ),
      );
    });

    test('unknown event kind throws with stable error code', () {
      final json = jsonEncode(<String, dynamic>{
        'schemaVersion': 1,
        'id': 'song-001',
        'revision': 1,
        'metadata': _metadataJson(),
        'source': _sourceJson(),
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'note',
            'id': 'note-track',
            'name': 'Lead',
            'instrument': <String, dynamic>{'name': 'Guitar'},
            'enabled': true,
            'events': <Map<String, dynamic>>[
              <String, dynamic>{
                'kind': 'wave-shape',
                'id': 'e-1',
                'startMicros': 0,
                'durationMicros': 1000,
                'midiPitch': 60,
              },
            ],
          },
        ],
        'assets': <Object?>[],
        'markers': <Object?>[],
        'createdAt': '2026-01-01T12:00:00Z',
        'updatedAt': '2026-01-02T12:00:00Z',
      });
      expect(
        () => codec.decode(utf8.encode(json)),
        throwsA(
          isA<SongDocumentCodecException>().having(
            (e) => e.code,
            'code',
            SongDocumentCodecErrorCode.eventTypeUnknown,
          ),
        ),
      );
    });
  });

  group('Model validation', () {
    test('SongChordEvent rejects negative start and zero duration', () {
      expect(
        () => SongChordEvent(
          id: SongEventId('c-1'),
          start: const Duration(milliseconds: -1),
          duration: const Duration(seconds: 1),
          symbol: const Chord('C'),
        ),
        throwsA(isA<SongTrackValidationException>()),
      );
      expect(
        () => SongChordEvent(
          id: SongEventId('c-1'),
          start: Duration.zero,
          duration: Duration.zero,
          symbol: const Chord('C'),
        ),
        throwsA(isA<SongTrackValidationException>()),
      );
    });

    test('SongNoteEvent rejects out-of-range midiPitch and negative fret', () {
      expect(
        () => SongNoteEvent(
          id: SongEventId('n-1'),
          start: Duration.zero,
          duration: const Duration(milliseconds: 500),
          midiPitch: -1,
        ),
        throwsA(isA<SongTrackValidationException>()),
      );
      expect(
        () => SongNoteEvent(
          id: SongEventId('n-1'),
          start: Duration.zero,
          duration: const Duration(milliseconds: 500),
          midiPitch: 128,
        ),
        throwsA(isA<SongTrackValidationException>()),
      );
      expect(
        () => SongNoteEvent(
          id: SongEventId('n-1'),
          start: Duration.zero,
          duration: const Duration(milliseconds: 500),
          midiPitch: 60,
          fret: -1,
        ),
        throwsA(isA<SongTrackValidationException>()),
      );
    });

    test('SongNoteEvent requires stringIndex and fret to be set together', () {
      expect(
        () => SongNoteEvent(
          id: SongEventId('n-1'),
          start: Duration.zero,
          duration: const Duration(milliseconds: 500),
          midiPitch: 60,
          fret: 5,
        ),
        throwsA(isA<SongTrackValidationException>()),
      );
      expect(
        () => SongNoteEvent(
          id: SongEventId('n-1'),
          start: Duration.zero,
          duration: const Duration(milliseconds: 500),
          midiPitch: 60,
          stringIndex: 3,
        ),
        throwsA(isA<SongTrackValidationException>()),
      );
      // Together: fine.
      final ok = SongNoteEvent(
        id: SongEventId('n-1'),
        start: Duration.zero,
        duration: const Duration(milliseconds: 500),
        midiPitch: 60,
        stringIndex: 3,
        fret: 5,
      );
      expect(ok.stringIndex, 3);
      expect(ok.fret, 5);
    });

    test(
      'BackingAudioTrack rejects negative gridOffset and unbounded gainDb',
      () {
        expect(
          () => BackingAudioTrack(
            id: SongTrackId('b-1'),
            name: 'Backing',
            instrument: SongInstrument(name: 'X'),
            assetId: SongAssetId('a-1'),
            gridOffset: const Duration(milliseconds: -1),
          ),
          throwsA(isA<SongTrackValidationException>()),
        );
        expect(
          () => BackingAudioTrack(
            id: SongTrackId('b-1'),
            name: 'Backing',
            instrument: SongInstrument(name: 'X'),
            assetId: SongAssetId('a-1'),
            gridOffset: Duration.zero,
            gainDb: -200,
          ),
          throwsA(isA<SongTrackValidationException>()),
        );
        expect(
          () => BackingAudioTrack(
            id: SongTrackId('b-1'),
            name: 'Backing',
            instrument: SongInstrument(name: 'X'),
            assetId: SongAssetId('a-1'),
            gridOffset: Duration.zero,
            gainDb: 200,
          ),
          throwsA(isA<SongTrackValidationException>()),
        );
      },
    );

    test('SongInstrument rejects empty name', () {
      expect(
        () => SongInstrument(name: ''),
        throwsA(isA<SongInstrumentValidationException>()),
      );
    });

    test('SongNoteTechnique.equal compares kind+raw+display', () {
      final a = SongNoteTechnique.known(SongNoteTechniqueKind.bend);
      final b = SongNoteTechnique.known(SongNoteTechniqueKind.bend);
      final c = SongNoteTechnique.unknown(rawCode: 'x', displayText: 'X');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('SongTrackId/SongEventId follow the shared SongTypedId contract', () {
      expect(() => SongTrackId(''), throwsA(isA<SongIdValidationException>()));
      expect(() => SongEventId(''), throwsA(isA<SongIdValidationException>()));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SongDocument _sampleDocument({
  required List<SongTrack> tracks,
  List<SongAssetReference>? assets,
  List<SongMarker>? markers,
}) {
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('song-001'),
    revision: 1,
    metadata: SongMetadata(title: 'Wonderwall'),
    source: _sampleSource(),
    assets: assets ?? const <SongAssetReference>[],
    markers: markers ?? const <SongMarker>[],
    tracks: tracks,
    createdAt: DateTime.utc(2026, 1, 1, 12),
    updatedAt: DateTime.utc(2026, 1, 2, 12),
  );
}

SongSource _sampleSource() => SongSource(
  type: SongSourceType.legacyLocal,
  originalFileName: 'song.json',
  sha256: 'a' * 64,
  importedAt: DateTime.utc(2026, 1, 1, 12),
  importerVersion: '1.0.0',
);

Map<String, dynamic> _metadataJson() => <String, dynamic>{
  'title': 'Wonderwall',
  'tags': <String>[],
  'defaultCapo': 0,
};

Map<String, dynamic> _sourceJson() => <String, dynamic>{
  'type': 'legacy_local',
  'originalFileName': 'song.json',
  'sha256': 'a' * 64,
  'importedAt': '2026-01-01T12:00:00Z',
  'importerVersion': '1.0.0',
  'warningSummary': <String>[],
};
