import 'dart:convert';
import 'dart:io';

String _pitchGrade(Map<String, Object?> fixture, Map<String, Object?> limits) {
  final cents =
      ((fixture['observedMidi'] as num) - (fixture['targetMidi'] as num)) *
          100 +
      (fixture['cents'] as num);
  final error = cents.abs();
  if (error <= (limits['exactCentsInclusive'] as num)) return 'exact';
  if (error <= (limits['nearCentsInclusive'] as num)) return 'near';
  if (error <= (limits['offPitchCentsInclusive'] as num)) return 'offPitch';
  return 'wrongNote';
}

String _onsetGrade(Map<String, Object?> fixture, Map<String, Object?> limits) {
  final compensated =
      (fixture['rawObservedAtUs'] as num) - (fixture['latencyUs'] as num);
  final error = compensated - (fixture['targetStartUs'] as num);
  final early = limits['earlyOnsetMicrosecondsInclusive'] as num;
  final late = limits['lateOnsetMicrosecondsInclusive'] as num;
  if (error < early) return 'early';
  if (error > late) return 'late';
  return 'onTime';
}

void main(List<String> arguments) {
  final manifestPath = arguments.isEmpty
      ? 'test/fixtures/audio/song_trainer/pitch_fixture_manifest.json'
      : arguments.single;
  final manifest =
      jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, Object?>;
  final limits = manifest['thresholds'] as Map<String, Object?>;
  final fixtures = manifest['fixtures'] as List<Object?>;
  var mismatchCount = 0;

  for (final rawFixture in fixtures) {
    final fixture = rawFixture as Map<String, Object?>;
    final expectedCompensated = fixture['expectedCompensatedAtUs'];
    final compensated =
        (fixture['rawObservedAtUs'] as num) - (fixture['latencyUs'] as num);
    final pitch = _pitchGrade(fixture, limits);
    final onset = _onsetGrade(fixture, limits);
    final accepted = fixture['accepted'] != false;
    final expectedPitch = fixture['expectedPitchGrade'] as String;
    final expectedOnset = fixture['expectedOnsetGrade'] as String;
    final isLatencySupported =
        (fixture['latencyUs'] as num) <=
        (limits['maximumObservationLatencyMicrosecondsInclusive'] as num);
    final actualPitch = accepted && isLatencySupported
        ? pitch
        : 'noStablePitch';
    final actualOnset = accepted && isLatencySupported ? onset : 'missed';
    final matches =
        compensated == expectedCompensated &&
        actualPitch == expectedPitch &&
        actualOnset == expectedOnset;
    if (!matches) mismatchCount++;
    stdout.writeln(
      '${fixture['id']}: raw=${fixture['rawObservedAtUs']} '
      'compensated=$compensated pitch=$actualPitch '
      'onset=$actualOnset ${matches ? 'PASS' : 'FAIL'}',
    );
  }
  if (mismatchCount != 0) {
    stderr.writeln('$mismatchCount pitch benchmark rows did not match.');
    exitCode = 1;
  }
}
