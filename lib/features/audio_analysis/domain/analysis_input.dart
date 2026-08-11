import 'dart:typed_data';

import 'analysis_mode.dart';

/// Audio supplied to the analysis boundary. Raw file bytes are kept separate
/// from already-decoded PCM so the import path remains explicit.
sealed class AnalysisInput {
  const AnalysisInput();
}

/// Privacy-sensitive filename metadata.
///
/// The original filename is available to the local owner only. Diagnostic
/// stringification deliberately exposes its privacy state but never its value.
final class SourceDisplayName {
  const SourceDisplayName(this.value) : redacted = true;

  final String value;
  final bool redacted;

  @override
  String toString() => 'SourceDisplayName(redacted: $redacted)';
}

/// PCM supplied by a microphone or a local session buffer.
final class PcmAnalysisInput extends AnalysisInput {
  PcmAnalysisInput({
    required this.samples,
    required this.sampleRate,
    required this.channelCount,
    required this.source,
    this.sourceDisplayName,
  }) {
    if (source == AnalysisInputSource.importedFile) {
      throw ArgumentError.value(
        source,
        'source',
        'Imported bytes must enter through FileAnalysisInput.',
      );
    }
  }

  final Float32List samples;
  final int sampleRate;
  final int channelCount;
  final AnalysisInputSource source;
  final SourceDisplayName? sourceDisplayName;

  @override
  String toString() =>
      'PcmAnalysisInput(sampleRate: $sampleRate, channelCount: $channelCount, '
      'source: $source, sourceDisplayName: ${sourceDisplayName == null ? null : 'redacted'})';
}

/// Untrusted imported bytes. Only [AnalysisInputSource.importedFile] is valid.
final class FileAnalysisInput extends AnalysisInput {
  FileAnalysisInput({
    required this.bytes,
    this.sourceDisplayName,
    this.source = AnalysisInputSource.importedFile,
  }) {
    if (source != AnalysisInputSource.importedFile) {
      throw ArgumentError.value(
        source,
        'source',
        'File input must have importedFile source.',
      );
    }
  }

  final Uint8List bytes;
  final SourceDisplayName? sourceDisplayName;
  final AnalysisInputSource source;

  @override
  String toString() =>
      'FileAnalysisInput(bytes: ${bytes.length}, source: $source, '
      'sourceDisplayName: ${sourceDisplayName == null ? null : 'redacted'})';
}

/// Decoded PCM with the source-channel metadata retained after downmixing.
final class DecodedAudio {
  const DecodedAudio({
    required this.samples,
    required this.sampleRate,
    required this.channelCount,
    required this.source,
  });

  final Float32List samples;
  final int sampleRate;
  final int channelCount;
  final AnalysisInputSource source;
}

/// PCM accepted by the boundary, plus machine-readable sanitization warnings.
final class ValidatedAnalysisInput {
  ValidatedAnalysisInput({
    required this.input,
    List<String> warningCodes = const <String>[],
  }) : warningCodes = List<String>.unmodifiable(warningCodes);

  final PcmAnalysisInput input;
  final List<String> warningCodes;
}
