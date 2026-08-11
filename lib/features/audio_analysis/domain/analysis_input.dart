import 'dart:typed_data';

import 'analysis_mode.dart';
import 'analysis_warning.dart';

/// A privacy-labelled source name. Its string representation is always redacted.
final class SourceDisplayName {
  const SourceDisplayName(this.value);

  /// The display-only name. It must never be passed to a logger or telemetry.
  final String value;

  /// Signals that [value] is personal metadata and must be redacted by callers.
  bool get redacted => true;

  @override
  String toString() => 'SourceDisplayName(redacted: true)';
}

/// The validated boundary shape for microphone, import, and session audio.
sealed class AnalysisInput {
  const AnalysisInput({required this.source, this.sourceDisplayName});

  final AnalysisInputSource source;
  final SourceDisplayName? sourceDisplayName;

  @override
  String toString() =>
      '$runtimeType(source: $source, sourceDisplayName: $sourceDisplayName)';
}

/// Audio bytes received from an imported file before decoding.
final class FileAnalysisInput extends AnalysisInput {
  FileAnalysisInput({
    required List<int> bytes,
    required super.source,
    super.sourceDisplayName,
  }) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  /// A defensive copy so a caller cannot change an input after validation starts.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String toString() =>
      'FileAnalysisInput(source: $source, byteCount: ${_bytes.length}, '
      'sourceDisplayName: $sourceDisplayName)';
}

/// Mono PCM plus source metadata, ready for pipeline validation.
final class PcmAnalysisInput extends AnalysisInput {
  PcmAnalysisInput({
    required List<double> samples,
    required this.sampleRate,
    required this.channelCount,
    required super.source,
    super.sourceDisplayName,
  }) : samples = List<double>.unmodifiable(samples);

  final List<double> samples;
  final int sampleRate;

  /// Original channel count, retained even when a decoder downmixes to mono.
  final int channelCount;

  @override
  String toString() =>
      'PcmAnalysisInput(source: $source, sampleCount: ${samples.length}, '
      'sampleRate: $sampleRate, channelCount: $channelCount, '
      'sourceDisplayName: $sourceDisplayName)';
}

/// PCM accepted at the boundary, with any non-fatal input-quality warnings.
final class ValidatedPcmAnalysisInput {
  ValidatedPcmAnalysisInput({
    required this.input,
    List<AnalysisWarning> warnings = const <AnalysisWarning>[],
  }) : warnings = List<AnalysisWarning>.unmodifiable(warnings);

  final PcmAnalysisInput input;
  final List<AnalysisWarning> warnings;
}
