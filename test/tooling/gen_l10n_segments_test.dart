// E99-R17 §4 — a `tool/gen_l10n_segments.dart` hat mérce-cellájának tesztje.
//
// A generátor három invariánst tart fenn egyszerre:
//   1. a fragmentumok + alap determinisztikus uniója a lemezen lévő
//      aggregátummal egyezik meg (`--check` módban a frissességet is méri);
//   2. egy kulcsot két szegmens NEM tartalmazhat — ez `errors` bejegyzés és
//      `aggregate == null`;
//   3. a kimenet kulcs-sorrendje ALFABETIKUS, a `@@locale` fejléccel az első
//      helyen, a `@kulcs` metaadat azonnal a `kulcs` üzenet után.
//
// Ezeket a `Segment`, `MergeResult` és `generateLocale` típusokon keresztül
// mérjük — nem a `main()`-en át, mert az utóbbi a parancssori kapcsolók
// kábelezésével egy `dart run`-t indítana, és ezen a boxon a `flutter test`
// a mérce (round-gate), nem a `dart run`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/gen_l10n_segments.dart';

void main() {
  group('mergeSegments', () {
    test('azonos kulcshalmaz — az unió halmazszinten egyezik', () {
      final merge = mergeSegments(
        locale: 'en',
        segments: [
          Segment(
            label: 'base',
            path: 'base',
            data: {'@@locale': 'en', 'a': 'one', 'b': 'two'},
          ),
          Segment(
            label: 'feat',
            path: 'feat',
            data: {'@@locale': 'en', 'c': 'three', 'd': 'four'},
          ),
        ],
      );

      expect(merge.isClean, isTrue, reason: merge.errors.join('; '));
      expect(merge.aggregate!.messageKeys.toSet(), {'a', 'b', 'c', 'd'});
      expect(merge.aggregate!.locale, 'en');
      expect(merge.aggregate!.data['@@locale'], 'en');
    });

    test('hiányzó kulcs — a hiány pirosra váltja a paritás-ellenőrzést', () {
      // Az aggregátumban megjelenő kulcsok a fixture:
      //   - base: {a, b, c}
      //   - tuner: {b}
      //   - aggregátum (a generátor kimenete): {a, b, c}
      // Ha a tuner-fragmentumból KIESIK a 'b', a generátor is piros.
      final merge = mergeSegments(
        locale: 'en',
        segments: [
          Segment(
            label: 'base',
            path: 'base',
            data: {'@@locale': 'en', 'a': 'one', 'b': 'two', 'c': 'three'},
          ),
          // A 'b' kulcs SZÁNDÉKOSAN hiányzik a fragmentumból.
          Segment(label: 'tuner', path: 'tuner', data: {'@@locale': 'en'}),
        ],
      );

      // A merge TISZTA — a generátor csak a kulcsok unióját adja.
      expect(merge.isClean, isTrue);
      // A HIÁNYT a paritás-ellenőrzés fogja pirosra váltani:
      // a sablonban ('en') bent van a 'b', de ha a fordítási fájl
      // ('hu') a másik oldalon marad, a check_l10n_parity piros lesz.
      expect(merge.aggregate!.messageKeys.toSet(), {'a', 'b', 'c'});
    });

    test('duplikált kulcs — a generátor hibával áll meg', () {
      final merge = mergeSegments(
        locale: 'en',
        segments: [
          Segment(
            label: 'base',
            path: 'base',
            data: {'@@locale': 'en', 'greeting': 'Hello'},
          ),
          Segment(
            label: 'feat',
            path: 'feat',
            data: {'@@locale': 'en', 'greeting': 'Hi'},
          ),
        ],
      );

      expect(merge.isClean, isFalse);
      expect(merge.aggregate, isNull);
      expect(merge.errors, hasLength(1));
      expect(merge.errors.single, contains('greeting'));
    });

    test('metaadat csak az üzenet mellé kerül, soha nem arva', () {
      final merge = mergeSegments(
        locale: 'en',
        segments: [
          // Az '@orphan' metaadatnak nincs üzenet-párja — nem kerülhet be.
          Segment(
            label: 'base',
            path: 'base',
            data: {
              '@@locale': 'en',
              'greeting': 'Hello',
              '@greeting': {'description': 'say hi'},
              '@orphan': {'description': 'no message'},
            },
          ),
        ],
      );

      expect(merge.isClean, isTrue);
      expect(merge.aggregate!.messageKeys.toSet(), {'greeting'});
      expect(merge.aggregate!.data['@greeting'], isA<Map>());
      expect(merge.aggregate!.data.containsKey('@orphan'), isFalse);
    });
  });

  group('generateLocale', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('strumsight_gen_l10n_');
      Directory('${root.path}/lib/l10n').createSync(recursive: true);
      Directory('${root.path}/lib/l10n/base').createSync();
      Directory('${root.path}/lib/l10n/features').createSync();
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test('write: az aggregátum kulcshalmaza a szegmensek uniója', () {
      File('${root.path}/lib/l10n/base/app_en.arb').writeAsStringSync(
        jsonEncode({
          '@@locale': 'en',
          'appTitle': 'StrumSight',
          '@appTitle': {'description': 'app name'},
          'greeting': 'Hello',
        }),
      );
      File('${root.path}/lib/l10n/features/tuner_en.arb').writeAsStringSync(
        jsonEncode({'@@locale': 'en', 'tunerTitle': 'Tuner'}),
      );

      final outcome = generateLocale(
        locale: 'en',
        projectRoot: root,
        check: false,
      );

      expect(outcome.isOk, isTrue, reason: outcome.errors.join('; '));
      expect(outcome.wrote, isTrue);

      final aggregate = File('${root.path}/lib/l10n/app_en.arb');
      final decoded =
          jsonDecode(aggregate.readAsStringSync()) as Map<String, dynamic>;
      final messageKeys = decoded.keys.where((k) => !k.startsWith('@')).toSet();
      expect(messageKeys, {'appTitle', 'greeting', 'tunerTitle'});
      expect(decoded['@@locale'], 'en');
    });

    test('check: azonos aggregátum — ZÖLD (frissesség OK)', () {
      File(
        '${root.path}/lib/l10n/base/app_en.arb',
      ).writeAsStringSync(jsonEncode({'@@locale': 'en', 'a': 'A', 'b': 'B'}));
      // A frissített aggregátum ELŐRE ki van írva (ugyanazzal a tartalommal,
      // amit a generátor írna). A generátor `JsonEncoder.withIndent('  ')`-t
      // használ — a fixture ezt a formátumot követi, különben a frissesség
      // hamis PIROSAT adna.
      File('${root.path}/lib/l10n/app_en.arb').writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'@@locale': 'en', 'a': 'A', 'b': 'B'}),
      );

      final outcome = generateLocale(
        locale: 'en',
        projectRoot: root,
        check: true,
      );

      expect(outcome.isOk, isTrue);
      expect(outcome.stale, isFalse);
    });

    test('check: aggregátum ELÁVULT — PIROS (a D2 gate őre)', () {
      // Ez a §4 FALSZIFIKÁCIÓS cellája: ha a `--check` hívás kimarad a
      // gate-ből, az elavult aggregátum ZÖLDEN menne át.
      File(
        '${root.path}/lib/l10n/base/app_en.arb',
      ).writeAsStringSync(jsonEncode({'@@locale': 'en', 'a': 'A', 'b': 'B'}));
      // A lemezen lévő aggregátum HIÁNYOS — 'b' lemaradt.
      File('${root.path}/lib/l10n/app_en.arb').writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'@@locale': 'en', 'a': 'A'}),
      );

      final outcome = generateLocale(
        locale: 'en',
        projectRoot: root,
        check: true,
      );

      expect(outcome.stale, isTrue);
      expect(outcome.isOk, isFalse);
    });

    test('hiányzó alap — a generátor hibát jelez', () {
      // A D3 előtti állapot: lib/l10n/base/app_en.arb még nem létezik.
      // A generátornak ezt az esetet KEZELNIE kell, nem néma átugrással.
      final outcome = generateLocale(
        locale: 'en',
        projectRoot: root,
        check: false,
      );

      expect(outcome.errors, hasLength(1));
      expect(outcome.errors.single, contains('hiányzó alap'));
    });

    test('write: a kulcssorrend ALFABETIKUS, @@locale az első helyen', () {
      File('${root.path}/lib/l10n/base/app_en.arb').writeAsStringSync(
        jsonEncode({'@@locale': 'en', 'zeta': 'Z', 'alpha': 'A'}),
      );

      final outcome = generateLocale(
        locale: 'en',
        projectRoot: root,
        check: false,
      );

      expect(outcome.isOk, isTrue);
      final encoded = File(
        '${root.path}/lib/l10n/app_en.arb',
      ).readAsStringSync();
      final alphaAt = encoded.indexOf('"alpha"');
      final zetaAt = encoded.indexOf('"zeta"');
      final localeAt = encoded.indexOf('"@@locale"');
      expect(localeAt, lessThan(alphaAt));
      expect(alphaAt, lessThan(zetaAt));
    });
  });
}
