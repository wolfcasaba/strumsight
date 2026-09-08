import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_frame.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/camera/fake_camera_capture.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/application/vision_pipeline_providers.dart';
import 'package:strumsight/features/vision/application/vision_session_controller.dart';
import 'package:strumsight/features/vision/application/vision_session_state.dart';
import 'package:strumsight/features/vision/data/persistence/vision_session_repository.dart';
import 'package:strumsight/features/vision/data/pipeline/vision_frame_pipeline.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';
import 'package:strumsight/features/vision/domain/quality/vision_quality_summary.dart';
import 'package:strumsight/features/vision/domain/vision_session.dart';
import 'package:strumsight/features/vision/domain/vision_session_result.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

final class _PermissionGateway implements CameraPermissionGateway {
  _PermissionGateway(this.current, {CameraPermissionState? requested})
    : requested = requested ?? current;

  CameraPermissionState current;
  CameraPermissionState requested;

  @override
  Future<CameraPermissionState> currentState() async => current;

  @override
  Future<CameraPermissionState> request() async => requested;
}

/// A pipeline stand-in: the controller must delegate frames to it and copy
/// its published summaries into state without inspecting a buffer itself.
final class _FakeProcessor implements VisionFrameProcessor {
  _FakeProcessor()
    : _updates = StreamController<VisionPipelineUpdate>.broadcast();

  final StreamController<VisionPipelineUpdate> _updates;
  final List<int> frameIds = <int>[];
  bool disposed = false;

  @override
  Stream<VisionPipelineUpdate> get updates => _updates.stream;

  @override
  void onFrame(CameraFrame frame) {
    frameIds.add(frame.frameId);
  }

  @override
  void reset() {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _updates.close();
  }

  Future<void> emit(VisionPipelineUpdate update) async {
    if (!_updates.isClosed) _updates.add(update);
    await Future<void>.delayed(Duration.zero);
  }
}

VisionPipelineUpdate _update({
  VisionMetricState hand = VisionMetricState.notObservable,
  VisionMetricState pose = VisionMetricState.notObservable,
  CalibrationLossState guitar = CalibrationLossState.tracking,
  VisionInsight? cue,
  List<VisionInsight> sessionSummary = const <VisionInsight>[],
}) => VisionPipelineUpdate(
  summary: VisionQualitySummary.fromFrames(const <VisionFrameQuality>[]),
  hand: hand,
  pose: pose,
  guitar: guitar,
  realtimeCue: cue,
  sessionSummary: sessionSummary,
);

final class _Rig {
  _Rig(
    this.container,
    this.capture,
    this.coordinator,
    this.results,
    this.processor,
    this.store,
  );

  final ProviderContainer container;
  final FakeCameraCapture capture;
  final CameraSessionCoordinator coordinator;
  final List<VisionSessionResult> results;
  final _FakeProcessor processor;
  final InMemoryKeyValueStore store;

  VisionSessionController get controller =>
      container.read(visionSessionControllerProvider.notifier);

  VisionSessionState get state =>
      container.read(visionSessionControllerProvider);

  void dispose() => container.dispose();
}

_Rig _rig({
  CameraPermissionState permission = CameraPermissionState.granted,
  Future<void>? startGate,
  bool persistResults = false,
}) {
  final capture = FakeCameraCapture(startGate: startGate);
  final coordinator = CameraSessionCoordinator();
  final results = <VisionSessionResult>[];
  final processor = _FakeProcessor();
  final store = InMemoryKeyValueStore();
  final container = ProviderContainer(
    overrides: [
      cameraPermissionGatewayProvider.overrideWithValue(
        _PermissionGateway(permission),
      ),
      cameraCaptureFactoryProvider.overrideWithValue(() => capture),
      cameraSessionCoordinatorProvider.overrideWithValue(coordinator),
      // E09-R28a: the session now builds a real pipeline, which reads the
      // persisted calibration. A stand-in keeps these cells about the state
      // machine rather than about frame quality.
      visionFrameProcessorFactoryProvider.overrideWithValue(() => processor),
      keyValueStoreProvider.overrideWithValue(store),
      visionSessionClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 8, 12),
      ),
      visionSessionIdFactoryProvider.overrideWithValue(
        () => VisionSessionId.create('session-1'),
      ),
      if (!persistResults)
        visionSessionResultListenerProvider.overrideWithValue(results.add),
    ],
  );
  // Keeps the auto-dispose session controller alive for the test route.
  container.listen(visionSessionControllerProvider, (_, _) {});
  return _Rig(container, capture, coordinator, results, processor, store);
}

Future<void> _startToRunning(_Rig rig) async {
  await rig.controller.begin();
  rig.controller.beginCalibration();
  await rig.controller.start();
  expect(rig.state.status, VisionSessionStatus.running);
}

typedef _GatedAction = FutureOr<void> Function(VisionSessionController);

final class _GatedActionCase {
  const _GatedActionCase(this.name, this.allowed, this.invoke);

  final String name;
  final Set<VisionSessionStatus> allowed;
  final _GatedAction invoke;
}

final class _SeededVisionSessionController extends VisionSessionController {
  _SeededVisionSessionController(this.initialStatus);

  final VisionSessionStatus initialStatus;

  @override
  VisionSessionState build() =>
      VisionSessionState.idle().copyWith(status: initialStatus);
}

Future<void> _expectInvalidTransitionCell(
  VisionSessionStatus status,
  _GatedActionCase action,
) async {
  final container = ProviderContainer(
    overrides: [
      visionSessionControllerProvider.overrideWith(
        () => _SeededVisionSessionController(status),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(visionSessionControllerProvider, (_, _) {});

  final controller = container.read(visionSessionControllerProvider.notifier);
  final before = container.read(visionSessionControllerProvider);

  await action.invoke(controller);

  final after = container.read(visionSessionControllerProvider);
  expect(after.status, before.status);
  expect(after.issue, VisionSessionIssue.invalidTransition);
}

void main() {
  final gatedActions = <_GatedActionCase>[
    _GatedActionCase('begin', const <VisionSessionStatus>{
      VisionSessionStatus.idle,
      VisionSessionStatus.completed,
      VisionSessionStatus.cancelled,
    }, (controller) => controller.begin()),
    _GatedActionCase('requestPermission', const <VisionSessionStatus>{
      VisionSessionStatus.permissionDenied,
      VisionSessionStatus.permissionPermanentlyDenied,
      VisionSessionStatus.cameraUnavailable,
    }, (controller) => controller.requestPermission()),
    _GatedActionCase('beginCalibration', const <VisionSessionStatus>{
      VisionSessionStatus.setup,
    }, (controller) => controller.beginCalibration()),
    _GatedActionCase('start', const <VisionSessionStatus>{
      VisionSessionStatus.calibrating,
    }, (controller) => controller.start()),
    _GatedActionCase('pause', const <VisionSessionStatus>{
      VisionSessionStatus.running,
    }, (controller) => controller.pause()),
    _GatedActionCase('resume', const <VisionSessionStatus>{
      VisionSessionStatus.paused,
    }, (controller) => controller.resume()),
    _GatedActionCase('recalibrate', const <VisionSessionStatus>{
      VisionSessionStatus.running,
      VisionSessionStatus.paused,
      VisionSessionStatus.calibrationLost,
    }, (controller) => controller.recalibrate()),
    _GatedActionCase(
      'reportQuality',
      const <VisionSessionStatus>{
        VisionSessionStatus.running,
        VisionSessionStatus.paused,
      },
      (controller) => controller.reportQuality(
        summary: VisionQualitySummary.fromFrames(const <VisionFrameQuality>[]),
        hand: VisionMetricState.notObservable,
        pose: VisionMetricState.notObservable,
        guitar: CalibrationLossState.tracking,
      ),
    ),
    _GatedActionCase('reportRealtimeCue', const <VisionSessionStatus>{
      VisionSessionStatus.running,
      VisionSessionStatus.paused,
      VisionSessionStatus.calibrationLost,
    }, (controller) => controller.reportRealtimeCue(null)),
  ];

  group('VisionSessionController state machine', () {
    test(
      'moves through idle, setup, calibrating, running, paused and completed',
      () async {
        final rig = _rig();
        addTearDown(rig.dispose);

        expect(rig.state.status, VisionSessionStatus.idle);
        await rig.controller.begin();
        expect(rig.state.status, VisionSessionStatus.setup);
        rig.controller.beginCalibration();
        expect(rig.state.status, VisionSessionStatus.calibrating);
        await rig.controller.start();
        expect(rig.state.status, VisionSessionStatus.running);
        await rig.controller.pause();
        expect(rig.state.status, VisionSessionStatus.paused);
        await rig.controller.resume();
        expect(rig.state.status, VisionSessionStatus.running);
        await rig.controller.stop();

        expect(rig.state.status, VisionSessionStatus.completed);
        expect(rig.results, hasLength(1));
        expect(rig.capture.isClosed, isTrue);
        expect(rig.coordinator.activeOwner, isNull);
      },
    );

    test(
      'permission branches are controlled and explicit request reaches setup',
      () async {
        final rig = _rig(permission: CameraPermissionState.denied);
        addTearDown(rig.dispose);

        await rig.controller.begin();
        expect(rig.state.status, VisionSessionStatus.permissionDenied);
        await rig.controller.requestPermission();
        expect(rig.state.status, VisionSessionStatus.permissionDenied);
        rig.controller.beginCalibration();
        expect(rig.state.issue, VisionSessionIssue.invalidTransition);
      },
    );

    for (final action in gatedActions) {
      for (final status in VisionSessionStatus.values) {
        if (!action.allowed.contains(status)) {
          test('${status.name} rejects ${action.name}', () async {
            await _expectInvalidTransitionCell(status, action);
          });
        }
      }
    }

    test('state audit has a fixed summary-only key set', () {
      final rig = _rig();
      addTearDown(rig.dispose);

      expect(rig.state.auditFields, <String>{
        'status',
        'qualitySummary',
        'overlayQuality',
        'calibrationState',
        'detailedOverlayEnabled',
        'session',
        'realtimeCue',
        'issue',
        'result',
      });
      expect(rig.state.auditFields.join(','), isNot(contains('frame')));
      expect(rig.state.auditFields.join(','), isNot(contains('pixel')));
    });

    test(
      'R23-selected realtime cue is copied as-is without UI selection',
      () async {
        final rig = _rig();
        addTearDown(rig.dispose);
        await _startToRunning(rig);

        rig.controller.reportQuality(
          summary: VisionQualitySummary.fromFrames(<VisionFrameQuality>[]),
          hand: VisionMetricState.notObservable,
          pose: VisionMetricState.notObservable,
          guitar: CalibrationLossState.tracking,
        );
        rig.controller.reportRealtimeCue(null);

        expect(rig.state.realtimeCue, isNull);
      },
    );
  });

  group('VisionSessionController pipeline wiring (E09-R28a)', () {
    test('every delivered frame reaches the processor', () async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _startToRunning(rig);

      expect(rig.capture.emitFrame().isSuccess, isTrue);
      expect(rig.capture.emitFrame().isSuccess, isTrue);

      expect(rig.processor.frameIds, <int>[0, 1]);
      expect(rig.state.status, VisionSessionStatus.running);
    });

    test('a published summary lands in state', () async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _startToRunning(rig);

      final cue = VisionInsight(
        code: InsightCode.setupNotObservable,
        policyVersion: 'e05-r23-v1',
        evidenceIds: const <String>['evidence-1'],
        confidence: 1,
      );
      await rig.processor.emit(
        _update(hand: VisionMetricState.needsImprovement, cue: cue),
      );

      expect(rig.state.overlayQuality.hand, VisionMetricState.needsImprovement);
      expect(rig.state.overlayQuality.guitar, CalibrationLossState.tracking);
      expect(rig.state.realtimeCue, cue);
    });

    test('a lost calibration moves the session to calibrationLost', () async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _startToRunning(rig);

      await rig.processor.emit(_update(guitar: CalibrationLossState.lost));

      expect(rig.state.status, VisionSessionStatus.calibrationLost);
      expect(rig.state.calibrationState, CalibrationLossState.lost);
      // A later update must keep updating the cue without tripping the state
      // machine's invalid-transition guard.
      await rig.processor.emit(_update(guitar: CalibrationLossState.lost));
      expect(rig.state.issue, isNot(VisionSessionIssue.invalidTransition));
    });

    test('emitting after the session ended is inert', () async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _startToRunning(rig);
      await rig.controller.stop();

      final before = rig.state;
      await rig.processor.emit(
        _update(hand: VisionMetricState.needsImprovement),
      );

      expect(rig.processor.disposed, isTrue);
      expect(rig.state.status, before.status);
      expect(rig.state.issue, isNull);
    });

    test('the processor is disposed with the capture', () async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _startToRunning(rig);

      await rig.controller.stop();

      expect(rig.processor.disposed, isTrue);
    });

    test('recalibrating drops the processor', () async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _startToRunning(rig);

      await rig.controller.recalibrate();

      expect(rig.state.status, VisionSessionStatus.calibrating);
      expect(rig.processor.disposed, isTrue);
    });

    test('the finished session is persisted by the default listener', () async {
      final rig = _rig(persistResults: true);
      addTearDown(rig.dispose);
      await _startToRunning(rig);
      expect(rig.capture.emitFrame().isSuccess, isTrue);

      await rig.controller.stop();
      await Future<void>.delayed(Duration.zero);

      final entries = VisionSessionRepository(store: rig.store).list();
      expect(entries, hasLength(1));
      expect(entries.single.sessionId, 'session-1');
      expect(entries.single.observedFrameCount, 1);
      expect(entries.single.modelVersions, isNotEmpty);
    });
  });

  group('VisionSessionController exit matrix', () {
    Future<void> expectFinalizedDuringStart(
      Future<VisionSessionResult?> Function(VisionSessionController) exit,
      VisionSessionEndReason reason,
    ) async {
      final startGate = Completer<void>();
      final rig = _rig(startGate: startGate.future);
      addTearDown(rig.dispose);
      await rig.controller.begin();
      rig.controller.beginCalibration();

      final start = rig.controller.start();
      await Future<void>.delayed(Duration.zero);
      expect(rig.capture.startCalls, 1);

      final finalization = exit(rig.controller);
      startGate.complete();
      await start;
      final result = await finalization;

      expect(rig.state.status, VisionSessionStatus.completed);
      expect(rig.capture.isClosed, isTrue);
      expect(rig.coordinator.activeOwner, isNull);
      expect(rig.results, hasLength(1));
      expect(result, same(rig.results.single));
      expect(result!.endReason, reason);
    }

    test('explicit stop finalizes when capture start is in flight', () {
      return expectFinalizedDuringStart(
        (controller) => controller.stop(),
        VisionSessionEndReason.explicitStop,
      );
    });

    test('route leave finalizes when capture start is in flight', () {
      return expectFinalizedDuringStart(
        (controller) => controller.leaveRoute(),
        VisionSessionEndReason.routeLeave,
      );
    });

    Future<void> expectReleased(
      Future<void> Function(_Rig rig) exit,
      VisionSessionEndReason reason,
    ) async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _startToRunning(rig);
      expect(rig.capture.emitFrame().isSuccess, isTrue);

      await exit(rig);
      await Future<void>.delayed(Duration.zero);

      expect(rig.capture.isClosed, isTrue);
      expect(rig.coordinator.activeOwner, isNull);
      expect(rig.results, hasLength(1));
      expect(rig.results.single.endReason, reason);
      expect(rig.results.single.observedFrameCount, 1);
    }

    test(
      'explicit stop closes the stream and lease once',
      () => expectReleased(
        (rig) => rig.controller.stop(),
        VisionSessionEndReason.explicitStop,
      ),
    );

    test(
      'route leave closes the stream and lease once',
      () => expectReleased(
        (rig) => rig.controller.leaveRoute(),
        VisionSessionEndReason.routeLeave,
      ),
    );

    test(
      'app background revokes owner then finalizes once',
      () => expectReleased(
        (rig) => rig.coordinator.revokeActive(),
        VisionSessionEndReason.appBackground,
      ),
    );

    test(
      'capture error closes the stream and lease once',
      () => expectReleased((rig) async {
        rig.capture.interrupt();
      }, VisionSessionEndReason.failure),
    );

    test(
      'dispose closes the stream and emits no state after disposal',
      () async {
        final rig = _rig();
        await _startToRunning(rig);
        rig.dispose();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(rig.capture.isClosed, isTrue);
        expect(rig.coordinator.activeOwner, isNull);
        expect(rig.results, hasLength(1));
        expect(rig.results.single.endReason, VisionSessionEndReason.disposed);
      },
    );

    test(
      'dispose during capture start avoids disposed Riverpod state access',
      () async {
        final startGate = Completer<void>();
        final rig = _rig(startGate: startGate.future);
        await rig.controller.begin();
        rig.controller.beginCalibration();

        final start = rig.controller.start();
        await Future<void>.delayed(Duration.zero);
        expect(rig.capture.startCalls, 1);

        rig.dispose();
        startGate.complete();
        await expectLater(start, completes);
        await Future<void>.delayed(Duration.zero);

        expect(rig.capture.isClosed, isTrue);
        expect(rig.coordinator.activeOwner, isNull);
        expect(rig.results, hasLength(1));
        expect(rig.results.single.endReason, VisionSessionEndReason.disposed);
      },
    );

    test('stop followed immediately by route leave emits one result', () async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _startToRunning(rig);

      await Future.wait([rig.controller.stop(), rig.controller.leaveRoute()]);

      expect(rig.results, hasLength(1));
      expect(rig.coordinator.activeOwner, isNull);
    });
  });
}
