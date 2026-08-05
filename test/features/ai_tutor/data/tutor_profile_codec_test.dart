import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/data/local/tutor_profile_codec.dart';
import 'package:strumsight/features/ai_tutor/domain/models/guitar_profile.dart';
import 'package:strumsight/features/ai_tutor/domain/models/learning_goal.dart';
import 'package:strumsight/features/ai_tutor/domain/models/student_profile.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_consent.dart';

const _codec = TutorProfileCodec();

void main() {
  const codec = _codec;

  group('TutorProfileCodec round-trip', () {
    test('round-trips each profile model and consent', () {
      final student = _studentProfile();
      final guitar = _guitarProfile();
      final goal = _learningGoal();
      const consent = TutorConsent(
        modelUseGranted: true,
        evaluationWithRedactionGranted: true,
      );

      final studentBytes = codec.encodeStudentProfile(student);
      final guitarBytes = codec.encodeGuitarProfile(guitar);
      final goalBytes = codec.encodeLearningGoal(goal);
      final consentBytes = codec.encodeTutorConsent(consent);

      final decodedStudent = codec.decodeStudentProfile(studentBytes);
      final decodedGuitar = codec.decodeGuitarProfile(guitarBytes);
      final decodedGoal = codec.decodeLearningGoal(goalBytes);
      final decodedConsent = codec.decodeTutorConsent(consentBytes);

      expect(decodedStudent, student);
      expect(decodedGuitar, guitar);
      expect(decodedGoal, goal);
      expect(decodedConsent, consent);
      expect(codec.encodeStudentProfile(decodedStudent), equals(studentBytes));
      expect(codec.encodeGuitarProfile(decodedGuitar), equals(guitarBytes));
      expect(codec.encodeLearningGoal(decodedGoal), equals(goalBytes));
      expect(codec.encodeTutorConsent(decodedConsent), equals(consentBytes));
    });

    test('produces byte-identical canonical envelopes after a round-trip', () {
      final original = _studentProfile();

      final first = codec.encodeStudentProfile(original);
      final decoded = codec.decodeStudentProfile(first);
      final second = codec.encodeStudentProfile(decoded);

      expect(second, first);
      expect(utf8.decode(second), utf8.decode(first));
    });

    test('round-trips consent axes without implying one another', () {
      const original = TutorConsent(persistentStorageGranted: true);

      final decoded = codec.decodeTutorConsent(
        codec.encodeTutorConsent(original),
      );

      expect(decoded.modelUseGranted, isFalse);
      expect(decoded.persistentStorageGranted, isTrue);
      expect(decoded.evaluationWithRedactionGranted, isFalse);
    });
  });

  group('TutorProfileCodec compatibility policy', () {
    test('ignores unknown fields when decoding a known envelope', () {
      final original = _studentProfile();
      final json = _jsonFor(codec.encodeStudentProfile(original));
      json['futureEnvelopeField'] = true;
      (json['studentProfile'] as Map<String, Object?>)['futureField'] =
          'kept by newer writers';

      final decoded = codec.decodeStudentProfile(utf8.encode(jsonEncode(json)));

      expect(decoded, original);
    });

    test('rejects missing required fields with a stable code', () {
      final json = _jsonFor(codec.encodeGuitarProfile(_guitarProfile()));
      json.remove('guitarProfile');

      expect(
        () => codec.decodeGuitarProfile(utf8.encode(jsonEncode(json))),
        throwsA(
          isA<TutorProfileCodecException>().having(
            (error) => error.code,
            'code',
            TutorProfileCodecErrorCode.fieldMissing,
          ),
        ),
      );
    });

    test('rejects unknown schema versions with a stable code', () {
      final json = _jsonFor(codec.encodeTutorConsent(const TutorConsent()));
      json['schemaVersion'] = TutorProfileCodec.supportedSchemaVersion + 1;

      expect(
        () => codec.decodeTutorConsent(utf8.encode(jsonEncode(json))),
        throwsA(
          isA<TutorProfileCodecException>().having(
            (error) => error.code,
            'code',
            TutorProfileCodecErrorCode.schemaVersionUnknown,
          ),
        ),
      );
    });
  });
}

StudentProfile _studentProfile() => StudentProfile(
  experienceLevel: ProfileField(
    StudentExperienceLevel.intermediate,
    StudentProfileFieldProvenance.userExplicit,
  ),
  preferredStyles: ProfileField(<String>[
    'blues',
    'rock',
  ], StudentProfileFieldProvenance.userExplicit),
  weeklyPracticeMinutes: ProfileField(
    180,
    StudentProfileFieldProvenance.userExplicit,
  ),
  explanationLength: ProfileField(
    TutorExplanationLength.detailed,
    StudentProfileFieldProvenance.userExplicit,
  ),
  feedbackDirectness: ProfileField(
    TutorFeedbackDirectness.direct,
    StudentProfileFieldProvenance.userExplicit,
  ),
  knownTechniques: ProfileField(<String>[
    'barre chords',
  ], StudentProfileFieldProvenance.userExplicit),
  avoidList: ProfileField(<String>[
    'rapid repeated bends',
  ], StudentProfileFieldProvenance.userExplicit),
  locale: ProfileField('hu', StudentProfileFieldProvenance.settingsImported),
);

GuitarProfile _guitarProfile() => GuitarProfile(
  id: 'guitar-1',
  name: ProfileField('Electric', StudentProfileFieldProvenance.userExplicit),
  type: ProfileField(
    GuitarType.electric,
    StudentProfileFieldProvenance.userExplicit,
  ),
  tuning: ProfileField(<String>[
    'E2',
    'A2',
    'D3',
    'G3',
    'B3',
    'E4',
  ], StudentProfileFieldProvenance.settingsImported),
  stringCount: ProfileField(6, StudentProfileFieldProvenance.settingsImported),
  capoFret: ProfileField(0, StudentProfileFieldProvenance.userExplicit),
  isPrimary: ProfileField(true, StudentProfileFieldProvenance.userExplicit),
);

LearningGoal _learningGoal() => LearningGoal(
  id: 'goal-1',
  statement: 'Build a daily practice habit',
  category: LearningGoalCategory.buildPracticeHabit,
  priority: LearningGoalPriority.medium,
  deadline: DateTime.utc(2026, 10, 1),
  status: LearningGoalStatus.active,
);

Map<String, Object?> _jsonFor(List<int> bytes) => Map<String, Object?>.from(
  jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
);
