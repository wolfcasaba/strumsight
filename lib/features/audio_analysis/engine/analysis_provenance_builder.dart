/// Provenance facts for the unchanged V1 ClipAnalyzer shipping path.
///
/// These values are recorded here instead of importing the V1 DSP internals:
/// the adapter is deliberately constrained to Analyze's public boundary.
final class LegacyAnalyzerProvenance {
  LegacyAnalyzerProvenance({
    required this.chunkSize,
    required this.chromaMedianWindow,
    required this.bassWeight,
    required this.nnlsWindow,
    required this.nnlsHop,
    required this.strumRefinerSource,
    required List<String> modelManifestIds,
    this.fallbackReason,
  }) : modelManifestIds = List<String>.unmodifiable(modelManifestIds) {
    if (chunkSize <= 0 || chromaMedianWindow <= 0) {
      throw ArgumentError('Legacy analyzer window values must be positive.');
    }
    if (!bassWeight.isFinite || bassWeight < 0 || bassWeight > 1) {
      throw ArgumentError.value(bassWeight, 'bassWeight');
    }
    if (nnlsWindow <= 0 || nnlsHop <= 0) {
      throw ArgumentError('Legacy NNLS values must be positive.');
    }
    if (strumRefinerSource == StrumRefinerSource.heuristic &&
        (fallbackReason == null || fallbackReason!.trim().isEmpty)) {
      throw ArgumentError('A heuristic fallback requires a reason.');
    }
    if (strumRefinerSource != StrumRefinerSource.heuristic &&
        fallbackReason != null) {
      throw ArgumentError('Only a heuristic fallback can carry a reason.');
    }
  }

  final int chunkSize;
  final int chromaMedianWindow;
  final double bassWeight;
  final int nnlsWindow;
  final int nnlsHop;
  final StrumRefinerSource strumRefinerSource;
  final String? fallbackReason;
  final List<String> modelManifestIds;
}

/// The source of the strum labels observed in the adapter output.
enum StrumRefinerSource { none, heuristic, crnn }

/// Builds immutable metadata for the fixed V1 default configuration.
///
/// The adapter cannot inspect ClipAnalyzer's private constructor defaults
/// without violating the cross-feature public.dart boundary. These named,
/// versioned values therefore describe the already-shipping default call only;
/// they are provenance, not a second DSP implementation.
final class AnalysisProvenanceBuilder {
  const AnalysisProvenanceBuilder({
    this.modelManifestId = 'strum_crnn.bin@SSML-v1',
  });

  static const int clipAnalyzerChunkSize = 2048;
  static const int clipAnalyzerChromaMedianWindow = 1;
  static const double clipAnalyzerBassWeight = 0.35;
  static const int legacyNnlsWindow = 16384;
  static const int legacyNnlsHop = 4096;
  static const String candidateMatchesHeuristicFallback =
      'candidate-matches-heuristic-baseline';

  final String modelManifestId;

  LegacyAnalyzerProvenance build({
    required StrumRefinerSource strumRefinerSource,
    String? fallbackReason,
  }) => LegacyAnalyzerProvenance(
    chunkSize: clipAnalyzerChunkSize,
    chromaMedianWindow: clipAnalyzerChromaMedianWindow,
    bassWeight: clipAnalyzerBassWeight,
    nnlsWindow: legacyNnlsWindow,
    nnlsHop: legacyNnlsHop,
    strumRefinerSource: strumRefinerSource,
    fallbackReason: fallbackReason,
    modelManifestIds: strumRefinerSource == StrumRefinerSource.none
        ? const <String>[]
        : <String>[modelManifestId],
  );
}
