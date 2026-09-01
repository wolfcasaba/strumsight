// E12-R19 — privacy-safe telemetry contract (ADR 0484). All acceptance
// cells for A1-A5 and A7 live in this one file per the round brief §0.0 R9
// (the A5 cell reads docs/operations/slo.yaml directly — no second document
// test, so there is only one source of truth for what "done" means here).
//
// A6 (Kör 17 consent cells) is `test/privacy/consent_enforcement_test.dart`,
// unchanged by this round and run alongside this file by the gate.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/log_redactor.dart';
import 'package:strumsight/core/telemetry/public.dart';

void main() {
  group('A1 — TelemetryEvent structurally forbids free-form payload fields '
      '(ADR 0484 D1) — source-scan, not runtime reflection (no dart:mirrors '
      'under flutter_test, §0.0 R4)', () {
    test('telemetry_event.dart has no Map<String,dynamic>/dynamic/Object? '
        'field and no free String field', () {
      final code = _withoutCommentsAndStrings(
        File('lib/core/telemetry/telemetry_event.dart').readAsStringSync(),
      );

      expect(
        RegExp(r'Map\s*<\s*String\s*,\s*dynamic\s*>').hasMatch(code),
        isFalse,
        reason:
            'a general Map<String, dynamic> payload field opens every '
            'structural protection back up (ADR 0484 D1)',
      );
      expect(
        RegExp(r'\bdynamic\b').hasMatch(code),
        isFalse,
        reason: 'no field or return type may be `dynamic`',
      );
      expect(
        RegExp(r'Object\?').hasMatch(code),
        isFalse,
        reason: 'no field may be typed `Object?`',
      );
      expect(
        _freeTypedFieldPattern('String').hasMatch(code),
        isFalse,
        reason:
            'no free-form String field is allowed — every dimension on '
            'the event must be a closed enum',
      );
    });
  });

  group('A2 — the redactor applies the EXISTING LogRedactor rules, not a '
      'second list (ADR 0484 D2)', () {
    test('(a) behaviour: token-like key, JWT/Bearer text, e-mail and '
        'over-length text are all redacted the same way LogRedactor redacts '
        'them', () {
      final input = <String, Object?>{
        'authToken': 'Bearer abc.def.ghi',
        'contactEmail': 'user@example.com',
        'note': 'x' * 250,
        'plain': 'hello',
      };

      final sanitized = TelemetryRedactor.sanitizeMetadata(input);

      expect(
        sanitized['authToken'],
        LogRedactor.redacted,
        reason: 'a token-like key is dropped entirely, whatever its value',
      );
      expect(sanitized['contactEmail'], contains(LogRedactor.redactedEmail));
      expect(
        (sanitized['note']! as String).startsWith('[redacted:'),
        isTrue,
        reason: 'a value over maxStringLength (200) must be summarised',
      );
      expect(sanitized['plain'], 'hello');

      expect(
        TelemetryRedactor.sanitizeText('Bearer sometoken123'),
        contains(LogRedactor.redactedToken),
      );
      expect(TelemetryRedactor.isSensitiveKey('sessionId'), isTrue);
    });

    test('(b) source-scan: telemetry_redactor.dart calls LogRedactor and '
        'declares no pattern/key-dictionary of its own', () {
      final code = _withoutCommentsAndStrings(
        File('lib/core/telemetry/telemetry_redactor.dart').readAsStringSync(),
      );

      expect(
        code.contains('LogRedactor'),
        isTrue,
        reason: 'the redactor must delegate to LogRedactor, not reimplement it',
      );
      expect(
        RegExp(r'\bRegExp\s*\(').hasMatch(code),
        isFalse,
        reason:
            'a second RegExp here is exactly the drifting second list '
            'ADR 0484 D2 forbids',
      );
      expect(
        RegExp(r'Set\s*<\s*String\s*>').hasMatch(code),
        isFalse,
        reason: 'a second key dictionary here is the same D2 violation',
      );
    });
  });

  group('A3 — opt-out mellett a sink NO-OP: nem tárol, nem pufferel '
      '(ADR 0484 D4)', () {
    test('record() with consent=false never reaches the delegate', () {
      final delegate = _RecordingTelemetrySink();
      final sink = ConsentGatedTelemetrySink(
        delegate: delegate,
        consentGranted: () => false,
      );

      sink.record(_sampleEvent());
      sink.record(_sampleEvent());

      expect(
        delegate.recorded,
        isEmpty,
        reason: 'the recording fake delegate must see zero events',
      );
    });

    test('events dropped while consent was false are NOT flushed after '
        'consent flips true — there is no buffer to flush from', () {
      final delegate = _RecordingTelemetrySink();
      var consentGranted = false;
      final sink = ConsentGatedTelemetrySink(
        delegate: delegate,
        consentGranted: () => consentGranted,
      );

      sink.record(_sampleEvent()); // dropped, consent is false
      expect(delegate.recorded, isEmpty);

      consentGranted = true; // the user opts in later in the same session

      expect(
        delegate.recorded,
        isEmpty,
        reason:
            'flipping consent alone must not retroactively deliver the '
            'event dropped before the flip — that would be collection '
            'before consent with the sending merely delayed',
      );

      sink.record(_sampleEvent()); // recorded — this one is AFTER the flip
      expect(delegate.recorded, hasLength(1));
    });
  });

  group('A4 — duration is reported as a bucket, lower bound inclusive '
      '(ADR 0484 D1)', () {
    test(
      '999ms (just under the 1000ms threshold) buckets to [500,1000)',
      () => expect(
        TelemetryDurationBucket.fromMilliseconds(999),
        TelemetryDurationBucket.ms500To1000,
      ),
    );
    test(
      '1000ms (exactly on the threshold) buckets to [1000,3000) — the '
      'lower bound is inclusive',
      () => expect(
        TelemetryDurationBucket.fromMilliseconds(1000),
        TelemetryDurationBucket.ms1000To3000,
      ),
    );
    test(
      '1001ms (just over the threshold) buckets to [1000,3000)',
      () => expect(
        TelemetryDurationBucket.fromMilliseconds(1001),
        TelemetryDurationBucket.ms1000To3000,
      ),
    );

    test('source-scan: the TelemetryEvent class body carries no raw int/'
        'Duration field', () {
      final source = File(
        'lib/core/telemetry/telemetry_event.dart',
      ).readAsStringSync();
      final classBody = _withoutCommentsAndStrings(
        _extractClassBody(source, 'TelemetryEvent'),
      );

      expect(
        _freeTypedFieldPattern('int').hasMatch(classBody),
        isFalse,
        reason: 'a raw int field on the event is a de-facto raw-ms channel',
      );
      expect(
        _freeTypedFieldPattern('Duration').hasMatch(classBody),
        isFalse,
        reason: 'a raw Duration field on the event is the same violation',
      );
    });
  });

  group('A5 — docs/operations/slo.yaml: unknown is never success, every '
      'SLO is required with on_missing: unknown (ADR 0484 D3)', () {
    late _SloDocument doc;

    setUpAll(() {
      doc = _parseSloYaml(File('docs/operations/slo.yaml').readAsLinesSync());
    });

    test('unknown is declared as a verdict but is not a success verdict', () {
      expect(doc.verdictValues, contains('unknown'));
      expect(doc.successVerdicts.contains('unknown'), isFalse);
    });

    test('unknown is a blocking verdict', () {
      expect(doc.blockingVerdicts.contains('unknown'), isTrue);
    });

    test('the document declares at least one SLO', () {
      expect(doc.slos, isNotEmpty);
    });

    test('every SLO is required: true with on_missing: unknown', () {
      for (final slo in doc.slos) {
        expect(
          slo.required,
          isTrue,
          reason: 'SLO "${slo.id}" must be required: true',
        );
        expect(
          slo.onMissing,
          'unknown',
          reason: 'SLO "${slo.id}" must declare on_missing: unknown',
        );
      }
    });

    test('every SLO id is unique', () {
      final ids = doc.slos.map((slo) => slo.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('A7 — the telemetry layer is structurally network-incapable '
      '(ADR 0484 D5)', () {
    test('no .dart file under lib/core/telemetry mentions Dio, ApiClient, '
        'HttpClient(, package:http or SharePlus', () {
      final forbidden = <RegExp>[
        RegExp(r'\bDio\b'),
        RegExp(r'\bApiClient\b'),
        RegExp(r'HttpClient\s*\('),
        RegExp(r'package:http'),
        RegExp(r'\bSharePlus\b'),
      ];

      final offences = <String>[];
      for (final entity in Directory(
        'lib/core/telemetry',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final code = _withoutCommentsAndStrings(entity.readAsStringSync());
        for (final pattern in forbidden) {
          if (pattern.hasMatch(code)) {
            offences.add('${entity.path}: matches $pattern');
          }
        }
      }

      expect(
        offences,
        isEmpty,
        reason:
            'the field\'s mere presence is enough to make this layer an '
            'egress route (ADR 0484 D5):\n${offences.join('\n')}',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

TelemetryEvent _sampleEvent() => const TelemetryEvent(
  name: TelemetryEventName.appLaunched,
  category: TelemetryEventCategory.lifecycle,
  result: TelemetryOperationResult.success,
  durationBucket: TelemetryDurationBucket.ms0To250,
);

final class _RecordingTelemetrySink implements TelemetrySink {
  final List<TelemetryEvent> recorded = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => recorded.add(event);
}

// ---------------------------------------------------------------------------
// Source-scan helpers — mirror the established real-tree scanning style of
// test/tooling/legacy_identifier_guard_test.dart and
// tool/check_data_inventory.dart's typed-member pattern, kept local to this
// test file (no second production tool needed for a single-file scan).
// ---------------------------------------------------------------------------

/// Blanks out `//` / `/* */` comments and string-literal contents (to
/// whitespace, preserving line breaks) so a doc comment or string literal
/// that merely NAMES a forbidden pattern cannot trip the scan below.
String _withoutCommentsAndStrings(String source) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final stop = end == -1 ? source.length : end + 2;
      buffer.write(source.substring(i, stop).replaceAll(RegExp('[^\n]'), ' '));
      i = stop;
      continue;
    }
    final char = source[i];
    if (char == "'" || char == '"') {
      final triple = source.startsWith(char * 3, i);
      final delimiter = triple ? char * 3 : char;
      final start = i;
      i += delimiter.length;
      while (i < source.length && !source.startsWith(delimiter, i)) {
        if (!triple && source[i] == r'\' && i + 1 < source.length) {
          i += 2;
          continue;
        }
        i++;
      }
      i = (i + delimiter.length).clamp(0, source.length);
      buffer.write(source.substring(start, i).replaceAll(RegExp('[^\n]'), ' '));
      continue;
    }
    buffer.write(char);
    i++;
  }
  return buffer.toString();
}

/// Matches a field declaration (`final <type> name;`) or constructor
/// parameter (`required <type> name,` / `<type> name)`) for [typeName] —
/// mirrors `tool/check_data_inventory.dart`'s `_dioTypedMemberPattern`, the
/// fan's own precedent for detecting a typed field by its declaration shape
/// rather than a bare token match (which would also fire on a doc comment
/// mentioning the type by name).
RegExp _freeTypedFieldPattern(String typeName) => RegExp(
  '\\bfinal\\s+$typeName\\??\\s+\\w+\\s*;|'
  '(?:required\\s+)?$typeName\\??\\s+\\w+\\s*[,)]',
);

/// Extracts the body of `class <className> { ... }` (brace-balanced, so the
/// constructor's own `({ ... })` parameter list nests correctly) from
/// [source].
String _extractClassBody(String source, String className) {
  final marker = RegExp('class\\s+$className\\b[^{]*\\{');
  final match = marker.firstMatch(source);
  if (match == null) {
    fail('class $className not found in source');
  }
  var depth = 1;
  var i = match.end;
  final start = i;
  while (i < source.length && depth > 0) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    i++;
  }
  return source.substring(start, i - 1);
}

// ---------------------------------------------------------------------------
// docs/operations/slo.yaml — hand-rolled line parser (§0.0 R5: no
// package:yaml dependency on the tree; mirrors
// tool/check_data_inventory.dart's DataInventory.parse over
// docs/privacy/data-inventory.yaml). Scoped to exactly the flat shape
// docs/operations/slo.yaml §8.1 mandates.
// ---------------------------------------------------------------------------

final class _SloDefinition {
  const _SloDefinition({
    required this.id,
    required this.required,
    required this.onMissing,
  });

  final String id;
  final bool required;
  final String onMissing;
}

final class _SloDocument {
  const _SloDocument({
    required this.verdictValues,
    required this.successVerdicts,
    required this.blockingVerdicts,
    required this.slos,
  });

  final List<String> verdictValues;
  final List<String> successVerdicts;
  final List<String> blockingVerdicts;
  final List<_SloDefinition> slos;
}

_SloDocument _parseSloYaml(List<String> lines) {
  List<String>? verdictValues;
  List<String>? successVerdicts;
  List<String>? blockingVerdicts;
  final slos = <_SloDefinition>[];

  String? id;
  String? onMissing;
  bool? required;
  var inSlo = false;

  void flush() {
    if (!inSlo) return;
    slos.add(
      _SloDefinition(
        id: id ?? '',
        required: required ?? false,
        onMissing: onMissing ?? '',
      ),
    );
    id = null;
    onMissing = null;
    required = null;
    inSlo = false;
  }

  final listPattern = RegExp(
    r'^(verdict_values|success_verdicts|blocking_verdicts):\s*\[(.*)\]\s*$',
  );
  final sloStartPattern = RegExp(r'^  - id:\s*(.*)$');
  final sloKvPattern = RegExp(r'^    (\w+):\s?(.*)$');

  for (final raw in lines) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    if (raw.trim() == 'slos:') continue;

    final listMatch = listPattern.firstMatch(raw);
    if (listMatch != null) {
      final values = listMatch
          .group(2)!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      switch (listMatch.group(1)!) {
        case 'verdict_values':
          verdictValues = values;
        case 'success_verdicts':
          successVerdicts = values;
        case 'blocking_verdicts':
          blockingVerdicts = values;
      }
      continue;
    }

    final startMatch = sloStartPattern.firstMatch(raw);
    if (startMatch != null) {
      flush();
      inSlo = true;
      id = startMatch.group(1)!.trim();
      continue;
    }

    final kvMatch = inSlo ? sloKvPattern.firstMatch(raw) : null;
    if (kvMatch != null) {
      final key = kvMatch.group(1)!;
      final value = kvMatch.group(2)!.trim();
      switch (key) {
        case 'required':
          required = value == 'true';
        case 'on_missing':
          onMissing = value;
        default:
          break; // title/metric/objective/window/source: not part of D3
      }
    }
  }
  flush();

  return _SloDocument(
    verdictValues: verdictValues ?? const [],
    successVerdicts: successVerdicts ?? const [],
    blockingVerdicts: blockingVerdicts ?? const [],
    slos: slos,
  );
}
