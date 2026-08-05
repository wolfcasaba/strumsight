import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/guitar_profile.dart';
import 'package:strumsight/features/ai_tutor/domain/models/learning_goal.dart';
import 'package:strumsight/features/ai_tutor/domain/models/student_profile.dart';

void main() {
  group('StudentProfile', () {
    test('retains a typed provenance for every user-visible field', () {
      final profile = _studentProfile();

      expect(
        profile.experienceLevel.provenance,
        StudentProfileFieldProvenance.userExplicit,
      );
      expect(
        profile.preferredStyles.provenance,
        StudentProfileFieldProvenance.userExplicit,
      );
      expect(
        profile.weeklyPracticeMinutes.provenance,
        StudentProfileFieldProvenance.userExplicit,
      );
      expect(
        profile.explanationLength.provenance,
        StudentProfileFieldProvenance.userExplicit,
      );
      expect(
        profile.feedbackDirectness.provenance,
        StudentProfileFieldProvenance.userExplicit,
      );
      expect(
        profile.knownTechniques.provenance,
        StudentProfileFieldProvenance.userExplicit,
      );
      expect(
        profile.avoidList.provenance,
        StudentProfileFieldProvenance.userExplicit,
      );
      expect(
        profile.locale.provenance,
        StudentProfileFieldProvenance.settingsImported,
      );
    });

    test('does not let inferred values replace explicit values', () {
      final explicit = _studentProfile();
      final inferred = _studentProfile(
        experienceLevel: ProfileField(
          StudentExperienceLevel.advanced,
          StudentProfileFieldProvenance.practiceInferred,
        ),
        preferredStyles: ProfileField(<String>[
          'jazz',
        ], StudentProfileFieldProvenance.songInferred),
      );

      final merged = explicit.merge(inferred);

      expect(merged.experienceLevel, explicit.experienceLevel);
      expect(merged.preferredStyles, explicit.preferredStyles);
      expect(merged.locale, explicit.locale);
    });

    test('copies collections so its profile fields cannot be mutated', () {
      final sourceStyles = <String>['rock'];
      final sourceAvoidList = <String>['wide stretches'];
      final profile = _studentProfile(
        preferredStyles: ProfileField(
          sourceStyles,
          StudentProfileFieldProvenance.userExplicit,
        ),
        avoidList: ProfileField(
          sourceAvoidList,
          StudentProfileFieldProvenance.userExplicit,
        ),
      );
      sourceStyles.add('jazz');
      sourceAvoidList.clear();

      expect(profile.preferredStyles.value, equals(<String>['rock']));
      expect(profile.avoidList.value, equals(<String>['wide stretches']));
      expect(
        () => profile.preferredStyles.value.add('metal'),
        throwsUnsupportedError,
      );
      expect(() => profile.avoidList.value.clear(), throwsUnsupportedError);
    });

    test('rejects invalid profile values with stable error codes', () {
      expect(
        () => _studentProfile(
          locale: ProfileField(
            ' ',
            StudentProfileFieldProvenance.settingsImported,
          ),
        ),
        throwsA(
          isA<StudentProfileValidationException>().having(
            (error) => error.code,
            'code',
            StudentProfileValidationCode.localeEmpty,
          ),
        ),
      );
      expect(
        () => _studentProfile(
          weeklyPracticeMinutes: ProfileField(
            maxWeeklyPracticeMinutes + 1,
            StudentProfileFieldProvenance.userExplicit,
          ),
        ),
        throwsA(
          isA<StudentProfileValidationException>().having(
            (error) => error.code,
            'code',
            StudentProfileValidationCode.weeklyPracticeMinutesOutOfRange,
          ),
        ),
      );
    });

    test('uses value equality and matching hashes for equal profiles', () {
      final first = _studentProfile();
      final second = _studentProfile();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          _studentProfile(
            feedbackDirectness: ProfileField(
              TutorFeedbackDirectness.direct,
              StudentProfileFieldProvenance.userExplicit,
            ),
          ),
        ),
      );
    });
  });

  group('GuitarProfile', () {
    test('retains provenance, tuning, capo, and primary selection', () {
      final profile = _guitarProfile();

      expect(profile.id, 'guitar-1');
      expect(profile.name.value, 'Main acoustic');
      expect(profile.type.value, GuitarType.acousticSteel);
      expect(profile.tuning.value, _standardTuning);
      expect(profile.stringCount.value, 6);
      expect(profile.capoFret.value, 2);
      expect(profile.isPrimary.value, isTrue);
      expect(
        profile.tuning.provenance,
        StudentProfileFieldProvenance.settingsImported,
      );
    });

    test('copies tuning so it cannot be mutated after construction', () {
      final sourceTuning = List<String>.from(_standardTuning);
      final profile = _guitarProfile(
        tuning: ProfileField(
          sourceTuning,
          StudentProfileFieldProvenance.settingsImported,
        ),
      );
      sourceTuning[0] = 'D2';

      expect(profile.tuning.value.first, 'E2');
      expect(() => profile.tuning.value.add('B5'), throwsUnsupportedError);
    });

    test('does not let inferred guitar fields replace explicit values', () {
      final explicit = _guitarProfile();
      final inferred = _guitarProfile(
        name: ProfileField(
          'Inferred electric',
          StudentProfileFieldProvenance.songInferred,
        ),
        capoFret: ProfileField(
          0,
          StudentProfileFieldProvenance.practiceInferred,
        ),
      );

      final merged = explicit.merge(inferred);

      expect(merged.id, explicit.id);
      expect(merged.name, explicit.name);
      expect(merged.capoFret, explicit.capoFret);
    });

    test('rejects invalid configuration with stable error codes', () {
      expect(
        () => _guitarProfile(
          stringCount: ProfileField(
            minGuitarStringCount - 1,
            StudentProfileFieldProvenance.userExplicit,
          ),
        ),
        throwsA(
          isA<GuitarProfileValidationException>().having(
            (error) => error.code,
            'code',
            GuitarProfileValidationCode.stringCountOutOfRange,
          ),
        ),
      );
      expect(
        () => _guitarProfile(
          tuning: ProfileField(<String>[
            'E2',
          ], StudentProfileFieldProvenance.userExplicit),
        ),
        throwsA(
          isA<GuitarProfileValidationException>().having(
            (error) => error.code,
            'code',
            GuitarProfileValidationCode.tuningLengthMismatch,
          ),
        ),
      );
      expect(
        () => _guitarProfile(
          capoFret: ProfileField(
            maxGuitarCapoFret + 1,
            StudentProfileFieldProvenance.userExplicit,
          ),
        ),
        throwsA(
          isA<GuitarProfileValidationException>().having(
            (error) => error.code,
            'code',
            GuitarProfileValidationCode.capoFretOutOfRange,
          ),
        ),
      );
    });

    test('uses value equality and matching hashes for equal guitars', () {
      final first = _guitarProfile();
      final second = _guitarProfile();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          _guitarProfile(
            capoFret: ProfileField(
              0,
              StudentProfileFieldProvenance.userExplicit,
            ),
          ),
        ),
      );
    });
  });

  group('LearningGoal', () {
    test('keeps category, priority, deadline, and active state together', () {
      final goal = _learningGoal();

      expect(goal.category, LearningGoalCategory.improveRhythm);
      expect(goal.priority, LearningGoalPriority.high);
      expect(goal.deadline, DateTime.utc(2026, 9, 1));
      expect(goal.status, LearningGoalStatus.active);
    });

    test('changes active state with immutable lifecycle values', () {
      final active = _learningGoal();

      final inactive = active.deactivate();
      final activatedAgain = inactive.activate();

      expect(active.status, LearningGoalStatus.active);
      expect(inactive.status, LearningGoalStatus.inactive);
      expect(activatedAgain, active);
    });

    test('rejects an empty statement with a stable error code', () {
      expect(
        () => _learningGoal(statement: ' '),
        throwsA(
          isA<LearningGoalValidationException>().having(
            (error) => error.code,
            'code',
            LearningGoalValidationCode.statementEmpty,
          ),
        ),
      );
    });

    test('uses value equality and matching hashes for equal goals', () {
      final first = _learningGoal();
      final second = _learningGoal();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(_learningGoal(priority: LearningGoalPriority.low)));
    });
  });
}

StudentProfile _studentProfile({
  ProfileField<StudentExperienceLevel>? experienceLevel,
  ProfileField<List<String>>? preferredStyles,
  ProfileField<int?>? weeklyPracticeMinutes,
  ProfileField<TutorExplanationLength>? explanationLength,
  ProfileField<TutorFeedbackDirectness>? feedbackDirectness,
  ProfileField<List<String>>? knownTechniques,
  ProfileField<List<String>>? avoidList,
  ProfileField<String>? locale,
}) {
  return StudentProfile(
    experienceLevel:
        experienceLevel ??
        ProfileField(
          StudentExperienceLevel.beginner,
          StudentProfileFieldProvenance.userExplicit,
        ),
    preferredStyles:
        preferredStyles ??
        ProfileField(<String>[
          'rock',
        ], StudentProfileFieldProvenance.userExplicit),
    weeklyPracticeMinutes:
        weeklyPracticeMinutes ??
        ProfileField(120, StudentProfileFieldProvenance.userExplicit),
    explanationLength:
        explanationLength ??
        ProfileField(
          TutorExplanationLength.standard,
          StudentProfileFieldProvenance.userExplicit,
        ),
    feedbackDirectness:
        feedbackDirectness ??
        ProfileField(
          TutorFeedbackDirectness.supportive,
          StudentProfileFieldProvenance.userExplicit,
        ),
    knownTechniques:
        knownTechniques ??
        ProfileField(<String>[
          'open chords',
        ], StudentProfileFieldProvenance.userExplicit),
    avoidList:
        avoidList ??
        ProfileField(<String>[
          'painful stretches',
        ], StudentProfileFieldProvenance.userExplicit),
    locale:
        locale ??
        ProfileField('hu', StudentProfileFieldProvenance.settingsImported),
  );
}

GuitarProfile _guitarProfile({
  ProfileField<String>? name,
  ProfileField<GuitarType>? type,
  ProfileField<List<String>>? tuning,
  ProfileField<int>? stringCount,
  ProfileField<int>? capoFret,
  ProfileField<bool>? isPrimary,
}) {
  return GuitarProfile(
    id: 'guitar-1',
    name:
        name ??
        ProfileField(
          'Main acoustic',
          StudentProfileFieldProvenance.userExplicit,
        ),
    type:
        type ??
        ProfileField(
          GuitarType.acousticSteel,
          StudentProfileFieldProvenance.userExplicit,
        ),
    tuning:
        tuning ??
        ProfileField(
          List<String>.from(_standardTuning),
          StudentProfileFieldProvenance.settingsImported,
        ),
    stringCount:
        stringCount ??
        ProfileField(6, StudentProfileFieldProvenance.settingsImported),
    capoFret:
        capoFret ?? ProfileField(2, StudentProfileFieldProvenance.userExplicit),
    isPrimary:
        isPrimary ??
        ProfileField(true, StudentProfileFieldProvenance.userExplicit),
  );
}

LearningGoal _learningGoal({
  String statement = 'Keep eighth-note rhythm even',
  LearningGoalPriority priority = LearningGoalPriority.high,
}) {
  return LearningGoal(
    id: 'goal-1',
    statement: statement,
    category: LearningGoalCategory.improveRhythm,
    priority: priority,
    deadline: DateTime.utc(2026, 9, 1).toLocal(),
    status: LearningGoalStatus.active,
  );
}

const _standardTuning = <String>['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];
