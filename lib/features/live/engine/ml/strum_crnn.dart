import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../dsp/log_mel_extractor.dart';
import '../dsp/strum_direction_classifier.dart';
import '../../../../core/music/strum.dart';
import '../../model/recognition_runtime_info.dart';
import 'crnn_frontend.dart';
import 'crnn_strum_net.dart';
import 'model_activation.dart';

/// The deployment facade over [CrnnStrumNet]: raw clip audio in, per-onset
/// ↓/↑ verdicts out, running the EXACT training-pipeline chain (linear
/// resample to 16 kHz → parity-contracted log-mel → PRE/POST window at the
/// onset → forward pass).
///
/// Batch-first by design (ml-track P1.3 note, 2026-07-13): the model window
/// needs ~240 ms of post-onset audio, which the LIVE path's 70 ms verdict
/// deadline cannot wait for — so the CRNN serves the Analyze/clip path, where
/// the whole recording exists, and the live path keeps the heuristic.
class StrumCrnn {
  StrumCrnn(this._net)
    : _logMel = LogMelExtractor(sampleRate: CrnnFrontend.modelSampleRate);

  final CrnnStrumNet _net;
  final LogMelExtractor _logMel;

  /// Output class count of the wrapped net (see [CrnnStrumNet.nClasses]).
  int get nClasses => _net.nClasses;

  /// Loads the weights asset from [path] and reports the outcome TYPED (ADR
  /// 0355): [ModelActivation.activated] with the loaded model, or
  /// [ModelActivation.fallback] with a stable [FallbackReason] — never the
  /// raw exception text (platform/locale-dependent, can carry a filesystem
  /// path). The caller's behaviour is unchanged either way: a fallback still
  /// means "use the heuristic", this only makes the outcome observable.
  static ModelActivation<StrumCrnn> activate(String path) {
    final Uint8List bytes;
    try {
      bytes = File(path).readAsBytesSync();
    } on PathNotFoundException {
      return ModelActivation.fallback(
        RecognitionRuntimeInfo.fallback(
          FallbackReason.assetMissing,
          sampleRate: CrnnFrontend.modelSampleRate,
        ),
      );
    } catch (_) {
      return ModelActivation.fallback(
        RecognitionRuntimeInfo.fallback(
          FallbackReason.assetUnreadable,
          sampleRate: CrnnFrontend.modelSampleRate,
        ),
      );
    }

    final netActivation = activateBytes(
      bytes,
      modelId: path.split(RegExp(r'[\\/]')).last,
      sampleRate: CrnnFrontend.modelSampleRate,
    );
    final net = netActivation.model;
    if (net == null) {
      return ModelActivation.fallback(netActivation.info);
    }
    return ModelActivation.activated(StrumCrnn(net), netActivation.info);
  }

  /// Activates a CRNN from already-loaded weight [bytes] under [modelId] —
  /// shared by [activate]'s file-backed path and the live pipeline's
  /// isolate-crossed bytes (r169 keeps rootBundle main-isolate-only, so the
  /// live path never opens files itself). Reads the 8-byte `SSML` header
  /// itself BEFORE calling [CrnnStrumNet.parse], so a bad magic/version is
  /// reported as [FallbackReason.parseFailed] rather than folding into
  /// [FallbackReason.shapeMismatch] — both throw [FormatException] from that
  /// call otherwise (ADR 0355 "Negative/price": a documented mini-duplication
  /// of the binary contract [CrnnStrumNet.parse] already enforces).
  static ModelActivation<CrnnStrumNet> activateBytes(
    Uint8List bytes, {
    required String modelId,
    required int sampleRate,
  }) {
    final magicOk =
        bytes.length >= 8 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'SSML';
    final version = magicOk
        ? ByteData.sublistView(bytes, 4, 8).getUint32(0, Endian.little)
        : -1;
    if (!magicOk || version != 1) {
      return ModelActivation.fallback(
        RecognitionRuntimeInfo.fallback(
          FallbackReason.parseFailed,
          sampleRate: sampleRate,
        ),
      );
    }

    final CrnnStrumNet net;
    try {
      net = CrnnStrumNet.parse(ByteData.sublistView(bytes));
    } catch (_) {
      return ModelActivation.fallback(
        RecognitionRuntimeInfo.fallback(
          FallbackReason.shapeMismatch,
          sampleRate: sampleRate,
        ),
      );
    }

    return ModelActivation.activated(
      net,
      RecognitionRuntimeInfo(
        strumModelId: modelId,
        strumModelVersion: version,
        strumModelSha256: crypto.sha256.convert(bytes).toString(),
        chordEngineId: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
        sampleRate: sampleRate,
        frontendVersion: RecognitionRuntimeInfo.frontendCrnnV1,
      ),
    );
  }

  /// Loads the weights asset from [path], or null when it is absent or
  /// unparseable — callers fall back to the heuristic, never crash (the
  /// model is an upgrade, not a dependency). A thin delegation kept
  /// byte-for-byte because six test files outside this round's scope pin
  /// this exact `StrumCrnn?` return type (ADR 0355 R1); prefer [activate]
  /// for the observable outcome.
  static StrumCrnn? tryLoad(String path) => activate(path).model;

  /// Classify the strum at each of [onsetTimes] (seconds) in [pcm].
  /// Label order is the training contract: 0 = down, 1 = up (ml/klangio.py).
  List<StrumClassification> classifyClip(
    Float64List pcm,
    int sampleRate,
    List<double> onsetTimes,
  ) {
    final pcm16k = CrnnFrontend.resampleLinear(
      pcm,
      sampleRate,
      CrnnFrontend.modelSampleRate,
    );
    final logmel = _logMel.process(pcm16k);
    return [for (final t in onsetTimes) _classifyWindow(logmel, t)];
  }

  StrumClassification _classifyWindow(
    List<Float64List> logmel,
    double onsetSec,
  ) {
    final probs = _net.forward(CrnnFrontend.windowAt(logmel, onsetSec));
    final up = probs[1] > probs[0];
    return StrumClassification(
      direction: up ? StrumDirection.up : StrumDirection.down,
      confidence: calibrate(up ? probs[1] : probs[0]),
    );
  }

  /// Raw softmax → empirical P(correct) for the BATCH model (r171, measured
  /// on the eval fold at labeled times, 2 013 strums): <0.7 → 62 %,
  /// 0.7–0.9 → 64 %, 0.9–0.97 → 73 %, 0.97–0.995 → 83 %, ≥0.995 → 96 % —
  /// better top-end calibration than the live 70 ms model (r170) because the
  /// full window is far more decisive, but still overconfident below 0.97.
  /// Keeps timeline/share-card percentages honest.
  static double calibrate(double p) {
    const knots = [
      (0.50, 0.60), (0.60, 0.62), (0.80, 0.64), //
      (0.935, 0.73), (0.9825, 0.83), (0.9975, 0.96), (1.00, 0.96),
    ];
    if (p <= knots.first.$1) return knots.first.$2;
    for (var i = 1; i < knots.length; i++) {
      if (p <= knots[i].$1) {
        final (x0, y0) = knots[i - 1];
        final (x1, y1) = knots[i];
        return y0 + (y1 - y0) * (p - x0) / (x1 - x0);
      }
    }
    return knots.last.$2;
  }
}
