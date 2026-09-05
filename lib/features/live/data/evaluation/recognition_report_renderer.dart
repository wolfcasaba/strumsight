/// Single-source recognition dashboard report and its three renderings
/// (E14-R09, ADR 0511 D5).
///
/// [RecognitionDashboardReport] is the one intermediate model the JSON,
/// Markdown and HTML output all read from — every number is rounded exactly
/// once, while building this model, and every renderer only stringifies an
/// already-rounded value (never re-aggregates or re-rounds). The four
/// [GroupKey] breakdowns partition the manifest's cases and call the
/// public, unmodified `computeRecognitionMetrics` per partition (ADR 0511
/// R3) — this file adds no new metric computation. A case missing a group
/// key is folded into a distinct, named [unknownGroupValue] bucket rather
/// than silently dropped (ADR 0511 acceptance #8). This file is
/// `dart:io`-free: reading the manifest and threshold file off disk, and
/// evaluating the release gate, are the CLI's job
/// (`tool/recognition_report.dart`).
library;

import 'dart:collection';
import 'dart:convert';

import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_release_gate.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_split.dart'
    show GroupKey;

/// The bucket name for cases missing the group key being partitioned on —
/// never silently dropped, always counted under this name.
const String unknownGroupValue = '(unknown)';

/// Every displayed metric is rounded to this many decimal places exactly
/// once, while building [RecognitionDashboardReport] — the single rounding
/// point ADR 0511 D5 requires. `null` (metric unavailable) is left as
/// `null`, never coerced to a number.
double? _round(double? value) =>
    value == null ? null : double.parse(value.toStringAsFixed(4));

/// One named metric reading, already rounded (ADR 0511 D5). [name] matches
/// a key of [recognitionMetricExtractors] (without the gate's `overall.`
/// scope prefix), so the same metric identifier is used whether the value
/// came from the manifest-wide aggregate or one [RecognitionGroupBreakdown].
final class RecognitionMetricSummaryEntry {
  const RecognitionMetricSummaryEntry({
    required this.name,
    required this.value,
    required this.higherIsBetter,
  });

  final String name;
  final double? value;
  final bool higherIsBetter;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
    'higherIsBetter': higherIsBetter,
  };
}

/// Every metric [recognitionMetricExtractors] knows how to read, rounded
/// once and sorted by name (ADR 0511 D7).
List<RecognitionMetricSummaryEntry> _summarize(RecognitionMetrics metrics) {
  final names = recognitionMetricExtractors.keys.toList()..sort();
  return <RecognitionMetricSummaryEntry>[
    for (final name in names)
      RecognitionMetricSummaryEntry(
        name: name,
        value: _round(recognitionMetricExtractors[name]!(metrics).value),
        higherIsBetter: recognitionMetricExtractors[name]!(
          metrics,
        ).higherIsBetter,
      ),
  ];
}

/// A fixed, deterministic explanation of why `uncertainCorrect` is `null` —
/// no dynamic content, so two runs produce byte-identical text (ADR 0511
/// D4/D7).
const String _uncertainCorrectUnavailableReasonText =
    '"uncertainCorrect" (correctness among abstained/rejected detections) '
    'cannot be computed from computeRecognitionMetrics\'s public output: the '
    'per-event correctness set and the event matcher it depends on are '
    'private to recognition_metrics.dart (ADR 0511 D4). Reproducing the '
    'match here would create a second, potentially divergent matching '
    'implementation for the same measurement (docs/LESSONS.md L269).';

/// The three event categories a release decision needs beyond a single
/// accuracy percentage (ADR 0511 D4): [confidentWrong] and [rejected] are
/// exact, derived from the public `acceptedAccuracy`/`coverage` ratios;
/// [uncertainCorrect] is deliberately `null` with
/// [uncertainCorrectUnavailableReason] explaining why — never coerced to
/// `0`.
final class RecognitionEventCategories {
  const RecognitionEventCategories({
    required this.confidentWrong,
    required this.rejected,
    required this.uncertainCorrect,
    required this.uncertainCorrectUnavailableReason,
  });

  factory RecognitionEventCategories.fromMetrics(RecognitionMetrics metrics) =>
      RecognitionEventCategories(
        confidentWrong:
            metrics.acceptedAccuracy.denominator -
            metrics.acceptedAccuracy.numerator,
        rejected: metrics.coverage.denominator - metrics.coverage.numerator,
        uncertainCorrect: null,
        uncertainCorrectUnavailableReason:
            _uncertainCorrectUnavailableReasonText,
      );

  /// Accepted (surfaced) detections that are not correct — identical to
  /// `falseVisibleEventsPerMinute.eventCount`.
  final int confidentWrong;

  /// Detected but abstained (never surfaced) events — the gap between
  /// `coverage`'s and `acceptedAccuracy`'s denominators.
  final int rejected;

  /// Always `null` — see [uncertainCorrectUnavailableReason].
  final int? uncertainCorrect;
  final String uncertainCorrectUnavailableReason;

  Map<String, Object?> toJson() => <String, Object?>{
    'confidentWrong': confidentWrong,
    'rejected': rejected,
    'uncertainCorrect': uncertainCorrect,
    'uncertainCorrectUnavailableReason': uncertainCorrectUnavailableReason,
  };
}

/// One [GroupKey] value's metrics and event categories, computed by
/// partitioning the manifest's cases and calling the public
/// `computeRecognitionMetrics` on that partition alone (ADR 0511 R3). A
/// case missing this [groupKey] is counted under [unknownGroupValue], never
/// dropped.
final class RecognitionGroupBreakdown {
  const RecognitionGroupBreakdown({
    required this.groupKey,
    required this.groupValue,
    required this.caseCount,
    required this.metrics,
    required this.categories,
  });

  final GroupKey groupKey;
  final String groupValue;
  final int caseCount;
  final List<RecognitionMetricSummaryEntry> metrics;
  final RecognitionEventCategories categories;

  Map<String, Object?> toJson() => <String, Object?>{
    'groupKey': groupKey.name,
    'groupValue': groupValue,
    'caseCount': caseCount,
    'metrics': <Map<String, Object?>>[
      for (final entry in metrics) entry.toJson(),
    ],
    'categories': categories.toJson(),
  };
}

/// The single intermediate model the JSON, Markdown and HTML renderings all
/// read from (ADR 0511 D5). Building it is the only place metric values are
/// rounded and groups are partitioned; every renderer only formats what is
/// already here.
final class RecognitionDashboardReport {
  const RecognitionDashboardReport({
    required this.manifestSchemaVersion,
    required this.caseCount,
    required this.overallMetrics,
    required this.overallCategories,
    required this.groups,
    required this.gate,
  });

  /// Builds the report: [overall] is the manifest-wide
  /// `computeRecognitionMetrics` result (already computed by the caller —
  /// this file never recomputes it), [cases] is the same manifest's full
  /// case list (used only for the group partition), and [gate] is the
  /// already-evaluated release-gate verdict for [overall].
  factory RecognitionDashboardReport.build({
    required String manifestSchemaVersion,
    required RecognitionMetrics overall,
    required List<RecognitionCase> cases,
    required RecognitionGateVerdict gate,
  }) {
    final groups =
        <RecognitionGroupBreakdown>[
          for (final groupKey in GroupKey.values)
            ..._breakdownsFor(groupKey, cases),
        ]..sort((a, b) {
          final byKey = a.groupKey.name.compareTo(b.groupKey.name);
          return byKey != 0 ? byKey : a.groupValue.compareTo(b.groupValue);
        });
    return RecognitionDashboardReport(
      manifestSchemaVersion: manifestSchemaVersion,
      caseCount: cases.length,
      overallMetrics: _summarize(overall),
      overallCategories: RecognitionEventCategories.fromMetrics(overall),
      groups: groups,
      gate: gate,
    );
  }

  final String manifestSchemaVersion;
  final int caseCount;
  final List<RecognitionMetricSummaryEntry> overallMetrics;
  final RecognitionEventCategories overallCategories;

  /// Sorted by group-key name, then group value (ADR 0511 D7 / acceptance
  /// #8) — never in set/map iteration order.
  final List<RecognitionGroupBreakdown> groups;
  final RecognitionGateVerdict gate;

  Map<String, Object?> toJson() => <String, Object?>{
    'manifestSchemaVersion': manifestSchemaVersion,
    'caseCount': caseCount,
    'gate': gate.toJson(),
    'overall': <String, Object?>{
      'metrics': <Map<String, Object?>>[
        for (final entry in overallMetrics) entry.toJson(),
      ],
      'categories': overallCategories.toJson(),
    },
    'groups': <Map<String, Object?>>[
      for (final group in groups) group.toJson(),
    ],
  };

  /// A stable, timestamp-free JSON rendering: the same report always
  /// produces byte-identical output (ADR 0511 D7).
  String toDeterministicJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

List<RecognitionGroupBreakdown> _breakdownsFor(
  GroupKey groupKey,
  List<RecognitionCase> cases,
) {
  final buckets = SplayTreeMap<String, List<RecognitionCase>>();
  for (final recognitionCase in cases) {
    final raw = switch (groupKey) {
      GroupKey.player => recognitionCase.player,
      GroupKey.device => recognitionCase.device,
      GroupKey.guitar => recognitionCase.guitar,
      GroupKey.room => recognitionCase.room,
    };
    final value = (raw == null || raw.trim().isEmpty) ? unknownGroupValue : raw;
    buckets.putIfAbsent(value, () => <RecognitionCase>[]).add(recognitionCase);
  }
  return <RecognitionGroupBreakdown>[
    for (final entry in buckets.entries)
      () {
        final groupMetrics = computeRecognitionMetrics(entry.value);
        return RecognitionGroupBreakdown(
          groupKey: groupKey,
          groupValue: entry.key,
          caseCount: entry.value.length,
          metrics: _summarize(groupMetrics),
          categories: RecognitionEventCategories.fromMetrics(groupMetrics),
        );
      }(),
  ];
}

String _fmt(double? value) => value == null ? 'n/a' : value.toStringAsFixed(4);

String _mdCell(String value) =>
    value.replaceAll('\\', r'\\').replaceAll('|', r'\|').replaceAll('\n', ' ');

String _htmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Renders a [RecognitionDashboardReport] as JSON, Markdown or HTML — all
/// three read the same already-computed, already-rounded fields, never
/// re-aggregating or re-rounding a number (ADR 0511 D5).
final class RecognitionReportRenderer {
  const RecognitionReportRenderer();

  String renderJson(RecognitionDashboardReport report) =>
      report.toDeterministicJson();

  String renderMarkdown(RecognitionDashboardReport report) {
    final buffer = StringBuffer();
    buffer.writeln('# Recognition dashboard report');
    buffer.writeln();
    buffer.writeln(
      '- Manifest schema version: ${report.manifestSchemaVersion}',
    );
    buffer.writeln('- Case count: ${report.caseCount}');
    buffer.writeln('- Gate schema version: ${report.gate.schemaVersion}');
    buffer.writeln(
      '- Gate thresholds version: ${report.gate.thresholdsVersion}',
    );
    buffer.writeln('- Gate verdict: ${report.gate.passed ? 'PASS' : 'FAIL'}');
    buffer.writeln();

    buffer.writeln('## Release gate');
    buffer.writeln();
    buffer.writeln(
      '| Metric | Threshold | Higher is better | Value | Verdict | '
      'Thresholds version |',
    );
    buffer.writeln('|---|---:|---|---:|---|---|');
    for (final finding in report.gate.findings) {
      buffer.writeln(
        '| ${_mdCell(finding.metricPath)} | ${finding.threshold} | '
        '${finding.higherIsBetter} | ${_fmt(finding.value)} | '
        '${finding.passed ? 'PASS' : 'FAIL'} | '
        '${_mdCell(finding.thresholdsVersion)} |',
      );
    }
    buffer.writeln();

    buffer.writeln('## Overall metrics');
    buffer.writeln();
    _writeMetricsTable(buffer, report.overallMetrics);
    buffer.writeln();

    buffer.writeln('## Event categories');
    buffer.writeln();
    buffer.writeln(
      '| Scope | Confident wrong | Rejected | Uncertain correct | '
      'Uncertain correct reason |',
    );
    buffer.writeln('|---|---:|---:|---:|---|');
    _writeCategoriesRow(buffer, 'overall', report.overallCategories);
    for (final group in report.groups) {
      _writeCategoriesRow(
        buffer,
        '${group.groupKey.name}=${group.groupValue}',
        group.categories,
      );
    }
    buffer.writeln();

    buffer.writeln('## Groups');
    buffer.writeln();
    buffer.writeln('| Group key | Group value | Case count | Metric | Value |');
    buffer.writeln('|---|---|---:|---|---:|');
    for (final group in report.groups) {
      for (final entry in group.metrics) {
        buffer.writeln(
          '| ${_mdCell(group.groupKey.name)} | ${_mdCell(group.groupValue)} | '
          '${group.caseCount} | ${_mdCell(entry.name)} | ${_fmt(entry.value)} |',
        );
      }
    }
    return buffer.toString();
  }

  void _writeMetricsTable(
    StringBuffer buffer,
    List<RecognitionMetricSummaryEntry> metrics,
  ) {
    buffer.writeln('| Metric | Value |');
    buffer.writeln('|---|---:|');
    for (final entry in metrics) {
      buffer.writeln('| ${_mdCell(entry.name)} | ${_fmt(entry.value)} |');
    }
  }

  void _writeCategoriesRow(
    StringBuffer buffer,
    String scope,
    RecognitionEventCategories categories,
  ) {
    buffer.writeln(
      '| ${_mdCell(scope)} | ${categories.confidentWrong} | '
      '${categories.rejected} | '
      '${categories.uncertainCorrect?.toString() ?? 'n/a'} | '
      '${_mdCell(categories.uncertainCorrectUnavailableReason)} |',
    );
  }

  String renderHtml(RecognitionDashboardReport report) {
    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="en">');
    buffer.writeln('<head><meta charset="utf-8">');
    buffer.writeln('<title>Recognition dashboard report</title></head>');
    buffer.writeln('<body>');
    buffer.writeln('<h1>Recognition dashboard report</h1>');
    buffer.writeln('<ul>');
    buffer.writeln(
      '<li>Manifest schema version: '
      '${_htmlEscape(report.manifestSchemaVersion)}</li>',
    );
    buffer.writeln('<li>Case count: ${report.caseCount}</li>');
    buffer.writeln(
      '<li>Gate schema version: '
      '${_htmlEscape(report.gate.schemaVersion)}</li>',
    );
    buffer.writeln(
      '<li>Gate thresholds version: '
      '${_htmlEscape(report.gate.thresholdsVersion)}</li>',
    );
    buffer.writeln(
      '<li>Gate verdict: ${report.gate.passed ? 'PASS' : 'FAIL'}</li>',
    );
    buffer.writeln('</ul>');

    buffer.writeln('<h2>Release gate</h2>');
    buffer.writeln('<table>');
    buffer.writeln(
      '<tr><th>Metric</th><th>Threshold</th><th>Higher is better</th>'
      '<th>Value</th><th>Verdict</th><th>Thresholds version</th></tr>',
    );
    for (final finding in report.gate.findings) {
      buffer.writeln(
        '<tr><td>${_htmlEscape(finding.metricPath)}</td>'
        '<td>${finding.threshold}</td>'
        '<td>${finding.higherIsBetter}</td>'
        '<td>${_fmt(finding.value)}</td>'
        '<td>${finding.passed ? 'PASS' : 'FAIL'}</td>'
        '<td>${_htmlEscape(finding.thresholdsVersion)}</td></tr>',
      );
    }
    buffer.writeln('</table>');

    buffer.writeln('<h2>Overall metrics</h2>');
    _writeHtmlMetricsTable(buffer, report.overallMetrics);

    buffer.writeln('<h2>Event categories</h2>');
    buffer.writeln('<table>');
    buffer.writeln(
      '<tr><th>Scope</th><th>Confident wrong</th><th>Rejected</th>'
      '<th>Uncertain correct</th><th>Uncertain correct reason</th></tr>',
    );
    _writeHtmlCategoriesRow(buffer, 'overall', report.overallCategories);
    for (final group in report.groups) {
      _writeHtmlCategoriesRow(
        buffer,
        '${group.groupKey.name}=${group.groupValue}',
        group.categories,
      );
    }
    buffer.writeln('</table>');

    buffer.writeln('<h2>Groups</h2>');
    buffer.writeln('<table>');
    buffer.writeln(
      '<tr><th>Group key</th><th>Group value</th><th>Case count</th>'
      '<th>Metric</th><th>Value</th></tr>',
    );
    for (final group in report.groups) {
      for (final entry in group.metrics) {
        buffer.writeln(
          '<tr><td>${_htmlEscape(group.groupKey.name)}</td>'
          '<td>${_htmlEscape(group.groupValue)}</td>'
          '<td>${group.caseCount}</td>'
          '<td>${_htmlEscape(entry.name)}</td>'
          '<td>${_fmt(entry.value)}</td></tr>',
        );
      }
    }
    buffer.writeln('</table>');

    buffer.writeln('</body>');
    buffer.writeln('</html>');
    return buffer.toString();
  }

  void _writeHtmlMetricsTable(
    StringBuffer buffer,
    List<RecognitionMetricSummaryEntry> metrics,
  ) {
    buffer.writeln('<table>');
    buffer.writeln('<tr><th>Metric</th><th>Value</th></tr>');
    for (final entry in metrics) {
      buffer.writeln(
        '<tr><td>${_htmlEscape(entry.name)}</td>'
        '<td>${_fmt(entry.value)}</td></tr>',
      );
    }
    buffer.writeln('</table>');
  }

  void _writeHtmlCategoriesRow(
    StringBuffer buffer,
    String scope,
    RecognitionEventCategories categories,
  ) {
    buffer.writeln(
      '<tr><td>${_htmlEscape(scope)}</td>'
      '<td>${categories.confidentWrong}</td>'
      '<td>${categories.rejected}</td>'
      '<td>${categories.uncertainCorrect?.toString() ?? 'n/a'}</td>'
      '<td>${_htmlEscape(categories.uncertainCorrectUnavailableReason)}</td>'
      '</tr>',
    );
  }
}
