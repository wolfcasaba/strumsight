// Javító sáv 2026-09-06 (R6, `docs/ui/apk-functionality-audit-2026-09-06.md`
// §1.3): the `practiceResult` route always built `PracticeResultFallback`
// ("result unavailable"), because the navigation sink fires on the
// session's `NavigateToResult` effect BEFORE the durable record of that
// session completes (`_finalizeSession` awaits `recorder.record` after the
// transition's effects were already emitted). Nothing told the route WHICH
// entry to show, or whether it exists yet. This file is that hand-off.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// What the result route should show for the session that just ended.
@immutable
sealed class PracticeResultTarget {
  const PracticeResultTarget();
}

/// No session hand-off in this app run — the route was reached cold (deep
/// link) and shows the newest history entry, if any.
final class PracticeResultTargetNone extends PracticeResultTarget {
  const PracticeResultTargetNone();
}

/// Navigation happened before the session even produced its result id —
/// the record is still on its way.
final class PracticeResultTargetPending extends PracticeResultTarget {
  const PracticeResultTargetPending();
}

/// The session's result id is known; the history entry with that id is the
/// one to show — it may still be a moment away ([recorded] says whether
/// the durable write has completed).
final class PracticeResultTargetSession extends PracticeResultTarget {
  const PracticeResultTargetSession(this.sessionId, {required this.recorded});

  final String sessionId;
  final bool recorded;

  @override
  bool operator ==(Object other) =>
      other is PracticeResultTargetSession &&
      other.sessionId == sessionId &&
      other.recorded == recorded;

  @override
  int get hashCode => Object.hash(sessionId, recorded);
}

/// The durable record failed (the session already surfaced its recoverable
/// error) — there is no entry to show for it.
final class PracticeResultTargetFailed extends PracticeResultTarget {
  const PracticeResultTargetFailed();
}

/// The hand-off state machine between the session's navigation sink and
/// the after-record hooks. Both orders are handled:
///
/// * navigate → record: [expect] marks the session (or `pending` when the
///   result id is not produced yet), [recorded] completes it;
/// * record → navigate: [recorded] lands first, [expect] with the same id
///   keeps the completed state (it never regresses a recorded session).
final class PracticeResultTargetController
    extends Notifier<PracticeResultTarget> {
  @override
  PracticeResultTarget build() => const PracticeResultTargetNone();

  /// Called by the navigation sink. [sessionId] is the ending session's
  /// result id when the controller already produced it, else `null`.
  void expect(String? sessionId) {
    if (sessionId == null) {
      state = const PracticeResultTargetPending();
      return;
    }
    final current = state;
    if (current is PracticeResultTargetSession &&
        current.sessionId == sessionId) {
      return;
    }
    state = PracticeResultTargetSession(sessionId, recorded: false);
  }

  /// Called by the after-record hook once the entry is durably written.
  void recorded(String sessionId) {
    state = PracticeResultTargetSession(sessionId, recorded: true);
  }

  /// Called when the durable write failed.
  void recordFailed() {
    state = const PracticeResultTargetFailed();
  }
}

final practiceResultTargetProvider =
    NotifierProvider<PracticeResultTargetController, PracticeResultTarget>(
      PracticeResultTargetController.new,
    );
