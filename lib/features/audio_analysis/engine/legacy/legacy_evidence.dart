import 'dart:typed_data';

import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';

import '../analysis_provenance_builder.dart';

/// Immutable input for the V1 adapter, including an optional CRNN candidate.
///
/// A zero sample rate remains representable because V1 defines it as an empty
/// result; normal pipeline callers construct this from [PreprocessedAudio].
final class LegacyClipAnalyzerInput {
  LegacyClipAnalyzerInput({
    required List<double> samples,
    required this.sampleRate,
    Uint8List? strumRefinerWeights,
  }) : samples = List<double>.unmodifiable(samples),
       _strumRefinerWeights = strumRefinerWeights == null
           ? null
           : Uint8List.fromList(strumRefinerWeights) {
    if (sampleRate < 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate');
    }
  }

  factory LegacyClipAnalyzerInput.fromPreprocessedAudio(
    PreprocessedAudio audio, {
    Uint8List? strumRefinerWeights,
  }) => LegacyClipAnalyzerInput(
    samples: audio.canonicalSamples,
    sampleRate: audio.sampleRate,
    strumRefinerWeights: strumRefinerWeights,
  );

  final List<double> samples;
  final int sampleRate;
  final Uint8List? _strumRefinerWeights;

  Uint8List? get strumRefinerWeights => _strumRefinerWeights == null
      ? null
      : Uint8List.fromList(_strumRefinerWeights);
}

/// Immutable record of the exported V1 entrypoint invocation.
final class LegacyClipAnalyzerCall {
  LegacyClipAnalyzerCall({
    required this.sampleRate,
    required this.sampleCount,
    required this.labMode,
    required this.hasCandidateStrumRefiner,
    List<String> modelManifestIds = const <String>[],
  }) : modelManifestIds = List<String>.unmodifiable(modelManifestIds) {
    if (sampleRate < 0 || sampleCount < 0) {
      throw ArgumentError('Legacy call dimensions cannot be negative.');
    }
    if (labMode) {
      throw ArgumentError('The legacy stage only supports Lab mode off.');
    }
  }

  final int sampleRate;
  final int sampleCount;
  final bool labMode;
  final bool hasCandidateStrumRefiner;
  final List<String> modelManifestIds;
}

/// A legacy chord span expressed on V2's microsecond timebase.
final class LegacyChordEvidence {
  const LegacyChordEvidence({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final Duration start;
  final Duration end;
}

/// A legacy strum observation expressed on V2's microsecond timebase.
final class LegacyStrumEvidence {
  const LegacyStrumEvidence({
    required this.direction,
    required this.time,
    required this.confidence,
  });

  final StrumDirection direction;
  final Duration time;
  final double confidence;
}

/// Intermediate V1 timeline evidence for later V2 timeline assembly.
final class LegacyEvidence {
  LegacyEvidence({
    required this.duration,
    required this.bpm,
    required List<LegacyChordEvidence> chords,
    required List<LegacyStrumEvidence> strums,
    required this.call,
    required this.provenance,
  }) : chords = List<LegacyChordEvidence>.unmodifiable(chords),
       strums = List<LegacyStrumEvidence>.unmodifiable(strums);

  factory LegacyEvidence.fromAnalyzeResult(
    AnalyzeResult result, {
    required LegacyClipAnalyzerCall call,
    required LegacyAnalyzerProvenance provenance,
  }) => LegacyEvidence(
    duration: durationFromSeconds(result.durationSec),
    bpm: result.bpm,
    chords: <LegacyChordEvidence>[
      for (final chord in result.chords)
        LegacyChordEvidence(
          label: chord.label,
          start: durationFromSeconds(chord.startSec),
          end: durationFromSeconds(chord.endSec),
        ),
    ],
    strums: <LegacyStrumEvidence>[
      for (final strum in result.strums)
        LegacyStrumEvidence(
          direction: strum.direction,
          time: durationFromSeconds(strum.timeSec),
          confidence: strum.confidence,
        ),
    ],
    call: call,
    provenance: provenance,
  );

  final Duration duration;
  final double bpm;
  final List<LegacyChordEvidence> chords;
  final List<LegacyStrumEvidence> strums;
  final LegacyClipAnalyzerCall call;
  final LegacyAnalyzerProvenance provenance;

  /// Preserves the explicitly approved V1-to-V2 timebase contract.
  static Duration durationFromSeconds(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );
}
