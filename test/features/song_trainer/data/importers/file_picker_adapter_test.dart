import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';

void main() {
  test(
    'buffers a single-subscription platform stream behind two reads',
    () async {
      final input = StreamController<List<int>>();
      final sourceFuture = PlatformFilePickerAdapter.fromPlatformFile(
        PlatformFile(name: 'lesson.mid', size: 3, readStream: input.stream),
      );
      input
        ..add(Uint8List.fromList(<int>[1, 2, 3]))
        ..close();
      final source = await sourceFuture;

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
    },
  );
}
