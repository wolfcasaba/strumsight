import 'dart:convert';

import '../../domain/models/tutor_content_block.dart';
import '../../domain/models/tutor_conversation.dart';
import '../../domain/models/tutor_ids.dart';
import '../../domain/models/tutor_message.dart';

/// Stable failure emitted when a persisted tutor conversation cannot be read.
class TutorConversationCodecException implements Exception {
  TutorConversationCodecException._(this.code, {this.field});

  /// One of [TutorConversationCodecErrorCode]'s constants.
  final String code;
  final String? field;

  @override
  String toString() =>
      'TutorConversationCodecException($code${field == null ? '' : ', field: $field'})';
}

/// Stable machine-readable failures emitted by [TutorConversationCodec].
abstract final class TutorConversationCodecErrorCode {
  static const String malformedJson = 'tutorConversation.codec.malformedJson';
  static const String notAnObject = 'tutorConversation.codec.notAnObject';
  static const String schemaVersionMissing =
      'tutorConversation.codec.schemaVersion.missing';
  static const String schemaVersionUnknown =
      'tutorConversation.codec.schemaVersion.unknown';
  static const String fieldMissing = 'tutorConversation.codec.field.missing';
  static const String fieldInvalid = 'tutorConversation.codec.field.invalid';
  static const String createdAtInvalid =
      'tutorConversation.codec.createdAt.invalid';
  static const String updatedAtInvalid =
      'tutorConversation.codec.updatedAt.invalid';
  static const String statusUnknown = 'tutorConversation.codec.status.unknown';
  static const String roleUnknown = 'tutorConversation.codec.role.unknown';
  static const String deliveryStateUnknown =
      'tutorConversation.codec.deliveryState.unknown';
  static const String blocksNotAList =
      'tutorConversation.codec.blocks.notAList';
  static const String messagesNotAList =
      'tutorConversation.codec.messages.notAList';
}

/// Deterministic JSON codec for the versioned tutor conversation model.
final class TutorConversationCodec {
  const TutorConversationCodec();

  /// The highest schema version this codec can decode.
  static const int supportedSchemaVersion = 1;

  /// Produces canonical UTF-8 JSON with a fixed key order.
  List<int> encode(TutorConversation conversation) =>
      utf8.encode(jsonEncode(_conversationToMap(conversation)));

  /// Decodes a version-one UTF-8 JSON conversation envelope.
  TutorConversation decode(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw TutorConversationCodecException._(
        TutorConversationCodecErrorCode.malformedJson,
      );
    }
    final root = _asObjectMap(
      decoded,
      TutorConversationCodecErrorCode.notAnObject,
    );
    final schemaVersion = _requiredInt(
      root,
      'schemaVersion',
      TutorConversationCodecErrorCode.schemaVersionMissing,
    );
    if (schemaVersion != supportedSchemaVersion) {
      throw TutorConversationCodecException._(
        TutorConversationCodecErrorCode.schemaVersionUnknown,
        field: 'schemaVersion',
      );
    }
    final messagesValue = root['messages'];
    if (messagesValue is! List) {
      throw TutorConversationCodecException._(
        TutorConversationCodecErrorCode.messagesNotAList,
        field: 'messages',
      );
    }
    return TutorConversation(
      schemaVersion: schemaVersion,
      id: TutorConversationId(
        _requiredString(
          root,
          'id',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      ),
      createdAt: _requiredUtcTimestamp(root, 'createdAt'),
      updatedAt: _requiredUtcTimestamp(root, 'updatedAt'),
      locale: _requiredString(
        root,
        'locale',
        TutorConversationCodecErrorCode.fieldMissing,
      ),
      title: _optionalString(root, 'title'),
      status: _conversationStatus(
        _requiredString(
          root,
          'status',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      ),
      messages: <TutorMessage>[
        for (final value in messagesValue) _messageFromMap(_asObjectMap(value)),
      ],
    );
  }
}

Map<String, Object?> _conversationToMap(TutorConversation conversation) =>
    <String, Object?>{
      'schemaVersion': conversation.schemaVersion,
      'id': conversation.id.value,
      'createdAt': conversation.createdAt.toUtc().toIso8601String(),
      'updatedAt': conversation.updatedAt.toUtc().toIso8601String(),
      'locale': conversation.locale,
      'status': conversation.status.name,
      'title': conversation.title,
      'messages': <Object?>[
        for (final message in conversation.messages) _messageToMap(message),
      ],
    };

Map<String, Object?> _messageToMap(TutorMessage message) => <String, Object?>{
  'id': message.id.value,
  'role': message.role.name,
  'createdAt': message.createdAt.toUtc().toIso8601String(),
  'sequence': message.sequence,
  'deliveryState': message.deliveryState.name,
  'replyTo': message.replyTo?.value,
  'blocks': <Object?>[for (final block in message.blocks) _blockToMap(block)],
};

TutorMessage _messageFromMap(Map<String, Object?> map) {
  final blocksValue = map['blocks'];
  if (blocksValue is! List) {
    throw TutorConversationCodecException._(
      TutorConversationCodecErrorCode.blocksNotAList,
      field: 'blocks',
    );
  }
  final replyTo = _optionalString(map, 'replyTo');
  return TutorMessage(
    id: TutorMessageId(
      _requiredString(map, 'id', TutorConversationCodecErrorCode.fieldMissing),
    ),
    role: _messageRole(
      _requiredString(
        map,
        'role',
        TutorConversationCodecErrorCode.fieldMissing,
      ),
    ),
    createdAt: _requiredUtcTimestamp(map, 'createdAt'),
    sequence: _requiredInt(
      map,
      'sequence',
      TutorConversationCodecErrorCode.fieldMissing,
    ),
    deliveryState: _deliveryState(
      _requiredString(
        map,
        'deliveryState',
        TutorConversationCodecErrorCode.fieldMissing,
      ),
    ),
    replyTo: replyTo == null ? null : TutorMessageId(replyTo),
    blocks: <TutorContentBlock>[
      for (final value in blocksValue) _blockFromMap(_asObjectMap(value)),
    ],
  );
}

Map<String, Object?> _blockToMap(TutorContentBlock block) {
  switch (block) {
    case TutorTextBlock(:final text):
      return <String, Object?>{'type': block.type, 'text': text};
    case TutorHeadingBlock(:final text, :final level):
      return <String, Object?>{
        'type': block.type,
        'text': text,
        'level': level,
      };
    case TutorBulletListBlock(:final items):
      return <String, Object?>{'type': block.type, 'items': items};
    case TutorMetricBlock(:final label, :final value, :final unit):
      return <String, Object?>{
        'type': block.type,
        'label': label,
        'value': value,
        'unit': unit,
      };
    case TutorEvidenceBlock(:final evidenceId, :final summary):
      return <String, Object?>{
        'type': block.type,
        'evidenceId': evidenceId,
        'summary': summary,
      };
    case TutorSourceBlock(:final title, :final reference):
      return <String, Object?>{
        'type': block.type,
        'title': title,
        'reference': reference,
      };
    case TutorActionBlock(:final actionId, :final label):
      return <String, Object?>{
        'type': block.type,
        'actionId': actionId.value,
        'label': label,
      };
    case TutorPracticePlanBlock(:final planId, :final title):
      return <String, Object?>{
        'type': block.type,
        'planId': planId,
        'title': title,
      };
    case TutorWarningBlock(:final message):
      return <String, Object?>{'type': block.type, 'message': message};
    case TutorErrorBlock(:final message):
      return <String, Object?>{'type': block.type, 'message': message};
    case TutorUnknownContentBlock(:final originalType, :final rawJson):
      return <String, Object?>{...rawJson, 'type': originalType};
  }
}

TutorContentBlock _blockFromMap(Map<String, Object?> map) {
  final type = _requiredString(
    map,
    'type',
    TutorConversationCodecErrorCode.fieldMissing,
  );
  switch (type) {
    case 'text':
      return TutorTextBlock(
        text: _requiredString(
          map,
          'text',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      );
    case 'heading':
      return TutorHeadingBlock(
        text: _requiredString(
          map,
          'text',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
        level: _requiredInt(
          map,
          'level',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      );
    case 'bulletList':
      final items = map['items'];
      if (items is! List || items.any((item) => item is! String)) {
        throw TutorConversationCodecException._(
          TutorConversationCodecErrorCode.fieldInvalid,
          field: 'items',
        );
      }
      return TutorBulletListBlock(items: items.cast<String>());
    case 'metric':
      return TutorMetricBlock(
        label: _requiredString(
          map,
          'label',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
        value: _requiredString(
          map,
          'value',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
        unit: _optionalString(map, 'unit'),
      );
    case 'evidence':
      return TutorEvidenceBlock(
        evidenceId: _requiredString(
          map,
          'evidenceId',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
        summary: _requiredString(
          map,
          'summary',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      );
    case 'source':
      return TutorSourceBlock(
        title: _requiredString(
          map,
          'title',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
        reference: _requiredString(
          map,
          'reference',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      );
    case 'action':
      return TutorActionBlock(
        actionId: TutorActionId(
          _requiredString(
            map,
            'actionId',
            TutorConversationCodecErrorCode.fieldMissing,
          ),
        ),
        label: _requiredString(
          map,
          'label',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      );
    case 'practicePlan':
      return TutorPracticePlanBlock(
        planId: _requiredString(
          map,
          'planId',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
        title: _requiredString(
          map,
          'title',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      );
    case 'warning':
      return TutorWarningBlock(
        message: _requiredString(
          map,
          'message',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      );
    case 'error':
      return TutorErrorBlock(
        message: _requiredString(
          map,
          'message',
          TutorConversationCodecErrorCode.fieldMissing,
        ),
      );
    default:
      return TutorUnknownContentBlock(originalType: type, rawJson: map);
  }
}

Map<String, Object?> _asObjectMap(
  Object? value, [
  String code = TutorConversationCodecErrorCode.fieldInvalid,
]) {
  if (value is! Map) {
    throw TutorConversationCodecException._(code);
  }
  final mapped = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw TutorConversationCodecException._(code);
    }
    mapped[entry.key as String] = entry.value;
  }
  return mapped;
}

String _requiredString(Map<String, Object?> map, String field, String code) {
  final value = map[field];
  if (value is! String) {
    throw TutorConversationCodecException._(code, field: field);
  }
  return value;
}

String? _optionalString(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value == null) return null;
  if (value is String) return value;
  throw TutorConversationCodecException._(
    TutorConversationCodecErrorCode.fieldInvalid,
    field: field,
  );
}

int _requiredInt(Map<String, Object?> map, String field, String code) {
  final value = map[field];
  if (value is! int) {
    throw TutorConversationCodecException._(code, field: field);
  }
  return value;
}

DateTime _requiredUtcTimestamp(Map<String, Object?> map, String field) {
  final value = _requiredString(
    map,
    field,
    field == 'createdAt'
        ? TutorConversationCodecErrorCode.createdAtInvalid
        : TutorConversationCodecErrorCode.updatedAtInvalid,
  );
  final parsed = DateTime.tryParse(value);
  if (!value.endsWith('Z') || parsed == null) {
    throw TutorConversationCodecException._(
      field == 'createdAt'
          ? TutorConversationCodecErrorCode.createdAtInvalid
          : TutorConversationCodecErrorCode.updatedAtInvalid,
      field: field,
    );
  }
  return parsed.toUtc();
}

TutorConversationStatus _conversationStatus(String name) {
  for (final value in TutorConversationStatus.values) {
    if (value.name == name) return value;
  }
  throw TutorConversationCodecException._(
    TutorConversationCodecErrorCode.statusUnknown,
    field: 'status',
  );
}

TutorMessageRole _messageRole(String name) {
  for (final value in TutorMessageRole.values) {
    if (value.name == name) return value;
  }
  throw TutorConversationCodecException._(
    TutorConversationCodecErrorCode.roleUnknown,
    field: 'role',
  );
}

TutorMessageDeliveryState _deliveryState(String name) {
  for (final value in TutorMessageDeliveryState.values) {
    if (value.name == name) return value;
  }
  throw TutorConversationCodecException._(
    TutorConversationCodecErrorCode.deliveryStateUnknown,
    field: 'deliveryState',
  );
}
