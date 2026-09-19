/// Riverpod wiring for the tutor's practice-plan preview (R9).
///
/// The preview screen used to have no source of drafts at all — it could
/// only be built by a test handing it one. These are the two seams that
/// make it a real surface: the length the student asked for, and the
/// producer that turns the on-device exercise catalog into a draft.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/planning/tutor_practice_plan_producer.dart';

/// The practice length a proposed plan is built for.
///
/// Held here (rather than passed as a route argument) so any tutor surface
/// can set it from the student's own input without the preview screen
/// needing a navigation contract.
class TutorPlanLengthController extends Notifier<Duration> {
  /// Twenty minutes is the middle of the deterministic-template ladder the
  /// plan model already supports (5 / 10 / 20 / 30).
  @override
  Duration build() => const Duration(minutes: 20);

  /// Sets the requested length. Values below one minute are ignored: the
  /// producer cannot split them into whole-minute blocks.
  void setMinutes(int minutes) {
    if (minutes < 1) return;
    state = Duration(minutes: minutes);
  }
}

final tutorPlanLengthProvider =
    NotifierProvider<TutorPlanLengthController, Duration>(
      TutorPlanLengthController.new,
    );

/// The pure producer. A provider so tests can substitute it, and so the
/// route never constructs planning logic inline.
final tutorPracticePlanProducerProvider = Provider<TutorPracticePlanProducer>(
  (ref) => const TutorPracticePlanProducer(),
);
