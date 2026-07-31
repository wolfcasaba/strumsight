import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// E02-R12 A9 — forrás-mintaőr a presentation rétegre.
///
/// A két képernyő, a mód-kártya, és a Setup controller forrása nem
/// tartalmazhat üzleti logikát. A guard tesztek a fájlokat olvassák —
/// nincs widget-pump, nincs context — így a fájdalmas szabályok (UI ≠
/// pontozás/matchelés) gépi mércék, nem szöveges ígéretek.
void main() {
  final hub = File(
    'lib/features/practice/presentation/screens/practice_hub_screen.dart',
  );
  final setup = File(
    'lib/features/practice/presentation/screens/practice_setup_screen.dart',
  );
  final card = File(
    'lib/features/practice/presentation/widgets/practice_mode_card.dart',
  );
  final controller = File(
    'lib/features/practice/application/practice_setup_controller.dart',
  );

  test('presentation screens exist on disk', () {
    expect(hub.existsSync(), isTrue);
    expect(setup.existsSync(), isTrue);
    expect(card.existsSync(), isTrue);
    expect(controller.existsSync(), isTrue);
  });

  test('Hub does not contain any business-logic symbol', () {
    final src = _stripComments(hub.readAsStringSync());
    expect(_occurrences(src, 'Stopwatch'), 0, reason: 'Hub has no Stopwatch');
    expect(_occurrences(src, 'Timer('), 0, reason: 'Hub has no Timer');
    expect(_occurrences(src, 'matcher'), 0, reason: 'Hub has no matcher');
    expect(_occurrences(src, 'scorer'), 0, reason: 'Hub has no scorer');
  });

  test('Setup does not contain any business-logic symbol', () {
    final src = _stripComments(setup.readAsStringSync());
    expect(_occurrences(src, 'Stopwatch'), 0, reason: 'Setup has no Stopwatch');
    expect(_occurrences(src, 'Timer('), 0, reason: 'Setup has no Timer');
    expect(_occurrences(src, 'matcher'), 0, reason: 'Setup has no matcher');
    expect(_occurrences(src, 'scorer'), 0, reason: 'Setup has no scorer');
  });

  test('Mode card does not contain any business-logic symbol', () {
    final src = _stripComments(card.readAsStringSync());
    expect(_occurrences(src, 'Stopwatch'), 0);
    expect(_occurrences(src, 'Timer('), 0);
    expect(_occurrences(src, 'matcher'), 0);
    expect(_occurrences(src, 'scorer'), 0);
  });

  test('Hub has exactly one DateTime.now( — the injectable default', () {
    final src = _stripComments(hub.readAsStringSync());
    expect(
      _occurrences(src, 'DateTime.now('),
      1,
      reason: 'ADR 0078 §8: Hub has exactly one DateTime.now() in the default',
    );
  });

  test('Setup has zero DateTime.now( occurrences', () {
    final src = _stripComments(setup.readAsStringSync());
    expect(
      _occurrences(src, 'DateTime.now('),
      0,
      reason: 'ADR 0078 §8: Setup never reads the clock',
    );
  });

  test('Mode card has zero DateTime.now( occurrences', () {
    final src = _stripComments(card.readAsStringSync());
    expect(_occurrences(src, 'DateTime.now('), 0);
  });

  test('Presentation files do not import domain/service/', () {
    for (final f in [hub, setup, card]) {
      final src = _stripComments(f.readAsStringSync());
      expect(
        _occurrences(src, 'domain/service/'),
        0,
        reason: '${f.path} imports a service',
      );
    }
  });

  test('Setup controller does not import flutter/material.dart', () {
    final src = _stripComments(controller.readAsStringSync());
    expect(
      _occurrences(src, 'flutter/material.dart'),
      0,
      reason: 'controller stays out of the widget tree',
    );
  });

  test('Setup controller does not reference BuildContext', () {
    final src = _stripComments(controller.readAsStringSync());
    expect(_occurrences(src, 'BuildContext'), 0);
  });
}

int _occurrences(String source, String needle) {
  if (needle.isEmpty) return 0;
  var from = 0;
  var count = 0;
  while (true) {
    final i = source.indexOf(needle, from);
    if (i < 0) return count;
    count++;
    from = i + needle.length;
  }
}

/// Removes Dart comments so the source-only guards do not match the
/// documentation that explicitly names the forbidden symbols. Preserves
/// line numbers of the surviving code (replaced with spaces, not removed,
/// so byte offsets in error messages stay meaningful).
String _stripComments(String source) {
  final buf = StringBuffer();
  var i = 0;
  final n = source.length;
  while (i < n) {
    final ch = source[i];
    final next = i + 1 < n ? source[i + 1] : '';
    if (ch == '/' && next == '/') {
      // Line comment — skip to end of line.
      while (i < n && source[i] != '\n') {
        buf.write(' ');
        i++;
      }
      continue;
    }
    if (ch == '/' && next == '*') {
      // Block comment — skip to matching */, preserving newlines so
      // line numbers don't shift.
      buf.write('  ');
      i += 2;
      while (i + 1 < n && !(source[i] == '*' && source[i + 1] == '/')) {
        buf.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i + 1 < n) {
        buf.write('  ');
        i += 2;
      }
      continue;
    }
    // String literal — copy verbatim; we don't try to parse escapes.
    if (ch == "'" || ch == '"') {
      final quote = ch;
      buf.write(ch);
      i++;
      while (i < n && source[i] != quote) {
        if (source[i] == r'\' && i + 1 < n) {
          buf.write(source[i]);
          buf.write(source[i + 1]);
          i += 2;
        } else {
          buf.write(source[i]);
          i++;
        }
      }
      if (i < n) {
        buf.write(source[i]);
        i++;
      }
      continue;
    }
    buf.write(ch);
    i++;
  }
  return buf.toString();
}
