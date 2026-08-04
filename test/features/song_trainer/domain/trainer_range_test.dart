import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';

void main() {
  group('TrainerRange', () {
    final sections = <SongSection>[
      SongSection(
        id: SongSectionId('verse'),
        name: 'Verse',
        startMeasure: 1,
        endMeasureExclusive: 3,
      ),
    ];

    test('maps full, section, and inclusive UI measure ranges to bounds', () {
      expect(
        const FullSongRange().resolve(measureCount: 4, sections: sections),
        MeasureRange(start: 0, endExclusive: 4),
      );
      expect(
        SectionRange(
          SongSectionId('verse'),
        ).resolve(measureCount: 4, sections: sections),
        MeasureRange(start: 1, endExclusive: 3),
      );
      expect(
        MeasureRange.fromInclusive(
          start: 3,
          endInclusive: 3,
        ).resolve(measureCount: 4, sections: sections),
        MeasureRange(start: 3, endExclusive: 4),
      );
    });

    test(
      'rejects a range that would exclude the final measure or leave song bounds',
      () {
        expect(
          () => MeasureRange.fromInclusive(start: 3, endInclusive: 2),
          throwsArgumentError,
        );
        expect(
          MeasureRange(
            start: 3,
            endExclusive: 5,
          ).resolve(measureCount: 4, sections: sections),
          isNull,
        );
      },
    );

    test(
      'bookmark retains song identity and revision while resolving its range',
      () {
        final bookmark = BookmarkRange(
          songId: SongId('song-42'),
          songRevision: 7,
          range: SectionRange(SongSectionId('verse')),
        );

        expect(
          bookmark.resolve(measureCount: 4, sections: sections),
          MeasureRange(start: 1, endExclusive: 3),
        );
        expect(bookmark.songId, SongId('song-42'));
        expect(bookmark.songRevision, 7);
        expect(
          bookmark.matchesSong(songId: SongId('song-42'), revision: 7),
          isTrue,
        );
        expect(
          bookmark.matchesSong(songId: SongId('song-42'), revision: 8),
          isFalse,
        );
      },
    );
  });
}
