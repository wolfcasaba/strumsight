import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Round E13-R32, §6/A1 + A6 + §0.0.B/B7.
///
/// B7 measured that the compassionate microcopy is ALREADY merged
/// (`streakV2*` in `gamification_{en,hu}.arb`); this file is the regression
/// GUARD the brief calls for — it reads the ARB fragment directly (not the
/// widget) so a LATER round that reintroduces punitive or pay-to-preserve
/// language turns this cell red, even though today's copy is already green.
///
/// Scope: every streak, reward-inbox, reward-summary, quest, and challenge
/// key — the surfaces where a punitive, urgency, or monetized-recovery
/// regression could land.
void main() {
  final enArb = _loadArb('lib/l10n/features/gamification_en.arb');
  final huArb = _loadArb('lib/l10n/features/gamification_hu.arb');

  const relevantPrefixes = <String>[
    'streakV2',
    'rewardInbox',
    'rewardSummary',
    'quest',
    'challenge',
    'gamificationHub',
  ];

  // Substring-safe phrases (long/specific enough that no legitimate copy
  // could contain them incidentally).
  const bannedEnglishPhrases = <String>[
    '!',
    'hurry',
    'urgent',
    'deadline',
    'last chance',
    'expires soon',
    'almost over',
    'napon belül',
    'restore your streak for',
    'buy back',
    'pay to',
    'purchase',
    'subscribe',
    'premium',
    'unlock your streak',
    'streak pass',
  ];
  // Short/ambiguous stems that need a word boundary — plain `contains`
  // would false-positive on unrelated words ("closer" contains "lose",
  // "brush" contains "rush").
  final bannedEnglishWords = <RegExp>[
    RegExp(r'\blost\b'),
    RegExp(r'\blose\b'),
    RegExp(r'\brush\b'),
  ];

  const bannedHungarianPhrases = <String>[
    '!',
    'elveszett',
    'veszíts',
    'sürg',
    'határidő',
    'napon belül',
    'siess',
    'hamarosan',
    'fizess',
    'vásárold meg',
    'előfizet',
    'prémium',
  ];
  // "maradt" as its own word means "left/remaining" (urgency framing, e.g.
  // "3 nap maradt"); as a SUBSTRING it also appears inside "megmaradtak"
  // ("preserved" — reassuring, the opposite meaning), so this must be a
  // word-boundary match, not `contains`.
  final bannedHungarianWords = <RegExp>[
    RegExp(r'\bmaradt\b'),
    RegExp(r'\bfogy\w*\b'),
    RegExp(r'\butolsó\b'),
  ];

  // Scoped to the specific keys that could plausibly carry a countdown —
  // NOT the metric-semantics keys that legitimately state a day count
  // (e.g. "Current rhythm: 5 days" is a measurement, not a countdown).
  const countdownScopedKeys = <String>[
    'streakV2BrokenTitle',
    'streakV2BrokenBody',
    'streakV2RecoveryCta',
    'streakV2GraceTitle',
    'streakV2GraceBody',
    'streakV2PlannedRestTitle',
    'streakV2PlannedRestBody',
    'rewardInboxPendingTitle',
    'rewardInboxPendingBody',
    'rewardInboxPendingRetryCta',
    'rewardInboxIntegrityTitle',
    'rewardInboxIntegrityBody',
  ];
  final dayCountdown = RegExp(r'\b\d+\s*(?:day|days|nap)\b');

  List<MapEntry<String, String>> relevantEntries(Map<String, dynamic> arb) => [
    for (final entry in arb.entries)
      if (!entry.key.startsWith('@') &&
          entry.value is String &&
          relevantPrefixes.any((prefix) => entry.key.startsWith(prefix)))
        MapEntry(entry.key, entry.value as String),
  ];

  group('A1 + A6 — no punitive, urgency, or pay-to-preserve language', () {
    test('every relevant EN key avoids the banned pattern set', () {
      final offenders = <String>[];
      for (final entry in relevantEntries(enArb)) {
        final lower = entry.value.toLowerCase();
        for (final banned in bannedEnglishPhrases) {
          if (lower.contains(banned)) {
            offenders.add('${entry.key} contains "$banned": ${entry.value}');
          }
        }
        for (final banned in bannedEnglishWords) {
          if (banned.hasMatch(lower)) {
            offenders.add(
              '${entry.key} contains ${banned.pattern}: ${entry.value}',
            );
          }
        }
        if (countdownScopedKeys.contains(entry.key) &&
            dayCountdown.hasMatch(lower)) {
          offenders.add('${entry.key} carries a day-countdown: ${entry.value}');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('every relevant HU key avoids the banned pattern set', () {
      final offenders = <String>[];
      for (final entry in relevantEntries(huArb)) {
        final lower = entry.value.toLowerCase();
        for (final banned in bannedHungarianPhrases) {
          if (lower.contains(banned)) {
            offenders.add('${entry.key} contains "$banned": ${entry.value}');
          }
        }
        for (final banned in bannedHungarianWords) {
          if (banned.hasMatch(lower)) {
            offenders.add(
              '${entry.key} contains ${banned.pattern}: ${entry.value}',
            );
          }
        }
        if (countdownScopedKeys.contains(entry.key) &&
            dayCountdown.hasMatch(lower)) {
          offenders.add('${entry.key} carries a day-countdown: ${entry.value}');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('at least the merged streakV2 broken/grace/plannedRest surface is '
        'covered by this scan (sanity — the scan is not vacuous)', () {
      final enKeys = relevantEntries(enArb).map((e) => e.key).toSet();
      for (final required in <String>[
        'streakV2BrokenTitle',
        'streakV2BrokenBody',
        'streakV2GraceTitle',
        'streakV2PlannedRestTitle',
        'streakV2RecoveryCta',
        'rewardInboxPendingBody',
        'rewardInboxIntegrityBody',
      ]) {
        expect(enKeys, contains(required), reason: '$required must be scanned');
      }
    });
  });

  group('A6 — no pay-to-preserve key exists at all', () {
    test('no ARB key name suggests a paid streak-restore feature', () {
      final suspiciousKeyPattern = RegExp(
        r'(buy|purchase|pay|premium|subscri).*streak|streak.*(buy|purchase|pay|premium|subscri)',
        caseSensitive: false,
      );
      final offenders = <String>[
        for (final key in enArb.keys)
          if (!key.startsWith('@') && suspiciousKeyPattern.hasMatch(key)) key,
      ];
      expect(offenders, isEmpty, reason: offenders.join(', '));
    });
  });

  group('VALÓDI-SÉRTÉS PRÓBA — the scan itself catches a reintroduced punitive '
      'string', () {
    test('a simulated regression string trips the same predicate this '
        'test enforces', () {
      const regressed = 'You lost your 30-day streak!';
      final lower = regressed.toLowerCase();
      final tripped =
          bannedEnglishPhrases.any(lower.contains) ||
          bannedEnglishWords.any((pattern) => pattern.hasMatch(lower));
      expect(
        tripped,
        isTrue,
        reason:
            'the banned-pattern scan must catch a reintroduced punitive '
            'string, or this whole test file is a false green',
      );
    });
  });
}

Map<String, dynamic> _loadArb(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('ARB missing at $path');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw StateError('ARB at $path is not a JSON object');
  }
  return decoded;
}
