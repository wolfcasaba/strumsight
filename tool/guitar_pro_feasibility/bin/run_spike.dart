import 'dart:convert';
import 'dart:io';

import 'package:guitar_pro_feasibility/gp_spike.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('Pass one or more local Guitar Pro fixture paths.');
    exitCode = 64;
    return;
  }

  final modulePath = Platform.environment['ALPHATAB_MODULE_PATH'];
  if (modulePath == null || modulePath.isEmpty) {
    stderr.writeln(
      'ALPHATAB_MODULE_PATH must identify an alphaTab Node module.',
    );
    exitCode = 64;
    return;
  }

  final probe = AlphaTabProbe(modulePath: modulePath);
  final reports = <Map<String, Object>>[];
  for (final path in arguments) {
    final outcome = await probe.tryProbe(File(path).uri);
    reports.add(<String, Object>{
      'fixture': path,
      'outcome': outcome is GuitarProProbeResult
          ? outcome.toJson()
          : <String, String>{
              'failure': (outcome as GuitarProProbeFailure).reason,
            },
    });
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(reports));
  if (reports.any(
    (report) =>
        (report['outcome'] as Map<String, Object>).containsKey('failure'),
  )) {
    exitCode = 1;
  }
}
