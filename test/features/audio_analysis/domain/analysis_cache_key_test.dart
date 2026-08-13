import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/cache/analysis_cache_key.dart';
import 'package:strumsight/features/audio_analysis/domain/target/analysis_target.dart';

void main() {
  test('cache key hits only when all six provenance components match', () {
    final baseline = _key();

    expect(_key(), baseline);
    expect(_key(inputFingerprint: 'different-input'), isNot(baseline));
    expect(_key(analyzerVersion: 'analyzer-v2'), isNot(baseline));
    expect(_key(modelManifestIds: const <String>['model-v2']), isNot(baseline));
    expect(_key(dspConfigHash: 'dsp-v2'), isNot(baseline));
    expect(_key(targetHash: 'target-v2'), isNot(baseline));
    expect(
      _key(featureFlagSnapshot: const <String, bool>{'v2': true}),
      isNot(baseline),
    );
  });

  test('cache key canonicalizes unordered feature flags', () {
    final first = _key(
      featureFlagSnapshot: const <String, bool>{'a': true, 'b': false},
    );
    final second = _key(
      featureFlagSnapshot: const <String, bool>{'b': false, 'a': true},
    );

    expect(second, first);
  });

  test('cache key derives the target hash from the target snapshot', () {
    final provenance = _provenance();
    final withoutTarget = AnalysisCacheKey.fromProvenance(
      provenance: provenance,
    );
    final withTarget = AnalysisCacheKey.fromProvenance(
      provenance: provenance,
      target: AnalysisTarget(
        id: 'target-a',
        kind: AnalysisTargetKind.practice,
        timebase: AnalysisTargetTimebase.session,
      ),
    );

    expect(withTarget, isNot(withoutTarget));
  });
}

AnalysisCacheKey _key({
  String inputFingerprint = 'input-v1',
  String analyzerVersion = 'analyzer-v1',
  List<String> modelManifestIds = const <String>['model-v1'],
  String dspConfigHash = 'dsp-v1',
  String targetHash = 'target-v1',
  Map<String, bool> featureFlagSnapshot = const <String, bool>{'v2': false},
}) => AnalysisCacheKey(
  inputFingerprint: inputFingerprint,
  analyzerVersion: analyzerVersion,
  modelManifestIds: modelManifestIds,
  dspConfigHash: dspConfigHash,
  targetHash: targetHash,
  featureFlagSnapshot: featureFlagSnapshot,
);

AnalysisProvenance _provenance() => AnalysisProvenance(
  appVersion: 'app-v1',
  analyzerVersion: 'analyzer-v1',
  pipelineVersion: 'pipeline-v1',
  stageVersions: const <String, String>{},
  dspConfigHash: 'dsp-v1',
  modelManifestIds: const <String>['model-v1'],
  inputFingerprint: 'input-v1',
  platform: 'test',
  featureFlagSnapshot: const <String, bool>{'v2': false},
);
