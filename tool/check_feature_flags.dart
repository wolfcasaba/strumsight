import 'dart:io';

import 'package:strumsight/core/feature_flags/public.dart';

/// Audits the feature-flag catalog (ADR 0446) for three machine-checkable
/// facts:
///
/// 1. **Completeness (D4):** every `final bool <name>;` field measured out
///    of `lib/app/config/feature_flags.dart`'s SOURCE has a catalog entry in
///    [featureFlagRegistry], and vice versa. This is a source parse, not
///    reflection (D4) — there is no runtime field list to reflect over in
///    the Dart AOT/Flutter environment this app ships to. The source parse
///    recognises the plain, nullable, and initialized field forms alike
///    (`final bool x;`, `final bool? x;`, `final bool x = false;`).
/// 2. **Expiration (D6):** no catalog entry's [FeatureFlagDefinition.expiresOn]
///    lies strictly before the injected `now`. The boundary is inclusive —
///    a flag expiring exactly on `now` is still valid.
/// 3. **Metadata completeness (A1):** every catalog entry's `owner` and
///    `killSwitchPath` are non-empty (not just whitespace) — an entry that
///    exists but names no owner or no kill-switch path is as unusable in an
///    incident as a missing entry.
///
/// The logic here is intentionally NOT inside `main()`: [parseFeatureFlagFieldNames],
/// [isFeatureFlagExpired], [auditFeatureFlagRegistry] and [checkFeatureFlagsAtRoot]
/// all take content- or root-parameters so tests can feed hand-built fixture
/// input (a registry missing an entry, an expired flag) that the real
/// checked-in tree cannot produce (mirrors `tool/check_sdd_index.dart`,
/// ADR 0443's machine-checkable-contract pattern). `main()` is only a thin,
/// `exitCode`-setting wrapper around [checkFeatureFlagsAtRoot].

/// Matches a field declaration's `final bool` / `final bool?` prefix
/// followed by the field name, whether or not it carries an initializer
/// (`final bool <name>;`, `final bool? <name>;`, or
/// `final bool <name> = <expr>;`) — the name always ends up in group 1.
///
/// Anchored to (optional leading whitespace then) the start of a line, so a
/// mention of `final bool foo;` inside a doc comment (which starts with
/// `///`) or a commented-out line (`//`) never reaches the "final" token at
/// line-start and is correctly ignored, alongside getters (`bool get ...`,
/// no `final` prefix) and constructor parameters (`this.foo = false`, no
/// `final bool` prefix either).
final _fieldPattern = RegExp(
  r'^\s*final bool\??\s+(\w+)\s*(?:;|=)',
  multiLine: true,
);

/// Extracts every `FeatureFlags` field name out of the raw Dart source of
/// `lib/app/config/feature_flags.dart`.
Set<String> parseFeatureFlagFieldNames(String source) {
  return {
    for (final match in _fieldPattern.allMatches(source)) match.group(1)!,
  };
}

/// Whether a flag with [expiresOn] has lapsed as of [now]. The boundary is
/// inclusive (ADR 0446 D6): a flag is still valid ON its [expiresOn] date,
/// and only lapses the day after — so this compares calendar dates, not
/// exact instants, and uses `isAfter` (not `>=`) against [expiresOn].
bool isFeatureFlagExpired({
  required DateTime expiresOn,
  required DateTime now,
}) {
  final expiryDate = DateTime(expiresOn.year, expiresOn.month, expiresOn.day);
  final today = DateTime(now.year, now.month, now.day);
  return today.isAfter(expiryDate);
}

enum FeatureFlagAuditIssueCode {
  missingCatalogEntry,
  unknownCatalogEntry,
  duplicateCatalogEntry,
  expiredFlag,
  incompleteCatalogEntry,
}

final class FeatureFlagAuditIssue {
  const FeatureFlagAuditIssue(this.code, this.message);

  final FeatureFlagAuditIssueCode code;
  final String message;
}

final class FeatureFlagAuditReport {
  FeatureFlagAuditReport({required List<FeatureFlagAuditIssue> issues})
    : issues = List.unmodifiable(issues);

  final List<FeatureFlagAuditIssue> issues;

  bool get isClean => issues.isEmpty;

  String format() {
    if (isClean) return 'Feature flag audit OK (${issues.length} issue(s)).';
    final output = StringBuffer('Feature flag audit failed:');
    for (final issue in issues) {
      output.writeln();
      output.write('- [${issue.code.name}] ${issue.message}');
    }
    return output.toString();
  }
}

/// Cross-checks [registry] against the field names measured out of the real
/// source ([sourceFieldNames]), and every entry's expiration against
/// [now]. This is the pure, content-parameterized core (mirrors
/// `validateSddIndex` in `tool/check_sdd_index.dart`): every input is a
/// plain value, so tests can construct a registry with a missing entry, an
/// unknown extra entry, or an expired flag directly — none of which the
/// real, shipped registry produces (R5: the real catalog is green).
FeatureFlagAuditReport auditFeatureFlagRegistry({
  required Set<String> sourceFieldNames,
  required List<FeatureFlagDefinition> registry,
  required DateTime now,
}) {
  final issues = <FeatureFlagAuditIssue>[];

  final catalogKeys = <String>{};
  for (final definition in registry) {
    if (!catalogKeys.add(definition.key)) {
      issues.add(
        FeatureFlagAuditIssue(
          FeatureFlagAuditIssueCode.duplicateCatalogEntry,
          'catalog key "${definition.key}" appears more than once in the '
          'registry.',
        ),
      );
    }
  }

  for (final field in sourceFieldNames) {
    if (!catalogKeys.contains(field)) {
      issues.add(
        FeatureFlagAuditIssue(
          FeatureFlagAuditIssueCode.missingCatalogEntry,
          'FeatureFlags field "$field" (lib/app/config/feature_flags.dart) '
          'has no catalog entry in featureFlagRegistry.',
        ),
      );
    }
  }

  for (final key in catalogKeys) {
    if (!sourceFieldNames.contains(key)) {
      issues.add(
        FeatureFlagAuditIssue(
          FeatureFlagAuditIssueCode.unknownCatalogEntry,
          'catalog key "$key" has no matching FeatureFlags field in '
          'lib/app/config/feature_flags.dart.',
        ),
      );
    }
  }

  for (final definition in registry) {
    final expiresOn = definition.expiresOn;
    if (expiresOn != null &&
        isFeatureFlagExpired(expiresOn: expiresOn, now: now)) {
      issues.add(
        FeatureFlagAuditIssue(
          FeatureFlagAuditIssueCode.expiredFlag,
          'flag "${definition.key}" expired on '
          '${expiresOn.toIso8601String()} (now: ${now.toIso8601String()}).',
        ),
      );
    }
  }

  for (final definition in registry) {
    final missingFields = <String>[
      if (definition.owner.trim().isEmpty) 'owner',
      if (definition.killSwitchPath.trim().isEmpty) 'killSwitchPath',
    ];
    if (missingFields.isNotEmpty) {
      issues.add(
        FeatureFlagAuditIssue(
          FeatureFlagAuditIssueCode.incompleteCatalogEntry,
          'catalog entry "${definition.key}" has an empty or '
          'whitespace-only ${missingFields.join(' and ')} '
          '(A1 requires owner, risk, fail-closed default and '
          'kill-switch path).',
        ),
      );
    }
  }

  return FeatureFlagAuditReport(issues: issues);
}

/// Reads and audits the real `lib/app/config/feature_flags.dart` source
/// under [projectRoot] against [featureFlagRegistry].
FeatureFlagAuditReport checkFeatureFlagsAtRoot({
  required Directory projectRoot,
  required DateTime now,
}) {
  final sourceFile = File(
    '${projectRoot.absolute.path}/lib/app/config/feature_flags.dart',
  );
  final fieldNames = parseFeatureFlagFieldNames(sourceFile.readAsStringSync());
  return auditFeatureFlagRegistry(
    sourceFieldNames: fieldNames,
    registry: featureFlagRegistry,
    now: now,
  );
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/check_feature_flags.dart');
    exitCode = 64;
    return;
  }
  try {
    final report = checkFeatureFlagsAtRoot(
      projectRoot: Directory.current,
      now: DateTime.now(),
    );
    if (report.isClean) {
      stdout.writeln(report.format());
      return;
    }
    stderr.writeln(report.format());
    exitCode = 1;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Feature flag audit could not run: $error');
    stderr.writeln(stackTrace);
    exitCode = 2;
  }
}
