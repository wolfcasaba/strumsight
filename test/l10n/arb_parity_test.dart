import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fragment-level ARB parity + Hungarian plural correctness (ADR 0424 §5.2,
/// §5.6). `test/core/l10n_parity_test.dart` already locks the AGGREGATE
/// (`lib/l10n/app_{en,hu}.arb`, generated per ADR 0307 §4); it cannot say
/// which SOURCE fragment a missing key came from. This file adds two layers
/// the aggregate cannot see:
///
///  1. Per-fragment key-set parity, with the failure `reason` naming the
///     actual `lib/l10n/{base,features}/*.arb` file to edit (F1).
///  2. ICU `plural` structural rules across every fragment (F2–F4) — the
///     naive "hu must mirror en's plural" rule is WRONG for Hungarian
///     (numeral + noun stays singular: "3 nap", not "3 napok"), so this is
///     a grammar-aware check, not a mirroring one.
void main() {
  const fragments = <(String label, String enPath, String huPath)>[
    ('base/app', 'lib/l10n/base/app_en.arb', 'lib/l10n/base/app_hu.arb'),
    (
      'features/community',
      'lib/l10n/features/community_en.arb',
      'lib/l10n/features/community_hu.arb',
    ),
    (
      'features/design_system',
      'lib/l10n/features/design_system_en.arb',
      'lib/l10n/features/design_system_hu.arb',
    ),
    (
      'features/gamification',
      'lib/l10n/features/gamification_en.arb',
      'lib/l10n/features/gamification_hu.arb',
    ),
    (
      'features/onboarding',
      'lib/l10n/features/onboarding_en.arb',
      'lib/l10n/features/onboarding_hu.arb',
    ),
    (
      'features/tuner',
      'lib/l10n/features/tuner_en.arb',
      'lib/l10n/features/tuner_hu.arb',
    ),
  ];

  Map<String, dynamic> loadArb(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  Set<String> messageKeysOf(Map<String, dynamic> arb) => {
    for (final k in arb.keys.where((k) => !k.startsWith('@'))) k,
  };

  group('fragment-level key parity (A1)', () {
    for (final (label, enPath, huPath) in fragments) {
      test('$label: en and hu define exactly the same keys', () {
        final en = messageKeysOf(loadArb(enPath));
        final hu = messageKeysOf(loadArb(huPath));
        expect(
          en.difference(hu),
          isEmpty,
          reason: 'keys missing from $huPath (fragment: $label)',
        );
        expect(
          hu.difference(en),
          isEmpty,
          reason: 'keys missing from $enPath (fragment: $label)',
        );
      });
    }
  });

  group('Hungarian plural grammar (A5, ADR 0424 §5.6)', () {
    // Every (fragment, key, en value, hu value) triple across ALL segments,
    // built once so the plural rules run repo-wide, not just where they
    // happen to live today.
    final allEntries = <(String fragment, String key, String en, String hu)>[];
    for (final (label, enPath, huPath) in fragments) {
      final en = loadArb(enPath);
      final hu = loadArb(huPath);
      for (final MapEntry(key: entry, value: enValue) in en.entries) {
        if (entry.startsWith('@')) continue;
        allEntries.add((
          label,
          entry,
          enValue as String,
          (hu[entry] ?? '') as String,
        ));
      }
    }

    final pluralEntries = allEntries
        .where((e) => _findPluralClause(e.$3, argument: null) != null)
        .toList();

    test('sanity: at least one ICU-plural en message exists to exercise', () {
      expect(pluralEntries, isNotEmpty);
    });

    for (final entry in pluralEntries) {
      final (fragment, key, enValue, huValue) = entry;
      final label = '$fragment/$key';

      test('$label: en plural clause has an "other" branch (F2)', () {
        final clause = _findPluralClause(enValue, argument: null)!;
        expect(
          clause.categories.containsKey('other'),
          isTrue,
          reason:
              'en value for $key ($fragment) is missing the mandatory '
              '"other" plural branch: $enValue',
        );
      });

      test(
        '$label: hu is either bare {${'count'}}-style or a valid ICU plural (rule 2/3)',
        () {
          final enClause = _findPluralClause(enValue, argument: null)!;
          final huClause = _findPluralClause(
            huValue,
            argument: enClause.argument,
          );
          if (huClause == null) {
            // Bare form: must still reference the same placeholder — a
            // grammatically valid Hungarian message needs the number.
            expect(
              huValue.contains('{${enClause.argument}}'),
              isTrue,
              reason:
                  'hu value for $key ($fragment) is neither an ICU plural '
                  'nor references {${enClause.argument}}: $huValue',
            );
            return;
          }
          const allowedCategories = {'zero', 'one', 'other'};
          final numericOrAllowed = huClause.categories.keys.every(
            (c) =>
                allowedCategories.contains(c) || RegExp(r'^=\d+$').hasMatch(c),
          );
          expect(
            numericOrAllowed,
            isTrue,
            reason:
                'hu plural for $key ($fragment) uses a category outside '
                '{=N, zero, one, other} (Hungarian has no few/many/two): '
                '${huClause.categories.keys}',
          );
          expect(
            huClause.categories.containsKey('other'),
            isTrue,
            reason:
                'hu plural for $key ($fragment) is missing its "other" '
                'branch: $huValue',
          );
        },
      );

      test(
        '$label: hu noun form is stable across count=1 and count=3 (rule 4)',
        () {
          final enClause = _findPluralClause(enValue, argument: null)!;
          final argument = enClause.argument;
          final rendered1 = _renderHuForCount(huValue, argument, 1);
          final rendered3 = _renderHuForCount(huValue, argument, 3);
          final stripped1 = rendered1.replaceAll(RegExp(r'\d+'), '#');
          final stripped3 = rendered3.replaceAll(RegExp(r'\d+'), '#');
          expect(
            stripped1,
            stripped3,
            reason:
                'hu value for $key ($fragment) changes the noun between '
                'count=1 ("$rendered1") and count=3 ("$rendered3") — '
                'Hungarian keeps the noun singular after any numeral',
          );
        },
      );
    }
  });
}

/// One parsed `{argument, plural, category{message} ...}` clause.
class _PluralClause {
  const _PluralClause({required this.argument, required this.categories});

  final String argument;
  final Map<String, String> categories;
}

/// Finds the first ICU plural clause in [message] whose variable name is
/// [argument] (or the first one found, if [argument] is `null`). Returns
/// `null` if [message] contains no `{name, plural, ...}` clause. Brace depth
/// is tracked explicitly because plural sub-messages legally nest braces
/// (e.g. `other{{count} days}`).
_PluralClause? _findPluralClause(String message, {required String? argument}) {
  final header = RegExp(r'\{(\w+),\s*plural,\s*');
  for (final match in header.allMatches(message)) {
    final foundArgument = match.group(1)!;
    if (argument != null && foundArgument != argument) continue;
    var depth = 0;
    var end = -1;
    for (var i = match.start; i < message.length; i++) {
      final ch = message[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end == -1) continue;
    final body = message.substring(match.end, end);
    return _PluralClause(
      argument: foundArgument,
      categories: _parsePluralCategories(body),
    );
  }
  return null;
}

/// Parses `=0{0 days} =1{1 day} other{{count} days}` into a category→message
/// map, respecting nested braces inside each category's sub-message.
Map<String, String> _parsePluralCategories(String body) {
  final categories = <String, String>{};
  var i = 0;
  final n = body.length;
  while (i < n) {
    while (i < n && body[i].trim().isEmpty) {
      i++;
    }
    if (i >= n) break;
    final tokenStart = i;
    while (i < n && body[i] != '{') {
      i++;
    }
    final token = body.substring(tokenStart, i).trim();
    if (token.isEmpty || i >= n) break;
    var depth = 0;
    final subStart = i;
    var subEnd = -1;
    for (; i < n; i++) {
      if (body[i] == '{') depth++;
      if (body[i] == '}') {
        depth--;
        if (depth == 0) {
          subEnd = i;
          i++;
          break;
        }
      }
    }
    if (subEnd == -1) break;
    categories[token] = body.substring(subStart + 1, subEnd);
  }
  return categories;
}

/// Renders [huValue] for the given [count], resolving either its ICU plural
/// clause (picking the matching category) or its bare `{argument}`
/// placeholder — enough to compare the noun form across counts (rule 4),
/// not a full ICU/CLDR-compliant renderer.
String _renderHuForCount(String huValue, String argument, int count) {
  final clause = _findPluralClause(huValue, argument: argument);
  if (clause == null) {
    return huValue.replaceAll('{$argument}', '$count');
  }
  final category =
      clause.categories['=$count'] ??
      (count == 0 ? clause.categories['zero'] : null) ??
      (count == 1 ? clause.categories['one'] : null) ??
      clause.categories['other']!;
  return category.replaceAll('{$argument}', '$count');
}
