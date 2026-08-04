import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_editor_screen.dart';

void main() {
  test('editor screen retains the route document identifier', () {
    const screen = SongEditorScreen(songId: 'song-42');
    expect(screen.songId, 'song-42');
  });
}
