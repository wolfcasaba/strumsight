import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/data/local/tutor_conversation_codec.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_conversation.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';

const _codec = TutorConversationCodec();

void main() {
  const codec = _codec;

  group('TutorConversationCodec round-trip', () {
    test('round-trips a populated conversation with every known block', () {
      final original = _conversation();

      final decoded = codec.decode(codec.encode(original));

      expect(decoded, equals(original));
    });

    test('canonicalizes unsorted message input by stable sequence', () {
      final original = _conversation(
        messages: <TutorMessage>[
          _message(id: 'message-2', sequence: 2),
          _message(id: 'message-0', sequence: 0),
          _message(id: 'message-1', sequence: 1),
        ],
      );

      final decoded = codec.decode(codec.encode(original));

      expect(
        decoded.messages.map((message) => message.id.value),
        equals(<String>['message-0', 'message-1', 'message-2']),
      );
    });

    test('encodes the same value as byte-identical canonical JSON', () {
      final original = _conversation();

      final first = codec.encode(original);
      final second = codec.encode(original);

      expect(first, equals(second));
      expect(utf8.decode(first), utf8.decode(second));
    });

    test('writes UTC timestamps and decodes them as UTC', () {
      final local = DateTime.utc(2026, 8, 4, 12).toLocal();
      final original = _conversation(
        createdAt: local,
        updatedAt: local.add(const Duration(minutes: 2)),
      );

      final encoded = utf8.decode(codec.encode(original));
      final decoded = codec.decode(utf8.encode(encoded));

      expect(encoded, contains('Z'));
      expect(decoded.createdAt.isUtc, isTrue);
      expect(decoded.updatedAt.isUtc, isTrue);
      expect(decoded.createdAt, original.createdAt.toUtc());
      expect(decoded.updatedAt, original.updatedAt.toUtc());
    });

    test('round-trips large Unicode text without loss', () {
      final text = '${'🎸 Árvíztűrő tükörfúrógép ' * 128}終';
      final original = _conversation(
        messages: <TutorMessage>[
          _message(
            id: 'unicode',
            blocks: <TutorContentBlock>[TutorTextBlock(text: text)],
          ),
        ],
      );

      final decoded = codec.decode(codec.encode(original));

      expect(
        (decoded.messages.single.blocks.single as TutorTextBlock).text,
        text,
      );
    });

    test('round-trips failed and cancelled as separate delivery states', () {
      final original = _conversation(
        messages: <TutorMessage>[
          _message(
            id: 'failed',
            sequence: 0,
            deliveryState: TutorMessageDeliveryState.failed,
          ),
          _message(
            id: 'cancelled',
            sequence: 1,
            deliveryState: TutorMessageDeliveryState.cancelled,
          ),
        ],
      );

      final decoded = codec.decode(codec.encode(original));

      expect(
        decoded.messages.map((message) => message.deliveryState),
        equals(<TutorMessageDeliveryState>[
          TutorMessageDeliveryState.failed,
          TutorMessageDeliveryState.cancelled,
        ]),
      );
    });
  });

  group('TutorConversationCodec unknown blocks', () {
    test('decodes an unknown block as a data-preserving placeholder', () {
      final json = _jsonFor(_conversation());
      final blocks =
          ((json['messages'] as List<Object?>).single
                  as Map<String, Object?>)['blocks']
              as List<Object?>;
      final block = blocks.first as Map<String, Object?>;
      block['type'] = 'future.chart';
      block['points'] = <Object?>[1, 2, 3];

      final decoded = codec.decode(utf8.encode(jsonEncode(json)));

      final unknown = decoded.messages.single.blocks.first;
      expect(unknown, isA<TutorUnknownContentBlock>());
      expect(
        (unknown as TutorUnknownContentBlock).originalType,
        'future.chart',
      );
      expect(unknown.rawJson['points'], equals(<Object?>[1, 2, 3]));
    });

    test('re-encodes a decoded unknown block instead of dropping it', () {
      final json = _jsonFor(_conversation());
      final blocks =
          ((json['messages'] as List<Object?>).single
                  as Map<String, Object?>)['blocks']
              as List<Object?>;
      final block = blocks.first as Map<String, Object?>;
      block['type'] = 'future.chart';
      block['points'] = <Object?>[1, 2, 3];
      final decoded = codec.decode(utf8.encode(jsonEncode(json)));

      final reencoded = _jsonFor(decoded);
      final reencodedBlocks =
          ((reencoded['messages'] as List<Object?>).single
                  as Map<String, Object?>)['blocks']
              as List<Object?>;
      final reencodedBlock = reencodedBlocks.first as Map<String, Object?>;

      expect(reencodedBlock['type'], 'future.chart');
      expect(reencodedBlock['points'], equals(<Object?>[1, 2, 3]));
    });
  });

  group('TutorConversationCodec failures', () {
    test('rejects an unknown schema version with a stable code', () {
      final json = _jsonFor(_conversation());
      json['schemaVersion'] = TutorConversationCodec.supportedSchemaVersion + 1;

      expect(
        () => codec.decode(utf8.encode(jsonEncode(json))),
        throwsA(
          isA<TutorConversationCodecException>().having(
            (error) => error.code,
            'code',
            TutorConversationCodecErrorCode.schemaVersionUnknown,
          ),
        ),
      );
    });

    test('rejects a non-UTC timestamp with a stable code', () {
      final json = _jsonFor(_conversation());
      json['createdAt'] = '2026-08-04T12:00:00+02:00';

      expect(
        () => codec.decode(utf8.encode(jsonEncode(json))),
        throwsA(
          isA<TutorConversationCodecException>().having(
            (error) => error.code,
            'code',
            TutorConversationCodecErrorCode.createdAtInvalid,
          ),
        ),
      );
    });
  });
}

TutorConversation _conversation({
  List<TutorMessage>? messages,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 8, 4, 12);
  return TutorConversation(
    schemaVersion: TutorConversationCodec.supportedSchemaVersion,
    id: TutorConversationId('conversation-1'),
    createdAt: created,
    updatedAt: updatedAt ?? created.add(const Duration(minutes: 1)),
    locale: 'hu',
    title: 'Mai gyakorlás',
    status: TutorConversationStatus.active,
    messages: messages ?? <TutorMessage>[_message()],
  );
}

TutorMessage _message({
  String id = 'message-1',
  int sequence = 0,
  TutorMessageDeliveryState deliveryState = TutorMessageDeliveryState.complete,
  List<TutorContentBlock>? blocks,
}) {
  return TutorMessage(
    id: TutorMessageId(id),
    role: TutorMessageRole.tutor,
    createdAt: DateTime.utc(2026, 8, 4, 12),
    sequence: sequence,
    deliveryState: deliveryState,
    replyTo: TutorMessageId('reply-1'),
    blocks:
        blocks ??
        <TutorContentBlock>[
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
        ],
  );
}

Map<String, Object?> _jsonFor(TutorConversation conversation) {
  return Map<String, Object?>.from(
    jsonDecode(utf8.decode(_codec.encode(conversation)))
        as Map<String, dynamic>,
  );
}
