import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  group('LearningActivityEvent — canonical JSON contract', () {
    test(
      'A3/A8: all six event kinds round-trip through their explicit type',
      () {
        for (final event in _events()) {
          final encoded = event.toJson();
          final decoded = LearningActivityEvent.fromJson(
            jsonDecode(jsonEncode(encoded)),
          );

          expect(
            encoded['type'],
            event.type,
            reason: '${event.runtimeType} must persist its stable type',
          );
          expect(decoded, event);
          expect(decoded.runtimeType, event.runtimeType);
          expect(decoded.hashCode, event.hashCode);
        }
      },
    );

    test('A3: decoding follows type, never a field-presence heuristic', () {
      final json = _practiceEvent().toJson();
      json['type'] = VisionActivityEvent.typeCode;

      final decoded = LearningActivityEvent.fromJson(json);

      expect(decoded, isA<VisionActivityEvent>());
      expect(decoded.source, ActivitySource.practice);
    });

    test('A2: every event kind rejects an unknown schema version', () {
      for (final event in _events()) {
        final encoded = event.toJson()..['schemaVersion'] = 2;

        expect(
          () => LearningActivityEvent.fromJson(encoded),
          throwsArgumentError,
          reason: '${event.runtimeType} must not reinterpret version 2',
        );
      }
    });

    test(
      'A2: decoding rejects absent schemaVersion and unknown event type',
      () {
        final missingSchemaVersion = _practiceEvent().toJson()
          ..remove('schemaVersion');
        final unknownType = _practiceEvent().toJson()..['type'] = 'unknown';

        expect(
          () => LearningActivityEvent.fromJson(missingSchemaVersion),
          throwsArgumentError,
        );
        expect(
          () => LearningActivityEvent.fromJson(unknownType),
          throwsArgumentError,
        );
      },
    );
  });

  group('LearningActivityEvent — validation boundaries', () {
    test('A4: every event kind rejects a duration below zero', () {
      for (final create in _eventCreators()) {
        expect(
          () => create(duration: const Duration(milliseconds: -1)),
          throwsArgumentError,
        );
      }
    });

    test('A4: every event kind accepts Duration.zero at the boundary', () {
      for (final create in _eventCreators()) {
        final event = create(duration: Duration.zero);

        expect(event.duration, Duration.zero);
      }
    });

    test('A4: every event kind accepts a duration above zero', () {
      const duration = Duration(seconds: 1);
      for (final create in _eventCreators()) {
        final event = create(duration: duration);

        expect(event.duration, duration);
      }
    });

    test('A4: scores outside the closed zero-to-one range are rejected', () {
      for (final score in <double>[-0.001, 1.001, double.nan]) {
        expect(() => _practiceEvent(score: score), throwsArgumentError);
      }
    });

    test('A4: the score boundaries zero and one are accepted', () {
      expect(_practiceEvent(score: 0).score, 0);
      expect(_practiceEvent(score: 1).score, 1);
    });

    test('A5: every event kind rejects an empty or blank caller eventId', () {
      for (final create in _eventCreators()) {
        expect(() => create(eventId: ''), throwsArgumentError);
        expect(() => create(eventId: '   '), throwsArgumentError);
      }
    });
  });

  group('associated domain types', () {
    test('ActivitySource has the persisted feature source codes', () {
      expect(ActivitySource.values.map((source) => source.name), <String>[
        'live',
        'analyze',
        'learn',
        'practice',
        'songTrainer',
        'vision',
        'tutor',
        'practicePlan',
      ]);
    });

    test('EvidenceTrust has the evidence-grade contract', () {
      expect(EvidenceTrust.values.map((trust) => trust.name), <String>[
        'unverified',
        'userConfirmed',
        'deviceObserved',
        'scored',
        'verified',
      ]);
    });

    test('RewardEligibility is an immutable validated data contract', () {
      final eligibility = RewardEligibility(
        eligible: true,
        reasonCode: 'practice.valid',
        validDuration: const Duration(minutes: 1),
        quality: 0.8,
        difficultyBand: 3,
      );

      expect(eligibility.eligible, isTrue);
      expect(eligibility.reasonCode, 'practice.valid');
      expect(eligibility.validDuration, const Duration(minutes: 1));
      expect(eligibility.quality, 0.8);
      expect(eligibility.difficultyBand, 3);
      expect(
        () => RewardEligibility(
          eligible: true,
          reasonCode: '',
          validDuration: Duration.zero,
          quality: 0.8,
          difficultyBand: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

typedef _EventCreator =
    LearningActivityEvent Function({String eventId, Duration duration});

List<_EventCreator> _eventCreators() => <_EventCreator>[
  ({
    String eventId = 'practice-1',
    Duration duration = const Duration(seconds: 1),
  }) => _practiceEvent(eventId: eventId, duration: duration),
  ({
    String eventId = 'song-1',
    Duration duration = const Duration(seconds: 1),
  }) => SongActivityEvent(
    eventId: eventId,
    occurredAt: _occurredAt,
    epochDay: _epochDay,
    source: ActivitySource.songTrainer,
    trust: EvidenceTrust.scored,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: duration,
    score: 0.8,
  ),
  ({
    String eventId = 'analysis-1',
    Duration duration = const Duration(seconds: 1),
  }) => AnalysisActivityEvent(
    eventId: eventId,
    occurredAt: _occurredAt,
    epochDay: _epochDay,
    source: ActivitySource.analyze,
    trust: EvidenceTrust.deviceObserved,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: duration,
    score: 0.7,
  ),
  ({
    String eventId = 'plan-1',
    Duration duration = const Duration(seconds: 1),
  }) => PlanActivityEvent(
    eventId: eventId,
    occurredAt: _occurredAt,
    epochDay: _epochDay,
    source: ActivitySource.practicePlan,
    trust: EvidenceTrust.userConfirmed,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: duration,
    score: 0.6,
  ),
  ({
    String eventId = 'tutor-1',
    Duration duration = const Duration(seconds: 1),
  }) => TutorActivityEvent(
    eventId: eventId,
    occurredAt: _occurredAt,
    epochDay: _epochDay,
    source: ActivitySource.tutor,
    trust: EvidenceTrust.userConfirmed,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: duration,
    score: 0.5,
  ),
  ({
    String eventId = 'vision-1',
    Duration duration = const Duration(seconds: 1),
  }) => VisionActivityEvent(
    eventId: eventId,
    occurredAt: _occurredAt,
    epochDay: _epochDay,
    source: ActivitySource.vision,
    trust: EvidenceTrust.deviceObserved,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: duration,
    score: 0.9,
  ),
];

List<LearningActivityEvent> _events() =>
    _eventCreators().map((create) => create()).toList(growable: false);

PracticeActivityEvent _practiceEvent({
  String eventId = 'practice-1',
  Duration duration = const Duration(seconds: 1),
  double score = 0.9,
}) => PracticeActivityEvent(
  eventId: eventId,
  occurredAt: _occurredAt,
  epochDay: _epochDay,
  source: ActivitySource.practice,
  trust: EvidenceTrust.scored,
  schemaVersion: learningActivityEventSchemaVersion,
  duration: duration,
  score: score,
);

final DateTime _occurredAt = DateTime.utc(2026, 8, 19, 12);
const int _epochDay = 20684;
