import 'package:meta/meta.dart';

import '../../../app/config/recognition_rollout_stage.dart';
import '../domain/recognition/recognition_mode.dart';

/// Stable, machine-checkable reasons the strum-direction model fell back to
/// the heuristic classifier (ADR 0355) — never the raw exception text, which
/// is platform/locale-dependent and can carry a filesystem path.
enum FallbackReason {
  /// The weight bytes never arrived: the asset file doesn't exist on disk,
  /// or the caller passed a null byte source.
  assetMissing,

  /// The file exists but reading it threw (permission, directory, truncated
  /// I/O) — anything other than "not found".
  assetUnreadable,

  /// The first 8 header bytes don't match the binary contract: the magic
  /// isn't `SSML`, or the version isn't the one this build understands.
  parseFailed,

  /// The header parsed but the arrays inside didn't — a missing tensor or a
  /// dimension mismatch.
  shapeMismatch,

  /// The caller explicitly disabled the model — not an error.
  disabledByFlag,
}

/// Which recognizer produced a verdict, or why it fell back to the
/// heuristic (ADR 0355) — Flutter-independent so the Lab and the local
/// accuracy export can show it without pulling in widget code. Carries only
/// model metadata: no filesystem path, exception text, or audio sample ever
/// goes into a field here.
@immutable
class RecognitionRuntimeInfo {
  const RecognitionRuntimeInfo({
    required this.strumModelId,
    required this.strumModelVersion,
    required this.strumModelSha256,
    required this.chordEngineId,
    required this.sampleRate,
    required this.frontendVersion,
    this.recognitionMode = RecognitionMode.free,
    this.shadowStage = RecognitionRolloutStage.off,
    this.chordModelId = chordModelNone,
    this.chordModelVersion = 0,
    this.chordModelSha256 = '',
    this.chordFallbackReason,
    this.fallbackReason,
  });

  /// The canonical "no model activated" shape — a neutral id/hash/version
  /// triple (never a partial or failed read) paired with [reason]. The one
  /// place every fallback path builds its info from, so a fallback can never
  /// carry a stray path fragment or byte value (ADR 0355 §5.2/§5.4).
  factory RecognitionRuntimeInfo.fallback(
    FallbackReason reason, {
    required int sampleRate,
    RecognitionMode recognitionMode = RecognitionMode.free,
    RecognitionRolloutStage shadowStage = RecognitionRolloutStage.off,
  }) => RecognitionRuntimeInfo(
    strumModelId: 'none',
    strumModelVersion: 0,
    strumModelSha256: '',
    chordEngineId: chordEngineNnlsViterbi,
    sampleRate: sampleRate,
    frontendVersion: frontendCrnnV1,
    recognitionMode: recognitionMode,
    shadowStage: shadowStage,
    fallbackReason: reason,
  );

  factory RecognitionRuntimeInfo.fromJson(Map<String, dynamic> json) =>
      RecognitionRuntimeInfo(
        strumModelId: json['strumModelId'] as String,
        strumModelVersion: json['strumModelVersion'] as int,
        strumModelSha256: json['strumModelSha256'] as String,
        chordEngineId: json['chordEngineId'] as String,
        sampleRate: json['sampleRate'] as int,
        frontendVersion: json['frontendVersion'] as String,
        recognitionMode: _modeFrom(json['recognitionMode']),
        shadowStage: _stageFrom(json['shadowStage']),
        chordModelId: (json['chordModelId'] as String?) ?? chordModelNone,
        chordModelVersion: (json['chordModelVersion'] as int?) ?? 0,
        chordModelSha256: (json['chordModelSha256'] as String?) ?? '',
        chordFallbackReason: json['chordFallbackReason'] == null
            ? null
            : FallbackReason.values.byName(
                json['chordFallbackReason'] as String,
              ),
        fallbackReason: json['fallbackReason'] == null
            ? null
            : FallbackReason.values.byName(json['fallbackReason'] as String),
      );

  /// Fail-closed decode of the regime: an absent or unknown value reads back
  /// as [RecognitionMode.free], the regime with no outside influence — never
  /// as `guided`, which would silently relabel a measurement as one taken
  /// with a lesson prior available (E14-R30, ADR 0544 D5).
  static RecognitionMode _modeFrom(Object? value) {
    for (final mode in RecognitionMode.values) {
      if (mode.name == value) return mode;
    }
    return RecognitionMode.free;
  }

  /// Fail-closed decode of the rollout stage: an unknown value reads back as
  /// `off`, never as a more permissive neighbour.
  static RecognitionRolloutStage _stageFrom(Object? value) =>
      RecognitionRolloutStage.tryParse(value is String ? value : null) ??
      RecognitionRolloutStage.off;

  /// The neutral chord-model id while no chord model is loaded — the shipped
  /// live chord path is DSP (NNLS + Viterbi), so this is the default.
  static const chordModelNone = 'none';

  /// The id reported for the shipped chord CRNN shadow candidate. The asset
  /// FILENAME only, never a path (same rule as [strumModelId]).
  static const chordModelCrnn = 'chord_crnn.bin';

  /// The chord-decoding engine identifier for the one DSP chord path this
  /// round ships (NNLS chroma + Viterbi decoder).
  static const chordEngineNnlsViterbi = 'nnls-viterbi-v1';

  /// The log-mel/window frontend contract (CrnnFrontend) feeding the
  /// strum-direction model.
  static const frontendCrnnV1 = 'crnn-frontend-v1';

  /// The neutral id the live (isolate-crossed) path reports while its CRNN
  /// is activated: the isolate boundary carries only weight bytes, never the
  /// real asset filename (E14-R04 wires that through, ADR 0355 R3).
  static const isolateLiveModelId = 'live-crnn';

  /// Which model activated — one of three shapes, each proven by a test
  /// (`model_activation_test.dart`): the asset FILENAME only (no directory,
  /// never a full path) on the file-backed [strumModelId] path
  /// (`StrumCrnn.activate`); the neutral [isolateLiveModelId] constant on the
  /// isolate-crossed live path; or `'none'` while [fallbackReason] is set.
  final String strumModelId;

  /// The weights' binary format version (the `SSML` header's `u32
  /// version`), or 0 while [fallbackReason] is set.
  final int strumModelVersion;

  /// SHA-256 (hex) of the ACTUALLY loaded weight bytes — never a value
  /// copied from a manifest — or the empty string while [fallbackReason] is
  /// set.
  final String strumModelSha256;

  /// Which chord-recognition engine produced the accompanying chord match.
  final String chordEngineId;

  /// Non-null only when the strum model did NOT activate: a closed,
  /// machine-checkable code — never the triggering exception's message.
  final FallbackReason? fallbackReason;

  /// The pipeline's audio sample rate (Hz).
  final int sampleRate;

  /// Version tag of the log-mel/window frontend feeding the model.
  final String frontendVersion;

  /// Which regime produced this verdict (E14-R30, ADR 0544 D5). A
  /// measurement taken in [RecognitionMode.guided] is NOT comparable to one
  /// taken in [RecognitionMode.free] — an expected-chord hint can exist in
  /// one and cannot exist in the other — so the regime travels WITH the
  /// number instead of being remembered separately.
  final RecognitionMode recognitionMode;

  /// The rollout stage of the shadow band running alongside this verdict
  /// (E14-R23, ADR 0548 D5). [RecognitionRolloutStage.off] means no shadow
  /// band ran. A stage here is never permission to show anything:
  /// `shadow.isUserVisible` is `false` by construction.
  final RecognitionRolloutStage shadowStage;

  /// Which chord model is loaded as the SHADOW candidate — the asset
  /// filename (never a path), or [chordModelNone] when none is (E14-R26,
  /// ADR 0549 D1). The shipped live chord verdict itself is still produced
  /// by [chordEngineId]; this field never means "the CRNN decided".
  final String chordModelId;

  /// The chord model's binary format version (the `CCRN` header's `u32
  /// version`), or 0 when no chord model is loaded.
  final int chordModelVersion;

  /// SHA-256 (hex) of the chord weight bytes ACTUALLY read — never a value
  /// copied from `assets/ml/model_manifest.json` — or the empty string when
  /// no chord model is loaded.
  final String chordModelSha256;

  /// Non-null only when the chord shadow band was asked to run and could
  /// not: a closed, machine-checkable code (missing asset, hash/parse
  /// failure, shape mismatch, or disabled by flag). Separate from
  /// [fallbackReason], which belongs to the STRUM band — one band failing
  /// must never be reported as the other one failing.
  final FallbackReason? chordFallbackReason;

  /// Attaches the shadow-band facts to an otherwise unchanged info.
  ///
  /// Additive by design: the strum/chord/engine identity of the PRODUCTION
  /// verdict is copied verbatim, so attaching a shadow report can never
  /// relabel which model actually decided. Passing `null` for a parameter
  /// leaves that field as it was.
  RecognitionRuntimeInfo withShadowBands({
    RecognitionMode? recognitionMode,
    RecognitionRolloutStage? shadowStage,
    String? chordModelId,
    int? chordModelVersion,
    String? chordModelSha256,
    FallbackReason? chordFallbackReason,
  }) => RecognitionRuntimeInfo(
    strumModelId: strumModelId,
    strumModelVersion: strumModelVersion,
    strumModelSha256: strumModelSha256,
    chordEngineId: chordEngineId,
    sampleRate: sampleRate,
    frontendVersion: frontendVersion,
    recognitionMode: recognitionMode ?? this.recognitionMode,
    shadowStage: shadowStage ?? this.shadowStage,
    chordModelId: chordModelId ?? this.chordModelId,
    chordModelVersion: chordModelVersion ?? this.chordModelVersion,
    chordModelSha256: chordModelSha256 ?? this.chordModelSha256,
    chordFallbackReason: chordFallbackReason ?? this.chordFallbackReason,
    fallbackReason: fallbackReason,
  );

  Map<String, dynamic> toJson() => {
    'strumModelId': strumModelId,
    'strumModelVersion': strumModelVersion,
    'strumModelSha256': strumModelSha256,
    'chordEngineId': chordEngineId,
    'fallbackReason': fallbackReason?.name,
    'sampleRate': sampleRate,
    'frontendVersion': frontendVersion,
    'recognitionMode': recognitionMode.name,
    'shadowStage': shadowStage.name,
    'chordModelId': chordModelId,
    'chordModelVersion': chordModelVersion,
    'chordModelSha256': chordModelSha256,
    'chordFallbackReason': chordFallbackReason?.name,
  };

  @override
  String toString() =>
      'RecognitionRuntimeInfo('
      'strumModelId: $strumModelId, '
      'strumModelVersion: $strumModelVersion, '
      'strumModelSha256: $strumModelSha256, '
      'chordEngineId: $chordEngineId, '
      'fallbackReason: ${fallbackReason?.name}, '
      'sampleRate: $sampleRate, '
      'frontendVersion: $frontendVersion, '
      'recognitionMode: ${recognitionMode.name}, '
      'shadowStage: ${shadowStage.name}, '
      'chordModelId: $chordModelId, '
      'chordModelVersion: $chordModelVersion, '
      'chordModelSha256: $chordModelSha256, '
      'chordFallbackReason: ${chordFallbackReason?.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecognitionRuntimeInfo &&
          other.strumModelId == strumModelId &&
          other.strumModelVersion == strumModelVersion &&
          other.strumModelSha256 == strumModelSha256 &&
          other.chordEngineId == chordEngineId &&
          other.fallbackReason == fallbackReason &&
          other.sampleRate == sampleRate &&
          other.frontendVersion == frontendVersion &&
          other.recognitionMode == recognitionMode &&
          other.shadowStage == shadowStage &&
          other.chordModelId == chordModelId &&
          other.chordModelVersion == chordModelVersion &&
          other.chordModelSha256 == chordModelSha256 &&
          other.chordFallbackReason == chordFallbackReason;

  @override
  int get hashCode => Object.hash(
    strumModelId,
    strumModelVersion,
    strumModelSha256,
    chordEngineId,
    fallbackReason,
    sampleRate,
    frontendVersion,
    recognitionMode,
    shadowStage,
    chordModelId,
    chordModelVersion,
    chordModelSha256,
    chordFallbackReason,
  );
}
