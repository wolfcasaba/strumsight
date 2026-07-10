import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks the i18n discipline (audited round 73: 211/211 keys in parity).
/// Every user-facing string goes through ARB; a key added to one locale but
/// not the other ships silent English to Hungarian users — this gate makes
/// that a test failure instead of a production surprise.
void main() {
  late Map<String, dynamic> en;
  late Map<String, dynamic> hu;

  setUpAll(() {
    en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    hu = jsonDecode(File('lib/l10n/app_hu.arb').readAsStringSync())
        as Map<String, dynamic>;
  });

  Set<String> keysOf(Map<String, dynamic> arb) =>
      {for (final k in arb.keys.where((k) => !k.startsWith('@'))) k};

  test('en and hu define exactly the same keys', () {
    final ek = keysOf(en);
    final hk = keysOf(hu);
    expect(ek.difference(hk), isEmpty,
        reason: 'keys missing from app_hu.arb');
    expect(hk.difference(ek), isEmpty,
        reason: 'keys missing from app_en.arb');
  });

  test('no locale has an empty translation', () {
    for (final arb in [en, hu]) {
      for (final k in keysOf(arb)) {
        expect((arb[k] as String).trim(), isNotEmpty,
            reason: 'empty translation for $k');
      }
    }
  });

  test('hu uses the same placeholders as en', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final k in keysOf(en)) {
      final enPh = ph.allMatches(en[k] as String).map((m) => m[1]).toSet();
      final huPh =
          ph.allMatches((hu[k] ?? '') as String).map((m) => m[1]).toSet();
      expect(huPh, enPh, reason: 'placeholder mismatch in $k');
    }
  });
}
