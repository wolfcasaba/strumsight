/// Coarse authored difficulty of a practice definition.
enum PracticeDifficulty {
  beginner('beginner'),
  intermediate('intermediate'),
  advanced('advanced');

  const PracticeDifficulty(this.code);

  /// Stable persisted identifier independent of enum order.
  final String code;
}

/// Resolves a stable code without guessing a fallback.
PracticeDifficulty? practiceDifficultyFromCode(String code) {
  for (final value in PracticeDifficulty.values) {
    if (value.code == code) return value;
  }
  return null;
}
