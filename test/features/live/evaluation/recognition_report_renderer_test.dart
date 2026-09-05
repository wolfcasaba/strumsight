import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/data/evaluation/recognition_report_renderer.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_release_gate.dart';

void main() {
  const gate = RecognitionReleaseGate();
  const renderer = RecognitionReportRenderer();

  RecognitionDashboardReport buildReport() {
    final cases = _fixtureCases();
    final overall = computeRecognitionMetrics(cases);
    final thresholds = gate.parseThresholds({
      'schemaVersion': '1',
      'thresholdsVersion': 'renderer-test-v1',
      'thresholds': [
        {'metricPath': 'overall.acceptedAccuracy.value', 'threshold': 0.9},
        {'metricPath': 'overall.coverage.value', 'threshold': 0.9},
      ],
    });
    final verdict = gate.evaluate(overall, thresholds);
    return RecognitionDashboardReport.build(
      manifestSchemaVersion: '1.0',
      overall: overall,
      cases: cases,
      gate: verdict,
    );
  }

  group('single source, three formats (ADR 0511 D5)', () {
    test(
      'the JSON, Markdown and HTML renderings agree on an overall metric',
      () {
        final report = buildReport();
        final json = renderer.renderJson(report);
        final markdown = renderer.renderMarkdown(report);
        final html = renderer.renderHtml(report);

        final expectedValue = report.overallMetrics
            .firstWhere((entry) => entry.name == 'acceptedAccuracy.value')
            .value!;

        expect(
          _jsonOverallMetric(json, 'acceptedAccuracy.value'),
          expectedValue,
        );
        expect(
          _mdTableCell(
            markdown,
            heading: 'Overall metrics',
            matchColumns: {'Metric': 'acceptedAccuracy.value'},
            readColumn: 'Value',
          ),
          expectedValue.toStringAsFixed(4),
        );
        expect(
          _htmlTableCell(
            html,
            heading: 'Overall metrics',
            matchColumns: {'Metric': 'acceptedAccuracy.value'},
            readColumn: 'Value',
          ),
          expectedValue.toStringAsFixed(4),
        );
      },
    );

    test('the JSON, Markdown and HTML renderings agree on a group metric', () {
      final report = buildReport();
      final json = renderer.renderJson(report);
      final markdown = renderer.renderMarkdown(report);
      final html = renderer.renderHtml(report);

      final playerAGroup = report.groups.firstWhere(
        (g) => g.groupKey.name == 'player' && g.groupValue == 'player-a',
      );
      final expectedValue = playerAGroup.metrics
          .firstWhere((entry) => entry.name == 'coverage.value')
          .value!;

      expect(
        _jsonGroupMetric(json, 'player', 'player-a', 'coverage.value'),
        expectedValue,
      );
      expect(
        _mdTableCell(
          markdown,
          heading: 'Groups',
          matchColumns: {
            'Group key': 'player',
            'Group value': 'player-a',
            'Metric': 'coverage.value',
          },
          readColumn: 'Value',
        ),
        expectedValue.toStringAsFixed(4),
      );
      expect(
        _htmlTableCell(
          html,
          heading: 'Groups',
          matchColumns: {
            'Group key': 'player',
            'Group value': 'player-a',
            'Metric': 'coverage.value',
          },
          readColumn: 'Value',
        ),
        expectedValue.toStringAsFixed(4),
      );
    });

    test('every format names the gate thresholds version', () {
      final report = buildReport();
      final json = renderer.renderJson(report);
      final markdown = renderer.renderMarkdown(report);
      final html = renderer.renderHtml(report);

      expect(json, contains('"thresholdsVersion": "renderer-test-v1"'));
      expect(markdown, contains('renderer-test-v1'));
      expect(html, contains('renderer-test-v1'));
      // Named on every finding row, not only once in a summary line.
      expect(
        report.gate.findings.every(
          (f) => f.thresholdsVersion == 'renderer-test-v1',
        ),
        isTrue,
      );
    });
  });

  group('scoped false-visible-event metrics render identically across formats '
      '(acceptance 7, ADR 0521 D5)', () {
    test('falseVisibleDirectionEventsPerMinute.value and '
        'falseVisibleChordEventsPerMinute.value agree across JSON, '
        'Markdown and HTML', () {
      final report = buildReport();
      final json = renderer.renderJson(report);
      final markdown = renderer.renderMarkdown(report);
      final html = renderer.renderHtml(report);

      for (final metricName in [
        'falseVisibleDirectionEventsPerMinute.value',
        'falseVisibleChordEventsPerMinute.value',
      ]) {
        final expectedValue = report.overallMetrics
            .firstWhere((entry) => entry.name == metricName)
            .value!;

        expect(_jsonOverallMetric(json, metricName), expectedValue);
        expect(
          _mdTableCell(
            markdown,
            heading: 'Overall metrics',
            matchColumns: {'Metric': metricName},
            readColumn: 'Value',
          ),
          expectedValue.toStringAsFixed(4),
        );
        expect(
          _htmlTableCell(
            html,
            heading: 'Overall metrics',
            matchColumns: {'Metric': metricName},
            readColumn: 'Value',
          ),
          expectedValue.toStringAsFixed(4),
        );
      }
    });
  });

  group('determinism (ADR 0511 D7)', () {
    test('two independent builds of the same manifest render byte-identical '
        'JSON, Markdown and HTML', () {
      final reportOne = buildReport();
      final reportTwo = buildReport();

      expect(renderer.renderJson(reportOne), renderer.renderJson(reportTwo));
      expect(
        renderer.renderMarkdown(reportOne),
        renderer.renderMarkdown(reportTwo),
      );
      expect(renderer.renderHtml(reportOne), renderer.renderHtml(reportTwo));
    });

    test('output carries no timestamp-shaped or absolute-path text', () {
      final report = buildReport();
      final json = renderer.renderJson(report);
      final markdown = renderer.renderMarkdown(report);
      final html = renderer.renderHtml(report);

      for (final output in [json, markdown, html]) {
        expect(output, isNot(contains('/home/')));
        expect(
          output,
          isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}'))),
        );
      }
    });

    test('groups are sorted by group-key name then group value, not '
        'iteration order', () {
      final report = buildReport();
      final keys = report.groups.map((g) => g.groupKey.name).toList();
      expect(keys, [...keys]..sort());
      for (final groupKey in {'device', 'guitar', 'player', 'room'}) {
        final values = report.groups
            .where((g) => g.groupKey.name == groupKey)
            .map((g) => g.groupValue)
            .toList();
        expect(values, [...values]..sort());
      }
    });
  });

  group('unknown group naming (ADR 0511 acceptance #8)', () {
    test('a case missing its device group key is counted, not dropped', () {
      final report = buildReport();
      final deviceGroups = report.groups.where(
        (g) => g.groupKey.name == 'device',
      );
      final unknown = deviceGroups.firstWhere(
        (g) => g.groupValue == unknownGroupValue,
      );
      expect(unknown.caseCount, 1);
    });

    test('a case missing its room group key is counted, not dropped', () {
      final report = buildReport();
      final roomGroups = report.groups.where((g) => g.groupKey.name == 'room');
      final unknown = roomGroups.firstWhere(
        (g) => g.groupValue == unknownGroupValue,
      );
      expect(unknown.caseCount, 1);
    });

    test('axes with no missing keys have no unknown bucket', () {
      final report = buildReport();
      final playerGroups = report.groups.where(
        (g) => g.groupKey.name == 'player',
      );
      expect(
        playerGroups.where((g) => g.groupValue == unknownGroupValue),
        isEmpty,
      );
    });
  });

  group('event categories (ADR 0511 D4)', () {
    test(
      'confidentWrong and rejected match the exact public-field formula',
      () {
        final cases = _fixtureCases();
        final raw = computeRecognitionMetrics(cases);
        final report = buildReport();

        expect(
          report.overallCategories.confidentWrong,
          raw.acceptedAccuracy.denominator - raw.acceptedAccuracy.numerator,
        );
        expect(
          report.overallCategories.rejected,
          raw.coverage.denominator - raw.coverage.numerator,
        );
      },
    );

    test('uncertainCorrect is null with a non-empty reason, never 0', () {
      final report = buildReport();
      expect(report.overallCategories.uncertainCorrect, isNull);
      expect(
        report.overallCategories.uncertainCorrectUnavailableReason,
        isNotEmpty,
      );
    });

    test('rejected does not leak into confidentWrong / the false-visible '
        'event count', () {
      final cases = _fixtureCases();
      final raw = computeRecognitionMetrics(cases);
      final report = buildReport();

      expect(report.overallCategories.rejected, greaterThan(0));
      expect(
        raw.falseVisibleEventsPerMinute.eventCount,
        report.overallCategories.confidentWrong,
      );
      expect(
        raw.coverage.denominator,
        raw.acceptedAccuracy.denominator + report.overallCategories.rejected,
      );
    });
  });
}

// --- Fixture manifest ----------------------------------------------------

List<RecognitionCase> _fixtureCases() => [
  RecognitionCase(
    caseId: 'case-a',
    player: 'player-a',
    device: 'phone-1',
    guitar: 'guitar-1',
    room: 'room-1',
    durationMs: 60000,
    expectedEvents: [
      RecognitionExpectedEvent(timeMs: 1000, kind: RecognitionEventKind.onset),
      RecognitionExpectedEvent(
        timeMs: 2000,
        kind: RecognitionEventKind.strum,
        direction: StrumDirection.down,
      ),
      RecognitionExpectedEvent(
        timeMs: 3000,
        kind: RecognitionEventKind.chord,
        chordLabel: 'C',
      ),
    ],
    detectedEvents: [
      RecognitionDetectedEvent(
        timeMs: 1020,
        kind: RecognitionEventKind.onset,
        accepted: true,
        confidence: 0.9,
      ),
      RecognitionDetectedEvent(
        timeMs: 2030,
        kind: RecognitionEventKind.strum,
        accepted: true,
        confidence: 0.8,
        direction: StrumDirection.down,
      ),
      RecognitionDetectedEvent(
        timeMs: 3040,
        kind: RecognitionEventKind.chord,
        accepted: true,
        confidence: 0.7,
        chordLabel: 'C',
      ),
      // Unmatched, accepted — a confident-wrong detection.
      RecognitionDetectedEvent(
        timeMs: 5000,
        kind: RecognitionEventKind.onset,
        accepted: true,
        confidence: 0.4,
      ),
      // Detected but abstained — a rejected detection.
      RecognitionDetectedEvent(
        timeMs: 8000,
        kind: RecognitionEventKind.onset,
        accepted: false,
        confidence: 0.2,
      ),
    ],
    detectionLatenciesMs: [30, 45],
  ),
  RecognitionCase(
    caseId: 'case-b',
    player: 'player-b',
    device: 'phone-2',
    guitar: 'guitar-2',
    room: null,
    durationMs: 30000,
    expectedEvents: [
      RecognitionExpectedEvent(
        timeMs: 500,
        kind: RecognitionEventKind.strum,
        direction: StrumDirection.up,
      ),
      RecognitionExpectedEvent(
        timeMs: 4000,
        kind: RecognitionEventKind.chord,
        chordLabel: 'noChord',
      ),
    ],
    detectedEvents: [
      RecognitionDetectedEvent(
        timeMs: 520,
        kind: RecognitionEventKind.strum,
        accepted: true,
        confidence: 0.6,
        direction: StrumDirection.up,
      ),
      // Detected but abstained — another rejected detection.
      RecognitionDetectedEvent(
        timeMs: 4900,
        kind: RecognitionEventKind.chord,
        accepted: false,
        confidence: 0.2,
        chordLabel: 'unknown',
      ),
    ],
    detectionLatenciesMs: [20],
  ),
  RecognitionCase(
    caseId: 'case-c',
    player: 'player-a',
    device: null,
    guitar: 'guitar-3',
    room: 'room-2',
    durationMs: 15000,
    expectedEvents: [
      RecognitionExpectedEvent(timeMs: 800, kind: RecognitionEventKind.onset),
    ],
    detectedEvents: [
      RecognitionDetectedEvent(
        timeMs: 820,
        kind: RecognitionEventKind.onset,
        accepted: true,
        confidence: 0.7,
      ),
    ],
    detectionLatenciesMs: [20],
  ),
];

// --- JSON lookups ----------------------------------------------------------

double _jsonOverallMetric(String json, String metricName) {
  final decoded = jsonDecodeMap(json);
  final metrics = (decoded['overall'] as Map)['metrics'] as List;
  final entry = metrics.cast<Map>().firstWhere((m) => m['name'] == metricName);
  return (entry['value'] as num).toDouble();
}

double _jsonGroupMetric(
  String json,
  String groupKey,
  String groupValue,
  String metricName,
) {
  final decoded = jsonDecodeMap(json);
  final groups = decoded['groups'] as List;
  final group = groups.cast<Map>().firstWhere(
    (g) => g['groupKey'] == groupKey && g['groupValue'] == groupValue,
  );
  final metrics = group['metrics'] as List;
  final entry = metrics.cast<Map>().firstWhere((m) => m['name'] == metricName);
  return (entry['value'] as num).toDouble();
}

// --- Markdown table parsing (header-based, not positional — L526) ---------

String _mdTableCell(
  String markdown, {
  required String heading,
  required Map<String, String> matchColumns,
  required String readColumn,
}) {
  final rows = _mdTableRows(markdown, heading);
  final header = rows.first;
  final columnIndex = <String, int>{
    for (var i = 0; i < header.length; i++) header[i]: i,
  };
  for (final row in rows.skip(1)) {
    final matches = matchColumns.entries.every(
      (entry) => row[columnIndex[entry.key]!] == entry.value,
    );
    if (matches) {
      return row[columnIndex[readColumn]!];
    }
  }
  throw StateError('no row in "$heading" matched $matchColumns');
}

List<List<String>> _mdTableRows(String markdown, String heading) {
  final lines = markdown.split('\n');
  final headingIndex = lines.indexWhere((l) => l.trim() == '## $heading');
  if (headingIndex == -1) {
    throw StateError('heading "$heading" not found');
  }
  final rows = <List<String>>[];
  for (var i = headingIndex + 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('## ')) break;
    if (!line.startsWith('|')) continue;
    if (RegExp(r'^\|[\s:|-]+\|$').hasMatch(line)) continue; // separator row
    final inner = line.substring(1, line.length - 1);
    rows.add(inner.split('|').map((c) => c.trim()).toList());
  }
  return rows;
}

// --- HTML table parsing (header-based, not positional) ---------------------

String _htmlTableCell(
  String html, {
  required String heading,
  required Map<String, String> matchColumns,
  required String readColumn,
}) {
  final rows = _htmlTableRows(html, heading);
  final header = rows.first;
  final columnIndex = <String, int>{
    for (var i = 0; i < header.length; i++) header[i]: i,
  };
  for (final row in rows.skip(1)) {
    final matches = matchColumns.entries.every(
      (entry) => row[columnIndex[entry.key]!] == entry.value,
    );
    if (matches) {
      return row[columnIndex[readColumn]!];
    }
  }
  throw StateError('no row in "$heading" matched $matchColumns');
}

List<List<String>> _htmlTableRows(String html, String heading) {
  final headingTag = '<h2>$heading</h2>';
  final headingIndex = html.indexOf(headingTag);
  if (headingIndex == -1) {
    throw StateError('heading "$heading" not found');
  }
  final tableStart = html.indexOf('<table>', headingIndex);
  final tableEnd = html.indexOf('</table>', tableStart);
  final tableHtml = html.substring(tableStart, tableEnd);
  final rowMatches = RegExp(
    '<tr>(.*?)</tr>',
    dotAll: true,
  ).allMatches(tableHtml);
  final cellPattern = RegExp('<t[dh]>(.*?)</t[dh]>', dotAll: true);
  return [
    for (final rowMatch in rowMatches)
      [
        for (final cell in cellPattern.allMatches(rowMatch.group(1)!))
          cell.group(1)!,
      ],
  ];
}

Map<String, Object?> jsonDecodeMap(String source) =>
    jsonDecode(source) as Map<String, Object?>;
