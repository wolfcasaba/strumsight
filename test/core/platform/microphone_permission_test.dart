import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';

/// E01-R09 §9.1 — the permission state → failure contract. The codes are what
/// the UI localises and what tests assert on, so they are pinned here.
void main() {
  test('granted is the only state without a failure', () {
    for (final state in MicrophonePermissionState.values) {
      expect(
        state.failure == null,
        state == MicrophonePermissionState.granted,
        reason: '$state',
      );
    }
  });

  test('denied is retryable — the dialog can still help', () {
    final failure = MicrophonePermissionState.denied.failure!;
    expect(failure, isA<PermissionFailure>());
    expect(failure.code, FailureCode.permissionMicrophoneDenied);
    expect(failure.retryable, isTrue);
  });

  test('permanently denied and restricted need the system settings', () {
    for (final state in const [
      MicrophonePermissionState.permanentlyDenied,
      MicrophonePermissionState.restricted,
    ]) {
      expect(state.failure!.code, FailureCode.permissionMicrophoneDenied);
      expect(state.failure!.retryable, isFalse, reason: '$state');
    }
  });

  test('an unavailable channel is its own, non-retryable code', () {
    final failure = MicrophonePermissionState.unavailable.failure!;
    expect(failure.code, FailureCode.permissionUnavailable);
    expect(failure.retryable, isFalse);
    expect(
      MicrophonePermissionState.unavailable.isGranted,
      isFalse,
      reason: 'a plugin error is never consent (§9.1)',
    );
  });
}
