// E12-R19 — privacy-safe telemetry contract (ADR 0484). All acceptance
// cells for A1-A5 and A7 live in this one file per the round brief §0.0 R9
// (the A5 cell reads docs/operations/slo.yaml directly — no second document
// test, so there is only one source of truth for what "done" means here).
//
// A6 (Kör 17 consent cells) is `test/privacy/consent_enforcement_test.dart`,
// unchanged by this round and run alongside this file by the gate.
//
// Javító kör #1 (docs/reviews/e12-r19-review.md): A1/A4 moved from a
// type-name DENYLIST to a closed-enum ALLOWLIST (MAJOR-1); the
// docs/operations/slo.yaml parser gained a fail-closed SLO-count check and
// an exact success_verdicts match (MAJOR-2); A1 now scans the whole
// lib/core/telemetry directory (MINOR-1); A2(b) also forbids a second
// List<String>/set literal (MINOR-2); A7's pattern list also covers local
// persistence (MINOR-3); the redactor doc-comment no longer overstates what
// LogRedactor does to metadata keys (MINOR-4); event-catalog.md is now
// checked against the enums in both directions (MINOR-5).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/log_redactor.dart';
import 'package:strumsight/core/telemetry/public.dart';

void main() {
  group('A1 — TelemetryEvent structurally forbids free-form payload fields '
      '(ADR 0484 D1) — source-scan, not runtime reflection (no dart:mirrors '
      'under flutter_test, §0.0 R4)', () {
    test('no .dart file under lib/core/telemetry declares a field typed '
        'Map<..., dynamic>, dynamic, Object or a free String — scanned as '
        'FIELD DECLARATIONS across the whole directory, not just '
        'telemetry_event.dart, so a sibling file cannot reopen the D1 hole '
        '(Javító kör #1, MINOR-1)', () {
      final offences = <String>[];
      for (final entity in Directory(
        'lib/core/telemetry',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final code = _withoutCommentsAndStrings(entity.readAsStringSync());
        for (final field in _fieldDeclarations(code)) {
          if (_isForbiddenTelemetryFieldType(field.key)) {
            offences.add(
              '${entity.path}: field `${field.value}` typed `${field.key}`',
            );
          }
        }
      }
      expect(
        offences,
        isEmpty,
        reason:
            'a free-form field anywhere under lib/core/telemetry reopens '
            'the D1 hole even when it is not on TelemetryEvent itself:\n'
            '${offences.join('\n')}',
      );
    });

    test(
      'TelemetryEvent field allowlist: every field is typed as one of the '
      'closed Telemetry* enums — an ALLOWLIST, not a denylist, so a future '
      'Map/List/double field cannot slip through simply because nobody '
      'named it in advance (Javító kör #1, MAJOR-1)',
      _expectTelemetryEventFieldsAreClosedEnums,
    );
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
      expect(
        RegExp(r'List\s*<\s*String\s*>').hasMatch(code),
        isFalse,
        reason:
            'a second string list here is the same drifting-D2-violation as '
            'a second Set<String> (Javító kör #1, MINOR-2)',
      );
      expect(
        RegExp(r'=\s*\{').hasMatch(code),
        isFalse,
        reason:
            'an un-annotated set/map literal here is the same D2 violation '
            'as a typed second list (Javító kör #1, MINOR-2)',
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

    test(
      'source-scan: every TelemetryEvent field is one of the closed '
      'Telemetry* enums — a raw int/Duration/double field is a de-facto '
      'raw-ms channel and is caught by the same allowlist as A1 (Javító '
      'kör #1, MAJOR-1)',
      _expectTelemetryEventFieldsAreClosedEnums,
    );
  });

  group('A5 — docs/operations/slo.yaml: unknown is never success, every '
      'SLO is required with on_missing: unknown (ADR 0484 D3)', () {
    late _SloDocument doc;

    setUpAll(() {
      doc = _parseSloYaml(File('docs/operations/slo.yaml').readAsLinesSync());
    });

    test('unknown is declared as a verdict but is not a success verdict', () {
      expect(doc.verdictValues, contains('unknown'));
      expect(
        doc.successVerdicts,
        ['success'],
        reason:
            'must be exactly ["success"] — an accidentally emptied list '
            'must not vacuously satisfy "does not contain unknown" '
            '(Javító kör #1, MAJOR-2)',
      );
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

    test('the parser observed every "- id:" line in the file — a silently '
        'dropped SLO (e.g. from a wrong indent) must fail loudly, not leave '
        'the dashboard green (Javító kör #1, MAJOR-2)', () {
      final raw = File('docs/operations/slo.yaml').readAsStringSync();
      final rawIdCount = RegExp(
        r'^\s*- id:',
        multiLine: true,
      ).allMatches(raw).length;
      expect(
        doc.slos.length,
        rawIdCount,
        reason:
            'the hand-rolled parser found ${doc.slos.length} SLO(s) but '
            'the file has $rawIdCount "- id:" line(s) — an indentation '
            'mismatch is silently dropping at least one SLO from every '
            'downstream check',
      );
    });

    test('schema_version is declared as 1 (Javító kör #1, MAJOR-2)', () {
      expect(doc.schemaVersion, 1);
    });
  });

  group('A7 — the telemetry layer is structurally network- AND local-'
      'persistence-incapable (ADR 0484 D5)', () {
    test('no .dart file under lib/core/telemetry mentions Dio, ApiClient, '
        'HttpClient(, package:http, SharePlus, dart:io, File(, Socket, '
        'WebSocket, SharedPreferences or path_provider — the D5 prohibition '
        'covers local persistence as well as the network (Javító kör #1, '
        'MINOR-3)', () {
      final forbidden = <RegExp>[
        RegExp(r'\bDio\b'),
        RegExp(r'\bApiClient\b'),
        RegExp(r'HttpClient\s*\('),
        RegExp(r'package:http'),
        RegExp(r'\bSharePlus\b'),
        RegExp(r"import\s+'dart:io'"),
        RegExp(r'\bFile\s*\('),
        RegExp(r'\bSocket\b'),
        RegExp(r'\bWebSocket\b'),
        RegExp(r'\bSharedPreferences\b'),
        RegExp(r'package:path_provider'),
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
            'egress or local-persistence route (ADR 0484 D5):\n'
            '${offences.join('\n')}',
      );
    });
  });

  group('MINOR-5 — event-catalog.md is checked against the enum values in '
      'both directions, not just documented as needing to be (Javító kör '
      '#1)', () {
    late String enumSource;
    late String catalog;

    setUpAll(() {
      enumSource = _withoutCommentsAndStrings(
        File('lib/core/telemetry/telemetry_event.dart').readAsStringSync(),
      );
      catalog = File('docs/analytics/event-catalog.md').readAsStringSync();
    });

    test('TelemetryEventName is in sync with the catalog in both '
        'directions', () {
      final enumValues = _simpleEnumValues(
        enumSource,
        'TelemetryEventName',
      ).toSet();
      final catalogValues = _catalogBacktickedTokens(
        catalog,
        'TelemetryEventName',
      ).toSet();

      expect(enumValues, isNotEmpty);
      expect(
        enumValues.difference(catalogValues),
        isEmpty,
        reason: 'enum value(s) missing from event-catalog.md (enum → doc)',
      );
      expect(
        catalogValues.difference(enumValues),
        isEmpty,
        reason:
            'event-catalog.md names value(s) that do not exist on '
            'TelemetryEventName (doc → enum)',
      );
    });

    test('TelemetryEventCategory is in sync with the catalog in both '
        'directions', () {
      final enumValues = _simpleEnumValues(
        enumSource,
        'TelemetryEventCategory',
      ).toSet();
      final catalogValues = _catalogBacktickedTokens(
        catalog,
        'TelemetryEventCategory',
      ).toSet();

      expect(enumValues, isNotEmpty);
      expect(
        enumValues.difference(catalogValues),
        isEmpty,
        reason: 'enum value(s) missing from event-catalog.md (enum → doc)',
      );
      expect(
        catalogValues.difference(enumValues),
        isEmpty,
        reason:
            'event-catalog.md names value(s) that do not exist on '
            'TelemetryEventCategory (doc → enum)',
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

/// Extracts every `final <type> <name>;` field declaration in [code] as
/// (type, name) pairs. [code] must already have comments/strings blanked
/// out via [_withoutCommentsAndStrings]. Scoped to whole-line declarations
/// (this fan's own style for every field in this directory), so it
/// naturally skips constructor parameter lists and method signatures —
/// neither ends a line in `<word>;` the way a field declaration does, which
/// is what keeps this directory-wide scan from tripping on e.g.
/// `telemetry_redactor.dart`'s `Map<String, Object?> sanitizeMetadata(...)`
/// method signature.
List<MapEntry<String, String>> _fieldDeclarations(String code) {
  final pattern = RegExp(r'^\s*final\s+(.+)\s+(\w+);\s*$', multiLine: true);
  return [
    for (final match in pattern.allMatches(code))
      MapEntry(match.group(1)!.trim(), match.group(2)!),
  ];
}

/// Whether [type] (a field's declared type, as captured by
/// [_fieldDeclarations]) is one of the free-form shapes ADR 0484 D1
/// forbids anywhere under `lib/core/telemetry` — `dynamic` in any position,
/// a bare `Object`, a bare `String`, or a `Map<...>` whose value type is
/// `dynamic`.
bool _isForbiddenTelemetryFieldType(String type) {
  final bareType = type.endsWith('?')
      ? type.substring(0, type.length - 1)
      : type;
  return RegExp(r'\bdynamic\b').hasMatch(type) ||
      bareType == 'Object' ||
      bareType == 'String' ||
      (bareType.startsWith('Map<') && type.contains('dynamic'));
}

/// The closed set of enum types every [TelemetryEvent] field must be typed
/// as (nullable or not).
const _closedTelemetryEventFieldTypes = <String>{
  'TelemetryEventName',
  'TelemetryEventCategory',
  'TelemetryOperationResult',
  'TelemetryDurationBucket',
  'TelemetryCapability',
};

/// MAJOR-1: an ALLOWLIST, not a denylist — ADR 0484 D1 states a POSITIVE
/// rule ("every field is a closed enum"), so this checks every field on
/// [TelemetryEvent] against the closed set of `Telemetry*` enums instead of
/// naming free-form types to reject one at a time. A denylist of named
/// types (`dynamic`, `Object?`, a hand-picked `Map<String, dynamic>` shape)
/// lets a future `Map<String, String>`, `List<String>` or raw `double`
/// field slip through simply because nobody enumerated it in advance
/// (docs/LESSONS.md L549) — shared between the A1 and A4 acceptance cells
/// because both map to the same underlying assertion.
void _expectTelemetryEventFieldsAreClosedEnums() {
  final source = File(
    'lib/core/telemetry/telemetry_event.dart',
  ).readAsStringSync();
  final classBody = _withoutCommentsAndStrings(
    _extractClassBody(source, 'TelemetryEvent'),
  );
  final fields = _fieldDeclarations(classBody);

  expect(
    fields,
    isNotEmpty,
    reason:
        'the field-declaration scan matched nothing on TelemetryEvent — '
        'the pattern or the class-body extraction is broken, not that the '
        'class genuinely has no fields',
  );

  for (final field in fields) {
    final type = field.key;
    final bareType = type.endsWith('?')
        ? type.substring(0, type.length - 1)
        : type;
    expect(
      _closedTelemetryEventFieldTypes.contains(bareType),
      isTrue,
      reason:
          'TelemetryEvent.${field.value} is typed `$type`, which is not '
          'one of the closed Telemetry* enums '
          '($_closedTelemetryEventFieldTypes) — every field must be a '
          'closed enum (ADR 0484 D1); a Map, List, double or any other '
          'free-form type reopens the hole the enum-only contract closes',
    );
  }
}

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

/// Extracts the comma-separated values of a simple (no constructor, no
/// arguments) `enum <enumName> { a, b, c }` declaration from [code]. Used
/// only for [TelemetryEventName] and [TelemetryEventCategory] — neither
/// carries constructor arguments, so splitting the brace-balanced body on
/// `,` is exact.
List<String> _simpleEnumValues(String code, String enumName) {
  final marker = RegExp('enum\\s+$enumName\\b\\s*\\{');
  final match = marker.firstMatch(code);
  if (match == null) {
    fail('enum $enumName not found in source');
  }
  final end = code.indexOf('}', match.end);
  if (end == -1) {
    fail('unterminated enum $enumName');
  }
  return code
      .substring(match.end, end)
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

/// Extracts every backtick-quoted `` `token` `` under the markdown `##
/// \`sectionHeading\`` heading in [markdown], up to (not including) the
/// next `## ` heading.
List<String> _catalogBacktickedTokens(String markdown, String sectionHeading) {
  final headingPattern = RegExp('^## `$sectionHeading`.*', multiLine: true);
  final headingMatch = headingPattern.firstMatch(markdown);
  if (headingMatch == null) {
    fail('event-catalog.md has no "## `$sectionHeading`" heading');
  }
  final nextHeadingStart = RegExp(r'^## ', multiLine: true)
      .allMatches(markdown)
      .map((m) => m.start)
      .firstWhere(
        (start) => start > headingMatch.start,
        orElse: () => markdown.length,
      );
  final section = markdown.substring(headingMatch.end, nextHeadingStart);
  return RegExp(
    r'`(\w+)`',
  ).allMatches(section).map((m) => m.group(1)!).toList();
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
    required this.schemaVersion,
    required this.verdictValues,
    required this.successVerdicts,
    required this.blockingVerdicts,
    required this.slos,
  });

  final int? schemaVersion;
  final List<String> verdictValues;
  final List<String> successVerdicts;
  final List<String> blockingVerdicts;
  final List<_SloDefinition> slos;
}

_SloDocument _parseSloYaml(List<String> lines) {
  int? schemaVersion;
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

  final schemaVersionPattern = RegExp(r'^schema_version:\s*(\d+)\s*$');
  final listPattern = RegExp(
    r'^(verdict_values|success_verdicts|blocking_verdicts):\s*\[(.*)\]\s*$',
  );
  final sloStartPattern = RegExp(r'^  - id:\s*(.*)$');
  final sloKvPattern = RegExp(r'^    (\w+):\s?(.*)$');

  for (final raw in lines) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    if (raw.trim() == 'slos:') continue;

    final schemaMatch = schemaVersionPattern.firstMatch(raw);
    if (schemaMatch != null) {
      schemaVersion = int.parse(schemaMatch.group(1)!);
      continue;
    }

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
    schemaVersion: schemaVersion,
    verdictValues: verdictValues ?? const [],
    successVerdicts: successVerdicts ?? const [],
    blockingVerdicts: blockingVerdicts ?? const [],
    slos: slos,
  );
}
