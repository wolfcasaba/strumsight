/// Stable-coded enum families for the AI Practice Generator domain
/// (ADR 0257, SDD Ch8 §7.7/§10.2/§14.2/§16.4/§17.2).
///
/// Every enum persists a fixed string `code`, never the Dart identifier
/// (`.name`): renaming a Dart enum value must not corrupt saved data.
/// Decoding an empty, missing, or unrecognized code is a controlled error —
/// never a silent fallback to a default value.
library;

/// Lifecycle state of an [AdaptivePracticePlan]-to-be (SDD Ch8 §7.7).
enum PlanStatus {
  draft('draft'),
  active('active'),
  paused('paused'),
  completed('completed'),
  archived('archived'),
  superseded('superseded'),
  cancelled('cancelled');

  const PlanStatus(this.code);

  final String code;

  static PlanStatus fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'PlanStatus',
  );

  @override
  String toString() => code;
}

/// Why a plan generation was requested (SDD Ch8 §10.2).
enum GenerationMode {
  starter('starter'),
  adaptive('adaptive'),
  songGoal('songGoal'),
  maintenance('maintenance'),
  returningAfterBreak('returningAfterBreak'),
  microPlan('microPlan'),
  assessment('assessment');

  const GenerationMode(this.code);

  final String code;

  static GenerationMode fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'GenerationMode',
  );

  @override
  String toString() => code;
}

/// The role a [PracticeBlock]-to-be plays within a day (SDD Ch8 §16.4).
enum BlockKind {
  readiness('readiness'),
  warmup('warmup'),
  assessment('assessment'),
  primaryFocus('primaryFocus'),
  secondaryFocus('secondaryFocus'),
  maintenance('maintenance'),
  song('song'),
  freePlay('freePlay'),
  reflection('reflection'),
  rest('rest'),
  cooldown('cooldown');

  const BlockKind(this.code);

  final String code;

  static BlockKind fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'BlockKind',
  );

  @override
  String toString() => code;
}

/// Severity of a plan-validation finding (SDD Ch8 §17.2).
enum ValidationSeverity {
  info('info'),
  warning('warning'),
  error('error'),
  fatal('fatal');

  const ValidationSeverity(this.code);

  final String code;

  static ValidationSeverity fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'ValidationSeverity',
  );

  @override
  String toString() => code;
}

/// Where an exercise candidate or evidence sample originated
/// (SDD Ch8 §14.2).
enum CandidateSource {
  practiceCatalog('practiceCatalog'),
  legacyLesson('legacyLesson'),
  songRange('songRange'),
  analysisHotspot('analysisHotspot'),
  visionCalibration('visionCalibration'),
  assessment('assessment'),
  freePractice('freePractice'),
  reflection('reflection'),
  rest('rest');

  const CandidateSource(this.code);

  final String code;

  static CandidateSource fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'CandidateSource',
  );

  @override
  String toString() => code;
}

/// Shared decode routine for every enum family above: an empty/missing code
/// and an unrecognized code both fail loudly instead of resolving to
/// whichever value happens to be first (ADR 0257 §4).
T _decodeEnumCode<T extends Enum>({
  required String? code,
  required List<T> values,
  required String Function(T value) codeOf,
  required String typeName,
}) {
  if (code == null || code.trim().isEmpty) {
    throw ArgumentError.value(code, 'code', '$typeName code must not be empty');
  }
  for (final value in values) {
    if (codeOf(value) == code) return value;
  }
  throw ArgumentError.value(code, 'code', 'Unknown $typeName code: $code');
}
