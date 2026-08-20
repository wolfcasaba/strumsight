import 'dart:convert';
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

  group('checkGeneratedAggregates (E99-R17 D2)', () {
    setUp(() {
      // A `checkGeneratedAggregates` a `lib/l10n/{base,features}` könyvtárakat
      // olvassa — a teszt root-on belül ezeket külön kell létrehozni.
      Directory('${root.path}/lib/l10n').createSync(recursive: true);
      Directory('${root.path}/lib/l10n/base').createSync();
    });

    test('friss aggregátum — ZÖLD', () {
      // A base + feature fragmentumokból GENERÁT generálja az aggregátumot
      // ugyanazzal a tartalommal — a `checkGeneratedAggregates` a frissességet
      // és a paritást EGYÜTT méri.
      final enBase = File('${root.path}/lib/l10n/base/app_en.arb')
        ..writeAsStringSync(_arb({'@@locale': 'en', 'a': 'A', 'b': 'B'}));
      File(
        '${root.path}/lib/l10n/base/app_hu.arb',
      ).writeAsStringSync(_arb({'@@locale': 'hu', 'a': 'Á', 'b': 'Bé'}));
      Directory('${root.path}/lib/l10n/features').createSync();
      File(
        '${root.path}/lib/l10n/features/tuner_en.arb',
      ).writeAsStringSync(_arb({'@@locale': 'en', 'tunerTitle': 'Tuner'}));
      File(
        '${root.path}/lib/l10n/features/tuner_hu.arb',
      ).writeAsStringSync(_arb({'@@locale': 'hu', 'tunerTitle': 'Hangoló'}));
      File('${root.path}/lib/l10n/app_en.arb').writeAsStringSync(
        _arb({'@@locale': 'en', 'a': 'A', 'b': 'B', 'tunerTitle': 'Tuner'}),
      );
      File('${root.path}/lib/l10n/app_hu.arb').writeAsStringSync(
        _arb({'@@locale': 'hu', 'a': 'Á', 'b': 'Bé', 'tunerTitle': 'Hangoló'}),
      );

      final report = checkGeneratedAggregates(projectRoot: root);
      expect(report.isClean, isTrue, reason: report.format());
      // ignore: unused_local_variable
      final _ = enBase;
    });

    test('aggregátum elavult — PIROS (a §4 4. cella)', () {
      // A base-ből generált aggregátum ELTÉR a lemezen lévőtől — ez a D2
      // falszifikációs cellája: a `--check` hívás nélkül ez a hiba
      // ZÖLDEN menne át.
      File(
        '${root.path}/lib/l10n/base/app_en.arb',
      ).writeAsStringSync(_arb({'@@locale': 'en', 'a': 'A', 'b': 'B'}));
      File(
        '${root.path}/lib/l10n/base/app_hu.arb',
      ).writeAsStringSync(_arb({'@@locale': 'hu', 'a': 'Á', 'b': 'Bé'}));
      Directory('${root.path}/lib/l10n/features').createSync();
      File(
        '${root.path}/lib/l10n/features/tuner_en.arb',
      ).writeAsStringSync(_arb({'@@locale': 'en', 'tunerTitle': 'Tuner'}));
      File(
        '${root.path}/lib/l10n/features/tuner_hu.arb',
      ).writeAsStringSync(_arb({'@@locale': 'hu', 'tunerTitle': 'Hangoló'}));
      // Az aggregátum HIÁNYOS — 'b' lemaradt.
      File('${root.path}/lib/l10n/app_en.arb').writeAsStringSync(
        _arb({'@@locale': 'en', 'a': 'A', 'tunerTitle': 'Tuner'}),
      );
      File('${root.path}/lib/l10n/app_hu.arb').writeAsStringSync(
        _arb({'@@locale': 'hu', 'a': 'Á', 'tunerTitle': 'Hangoló'}),
      );

      final report = checkGeneratedAggregates(projectRoot: root);
      expect(report.isClean, isFalse);
      expect(
        report.problems.any((p) => p.contains('aggregátum elavult')),
        isTrue,
      );
    });

    test('hiányzó kulcs — a paritás PIROS, a generátor is jelzi', () {
      // A §4 2. cellája: a sablonban ('en') bent van a kulcs, de a
      // fordításból ('hu') kimarad. A paritás-ellenőrzés a
      // `checkL10nParity`-n át fog pirosra váltani — ezt a `main()`
      // hívásláncában a `checkGeneratedAggregates` után futó lépés méri.
      // Itt csak a frissességet mérjük: az aggregátum a base-szintű
      // tartalommal megegyezik.
      File(
        '${root.path}/lib/l10n/base/app_en.arb',
      ).writeAsStringSync(_arb({'@@locale': 'en', 'greeting': 'Hello'}));
      // A 'hu' fordítás HIÁNYOS — 'greeting' nem szerepel.
      File(
        '${root.path}/lib/l10n/base/app_hu.arb',
      ).writeAsStringSync(_arb({'@@locale': 'hu', 'farewell': 'Viszlát'}));
      File(
        '${root.path}/lib/l10n/app_en.arb',
      ).writeAsStringSync(_arb({'@@locale': 'en', 'greeting': 'Hello'}));
      File(
        '${root.path}/lib/l10n/app_hu.arb',
      ).writeAsStringSync(_arb({'@@locale': 'hu', 'farewell': 'Viszlát'}));

      final report = checkGeneratedAggregates(projectRoot: root);
      // A frissesség ÖNMAGÁBAN zöld — a paritás-ellenőrzés pirosra vált,
      // de ez a függvény csak a generátor `--check` ágát hívja.
      expect(report.isClean, isTrue, reason: report.format());
    });
  });
}

String _arb(Map<String, dynamic> data) {
  // A `JsonEncoder.withIndent('  ')` formátum a `tool/gen_l10n_segments.dart`
  // által is használt — a fixture-konzisztencia kedvéért.
  return JsonEncoder.withIndent('  ').convert(data);
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
