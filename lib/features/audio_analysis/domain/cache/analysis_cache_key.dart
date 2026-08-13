/// Reproducibility-complete key for derived analysis cache entries.
library;

import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

import '../analysis_provenance.dart';
import '../target/analysis_target.dart';

/// Cache identity that prevents reuse across incompatible analysis contexts.
final class AnalysisCacheKey {
  AnalysisCacheKey({
    required this.inputFingerprint,
    required this.analyzerVersion,
    required List<String> modelManifestIds,
    required this.dspConfigHash,
    required this.targetHash,
    required Map<String, bool> featureFlagSnapshot,
  }) : modelManifestIds = List<String>.unmodifiable(modelManifestIds),
       featureFlagSnapshot = Map<String, bool>.unmodifiable(
         Map<String, bool>.fromEntries(
           featureFlagSnapshot.entries.toList()
             ..sort((left, right) => left.key.compareTo(right.key)),
         ),
       ) {
    if (<String>[
      inputFingerprint,
      analyzerVersion,
      dspConfigHash,
      targetHash,
    ].any((value) => value.trim().isEmpty)) {
      throw ArgumentError('Analysis cache key components must be non-empty.');
    }
    if (this.modelManifestIds.any((value) => value.trim().isEmpty)) {
      throw ArgumentError.value(modelManifestIds, 'modelManifestIds');
    }
  }

  /// Stable sentinel for analyses that intentionally have no reference target.
  static const String noTargetHash = 'no-analysis-target-v1';

  final String inputFingerprint;
  final String analyzerVersion;
  final List<String> modelManifestIds;
  final String dspConfigHash;
  final String targetHash;
  final Map<String, bool> featureFlagSnapshot;

  /// Builds the key from persisted provenance and a canonical target snapshot.
  factory AnalysisCacheKey.fromProvenance({
    required AnalysisProvenance provenance,
    AnalysisTarget? target,
  }) => AnalysisCacheKey(
    inputFingerprint: provenance.inputFingerprint,
    analyzerVersion: provenance.analyzerVersion,
    modelManifestIds: provenance.modelManifestIds,
    dspConfigHash: provenance.dspConfigHash,
    targetHash: target == null ? noTargetHash : targetFingerprint(target),
    featureFlagSnapshot: provenance.featureFlagSnapshot,
  );

  /// A safe filename and lookup id derived from the complete key.
  String get cacheId =>
      crypto.sha256.convert(utf8.encode(_canonicalJson())).toString();

  /// Deterministic snapshot hash, including all target facts and ordering.
  static String targetFingerprint(AnalysisTarget target) => crypto.sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'id': target.id,
            'targetVersion': target.targetVersion,
            'kind': target.kind.name,
            'timebase': target.timebase.name,
            'expectedEvents': <Object?>[
              for (final event in target.expectedEvents)
                <String, Object?>{
                  'id': event.id,
                  'timeMicros': event.time.inMicroseconds,
                  'type': event.type.name,
                  'direction': event.direction?.name,
                },
            ],
            'expectedChords': target.expectedChords,
            'expectedNotes': target.expectedNotes,
            'sections': <Object?>[
              for (final section in target.sections)
                <String, Object?>{
                  'id': section.id,
                  'startMicros': section.start.inMicroseconds,
                  'endMicros': section.end.inMicroseconds,
                },
            ],
          }),
        ),
      )
      .toString();

  String _canonicalJson() => jsonEncode(<String, Object?>{
    'inputFingerprint': inputFingerprint,
    'analyzerVersion': analyzerVersion,
    'modelManifestIds': modelManifestIds,
    'dspConfigHash': dspConfigHash,
    'targetHash': targetHash,
    'featureFlagSnapshot': featureFlagSnapshot,
  });

  @override
  bool operator ==(Object other) =>
      other is AnalysisCacheKey && other.cacheId == cacheId;

  @override
  int get hashCode => cacheId.hashCode;
}
