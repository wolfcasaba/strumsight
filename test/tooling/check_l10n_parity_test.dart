import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/check_l10n_parity.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('strumsight_l10n_parity_');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('accepts a complete translation', () {
    final report = _check(
      root,
      template: '''
{
  "@@locale": "en",
  "appTitle": "StrumSight",
  "@appTitle": {"description": "App name"},
  "greeting": "Hello, {name}!"
}
''',
      translation: '''
{
  "@@locale": "hu",
  "appTitle": "StrumSight",
  "greeting": "Szia, {name}!"
}
''',
    );

    expect(report.isClean, isTrue, reason: report.format());
    expect(report.messageCount, 2);
  });

  test('reports a key missing from the translation', () {
    final report = _check(
      root,
      template: '''
{"a": "One", "b": "Two"}
''',
      translation: '''
{"a": "Egy"}
''',
    );

    expect(report.isClean, isFalse);
    expect(report.issues.single.key, 'b');
    expect(report.issues.single.kind, L10nIssueKind.missingTranslation);
  });

  test('reports a key that only the translation has', () {
    final report = _check(
      root,
      template: '''
{"a": "One"}
''',
      translation: '''
{"a": "Egy", "stale": "Régi"}
''',
    );

    expect(report.issues.single.key, 'stale');
    expect(report.issues.single.kind, L10nIssueKind.extraTranslation);
  });

  test('reports mismatched placeholders', () {
    final report = _check(
      root,
      template: '''
{"progress": "{done} of {total}"}
''',
      translation: '''
{"progress": "{done} / {osszes}"}
''',
    );

    expect(report.issues.single.kind, L10nIssueKind.placeholderMismatch);
    expect(report.issues.single.detail, contains('total'));
  });

  test('reports an empty translation instead of accepting it as present', () {
    final report = _check(
      root,
      template: '''
{"a": "One"}
''',
      translation: '''
{"a": "   "}
''',
    );

    expect(report.issues.single.kind, L10nIssueKind.emptyMessage);
  });

  test('ignores @-prefixed metadata on both sides', () {
    final report = _check(
      root,
      template: '''
{
  "@@locale": "en",
  "a": "One",
  "@a": {"description": "csak a sablonban van metaadat"}
}
''',
      translation: '''
{"@@locale": "hu", "a": "Egy"}
''',
    );

    expect(report.isClean, isTrue, reason: report.format());
  });
}

L10nParityReport _check(
  Directory root, {
  required String template,
  required String translation,
}) {
  final templateFile = File('${root.path}/app_en.arb')
    ..writeAsStringSync(template);
  final translationFile = File('${root.path}/app_hu.arb')
    ..writeAsStringSync(translation);
  return checkL10nParity(template: templateFile, translation: translationFile);
}
