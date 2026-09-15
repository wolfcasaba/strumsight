import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Throwaway diagnostic: prints `dart format` line diffs for every file
/// under diag/ so the CI log names the exact shapes the formatter wants.
void main() {
  test('dump format diffs', () async {
    final files =
        Directory('diag')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final dart = _dartExecutable();
    for (final file in files) {
      final original = file.readAsStringSync().split('\n');
      final result = await Process.run(dart, [
        'format',
        '--output=show',
        '--summary=none',
        file.path,
      ]);
      if (result.exitCode != 0) {
        print('!!! ${file.path}: exit ${result.exitCode}\n${result.stderr}');
        continue;
      }
      final formatted = (result.stdout as String).split('\n');
      final diff = _unifiedDiff(original, formatted);
      print('=== DIFF ${file.path} (${diff.isEmpty ? "clean" : "changed"})');
      for (final line in diff) {
        print(line);
      }
    }
  });
}

String _dartExecutable() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && File('$root/bin/dart').existsSync()) {
    return '$root/bin/dart';
  }
  return 'dart';
}

List<String> _unifiedDiff(List<String> a, List<String> b, {int context = 2}) {
  final n = a.length;
  final m = b.length;
  // LCS table on lines (files are a few thousand lines at most).
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] > lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  // Build an edit script: ' ' equal, '-' removed (from a), '+' added (from b).
  final ops = <(String, String, int, int)>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      ops.add((' ', a[i], i, j));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      ops.add(('-', a[i], i, j));
      i++;
    } else {
      ops.add(('+', b[j], i, j));
      j++;
    }
  }
  while (i < n) {
    ops.add(('-', a[i], i, j));
    i++;
  }
  while (j < m) {
    ops.add(('+', b[j], i, j));
    j++;
  }
  final out = <String>[];
  var k = 0;
  while (k < ops.length) {
    if (ops[k].$1 == ' ') {
      k++;
      continue;
    }
    // Hunk: from k back `context`, forward until `context` equal lines pass.
    var start = k - context;
    if (start < 0) start = 0;
    var end = k;
    var equalRun = 0;
    while (end < ops.length && equalRun < context) {
      if (ops[end].$1 == ' ') {
        equalRun++;
      } else {
        equalRun = 0;
      }
      end++;
    }
    out.add('@@ a:${ops[start].$3 + 1} b:${ops[start].$4 + 1} @@');
    for (var x = start; x < end; x++) {
      out.add('${ops[x].$1}${ops[x].$2}');
    }
    k = end;
  }
  return out;
}
