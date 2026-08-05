import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';

void main() {
  group('Skill taxonomy', () {
    test('exposes the versioned initial skill manifest', () {
      final taxonomy = SkillTaxonomy.initial;

      expect(taxonomy.schemaVersion, 1);
      expect(
        taxonomy.nodes.map((node) => node.id.value),
        equals(<String>[
          'rhythm.pulse',
          'rhythm.onBeatAccuracy',
          'rhythm.offBeatAccuracy',
          'rhythm.subdivisionEighth',
          'rhythm.subdivisionSixteenth',
          'strum.downStroke',
          'strum.upStroke',
          'strum.directionPattern',
          'chord.shapeClarity',
          'chord.changeSpeed',
          'chord.progressionAccuracy',
          'chord.barreFoundation',
          'pitch.singleNoteAccuracy',
          'pitch.noteDuration',
          'song.sectionConsistency',
          'song.fullRunConsistency',
          'practice.consistency',
          'practice.focus',
        ]),
      );
    });

    test('models the rhythm prerequisite chain explicitly', () {
      final taxonomy = SkillTaxonomy.initial;

      expect(
        taxonomy.nodeFor(SkillId('rhythm.onBeatAccuracy'))?.prerequisiteIds,
        equals(<SkillId>[SkillId('rhythm.pulse')]),
      );
      expect(
        taxonomy
            .nodeFor(SkillId('rhythm.subdivisionSixteenth'))
            ?.prerequisiteIds,
        equals(<SkillId>[SkillId('rhythm.offBeatAccuracy')]),
      );
    });

    test('keeps taxonomy and prerequisite lists immutable', () {
      final taxonomy = SkillTaxonomy.initial;
      final node = taxonomy.nodeFor(SkillId('rhythm.onBeatAccuracy'))!;

      expect(() => taxonomy.nodes.add(node), throwsUnsupportedError);
      expect(
        () => node.prerequisiteIds.add(SkillId('rhythm.pulse')),
        throwsUnsupportedError,
      );
    });

    test('uses normalized value semantics for skill IDs and nodes', () {
      final firstId = SkillId(' rhythm.pulse ');
      final secondId = SkillId('rhythm.pulse');
      final firstNode = SkillNode(
        id: firstId,
        prerequisiteIds: <SkillId>[SkillId('practice.consistency')],
      );
      final secondNode = SkillNode(
        id: secondId,
        prerequisiteIds: <SkillId>[SkillId('practice.consistency')],
      );

      expect(firstId, equals(secondId));
      expect(firstId.hashCode, secondId.hashCode);
      expect(firstId.toString(), 'SkillId(rhythm.pulse)');
      expect(firstNode, equals(secondNode));
      expect(firstNode.hashCode, secondNode.hashCode);
      expect(SkillTaxonomy.initial.nodeFor(SkillId('not.in.taxonomy')), isNull);
    });

    test('rejects invalid skill IDs and invalid taxonomy structures', () {
      expect(
        () => SkillId(' '),
        throwsA(
          isA<SkillIdValidationException>().having(
            (error) => error.code,
            'code',
            SkillIdValidationCode.empty,
          ),
        ),
      );
      expect(
        () => SkillId('s' * (maxSkillIdLength + 1)),
        throwsA(
          isA<SkillIdValidationException>().having(
            (error) => error.code,
            'code',
            SkillIdValidationCode.tooLong,
          ),
        ),
      );
      expect(
        () => SkillTaxonomy(schemaVersion: 0, nodes: const <SkillNode>[]),
        throwsA(
          isA<SkillTaxonomyValidationException>().having(
            (error) => error.code,
            'code',
            SkillTaxonomyValidationCode.schemaVersionOutOfRange,
          ),
        ),
      );
      expect(
        () => SkillTaxonomy(
          schemaVersion: 1,
          nodes: <SkillNode>[
            SkillNode(id: SkillId('a'), prerequisiteIds: const <SkillId>[]),
            SkillNode(id: SkillId('a'), prerequisiteIds: const <SkillId>[]),
          ],
        ),
        throwsA(
          isA<SkillTaxonomyValidationException>().having(
            (error) => error.code,
            'code',
            SkillTaxonomyValidationCode.duplicateSkillId,
          ),
        ),
      );
      expect(
        () => SkillTaxonomy(
          schemaVersion: 1,
          nodes: <SkillNode>[
            SkillNode(
              id: SkillId('a'),
              prerequisiteIds: <SkillId>[SkillId('a')],
            ),
          ],
        ),
        throwsA(
          isA<SkillTaxonomyValidationException>().having(
            (error) => error.code,
            'code',
            SkillTaxonomyValidationCode.selfPrerequisite,
          ),
        ),
      );
      expect(
        () => SkillTaxonomy(
          schemaVersion: 1,
          nodes: <SkillNode>[
            SkillNode(
              id: SkillId('a'),
              prerequisiteIds: <SkillId>[SkillId('missing')],
            ),
          ],
        ),
        throwsA(
          isA<SkillTaxonomyValidationException>().having(
            (error) => error.code,
            'code',
            SkillTaxonomyValidationCode.unknownPrerequisite,
          ),
        ),
      );
    });

    test('rejects a prerequisite cycle with a stable error code', () {
      expect(
        SkillTaxonomyValidationCode.prerequisiteCycle,
        'skillTaxonomy.prerequisite.cycle',
      );
      expect(
        () => SkillTaxonomy(
          schemaVersion: 1,
          nodes: <SkillNode>[
            SkillNode(
              id: SkillId('rhythm.a'),
              prerequisiteIds: <SkillId>[SkillId('rhythm.b')],
            ),
            SkillNode(
              id: SkillId('rhythm.b'),
              prerequisiteIds: <SkillId>[SkillId('rhythm.a')],
            ),
          ],
        ),
        throwsA(
          isA<SkillTaxonomyValidationException>().having(
            (error) => error.code,
            'code',
            SkillTaxonomyValidationCode.prerequisiteCycle,
          ),
        ),
      );
    });

    test('formats taxonomy validation errors with their stable code', () {
      try {
        SkillTaxonomy(schemaVersion: 0, nodes: const <SkillNode>[]);
      } on SkillTaxonomyValidationException catch (error) {
        expect(
          error.toString(),
          'SkillTaxonomyValidationException(skillTaxonomy.schemaVersion.outOfRange)',
        );
      }
    });
  });

  group('Domain purity', () {
    test(
      'ai_tutor domain has no framework, storage, or cross-feature imports',
      () {
        final domainDirectory = Directory('lib/features/ai_tutor/domain');
        expect(domainDirectory.existsSync(), isTrue);

        final sourceFiles =
            domainDirectory
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart'))
                .toList()
              ..sort((left, right) => left.path.compareTo(right.path));
        final violations = <String>[];

        for (final file in sourceFiles) {
          violations.addAll(
            _findPurityViolations(file.path, file.readAsStringSync()),
          );
        }

        expect(
          violations,
          isEmpty,
          reason:
              'ai_tutor domain purity violations:\n${violations.join('\n')}',
        );
      },
    );

    test('purity scan ignores forbidden spellings in comments and strings', () {
      const source = r'''
/// Documentation may explain why DateTime.now() is forbidden.
const wallClockExample = 'DateTime.now()';
const importExample = "import 'package:flutter/material.dart';";
''';

      expect(_findPurityViolations('memory.dart', source), isEmpty);
    });
  });
}

final _forbiddenPatterns = <String, RegExp>{
  'ambient wall clock': RegExp(r'\bDateTime\s*\.\s*now\s*\('),
  'ambient stopwatch': RegExp(r'\bStopwatch\s*\('),
  'ambient randomness': RegExp(r'\bRandom(?:\s*\.\s*secure)?\s*\('),
  'console output': RegExp(r'\bprint\s*\('),
  'framework or storage import': RegExp(
    r'''import\s+['"]package:(?:flutter(?:/|_)|[^/'"]*riverpod[^/'"]*/|dio/|shared_preferences/)''',
  ),
  'localization import': RegExp(r'''import\s+['"][^'"]*l10n(?:/|\.dart)'''),
  'cross-feature import': RegExp(
    r'''import\s+['"]package:strumsight/features/(?:practice|songs|streak|auth|settings|progress|metronome|diagnostics|share|learn|onboarding|library|chords|tuner|analyze|live)/''',
  ),
};

List<String> _findPurityViolations(String path, String source) {
  final codeMask = _sourceCodeMask(source);
  final violations = <String>[];
  for (final entry in _forbiddenPatterns.entries) {
    for (final match in entry.value.allMatches(source)) {
      if (!codeMask[match.start]) continue;
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      violations.add('$path:$line: ${entry.key}');
    }
  }
  return violations;
}

List<bool> _sourceCodeMask(String source) {
  final codeMask = List<bool>.filled(source.length, true);
  var index = 0;
  while (index < source.length) {
    final lineCommentEnd = _lineCommentEnd(source, index);
    if (lineCommentEnd != null) {
      _maskRange(codeMask, index, lineCommentEnd);
      index = lineCommentEnd;
      continue;
    }
    final blockCommentEnd = _blockCommentEnd(source, index);
    if (blockCommentEnd != null) {
      _maskRange(codeMask, index, blockCommentEnd);
      index = blockCommentEnd;
      continue;
    }
    final stringLiteral = _scanStringLiteral(source, index);
    if (stringLiteral != null) {
      _maskRange(codeMask, index, stringLiteral.end);
      for (final interpolation in stringLiteral.interpolations) {
        final interpolationMask = _sourceCodeMask(
          source.substring(interpolation.start, interpolation.end),
        );
        for (var offset = 0; offset < interpolationMask.length; offset++) {
          codeMask[interpolation.start + offset] = interpolationMask[offset];
        }
      }
      index = stringLiteral.end;
      continue;
    }
    index++;
  }
  return codeMask;
}

int? _lineCommentEnd(String source, int start) {
  if (!source.startsWith('//', start)) return null;
  var index = start + 2;
  while (index < source.length && source[index] != '\n') {
    index++;
  }
  return index;
}

int? _blockCommentEnd(String source, int start) {
  if (!source.startsWith('/*', start)) return null;
  var depth = 1;
  var index = start + 2;
  while (index < source.length && depth > 0) {
    if (source.startsWith('/*', index)) {
      depth++;
      index += 2;
    } else if (source.startsWith('*/', index)) {
      depth--;
      index += 2;
    } else {
      index++;
    }
  }
  return index;
}

_StringLiteralScan? _scanStringLiteral(String source, int start) {
  var quoteIndex = start;
  var raw = false;
  if (source[start] == 'r' &&
      start + 1 < source.length &&
      (source[start + 1] == "'" || source[start + 1] == '"')) {
    raw = true;
    quoteIndex++;
  }
  if (source[quoteIndex] != "'" && source[quoteIndex] != '"') return null;

  final quote = source[quoteIndex];
  final triple = source.startsWith('$quote$quote$quote', quoteIndex);
  final delimiter = triple ? '$quote$quote$quote' : quote;
  final interpolations = <_SourceRange>[];
  var index = quoteIndex + delimiter.length;
  while (index < source.length) {
    if (source.startsWith(delimiter, index)) {
      return _StringLiteralScan(index + delimiter.length, interpolations);
    }
    if (!raw && source[index] == r'\' && index + 1 < source.length) {
      index += 2;
      continue;
    }
    if (!raw && source.startsWith(r'${', index)) {
      final expressionStart = index + 2;
      final expressionEnd = _interpolationEnd(source, expressionStart);
      interpolations.add(_SourceRange(expressionStart, expressionEnd));
      index = expressionEnd < source.length ? expressionEnd + 1 : source.length;
      continue;
    }
    index++;
  }
  return _StringLiteralScan(source.length, interpolations);
}

int _interpolationEnd(String source, int start) {
  var depth = 1;
  var index = start;
  while (index < source.length) {
    final lineCommentEnd = _lineCommentEnd(source, index);
    if (lineCommentEnd != null) {
      index = lineCommentEnd;
      continue;
    }
    final blockCommentEnd = _blockCommentEnd(source, index);
    if (blockCommentEnd != null) {
      index = blockCommentEnd;
      continue;
    }
    final stringLiteral = _scanStringLiteral(source, index);
    if (stringLiteral != null) {
      index = stringLiteral.end;
      continue;
    }
    if (source[index] == '{') {
      depth++;
    } else if (source[index] == '}') {
      depth--;
      if (depth == 0) return index;
    }
    index++;
  }
  return source.length;
}

void _maskRange(List<bool> mask, int start, int end) {
  for (var index = start; index < end; index++) {
    mask[index] = false;
  }
}

final class _SourceRange {
  const _SourceRange(this.start, this.end);

  final int start;
  final int end;
}

final class _StringLiteralScan {
  const _StringLiteralScan(this.end, this.interpolations);

  final int end;
  final List<_SourceRange> interpolations;
}
