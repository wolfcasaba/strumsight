import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

/// SDD §4.3 / ADR 0236 §2 — no analysis-origin ARB string or metric name may
/// imply a hand/finger/instrument-fault/health diagnosis. This pattern may
/// only be WIDENED by a future round, never narrowed (ADR 0236 §2).
final RegExp forbiddenAnalysisClaimPattern = RegExp(
  r'ujj|finger|csukló|wrist|húr zörg|buzz|pengető szög|pick angle|'
  r'nyak görbe|neck bow|helytelen(ül)? (tart|fog)',
  caseSensitive: false,
);

/// ARB key prefixes that originate in the audio-analysis feature (V1 or V2)
/// and therefore fall under the claim-safety guard. Every technique-proxy
/// key uses the `analysisTechnique` prefix (ADR 0236 §1); the pre-existing
/// per-domain metric prefixes are included so the guard covers the whole
/// analysis surface, not only this round's additions — a regex narrowed to
/// just `analysisTechnique` would miss a violation introduced under
/// `pitchMetric*`/`dynamicsMetric*`/etc.
const List<String> analysisArbKeyPrefixes = <String>[
  'analysis',
  'pitchMetric',
  'pitchFeedback',
  'timingMetric',
  'timingFeedback',
  'rhythmMetric',
  'rhythmFeedback',
  'dynamicsMetric',
  'dynamicsFeedback',
  'harmonyMetric',
  'technique',
];

bool isAnalysisArbKey(String key) => analysisArbKeyPrefixes.any(key.startsWith);

/// A key or value naming a forbidden claim is a violation either way — a
/// key like `analysisTechniqueFingerPlacement` implies a finger diagnosis
/// even if its translated value is neutral (review F1).
bool violatesClaimSafety(String key, String value) =>
    forbiddenAnalysisClaimPattern.hasMatch(key) ||
    forbiddenAnalysisClaimPattern.hasMatch(value);

Map<String, String> readFlatArb(String path) {
  final decoded =
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return <String, String>{
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value! as String,
  };
}

void main() {
  group('analysis claim safety (ADR 0236)', () {
    test('no analysis-origin ARB key or metric ID matches a forbidden claim '
        'pattern (hand/finger/instrument-fault/health)', () {
      final offences = <String>[];
      for (final path in <String>[
        'lib/l10n/app_en.arb',
        'lib/l10n/app_hu.arb',
      ]) {
        for (final entry in readFlatArb(path).entries) {
          if (!isAnalysisArbKey(entry.key)) continue;
          if (violatesClaimSafety(entry.key, entry.value)) {
            offences.add('$path: "${entry.key}" -> "${entry.value}"');
          }
        }
      }
      for (final id in AnalysisMetricId.known) {
        if (forbiddenAnalysisClaimPattern.hasMatch(id)) {
          offences.add('AnalysisMetricId: "$id"');
        }
      }
      expect(
        offences,
        isEmpty,
        reason:
            'ADR 0236 §2/§5: analysis ARB strings and metric IDs must '
            'never imply a hand, finger, instrument-fault or health '
            'diagnosis. Widen the pattern, never narrow it. Found:\n'
            '${offences.join('\n')}',
      );
    });

    test('no analysis ARB string uses a forbidden technique/skill/score name '
        '(ADR 0236 §1)', () {
      const forbiddenNames = <String>[
        'Technique score',
        'Cleanliness',
        'Skill',
      ];
      for (final path in <String>[
        'lib/l10n/app_en.arb',
        'lib/l10n/app_hu.arb',
      ]) {
        final entries = readFlatArb(path);
        for (final entry in entries.entries) {
          if (!isAnalysisArbKey(entry.key)) continue;
          for (final name in forbiddenNames) {
            expect(
              entry.value.toLowerCase(),
              isNot(contains(name.toLowerCase())),
              reason: '$path: "${entry.key}" -> "${entry.value}"',
            );
          }
        }
      }
    });

    test('a forbidden analysis-origin ARB key name is rejected even with a '
        'neutral value (regression for review F1 — key-only mutation)', () {
      // Fake, in-memory map only — never written to the real ARB assets.
      // Reproduces the review's mutation: a key naming a forbidden claim
      // ("finger") with a value that itself contains no forbidden term.
      const fakeArbEntries = <String, String>{
        'analysisTechniqueFingerPlacement':
            'A neutral label without a forbidden value',
      };
      final offences = <String>[];
      for (final entry in fakeArbEntries.entries) {
        if (!isAnalysisArbKey(entry.key)) continue;
        if (violatesClaimSafety(entry.key, entry.value)) {
          offences.add('fake: "${entry.key}" -> "${entry.value}"');
        }
      }
      expect(
        offences,
        isNotEmpty,
        reason:
            'The claim-safety guard must reject a forbidden analysis-origin '
            'ARB key name even when its value is neutral (ADR 0236 §2, '
            'review F1).',
      );
    });

    test('every technique-proxy ARB key exists in en and hu', () {
      const keys = <String>[
        'analysisTechniqueChordChangeGap',
        'analysisTechniqueConfidenceCollapseDuration',
        'analysisTechniqueUnexpectedExtraOnsets',
        'analysisTechniqueSustainedNoteDropout',
        'analysisTechniqueAttackInstability',
        'analysisTechniqueDisclaimer',
      ];
      final en = readFlatArb('lib/l10n/app_en.arb');
      final hu = readFlatArb('lib/l10n/app_hu.arb');
      for (final key in keys) {
        expect(en, contains(key), reason: 'en missing $key');
        expect(hu, contains(key), reason: 'hu missing $key');
      }
    });
  });
}
