import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_conversation.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_response_mode.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_turn.dart';

void main() {
  group('Tutor typed IDs', () {
    test('normalizes every ID kind by trimming surrounding whitespace', () {
      final ids = <TutorTypedId>[
        TutorConversationId(' conversation-1 '),
        TutorMessageId(' message-1 '),
        TutorTurnId(' turn-1 '),
        TutorRequestId(' request-1 '),
        TutorActionId(' action-1 '),
      ];

      expect(
        ids.map((id) => id.value),
        equals(<String>[
          'conversation-1',
          'message-1',
          'turn-1',
          'request-1',
          'action-1',
        ]),
      );
    });

    test('rejects blank IDs with the stable empty code', () {
      expect(TutorIdValidationCode.empty, 'tutorId.empty');
      expect(
        () => TutorConversationId(' \t '),
        throwsA(
          isA<TutorIdValidationException>().having(
            (error) => error.code,
            'code',
            TutorIdValidationCode.empty,
          ),
        ),
      );
    });

    test('rejects IDs beyond the shared maximum with the stable code', () {
      expect(TutorIdValidationCode.tooLong, 'tutorId.tooLong');
      expect(
        () => TutorMessageId('a' * (maxTutorIdLength + 1)),
        throwsA(
          isA<TutorIdValidationException>().having(
            (error) => error.code,
            'code',
            TutorIdValidationCode.tooLong,
          ),
        ),
      );
    });

    test('accepts the shared maximum length after trimming', () {
      final id = TutorRequestId(' ${'a' * maxTutorIdLength} ');

      expect(id.value, hasLength(maxTutorIdLength));
    });

    test('keeps distinct ID kinds type-safe for equality', () {
      expect(TutorConversationId('same'), isNot(TutorMessageId('same')));
      expect(TutorConversationId('same'), equals(TutorConversationId('same')));
    });

    test('has stable value-object strings and hashes', () {
      final first = TutorConversationId('conversation-1');
      final second = TutorConversationId('conversation-1');

      expect(first.hashCode, second.hashCode);
      expect(first.toString(), 'TutorConversationId(conversation-1)');
      try {
        TutorConversationId('');
      } on TutorIdValidationException catch (error) {
        expect(error.toString(), 'TutorIdValidationException(tutorId.empty)');
      }
    });
  });

  group('TutorConversation', () {
    test('normalizes timestamps and orders messages by stable sequence', () {
      final first = _message(id: 'first', sequence: 0);
      final second = _message(id: 'second', sequence: 1);
      final third = _message(id: 'third', sequence: 2);
      final localCreated = DateTime.utc(2026, 8, 4, 12).toLocal();
      final conversation = TutorConversation(
        schemaVersion: 1,
        id: TutorConversationId('conversation-1'),
        createdAt: localCreated,
        updatedAt: localCreated.add(const Duration(minutes: 3)),
        locale: 'hu',
        status: TutorConversationStatus.active,
        messages: [third, first, second],
      );

      expect(conversation.createdAt.isUtc, isTrue);
      expect(conversation.updatedAt.isUtc, isTrue);
      expect(
        conversation.messages.map((message) => message.id.value),
        equals(<String>['first', 'second', 'third']),
      );
    });

    test('keeps equal-sequence messages in their original order', () {
      final first = _message(id: 'first', sequence: 7);
      final second = _message(id: 'second', sequence: 7);
      final conversation = _conversation(messages: [second, first]);

      expect(
        conversation.messages.map((message) => message.id.value),
        equals(<String>['second', 'first']),
      );
    });

    test('exposes an unmodifiable ordered message list', () {
      final conversation = _conversation(messages: [_message(id: 'first')]);

      expect(
        () => conversation.messages.add(_message(id: 'second')),
        throwsUnsupportedError,
      );
    });

    test('rejects an updated timestamp before creation with a stable code', () {
      expect(
        () => TutorConversation(
          schemaVersion: 1,
          id: TutorConversationId('conversation-1'),
          createdAt: DateTime.utc(2026, 8, 4, 12),
          updatedAt: DateTime.utc(2026, 8, 4, 11),
          locale: 'hu',
          status: TutorConversationStatus.active,
          messages: const <TutorMessage>[],
        ),
        throwsA(
          isA<TutorConversationValidationException>().having(
            (error) => error.code,
            'code',
            TutorConversationValidationCode.createdAtAfterUpdatedAt,
          ),
        ),
      );
    });

    test('keeps active, archived, and deleted as distinct statuses', () {
      expect(
        TutorConversationStatus.values,
        equals(<TutorConversationStatus>[
          TutorConversationStatus.active,
          TutorConversationStatus.archived,
          TutorConversationStatus.deleted,
        ]),
      );
    });

    test('rejects unsupported schema versions and empty locales', () {
      expect(
        () => TutorConversation(
          schemaVersion: 0,
          id: TutorConversationId('conversation-1'),
          createdAt: DateTime.utc(2026, 8, 4, 12),
          updatedAt: DateTime.utc(2026, 8, 4, 12),
          locale: 'hu',
          status: TutorConversationStatus.active,
          messages: <TutorMessage>[],
        ),
        throwsA(isA<TutorConversationValidationException>()),
      );
      expect(
        () => TutorConversation(
          schemaVersion: 1,
          id: TutorConversationId('conversation-1'),
          createdAt: DateTime.utc(2026, 8, 4, 12),
          updatedAt: DateTime.utc(2026, 8, 4, 12),
          locale: ' ',
          status: TutorConversationStatus.active,
          messages: <TutorMessage>[],
        ),
        throwsA(isA<TutorConversationValidationException>()),
      );
    });

    test('uses value equality and matching hashes for equal conversations', () {
      final first = _conversation(messages: <TutorMessage>[_message()]);
      final second = _conversation(messages: <TutorMessage>[_message()]);

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });
  });

  group('TutorTurn', () {
    test('keeps typed IDs, UTC creation time, and response mode together', () {
      final turn = TutorTurn(
        id: TutorTurnId('turn-1'),
        conversationId: TutorConversationId('conversation-1'),
        requestId: TutorRequestId('request-1'),
        userMessageId: TutorMessageId('message-1'),
        actionId: TutorActionId('action-1'),
        requestedResponseMode: TutorResponseMode.detailed,
        createdAt: DateTime.utc(2026, 8, 4, 12).toLocal(),
      );

      expect(turn.id, TutorTurnId('turn-1'));
      expect(turn.conversationId, TutorConversationId('conversation-1'));
      expect(turn.requestedResponseMode, TutorResponseMode.detailed);
      expect(turn.createdAt.isUtc, isTrue);
    });

    test('uses value equality and matching hashes for equal turns', () {
      final first = _turn();
      final second = _turn();

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
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

TutorConversation _conversation({List<TutorMessage>? messages}) {
  return TutorConversation(
    schemaVersion: 1,
    id: TutorConversationId('conversation-1'),
    createdAt: DateTime.utc(2026, 8, 4, 12),
    updatedAt: DateTime.utc(2026, 8, 4, 12, 1),
    locale: 'hu',
    status: TutorConversationStatus.active,
    messages: messages ?? const <TutorMessage>[],
  );
}

TutorMessage _message({String id = 'message-1', int sequence = 0}) {
  return TutorMessage(
    id: TutorMessageId(id),
    role: TutorMessageRole.user,
    createdAt: DateTime.utc(2026, 8, 4, 12),
    sequence: sequence,
    deliveryState: TutorMessageDeliveryState.complete,
    blocks: <TutorContentBlock>[TutorTextBlock(text: 'Szia')],
  );
}

TutorTurn _turn() {
  return TutorTurn(
    id: TutorTurnId('turn-1'),
    conversationId: TutorConversationId('conversation-1'),
    requestId: TutorRequestId('request-1'),
    userMessageId: TutorMessageId('message-1'),
    actionId: TutorActionId('action-1'),
    requestedResponseMode: TutorResponseMode.standard,
    createdAt: DateTime.utc(2026, 8, 4, 12),
  );
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
