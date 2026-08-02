import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/songs/model/setlist.dart';
import 'package:strumsight/features/songs/model/song.dart';

/// E03-R01 — legacy Song/Setlist parity baseline.
///
/// The legacy model (pre-SongDocument V2) lives in
/// [lib/features/songs/model/] and is wired to a SharedPreferences-backed
/// `KeyValueStore` under [StorageKeys.songs] and [StorageKeys.setlists].
/// This test reads the seven self-authored JSON snapshots under
/// `test/fixtures/song_trainer/legacy/` and locks the legacy codec against
/// the values each snapshot was produced from. A reviewer can flip any cell
/// in the `expected` block of a snapshot and turn the corresponding
/// scenario red — the assertions here use exact `equals` (not `closeTo`)
/// for the discrete invariants and `closeTo` only for floating-point
/// durations and beats that are the result of a single BPM division.
///
/// **Scope of this round:** only the *existing* legacy contract is locked.
/// This test never imports `lib/features/song_trainer/` — the V2 boundary
/// is empty by design (E03-R01 §5.1).
const _fixturesDir = 'test/fixtures/song_trainer/legacy';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('$_fixturesDir/$name');
  expect(file.existsSync(), isTrue, reason: 'fixture missing: ${file.path}');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

String _directionToken(StrumDirection? d) => switch (d) {
  StrumDirection.down => 'd',
  StrumDirection.up => 'u',
  null => '-',
};

void _expectSongParity(Map<String, dynamic> fixture) {
  final songJson = fixture['song'] as Map<String, dynamic>;
  final expected = fixture['expected'] as Map<String, dynamic>;

  // JSON round-trip parity — catches schema drift in [Song.fromJson].
  final song = Song.fromJson(songJson);

  final lesson = song.toLesson();
  final analyze = song.toAnalyzeResult();

  // Discrete invariants: exact equality.
  expect(
    lesson.events.length,
    expected['events'],
    reason: '${fixture['fixture']} event count',
  );
  expect(
    lesson.beatsPerBar,
    expected['meter'],
    reason: '${fixture['fixture']} meter (beatsPerBar)',
  );
  expect(
    lesson.chordSequence,
    expected['chordSequence'],
    reason: '${fixture['fixture']} chord sequence',
  );
  expect(
    analyze.downCount,
    expected['downCount'],
    reason: '${fixture['fixture']} down count',
  );
  expect(
    analyze.upCount,
    expected['upCount'],
    reason: '${fixture['fixture']} up count',
  );
  expect(
    analyze.chordSummary,
    expected['chordSummary'],
    reason: '${fixture['fixture']} chord summary',
  );

  // Direction sequence is the deepest parity check — it catches
  // drop-rests, flip-down-up, or 4/4-hardcoded implementations.
  expect(
    lesson.events.map((e) => _directionToken(e.direction)).toList(),
    expected['directionSequence'],
    reason: '${fixture['fixture']} direction sequence',
  );

  // Floating-point invariants: one division per BPM, so closeTo is exact
  // enough — the legacy `_slot` ↔ `_unslot` round-trip has zero loss.
  expect(
    lesson.totalBeats,
    closeTo((expected['totalBeats'] as num).toDouble(), 1e-9),
    reason: '${fixture['fixture']} totalBeats',
  );
  expect(
    analyze.durationSec,
    closeTo((expected['durationSec'] as num).toDouble(), 1e-9),
    reason: '${fixture['fixture']} durationSec',
  );

  // Per-chord beat groups (rest and multi-chord fixtures only).
  final perChord = expected['perChordBeats'];
  if (perChord is Map) {
    final expectedBeats = <String, List<double>>{
      for (final entry in perChord.entries)
        entry.key as String: (entry.value as List)
            .map((b) => (b as num).toDouble())
            .toList(),
    };
    final actual = <String, List<double>>{};
    for (final e in lesson.events) {
      actual.putIfAbsent(e.chord, () => []).add(e.beat);
    }
    expect(
      actual,
      expectedBeats,
      reason: '${fixture['fixture']} per-chord beats',
    );
  }
}

void _expectSetlistParity(Map<String, dynamic> fixture) {
  final expected = fixture['expected'] as Map<String, dynamic>;

  // Build the songbook from the embedded snapshot, then load the setlist.
  final songbook = [
    for (final raw in fixture['songbook'] as List)
      Song.fromJson(raw as Map<String, dynamic>),
  ];
  final setlist = Setlist.fromJson(fixture['setlist'] as Map<String, dynamic>);

  // Order preservation + drop-unresolved semantics.
  expect(
    setlist.resolve(songbook).map((s) => s.id).toList(),
    expected['resolvedOrder'],
    reason: '${fixture['fixture']} resolve order',
  );

  // The duplicate fixture must NOT be silently deduped: both copies survive
  // and the combined lesson plays them back-to-back at the reference tempo.
  final combined = setlist.combine(setlist.resolve(songbook));

  expect(
    combined.events.length,
    expected['events'],
    reason: '${fixture['fixture']} combined event count',
  );
  expect(
    combined.bpm,
    closeTo((expected['bpm'] as num).toDouble(), 1e-9),
    reason: '${fixture['fixture']} combined bpm',
  );
  expect(
    combined.beatsPerBar,
    expected['meter'],
    reason: '${fixture['fixture']} combined meter',
  );
  expect(
    combined.chordSequence,
    expected['chordSequence'],
    reason: '${fixture['fixture']} combined chord sequence',
  );
  expect(
    combined.events.map((e) => _directionToken(e.direction)).toList(),
    expected['directionSequence'],
    reason: '${fixture['fixture']} combined direction sequence',
  );

  // Beat sequence is the deepest parity check for the mixed-bpm fixture:
  // it locks the warp factor exactly, so a flatten-to-common-BPM regression
  // turns the assertion red on the warped song-b events.
  final expectedBeats = [
    for (final b in (expected['beatSequence'] as List)) (b as num).toDouble(),
  ];
  expect(
    combined.events.map((e) => e.beat).toList(),
    closeToEach(expectedBeats, 1e-9),
    reason: '${fixture['fixture']} beat sequence',
  );

  // totalBeats is the sum of warped lengths; floating-point division.
  expect(
    combined.totalBeats,
    closeTo((expected['totalBeats'] as num).toDouble(), 1e-9),
    reason: '${fixture['fixture']} combined totalBeats',
  );

  // Per-song duration (mixed-bpm fixture only): proves each song keeps its
  // own real-time duration at its own tempo.
  final perDuration = expected['perSongDurationSec'];
  if (perDuration is Map) {
    for (final song in songbook) {
      final bpb = song.beatsPerBar;
      final spb = song.bpm > 0 ? 60.0 / song.bpm : 0.5;
      final expectedDur = (perDuration[song.id] as num).toDouble();
      expect(
        song.chords.length * bpb * spb,
        closeTo(expectedDur, 1e-9),
        reason: '${fixture['fixture']} per-song duration ${song.id}',
      );
    }
  }

  // Unresolved-id assertion (missing-song fixture only) — the legacy
  // resolve contract is "silently skip", not "throw".
  final unresolved = expected['unresolvedIds'];
  if (unresolved is List) {
    final missing = setlist.songIds
        .where((id) => !songbook.any((s) => s.id == id))
        .toList();
    expect(missing, unresolved, reason: '${fixture['fixture']} unresolved ids');
  }
}

void main() {
  group('E03-R01 legacy Song parity', () {
    for (final name in const [
      'song_44.json',
      'song_34.json',
      'song_rests.json',
      'song_multiple_chords.json',
    ]) {
      test(name, () {
        _expectSongParity(_loadFixture(name));
      });
    }
  });

  group('E03-R01 legacy Setlist parity', () {
    for (final name in const [
      'setlist_duplicate.json',
      'setlist_missing_song.json',
      'setlist_mixed_bpm.json',
    ]) {
      test(name, () {
        _expectSetlistParity(_loadFixture(name));
      });
    }
  });

  group('E03-R01 rollout guard', () {
    test('songTrainerV2Enabled defaults to false in every environment', () {
      // E03-R01 §5.1: the flag MUST NOT be flipped on implicitly by
      // running outside production. A debug or test build that "happens
      // to enable" the Song Trainer V2 would ship the boundary to anyone
      // who installs a non-prod artifact.
      for (final env in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(env, accountEnabled: false);
        expect(
          flags.songTrainerV2Enabled,
          isFalse,
          reason: 'flag must be OFF in $env',
        );
      }
    });

    test('the default constructor keeps the new flag OFF as well', () {
      const flags = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(flags.songTrainerV2Enabled, isFalse);
    });
  });
}

/// Like `closeTo` for a list, asserting every element is within
/// [epsilon] of the corresponding element.
Matcher closeToEach(List<double> expected, double epsilon) {
  return predicate<List<double>>((actual) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if ((actual[i] - expected[i]).abs() > epsilon) return false;
    }
    return true;
  }, 'list within $epsilon of $expected');
}
