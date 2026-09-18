import 'dart:async';

import 'package:strumsight/core/platform/microphone_permission.dart';

/// A permission gateway that PARKS on the system dialog until the test says
/// otherwise.
///
/// `FakeMicrophonePermissionGateway` answers within a microtask, which closes
/// the §9.3 window entirely: by the time a test can call `stop()`, the start
/// handshake is already past the permission step. This one hands the test the
/// exact moment the dialog went up ([asked]) and lets it decide when the user
/// answers ([grant]) — the window in which "the user left the screen while the
/// dialog was up" actually happens on a device.
class GatedPermissionGateway implements MicrophonePermissionGateway {
  GatedPermissionGateway({this.initial = MicrophonePermissionState.denied});

  /// What [currentState] reports, i.e. why the dialog is shown at all.
  final MicrophonePermissionState initial;

  final Completer<void> _asked = Completer<void>();
  final Completer<MicrophonePermissionState> _answer =
      Completer<MicrophonePermissionState>();

  /// Completes when [request] has been reached — the dialog is now up.
  Future<void> get asked => _asked.future;

  @override
  Future<MicrophonePermissionState> currentState() async => initial;

  @override
  Future<MicrophonePermissionState> request() {
    if (!_asked.isCompleted) _asked.complete();
    return _answer.future;
  }

  /// The user answers the dialog.
  void grant([
    MicrophonePermissionState state = MicrophonePermissionState.granted,
  ]) {
    if (!_answer.isCompleted) _answer.complete(state);
  }
}
