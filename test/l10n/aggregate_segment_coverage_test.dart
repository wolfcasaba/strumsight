import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The generated aggregate (`lib/l10n/app_{en,hu}.arb`, ADR 0307 §4) is the
/// UNION of the hand-edited segments — `lib/l10n/base/app_<locale>.arb` plus
/// `lib/l10n/features/<feature>_<locale>.arb`. A key that lives ONLY in the
/// aggregate compiles today and disappears the moment anyone re-runs
/// `dart run tool/gen_l10n_segments.dart --write`, taking every call site
/// with it (round A3 finding: `liveStringsSemantics` was in exactly that
/// state).
///
/// `tool/gen_l10n_segments.dart --check` catches the reverse direction
/// (segments newer than the aggregate); nothing caught this one, because a
/// stale aggregate with EXTRA keys is a superset, and the check only ran
/// after a regeneration had already destroyed the evidence.
void main() {
  Map<String, dynamic> loadArb(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  Set<String> messageKeysOf(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  Iterable<String> segmentsFor(String locale) sync* {
    yield 'lib/l10n/base/app_$locale.arb';
    final featureDir = Directory('lib/l10n/features');
    final suffix = '_$locale.arb';
    final paths =
        featureDir
            .listSync()
            .whereType<File>()
            .map((f) => f.path.replaceAll(r'\', '/'))
            .where((p) => p.endsWith(suffix))
            .toList()
          ..sort();
    yield* paths;
  }

  for (final locale in const ['en', 'hu']) {
    test('$locale: every aggregate key is backed by a source segment', () {
      final aggregate = messageKeysOf(loadArb('lib/l10n/app_$locale.arb'));
      final fromSegments = <String>{};
      for (final path in segmentsFor(locale)) {
        fromSegments.addAll(messageKeysOf(loadArb(path)));
      }

      expect(
        aggregate.difference(fromSegments),
        isEmpty,
        reason:
            'these keys exist only in the generated lib/l10n/app_$locale.arb '
            'and would be deleted by the next '
            '`dart run tool/gen_l10n_segments.dart --write` — add them to '
            'lib/l10n/base/app_$locale.arb or the owning feature segment',
      );
    });
  }
}
