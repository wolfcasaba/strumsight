import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

import '../../data/shadow/chord_shadow_candidate.dart';
import '../../model/recognition_runtime_info.dart';
import '../dsp/cqt_extractor.dart';
import 'chord_crnn.dart';

/// The typed outcome of trying to bring the shipped chord CRNN up for a
/// shadow run (E14-R26, ADR 0549 D1).
///
/// Fail-VISIBLE, like `ModelActivation` on the strum side: a missing,
/// truncated or tampered asset produces a [FallbackReason], never a silent
/// "no chord shadow today". The Lab renders the reason; the snapshot
/// serialises it.
@immutable
class ChordShadowActivation {
  const ChordShadowActivation._({this.runner, this.reason, this.sha256});

  /// The model parsed and (when a hash was demanded) matched it.
  factory ChordShadowActivation.activated(
    ChordCrnnShadowRunner runner,
    String sha256,
  ) => ChordShadowActivation._(runner: runner, sha256: sha256);

  /// The model did not come up; [reason] says why in a closed code.
  factory ChordShadowActivation.fallback(FallbackReason reason) =>
      ChordShadowActivation._(reason: reason);

  final ChordCrnnShadowRunner? runner;
  final FallbackReason? reason;

  /// SHA-256 (hex) of the bytes ACTUALLY read — never a value copied out of
  /// the manifest.
  final String? sha256;

  bool get isActivated => runner != null && reason == null;

  /// Parses [bytes] and, when [expectedSha256] is given, refuses to activate
  /// unless the hash of the bytes in hand matches it.
  ///
  /// The integrity check is deliberately fail-CLOSED: a mismatch is
  /// [FallbackReason.parseFailed] with no model, not "load it anyway and
  /// hope". A model whose bytes are not the reviewed bytes has no measured
  /// behaviour at all.
  static ChordShadowActivation activate(
    Uint8List? bytes, {
    String? expectedSha256,
  }) {
    if (bytes == null || bytes.isEmpty) {
      return ChordShadowActivation.fallback(FallbackReason.assetMissing);
    }
    final digest = crypto.sha256.convert(bytes).toString();
    if (expectedSha256 != null && digest != expectedSha256) {
      return ChordShadowActivation.fallback(FallbackReason.parseFailed);
    }
    final ChordCrnn net;
    try {
      net = ChordCrnn.parse(ByteData.sublistView(bytes));
    } on FormatException {
      // A typed, reported outcome — NOT a swallowed failure: the caller
      // stores the reason and the Lab shows it.
      return ChordShadowActivation.fallback(FallbackReason.parseFailed);
    } on RangeError {
      return ChordShadowActivation.fallback(FallbackReason.parseFailed);
    }
    if (net.nBins != CqtExtractor.nBins ||
        net.nClasses != ChordCrnnShadowRunner.majmin25Labels.length) {
      return ChordShadowActivation.fallback(FallbackReason.shapeMismatch);
    }
    return ChordShadowActivation.activated(
      ChordCrnnShadowRunner._(net, digest),
      digest,
    );
  }
}

/// Runs the SHIPPED chord CRNN (`assets/ml/chord_crnn.bin`) as a SHADOW
/// candidate next to the live NNLS-chroma → dictionary → Viterbi path
/// (SDD Ch14 §4.5, Kör 26, ADR 0549).
///
/// Two drivers, one model:
///
/// * [runClip] — decode a whole recorded buffer in one pass. This is what
///   the Lab's capture-and-compare uses, and it is the DETERMINISTIC one:
///   the same PCM always produces the same verdict list, which is what makes
///   the agreement report testable at all.
/// * [addPcm]/[poll] — the streaming trailing-window adapter for a live
///   run: a fixed PCM ring of exactly [windowFrames] CQT hops is re-analysed
///   every [emitEveryFrames] hops and the LAST frame's posterior is the
///   current verdict.
///
/// **Honest limits of the streaming adapter (ADR 0549 D4, chunk 018).**
/// `CqtExtractor` centre-pads whatever buffer it is given, so the newest
/// frame of a trailing window sees padding where a continuous CQT would see
/// future audio, and the GRU restarts from a zero state on every window. The
/// streaming verdict is therefore NOT bit-identical to [runClip] over the
/// same audio, and by how much it differs on real guitar is
/// **NOT MEASURED** — no device, no corpus on this box. Nothing downstream
/// treats the difference as zero: the shadow report is a comparison surface,
/// never an input to recognition.
///
/// Nothing this class produces may reach a `LiveFrame`, a score or a pixel
/// (`RecognitionRolloutStage.shadow.isUserVisible == false`).
class ChordCrnnShadowRunner implements ChordShadowCandidateSource {
  ChordCrnnShadowRunner._(this._net, this.sha256);

  final ChordCrnn _net;

  /// SHA-256 (hex) of the weight bytes this instance parsed.
  final String sha256;

  /// The SHA-256 of the shipped `assets/ml/chord_crnn.bin`, as declared by
  /// `assets/ml/model_manifest.json`.
  ///
  /// It is a CONSTANT here rather than a runtime manifest read because the
  /// manifest is not a bundled asset (only the `.bin` files are), so the app
  /// cannot open it on device. The constant cannot drift: a test hashes the
  /// real asset bytes, reads the manifest's declared value, and fails if the
  /// three disagree — so replacing the model without updating this line
  /// turns CI red instead of shipping an unverified blob.
  static const String shippedChordModelSha256 =
      '8f7596d45784fecd472be3bda141599e'
      '77a690edc8d526b85a9929532709fc74';

  /// The only `CCRN` container version this build parses — `ChordCrnn.parse`
  /// rejects anything else, so an activated runner is always this version.
  static const int chordModelFormatVersion = 1;

  /// The model's own analysis window (`ml/chords/train_chord.py` trains on
  /// 100 CQT frames). Carried over unchanged — this is the model's contract,
  /// not a tunable.
  static const int windowFrames = 100;

  /// How often the streaming adapter re-runs the window, in CQT hops
  /// (8 × 2048 / 22050 ≈ 0.74 s). A shadow REPORTING cadence: it trades CPU
  /// against comparison density and touches no recognition threshold.
  static const int emitEveryFrames = 8;

  /// The 25 majmin labels, index-aligned to `ml/chords/labels.py`
  /// (0 = N.C., 1..12 = C..B major, 13..24 = C..B minor). Duplicated from
  /// `MlChordDecoder.majmin25Labels` rather than imported, because
  /// `features/live` must not depend on `features/analyze`; a parity cell
  /// pins the two lists equal.
  static const List<String> majmin25Labels = [
    'N.C.',
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
    'Cm',
    'C#m',
    'Dm',
    'D#m',
    'Em',
    'Fm',
    'F#m',
    'Gm',
    'G#m',
    'Am',
    'A#m',
    'Bm',
  ];

  /// Seconds per CQT frame — the chord candidate's hop.
  static double get frameHopSec => CqtExtractor.hop / CqtExtractor.sr;

  // --- clip driver ---------------------------------------------------------

  List<ChordShadowVerdict> _clipVerdicts = const [];

  /// Decodes [pcm] in ONE pass and keeps the result as the source
  /// [verdictAtSeconds] answers from. Frame `i` is stamped at
  /// `i * frameHopSec` seconds, matching the CQT grid.
  ///
  /// Empty or unusable input yields an empty list — never a fabricated
  /// verdict.
  List<ChordShadowVerdict> runClip(List<double> pcm, int sampleRate) {
    if (pcm.isEmpty || sampleRate <= 0) {
      _clipVerdicts = const [];
      return _clipVerdicts;
    }
    final f32 = pcm is Float32List ? pcm : Float32List.fromList(pcm);
    final cqt = CqtExtractor().extract(f32, sampleRate);
    if (cqt.isEmpty) {
      _clipVerdicts = const [];
      return _clipVerdicts;
    }
    _clipVerdicts = _decode(cqt, startFrame: 0);
    return _clipVerdicts;
  }

  /// The verdict covering [timeSec], i.e. the newest one whose own timestamp
  /// is at or before it. `null` before the first verdict exists — the
  /// observer records that as "candidate unavailable", never as N.C.
  @override
  ChordShadowVerdict? verdictAtSeconds(double timeSec) {
    if (_streamVerdict != null) {
      return timeSec >= _streamVerdict!.timeSec ? _streamVerdict : null;
    }
    if (_clipVerdicts.isEmpty || !timeSec.isFinite || timeSec < 0) return null;
    final index = (timeSec / frameHopSec).floor();
    if (index < 0) return null;
    return _clipVerdicts[math.min(index, _clipVerdicts.length - 1)];
  }

  // --- streaming driver ----------------------------------------------------

  Float64List? _ring;
  int _ringWrite = 0;
  int _ringFilled = 0;
  int _sinceEmit = 0;
  int _inputSampleRate = 0;
  int _samplesSeen = 0;
  ChordShadowVerdict? _streamVerdict;

  /// Window length in INPUT samples for [sampleRate].
  int _windowSamples(int sampleRate) =>
      (windowFrames * CqtExtractor.hop * sampleRate / CqtExtractor.sr).ceil();

  int _emitSamples(int sampleRate) =>
      (emitEveryFrames * CqtExtractor.hop * sampleRate / CqtExtractor.sr)
          .ceil();

  /// Feeds live PCM. The ring is allocated ONCE, on the first chunk, and
  /// never grows: a ten-minute stream costs the same bytes as the first
  /// window.
  void addPcm(List<double> pcm, int sampleRate) {
    if (sampleRate <= 0 || pcm.isEmpty) return;
    final ring = _ensureRing(sampleRate);
    for (var i = 0; i < pcm.length; i++) {
      ring[_ringWrite] = pcm[i];
      _ringWrite = (_ringWrite + 1) % ring.length;
      if (_ringFilled < ring.length) _ringFilled++;
    }
    _samplesSeen += pcm.length;
    _sinceEmit += pcm.length;
  }

  /// Re-runs the trailing window when enough new audio has arrived and the
  /// window is full; returns the current verdict (possibly the previous one)
  /// or `null` while the window is still filling.
  ChordShadowVerdict? poll() {
    final ring = _ring;
    if (ring == null) return null;
    if (_ringFilled < ring.length) return null;
    if (_sinceEmit < _emitSamples(_inputSampleRate)) return _streamVerdict;
    _sinceEmit = 0;

    // Oldest-first copy of the window — the ONLY per-emit allocation, and it
    // is a fixed size.
    final window = Float32List(ring.length);
    // The ring is full, so the oldest sample sits exactly at the write head.
    final start = _ringWrite;
    for (var i = 0; i < ring.length; i++) {
      window[i] = ring[(start + i) % ring.length];
    }
    final cqt = CqtExtractor().extract(window, _inputSampleRate);
    if (cqt.isEmpty) return _streamVerdict;

    final decoded = _decode(cqt, startFrame: 0);
    if (decoded.isEmpty) return _streamVerdict;
    // The window's newest frame is the current verdict, stamped on the
    // ENGINE clock (total samples fed / rate), not on the window's own grid.
    final last = decoded.last;
    _streamVerdict = ChordShadowVerdict(
      timeSec: _samplesSeen / _inputSampleRate,
      label: last.label,
      posterior: last.posterior,
    );
    return _streamVerdict;
  }

  Float64List _ensureRing(int sampleRate) {
    final existing = _ring;
    if (existing != null && sampleRate == _inputSampleRate) return existing;
    _inputSampleRate = sampleRate;
    _ringWrite = 0;
    _ringFilled = 0;
    _sinceEmit = 0;
    final ring = Float64List(_windowSamples(sampleRate));
    _ring = ring;
    return ring;
  }

  /// The allocated streaming ring length (0 before the first chunk).
  /// Exposed so a test can assert it is constant across N chunks.
  @visibleForTesting
  int get debugRingLength => _ring?.length ?? 0;

  // --- shared ---------------------------------------------------------------

  List<ChordShadowVerdict> _decode(
    List<Float32List> cqt, {
    required int startFrame,
  }) {
    final posteriors = _net.infer(cqt);
    final hop = frameHopSec;
    return <ChordShadowVerdict>[
      for (var i = 0; i < posteriors.length; i++)
        _verdictFrom(posteriors[i], (startFrame + i) * hop),
    ];
  }

  static ChordShadowVerdict _verdictFrom(List<double> posterior, double t) {
    var best = 0;
    for (var c = 1; c < posterior.length; c++) {
      if (posterior[c] > posterior[best]) best = c;
    }
    return ChordShadowVerdict(
      timeSec: t,
      label: best < majmin25Labels.length ? majmin25Labels[best] : 'N.C.',
      posterior: posterior[best],
    );
  }
}
