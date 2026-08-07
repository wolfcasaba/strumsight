// E05-R14 — RecordedPoseLandmarkProvider (fixture adapter, CI-út).
//
// A CI ezt futtatja, amíg a production adapter deferred (ADR 0186
// §Következmények). A fixture-ek SZÁNDÉKOSAN tartalmaznak arc-pontokat
// (`nose`, `left_eye`, `right_ear`, `mouth`) a NYERS provider-kimenetben —
// a `mapRawPoseLandmarks` mapping ezeket eldobja, és pontosan ez a kör
// kulcsbizonyítéka (privacy-audit teszt).

library;

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart'
    show VisionImage;
import 'package:strumsight/features/vision/data/landmarks/pose_landmark_provider.dart';
import 'package:strumsight/features/vision/domain/landmarks/pose_landmarks.dart';

const _defaultModelId = 'pose_landmarker';
const _defaultModelVersion = '1.0.0';

/// The raw face-landmark names a real pose model may emit. They are part of
/// the fixtures precisely so the mapping's drop behaviour is measured.
const List<String> recordedFaceLandmarkNames = <String>[
  'nose',
  'left_eye',
  'right_eye',
  'left_ear',
  'right_ear',
  'mouth_left',
  'mouth_right',
];

/// A provider returning a fixed, pre-recorded raw payload for every `infer`
/// call. The payload is mapped through `mapRawPoseLandmarks`, so the fixture
/// exercises the same privacy filter the production adapter will.
final class RecordedPoseLandmarkProvider implements PoseLandmarkProvider {
  RecordedPoseLandmarkProvider({
    required this.modelId,
    required this.modelVersion,
    required this.produceRaw,
  });

  @override
  final String modelId;
  @override
  final String modelVersion;

  /// The raw provider payload for a given frame.
  final List<RawPoseLandmark> Function(VisionImage image) produceRaw;

  bool _initialized = false;
  bool _closed = false;
  String? _failureCode;

  /// A full upper body PLUS face landmarks — the canonical mapping and
  /// privacy-audit fixture. [offsetY] shifts the whole body so the drift
  /// model can be exercised.
  factory RecordedPoseLandmarkProvider.fixtureUpperBody({
    double offsetY = 0,
    double visibility = 0.9,
  }) => RecordedPoseLandmarkProvider(
    modelId: _defaultModelId,
    modelVersion: _defaultModelVersion,
    produceRaw: (image) => <RawPoseLandmark>[
      ..._upperBodyRaw(offsetY: offsetY, visibility: visibility),
      ..._faceRaw(visibility: visibility),
    ],
  );

  /// A payload containing ONLY face landmarks — everything is dropped, so
  /// the mapped result must be `notObservable` (no zero-filled fake body).
  factory RecordedPoseLandmarkProvider.fixtureFaceOnly() =>
      RecordedPoseLandmarkProvider(
        modelId: _defaultModelId,
        modelVersion: _defaultModelVersion,
        produceRaw: (image) => _faceRaw(visibility: 0.9),
      );

  /// Nobody in frame — empty raw payload, `notObservable`.
  factory RecordedPoseLandmarkProvider.fixtureNoPose() =>
      RecordedPoseLandmarkProvider(
        modelId: _defaultModelId,
        modelVersion: _defaultModelVersion,
        produceRaw: (image) => const <RawPoseLandmark>[],
      );

  /// Failure-path cell — `infer` returns `AppResult.failure(<code>)`.
  factory RecordedPoseLandmarkProvider.fixtureFailure({
    required String code,
  }) => RecordedPoseLandmarkProvider(
    modelId: _defaultModelId,
    modelVersion: _defaultModelVersion,
    produceRaw: (image) => const <RawPoseLandmark>[],
  ).._failureCode = code;

  static List<RawPoseLandmark> _upperBodyRaw({
    required double offsetY,
    required double visibility,
  }) => <RawPoseLandmark>[
    RawPoseLandmark(
      name: 'left_shoulder',
      x: 0.40,
      y: 0.30 + offsetY,
      z: 0.01,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'right_shoulder',
      x: 0.60,
      y: 0.30 + offsetY,
      z: 0.01,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'left_elbow',
      x: 0.35,
      y: 0.45 + offsetY,
      z: 0.02,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'right_elbow',
      x: 0.65,
      y: 0.45 + offsetY,
      z: 0.02,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'left_wrist',
      x: 0.38,
      y: 0.58 + offsetY,
      z: 0.03,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'right_wrist',
      x: 0.62,
      y: 0.58 + offsetY,
      z: 0.03,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'left_hip',
      x: 0.44,
      y: 0.70 + offsetY,
      z: 0.04,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'right_hip',
      x: 0.56,
      y: 0.70 + offsetY,
      z: 0.04,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'neck',
      x: 0.50,
      y: 0.26 + offsetY,
      z: 0.0,
      visibility: visibility,
    ),
  ];

  static List<RawPoseLandmark> _faceRaw({required double visibility}) => <
    RawPoseLandmark
  >[
    for (var index = 0; index < recordedFaceLandmarkNames.length; index++)
      RawPoseLandmark(
        name: recordedFaceLandmarkNames[index],
        x: 0.48 + index * 0.01,
        y: 0.18 + index * 0.005,
        z: 0,
        visibility: visibility,
      ),
  ];

  @override
  Future<AppResult<void>> initialize(PoseModelConfig config) async {
    _initialized = true;
    return AppResult<void>.success(null);
  }

  @override
  Future<AppResult<PoseLandmarks>> infer(VisionImage image) async {
    if (_closed) {
      return AppResult<PoseLandmarks>.failure(
        const MlFailure(code: FailureCode.mlModelLoad, retryable: false),
      );
    }
    if (!_initialized) {
      return AppResult<PoseLandmarks>.failure(
        const MlFailure(code: FailureCode.mlModelLoad, retryable: true),
      );
    }
    final failureCode = _failureCode;
    if (failureCode != null) {
      return AppResult<PoseLandmarks>.failure(
        MlFailure(code: failureCode, retryable: false),
      );
    }
    return AppResult<PoseLandmarks>.success(
      mapRawPoseLandmarks(
        timestampUs: image.timestamp.microsecondsSinceSessionStart,
        raw: produceRaw(image),
      ),
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
