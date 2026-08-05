import '../../domain/models/tutor_ids.dart';

/// One correlated imperative step emitted by [reduceTutorTurn].
sealed class TutorEffect {
  const TutorEffect(this.requestId);

  final TutorRequestId requestId;
}

final class BuildTutorContext extends TutorEffect {
  const BuildTutorContext(super.requestId);
}

final class RetrieveTutorKnowledge extends TutorEffect {
  const RetrieveTutorKnowledge(super.requestId);
}

final class StartTutorModel extends TutorEffect {
  const StartTutorModel(super.requestId, {required this.isRepair});

  final bool isRepair;
}

final class ExecuteTutorTool extends TutorEffect {
  const ExecuteTutorTool(
    super.requestId, {
    required this.name,
    required this.arguments,
  });

  final String name;
  final String arguments;
}

final class ValidateTutorOutput extends TutorEffect {
  const ValidateTutorOutput(super.requestId);
}

final class CancelTutorModel extends TutorEffect {
  const CancelTutorModel(super.requestId);
}

final class TutorTurnCompleted extends TutorEffect {
  const TutorTurnCompleted(super.requestId);
}

final class TutorDeterministicFallback extends TutorEffect {
  const TutorDeterministicFallback(super.requestId);
}

final class TutorConsentRevoked extends TutorEffect {
  const TutorConsentRevoked(super.requestId);
}

final class TutorUsageLimitReached extends TutorEffect {
  const TutorUsageLimitReached(super.requestId);
}
