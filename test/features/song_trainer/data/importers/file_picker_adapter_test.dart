import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';

void main() {
  test('buffers a platform file behind two reads', () async {
    final source = await PlatformFilePickerAdapter.fromXFile(
      XFile.fromData(
        Uint8List.fromList(<int>[1, 2, 3]),
        path: 'lesson.mid',
        name: 'lesson.mid',
        mimeType: 'audio/midi',
      ),
    );

    expect(source.displayName, 'lesson.mid');
    expect(source.byteLength, 3);
    expect(await source.openRead().expand((chunk) => chunk).toList(), <int>[
      1,
      2,
      3,
    ]);
    expect(await source.openRead().expand((chunk) => chunk).toList(), <int>[
      1,
      2,
      3,
    ]);
  });
}
