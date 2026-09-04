import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/engine/ml/model_activation.dart';
import 'package:strumsight/features/live/engine/ml/strum_crnn.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/model/recognition_runtime_info.dart';

import '../../support/synth.dart';

const sr = 44100;

/// E14-R03 (ADR 0355): the loader must be able to SAY which model activated
/// or why it fell back — the fallback BEHAVIOUR (heuristic keeps running)
/// stays bit-identical; only the observability changes.
void main() {
  group('StrumCrnn.activate — 1. real 3-class asset activates', () {
    test('activated, nClasses == 3, measured id/hash, no fallback', () {
      final path = 'assets/ml/strum_crnn_live_3c.bin';
      final bytes = File(path).readAsBytesSync();
      final expectedSha256 = crypto.sha256.convert(bytes).toString();

      final result = StrumCrnn.activate(path);

      expect(result.model, isNotNull);
      expect(result.model!.nClasses, 3);
      expect(result.info.fallbackReason, isNull);
      expect(result.info.strumModelId, 'strum_crnn_live_3c.bin');
      expect(result.info.strumModelSha256, expectedSha256);
      expect(result.info.strumModelVersion, 1);
    });

    test('tryLoad keeps returning StrumCrnn? unchanged (R1 delegation)', () {
      final model = StrumCrnn.tryLoad('assets/ml/strum_crnn_live_3c.bin');
      expect(model, isNotNull);
      expect(model, isA<StrumCrnn>());
    });
  });

  group('StrumCrnn.activate — 2. fallback matrix, one cell per code', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('strumsight_activation_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('assetMissing: the file does not exist', () {
      final result = StrumCrnn.activate('${tempDir.path}/nope.bin');
      expect(result.model, isNull);
      expect(result.info.fallbackReason, FallbackReason.assetMissing);
    });

    test('assetUnreadable: the path is a directory, not a file', () {
      final dirPath = '${tempDir.path}/a_directory';
      Directory(dirPath).createSync();

      final result = StrumCrnn.activate(dirPath);

      expect(result.model, isNull);
      expect(result.info.fallbackReason, FallbackReason.assetUnreadable);
    });

    test('parseFailed: bad magic bytes', () {
      final badMagic = File('${tempDir.path}/bad_magic.bin');
      final header = ByteData(8)
        ..setUint8(0, 'X'.codeUnitAt(0))
        ..setUint8(1, 'X'.codeUnitAt(0))
        ..setUint8(2, 'X'.codeUnitAt(0))
        ..setUint8(3, 'X'.codeUnitAt(0))
        ..setUint32(4, 1, Endian.little);
      badMagic.writeAsBytesSync(header.buffer.asUint8List());

      final result = StrumCrnn.activate(badMagic.path);

      expect(result.model, isNull);
      expect(result.info.fallbackReason, FallbackReason.parseFailed);
    });

    test('parseFailed: unsupported version', () {
      final badVersion = File('${tempDir.path}/bad_version.bin');
      final header = ByteData(8)
        ..setUint8(0, 'S'.codeUnitAt(0))
        ..setUint8(1, 'S'.codeUnitAt(0))
        ..setUint8(2, 'M'.codeUnitAt(0))
        ..setUint8(3, 'L'.codeUnitAt(0))
        ..setUint32(4, 99, Endian.little);
      badVersion.writeAsBytesSync(header.buffer.asUint8List());

      final result = StrumCrnn.activate(badVersion.path);

      expect(result.model, isNull);
      expect(result.info.fallbackReason, FallbackReason.parseFailed);
    });

    test('shapeMismatch: valid header, missing arrays', () {
      final truncated = File('${tempDir.path}/truncated.bin');
      final bytes = File('assets/ml/strum_crnn_live_3c.bin').readAsBytesSync();
      // Keep the valid SSML v1 header (8 bytes) but zero the array count so
      // CrnnStrumNet.parse throws on a missing required array, not on the
      // header check — the header/shape distinction is exactly what the
      // pre-check in StrumCrnn.activateBytes exists to make (ADR 0355 R8).
      truncated.writeAsBytesSync(bytes.sublist(0, 8) + [0, 0, 0, 0]);

      final result = StrumCrnn.activate(truncated.path);

      expect(result.model, isNull);
      expect(result.info.fallbackReason, FallbackReason.shapeMismatch);
    });

    test('disabledByFlag: the caller explicitly disabled the model', () {
      final info = RecognitionRuntimeInfo.fallback(
        FallbackReason.disabledByFlag,
        sampleRate: 44100,
      );

      final result = ModelActivation<StrumCrnn>.disabled(info);

      expect(result.model, isNull);
      expect(result.info.fallbackReason, FallbackReason.disabledByFlag);
    });
  });

  group('3. fallback preserves pipeline behaviour (heuristic still verdicts)', () {
    test('garbage weights bytes -> heuristic still verdicts a real strum', () {
      final pipeline = LivePipeline(sampleRate: sr, crnnWeights: Uint8List(16));

      expect(pipeline.debugStrumClassifier, isA<HeuristicStrumClassifier>());
      expect(pipeline.runtimeInfo.fallbackReason, isNotNull);

      // Same driven signal + assertion shape as the pre-round
      // live_pipeline_test.dart baseline — a real onset must still
      // produce a directional verdict via the heuristic (falsified in
      // the handoff note, docs/rounds/e14-r03-model-activation-telemetry.md §10).
      final signal = strumSignal(lowFirst: true, seconds: 0.4);
      final frames = <LiveFrame>[];
      for (var i = 0; i < signal.length; i += 1024) {
        final end = (i + 1024 < signal.length) ? i + 1024 : signal.length;
        frames.addAll(pipeline.addChunk(signal.sublist(i, end)));
      }
      expect(
        frames.any((f) => f.latestStrum != null),
        isTrue,
        reason: 'fallback must still yield a heuristic verdict',
      );
    });

    test('valid weights -> live CRNN classifier activates, info matches', () {
      final bytes = File('assets/ml/strum_crnn_live_3c.bin').readAsBytesSync();
      final pipeline = LivePipeline(sampleRate: 44100, crnnWeights: bytes);

      expect(
        pipeline.debugStrumClassifier,
        isNot(isA<HeuristicStrumClassifier>()),
      );
      expect(pipeline.runtimeInfo.fallbackReason, isNull);
      expect(
        pipeline.runtimeInfo.strumModelSha256,
        crypto.sha256.convert(bytes).toString(),
      );
    });

    test('no weights -> heuristic, runtimeInfo says assetMissing', () {
      final pipeline = LivePipeline(sampleRate: 44100);

      expect(pipeline.debugStrumClassifier, isA<HeuristicStrumClassifier>());
      expect(pipeline.runtimeInfo.fallbackReason, FallbackReason.assetMissing);
    });
  });

  group('4. redaction canary — fallback values never leak the path', () {
    test('a unique temp-dir segment never appears in toString()/toJson()', () {
      final tempRoot = Directory.systemTemp.createTempSync(
        'strumsight_canary_',
      );
      addTearDown(() => tempRoot.deleteSync(recursive: true));
      final canarySegment = tempRoot.path.split(Platform.pathSeparator).last;
      final missingPath = '${tempRoot.path}/does_not_exist.bin';

      final result = StrumCrnn.activate(missingPath);

      expect(result.model, isNull);
      final rendered = result.info.toString();
      final encoded = json.encode(result.info.toJson());

      expect(rendered.contains(canarySegment), isFalse);
      expect(rendered.contains(tempRoot.path), isFalse);
      expect(encoded.contains(canarySegment), isFalse);
      expect(encoded.contains(tempRoot.path), isFalse);
      // The fallback shape never carries any path-derived value at all.
      expect(result.info.strumModelId, 'none');
    });
  });
}
