/// Origin of a practice definition.
enum PracticeSource {
  builtin('builtin'),
  lesson('lesson'),
  song('song'),
  analyze('analyze'),
  setlist('setlist'),
  dailyChallenge('dailyChallenge'),
  userCreated('userCreated'),

  /// Reserved for a future source; Epic 2 does not generate AI content.
  futureAi('futureAi');

  const PracticeSource(this.code);

  /// Stable persisted identifier independent of enum order.
  final String code;
}

/// Resolves a stable code without guessing a fallback.
PracticeSource? practiceSourceFromCode(String code) {
  for (final value in PracticeSource.values) {
    if (value.code == code) return value;
  }
  return null;
}
