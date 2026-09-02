// E12-R26 — rollback and disaster-recovery drill: client-side cells.
//
// Acceptance-map (round brief §0.0.1 P1/P6, §6):
//   A3  group 'A3 — kill switch round-trip'
//   A4  group 'A4 — the resolver is stateless: the kill switch takes effect
//       at the NEXT resolve()'
//   A5  group 'A5/A6 — the disaster-recovery drill log is a MACHINE-CHECKED
//       artifact'
//   A6  same group, 'a "Felfedezett runbook-hibák" section exists' test

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/feature_flags/public.dart';

/// Unlike the existing `_FakeSource` (immutable, built once per resolver),
/// this source's opinion can change BETWEEN `resolve()` calls on the SAME
/// resolver instance — the only construction that can falsify a memoizing
/// resolver implementation (round brief §0.0.1 P1: "két külön felépített
/// resolver egy memoizáló implementációt sem tenne pirosra").
class _MutableSource implements FeatureFlagSource {
  _MutableSource([Map<String, bool?> initial = const {}])
    : _values = Map.of(initial);
  final Map<String, bool?> _values;

  void setValue(String key, bool? value) => _values[key] = value;

  @override
  bool? valueFor(String key) => _values[key];
}

class _FakeSource implements FeatureFlagSource {
  _FakeSource([Map<String, bool> values = const {}]) : _values = values;
  final Map<String, bool> _values;

  @override
  bool? valueFor(String key) => _values[key];
}

FeatureFlagDefinition _definitionOf({
  bool failClosedDefault = false,
  String key = 'testFlag',
}) {
  return FeatureFlagDefinition(
    key: key,
    owner: 'lib/features/test',
    risk: FeatureFlagRisk.low,
    failClosedDefault: failClosedDefault,
    killSwitchPath: 'n/a (fixture)',
  );
}

Directory _findProjectRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    final pubspec = File('${candidate.path}/pubspec.yaml');
    final agents = File('${candidate.path}/AGENTS.md');
    if (pubspec.existsSync() && agents.existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not find the StrumSight repository root.');
    }
    candidate = parent;
  }
}

void main() {
  group('A3 — kill switch round-trip (ADR 0446 D7 second half, §0.0.1 P6): '
      'off preserves data, back-on serves the SAME data again — single '
      'resolver instance, single mutated source (not two independently-built '
      'resolvers)', () {
    test('off (emergency wins) → data present but hidden; the SAME source '
        'lifted (round-trip, not a fresh resolver) → local wins → the SAME '
        'data is accessible again, byte-for-byte unchanged', () {
      final userData = <String>['recording-1', 'recording-2', 'recording-3'];
      final originalSnapshot = List<String>.of(userData);

      final mutableEmergency = _MutableSource({'testFlag': false});
      final localSource = _FakeSource({'testFlag': true});
      final resolver = FeatureFlagResolver(
        emergency: mutableEmergency,
        local: localSource,
      );

      final offResolution = resolver.resolve(_definitionOf());
      expect(offResolution.value, isFalse);
      expect(offResolution.origin, FeatureFlagResolutionOrigin.emergencyOff);
      expect(
        userData,
        originalSnapshot,
        reason: 'kikapcsolás nem törli/mutálja az adatot',
      );

      // The round-trip: the SAME resolver, the SAME underlying source,
      // whose opinion is lifted between calls — not a second resolver
      // built fresh with a different configuration.
      mutableEmergency.setValue('testFlag', null);

      final onResolution = resolver.resolve(_definitionOf());
      expect(onResolution.value, isTrue);
      expect(onResolution.origin, FeatureFlagResolutionOrigin.local);
      expect(
        userData,
        originalSnapshot,
        reason:
            'visszakapcsolás után UGYANAZ az adat érhető el — nem '
            'újragenerált, nem részleges',
      );
    });
  });

  group(
    'A4 — the resolver is stateless: the emergency kill switch takes effect '
    'at the NEXT resolve(), not after any elapsed time (§0.0.1 P1 revised — '
    'A4 premise: no flag cache exists, elavulási ablak = 0 resolutions). '
    'Küszöb-cellahármas a feloldás-INDEXEN, INKLUZÍV határral, EGYETLEN '
    'resolver-példányon, hívások között változó fake forrással.',
    () {
      test('k-1 (last resolve before the flip) = OLD (on); k (first resolve '
          'after, inclusive boundary) = NEW (off); k+1 = NEW (off) — a '
          'memoizing resolver would keep returning OLD at k and fail this '
          'cell', () {
        final mutableEmergency = _MutableSource();
        final localSource = _FakeSource({'testFlag': true});
        final resolver = FeatureFlagResolver(
          emergency: mutableEmergency,
          local: localSource,
        );

        // k-1: the last resolve() before the vész-kikapcsolás lands.
        final beforeFlip = resolver.resolve(_definitionOf());
        expect(beforeFlip.value, isTrue);
        expect(beforeFlip.origin, FeatureFlagResolutionOrigin.local);

        // The kill switch lands: the SAME source's opinion changes.
        mutableEmergency.setValue('testFlag', false);

        // k: the FIRST resolve() after the flip already sees it — the
        // inclusive boundary the brief specifies.
        final atFlip = resolver.resolve(_definitionOf());
        expect(atFlip.value, isFalse);
        expect(atFlip.origin, FeatureFlagResolutionOrigin.emergencyOff);

        // k+1: every further resolve() keeps seeing the new value.
        final afterFlip = resolver.resolve(_definitionOf());
        expect(afterFlip.value, isFalse);
        expect(afterFlip.origin, FeatureFlagResolutionOrigin.emergencyOff);
      });
    },
  );

  group('A5/A6 — the disaster-recovery drill log is a MACHINE-CHECKED artifact, '
      'not a prose promise (§0.0.1 P5)', () {
    final drillFile = File(
      '${_findProjectRoot().path}/docs/operations/disaster-recovery-drill.md',
    );

    test('the drill log file exists', () {
      expect(
        drillFile.existsSync(),
        isTrue,
        reason:
            'docs/operations/disaster-recovery-drill.md must exist — '
            'the round §4.4 deliverable',
      );
    });

    final content = drillFile.existsSync() ? drillFile.readAsStringSync() : '';
    final durationPattern = RegExp(r'\d+(\.\d+)?\s*(s|ms)\b');
    final estimatePattern = RegExp(
      r'(kb\.|~|approx|becsült|körülbelül)',
      caseSensitive: false,
    );
    final stepRowPattern = RegExp(r'^\|\s*\d+\s*\|');

    test('A5(a): no documented step uses an estimate marker (kb., ~, approx, '
        'becsült, körülbelül) — becsült idő NEM elfogadható (brief §5.1)', () {
      final offenders = content
          .split('\n')
          .where((line) => estimatePattern.hasMatch(line))
          .toList();
      expect(
        offenders,
        isEmpty,
        reason: 'estimation marker(s) found:\n${offenders.join('\n')}',
      );
    });

    test('A5(b): every documented drill step row carries a strict numeric '
        'duration (`\\d+(\\.\\d+)?\\s*(s|ms)`) — the "| # | ... |" step-table '
        'convention', () {
      final stepRows = content
          .split('\n')
          .where((line) => stepRowPattern.hasMatch(line))
          .toList();
      expect(
        stepRows,
        isNotEmpty,
        reason:
            'no step rows found — the drill log must record each step '
            'as a "| <#> | ... | <measured duration> | ... |" table row',
      );
      for (final row in stepRows) {
        expect(
          durationPattern.hasMatch(row),
          isTrue,
          reason: 'step row has no strict numeric duration: $row',
        );
      }
    });

    test('A6: the log has a "Felfedezett runbook-hibák" section (stated '
        'explicitly even when empty — "nem találtunk" must be said, not '
        'omitted)', () {
      expect(
        content,
        contains(RegExp('Felfedezett runbook-hibák', caseSensitive: false)),
      );
    });
  });
}
