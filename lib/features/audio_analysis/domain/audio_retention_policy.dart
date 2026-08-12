/// Storage retention policy for the audio-analysis repository
/// (ADR 0239 §Döntés 11, ADR 0217 — nyers audio nem perzisztálódhat).
///
/// The repository NEVER writes audio bytes; [keepOriginal] is a
/// forward-compatible policy flag a future import-runner can honour
/// (E06-R28 cache). Today the repository only writes the V2 document
/// JSON and the summary index — the flag is stored alongside the
/// summary so a future rollout can read it back without contract
/// changes.
library;

import 'package:meta/meta.dart';

/// Immutable retention policy value object.
///
/// The default constructor returns a `keepOriginal: false` instance —
/// this matches the ADR 0217 "no raw audio" guarantee and the brief
/// §5.7 "NEM elfogadható: preview waveform néven tárolt teljes PCM"
/// explicit ban.
@immutable
final class AudioRetentionPolicy {
  /// Default retention policy — no raw audio is persisted.
  static const AudioRetentionPolicy defaultPolicy = AudioRetentionPolicy._(
    keepOriginal: false,
  );

  const AudioRetentionPolicy({this.keepOriginal = false})
    : _sentinel = keepOriginal;

  const AudioRetentionPolicy._({required bool keepOriginal})
    : keepOriginal = keepOriginal,
      _sentinel = keepOriginal;

  /// Whether the originating recorder chose to keep the original audio
  /// alongside the analysis. The V2 document model never stores audio
  /// bytes, so this flag is informational only.
  final bool keepOriginal;

  // Ignore: unused_field — kept for future-proofing the value-equality
  // contract so a future field addition can be wired without breaking
  // callers that compare policies by reference.
  // ignore: unused_field
  final bool _sentinel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioRetentionPolicy && other.keepOriginal == keepOriginal;

  @override
  int get hashCode => keepOriginal.hashCode;

  @override
  String toString() => 'AudioRetentionPolicy(keepOriginal: $keepOriginal)';
}
