// Repository delivery-workflow policy guard (E12-R03, ADR 0444).
//
// This is the CI gate for the round's five issue templates, the
// `.github/CODEOWNERS` notify-only ownership file and the extended
// `.github/pull_request_template.md`. There is deliberately no separate
// `tool/*.dart` library for this guard's logic (unlike the
// `tool/ci/check_secrets.dart` / `test/tooling/check_secrets_test.dart`
// pattern this round follows in spirit) — the round's allowed-files list
// only grants this test file on the Dart side, so [parseIssueForm] and the
// check functions below live here as top-level, content-parameterized
// functions (ADR 0444 D6) that both fixture-driven tests and the
// real-file tests call.
//
// Three measured lessons shape this file:
//   - L110: the guard is boxed-green/CI-red if it shells out to `rg`,
//     `python3` or `gh` — this file uses pure `dart:io` file reads only
//     (see the "A8" group at the end, which also guards itself).
//   - L260: a "does the file CONTAIN this keyword" check is blind to a
//     missing *required* field — every acceptance cell below is backed by
//     a fixture that the check must turn red, not just a real-file read.
//   - L476: a line-based guard can be structurally blind to a shape the
//     real world produces — the round's §10 handoff additionally documents
//     a manual real-file mutation probe (remove `bug.yml`'s rollback
//     field, rerun the gate, restore it) that this automated suite cannot
//     substitute for.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Restricted GitHub Issue Forms YAML subset (ADR 0444 D3)
// ---------------------------------------------------------------------------

/// One `body:` element of a restricted-subset issue form.
final class IssueFormField {
  const IssueFormField({
    required this.type,
    this.id,
    this.label,
    required this.required,
    this.options = const [],
  });

  final String type;
  final String? id;
  final String? label;
  final bool required;
  final List<String> options;
}

/// A parsed `.github/ISSUE_TEMPLATE/*.yml` document.
final class IssueForm {
  const IssueForm({
    this.name,
    this.description,
    this.title,
    this.labels = const [],
    this.fields = const [],
  });

  final String? name;
  final String? description;
  final String? title;
  final List<String> labels;
  final List<IssueFormField> fields;
}

bool _isBlankOrComment(String line) {
  final trimmed = line.trim();
  return trimmed.isEmpty || trimmed.startsWith('#');
}

String _unquote(String raw) {
  final trimmed = raw.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

final _topLevelKeyLine = RegExp(r'^([a-zA-Z_]+):(.*)$');
final _twoSpaceListItem = RegExp(r'^ {2}- (.*)$');
final _bodyElementHeader = RegExp(r'^ {2}- type: (\S+)$');
final _fourSpaceKeyLine = RegExp(r'^ {4}([a-zA-Z_]+):(.*)$');
final _sixSpaceKeyLine = RegExp(r'^ {6}([a-zA-Z_]+):(.*)$');
final _eightSpaceListItem = RegExp(r'^ {8}- (.*)$');
final _checkboxOptionLabel = RegExp(r'^label:\s*(.*)$');

/// Parses the deliberately RESTRICTED GitHub Issue Forms YAML subset used by
/// this repository's `.github/ISSUE_TEMPLATE/*.yml` files.
///
/// `package:yaml` is only a transitive dependency here (`pubspec.lock:1262`,
/// not declared in `pubspec.yaml`) — importing it would turn
/// `flutter analyze` red via the `depend_on_referenced_packages` lint (ADR
/// 0444 D3, the same measurement as ADR 0443 D3). This repository therefore
/// restricts issue-form YAML to a subset a small, indentation-exact,
/// line-based parser can read without ambiguity:
///
///  - top-level scalar keys `name:`, `description:`, `title:` (column 0,
///    single-line value, optionally double-quoted);
///  - `labels:` (empty value) followed by a 2-space-indented `- <value>`
///    list;
///  - `body:` (empty value) followed by a 2-space-indented list of
///    elements, each starting with `  - type: <kind>`;
///  - inside an element (exactly 4-space indent): `id:`, `attributes:`,
///    `validations:`;
///  - inside `attributes:` (exactly 6-space indent): `label:`,
///    `description:`, `placeholder:`, `value:`, and `options:` (empty
///    value, followed by an 8-space-indented list — each item either
///    `label: <value>` for a `checkboxes` option, or a plain scalar for a
///    `dropdown` option);
///  - inside `validations:` (exactly 6-space indent): `required:
///    true|false`.
///
/// A container key (`labels:`, `body:`, `attributes:`, `validations:`,
/// `options:`) written with an inline value on the same line — the shape a
/// YAML flow mapping/list would take, e.g. `attributes: {label: "x"}` — is
/// rejected with a `FormatException` naming the exact line, not silently
/// misread: the restricted subset has no flow-collection support at all.
/// Any line at the wrong indentation, or any unsupported key, fails the
/// same way. A file needing one of these forms is not a parser gap to route
/// around — it needs rewriting into the subset this repository's CI gate
/// can read.
IssueForm parseIssueForm(String contents, {required String sourceLabel}) {
  final lines = contents.split('\n');
  var i = 0;
  String? name;
  String? description;
  String? title;
  final labels = <String>[];
  final fields = <IssueFormField>[];

  while (i < lines.length) {
    if (_isBlankOrComment(lines[i])) {
      i++;
      continue;
    }
    final match = _topLevelKeyLine.firstMatch(lines[i]);
    if (match == null) {
      throw FormatException(
        '$sourceLabel:${i + 1}: expected a top-level "key:" line in the '
        'restricted issue-form YAML subset (see parseIssueForm doc '
        'comment), got: "${lines[i]}"',
      );
    }
    final key = match.group(1)!;
    final rest = match.group(2)!.trim();
    final lineNumber = i + 1;
    i++;
    switch (key) {
      case 'name':
        name = _unquote(rest);
      case 'description':
        description = _unquote(rest);
      case 'title':
        title = _unquote(rest);
      case 'labels':
        if (rest.isNotEmpty) {
          throw FormatException(
            '$sourceLabel:$lineNumber: "labels:" must start a block list '
            '(one "- <value>" per line), not an inline value: "$rest"',
          );
        }
        while (i < lines.length && _twoSpaceListItem.hasMatch(lines[i])) {
          labels.add(
            _unquote(_twoSpaceListItem.firstMatch(lines[i])!.group(1)!),
          );
          i++;
        }
      case 'body':
        if (rest.isNotEmpty) {
          throw FormatException(
            '$sourceLabel:$lineNumber: "body:" must start a block list, '
            'not an inline value: "$rest"',
          );
        }
        i = _parseBodyElements(lines, i, sourceLabel, fields);
      default:
        throw FormatException(
          '$sourceLabel:$lineNumber: unsupported top-level key "$key" — '
          'the restricted subset only supports '
          'name/description/title/labels/body',
        );
    }
  }

  return IssueForm(
    name: name,
    description: description,
    title: title,
    labels: labels,
    fields: fields,
  );
}

int _parseBodyElements(
  List<String> lines,
  int start,
  String sourceLabel,
  List<IssueFormField> fields,
) {
  var i = start;
  while (i < lines.length) {
    if (_isBlankOrComment(lines[i])) {
      i++;
      continue;
    }
    if (!lines[i].startsWith(' ')) break; // back to a top-level key

    final header = _bodyElementHeader.firstMatch(lines[i]);
    if (header == null) {
      throw FormatException(
        '$sourceLabel:${i + 1}: expected a body element '
        '"  - type: <kind>", got: "${lines[i]}"',
      );
    }
    final type = header.group(1)!;
    i++;

    String? id;
    String? label;
    var required = false;
    final options = <String>[];

    while (i < lines.length && _fourSpaceKeyLine.hasMatch(lines[i])) {
      final match = _fourSpaceKeyLine.firstMatch(lines[i])!;
      final key = match.group(1)!;
      final rest = match.group(2)!.trim();
      final lineNumber = i + 1;
      i++;
      if (key == 'id') {
        id = _unquote(rest);
      } else if (key == 'attributes') {
        if (rest.isNotEmpty) {
          throw FormatException(
            '$sourceLabel:$lineNumber: "attributes:" must start a block '
            'mapping, not an inline value: "$rest"',
          );
        }
        while (i < lines.length && _sixSpaceKeyLine.hasMatch(lines[i])) {
          final attrMatch = _sixSpaceKeyLine.firstMatch(lines[i])!;
          final attrKey = attrMatch.group(1)!;
          final attrRest = attrMatch.group(2)!.trim();
          final attrLineNumber = i + 1;
          i++;
          if (attrKey == 'label') {
            label = _unquote(attrRest);
          } else if (attrKey == 'options') {
            if (attrRest.isNotEmpty) {
              throw FormatException(
                '$sourceLabel:$attrLineNumber: "options:" must start a '
                'block list, not an inline value: "$attrRest"',
              );
            }
            while (i < lines.length && _eightSpaceListItem.hasMatch(lines[i])) {
              final optionText = _eightSpaceListItem
                  .firstMatch(lines[i])!
                  .group(1)!;
              final checkboxMatch = _checkboxOptionLabel.firstMatch(optionText);
              options.add(_unquote(checkboxMatch?.group(1) ?? optionText));
              i++;
            }
          } else if (attrKey == 'description' ||
              attrKey == 'placeholder' ||
              attrKey == 'value') {
            // Recognized, single-line-only; not needed by the policy
            // checks below, so the value itself is not retained.
          } else {
            throw FormatException(
              '$sourceLabel:$attrLineNumber: unsupported "attributes:" '
              'key "$attrKey"',
            );
          }
        }
      } else if (key == 'validations') {
        if (rest.isNotEmpty) {
          throw FormatException(
            '$sourceLabel:$lineNumber: "validations:" must start a block '
            'mapping, not an inline value: "$rest"',
          );
        }
        while (i < lines.length && _sixSpaceKeyLine.hasMatch(lines[i])) {
          final valMatch = _sixSpaceKeyLine.firstMatch(lines[i])!;
          final valKey = valMatch.group(1)!;
          final valRest = valMatch.group(2)!.trim();
          final valLineNumber = i + 1;
          i++;
          if (valKey != 'required') {
            throw FormatException(
              '$sourceLabel:$valLineNumber: unsupported "validations:" '
              'key "$valKey" — only "required" is supported',
            );
          }
          if (valRest == 'true') {
            required = true;
          } else if (valRest == 'false') {
            required = false;
          } else {
            throw FormatException(
              '$sourceLabel:$valLineNumber: "required:" must be "true" '
              'or "false", got: "$valRest"',
            );
          }
        }
      } else {
        throw FormatException(
          '$sourceLabel:$lineNumber: unsupported body-element key '
          '"$key" — only id/attributes/validations are supported',
        );
      }
    }

    fields.add(
      IssueFormField(
        type: type,
        id: id,
        label: label,
        required: required,
        options: options,
      ),
    );
  }
  return i;
}

/// The six fields `docs/process/backlog-policy.md` §3 requires on every
/// issue template, each with `validations: required: true`.
const List<String> requiredIssueFieldIds = [
  'chapter',
  'round',
  'acceptance',
  'test_plan',
  'rollback',
  'privacy',
];

/// Returns the subset of [requiredIssueFieldIds] that [form] does NOT
/// declare with `required: true` — empty when the form is compliant.
List<String> findMissingRequiredIssueFields(IssueForm form) {
  final requiredPresent = <String>{
    for (final field in form.fields)
      if (field.id != null && field.required) field.id!,
  };
  return [
    for (final fieldId in requiredIssueFieldIds)
      if (!requiredPresent.contains(fieldId)) fieldId,
  ];
}

/// Reads `blank_issues_enabled:` out of `.github/ISSUE_TEMPLATE/config.yml`.
///
/// Returns `null` when the key is absent — the caller must treat a missing
/// key as non-compliant, not silently default it.
bool? parseBlankIssuesEnabled(String contents) {
  for (final line in contents.split('\n')) {
    final match = RegExp(
      r'^blank_issues_enabled:\s*(true|false)\s*$',
    ).firstMatch(line.trim());
    if (match != null) return match.group(1) == 'true';
  }
  return null;
}

// ---------------------------------------------------------------------------
// CODEOWNERS (ADR 0444 D1, D4)
// ---------------------------------------------------------------------------

/// One non-comment, non-blank line of a `CODEOWNERS` file.
final class CodeownersEntry {
  const CodeownersEntry({
    required this.pattern,
    required this.owners,
    required this.lineNumber,
  });

  final String pattern;
  final List<String> owners;
  final int lineNumber;
}

List<CodeownersEntry> parseCodeowners(String contents) {
  final entries = <CodeownersEntry>[];
  final lines = contents.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    entries.add(
      CodeownersEntry(
        pattern: parts.first,
        owners: parts.skip(1).toList(),
        lineNumber: i + 1,
      ),
    );
  }
  return entries;
}

/// Returns the patterns in [entries] that do not resolve to a real path
/// under [exists] (ADR 0444 D4 — a fantom-útvonal covers nothing silently).
List<String> findPhantomCodeownersPaths(
  List<CodeownersEntry> entries, {
  required bool Function(String path) exists,
}) {
  final phantom = <String>[];
  for (final entry in entries) {
    final relative = entry.pattern
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    if (relative.isEmpty) continue;
    if (!exists(relative)) phantom.add(entry.pattern);
  }
  return phantom;
}

/// D1-sértő minta: emberi jóváhagyást a merge FELTÉTELÉVÉ tévő szöveg
/// `.github/CODEOWNERS`-ben vagy `docs/process/branch-protection.md`-ben —
/// ez DEADLOCK-ba vinné az autonóm kör-pipeline squash-merge-ét (ADR 0444
/// D1, ADR 0050 "Szóló-fejlesztői adaptációk").
///
/// A minta SZÖVEGES előfordulást mér, nem szándékot: egy olyan mondat is
/// pirosra vált, amely ezt a tilalmat a saját szavaival mondja ki (nem csak
/// egy olyan, ami megsérti). Ez szándékos fail-closed viselkedés, nem hiba
/// — a szerkesztett dokumentumok ezért a szabályt körülírással fogalmazzák,
/// a lenti minták szó szerinti fordulatai nélkül, és **a minta gyengítése
/// (pl. negáció-érzékennyé tétel) nem megoldás**, mert az pont ezt az őrt
/// ölné meg.
final List<RegExp> forbiddenHumanApprovalPatterns = [
  RegExp(r'required_approving_review_count\s*[:=]?\s*[1-9]'),
  RegExp(r'legal[aá]bb\s+1\s+(?:approving\s+)?review', caseSensitive: false),
  RegExp(
    r'k[oö]telez[oő]\s+(?:emberi\s+)?j[oó]v[aá]hagy[aá]s',
    caseSensitive: false,
  ),
];

List<String> findForbiddenHumanApprovalMatches(String contents) => [
  for (final pattern in forbiddenHumanApprovalPatterns)
    if (pattern.hasMatch(contents)) pattern.pattern,
];

// ---------------------------------------------------------------------------
// PR template (ADR 0444 D5, brief §0.0.A P5 / A7)
// ---------------------------------------------------------------------------

/// The section headers that must survive any `pull_request_template.md`
/// edit — the ten mért headers plus this round's new "Release evidence"
/// block. Losing one is a regression (ADR 0444 D5), not a stylistic choice.
const List<String> requiredPrTemplateHeaders = [
  '## SDD requirement / kör',
  '## Cél és nem-cél',
  '## Fő változások',
  '## Migration / API hatás',
  '## Tesztek',
  '## Evidence',
  '## Release evidence',
  '## Privacy / security hatás',
  '## Rollback',
  '## Follow-up',
];

List<String> findMissingPrTemplateHeaders(String contents) => [
  for (final header in requiredPrTemplateHeaders)
    if (!contents.contains(header)) header,
];

/// Whether the template carries a mandatory release-asset explanation line
/// (SDD Ch12 Kör 3 "tiltsd a release asset változás magyarázat nélküli
/// merge-ét" — brief §0.0.A P5 / A7).
bool prTemplateHasReleaseAssetLine(String contents) =>
    contents.toLowerCase().contains('release asset');

void main() {
  group('parseIssueForm — restricted subset (ADR 0444 D3)', () {
    test('parses a minimal, fully-formed issue form', () {
      const fixture = '''
name: "Feature request"
description: "desc"
title: "[Feature] "
labels:
  - feature
  - needs-triage
body:
  - type: markdown
    attributes:
      value: "info"
  - type: input
    id: chapter
    attributes:
      label: "Chapter"
      description: "which chapter"
      placeholder: "pl. Chapter 07"
    validations:
      required: true
  - type: dropdown
    id: severity
    attributes:
      label: "Severity"
      options:
        - "P0"
        - "P1"
    validations:
      required: false
  - type: checkboxes
    id: confirm
    attributes:
      label: "Confirm"
      options:
        - label: "First"
        - label: "Second"
''';
      final form = parseIssueForm(fixture, sourceLabel: 'fixture');
      expect(form.name, 'Feature request');
      expect(form.title, '[Feature] ');
      expect(form.labels, ['feature', 'needs-triage']);
      expect(form.fields, hasLength(4));
      expect(form.fields[0].type, 'markdown');
      final chapterField = form.fields[1];
      expect(chapterField.id, 'chapter');
      expect(chapterField.label, 'Chapter');
      expect(chapterField.required, isTrue);
      final severityField = form.fields[2];
      expect(severityField.required, isFalse);
      expect(severityField.options, ['P0', 'P1']);
      final checkboxField = form.fields[3];
      expect(checkboxField.options, ['First', 'Second']);
    });

    test('rejects an inline flow-map on a container key (6.1 matrix row: '
        '"a Dart parser által NEM olvasható alak")', () {
      const fixture = '''
name: "x"
body:
  - type: input
    id: chapter
    attributes: {label: "Chapter"}
    validations:
      required: true
''';
      expect(
        () => parseIssueForm(fixture, sourceLabel: 'fixture'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('inline value'),
          ),
        ),
      );
    });

    test('rejects a line at the wrong indentation', () {
      const fixture = '''
name: "x"
body:
  - type: input
     id: chapter
''';
      expect(
        () => parseIssueForm(fixture, sourceLabel: 'fixture'),
        throwsFormatException,
      );
    });

    test('rejects an unsupported top-level key', () {
      expect(
        () => parseIssueForm('unsupported: 1\n', sourceLabel: 'fixture'),
        throwsFormatException,
      );
    });

    test('rejects "required:" that is neither true nor false', () {
      const fixture = '''
name: "x"
body:
  - type: input
    id: chapter
    validations:
      required: maybe
''';
      expect(
        () => parseIssueForm(fixture, sourceLabel: 'fixture'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('"true" or "false"'),
          ),
        ),
      );
    });
  });

  group('A1 — required issue-template fields, fixture-driven (L260)', () {
    String formWithFields(List<String> presentRequiredIds) {
      final buffer = StringBuffer('name: "x"\nbody:\n');
      for (final fieldId in presentRequiredIds) {
        buffer.write(
          '  - type: input\n    id: $fieldId\n    validations:\n'
          '      required: true\n',
        );
      }
      return buffer.toString();
    }

    test('a fixture missing the rollback field is flagged', () {
      final fixture = formWithFields(
        requiredIssueFieldIds.where((id) => id != 'rollback').toList(),
      );
      final form = parseIssueForm(fixture, sourceLabel: 'fixture');
      expect(findMissingRequiredIssueFields(form), ['rollback']);
    });

    test('a fixture with all six required fields present is clean', () {
      final fixture = formWithFields(requiredIssueFieldIds);
      final form = parseIssueForm(fixture, sourceLabel: 'fixture');
      expect(findMissingRequiredIssueFields(form), isEmpty);
    });

    test('a field present but not required: true does not satisfy the '
        'requirement (contains-only would have missed this — L260)', () {
      const fixture = '''
name: "x"
body:
  - type: textarea
    id: rollback
    validations:
      required: false
''';
      final form = parseIssueForm(fixture, sourceLabel: 'fixture');
      expect(findMissingRequiredIssueFields(form), contains('rollback'));
    });

    test('all five real issue templates satisfy the six required fields', () {
      for (final filename in [
        'feature.yml',
        'bug.yml',
        'security.yml',
        'migration.yml',
        'release.yml',
      ]) {
        final path = '.github/ISSUE_TEMPLATE/$filename';
        final form = parseIssueForm(
          File(path).readAsStringSync(),
          sourceLabel: path,
        );
        expect(
          findMissingRequiredIssueFields(form),
          isEmpty,
          reason: '$path is missing required fields',
        );
      }
    });
  });

  group('A2 — blank issues disabled', () {
    test('the real config.yml sets blank_issues_enabled: false', () {
      final contents = File(
        '.github/ISSUE_TEMPLATE/config.yml',
      ).readAsStringSync();
      expect(parseBlankIssuesEnabled(contents), isFalse);
    });

    test('a fixture with true is read as true, not silently accepted', () {
      expect(parseBlankIssuesEnabled('blank_issues_enabled: true\n'), isTrue);
    });

    test('a fixture missing the key returns null (caller fails closed)', () {
      expect(parseBlankIssuesEnabled('contact_links:\n'), isNull);
    });
  });

  group('A3 — CODEOWNERS patterns match the measured tree (ADR 0444 D4)', () {
    bool realTreeExists(String relativePath) =>
        FileSystemEntity.typeSync(relativePath) !=
        FileSystemEntityType.notFound;

    test('every real CODEOWNERS pattern points to an existing path', () {
      final entries = parseCodeowners(
        File('.github/CODEOWNERS').readAsStringSync(),
      );
      expect(entries, isNotEmpty);
      final phantom = findPhantomCodeownersPaths(
        entries,
        exists: realTreeExists,
      );
      expect(phantom, isEmpty, reason: phantom.join(', '));
    });

    test('6.1 matrix row: "assets/models/**" is flagged — the fantom-minta '
        '§0.0.A P3 measured does NOT exist (the real name is assets/ml/)', () {
      final entries = parseCodeowners('/assets/models/ @someone\n');
      final phantom = findPhantomCodeownersPaths(
        entries,
        exists: realTreeExists,
      );
      expect(phantom, ['/assets/models/']);
    });

    test('6.1 matrix row: "lib/audio/**" is flagged — the real tree has '
        'lib/core/audio/, not lib/audio/', () {
      final entries = parseCodeowners('/lib/audio/ @someone\n');
      final phantom = findPhantomCodeownersPaths(
        entries,
        exists: realTreeExists,
      );
      expect(phantom, ['/lib/audio/']);
    });

    test('a pattern on a real path is not flagged', () {
      final entries = parseCodeowners('/lib/core/audio/ @someone\n');
      final phantom = findPhantomCodeownersPaths(
        entries,
        exists: realTreeExists,
      );
      expect(phantom, isEmpty);
    });
  });

  group('A4 — PR template regression guard (ADR 0444 D5)', () {
    test('the real PR template keeps every required header', () {
      final contents = File(
        '.github/pull_request_template.md',
      ).readAsStringSync();
      expect(findMissingPrTemplateHeaders(contents), isEmpty);
    });

    test('6.1 matrix row: a rewrite that drops "Tesztek (pontos parancsok…)" '
        'is flagged', () {
      const fixture = '## SDD requirement / kör\n## Evidence\n';
      expect(findMissingPrTemplateHeaders(fixture), contains('## Tesztek'));
    });

    test('a fixture missing "## Rollback" is flagged (regression class)', () {
      const fixture = '## SDD requirement / kör\n## Evidence\n';
      expect(findMissingPrTemplateHeaders(fixture), contains('## Rollback'));
    });
  });

  group('A6 — no required human approval (ADR 0444 D1)', () {
    test('the real branch-protection.md contains no forbidden pattern', () {
      final contents = File(
        'docs/process/branch-protection.md',
      ).readAsStringSync();
      expect(findForbiddenHumanApprovalMatches(contents), isEmpty);
    });

    test('the real CODEOWNERS contains no forbidden pattern', () {
      final contents = File('.github/CODEOWNERS').readAsStringSync();
      expect(findForbiddenHumanApprovalMatches(contents), isEmpty);
    });

    test(
      '6.1 matrix row: "legalább 1 approving review kötelező" is flagged',
      () {
        expect(
          findForbiddenHumanApprovalMatches(
            'Kötelező: legalább 1 approving review a merge előtt.',
          ),
          isNotEmpty,
        );
      },
    );

    test('required_approving_review_count: 1 is flagged', () {
      expect(
        findForbiddenHumanApprovalMatches('required_approving_review_count: 1'),
        isNotEmpty,
      );
    });

    test('required_approving_review_count: 0 (informational, not a '
        'requirement) is NOT flagged — zero is not a merge condition', () {
      expect(
        findForbiddenHumanApprovalMatches('required_approving_review_count: 0'),
        isEmpty,
      );
    });
  });

  group('A7 — release-asset mandatory line (brief §0.0.A P5)', () {
    test('the real PR template has a release-asset line', () {
      final contents = File(
        '.github/pull_request_template.md',
      ).readAsStringSync();
      expect(prTemplateHasReleaseAssetLine(contents), isTrue);
    });

    test('the real backlog-policy.md states the release-asset rule', () {
      final contents = File(
        'docs/process/backlog-policy.md',
      ).readAsStringSync();
      expect(contents.toLowerCase(), contains('release asset'));
    });

    test('6.1 matrix row: a PR template missing the release-asset line is '
        'flagged', () {
      expect(prTemplateHasReleaseAssetLine('## Evidence\n'), isFalse);
    });
  });

  group(
    'A8 — the guard itself never shells out to an external binary (L110)',
    () {
      // Built via adjacent string-literal concatenation so this file's OWN
      // source text never contains either literal marker being searched
      // for contiguously — a self-matching guard would always fail
      // regardless of the rest of the file, exactly like the A9 guard in
      // sdd_index_guard_test.dart avoids writing "package:" directly
      // adjacent to "yaml" in its own source.
      //
      // `dart:io` has three external-process entry points, but only two
      // distinct name prefixes: the synchronous variant shares its prefix
      // with the async one, so a single marker covers both, and a second,
      // unrelated marker covers the third entry point.
      final forbiddenProcessCallMarkers = [
        'Process'
            '.run',
        'Process'
            '.start',
      ];

      test('this test file never spawns an external process through any '
          'dart:io Process entry point', () {
        final source = File(
          'test/tooling/repository_policy_test.dart',
        ).readAsStringSync();
        for (final marker in forbiddenProcessCallMarkers) {
          expect(source, isNot(contains(marker)));
        }
      });
    },
  );
}
