/// Prints a reproducible quality and resource summary for the golden corpus.
library;

import 'dart:io';

import 'package:strumsight/features/practice_generator/application/service/shadow_plan_generator.dart';

import '../../test/fixtures/practice_planner/golden_profiles.dart';

Future<void> main() async {
  final generator = ShadowPlanGenerator();
  final profiles = goldenProfiles();
  final startedRss = ProcessInfo.currentRss;
  final stopwatch = Stopwatch()..start();
  var hardViolations = 0;
  var activationCalls = 0;
  var persistentWrites = 0;
  var successfulPlans = 0;

  stdout.writeln('Practice plan quality report');
  stdout.writeln('profiles=${profiles.length}');
  for (final profile in profiles) {
    final run = await generator.generate(profile.input);
    final plan = run.result.valueOrNull;
    hardViolations += run.hardViolationCount;
    activationCalls += run.activationCalls;
    persistentWrites += run.persistentWrites;
    if (plan != null) successfulPlans += 1;
    stdout.writeln(
      '${profile.id}: success=${plan != null} '
      'hardViolations=${run.hardViolationCount} '
      'activationCalls=${run.activationCalls} '
      'persistentWrites=${run.persistentWrites}',
    );
  }
  stopwatch.stop();
  final endingRss = ProcessInfo.currentRss;

  stdout.writeln('successfulPlans=$successfulPlans/${profiles.length}');
  stdout.writeln('hardViolations=$hardViolations');
  stdout.writeln('activationCalls=$activationCalls');
  stdout.writeln('persistentWrites=$persistentWrites');
  stdout.writeln('latencyMicros=${stopwatch.elapsedMicroseconds}');
  stdout.writeln('rssDeltaBytes=${endingRss - startedRss}');
}
