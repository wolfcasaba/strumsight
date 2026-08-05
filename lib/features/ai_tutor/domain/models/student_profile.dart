/// Stable exception emitted when a student profile value is invalid.
class StudentProfileValidationException implements Exception {
  StudentProfileValidationException._(this.code);

  /// One of [StudentProfileValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'StudentProfileValidationException($code)';
}

/// Stable machine-readable codes emitted by student profile validation.
abstract final class StudentProfileValidationCode {
  static const String localeEmpty = 'studentProfile.locale.empty';
  static const String weeklyPracticeMinutesOutOfRange =
      'studentProfile.weeklyPracticeMinutes.outOfRange';
  static const String listItemEmpty = 'studentProfile.listItem.empty';
}

const int maxWeeklyPracticeMinutes = 7 * 24 * 60;

enum StudentExperienceLevel { unknown, beginner, intermediate, advanced }

enum TutorExplanationLength { concise, standard, detailed }

enum TutorFeedbackDirectness { supportive, balanced, direct }

enum StudentProfileFieldProvenance {
  userExplicit,
  settingsImported,
  practiceInferred,
  songInferred,
  systemDefault,
}

extension on StudentProfileFieldProvenance {
  bool get isInferred =>
      this == StudentProfileFieldProvenance.practiceInferred ||
      this == StudentProfileFieldProvenance.songInferred;
}

/// A profile value with its independently recorded provenance.
final class ProfileField<T> {
  const ProfileField(this.value, this.provenance);

  final T value;
  final StudentProfileFieldProvenance provenance;

  /// Retains an explicit value when a later inferred value conflicts with it.
  ProfileField<T> resolveWith(ProfileField<T> candidate) {
    if (provenance == StudentProfileFieldProvenance.userExplicit &&
        candidate.provenance.isInferred) {
      return this;
    }
    return candidate;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileField &&
          other.provenance == provenance &&
          _profileValuesEqual(other.value, value);

  @override
  int get hashCode => Object.hash(provenance, _profileValueHash(value));
}

/// Student tutoring preferences and per-field provenance.
final class StudentProfile {
  StudentProfile({
    required this.experienceLevel,
    required ProfileField<List<String>> preferredStyles,
    required ProfileField<int?> weeklyPracticeMinutes,
    required this.explanationLength,
    required this.feedbackDirectness,
    required ProfileField<List<String>> knownTechniques,
    required ProfileField<List<String>> avoidList,
    required ProfileField<String> locale,
  }) : preferredStyles = ProfileField(
         _immutableStrings(preferredStyles.value),
         preferredStyles.provenance,
       ),
       weeklyPracticeMinutes = weeklyPracticeMinutes,
       knownTechniques = ProfileField(
         _immutableStrings(knownTechniques.value),
         knownTechniques.provenance,
       ),
       avoidList = ProfileField(
         _immutableStrings(avoidList.value),
         avoidList.provenance,
       ),
       locale = ProfileField(_locale(locale.value), locale.provenance) {
    final minutes = weeklyPracticeMinutes.value;
    if (minutes != null &&
        (minutes < 0 || minutes > maxWeeklyPracticeMinutes)) {
      throw StudentProfileValidationException._(
        StudentProfileValidationCode.weeklyPracticeMinutesOutOfRange,
      );
    }
  }

  final ProfileField<StudentExperienceLevel> experienceLevel;
  final ProfileField<List<String>> preferredStyles;
  final ProfileField<int?> weeklyPracticeMinutes;
  final ProfileField<TutorExplanationLength> explanationLength;
  final ProfileField<TutorFeedbackDirectness> feedbackDirectness;
  final ProfileField<List<String>> knownTechniques;
  final ProfileField<List<String>> avoidList;
  final ProfileField<String> locale;

  /// Resolves each profile field without allowing inferred data over explicit data.
  StudentProfile merge(StudentProfile candidate) => StudentProfile(
    experienceLevel: experienceLevel.resolveWith(candidate.experienceLevel),
    preferredStyles: preferredStyles.resolveWith(candidate.preferredStyles),
    weeklyPracticeMinutes: weeklyPracticeMinutes.resolveWith(
      candidate.weeklyPracticeMinutes,
    ),
    explanationLength: explanationLength.resolveWith(
      candidate.explanationLength,
    ),
    feedbackDirectness: feedbackDirectness.resolveWith(
      candidate.feedbackDirectness,
    ),
    knownTechniques: knownTechniques.resolveWith(candidate.knownTechniques),
    avoidList: avoidList.resolveWith(candidate.avoidList),
    locale: locale.resolveWith(candidate.locale),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudentProfile &&
          other.experienceLevel == experienceLevel &&
          other.preferredStyles == preferredStyles &&
          other.weeklyPracticeMinutes == weeklyPracticeMinutes &&
          other.explanationLength == explanationLength &&
          other.feedbackDirectness == feedbackDirectness &&
          other.knownTechniques == knownTechniques &&
          other.avoidList == avoidList &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    experienceLevel,
    preferredStyles,
    weeklyPracticeMinutes,
    explanationLength,
    feedbackDirectness,
    knownTechniques,
    avoidList,
    locale,
  );
}

List<String> _immutableStrings(List<String> values) {
  final normalized = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw StudentProfileValidationException._(
        StudentProfileValidationCode.listItemEmpty,
      );
    }
    normalized.add(trimmed);
  }
  return List<String>.unmodifiable(normalized);
}

String _locale(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw StudentProfileValidationException._(
      StudentProfileValidationCode.localeEmpty,
    );
  }
  return trimmed;
}

bool _profileValuesEqual(Object? first, Object? second) {
  if (first is List && second is List) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_profileValuesEqual(first[index], second[index])) return false;
    }
    return true;
  }
  return first == second;
}

int _profileValueHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(_profileValueHash));
  }
  return value.hashCode;
}
