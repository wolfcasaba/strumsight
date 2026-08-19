// E07-R24 — SongGoalReaderAdapter: A5 (explicit missing-asset branch),
// A6 (stale-revision detection), and A7 (public-API-only imports).
//
// The architecture guard in `tool/check_architecture.dart` enforces the
// cross-feature import rule, so the A7 cell is verified by running that
// step inside the round gate (it surfaces a banned Song Trainer internal
// import as a compile-time finding). This file focuses on the
// behavioural cells.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

import '../../../fixtures/practice_generator/song_goal/song_goal_fixtures.dart';

void main() {
  group('SongGoalReaderAdapter — A5 explicit missing-asset branch', () {
    test('a section with no usable public asset reference surfaces '
        'usableAssetReference == null (never a silent skip)', () {
      final document = buildSongDocument(
        revision: 5,
        sections: [
          buildSongSection(
            id: 's-noasset',
            name: 'Solo',
            kind: SongSectionKind.solo,
            startMeasure: 0,
            endMeasureExclusive: 8,
          ),
        ],
        // No assets at the document level either.
        assets: const <SongAssetReference>[],
      );
      final outcome = const SongGoalReaderAdapter().read(document: document);
      expect(outcome, isA<SongGoalReadSuccess>());
      final success = outcome as SongGoalReadSuccess;
      expect(success.sections, hasLength(1));
      expect(success.sections.single.sectionId.value, 's-noasset');
      expect(success.sections.single.usableAssetReference, isNull);
      expect(success.hasNoUsableAssets, isTrue);
      expect(success.missingUsableAssetCount, 1);
    });

    test('a document with sections but a missing per-section asset is still '
        'surfaced as a SongGoalReadSuccess with explicit gaps', () {
      final documentAsset = buildSongAssetReference(id: 'document-asset');
      final document = buildSongDocument(
        revision: 5,
        sections: [
          buildSongSection(
            id: 's-with-asset',
            name: 'Verse',
            kind: SongSectionKind.verse,
            startMeasure: 0,
            endMeasureExclusive: 8,
          ),
          buildSongSection(
            id: 's-without-asset',
            name: 'Bridge',
            kind: SongSectionKind.bridge,
            startMeasure: 8,
            endMeasureExclusive: 16,
          ),
        ],
        assets: [documentAsset],
      );
      final outcome = const SongGoalReaderAdapter().read(document: document);
      final success = outcome as SongGoalReadSuccess;
      expect(success.documentAssetReferences, [documentAsset]);
      expect(success.sections, hasLength(2));
      expect(
        success.sections[0].usableAssetReference,
        isNull,
        reason:
            'section→asset pairing is not in the public surface; '
            'the adapter surfaces the explicit null, never a guess',
      );
      expect(success.sections[1].usableAssetReference, isNull);
      expect(success.missingUsableAssetCount, 2);
      expect(success.hasNoUsableAssets, isFalse);
    });
  });

  group('SongGoalReaderAdapter — A6 stale-revision detection', () {
    test('a matching expectedRevision produces SongGoalReadSuccess', () {
      final document = buildSongDocument(
        revision: 5,
        sections: [
          buildSongSection(
            id: 's-ok',
            name: 'Verse',
            kind: SongSectionKind.verse,
            startMeasure: 0,
            endMeasureExclusive: 8,
          ),
        ],
      );
      final outcome = const SongGoalReaderAdapter().read(
        document: document,
        expectedRevision: 5,
      );
      expect(outcome, isA<SongGoalReadSuccess>());
    });

    test('a divergent expectedRevision produces SongGoalReadStaleRevision '
        'with actual + expected surfaced (elavult revízió)', () {
      final document = buildSongDocument(
        revision: 7,
        sections: [
          buildSongSection(
            id: 's-stale',
            name: 'Verse',
            kind: SongSectionKind.verse,
            startMeasure: 0,
            endMeasureExclusive: 8,
          ),
        ],
      );
      final outcome = const SongGoalReaderAdapter().read(
        document: document,
        expectedRevision: 5, // caller thought this was 5
      );
      expect(outcome, isA<SongGoalReadStaleRevision>());
      final stale = outcome as SongGoalReadStaleRevision;
      expect(stale.actualRevision, 7);
      expect(stale.expectedRevision, 5);
      expect(stale.documentId.value, 'fixture-song-1');
    });

    test('a document with zero sections produces SongGoalReadNoSections '
        '(no silent skip — explicit branch the planner routes on)', () {
      final document = buildSongDocument(
        revision: 5,
        sections: const <SongSection>[],
      );
      final outcome = const SongGoalReaderAdapter().read(document: document);
      expect(outcome, isA<SongGoalReadNoSections>());
      final empty = outcome as SongGoalReadNoSections;
      expect(empty.documentRevision, 5);
      expect(empty.documentId.value, 'fixture-song-1');
    });

    test('a stale revision takes precedence over the no-sections branch', () {
      final document = buildSongDocument(
        revision: 7,
        sections: const <SongSection>[],
      );
      final outcome = const SongGoalReaderAdapter().read(
        document: document,
        expectedRevision: 5,
      );
      expect(outcome, isA<SongGoalReadStaleRevision>());
    });
  });

  group('SongGoalReaderAdapter — A7 public API only', () {
    test('the adapter accepts the public-domain SongDocument surface '
        '(sections, assets, revision, id, metadata, source) '
        'without reading anything else', () {
      final asset = buildSongAssetReference(id: 'asset-public');
      final document = buildSongDocument(
        revision: 5,
        sections: [
          buildSongSection(
            id: 's-public',
            name: 'Verse',
            kind: SongSectionKind.verse,
            startMeasure: 0,
            endMeasureExclusive: 8,
          ),
        ],
        assets: [asset],
      );
      // No Song Trainer internal types are imported here — the only
      // Song Trainer symbols touched are the ones re-exported by
      // `package:strumsight/features/song_trainer/domain/public.dart`.
      final outcome = const SongGoalReaderAdapter().read(
        document: document,
        expectedRevision: 5,
      );
      expect(outcome, isA<SongGoalReadSuccess>());
    });
  });
}
