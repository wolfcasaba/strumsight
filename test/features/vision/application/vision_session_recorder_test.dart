// E09-R28a: the finished session is persisted instead of dropped.
//
// `visionSessionResultListenerProvider` defaulted to `(_) {}`, so every
// session aggregate was built and thrown away: the privacy centre's session
// list and the practice generator's Vision evidence adapter both read a store
// that nothing ever wrote to.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/application/vision_session_recorder.dart';
import 'package:strumsight/features/vision/data/persistence/vision_session_repository.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';
import 'package:strumsight/features/vision/domain/quality/vision_quality_summary.dart';
import 'package:strumsight/features/vision/domain/vision_session.dart';
import 'package:strumsight/features/vision/domain/vision_session_result.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const Map<String, String> _deferred = <String, String>{
  'hand_landmarker': 'deferred',
  'pose_landmarker': 'deferred',
};

VisionSessionResult _result({String id = 'session-1'}) => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create(id),
    startedAt: DateTime.utc(2026, 9, 2, 10),
  ),
  endedAt: DateTime.utc(2026, 9, 2, 10, 5),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(const <VisionFrameQuality>[]),
  calibrationState: CalibrationLossState.lost,
  sessionSummary: const <VisionInsight>[],
  observedFrameCount: 480,
);

final class _RecordingLogger implements AppLogger {
  final List<String> errors = <String>[];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {}

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    errors.add(event);
  }
}

void main() {
  group('VisionSessionResultRecorder', () {
    test('a finished session round-trips into local history', () async {
      final store = InMemoryKeyValueStore();
      final repository = VisionSessionRepository(store: store);
      final recorder = VisionSessionResultRecorder(
        repository: repository,
        modelVersions: _deferred,
        logger: _RecordingLogger(),
      );

      recorder(_result());
      await recorder.pending;

      final entries = VisionSessionRepository(store: store).list();
      expect(entries, hasLength(1));
      expect(entries.single.sessionId, 'session-1');
      expect(entries.single.observedFrameCount, 480);
      expect(entries.single.endReason, VisionSessionEndReason.explicitStop);
      expect(entries.single.calibrationState, CalibrationLossState.lost);
      // Both vision models are `deferred`, and the entry says so rather than
      // naming a model that never ran.
      expect(entries.single.modelVersions, _deferred);
    });

    test('two sessions both survive, newest first', () async {
      final store = InMemoryKeyValueStore();
      final recorder = VisionSessionResultRecorder(
        repository: VisionSessionRepository(store: store),
        modelVersions: _deferred,
        logger: _RecordingLogger(),
      );

      recorder(_result());
      recorder(_result(id: 'session-2'));
      await recorder.pending;

      final entries = VisionSessionRepository(store: store).list();
      expect(entries.map((entry) => entry.sessionId), <String>[
        'session-2',
        'session-1',
      ]);
    });

    test('a failed write is reported, never silently dropped', () async {
      final store = InMemoryKeyValueStore();
      final logger = _RecordingLogger();
      final recorder = VisionSessionResultRecorder(
        repository: VisionSessionRepository(store: store),
        // The codec rejects an empty provenance map; this stands in for any
        // write that cannot complete.
        modelVersions: const <String, String>{},
        logger: logger,
      );

      recorder(_result());
      await recorder.pending;

      expect(logger.errors, <String>['vision.session.persist_failed']);
      expect(VisionSessionRepository(store: store).list(), isEmpty);
    });
  });
}
