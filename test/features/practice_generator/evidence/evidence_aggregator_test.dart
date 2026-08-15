import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/practice_generator/application/service/evidence_aggregator.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_evidence.dart';
import 'package:strumsight/features/practice_generator/domain/repository/practice_evidence_repository.dart';

/// Collects every record passed to the logger, verbatim, so a test can
/// assert both what WAS logged and — just as importantly — what was not.
final class CollectingAppLogger implements AppLogger {
  final List<String> events = <String>[];
  final List<Map<String, Object?>> fields = <Map<String, Object?>>[];
  final List<Object?> errors = <Object?>[];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      _record(event, fields);

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) =>
      _record(event, fields);

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    _record(event, fields);
    if (error != null) errors.add(error);
  }

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    _record(event, fields);
    errors.add(error);
  }

  void _record(String event, Map<String, Object?> recordFields) {
    events.add(event);
    fields.add(recordFields);
  }

  /// Every raw value ever recorded (event names, field values, errors),
  /// flattened for a single free-text-leak assertion.
  Iterable<String> get everyLoggedString sync* {
    yield* events;
    for (final map in fields) {
      for (final value in map.values) {
        if (value != null) yield value.toString();
      }
    }
    for (final err in errors) {
      if (err != null) yield err.toString();
    }
  }
}

void main() {
  const secretNote =
      'sharp stabbing pain in the left wrist during barre chords';

  SkillEvidence evidence({
    String skillId = 'chord.gMajor',
    EvidenceSource source = EvidenceSource.learn,
    required String outcomeId,
    DateTime? measuredAt,
    DiscomfortReport? discomfort,
    PerformanceEvidence? performance,
  }) => SkillEvidence(
    skillId: skillId,
    source: source,
    sourceOutcomeId: OutcomeId(outcomeId),
    measurementVersion: 1,
    measuredAt: measuredAt ?? DateTime.utc(2026, 8, 10),
    capturedAt: DateTime.utc(2026, 8, 15),
    confidence: 0.8,
    performance:
        performance ??
        (discomfort == null
            ? PerformanceEvidence(metricCode: 'chordChangeAccuracy', value: 0.7)
            : null),
    discomfort: discomfort,
  );

  group('EvidenceAggregator — deduplication (A2, A3)', () {
    test(
      'the same source outcome id ingested twice yields one evidence (A2)',
      () {
        final repository = InMemoryPracticeEvidenceRepository();
        final aggregator = EvidenceAggregator(repository: repository);

        aggregator.ingest(evidence(outcomeId: 'outcome-1'));
        aggregator.ingest(evidence(outcomeId: 'outcome-1'));

        expect(repository.allForSkill('chord.gMajor'), hasLength(1));
      },
    );

    test(
      'two different sources reporting the same outcome id still yield one evidence (A3)',
      () {
        final repository = InMemoryPracticeEvidenceRepository();
        final aggregator = EvidenceAggregator(repository: repository);

        aggregator.ingest(
          evidence(outcomeId: 'outcome-42', source: EvidenceSource.learn),
        );
        aggregator.ingest(
          evidence(outcomeId: 'outcome-42', source: EvidenceSource.progress),
        );

        final stored = repository.allForSkill('chord.gMajor');
        expect(stored, hasLength(1));
        expect(stored.single.source, EvidenceSource.learn);
      },
    );

    test('different source outcome ids are kept as distinct evidence', () {
      final repository = InMemoryPracticeEvidenceRepository();
      final aggregator = EvidenceAggregator(repository: repository);

      aggregator.ingest(evidence(outcomeId: 'outcome-1'));
      aggregator.ingest(evidence(outcomeId: 'outcome-2'));

      expect(repository.allForSkill('chord.gMajor'), hasLength(2));
    });
  });

  group('EvidenceAggregator — sensitive text never logged (A5)', () {
    test('a discomfort free-text note never reaches the logger', () {
      final repository = InMemoryPracticeEvidenceRepository();
      final logger = CollectingAppLogger();
      final aggregator = EvidenceAggregator(
        repository: repository,
        logger: logger,
      );

      aggregator.ingest(
        evidence(
          outcomeId: 'outcome-1',
          performance: null,
          discomfort: DiscomfortReport(category: DiscomfortCategory.pain),
        ),
        discomfortNote: secretNote,
      );

      expect(logger.events, isNotEmpty);
      for (final logged in logger.everyLoggedString) {
        expect(
          logged.contains(secretNote),
          isFalse,
          reason: 'free-text discomfort note leaked into a log record: $logged',
        );
      }
    });

    test(
      'logging only carries the stable outcome id and discomfort category',
      () {
        final repository = InMemoryPracticeEvidenceRepository();
        final logger = CollectingAppLogger();
        final aggregator = EvidenceAggregator(
          repository: repository,
          logger: logger,
        );

        aggregator.ingest(
          evidence(
            outcomeId: 'outcome-1',
            performance: null,
            discomfort: DiscomfortReport(category: DiscomfortCategory.tension),
          ),
          discomfortNote: secretNote,
        );

        expect(logger.fields.single['sourceOutcomeId'], 'outcome-1');
        expect(logger.fields.single['discomfortCategory'], 'tension');
        expect(logger.fields.single.containsValue(secretNote), isFalse);
      },
    );

    test('duplicate ingestion also never logs the note (dedup path)', () {
      final repository = InMemoryPracticeEvidenceRepository();
      final logger = CollectingAppLogger();
      final aggregator = EvidenceAggregator(
        repository: repository,
        logger: logger,
      );

      final withDiscomfort = evidence(
        outcomeId: 'outcome-1',
        performance: null,
        discomfort: DiscomfortReport(category: DiscomfortCategory.pain),
      );
      aggregator.ingest(withDiscomfort, discomfortNote: secretNote);
      aggregator.ingest(withDiscomfort, discomfortNote: secretNote);

      for (final logged in logger.everyLoggedString) {
        expect(logged.contains(secretNote), isFalse);
      }
    });

    test('a data-URI/base64-like discomfort note is discarded at the ingestion '
        'boundary — never stored, serialized, logged, or in an exception '
        '(regression, F1)', () {
      const dataUriNote =
          'data:audio/wav;base64,'
          'UklGRixhAAAAV0FWRWZtdCAQAAAAAQACAESsAAAAiBUAAAIAEABkYXRh';
      final repository = InMemoryPracticeEvidenceRepository();
      final logger = CollectingAppLogger();
      final aggregator = EvidenceAggregator(
        repository: repository,
        logger: logger,
      );

      Object? thrown;
      SkillEvidence? stored;
      try {
        stored = aggregator.ingest(
          evidence(
            outcomeId: 'outcome-data-uri',
            performance: null,
            discomfort: DiscomfortReport(category: DiscomfortCategory.pain),
          ),
          discomfortNote: dataUriNote,
        );
      } catch (e) {
        thrown = e;
      }

      expect(
        thrown,
        isNull,
        reason: 'ingest must not throw for an otherwise-valid evidence',
      );

      // Not stored: DiscomfortReport has no field capable of holding it.
      expect(stored, isNotNull);
      expect(stored!.discomfort!.category, DiscomfortCategory.pain);

      // Not serialized: nothing round-trips it back out.
      expect(stored.toString(), isNot(contains(dataUriNote)));
      expect(stored.discomfort.toString(), isNot(contains(dataUriNote)));
      expect(
        repository.allForSkill('chord.gMajor').toString(),
        isNot(contains(dataUriNote)),
      );

      // Not logged, in any event name, field, or error.
      for (final logged in logger.everyLoggedString) {
        expect(logged.contains(dataUriNote), isFalse);
      }

      // Not in an exception message, should any future path throw.
      if (thrown != null) {
        expect(thrown.toString(), isNot(contains(dataUriNote)));
      }
    });
  });
}
