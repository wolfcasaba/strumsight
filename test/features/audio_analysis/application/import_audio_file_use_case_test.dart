// R26 (audit MI4) — the audio-file import boundary.
//
// The CTA on the Analyze home screen used to say, honestly, that no import
// flow existed. These cells measure the flow that replaced it: what the user
// chose, what this build can decode, and — for everything it cannot — that a
// NAMED reason comes back instead of silence.
//
// The WAV decoder itself is already measured by
// `test/features/audio_analysis/data/audio_decoder_gateway_test.dart`; the
// malformed cells here prove the use case FORWARDS those typed failures
// rather than collapsing them into a nullable "nothing happened".
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/audio_analysis/application/import_audio_file_use_case.dart';
import 'package:strumsight/features/audio_analysis/data/input/analysis_audio_file_picker.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';

const _sampleRate = 48000;

/// 250 ms at [_sampleRate] — exactly `InputLimits.minDuration`, the shortest
/// clip the input boundary accepts.
const _minimumFrames = 12000;

/// Every container the picker OFFERS that no decoder in the tree can turn
/// into PCM. Offering them is deliberate: the user must be able to select the
/// file they actually have and be told why it cannot be used.
const _undecodable = <String>['mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac'];

void main() {
  test('a dismissed picker is a cancel, not a failure', () async {
    final outcome = await _useCase(null)();

    expect(outcome, isA<AudioFileImportCancelled>());
  });

  test('a picker that throws is reported, never swallowed', () async {
    final useCase = ImportAudioFileUseCase(
      picker: _FakePicker(error: StateError('no activity to pick with')),
    );

    final outcome = await useCase();

    expect(outcome, isA<AudioFileImportFailed>());
    expect(
      (outcome as AudioFileImportFailed).failure.code,
      FailureCode.unknown,
    );
  });

  group('containers this build cannot decode', () {
    for (final extension in _undecodable) {
      test('a .$extension file is reported as unsupported', () async {
        final outcome = await _useCase(
          PickedAudioFile(
            displayName: 'take.$extension',
            bytes: Uint8List.fromList(<int>[0, 1, 2, 3]),
          ),
        )();

        expect(outcome, isA<AudioFileImportUnsupported>());
        expect((outcome as AudioFileImportUnsupported).extension, extension);
      });
    }

    test('a name with no extension is unsupported, not a crash', () async {
      final outcome = await _useCase(
        PickedAudioFile(displayName: 'take', bytes: _wav()),
      )();

      expect(outcome, isA<AudioFileImportUnsupported>());
      expect((outcome as AudioFileImportUnsupported).extension, isNull);
    });

    test('the extension check is case-insensitive', () async {
      final outcome = await _useCase(
        PickedAudioFile(displayName: 'TAKE.WAV', bytes: _wav()),
      )();

      expect(outcome, isA<AudioFileImportReady>());
    });
  });

  test('a valid WAV becomes PCM carrying the file provenance', () async {
    final outcome = await _useCase(
      PickedAudioFile(displayName: 'riff-take.wav', bytes: _wav()),
    )();

    expect(outcome, isA<AudioFileImportReady>());
    final audio = (outcome as AudioFileImportReady).audio;
    expect(audio.source, AnalysisInputSource.importedFile);
    expect(audio.sourceDisplayName?.value, 'riff-take.wav');
    expect(audio.sampleRate, _sampleRate);
    expect(audio.channelCount, 1);
    expect(audio.samples, hasLength(_minimumFrames));
    // The samples are the decoded file, not silence: a flow that "works" on
    // an empty buffer would analyse nothing and still show a result.
    expect(audio.samples.every((sample) => sample.abs() > 0), isTrue);
  });

  test('a stereo WAV keeps its original channel count', () async {
    final outcome = await _useCase(
      PickedAudioFile(displayName: 'stereo.wav', bytes: _wav(channels: 2)),
    )();

    final audio = (outcome as AudioFileImportReady).audio;
    expect(audio.channelCount, 2);
    expect(audio.samples, hasLength(_minimumFrames));
  });

  group('malformed and out-of-bounds WAV files fail in a named way', () {
    final cases = <({String label, Uint8List bytes, String code})>[
      (
        label: 'bytes that are not RIFF at all',
        bytes: Uint8List.fromList(List<int>.filled(64, 7)),
        code: FailureCode.audioInvalidRiff,
      ),
      (
        label: 'a header cut off mid-fmt',
        bytes: Uint8List.sublistView(_wav(), 0, 30),
        code: FailureCode.audioTruncatedChunk,
      ),
      (
        label: 'a file shorter than the RIFF header itself',
        bytes: Uint8List.fromList(<int>[0x52, 0x49, 0x46, 0x46]),
        code: FailureCode.audioInvalidRiff,
      ),
      (
        label: 'a data chunk of zero length',
        bytes: _wav(frames: 0),
        code: FailureCode.audioTruncatedChunk,
      ),
      (
        label: 'a clip shorter than the minimum analysable duration',
        bytes: _wav(frames: 2000),
        code: FailureCode.audioClipTooShort,
      ),
      (
        label: 'an unsupported bit depth (24-bit)',
        bytes: _wav(bitsPerSample: 24),
        code: FailureCode.audioUnsupportedBitDepth,
      ),
    ];
    for (final testCase in cases) {
      test('${testCase.label} is rejected by code', () async {
        final outcome = await _useCase(
          PickedAudioFile(displayName: 'broken.wav', bytes: testCase.bytes),
        )();

        expect(outcome, isA<AudioFileImportFailed>());
        expect(
          (outcome as AudioFileImportFailed).failure.code,
          testCase.code,
          reason: testCase.label,
        );
      });
    }
  });
}

ImportAudioFileUseCase _useCase(PickedAudioFile? file) =>
    ImportAudioFileUseCase(picker: _FakePicker(file: file));

final class _FakePicker implements AnalysisAudioFilePicker {
  _FakePicker({this.file, this.error});

  final PickedAudioFile? file;
  final Object? error;

  @override
  Future<PickedAudioFile?> pickAnalysisAudioFile() async {
    final thrown = error;
    if (thrown != null) throw thrown;
    return file;
  }
}

/// A real, byte-exact RIFF/WAVE buffer — the shape a phone recorder or a DAW
/// export writes, so the cells above exercise the shipped decoder rather than
/// a hand-made stand-in.
Uint8List _wav({
  int frames = _minimumFrames,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final frameBytes = channels * (bitsPerSample ~/ 8);
  final dataLength = frames * frameBytes;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, 36 + dataLength, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, _sampleRate, Endian.little);
  data.setUint32(28, _sampleRate * frameBytes, Endian.little);
  data.setUint16(32, frameBytes, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, dataLength, Endian.little);
  if (bitsPerSample == 16) {
    for (var offset = 44; offset < bytes.length; offset += 2) {
      data.setInt16(offset, 8192, Endian.little);
    }
  }
  return bytes;
}
