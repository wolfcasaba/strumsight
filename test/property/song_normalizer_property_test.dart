// Property gate for SongNormalizer (E03-R05, §6 acceptance).
//
// The same PROPERTY_SEED convention as the rest of the repo:
//   * CI passes PROPERTY_SEED from the run id;
//   * absent → 42 (deterministic dev loop).
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

const _normalizer = SongNormalizer();

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('normalize is idempotent on randomized documents '
      '(PROPERTY_SEED=$seed)', () {
    for (var trial = 0; trial < 8; trial++) {
      final document = _randomDocument(Random(seed + trial));
      final once = _normalizer.normalize(document);
      final twice = _normalizer.normalize(once);
      expect(
        twice,
        equals(once),
        reason: 'normalize must be idempotent (trial $trial)',
      );
    }
  });

  test('normalize preserves every original ID on randomized documents '
      '(PROPERTY_SEED=$seed)', () {
    for (var trial = 0; trial < 8; trial++) {
      final document = _randomDocument(Random(seed + trial));
      final normalized = _normalizer.normalize(document);

      expect(normalized.id, document.id);
      expect(
        normalized.tracks.length,
        document.tracks.length,
        reason: 'track count must be preserved',
      );
      // Match tracks by id — the normalizer reorders tracks.
      for (final original in document.tracks) {
        final canonical = normalized.tracks.firstWhere(
          (track) => track.id.value == original.id.value,
          orElse: () => throw StateError(
            'track id "${original.id.value}" must survive normalization',
          ),
        );
        expect(canonical.id, original.id);
        expect(canonical.name, original.name);
        expect(canonical.instrument, original.instrument);
        expect(canonical.enabled, original.enabled);
      }
    }
  });

  test('normalize preserves event identity on randomized documents '
      '(PROPERTY_SEED=$seed)', () {
    for (var trial = 0; trial < 8; trial++) {
      final document = _randomDocument(Random(seed + trial));
      final normalized = _normalizer.normalize(document);

      // Match tracks by id — the normalizer reorders tracks by
      // (kind, id), so index-based comparison would mismatch.
      for (final original in document.tracks) {
        final canonical = normalized.tracks.firstWhere(
          (track) => track.id.value == original.id.value,
          orElse: () => throw StateError(
            'track id "${original.id.value}" must survive normalization',
          ),
        );
        final originalIds = _eventIds(original);
        final canonicalIds = _eventIds(canonical);
        // Multiset equality: every original event id appears in the
        // canonical list, and the count matches.
        expect(
          canonicalIds.length,
          originalIds.length,
          reason: 'event count must be preserved',
        );
        for (final id in originalIds) {
          expect(
            canonicalIds.contains(id),
            isTrue,
            reason: 'event id "$id" must survive normalization',
          );
        }
      }
    }
  });

  test('canonical event ordering is monotonic by (start, id) for every '
      'supported track subtype (PROPERTY_SEED=$seed)', () {
    for (var trial = 0; trial < 8; trial++) {
      final document = _randomDocument(Random(seed + trial));
      final normalized = _normalizer.normalize(document);

      for (final track in normalized.tracks) {
        if (track is ChordTrack) {
          for (var i = 1; i < track.events.length; i++) {
            final previous = track.events[i - 1];
            final current = track.events[i];
            final startCompare = previous.start.compareTo(current.start);
            if (startCompare == 0) {
              expect(
                previous.id.value.compareTo(current.id.value),
                lessThan(0),
                reason: 'canonical chord event order violated',
              );
            } else {
              expect(
                startCompare,
                lessThan(0),
                reason: 'canonical chord event order violated',
              );
            }
          }
        } else if (track is NoteTrack) {
          for (var i = 1; i < track.events.length; i++) {
            final previous = track.events[i - 1];
            final current = track.events[i];
            final startCompare = previous.start.compareTo(current.start);
            if (startCompare == 0) {
              expect(
                previous.id.value.compareTo(current.id.value),
                lessThan(0),
                reason: 'canonical note event order violated',
              );
            } else {
              expect(
                startCompare,
                lessThan(0),
                reason: 'canonical note event order violated',
              );
            }
          }
        }
      }
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers — randomized document construction (PII-safe: random IDs are
// never written to disk; they exist only in memory for the property run).
// ---------------------------------------------------------------------------

List<String> _eventIds(SongTrack track) {
  if (track is ChordTrack) {
    return track.events.map((e) => e.id.value).toList();
  }
  if (track is NoteTrack) {
    return track.events.map((e) => e.id.value).toList();
  }
  if (track is StrumTrack) {
    return track.events.map((e) => e.id.value).toList();
  }
  if (track is LyricsTrack) {
    return track.events.map((e) => e.id.value).toList();
  }
  if (track is MarkerTrack) {
    return track.events.map((e) => e.id.value).toList();
  }
  return const <String>[];
}

SongDocument _randomDocument(Random random) {
  final trackCount = 1 + random.nextInt(3); // 1..3 tracks.
  final tracks = <SongTrack>[
    for (var i = 0; i < trackCount; i++) _randomChordOrNoteTrack(random, i),
  ];
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('doc-${random.nextInt(1 << 20)}'),
    revision: 0,
    metadata: SongMetadata(title: 'Property'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'doc.strum',
      sha256: 'a' * 64,
      importedAt: DateTime.utc(2026, 1, 1, 12),
      importerVersion: '1.0.0',
    ),
    tracks: tracks,
    createdAt: DateTime.utc(2026, 1, 1, 12),
    updatedAt: DateTime.utc(2026, 1, 1, 12),
  );
}

SongTrack _randomChordOrNoteTrack(Random random, int slot) {
  if (slot % 2 == 0) {
    final eventCount = 1 + random.nextInt(6); // 1..6
    final events = <SongChordEvent>[
      for (var i = 0; i < eventCount; i++)
        SongChordEvent(
          id: SongEventId('c-$slot-$i'),
          start: Duration(milliseconds: 100 * random.nextInt(20)),
          duration: const Duration(milliseconds: 100),
          symbol: Chord(['C', 'G', 'Am', 'F'][random.nextInt(4)]),
        ),
    ];
    return ChordTrack(
      id: SongTrackId('t-$slot'),
      name: 'Track $slot',
      instrument: SongInstrument(name: 'Guitar'),
      events: events,
    );
  } else {
    final eventCount = 1 + random.nextInt(6);
    final events = <SongNoteEvent>[
      for (var i = 0; i < eventCount; i++)
        SongNoteEvent(
          id: SongEventId('n-$slot-$i'),
          start: Duration(milliseconds: 100 * random.nextInt(20)),
          duration: const Duration(milliseconds: 50),
          midiPitch: 60 + random.nextInt(12),
        ),
    ];
    return NoteTrack(
      id: SongTrackId('t-$slot'),
      name: 'Track $slot',
      instrument: SongInstrument(name: 'Guitar'),
      events: events,
    );
  }
}
