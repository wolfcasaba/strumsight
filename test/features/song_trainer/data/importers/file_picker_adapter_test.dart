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

  /// K1 guard: the sheet-import path is untouched by the audio attach
  /// flow. Widening THIS list (instead of adding the audio group) would
  /// let an mp3 into the notation importer registry.
  test('the notation picker still accepts exactly the notation set', () {
    expect(PlatformFilePickerAdapter.supportedExtensions, <String>[
      'json',
      'musicxml',
      'xml',
      'mxl',
      'mid',
      'midi',
    ]);
  });

  test('the audio picker offers the seven attachable containers', () {
    expect(PlatformFilePickerAdapter.supportedAudioExtensions, <String>[
      'mp3',
      'm4a',
      'mp4',
      'aac',
      'ogg',
      'flac',
      'wav',
    ]);
    // Android SAF filters on the MIME type it resolved, and reports
    // `video/mp4` for plenty of audio-only MPEG-4 containers — without it
    // in the group the user's m4a is greyed out in the system picker.
    expect(
      PlatformFilePickerAdapter.audioTypeGroup.mimeTypes,
      contains('video/mp4'),
    );
    expect(
      PlatformFilePickerAdapter.audioTypeGroup.extensions,
      PlatformFilePickerAdapter.supportedAudioExtensions,
    );
  });

  test('mimeType carries a real media type, never the extension', () async {
    final source = await PlatformFilePickerAdapter.fromXFile(
      XFile.fromData(
        Uint8List.fromList(<int>[1]),
        path: 'backing.m4a',
        name: 'backing.m4a',
        // What Android hands over for an audio-only MPEG-4 container.
        mimeType: 'video/mp4',
      ),
    );

    // The stored type is the AUDIO one for both `m4a` and `mp4`: only the
    // audio stream is ever played, so the asset documents that.
    expect(source.mimeType, 'audio/mp4');
    expect(PlatformFilePickerAdapter.mimeTypesByExtension['mp4'], 'audio/mp4');
    expect(PlatformFilePickerAdapter.mimeTypesByExtension['mp3'], 'audio/mpeg');
    expect(
      PlatformFilePickerAdapter.mimeTypeOf('song.json'),
      'application/json',
    );
  });

  test('an unmapped extension falls back to the platform type', () async {
    const opus = 'audio/opus';
    expect(
      PlatformFilePickerAdapter.mimeTypeOf('take.opus', reported: opus),
      opus,
    );
    expect(PlatformFilePickerAdapter.mimeTypeOf('noextension'), isNull);
    expect(PlatformFilePickerAdapter.extensionOf('BACKING.M4A'), 'm4a');
  });
}
