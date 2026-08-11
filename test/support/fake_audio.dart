import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:strumsight/core/audio/audio_providers.dart';
import 'package:strumsight/core/audio/capture/audio_capture.dart';
import 'package:strumsight/core/audio/capture/audio_capture_factory.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/audio/mic_capture.dart';
import 'package:strumsight/core/platform/app_lifecycle.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/core/platform/screen_wakelock.dart';

/// Test doubles for the E01-R09 microphone lifecycle.
///
/// The whole point of Kör 9's gateways is that no test needs a platform
/// channel to describe "permission denied", "the mic is busy" or "the app went
/// to the background" — it injects one of these instead.

/// A permission gateway with a scripted answer.
class FakeMicrophonePermissionGateway implements MicrophonePermissionGateway {
  FakeMicrophonePermissionGateway({
    this.state = MicrophonePermissionState.granted,
    this._afterRequest,
  });

  /// What [currentState] reports (and what [request] leaves behind).
  MicrophonePermissionState state;
  final MicrophonePermissionState? _afterRequest;

  int currentStateCalls = 0;
  int requestCalls = 0;

  @override
  Future<MicrophonePermissionState> currentState() async {
    currentStateCalls++;
    return state;
  }

  @override
  Future<MicrophonePermissionState> request() async {
    requestCalls++;
    return state = _afterRequest ?? state;
  }
}

/// A PCM source that never touches a device.
class FakeAudioCapture implements AudioCapture {
  FakeAudioCapture({this.sampleRate = 44100, this.failWith, this.startGate});

  final int sampleRate;

  /// When set, [start] throws it — "the mic is busy / the channel is broken".
  final Object? failWith;

  /// When set, [start] awaits it first — lets a test land a stop() exactly
  /// mid-handshake.
  final Future<void>? startGate;

  int startCalls = 0;
  int stopCalls = 0;
  bool isRunning = false;
  void Function(List<double> chunk)? _onChunk;
  final List<void Function(List<double> chunk)> _callbackHistory = [];

  /// Every callback handed to a start attempt, including stale ones. Tests can
  /// deliver a late chunk from a previous recording deterministically.
  List<void Function(List<double> chunk)> get callbackHistory =>
      List.unmodifiable(_callbackHistory);

  @override
  Future<int> start(void Function(List<double> chunk) onChunk) async {
    startCalls++;
    _onChunk = onChunk;
    _callbackHistory.add(onChunk);
    if (startGate != null) await startGate;
    if (failWith != null) throw failWith!;
    isRunning = true;
    return sampleRate;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    isRunning = false;
  }

  /// Deliver a chunk as if the device had produced it.
  void emit(List<double> chunk) => _onChunk?.call(chunk);

  /// Delivers to the callback captured by a particular start attempt.
  void emitToStart(int startIndex, List<double> chunk) =>
      _callbackHistory[startIndex](chunk);
}

/// A sample buffer which records every indexed read. It proves that preview
/// calculations remain linear in the incoming PCM rather than doing repeated
/// passes or invoking an analysis stage.
class CountingSampleBuffer extends ListBase<double> {
  CountingSampleBuffer(Iterable<double> values) : _values = List.of(values);

  final List<double> _values;
  int readCount = 0;

  @override
  int get length => _values.length;

  @override
  set length(int value) => _values.length = value;

  @override
  double operator [](int index) {
    readCount++;
    return _values[index];
  }

  @override
  void operator []=(int index, double value) {
    _values[index] = value;
  }
}

/// Drivable app lifecycle: `emit(AppLifecycleState.paused)` == "user switched
/// apps".
class FakeAppLifecycleEvents implements AppLifecycleEvents {
  final List<void Function(AppLifecycleState)> listeners = [];
  bool disposed = false;

  @override
  void addListener(void Function(AppLifecycleState state) listener) =>
      listeners.add(listener);

  @override
  void removeListener(void Function(AppLifecycleState state) listener) =>
      listeners.remove(listener);

  @override
  void dispose() => disposed = true;

  void emit(AppLifecycleState state) {
    for (final listener in List.of(listeners)) {
      listener(state);
    }
  }
}

/// Counts wakelock acquire/release so a test can prove it was RELEASED.
class FakeScreenWakelock implements ScreenWakelock {
  int enableCalls = 0;
  int disableCalls = 0;
  bool isHeld = false;

  @override
  Future<void> enable() async {
    enableCalls++;
    isHeld = true;
  }

  @override
  Future<void> disable() async {
    disableCalls++;
    isHeld = false;
  }
}

/// A [MicCapture] wired to fakes — the default building block of the mic tests.
MicCapture fakeMicCapture({
  AudioOwner owner = AudioOwner.live,
  AudioSessionCoordinator? coordinator,
  MicrophonePermissionGateway? permissions,
  AudioCapture? capture,
}) => MicCapture(
  owner: owner,
  coordinator: coordinator ?? AudioSessionCoordinator(),
  permissions: permissions ?? FakeMicrophonePermissionGateway(),
  captureFactory: () => capture ?? FakeAudioCapture(),
);

/// Provider overrides that keep a widget test entirely off the platform:
/// permission is whatever [permissions] says, capture is a fake, and the
/// lifecycle/wakelock are drivable.
List<Override> fakeAudioOverrides({
  MicrophonePermissionGateway? permissions,
  AudioCaptureFactory? captureFactory,
  AppLifecycleEvents? lifecycle,
  ScreenWakelock? wakelock,
}) => [
  microphonePermissionGatewayProvider.overrideWithValue(
    permissions ?? FakeMicrophonePermissionGateway(),
  ),
  audioCaptureFactoryProvider.overrideWithValue(
    captureFactory ?? FakeAudioCapture.new,
  ),
  appLifecycleEventsProvider.overrideWithValue(
    lifecycle ?? FakeAppLifecycleEvents(),
  ),
  screenWakelockProvider.overrideWithValue(wakelock ?? FakeScreenWakelock()),
];
