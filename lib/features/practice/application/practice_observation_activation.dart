import '../domain/model/practice_session_state.dart';

/// The status table used by the E02-R09 controller to decide whether capture
/// may be active. The controller reads this table rather than a widget field.
const Map<PracticeSessionStatus, bool> practiceCaptureActiveByStatus = {
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

/// Returns the capture decision from [practiceCaptureActiveByStatus].
///
/// The E02-R09 controller is the intended caller. Capture activation is owned
/// by this status table, never by a presentation-layer widget field.
bool practiceCaptureActive(PracticeSessionStatus status) =>
    practiceCaptureActiveByStatus[status] ??
    (throw StateError('Missing capture policy for status: $status'));
