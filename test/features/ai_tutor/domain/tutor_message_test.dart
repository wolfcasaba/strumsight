import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';

void main() {
  group('TutorMessage', () {
    test('keeps all user-visible roles distinct', () {
      expect(
        TutorMessageRole.values,
        equals(<TutorMessageRole>[
          TutorMessageRole.user,
          TutorMessageRole.tutor,
          TutorMessageRole.tool,
          TutorMessageRole.systemNotice,
        ]),
      );
    });

    test('keeps every delivery terminal state distinct', () {
      expect(
        TutorMessageDeliveryState.values,
        equals(<TutorMessageDeliveryState>[
          TutorMessageDeliveryState.pending,
          TutorMessageDeliveryState.streaming,
          TutorMessageDeliveryState.complete,
          TutorMessageDeliveryState.failed,
          TutorMessageDeliveryState.cancelled,
        ]),
      );
      expect(
        TutorMessageDeliveryState.failed,
        isNot(TutorMessageDeliveryState.cancelled),
      );
    });

    test('normalizes creation time and retains reply linkage', () {
      final message = TutorMessage(
        id: TutorMessageId('message-2'),
        role: TutorMessageRole.tutor,
        createdAt: DateTime.utc(2026, 8, 4, 12).toLocal(),
        sequence: 2,
        deliveryState: TutorMessageDeliveryState.complete,
        replyTo: TutorMessageId('message-1'),
        blocks: <TutorContentBlock>[TutorTextBlock(text: 'Rendben.')],
      );

      expect(message.createdAt.isUtc, isTrue);
      expect(message.replyTo, TutorMessageId('message-1'));
      expect(message.sequence, 2);
    });

    test('exposes an unmodifiable block list', () {
      final message = _message();

      expect(
        () => message.blocks.add(TutorTextBlock(text: 'more')),
        throwsUnsupportedError,
      );
    });

    test('rejects a negative sequence with a stable error code', () {
      expect(
        () => TutorMessage(
          id: TutorMessageId('message-1'),
          role: TutorMessageRole.user,
          createdAt: DateTime.utc(2026, 8, 4, 12),
          sequence: -1,
          deliveryState: TutorMessageDeliveryState.complete,
          blocks: <TutorContentBlock>[TutorTextBlock(text: 'Szia')],
        ),
        throwsA(
          isA<TutorMessageValidationException>().having(
            (error) => error.code,
            'code',
            TutorMessageValidationCode.sequenceNegative,
          ),
        ),
      );
    });

    test('uses value equality and matching hashes for equal messages', () {
      final first = _message();
      final second = _message();

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
      try {
        TutorMessage(
          id: TutorMessageId('message-1'),
          role: TutorMessageRole.user,
          createdAt: DateTime.utc(2026, 8, 4, 12),
          sequence: -1,
          deliveryState: TutorMessageDeliveryState.complete,
          blocks: <TutorContentBlock>[TutorTextBlock(text: 'Szia')],
        );
      } on TutorMessageValidationException catch (error) {
        expect(
          error.toString(),
          'TutorMessageValidationException(tutorMessage.sequence.negative)',
        );
      }
    });
  });

  group('Tutor content blocks', () {
    test('provides the structured block types used by tutor messages', () {
      final blocks = <TutorContentBlock>[
        TutorTextBlock(text: 'Start slowly.'),
        TutorHeadingBlock(text: 'Warm-up', level: 2),
        TutorBulletListBlock(items: <String>['Relax', 'Count']),
        TutorMetricBlock(label: 'Accuracy', value: '91%', unit: '%'),
        TutorEvidenceBlock(evidenceId: 'evidence-1', summary: '8 of 9'),
        TutorSourceBlock(title: 'Practice result', reference: 'session-1'),
        TutorActionBlock(
          actionId: TutorActionId('action-1'),
          label: 'Create plan',
        ),
        TutorPracticePlanBlock(planId: 'plan-1', title: 'Slow changes'),
        TutorWarningBlock(message: 'Confidence is low.'),
        TutorErrorBlock(message: 'Try again later.'),
      ];

      expect(
        blocks.map((block) => block.type),
        equals(<String>[
          'text',
          'heading',
          'bulletList',
          'metric',
          'evidence',
          'source',
          'action',
          'practicePlan',
          'warning',
          'error',
        ]),
      );
    });

    test('keeps unknown blocks as an inspectable placeholder', () {
      final block = TutorUnknownContentBlock(
        originalType: 'future.chart',
        rawJson: <String, Object?>{
          'type': 'future.chart',
          'points': <Object?>[1, 2, 3],
        },
      );

      expect(block.type, 'unknown');
      expect(block.originalType, 'future.chart');
      expect(block.rawJson['points'], equals(<Object?>[1, 2, 3]));
      expect(() => block.rawJson['newField'] = true, throwsUnsupportedError);
    });

    test('rejects invalid heading levels with a stable error code', () {
      expect(
        () => TutorHeadingBlock(text: 'Too deep', level: 7),
        throwsA(
          isA<TutorContentBlockValidationException>().having(
            (error) => error.code,
            'code',
            TutorContentBlockValidationCode.headingLevelOutOfRange,
          ),
        ),
      );
    });

    test('rejects an empty bullet list with a stable error code', () {
      expect(
        () => TutorBulletListBlock(items: <String>[]),
        throwsA(
          isA<TutorContentBlockValidationException>().having(
            (error) => error.code,
            'code',
            TutorContentBlockValidationCode.bulletListEmpty,
          ),
        ),
      );
    });

    test('uses value equality and matching hashes for known blocks', () {
      final blocks = <TutorContentBlock>[
        TutorTextBlock(text: 'Start slowly.'),
        TutorHeadingBlock(text: 'Warm-up', level: 2),
        TutorBulletListBlock(items: <String>['Relax', 'Count']),
        TutorMetricBlock(label: 'Accuracy', value: '91%', unit: '%'),
        TutorEvidenceBlock(evidenceId: 'evidence-1', summary: '8 of 9'),
        TutorSourceBlock(title: 'Practice result', reference: 'session-1'),
        TutorActionBlock(
          actionId: TutorActionId('action-1'),
          label: 'Create plan',
        ),
        TutorPracticePlanBlock(planId: 'plan-1', title: 'Slow changes'),
        TutorWarningBlock(message: 'Confidence is low.'),
        TutorErrorBlock(message: 'Try again later.'),
      ];
      final equalBlocks = <TutorContentBlock>[
        TutorTextBlock(text: 'Start slowly.'),
        TutorHeadingBlock(text: 'Warm-up', level: 2),
        TutorBulletListBlock(items: <String>['Relax', 'Count']),
        TutorMetricBlock(label: 'Accuracy', value: '91%', unit: '%'),
        TutorEvidenceBlock(evidenceId: 'evidence-1', summary: '8 of 9'),
        TutorSourceBlock(title: 'Practice result', reference: 'session-1'),
        TutorActionBlock(
          actionId: TutorActionId('action-1'),
          label: 'Create plan',
        ),
        TutorPracticePlanBlock(planId: 'plan-1', title: 'Slow changes'),
        TutorWarningBlock(message: 'Confidence is low.'),
        TutorErrorBlock(message: 'Try again later.'),
      ];

      for (var index = 0; index < blocks.length; index++) {
        expect(blocks[index], equals(equalBlocks[index]));
        expect(blocks[index].hashCode, equalBlocks[index].hashCode);
      }
      expect(TutorTextBlock(text: 'one'), isNot(TutorTextBlock(text: 'two')));
      expect(
        TutorBulletListBlock(items: <String>['one']),
        isNot(TutorBulletListBlock(items: <String>['two'])),
      );
    });

    test(
      'compares nested unknown JSON by value and rejects invalid inputs',
      () {
        final rawJson = <String, Object?>{
          'type': 'future.chart',
          'meta': <String, Object?>{
            'labels': <Object?>['A', 'B'],
          },
        };
        final first = TutorUnknownContentBlock(
          originalType: 'future.chart',
          rawJson: rawJson,
        );
        final second = TutorUnknownContentBlock(
          originalType: 'future.chart',
          rawJson: <String, Object?>{
            'type': 'future.chart',
            'meta': <String, Object?>{
              'labels': <Object?>['A', 'B'],
            },
          },
        );

        expect(first, equals(second));
        expect(first.hashCode, second.hashCode);
        expect(
          () => TutorUnknownContentBlock(originalType: ' ', rawJson: rawJson),
          throwsA(isA<TutorContentBlockValidationException>()),
        );
        expect(
          () => TutorUnknownContentBlock(
            originalType: 'future.chart',
            rawJson: <String, Object?>{
              'type': 'future.chart',
              'invalid': DateTime.utc(2026, 8, 4),
            },
          ),
          throwsA(isA<TutorContentBlockValidationException>()),
        );
      },
    );
  });
}

TutorMessage _message() {
  return TutorMessage(
    id: TutorMessageId('message-1'),
    role: TutorMessageRole.user,
    createdAt: DateTime.utc(2026, 8, 4, 12),
    sequence: 0,
    deliveryState: TutorMessageDeliveryState.complete,
    blocks: <TutorContentBlock>[TutorTextBlock(text: 'Szia')],
  );
}
