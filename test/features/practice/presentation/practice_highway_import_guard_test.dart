// E02-R14 — A8 import-guard test.
//
// The new presentation files must not:
//   - import or reference any Learn-internal symbol
//     (Lesson, LessonEvent, LessonScorer, ...)
//   - import the Practice domain 'service/' layer (none exists yet, but
//     the guard pins the boundary so a future violation trips immediately).
//
// The check is a source-only scan — no widget pump, no Dart constants.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final newFiles = <File>[
    File('lib/features/practice/presentation/widgets/practice_highway.dart'),
    File('lib/features/practice/presentation/widgets/practice_feedback.dart'),
    File(
      'lib/features/practice/presentation/widgets/practice_pattern_preview.dart',
    ),
    File('lib/features/practice/presentation/widgets/practice_chord_lane.dart'),
    File('lib/features/practice/presentation/views/strum_pattern_view.dart'),
    File(
      'lib/features/practice/presentation/views/chord_progression_view.dart',
    ),
  ];

  test('all six files exist on disk', () {
    for (final f in newFiles) {
      expect(f.existsSync(), isTrue, reason: '${f.path} must exist');
    }
  });

  test('no Learn-internal symbols are referenced', () {
    const banned = <String>[
      'features/learn/',
      'LessonScorer',
      'LessonEvent',
      'class Lesson',
      'Lesson(', // identifier / constructor call
    ];
    for (final f in newFiles) {
      final src = _stripComments(f.readAsStringSync());
      for (final needle in banned) {
        expect(
          _occurrences(src, needle),
          0,
          reason: '${f.path} must not reference $needle',
        );
      }
    }
  });

  test('no Practice domain service/ import', () {
    for (final f in newFiles) {
      final src = _stripComments(f.readAsStringSync());
      expect(
        _occurrences(src, 'domain/service/'),
        0,
        reason: '${f.path} imports a service',
      );
    }
  });

  test('no scoring / matcher in the widget layer', () {
    const banned = <String>['Scorer(', 'matcher', 'Stopwatch', 'Timer('];
    for (final f in newFiles) {
      final src = _stripComments(f.readAsStringSync());
      for (final needle in banned) {
        expect(
          _occurrences(src, needle),
          0,
          reason: '${f.path} must not contain $needle',
        );
      }
    }
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

/// Strips Dart line and block comments while preserving string literals
/// (so the guard does not match doc-comments that name the forbidden
/// symbols). The shape is copied from the existing presentation guard
/// so the two source-only checks reason identically.
String _stripComments(String source) {
  final buf = StringBuffer();
  var i = 0;
  final n = source.length;
  while (i < n) {
    final ch = source[i];
    final next = i + 1 < n ? source[i + 1] : '';
    if (ch == '/' && next == '/') {
      while (i < n && source[i] != '\n') {
        buf.write(' ');
        i++;
      }
      continue;
    }
    if (ch == '/' && next == '*') {
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
