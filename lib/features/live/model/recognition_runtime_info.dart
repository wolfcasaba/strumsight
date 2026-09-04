import 'package:meta/meta.dart';

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
    this.fallbackReason,
  });

  /// The canonical "no model activated" shape — a neutral id/hash/version
  /// triple (never a partial or failed read) paired with [reason]. The one
  /// place every fallback path builds its info from, so a fallback can never
  /// carry a stray path fragment or byte value (ADR 0355 §5.2/§5.4).
  factory RecognitionRuntimeInfo.fallback(
    FallbackReason reason, {
    required int sampleRate,
  }) => RecognitionRuntimeInfo(
    strumModelId: 'none',
    strumModelVersion: 0,
    strumModelSha256: '',
    chordEngineId: chordEngineNnlsViterbi,
    sampleRate: sampleRate,
    frontendVersion: frontendCrnnV1,
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
        fallbackReason: json['fallbackReason'] == null
            ? null
            : FallbackReason.values.byName(json['fallbackReason'] as String),
      );

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

  Map<String, dynamic> toJson() => {
    'strumModelId': strumModelId,
    'strumModelVersion': strumModelVersion,
    'strumModelSha256': strumModelSha256,
    'chordEngineId': chordEngineId,
    'fallbackReason': fallbackReason?.name,
    'sampleRate': sampleRate,
    'frontendVersion': frontendVersion,
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
      'frontendVersion: $frontendVersion)';

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
          other.frontendVersion == frontendVersion;

  @override
  int get hashCode => Object.hash(
    strumModelId,
    strumModelVersion,
    strumModelSha256,
    chordEngineId,
    fallbackReason,
    sampleRate,
    frontendVersion,
  );
}
