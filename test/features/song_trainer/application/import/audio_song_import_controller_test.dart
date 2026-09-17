// K3/A4 — the audio import operation, end to end, without a platform channel.
//
// The decoder and the analyzer are the only seams that are faked; everything
// below them is the production path: the real limit profile, the real mapper,
// the real normalizer/validator, the real content-hash asset store and the
// real repository contract. The cells measure the four outcomes that matter:
// a draft with its backing audio attached, a named refusal instead of a
// half-written song, cancellation that writes nothing, and a scratch file
// that does not survive the operation.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/platform_audio_decoder.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/song_trainer/application/import/audio_song_import_controller.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_effect.dart';
import 'package:strumsight/features/song_trainer/data/importers/audio_song_draft_mapper.dart';
import 'package:strumsight/features/song_trainer/data/importers/import_limits.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('k3-audio-import');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<_Rig> rig({
    AudioPcmDecode? decode,
    AudioClipAnalyze? analyze,
    int maxSourceBytes = maxAudioImportSourceBytes,
  }) async {
    final repository = InMemorySongRepository(
      clock: () => DateTime.utc(2026, 9, 17),
    );
    final assets = await FileSongAssetRepository.openAtDirectory(
      root: Directory('${root.path}/assets'),
      clock: () => DateTime.utc(2026, 9, 17),
    );
    final scratchRoot = Directory('${root.path}/audio-import');
    final controller = AudioSongImportController(
      decode: decode ?? _decodeOk,
      analyze: analyze ?? _analyzeGcd,
      repository: () => repository,
      assetRepository: () => assets,
      workspaceRoot: () async => scratchRoot,
      clock: () => DateTime.utc(2026, 9, 17),
      maxSourceBytes: maxSourceBytes,
    );
    addTearDown(controller.dispose);
    return _Rig(
      controller: controller,
      repository: repository,
      scratchRoot: scratchRoot,
    );
  }

  test('an mp3 becomes a draft song with its audio attached', () async {
    final harness = await rig();
    final effects = <SongImportEffect>[];
    harness.controller.effects.listen(effects.add);

    harness.controller.beginSelection();
    await harness.controller.selectSource(_source());

    expect(
      harness.controller.state.phase,
      AudioSongImportPhase.success,
      reason: harness.controller.state.failureCode,
    );
    expect(effects.whereType<SongImportSucceededEffect>(), hasLength(1));

    final document = await harness.only();
    expect(document.source.type, SongSourceType.audioAnalysis);
    expect(document.source.originalFileName, 'my-song.mp3');
    expect(
      document.source.warningSummary,
      contains(AudioSongDraftWarningCode.reviewRequired),
    );
    final backing = document.tracks.whereType<BackingAudioTrack>().single;
    expect(document.assets, hasLength(1));
    expect(document.assets.single.id, backing.assetId);
    expect(document.assets.single.extension, 'mp3');
    expect(document.assets.single.byteLength, _bytes.length);
    expect(document.tracks.whereType<ChordTrack>().single.events, hasLength(3));

    // The scratch copy exists only for the length of the operation.
    final leftovers = harness.scratchRoot.existsSync()
        ? harness.scratchRoot.listSync()
        : const <FileSystemEntity>[];
    expect(leftovers, isEmpty);
  });

  test('a declared size over the audio ceiling is refused by name', () async {
    final harness = await rig(maxSourceBytes: 8);

    harness.controller.beginSelection();
    await harness.controller.selectSource(_source());

    expect(harness.controller.state.phase, AudioSongImportPhase.failure);
    expect(
      harness.controller.state.failureCode,
      AudioSongImportFailureCode.sourceBytesExceeded,
    );
    expect(await harness.count(), 0);
  });

  test('a container the app cannot play is refused before any read', () async {
    final harness = await rig();

    harness.controller.beginSelection();
    await harness.controller.selectSource(_source(name: 'notes.txt'));

    expect(
      harness.controller.state.failureCode,
      AudioSongImportFailureCode.unsupportedFormat,
    );
    expect(await harness.count(), 0);
  });

  test('a decoder failure surfaces its own stable code', () async {
    final harness = await rig(decode: _decodeUnsupportedPlatform);

    harness.controller.beginSelection();
    await harness.controller.selectSource(_source());

    expect(
      harness.controller.state.failureCode,
      FailureCode.audioUnsupportedPlatform,
    );
    expect(await harness.count(), 0);
  });

  test('an analysis with no chords writes nothing at all', () async {
    final harness = await rig(analyze: _analyzeEmpty);

    harness.controller.beginSelection();
    await harness.controller.selectSource(_source());

    expect(
      harness.controller.state.failureCode,
      AudioSongDraftFailureCode.noChords,
    );
    expect(
      await harness.count(),
      0,
      reason: 'a 0-event song must never be created',
    );
  });

  test('cancelling mid-analysis commits nothing', () async {
    final gate = Completer<AnalyzeResult>();
    final harness = await rig(analyze: (_, _) => gate.future);
    final effects = <SongImportEffect>[];
    harness.controller.effects.listen(effects.add);

    harness.controller.beginSelection();
    final running = harness.controller.selectSource(_source());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    harness.controller.cancel();
    gate.complete(_gcdResult());
    await running;

    expect(harness.controller.state.phase, AudioSongImportPhase.cancelled);
    expect(effects.whereType<SongImportSucceededEffect>(), isEmpty);
    expect(await harness.count(), 0);
  });
}

final class _Rig {
  _Rig({
    required this.controller,
    required this.repository,
    required this.scratchRoot,
  });

  final AudioSongImportController controller;
  final InMemorySongRepository repository;
  final Directory scratchRoot;

  Future<int> count() async {
    final listed = await repository.list(const SongQuery());
    return (listed as Success<List<SongSummary>>).value.length;
  }

  Future<SongDocument> only() async {
    final listed = await repository.list(const SongQuery());
    final summaries = (listed as Success<List<SongSummary>>).value;
    expect(summaries, hasLength(1));
    final loaded = await repository.get(summaries.single.id);
    return (loaded as Success<SongDocument?>).value!;
  }
}

final Uint8List _bytes = Uint8List.fromList(
  List<int>.generate(2048, (index) => index % 251),
);

ImportSourceFile _source({String name = 'my-song.mp3'}) => ImportSourceFile(
  displayName: name,
  byteLength: _bytes.length,
  mimeType: 'audio/mpeg',
  openRead: () => Stream<List<int>>.value(_bytes),
);

Future<AppResult<DecodedPcm>> _decodeOk(String path) async {
  // The controller must have written the picked bytes somewhere real: the
  // platform decoder takes a PATH, and a fake that ignores it would hide a
  // missing write.
  expect(File(path).existsSync(), isTrue, reason: 'no scratch file at $path');
  final samples = Float32List(16000 * 6);
  for (var index = 0; index < samples.length; index++) {
    samples[index] = (index % 100) / 100 - 0.5;
  }
  return Success<DecodedPcm>(DecodedPcm(sampleRate: 16000, samples: samples));
}

Future<AppResult<DecodedPcm>> _decodeUnsupportedPlatform(String path) async {
  return const Failure<DecodedPcm>(
    AudioFailure(code: FailureCode.audioUnsupportedPlatform, retryable: false),
  );
}

Future<AnalyzeResult> _analyzeGcd(List<double> pcm, int sampleRate) async =>
    _gcdResult();

Future<AnalyzeResult> _analyzeEmpty(List<double> pcm, int sampleRate) async =>
    const AnalyzeResult(
      durationSec: 6,
      bpm: 120,
      chords: <TimelineChord>[],
      strums: <TimelineStrum>[],
    );

AnalyzeResult _gcdResult() => const AnalyzeResult(
  durationSec: 6,
  bpm: 120,
  chords: <TimelineChord>[
    TimelineChord(label: 'G', startSec: 0, endSec: 2),
    TimelineChord(label: 'C', startSec: 2, endSec: 4),
    TimelineChord(label: 'D', startSec: 4, endSec: 6),
  ],
  strums: <TimelineStrum>[
    TimelineStrum(
      direction: StrumDirection.down,
      timeSec: 0.5,
      confidence: 0.9,
    ),
  ],
);
