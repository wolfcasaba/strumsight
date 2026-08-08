import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/ml/vision_model_manifest.dart';

const _manifestPath = 'assets/ml/model_manifest.json';

void main() {
  test('shipping vision manifest passes the integrity gate', () {
    final report = _validate(_manifest());

    expect(report.isClean, isTrue, reason: report.issues.join('\n'));
  });

  test('bad checksum fails the integrity gate', () {
    final document = _manifest();
    _visionModel(document, 'hand_landmarker')['sha256'] = 'invalid-checksum';

    final report = _validate(document);

    expect(report.isClean, isFalse);
    expect(report.issues.join('\n'), contains('sha256'));
  });

  test('mismatched output schema fails the integrity gate', () {
    final document = _manifest();
    _visionModel(document, 'pose_landmarker')['output_schema'] =
        handLandmarksOutputSchema;

    final report = _validate(document);

    expect(report.isClean, isFalse);
    expect(report.issues.join('\n'), contains('output_schema'));
  });

  test('missing license fails the integrity gate', () {
    final document = _manifest();
    _visionModel(document, 'hand_landmarker').remove('license');

    final report = _validate(document);

    expect(report.isClean, isFalse);
    expect(report.issues.join('\n'), contains('license'));
  });
}

VisionModelManifestReport _validate(Map<String, Object?> document) =>
    validateVisionManifest(
      projectRoot: Directory.current,
      rawDocument: document,
    );

Map<String, Object?> _manifest() =>
    jsonDecode(File(_manifestPath).readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> _visionModel(
  Map<String, Object?> document,
  String modelId,
) {
  final models = document['vision_models']! as List<Object?>;
  return models.cast<Map<String, Object?>>().singleWhere(
    (model) => model['model_id'] == modelId,
  );
}
