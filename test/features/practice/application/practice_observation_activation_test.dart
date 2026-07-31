import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/application/practice_observation_activation.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';

void main() {
  test('maps every practice session status to its capture decision', () {
    const expected = <PracticeSessionStatus, bool>{
      PracticeSessionStatus.idle: false,
      PracticeSessionStatus.preparing: false,
      PracticeSessionStatus.permissionRequired: false,
      PracticeSessionStatus.ready: false,
      PracticeSessionStatus.countIn: true,
      PracticeSessionStatus.running: true,
      PracticeSessionStatus.paused: false,
      PracticeSessionStatus.finishing: false,
      PracticeSessionStatus.completed: false,
      PracticeSessionStatus.cancelled: false,
      PracticeSessionStatus.failed: false,
    };

    for (final status in PracticeSessionStatus.values) {
      expect(
        practiceCaptureActiveByStatus[status],
        expected[status],
        reason: '$status must have an explicit policy entry',
      );
      expect(practiceCaptureActive(status), expected[status]);
    }
  });

  test('policy keys cover exactly the session status enum', () {
    expect(
      practiceCaptureActiveByStatus.keys.toSet(),
      PracticeSessionStatus.values.toSet(),
    );
  });

  test('paused disables capture and closes the chunk 014 pause gap', () {
    expect(practiceCaptureActive(PracticeSessionStatus.paused), isFalse);
  });
}
