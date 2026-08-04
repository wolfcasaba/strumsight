import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';

void main() {
  test(
    'setlist ids reject traversal-like values before they can become file names',
    () {
      expect(
        () => SongSetlist(
          id: '../outside',
          name: 'Invalid',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          items: <SongSetlistItem>[
            SongSetlistItem(id: 'item', songId: SongId('song-a')),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test('Song Trainer uses only public cross-feature imports', () {
    final root = Directory('lib/features/song_trainer');
    final forbidden = RegExp(
      r'''features/(?:progress|streak|practice)/(?!public\.dart)['"]''',
    );
    final violations = <String>[];
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) {
        continue;
      }
      if (forbidden.hasMatch(file.readAsStringSync())) {
        violations.add(file.path);
      }
    }

    expect(violations, isEmpty);
  });
}
