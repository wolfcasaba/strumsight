import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';

bool _aiTutorEnabled(Object flags) {
  final dynamic dynamicFlags = flags;
  return dynamicFlags.aiTutorEnabled as bool;
}

bool _aiTutorCloudEnabled(Object flags) {
  final dynamic dynamicFlags = flags;
  return dynamicFlags.aiTutorCloudEnabled as bool;
}

List<bool> _visionFlags(FeatureFlags flags) => <bool>[
  flags.visionEnabled,
  flags.visionSetupEnabled,
  flags.visionHandTrackingEnabled,
  flags.visionPoseTrackingEnabled,
  flags.visionGuitarGeometryEnabled,
  flags.visionPracticeIntegrationEnabled,
  flags.visionSongIntegrationEnabled,
  flags.visionTutorIntegrationEnabled,
  flags.visionAnalysisIntegrationEnabled,
  flags.visionExperimentalFineFretEnabled,
  flags.visionLabCaptureEnabled,
];

List<bool> _audioAnalysisFlags(FeatureFlags flags) => <bool>[
  flags.audioAnalysisV2Enabled,
  flags.analysisBeatGridEnabled,
  flags.analysisPitchEnabled,
  flags.analysisPreprocessingExperimentalEnabled,
  flags.analysisExperimentalFusionEnabled,
  flags.analysisComparisonEnabled,
];

FeatureFlags _withAiTutorFlags({
  required bool aiTutorEnabled,
  required bool aiTutorCloudEnabled,
}) {
  return Function.apply(FeatureFlags.new, const <Object?>[], <Symbol, Object?>{
        #accountEnabled: false,
        #diagnosticsEnabled: false,
        #labModeAvailable: false,
        #aiTutorEnabled: aiTutorEnabled,
        #aiTutorCloudEnabled: aiTutorCloudEnabled,
      })
      as FeatureFlags;
}

void _expectAiTutorFlagsOff(Object flags) {
  expect(
    () => _aiTutorEnabled(flags),
    returnsNormally,
    reason: 'FeatureFlags must expose aiTutorEnabled.',
  );
  expect(
    () => _aiTutorCloudEnabled(flags),
    returnsNormally,
    reason: 'FeatureFlags must expose aiTutorCloudEnabled.',
  );
  expect(_aiTutorEnabled(flags), isFalse);
  expect(_aiTutorCloudEnabled(flags), isFalse);
}

const _rolloutMarkerBegin = '<!-- capability-rollout-decisions:begin -->';
const _rolloutMarkerEnd = '<!-- capability-rollout-decisions:end -->';
const _rolloutExpectedHeader =
    '| capability_group | flags | classification | a | b | c | d | evidence | resolving |';
const _rolloutClassificationSet = <String>{'BE', 'PREVIEW', 'KI', 'N/A'};

class _RolloutRow {
  _RolloutRow({
    required this.group,
    required this.flags,
    required this.classification,
    required this.resolving,
  });

  final String group;
  final List<String> flags;
  final String classification;
  final String resolving;
}

/// Reads and parses the `capability-rollout-decisions` marker block in
/// `docs/release/capability-rollout.md` as data. Fail-closed: a missing,
/// empty, or header-mismatched block fails the calling test loudly instead
/// of silently yielding zero rows (the L566 silent-pass pattern) — a `for`
/// loop over an empty row list would otherwise vacuously pass A1/A6.
List<_RolloutRow> _parseCapabilityRolloutTable() {
  final text = File('docs/release/capability-rollout.md').readAsStringSync();
  final beginIndex = text.indexOf(_rolloutMarkerBegin);
  final endIndex = text.indexOf(_rolloutMarkerEnd);
  if (beginIndex == -1 || endIndex == -1 || endIndex <= beginIndex) {
    fail(
      'docs/release/capability-rollout.md must contain a well-formed '
      '$_rolloutMarkerBegin ... $_rolloutMarkerEnd block.',
    );
  }
  final lines = text
      .substring(beginIndex + _rolloutMarkerBegin.length, endIndex)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length < 3) {
    fail(
      'capability-rollout-decisions marker block has no '
      'header/separator/data rows.',
    );
  }
  if (lines.first != _rolloutExpectedHeader) {
    fail(
      'capability-rollout-decisions header changed unexpectedly:\n'
      '${lines.first}',
    );
  }
  if (!RegExp(r'^\|(?:-+\|)+$').hasMatch(lines[1])) {
    fail(
      'capability-rollout-decisions table is missing its separator row:\n'
      '${lines[1]}',
    );
  }

  const placeholder = '';
  final rows = <_RolloutRow>[];
  for (final line in lines.skip(2)) {
    final cells = line
        .replaceAll(r'\|', placeholder)
        .split('|')
        .map((cell) => cell.trim().replaceAll(placeholder, '|'))
        .toList();
    if (cells.length != 11) {
      fail(
        'capability-rollout-decisions row has an unexpected column count '
        '(${cells.length}): $line',
      );
    }
    final flags = RegExp(
      r'`(\w+)`',
    ).allMatches(cells[2]).map((m) => m.group(1)!).toList();
    rows.add(
      _RolloutRow(
        group: cells[1],
        flags: flags,
        classification: cells[3],
        resolving: cells[9],
      ),
    );
  }
  if (rows.isEmpty) {
    fail('capability-rollout-decisions table has no data rows.');
  }
  return rows;
}

/// Reads the field names `FeatureFlags.forEnvironment` actually assigns,
/// from its `return FeatureFlags(` call, so the coverage check never drifts
/// from the real flag set — a hardcoded list here could silently miss a
/// newly added flag.
List<String> _forEnvironmentFieldNames() {
  final source = File('lib/app/config/feature_flags.dart').readAsStringSync();
  final returnIndex = source.indexOf('return FeatureFlags(');
  if (returnIndex == -1) {
    fail(
      'lib/app/config/feature_flags.dart: expected a `return '
      'FeatureFlags(` call inside forEnvironment.',
    );
  }
  final closeIndex = source.indexOf('\n    );', returnIndex);
  if (closeIndex == -1) {
    fail('Could not find the closing `);` of the forEnvironment return call.');
  }
  final names = RegExp(r'^\s*(\w+):', multiLine: true)
      .allMatches(source.substring(returnIndex, closeIndex))
      .map((m) => m.group(1)!)
      .toList();
  if (names.isEmpty) {
    fail('No named arguments found in the forEnvironment return call.');
  }
  return names;
}

String _rolloutClassificationToken(String cell) {
  final match = RegExp(
    r'^\*{0,2}(BE|PREVIEW|KI|N/A)\b',
  ).firstMatch(cell.trim());
  return match?.group(1) ?? cell.trim();
}

void main() {
  group('Song Trainer V2 rollout boundary', () {
    test('is enabled in development', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      expect(flags.songTrainerV2Enabled, isTrue);
    });

    test('is enabled in lab', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      expect(flags.songTrainerV2Enabled, isTrue);
    });

    test('remains disabled in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(flags.songTrainerV2Enabled, isFalse);
    });

    test('keeps unrelated rollout flags disabled in every environment', () {
      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );

        expect(flags.aiTutorEnabled, isFalse);
        expect(flags.aiTutorCloudEnabled, isFalse);
        expect(flags.visionEnabled, isFalse);
      }
    });
  });

  group('Adaptive shell feature flag (E15-R02, ADR 0467, A1)', () {
    test('is enabled in development', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      expect(flags.adaptiveShellEnabled, isTrue);
    });

    test('is enabled in lab', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      expect(flags.adaptiveShellEnabled, isTrue);
    });

    test('remains disabled in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(flags.adaptiveShellEnabled, isFalse);
    });
  });

  group('Migrated Learn rollout boundary', () {
    test('is enabled in development', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      expect(flags.migratedLearnEnabled, isTrue);
    });

    test('is enabled in lab', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      expect(flags.migratedLearnEnabled, isTrue);
    });

    test('remains disabled in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(flags.migratedLearnEnabled, isFalse);
    });
  });

  group('AI Tutor feature flags', () {
    test('const constructor defaults both flags to off', () {
      const flags = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );

      _expectAiTutorFlagsOff(flags);
    });

    test('forEnvironment leaves both flags off in every environment', () {
      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );

        _expectAiTutorFlagsOff(flags);
      }
    });

    test('new flags participate in value semantics but not network use', () {
      const defaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(
        () =>
            _withAiTutorFlags(aiTutorEnabled: true, aiTutorCloudEnabled: false),
        returnsNormally,
        reason: 'FeatureFlags must accept both AI Tutor flags.',
      );
      final tutorEnabled = _withAiTutorFlags(
        aiTutorEnabled: true,
        aiTutorCloudEnabled: false,
      );
      final cloudEnabled = _withAiTutorFlags(
        aiTutorEnabled: false,
        aiTutorCloudEnabled: true,
      );
      final tutorEnabledCopy = _withAiTutorFlags(
        aiTutorEnabled: true,
        aiTutorCloudEnabled: false,
      );
      final cloudEnabledCopy = _withAiTutorFlags(
        aiTutorEnabled: false,
        aiTutorCloudEnabled: true,
      );

      expect(tutorEnabled, isNot(defaults));
      expect(cloudEnabled, isNot(defaults));
      expect(tutorEnabledCopy, tutorEnabled);
      expect(tutorEnabledCopy.hashCode, tutorEnabled.hashCode);
      expect(cloudEnabledCopy, cloudEnabled);
      expect(cloudEnabledCopy.hashCode, cloudEnabled.hashCode);
      expect(tutorEnabled.usesNetwork, isFalse);
      expect(cloudEnabled.usesNetwork, isFalse);
      expect(tutorEnabled.toString(), contains('aiTutorEnabled: true'));
      expect(cloudEnabled.toString(), contains('aiTutorCloudEnabled: true'));
    });
  });

  group('Computer Vision feature flags', () {
    test('all eleven flags default to off in every environment', () {
      const constructorDefaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(_visionFlags(constructorDefaults), everyElement(isFalse));

      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );

        expect(
          _visionFlags(flags),
          everyElement(isFalse),
          reason: '$environment must not implicitly enable Computer Vision.',
        );
      }
    });

    test('vision flags are offline and participate in value semantics', () {
      const defaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      const enabled = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        visionEnabled: true,
      );
      const enabledCopy = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        visionEnabled: true,
      );

      expect(enabled, isNot(defaults));
      expect(enabledCopy, enabled);
      expect(enabledCopy.hashCode, enabled.hashCode);
      expect(enabled.usesNetwork, isFalse);
      expect(enabled.toString(), contains('visionEnabled: true'));
    });
  });

  group('Audio Analysis V2 rollout boundary', () {
    test('all audio analysis flags remain off in every environment', () {
      const constructorDefaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(_audioAnalysisFlags(constructorDefaults), everyElement(isFalse));

      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );
        expect(
          _audioAnalysisFlags(flags),
          everyElement(isFalse),
          reason: '$environment must not implicitly enable Audio Analysis V2.',
        );
        expect(flags.toString(), contains('audioAnalysisV2Enabled: false'));
        expect(flags.toString(), contains('analysisBeatGridEnabled: false'));
        expect(flags.toString(), contains('analysisPitchEnabled: false'));
        expect(
          flags.toString(),
          contains('analysisPreprocessingExperimentalEnabled: false'),
        );
        expect(
          flags.toString(),
          contains('analysisExperimentalFusionEnabled: false'),
        );
        expect(flags.toString(), contains('analysisComparisonEnabled: false'));
      }
    });

    test('analysisComparisonEnabled defaults to false and remains off for '
        'every environment', () {
      const constructorDefaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(constructorDefaults.analysisComparisonEnabled, isFalse);

      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );
        expect(
          flags.analysisComparisonEnabled,
          isFalse,
          reason: '$environment must not implicitly enable comparison.',
        );
      }
    });

    test(
      'audio analysis flags participate in value semantics and remain offline',
      () {
        const defaults = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
        );
        const enabled = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          audioAnalysisV2Enabled: true,
          analysisExperimentalFusionEnabled: true,
        );
        const enabledCopy = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          audioAnalysisV2Enabled: true,
          analysisExperimentalFusionEnabled: true,
        );
        expect(enabled, isNot(defaults));
        expect(enabledCopy, enabled);
        expect(enabledCopy.hashCode, enabled.hashCode);
        expect(enabled.hashCode, isNot(defaults.hashCode));
        expect(enabled.usesNetwork, isFalse);
      },
    );
  });

  group('E16-R03 capability rollout — zero flip (ADR 0492)', () {
    // Pins the round's ZERO FLIP outcome as a flag-boolean regression guard:
    // every capability this round evaluated that was `false` before the
    // round stays `false` in every environment (a documented, accepted
    // "zero flip" outcome, brief §0.0.1 R3). The decision table's own
    // structure (A1 coverage/classification, A6 resolving round) is
    // measured separately below, against `docs/release/capability-
    // rollout.md` as data, not against these flag booleans.
    test('the four previously-false capability groups this round evaluated '
        'stay off in every environment: AI Tutor, Planner Assist, Vision, '
        'Audio Analysis V2, Recognition recovery', () {
      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );

        expect(
          flags.aiTutorEnabled,
          isFalse,
          reason:
              '$environment: aiTutorEnabled stays KI — epic-04-completion-'
              'report.md names the ON decision a separate Termék/User call',
        );
        expect(
          flags.plannerAssistEnabled,
          isFalse,
          reason:
              '$environment: plannerAssistEnabled stays KI (no model '
              'integration, separate rollout decision, ADR 0491 D2)',
        );
        expect(
          _visionFlags(flags),
          everyElement(isFalse),
          reason:
              '$environment: Vision stays KI pending HORIZON device '
              'acceptance (docs/sdd/epic-05-completion-report.md)',
        );
        expect(
          _audioAnalysisFlags(flags),
          everyElement(isFalse),
          reason:
              '$environment: Audio Analysis V2 stays KI — Epic 6 '
              'release blockers remain open (ADR 0220)',
        );
        expect(
          flags.recognitionRecoveryEnabled,
          isFalse,
          reason:
              '$environment: recognitionRecoveryEnabled stays KI — no '
              'accepted activation package (docs/eval/'
              'recognition-release-guard.md)',
        );
        expect(flags.recognitionShadowModeEnabled, isFalse);
        expect(flags.newLiveStageEnabled, isFalse);
      }
    });

    // A3 — the two named external-resource branches must never become the
    // nonProd default: cloud Tutor needs the StrumSight backend proxy, and
    // Community needs its dart-define (no default flip either).
    test('aiTutorCloudEnabled and the five Community flags never default on '
        'in any environment (A3 — external resource)', () {
      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );

        expect(
          flags.aiTutorCloudEnabled,
          isFalse,
          reason:
              '$environment: aiTutorCloudEnabled requires the backend '
              'proxy and an open R-PRIV-01 precondition',
        );
        expect(flags.communityEnabled, isFalse, reason: 'communityEnabled');
        expect(
          flags.communityWritesEnabled,
          isFalse,
          reason: 'communityWritesEnabled',
        );
        expect(
          flags.communityMediaEnabled,
          isFalse,
          reason: 'communityMediaEnabled',
        );
        expect(
          flags.communityLeaderboardEnabled,
          isFalse,
          reason: 'communityLeaderboardEnabled',
        );
        expect(
          flags.communityClubsEnabled,
          isFalse,
          reason: 'communityClubsEnabled',
        );
      }
    });

    // A2 — the eight capabilities that were already `nonProd` BEFORE this
    // round stay exactly that: BE in development/lab, off in production.
    // This round confirmed them (docs/release/capability-rollout.md §2) but
    // did not move any of their `forEnvironment` branches.
    test('the eight pre-existing BE capabilities keep their nonProd default '
        '(A2, unchanged by this round)', () {
      for (final environment in [
        AppEnvironment.development,
        AppEnvironment.lab,
      ]) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );
        expect(flags.diagnosticsEnabled, isTrue, reason: '$environment');
        expect(flags.labModeAvailable, isTrue, reason: '$environment');
        expect(flags.practiceEngineV2Enabled, isTrue, reason: '$environment');
        expect(flags.migratedLearnEnabled, isTrue, reason: '$environment');
        expect(
          flags.practiceDetailedHistoryEnabled,
          isTrue,
          reason: '$environment',
        );
        expect(flags.songTrainerV2Enabled, isTrue, reason: '$environment');
        expect(flags.practiceGeneratorEnabled, isTrue, reason: '$environment');
        expect(flags.adaptiveShellEnabled, isTrue, reason: '$environment');
      }

      final production = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );
      expect(production.diagnosticsEnabled, isFalse);
      expect(production.labModeAvailable, isFalse);
      expect(production.practiceEngineV2Enabled, isFalse);
      expect(production.migratedLearnEnabled, isFalse);
      expect(production.practiceDetailedHistoryEnabled, isFalse);
      expect(production.songTrainerV2Enabled, isFalse);
      expect(production.practiceGeneratorEnabled, isFalse);
      expect(production.adaptiveShellEnabled, isFalse);
    });

    // A4 — this round moved no production default at all.
    test('production defaults are byte-identical to every non-production '
        'default check above, i.e. every field this round evaluated stays '
        'off in production too (A4)', () {
      final production = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );
      expect(production.aiTutorEnabled, isFalse);
      expect(production.aiTutorCloudEnabled, isFalse);
      expect(production.plannerAssistEnabled, isFalse);
      expect(_visionFlags(production), everyElement(isFalse));
      expect(_audioAnalysisFlags(production), everyElement(isFalse));
      expect(production.recognitionRecoveryEnabled, isFalse);
      expect(production.recognitionShadowModeEnabled, isFalse);
      expect(production.newLiveStageEnabled, isFalse);
    });

    // A7 — docs/release/capability-rollout.md is the NON-production
    // decision: it must disambiguate itself from ga-scope.md (production/GA)
    // and rollout-decision.md (staged percentage rollout), and it must never
    // assert its own production default (single source of truth stays
    // ga-scope.md, ADR 0492 D2) — read the file as a file, following the
    // test/tooling/rollout_decision_test.dart A5 pattern.
    test('capability-rollout.md disambiguates itself from ga-scope.md and '
        'rollout-decision.md and states no production default of its own '
        '(A7)', () {
      final text = File(
        'docs/release/capability-rollout.md',
      ).readAsStringSync();

      expect(text, contains('NEM-production'));
      expect(text, contains('docs/release/ga-scope.md'));
      expect(text, contains('docs/release/rollout-decision.md'));
      expect(
        text,
        contains('saját állítást nem tesz'),
        reason:
            'must explicitly disclaim making its own production-default '
            'claim (ADR 0492 D2)',
      );
      expect(
        text,
        isNot(contains('production_default')),
        reason:
            'the production_default column lives ONLY in ga-scope.md — '
            'a second occurrence here would be a second source of truth',
      );
      expect(text, contains('ZERO FLIP'));
    });

    // A1 — coverage: every field FeatureFlags.forEnvironment assigns (read
    // from the source, not hardcoded, so a future new flag can't silently
    // drop off the table) must appear exactly once in the decision table's
    // `flags` column — no capability may be missing, duplicated, or a
    // stranger the code doesn't actually have.
    test('A1 — every forEnvironment field appears exactly once in the '
        'decision table', () {
      final expectedFields = _forEnvironmentFieldNames();
      final rows = _parseCapabilityRolloutTable();
      final tableFlags = rows.expand((row) => row.flags).toList();

      final counts = <String, int>{};
      for (final flag in tableFlags) {
        counts[flag] = (counts[flag] ?? 0) + 1;
      }

      final missing = expectedFields
          .where((field) => counts[field] == null)
          .toList();
      final duplicated = counts.entries
          .where((entry) => entry.value > 1)
          .map((entry) => entry.key)
          .toList();
      final unknown = counts.keys
          .where((flag) => !expectedFields.contains(flag))
          .toList();

      expect(
        missing,
        isEmpty,
        reason:
            'forEnvironment field(s) missing from the decision table: '
            '$missing',
      );
      expect(
        duplicated,
        isEmpty,
        reason:
            'decision table lists these flag(s) more than once: '
            '$duplicated',
      );
      expect(
        unknown,
        isEmpty,
        reason:
            'decision table names flag(s) forEnvironment does not '
            'assign: $unknown',
      );
      expect(tableFlags.length, expectedFields.length);
    });

    // A1 — closed classification set: every row's classification must be
    // BE, PREVIEW, KI, or N/A (a leading `**` marker is allowed) — an
    // unrecognized value fails instead of silently passing as "some string".
    test('A1 — every row classification is BE, PREVIEW, KI, or N/A', () {
      final rows = _parseCapabilityRolloutTable();
      final invalid = <String>[];
      for (final row in rows) {
        final token = _rolloutClassificationToken(row.classification);
        if (!_rolloutClassificationSet.contains(token)) {
          invalid.add('${row.group}: "${row.classification}"');
        }
      }
      expect(
        invalid,
        isEmpty,
        reason: 'row(s) with an unrecognized classification: $invalid',
      );
    });

    // A6 — every non-BE, non-N/A row must name either a resolving round
    // (`EXX-RYY`) or a repo-relative path that actually resolves on the
    // tree; a bare "később"/"later"/"TBD"/empty cell fails this check.
    test('A6 — every non-BE row names a resolving round or a real path', () {
      final roundIdPattern = RegExp(r'E\d+-R\d+');
      final pathPattern = RegExp(r'`([\w.\-]+(?:/[\w.\-]+)+)`');
      final rows = _parseCapabilityRolloutTable();
      final unresolved = <String>[];

      for (final row in rows) {
        final token = _rolloutClassificationToken(row.classification);
        if (token == 'BE' || token == 'N/A') {
          continue;
        }
        final hasRoundId = roundIdPattern.hasMatch(row.resolving);
        final hasResolvablePath = pathPattern
            .allMatches(row.resolving)
            .map((m) => m.group(1)!)
            .any((path) => File(path).existsSync());
        if (!hasRoundId && !hasResolvablePath) {
          unresolved.add('${row.group}: "${row.resolving}"');
        }
      }

      expect(
        unresolved,
        isEmpty,
        reason:
            'row(s) without a resolving round-id or an existing '
            'repo-relative path: $unresolved',
      );
    });
  });
}
