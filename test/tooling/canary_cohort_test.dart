// Open Beta canary-cohort gate (E12-R29, round brief §0.0 P1-P8, §6 A1/A5/A6).
//
// Pure-Dart parsing/consistency test — no python tool is added (none is on
// this round's allowed_paths; the brief §0.0 P6 explicitly wants the
// document parsed directly in Dart, the same split
// `test/tooling/beta_profile_test.dart`'s A5/A6 groups already use for
// `closed-beta-launch.md`). Every parse step is FAIL-CLOSED (§0.0 P6,
// L571/L575): a missing marker, fenced block, or section throws instead of
// being silently skipped — the group below proves that with temp-fixture
// mutation probes, precedent `test/tooling/ga_scope_test.dart`'s `_tempCopy`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _launchDoc = 'docs/beta/open-beta-launch.md';
const _capacityReview = 'docs/operations/capacity-review.md';
const _cohortProfiles = 'docs/beta/cohort-profiles.yaml';
const _authPy = 'backend/app/routers/auth.py';
const _registry = 'lib/core/feature_flags/feature_flag_registry.dart';

const _canaryBegin = '<!-- canary-cohort-profile:begin -->';
const _canaryEnd = '<!-- canary-cohort-profile:end -->';
const _humanGateBegin = '<!-- human-gate:begin -->';
const _humanGateEnd = '<!-- human-gate:end -->';

/// Writes [contents] to a fresh file inside a fresh temp dir and returns
/// both so callers can `addTearDown` the directory. Precedent:
/// `test/tooling/ga_scope_test.dart:26-32`.
({Directory dir, File file}) _tempCopy(String name, String contents) {
  final dir = Directory.systemTemp.createTempSync('strumsight_canary_cohort_');
  final file = File('${dir.path}/$name')..writeAsStringSync(contents);
  return (dir: dir, file: file);
}

// ---------------------------------------------------------------------------
// Marker extraction — fail-closed (§0.0 P6): a missing begin/end pair throws
// a FormatException, it never returns an empty/partial result silently.
// ---------------------------------------------------------------------------

String _extractMarked(
  String text, {
  required String begin,
  required String end,
}) {
  final beginIndex = text.indexOf(begin);
  final endIndex = text.indexOf(end);
  if (beginIndex == -1 || endIndex == -1 || endIndex < beginIndex) {
    throw FormatException('markers $begin / $end not found (or out of order)');
  }
  return text.substring(beginIndex + begin.length, endIndex);
}

String _extractHumanGate(String docText) =>
    _extractMarked(docText, begin: _humanGateBegin, end: _humanGateEnd);

// ---------------------------------------------------------------------------
// Canary-profile parsing (§0.0 P6) — the machine-readable block inside
// open-beta-launch.md.
// ---------------------------------------------------------------------------

class CanaryProfile {
  const CanaryProfile({required this.maxTesters, required this.flags});
  final int maxTesters;
  final Map<String, bool> flags;
}

CanaryProfile parseCanaryProfile(String docText) {
  final block = _extractMarked(docText, begin: _canaryBegin, end: _canaryEnd);
  final fenceMatch = RegExp(
    r'```yaml\n(.*?)\n```',
    dotAll: true,
  ).firstMatch(block);
  if (fenceMatch == null) {
    throw FormatException('no ```yaml fenced block inside the canary markers');
  }
  final yaml = fenceMatch.group(1)!;

  final maxTestersMatch = RegExp(
    r'^maxTesters:\s*(\d+)\s*$',
    multiLine: true,
  ).firstMatch(yaml);
  if (maxTestersMatch == null) {
    throw FormatException('no maxTesters: line inside the canary yaml block');
  }

  final flagsIndex = yaml.indexOf('flags:');
  if (flagsIndex == -1) {
    throw FormatException('no flags: section inside the canary yaml block');
  }
  final flagsSection = yaml.substring(flagsIndex);
  final flagMatches = RegExp(
    r'^  ([a-zA-Z0-9]+):\s*(true|false)\s*$',
    multiLine: true,
  ).allMatches(flagsSection);
  final flags = <String, bool>{
    for (final m in flagMatches) m.group(1)!: m.group(2) == 'true',
  };
  if (flags.isEmpty) {
    throw FormatException('flags: section has no key: value entries');
  }

  return CanaryProfile(
    maxTesters: int.parse(maxTestersMatch.group(1)!),
    flags: flags,
  );
}

// ---------------------------------------------------------------------------
// cohort-profiles.yaml parsing — the STABLE cohorts (internal / closed_beta).
// Read-only: this file is in the round's tilos zóna, never written to.
// ---------------------------------------------------------------------------

String _cohortBlock(String yamlText, String cohortId) {
  final idMarker = '- id: $cohortId';
  final start = yamlText.indexOf(idMarker);
  if (start == -1) {
    throw FormatException('cohort $cohortId not found in $_cohortProfiles');
  }
  final nextCohort = RegExp(
    r'\n  - id: ',
  ).allMatches(yamlText, start + idMarker.length);
  final end = nextCohort.isEmpty ? yamlText.length : nextCohort.first.start;
  return yamlText.substring(start, end);
}

Map<String, bool> _cohortFlags(String yamlText, String cohortId) {
  final block = _cohortBlock(yamlText, cohortId);
  final flagsIndex = block.indexOf('flags:');
  if (flagsIndex == -1) {
    throw FormatException('cohort $cohortId has no flags: section');
  }
  final flagsSection = block.substring(flagsIndex);
  final matches = RegExp(
    r'^      ([a-zA-Z0-9]+):\s*(true|false)\s*$',
    multiLine: true,
  ).allMatches(flagsSection);
  final flags = <String, bool>{
    for (final m in matches) m.group(1)!: m.group(2) == 'true',
  };
  if (flags.isEmpty) {
    throw FormatException('cohort $cohortId flags: section has no entries');
  }
  return flags;
}

int _cohortMaxTesters(String yamlText, String cohortId) {
  final block = _cohortBlock(yamlText, cohortId);
  final match = RegExp(
    r'^    maxTesters:\s*(\d+)\s*$',
    multiLine: true,
  ).firstMatch(block);
  if (match == null) {
    throw FormatException('cohort $cohortId has no maxTesters: line');
  }
  return int.parse(match.group(1)!);
}

// The known-good baseline for the two STABLE cohorts, transcribed from
// `docs/beta/cohort-profiles.yaml` as shipped by E12-R27/R28. A5 measures
// that these values never move — this round never writes that file (tilos
// zóna), so any drift here can only come from a FUTURE round (or, in the
// mutation probe below, a synthetic fixture standing in for one).
const _internalBaseline = <String, bool>{
  'accountEnabled': false,
  'diagnosticsEnabled': false,
  'labModeAvailable': true,
  'practiceEngineV2Enabled': true,
  'migratedLearnEnabled': true,
  'practiceDetailedHistoryEnabled': true,
  'songTrainerV2Enabled': false,
  'aiTutorEnabled': false,
  'aiTutorCloudEnabled': false,
  'visionEnabled': false,
  'visionLabCaptureEnabled': false,
  'audioAnalysisV2Enabled': true,
  'communityEnabled': false,
  'communityWritesEnabled': false,
  'communityMediaEnabled': false,
  'adaptiveShellEnabled': true,
};

const _closedBetaBaseline = <String, bool>{
  'accountEnabled': false,
  'diagnosticsEnabled': false,
  'labModeAvailable': true,
  'practiceEngineV2Enabled': true,
  'migratedLearnEnabled': false,
  'practiceDetailedHistoryEnabled': false,
  'songTrainerV2Enabled': false,
  'aiTutorEnabled': false,
  'aiTutorCloudEnabled': false,
  'visionEnabled': false,
  'visionLabCaptureEnabled': false,
  'audioAnalysisV2Enabled': false,
  'communityEnabled': false,
  'communityWritesEnabled': false,
  'communityMediaEnabled': false,
  'adaptiveShellEnabled': false,
};

// ---------------------------------------------------------------------------
// A1 — cohort-ceiling consistency: capacity-review.md's marker, the canary
// block's maxTesters, and a fresh recomputation from the measured backend
// source constants must all agree.
// ---------------------------------------------------------------------------

int _grepInt(String path, RegExp pattern, {required String label}) {
  final text = File(path).readAsStringSync();
  final match = pattern.firstMatch(text);
  if (match == null) {
    throw FormatException('$label not found in $path');
  }
  return int.parse(match.group(1)!);
}

/// Returns a list of consistency problems (empty == ok). Deliberately does
/// NOT catch parse exceptions from its callees — a missing marker/section
/// must propagate as a thrown error (fail-closed), not degrade into a
/// "problem string" that a caller could accidentally treat as a soft
/// warning.
List<String> ceilingConsistencyProblems({
  required String authPyPath,
  required String cohortProfilesPath,
  required String capacityReviewPath,
  required String launchDocPath,
}) {
  final problems = <String>[];

  final loginMax = _grepInt(
    authPyPath,
    RegExp(r'login_limiter = RateLimiter\(max_attempts=(\d+)'),
    label: 'login_limiter.max_attempts',
  );
  final registerMax = _grepInt(
    authPyPath,
    RegExp(r'register_limiter = RateLimiter\(max_attempts=(\d+)'),
    label: 'register_limiter.max_attempts',
  );
  final cohortText = File(cohortProfilesPath).readAsStringSync();
  final closedBetaMax = _cohortMaxTesters(cohortText, 'closed_beta');

  if ((closedBetaMax * registerMax) % loginMax != 0) {
    problems.add(
      'formula does not divide evenly: $closedBetaMax * $registerMax / '
      '$loginMax — the ceiling arithmetic needs re-deriving, not truncating',
    );
    return problems;
  }
  final computed = (closedBetaMax * registerMax) ~/ loginMax;

  final reviewCeiling = _grepInt(
    capacityReviewPath,
    RegExp(r'<!-- canary-max-testers: (\d+) -->'),
    label: 'canary-max-testers marker',
  );
  if (reviewCeiling != computed) {
    problems.add(
      'capacity-review.md marker ($reviewCeiling) != freshly computed '
      'ceiling ($computed)',
    );
  }

  final launchText = File(launchDocPath).readAsStringSync();
  final canary = parseCanaryProfile(launchText);
  if (canary.maxTesters != computed) {
    problems.add(
      'open-beta-launch.md canary maxTesters (${canary.maxTesters}) != '
      'freshly computed ceiling ($computed)',
    );
  }

  return problems;
}

// ---------------------------------------------------------------------------
// P7 — every canary flag key must exist in the measured 40-entry catalog.
// ---------------------------------------------------------------------------

Set<String> _registryKeys(String text) => RegExp(
  r"key:\s*'([a-zA-Z0-9]+)'",
).allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  group('A1 — the cohort ceiling is consistent across capacity-review.md, '
      'open-beta-launch.md, and the measured source constants', () {
    test('the real tree has no consistency problems', () {
      final problems = ceilingConsistencyProblems(
        authPyPath: _authPy,
        cohortProfilesPath: _cohortProfiles,
        capacityReviewPath: _capacityReview,
        launchDocPath: _launchDoc,
      );
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('sanity: the ceiling is not a round, unexplained number — it '
        'recomputes from three cited measured constants', () {
      final loginMax = _grepInt(
        _authPy,
        RegExp(r'login_limiter = RateLimiter\(max_attempts=(\d+)'),
        label: 'login_limiter.max_attempts',
      );
      final registerMax = _grepInt(
        _authPy,
        RegExp(r'register_limiter = RateLimiter\(max_attempts=(\d+)'),
        label: 'register_limiter.max_attempts',
      );
      final cohortText = File(_cohortProfiles).readAsStringSync();
      final closedBetaMax = _cohortMaxTesters(cohortText, 'closed_beta');
      expect(loginMax, greaterThan(0));
      expect(registerMax, greaterThan(0));
      expect(closedBetaMax, greaterThan(0));
      expect((closedBetaMax * registerMax) ~/ loginMax, 25);
    });

    test('mutation probe: a capacity-review.md marker that disagrees with '
        'the recomputed ceiling is a non-empty problem list', () {
      final reviewText = File(_capacityReview).readAsStringSync();
      final mangled = reviewText.replaceFirst(
        '<!-- canary-max-testers: 25 -->',
        '<!-- canary-max-testers: 999 -->',
      );
      expect(mangled, isNot(reviewText));
      final fixture = _tempCopy('capacity-review.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final problems = ceilingConsistencyProblems(
        authPyPath: _authPy,
        cohortProfilesPath: _cohortProfiles,
        capacityReviewPath: fixture.file.path,
        launchDocPath: _launchDoc,
      );
      expect(problems, isNotEmpty);
      expect(problems.join(), contains('999'));
    });

    test(
      'mutation probe: an open-beta-launch.md canary maxTesters that '
      'disagrees with the recomputed ceiling is a non-empty problem list',
      () {
        final launchText = File(_launchDoc).readAsStringSync();
        final mangled = launchText.replaceFirst(
          'maxTesters: 25',
          'maxTesters: 999',
        );
        expect(mangled, isNot(launchText));
        final fixture = _tempCopy('open-beta-launch.md', mangled);
        addTearDown(() => fixture.dir.deleteSync(recursive: true));

        final problems = ceilingConsistencyProblems(
          authPyPath: _authPy,
          cohortProfilesPath: _cohortProfiles,
          capacityReviewPath: _capacityReview,
          launchDocPath: fixture.file.path,
        );
        expect(problems, isNotEmpty);
        expect(problems.join(), contains('999'));
      },
    );
  });

  group('A5 — the canary flag profile is isolated: the stable cohorts keep '
      'their exact shipped values', () {
    test('the real tree — internal and closed_beta match the E12-R27/R28 '
        'baseline exactly', () {
      final cohortText = File(_cohortProfiles).readAsStringSync();
      expect(_cohortFlags(cohortText, 'internal'), _internalBaseline);
      expect(_cohortFlags(cohortText, 'closed_beta'), _closedBetaBaseline);
    });

    test('valódi-sértés próba (KÖTELEZŐ, §10) — flipping closed_beta\'s '
        'migratedLearnEnabled to match the canary profile\'s value (a '
        'simulated leak) is caught: the parsed flags no longer match the '
        'baseline', () {
      final cohortText = File(_cohortProfiles).readAsStringSync();
      final canaryText = File(_launchDoc).readAsStringSync();
      final canary = parseCanaryProfile(canaryText);
      // The canary profile turns migratedLearnEnabled ON; closed_beta ships
      // it OFF. Simulate the canary "leaking" into the stable cohort by
      // flipping closed_beta's line to the canary's value.
      expect(canary.flags['migratedLearnEnabled'], isTrue);
      expect(_closedBetaBaseline['migratedLearnEnabled'], isFalse);

      final mangled = cohortText.replaceFirst(
        'migratedLearnEnabled: false',
        'migratedLearnEnabled: true',
      );
      expect(mangled, isNot(cohortText));
      final fixture = _tempCopy('cohort-profiles.yaml', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final leaked = _cohortFlags(
        fixture.file.readAsStringSync(),
        'closed_beta',
      );
      // A5 goes RED here: the leaked profile no longer matches the baseline.
      expect(leaked, isNot(_closedBetaBaseline));
      expect(leaked['migratedLearnEnabled'], isTrue);
    });
  });

  group('A6 — the document states the Open Beta canary has NOT launched '
      'and opening it is a human decision', () {
    test('the real document carries the required framing and no past-tense '
        'launch claim', () {
      final text = File(_launchDoc).readAsStringSync();
      final gate = _extractHumanGate(text).toLowerCase();

      expect(gate, contains('has not launched'));
      expect(gate, contains('human decision'));

      final lower = text.toLowerCase();
      const bannedPhrases = [
        'the canary has launched',
        'canary launched',
        'testers invited',
        'testers have been invited',
        'cohort opened',
        'cohort has been opened',
        'a canary elindult',
        'tesztelők meghívva',
      ];
      for (final phrase in bannedPhrases) {
        expect(
          lower,
          isNot(contains(phrase)),
          reason: 'past-tense launch claim found: "$phrase"',
        );
      }
    });
  });

  group('P6 (§0.0) — fail-closed parsing: a missing canary block / flags '
      'table / human-gate marker turns the cell RED, never a silent skip '
      '(L571/L575)', () {
    test('missing canary begin/end markers throws, it does not return an '
        'empty profile', () {
      final text = File(_launchDoc).readAsStringSync();
      final withoutMarkers = text
          .replaceAll(_canaryBegin, '')
          .replaceAll(_canaryEnd, '');
      expect(withoutMarkers, isNot(contains(_canaryBegin)));
      expect(() => parseCanaryProfile(withoutMarkers), throwsFormatException);
    });

    test('a canary block with the ```yaml fence stripped throws', () {
      final text = File(_launchDoc).readAsStringSync();
      final block = _extractMarked(text, begin: _canaryBegin, end: _canaryEnd);
      final withoutFence = text.replaceFirst(
        block,
        block.replaceAll('```yaml', '').replaceAll('```', ''),
      );
      expect(() => parseCanaryProfile(withoutFence), throwsFormatException);
    });

    test('a canary yaml block with no flags: section throws', () {
      final text = File(_launchDoc).readAsStringSync();
      final canary = parseCanaryProfile(text);
      expect(canary.flags, isNotEmpty); // sanity: real tree parses fine
      final block = _extractMarked(text, begin: _canaryBegin, end: _canaryEnd);
      final flagsLineIndex = block.indexOf('\nflags:');
      expect(flagsLineIndex, isNot(-1));
      final truncatedBlock = block.substring(0, flagsLineIndex) + '\n```';
      final mangled = text.replaceFirst(block, truncatedBlock);
      expect(() => parseCanaryProfile(mangled), throwsFormatException);
    });

    test('missing human-gate markers throws, it does not return empty '
        'text silently mistaken for "nothing to check"', () {
      final text = File(_launchDoc).readAsStringSync();
      final withoutMarkers = text
          .replaceAll(_humanGateBegin, '')
          .replaceAll(_humanGateEnd, '');
      expect(() => _extractHumanGate(withoutMarkers), throwsFormatException);
    });

    test('missing capacity-review.md ceiling marker throws (not a silent '
        '0)', () {
      final reviewText = File(_capacityReview).readAsStringSync();
      final mangled = reviewText.replaceFirst(
        '<!-- canary-max-testers: 25 -->',
        '',
      );
      expect(mangled, isNot(reviewText));
      final fixture = _tempCopy('capacity-review.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      expect(
        () => ceilingConsistencyProblems(
          authPyPath: _authPy,
          cohortProfilesPath: _cohortProfiles,
          capacityReviewPath: fixture.file.path,
          launchDocPath: _launchDoc,
        ),
        throwsFormatException,
      );
    });
  });

  group('P7 (§0.0) — every canary flag key exists in the measured '
      'feature-flag registry', () {
    test('the real tree — every canary flag key is a real registry key', () {
      final registryText = File(_registry).readAsStringSync();
      final keys = _registryKeys(registryText);
      expect(keys.length, greaterThanOrEqualTo(40));

      final canary = parseCanaryProfile(File(_launchDoc).readAsStringSync());
      final unknown = canary.flags.keys
          .where((k) => !keys.contains(k))
          .toList();
      expect(unknown, isEmpty, reason: 'invented flag key(s): $unknown');
    });

    test('mutation probe: a fabricated flag key in a temp copy is flagged '
        'as unknown', () {
      final launchText = File(_launchDoc).readAsStringSync();
      final mangled = launchText.replaceFirst(
        'adaptiveShellEnabled: true',
        'adaptiveShellEnabledTypo: true',
      );
      expect(mangled, isNot(launchText));
      final fixture = _tempCopy('open-beta-launch.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final registryText = File(_registry).readAsStringSync();
      final keys = _registryKeys(registryText);
      final canary = parseCanaryProfile(fixture.file.readAsStringSync());
      final unknown = canary.flags.keys
          .where((k) => !keys.contains(k))
          .toList();
      expect(unknown, contains('adaptiveShellEnabledTypo'));
    });
  });
}
