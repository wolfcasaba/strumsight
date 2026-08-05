/// Stable exception emitted when a learning goal value is invalid.
class LearningGoalValidationException implements Exception {
  LearningGoalValidationException._(this.code);

  /// One of [LearningGoalValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'LearningGoalValidationException($code)';
}

/// Stable machine-readable codes emitted by learning goal validation.
abstract final class LearningGoalValidationCode {
  static const String idEmpty = 'learningGoal.id.empty';
  static const String statementEmpty = 'learningGoal.statement.empty';
  static const String statementTooLong = 'learningGoal.statement.tooLong';
}

const int maxLearningGoalStatementLength = 500;

enum LearningGoalCategory {
  improveRhythm,
  cleanChordChanges,
  learnSong,
  increaseStableTempo,
  buildPracticeHabit,
  improvePitchAccuracy,
  understandTheory,
}

enum LearningGoalPriority { low, medium, high }

enum LearningGoalStatus { active, inactive }

/// Learning-goal data with an optional UTC deadline.
final class LearningGoal {
  LearningGoal({
    required String id,
    required String statement,
    required this.category,
    required this.priority,
    DateTime? deadline,
    required this.status,
  }) : id = _id(id),
       statement = _statement(statement),
       deadline = deadline?.toUtc();

  final String id;
  final String statement;
  final LearningGoalCategory category;
  final LearningGoalPriority priority;
  final DateTime? deadline;
  final LearningGoalStatus status;

  LearningGoal activate() => _withStatus(LearningGoalStatus.active);

  LearningGoal deactivate() => _withStatus(LearningGoalStatus.inactive);

  LearningGoal _withStatus(LearningGoalStatus nextStatus) => LearningGoal(
    id: id,
    statement: statement,
    category: category,
    priority: priority,
    deadline: deadline,
    status: nextStatus,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LearningGoal &&
          other.id == id &&
          other.statement == statement &&
          other.category == category &&
          other.priority == priority &&
          other.deadline == deadline &&
          other.status == status;

  @override
  int get hashCode =>
      Object.hash(id, statement, category, priority, deadline, status);
}

String _id(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw LearningGoalValidationException._(LearningGoalValidationCode.idEmpty);
  }
  return trimmed;
}

String _statement(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw LearningGoalValidationException._(
      LearningGoalValidationCode.statementEmpty,
    );
  }
  if (trimmed.length > maxLearningGoalStatementLength) {
    throw LearningGoalValidationException._(
      LearningGoalValidationCode.statementTooLong,
    );
  }
  return trimmed;
}
