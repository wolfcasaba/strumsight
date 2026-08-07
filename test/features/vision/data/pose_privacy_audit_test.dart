// E05-R14 §6 — Pose privacy audit (a kör KULCSBIZONYÍTÉKA).
//
// Két, egymástól független őr:
//   1. a `PoseLandmarks` audit-felszíne egy RÖGZÍTETT kulcshalmazzal egyezik
//      (új mező csak a snapshot frissítésével kerülhet be);
//   2. a nyers provider-kimenet arc-pontjai (`nose`, `left_eye`, `mouth_*`…)
//      SEHOL nem jelennek meg — sem az ID-halmazban, sem az audit-map
//      szerializált alakjában, sem a `toString()` log-alakban.
//
// Valódi-sértés próba (§6, §10): a mapping allow-listájára ideiglenesen
// felvett arc-pont ezt a fájlt PIROSRA váltja — az ellenőrzött állítás a
// `poseLandmarkIdByRawName` kulcshalmaza és a mapped ID-készlet is.

library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart';
import 'package:strumsight/features/vision/data/landmarks/pose_landmark_provider.dart';
import 'package:strumsight/features/vision/data/landmarks/recorded_pose_landmark_provider.dart';
import 'package:strumsight/features/vision/domain/landmarks/pose_landmarks.dart';

/// The pinned audit surface. Adding a key here is a deliberate, reviewed act.
const _expectedTopLevelKeys = <String>{
  'timestamp_us',
  'observability',
  'landmarks',
};

const _expectedPointKeys = <String>{'x', 'y', 'z', 'visibility'};

const _expectedLandmarkNames = <String>{
  'leftShoulder',
  'rightShoulder',
  'leftElbow',
  'rightElbow',
  'leftWrist',
  'rightWrist',
  'leftHip',
  'rightHip',
  'neckReference',
};

const _forbiddenSubstrings = <String>[
  'eye',
  'nose',
  'mouth',
  'ear',
  'face',
  'lip',
];

VisionImage _imageAt(int microseconds) => VisionImage(
  width: 256,
  height: 256,
  pixelFormat: VisionPixelFormat.rgb888,
  bytes: List<int>.filled(8, 0),
  timestamp: HandLandmarkTimestamp(microseconds),
  sourceRect: NormalizedRect.full(),
  mirror: false,
);

void main() {
  test('PoseLandmarkId enum contains exactly the 9 retained points', () {
    expect(
      PoseLandmarkId.values.map((id) => id.name).toSet(),
      _expectedLandmarkNames,
    );
  });

  test('the raw-name allow-list maps onto retained IDs only', () {
    expect(
      poseLandmarkIdByRawName.values.toSet(),
      PoseLandmarkId.values.toSet(),
      reason: 'every allow-listed raw name must resolve to a retained ID',
    );
    for (final rawName in poseLandmarkIdByRawName.keys) {
      for (final forbidden in _forbiddenSubstrings) {
        expect(
          rawName.toLowerCase().contains(forbidden),
          isFalse,
          reason: 'allow-listed raw name "$rawName" looks like a face point',
        );
      }
    }
  });

  test('audit map key set matches the pinned snapshot', () async {
    final provider = RecordedPoseLandmarkProvider.fixtureUpperBody();
    await provider.initialize(const PoseModelConfig());
    final result = await provider.infer(_imageAt(1000));
    final pose = result.valueOrNull!;

    final audit = pose.toAuditMap();
    expect(audit.keys.toSet(), _expectedTopLevelKeys);

    final landmarks = audit['landmarks']! as Map<String, Object?>;
    expect(landmarks.keys.toSet(), _expectedLandmarkNames);
    for (final entry in landmarks.entries) {
      expect(
        (entry.value! as Map<String, Object?>).keys.toSet(),
        _expectedPointKeys,
        reason: 'per-point audit fields are pinned for ${entry.key}',
      );
    }
  });

  test(
    'face landmarks in the raw payload never reach the domain object, its '
    'serialized form, or its log form',
    () async {
      final provider = RecordedPoseLandmarkProvider.fixtureUpperBody();
      await provider.initialize(const PoseModelConfig());
      final pose = (await provider.infer(_imageAt(2000))).valueOrNull!;

      expect(
        pose.presentIds.map((id) => id.name).toSet(),
        _expectedLandmarkNames,
        reason: 'exactly the retained set — no more, no less',
      );
      expect(pose.count, 9);

      final serialized = jsonEncode(pose.toAuditMap()).toLowerCase();
      final logged = pose.toString().toLowerCase();
      for (final forbidden in _forbiddenSubstrings) {
        expect(
          serialized.contains(forbidden),
          isFalse,
          reason: 'serialized pose leaked a "$forbidden" field',
        );
        expect(
          logged.contains(forbidden),
          isFalse,
          reason: 'logged pose leaked a "$forbidden" field',
        );
      }
      // The fixture really did emit face points — otherwise this test
      // would pass vacuously.
      expect(recordedFaceLandmarkNames, isNotEmpty);
      final raw = provider.produceRaw(_imageAt(2000)).map((p) => p.name);
      expect(raw, containsAll(recordedFaceLandmarkNames));
    },
  );

  test('a face-only payload yields notObservable, not a zero-filled body', () async {
    final provider = RecordedPoseLandmarkProvider.fixtureFaceOnly();
    await provider.initialize(const PoseModelConfig());
    final pose = (await provider.infer(_imageAt(3000))).valueOrNull!;

    expect(pose.observability, PoseObservability.notObservable);
    expect(pose.count, 0);
    expect(pose.presentIds, isEmpty);
    for (final id in PoseLandmarkId.values) {
      expect(pose.byId(id), isNull);
    }
  });
}
