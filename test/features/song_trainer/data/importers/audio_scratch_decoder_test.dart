// K3 — the bytes → path adapter the platform decoder needs.
//
// A plain (non-widget) cell on purpose: real `dart:io` work never completes
// inside `testWidgets`' fake-async zone, which is exactly why this file write
// lives here and not in the import controller.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/platform_audio_decoder.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/importers/audio_scratch_decoder.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('k3-scratch');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('the decoder sees the picked bytes on disk, and only then', () async {
    final bytes = Uint8List.fromList(<int>[9, 8, 7, 6, 5]);
    Uint8List? seen;
    var existedDuringDecode = false;
    final decoder = AudioScratchDecoder(
      workspaceRoot: () async => root,
      decode: (path) async {
        final file = File(path);
        existedDuringDecode = file.existsSync();
        seen = file.readAsBytesSync();
        expect(path, endsWith('.mp3'));
        return Success<DecodedPcm>(
          DecodedPcm(sampleRate: 8000, samples: Float32List(8)),
        );
      },
    );

    final result = await decoder.decodeBytes(bytes, 'mp3');

    expect(result, isA<Success<DecodedPcm>>());
    expect(existedDuringDecode, isTrue);
    expect(seen, bytes);
    expect(root.listSync(), isEmpty, reason: 'the scratch copy must not stay');
  });

  test('a decoder failure still removes the scratch copy', () async {
    final decoder = AudioScratchDecoder(
      workspaceRoot: () async => root,
      decode: (path) async {
        return const Failure<DecodedPcm>(
          AudioFailure(code: FailureCode.audioDecoderFailed, retryable: false),
        );
      },
    );

    final result = await decoder.decodeBytes(
      Uint8List.fromList(<int>[1, 2, 3]),
      'm4a',
    );

    expect(
      (result as Failure<DecodedPcm>).error.code,
      FailureCode.audioDecoderFailed,
    );
    expect(root.listSync(), isEmpty);
  });

  test('a throwing decoder still removes the scratch copy', () async {
    final decoder = AudioScratchDecoder(
      workspaceRoot: () async => root,
      decode: (path) async => throw StateError('boom'),
    );

    await expectLater(
      decoder.decodeBytes(Uint8List.fromList(<int>[1]), 'wav'),
      throwsStateError,
    );
    expect(root.listSync(), isEmpty);
  });

  test('the workspace directory is created when it is missing', () async {
    final nested = Directory('${root.path}/a/b/c');
    final decoder = AudioScratchDecoder(
      workspaceRoot: () async => nested,
      decode: (path) async {
        expect(File(path).parent.path, nested.path);
        return Success<DecodedPcm>(
          DecodedPcm(sampleRate: 8000, samples: Float32List(4)),
        );
      },
    );

    final result = await decoder.decodeBytes(
      Uint8List.fromList(<int>[7]),
      'ogg',
    );

    expect(result, isA<Success<DecodedPcm>>());
    expect(nested.existsSync(), isTrue);
  });
}
