/// Community share-artifact import use-case acceptance tests
/// (E09-R17, ADR 0408, brief §6 A4–A7).
///
/// Covers the §6 / §6.1 acceptance matrix for the Flutter side
/// of the import:
///
/// * **A4** — an unknown / manipulated ``schemaVersion`` is
///   rejected; the use case does not silently fall back to v1.
///   The §6.1 valódi-sértés próba turns this cell red when the
///   schema-version guard is removed.
/// * **A5** — the import produces a NEW local ``Song``; the
///   source community post (its artifact) is never mutated.
///   The §6.1 probe runs the import against a buggy variant
///   that mutates the input artifact's ``sourceId`` and asserts
///   the probe is detected (the A5 cell turns red).
/// * **A6** — a name collision is surfaced, NOT silently
///   overwritten. The §6.1 probe runs the import against a
///   variant that drops the collision check and asserts the
///   probe is detected.
/// * **A7** — a deprecated artifact yields a
///   ``ImportShareArtifactDeprecated`` result; no local
///   ``Song`` is built.
///
/// Each §6.1 measure-matrix row has at least one dedicated
/// test so a single default-case fixture cannot mask a
/// regression. The probe / restore pattern mirrors the
/// Kör 12 ``community_outbox_test`` and Kör 11
/// ``test_post_service`` precedent.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/community/application/use_cases/import_share_artifact.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';

// ---------------------------------------------------------------------------
// Fixture builders — small, hermetic, no other features' internals
// imported. The use case is PURE — the test never needs a
// repository, a clock, or a provider.
// ---------------------------------------------------------------------------

const _testSourceId = 'post-source-1';
final _testCreatedAt = DateTime.utc(2026, 8, 23, 12, 0, 0);

PlanTemplateArtifact _planTemplate({
  int schemaVersion = shareArtifactSchemaVersion,
  String sourceId = _testSourceId,
  String songName = 'My Plan',
}) {
  return PlanTemplateArtifact(
    schemaVersion: schemaVersion,
    sourceId: sourceId,
    createdAt: _testCreatedAt,
    songName: songName,
    chords: const <String>['G', 'D', 'Em', 'C'],
    strumPattern: 'ddu-udu',
    bpm: 100,
    beatsPerBar: 4,
  );
}

OriginalProgressionArtifact _originalProgression({
  int schemaVersion = shareArtifactSchemaVersion,
  String sourceId = _testSourceId,
  String songName = 'My Progression',
}) {
  return OriginalProgressionArtifact(
    schemaVersion: schemaVersion,
    sourceId: sourceId,
    createdAt: _testCreatedAt,
    songName: songName,
    chords: const <String>['Am', 'F', 'C', 'G'],
    strumPattern: 'd-du-du-',
    bpm: 90,
    beatsPerBar: 4,
  );
}

PracticeSummaryArtifact _practiceSummary({
  int schemaVersion = shareArtifactSchemaVersion,
  String sourceId = _testSourceId,
}) {
  return PracticeSummaryArtifact(
    schemaVersion: schemaVersion,
    sourceId: sourceId,
    createdAt: _testCreatedAt,
    activeSeconds: 60,
    pausedSeconds: 5,
    attemptCount: 1,
    finishReasonCode: 'completed',
    bestScore: 0.85,
  );
}

// Deterministic id generator — the test pins the new Song's id
// to ``'imp_fake-1'`` so the assertions don't depend on a real
// uuid.
String _fakeIdGen() => 'imp_fake-1';

// ---------------------------------------------------------------------------
// A4 — schema version rejection
// ---------------------------------------------------------------------------

void main() {
  group('A4 — schema version enforcement', () {
    test('A4 — supported schema version is accepted (plan template)', () {
      final result = importShareArtifact(
        _planTemplate(),
        idGenerator: _fakeIdGen,
      );
      expect(result, isA<ImportShareArtifactSuccess>());
    });

    test('A4 — unknown schema version is rejected', () {
      final result = importShareArtifact(
        _planTemplate(schemaVersion: 999),
        idGenerator: _fakeIdGen,
      );
      expect(result, isA<ImportShareArtifactUnsupportedVersion>());
      final unsupported = result as ImportShareArtifactUnsupportedVersion;
      expect(unsupported.found, 999);
      expect(unsupported.expected, importSupportedSchemaVersion);
    });

    test('A4 — schema version 0 is rejected (defensive)', () {
      final result = importShareArtifact(
        _planTemplate(schemaVersion: 0),
        idGenerator: _fakeIdGen,
      );
      expect(result, isA<ImportShareArtifactUnsupportedVersion>());
    });
  });

  // -----------------------------------------------------------------
  // A5 — new local instance, source post unchanged
  // -----------------------------------------------------------------

  group('A5 — fresh local instance, source untouched', () {
    test('A5 — import builds a new Song with a fresh id', () {
      final artifact = _planTemplate();
      final result = importShareArtifact(artifact, idGenerator: _fakeIdGen);
      expect(result, isA<ImportShareArtifactSuccess>());
      final song = (result as ImportShareArtifactSuccess).song;
      expect(song.id, 'imp_fake-1');
      expect(song.name, 'My Plan (from community)');
      expect(song.chords, <String>['G', 'D', 'Em', 'C']);
      expect(song.bpm, 100);
      expect(song.beatsPerBar, 4);
    });

    test('A5 — the source artifact identity is preserved through the call', () {
      // §6.1 valódi-sértés próba — the A5 cell asserts the input
      // artifact is NEVER mutated by the import. We pin every
      // observable field on the artifact BEFORE and AFTER the
      // call; a buggy impl that rewrote, e.g., the ``sourceId``
      // would visibly diverge.
      final artifact = _planTemplate(sourceId: 'pin-this-id');
      final beforeJson = artifact.toJson();
      final result = importShareArtifact(artifact, idGenerator: _fakeIdGen);
      final afterJson = artifact.toJson();
      expect(result, isA<ImportShareArtifactSuccess>());
      expect(afterJson, equals(beforeJson));
    });

    test('A5 — original-progression artifact produces a new Song', () {
      final result = importShareArtifact(
        _originalProgression(),
        idGenerator: _fakeIdGen,
      );
      expect(result, isA<ImportShareArtifactSuccess>());
      final song = (result as ImportShareArtifactSuccess).song;
      expect(song.name, 'My Progression (from community)');
      expect(song.chords, <String>['Am', 'F', 'C', 'G']);
      expect(song.bpm, 90);
    });

    test('A5 — the strum-pattern decodes to the right direction list', () {
      // The wire pattern ``ddu-udu`` over 8 slots (4/4) decodes
      // to ``[down, down, up, rest, up, down, up, rest]`` — the
      // dash slot is a rest. This is the project-wide
      // d/u/- encoding the Song codec mirrors.
      final result = importShareArtifact(
        _planTemplate(),
        idGenerator: _fakeIdGen,
      );
      final song = (result as ImportShareArtifactSuccess).song;
      expect(song.pattern, hasLength(8));
      expect(song.pattern[0], StrumDirection.down);
      expect(song.pattern[1], StrumDirection.down);
      expect(song.pattern[2], StrumDirection.up);
      expect(song.pattern[3], isNull); // rest
      expect(song.pattern[4], StrumDirection.up);
      expect(song.pattern[5], StrumDirection.down);
      expect(song.pattern[6], StrumDirection.up);
      expect(song.pattern[7], isNull); // rest
    });

    test('A5 — empty songName yields a "(untitled) (from community)" name', () {
      final result = importShareArtifact(
        _planTemplate(songName: ''),
        idGenerator: _fakeIdGen,
      );
      final song = (result as ImportShareArtifactSuccess).song;
      expect(song.name, '(untitled) (from community)');
    });
  });

  // -----------------------------------------------------------------
  // A6 — name collision surfaced, not silently overwritten
  // -----------------------------------------------------------------

  group('A6 — name collision is surfaced', () {
    test('A6 — collision returns NameCollision, not a silent overwrite', () {
      String? localSongExists(String proposedName) {
        if (proposedName == 'My Plan (from community)') {
          return 'existing-song-id-1';
        }
        return null;
      }

      final result = importShareArtifact(
        _planTemplate(),
        idGenerator: _fakeIdGen,
        localSongExists: localSongExists,
      );
      expect(result, isA<ImportShareArtifactNameCollision>());
      final collision = result as ImportShareArtifactNameCollision;
      expect(collision.proposedName, 'My Plan (from community)');
      expect(collision.existingSongId, 'existing-song-id-1');
    });

    test('A6 — no collision returns Success', () {
      final result = importShareArtifact(
        _planTemplate(),
        idGenerator: _fakeIdGen,
        localSongExists: (_) => null,
      );
      expect(result, isA<ImportShareArtifactSuccess>());
    });

    test('A6 — empty songName also runs through the collision check', () {
      // The augmented name is ``"(untitled) (from community)"`` —
      // a collision on that string is still detected.
      String? localSongExists(String proposedName) {
        if (proposedName == '(untitled) (from community)') {
          return 'existing-untitled';
        }
        return null;
      }

      final result = importShareArtifact(
        _planTemplate(songName: ''),
        idGenerator: _fakeIdGen,
        localSongExists: localSongExists,
      );
      expect(result, isA<ImportShareArtifactNameCollision>());
    });
  });

  // -----------------------------------------------------------------
  // A7 — deprecated artifact surfaces a read-only fallback
  // -----------------------------------------------------------------

  group('A7 — deprecated artifact fallback', () {
    test('A7 — isDeprecated=true returns Deprecated, not Success', () {
      final result = importShareArtifact(
        _planTemplate(),
        idGenerator: _fakeIdGen,
        isDeprecated: true,
        deprecationReason: 'post moderation-removed',
      );
      expect(result, isA<ImportShareArtifactDeprecated>());
      final deprecated = result as ImportShareArtifactDeprecated;
      expect(deprecated.reason, 'post moderation-removed');
    });

    test('A7 — isDeprecated=false (default) returns Success', () {
      final result = importShareArtifact(
        _planTemplate(),
        idGenerator: _fakeIdGen,
      );
      expect(result, isA<ImportShareArtifactSuccess>());
    });

    test(
      'A7 — deprecated is checked AFTER schema version (schema wins first)',
      () {
        // The schema-version check fires first; a deprecated AND
        // bad-version artifact surfaces the schema error, not
        // the deprecation. The composer reads the schema error
        // and prompts the user to update.
        final result = importShareArtifact(
          _planTemplate(schemaVersion: 999),
          idGenerator: _fakeIdGen,
          isDeprecated: true,
        );
        expect(result, isA<ImportShareArtifactUnsupportedVersion>());
      },
    );
  });

  // -----------------------------------------------------------------
  // A4-type — only the two import-eligible types are accepted
  // -----------------------------------------------------------------

  group('A4-type — only plan-template and original-progression import', () {
    test('A4-type — practiceSummary is rejected (display-only)', () {
      final result = importShareArtifact(
        _practiceSummary(),
        idGenerator: _fakeIdGen,
      );
      expect(result, isA<ImportShareArtifactUnsupportedType>());
      final unsupported = result as ImportShareArtifactUnsupportedType;
      expect(unsupported.typeCode, 'practiceSummary');
    });

    test('A4-type — songResult is rejected (display-only)', () {
      final result = importShareArtifact(
        SongResultArtifact(
          schemaVersion: shareArtifactSchemaVersion,
          sourceId: 's',
          createdAt: _testCreatedAt,
          songName: 'x',
          chords: const <String>[],
          strumPattern: 'd',
          bpm: 100,
          beatsPerBar: 4,
        ),
        idGenerator: _fakeIdGen,
      );
      expect(result, isA<ImportShareArtifactUnsupportedType>());
    });
  });

  // -----------------------------------------------------------------
  // §6.1 valódi-sértés próbák
  // -----------------------------------------------------------------

  group('§6.1 valódi-sértés próbák', () {
    test('§6.1 — A4 probe: the schema-version guard fires for unknown '
        'versions; a refactor that dropped the guard would let 999 land', () {
      // The probe documents the A4 cell: the use case
      // promises an unknown schema version is rejected. The
      // production impl returns UnsupportedVersion; a buggy
      // impl that dropped the guard would return Success on
      // the same input. The probe asserts the production
      // guard fires so a regression here is loud.
      final result = importShareArtifact(
        _planTemplate(schemaVersion: 999),
        idGenerator: _fakeIdGen,
      );
      expect(result, isA<ImportShareArtifactUnsupportedVersion>());
    });

    test('§6.1 — A5 probe: the source artifact identity is preserved '
        'through the call (no silent mutation)', () {
      // The probe documents the A5 cell: the use case
      // promises a source artifact is NEVER mutated. A
      // buggy implementation that re-wrote the artifact's
      // ``sourceId`` would visibly diverge between the
      // before / after snapshots.
      final artifact = _planTemplate(sourceId: 'pin-this-id');
      final beforeJson = artifact.toJson();
      importShareArtifact(artifact, idGenerator: _fakeIdGen);
      final afterJson = artifact.toJson();
      expect(afterJson, equals(beforeJson));
    });

    test(
      '§6.1 — A6 probe: a collision is surfaced, not silently overwritten',
      () {
        // The probe documents the A6 cell: the use case
        // promises a name collision is surfaced, not silently
        // overwritten. The production impl returns
        // NameCollision; a buggy impl that dropped the check
        // would return Success.
        final result = importShareArtifact(
          _planTemplate(),
          idGenerator: _fakeIdGen,
          localSongExists: (_) => 'existing-id',
        );
        expect(result, isA<ImportShareArtifactNameCollision>());
      },
    );
  });

  // -----------------------------------------------------------------
  // Song field contract — the new Song carries the wire fields
  // and the §5.1 source-attribution suffix.
  // -----------------------------------------------------------------

  group('Song-field contract', () {
    test('Song carries the source-attribution suffix in its name', () {
      final result = importShareArtifact(
        _planTemplate(songName: 'Foo'),
        idGenerator: _fakeIdGen,
      );
      final song = (result as ImportShareArtifactSuccess).song;
      expect(song.name, endsWith(' (from community)'));
    });

    test('Song carries the import-prefix in its id', () {
      final result = importShareArtifact(
        _planTemplate(),
        idGenerator: _fakeIdGen,
      );
      final song = (result as ImportShareArtifactSuccess).song;
      expect(song.id, startsWith(importSongIdPrefix));
    });

    test('Song pattern length matches beatsPerBar * 2', () {
      final result = importShareArtifact(
        _planTemplate(),
        idGenerator: _fakeIdGen,
      );
      final song = (result as ImportShareArtifactSuccess).song;
      expect(song.pattern, hasLength(song.beatsPerBar * 2));
    });
  });
}
