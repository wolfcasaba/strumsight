/// Reproducibility metadata attached to one analysis run (SDD Ch7 §10.1).
final class AnalysisProvenance {
  AnalysisProvenance({
    required this.appVersion,
    required this.analyzerVersion,
    required this.pipelineVersion,
    required Map<String, String> stageVersions,
    required this.dspConfigHash,
    required List<String> modelManifestIds,
    required this.inputFingerprint,
    required this.platform,
    required Map<String, bool> featureFlagSnapshot,
    this.targetVersion,
  }) : stageVersions = Map<String, String>.unmodifiable(stageVersions),
       modelManifestIds = List<String>.unmodifiable(modelManifestIds),
       featureFlagSnapshot = Map<String, bool>.unmodifiable(
         featureFlagSnapshot,
       ) {
    if (<String>[
      appVersion,
      analyzerVersion,
      pipelineVersion,
      dspConfigHash,
      inputFingerprint,
      platform,
    ].any((value) => value.trim().isEmpty)) {
      throw ArgumentError(
        'Provenance version and fingerprint fields must be non-empty.',
      );
    }
  }
  final String appVersion;
  final String analyzerVersion;
  final String pipelineVersion;
  final Map<String, String> stageVersions;
  final String dspConfigHash;
  final List<String> modelManifestIds;
  final String inputFingerprint;
  final String platform;
  final String? targetVersion;
  final Map<String, bool> featureFlagSnapshot;
}
