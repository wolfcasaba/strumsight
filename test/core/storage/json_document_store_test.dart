import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/json_validation.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';

import 'in_memory_key_value_store.dart';

/// Captures what was logged so a test can assert that corruption was REPORTED,
/// not just survived.
class _RecordingLogger implements AppLogger {
  final List<String> events = [];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      events.add(event);

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) =>
      events.add(event);

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => events.add(event);

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) => events.add(event);
}

/// One trivial record type, so the store's behaviour is tested without dragging
/// a feature model's rules in.
class _Note {
  const _Note(this.id, this.value);
  final String id;
  final int value;

  Map<String, dynamic> toJson() => {'id': id, 'value': value};

  factory _Note.fromJson(Map<String, dynamic> j) =>
      _Note(requireString(j, 'id'), requireInt(j, 'value'));
}

void main() {
  const key = 'ss.test.notes';
  const legacyKey = 'test_notes_v1';

  ({
    JsonCollectionStore<_Note> notes,
    InMemoryKeyValueStore store,
    _RecordingLogger logger,
  })
  collection({
    Map<String, Object>? initial,
    int maxItems = 10,
    RecordOrder order = RecordOrder.newestFirst,
  }) {
    final store = InMemoryKeyValueStore(initial);
    final logger = _RecordingLogger();
    return (
      notes: JsonCollectionStore<_Note>(
        document: JsonDocumentStore(
          store: store,
          logger: logger,
          key: key,
          legacyKey: legacyKey,
          name: 'notes',
        ),
        fromJson: _Note.fromJson,
        toJson: (n) => n.toJson(),
        maxItems: maxItems,
        order: order,
      ),
      store: store,
      logger: logger,
    );
  }

  group('envelope (§7.3)', () {
    test('a write carries the schema version and reads back', () async {
      final c = collection();
      await c.notes.write(const [_Note('a', 1), _Note('b', 2)]);

      final raw = jsonDecode(c.store.readString(key)!) as Map<String, dynamic>;
      expect(raw['schemaVersion'], documentSchemaVersion);
      expect(raw['items'], hasLength(2));
      expect(c.notes.read().map((n) => n.id), ['a', 'b']);
    });

    test('an empty store reads as an empty, correctly TYPED list', () {
      final read = collection().notes.read();
      expect(read, isEmpty);
      // `const []` would be a List<Never> at runtime and blow up the first
      // caller that passes a typed closure (the r07 library-detail crash).
      expect(read, isA<List<_Note>>());
      expect(
        () => read.firstWhere((n) => false, orElse: () => const _Note('x', 0)),
        returnsNormally,
      );
    });

    test('a document from a NEWER build is isolated, not guessed at', () {
      final c = collection(
        initial: {
          key: jsonEncode({
            'schemaVersion': documentSchemaVersion + 1,
            'items': [
              {'id': 'a', 'value': 1},
            ],
          }),
        },
      );
      expect(c.notes.read(), isEmpty);
      expect(c.logger.events, contains('storage.document.corrupt'));
    });
  });

  group('corruption (§7.4)', () {
    test('one bad record is skipped, every good one still loads', () {
      final c = collection(
        initial: {
          key: jsonEncode({
            'schemaVersion': 1,
            'items': [
              {'id': 'a', 'value': 1},
              {'id': '', 'value': 2}, // empty id
              {'value': 3}, // missing id
              'not even an object',
              {'id': 'd', 'value': 4},
            ],
          }),
        },
      );

      expect(c.notes.read().map((n) => n.id), ['a', 'd']);
      expect(c.logger.events, contains('storage.document.record_skipped'));
      expect(c.logger.events, contains('storage.document.records_skipped'));
    });

    test(
      'an unparsable document is QUARANTINED, never silently dropped',
      () async {
        final c = collection(initial: {key: '{{{ not json'});

        expect(c.notes.read(), isEmpty, reason: 'the app carries on');
        expect(c.logger.events, contains('storage.document.corrupt'));
        expect(
          c.store.readString(key),
          '{{{ not json',
          reason: 'nothing is destroyed until there is a copy',
        );

        await c.notes.write(const [_Note('fresh', 1)]);
        expect(
          c.store.readString(StorageKeys.quarantineOf(key)),
          '{{{ not json',
          reason: 'the unreadable bytes stay recoverable',
        );
        expect(c.notes.read().single.id, 'fresh');
      },
    );

    test(
      'a platform write refusal is logged, never thrown at the caller',
      () async {
        final c = collection();
        c.store.failingKeys.add(key);

        await expectLater(c.notes.write(const [_Note('a', 1)]), completes);
        expect(c.logger.events, contains('storage.document.write_failed'));
      },
    );
  });

  group('legacy fallback (a failed migration must not cost data)', () {
    test('a pre-envelope blob is still read', () {
      final c = collection(
        initial: {
          legacyKey: jsonEncode([
            {'id': 'old', 'value': 7},
          ]),
        },
      );
      expect(c.notes.read().single.id, 'old');
    });

    test('the next write moves it over and drops the legacy key', () async {
      final c = collection(
        initial: {
          legacyKey: jsonEncode([
            {'id': 'old', 'value': 7},
          ]),
        },
      );
      await c.notes.write([...c.notes.read(), const _Note('new', 8)]);

      expect(c.store.contains(legacyKey), isFalse);
      expect(c.notes.read().map((n) => n.id), ['old', 'new']);
    });

    test('the envelope wins when both keys exist', () {
      final c = collection(
        initial: {
          key: jsonEncode({
            'schemaVersion': 1,
            'items': [
              {'id': 'current', 'value': 1},
            ],
          }),
          legacyKey: jsonEncode([
            {'id': 'stale', 'value': 0},
          ]),
        },
      );
      expect(c.notes.read().single.id, 'current');
    });
  });

  group('size limits (§7.5)', () {
    test('a newest-first collection evicts the OLDEST on write', () async {
      final c = collection(maxItems: 3);
      await c.notes.write(const [
        _Note('newest', 4),
        _Note('c', 3),
        _Note('b', 2),
        _Note('oldest', 1),
      ]);
      expect(c.notes.read().map((n) => n.id), ['newest', 'c', 'b']);
    });

    test('a newest-last collection evicts from the front', () async {
      final c = collection(maxItems: 3, order: RecordOrder.newestLast);
      await c.notes.write(const [
        _Note('oldest', 1),
        _Note('b', 2),
        _Note('c', 3),
        _Note('newest', 4),
      ]);
      expect(c.notes.read().map((n) => n.id), ['b', 'c', 'newest']);
    });

    test(
      'an over-cap document written by an older build is trimmed on read',
      () {
        final c = collection(
          maxItems: 2,
          initial: {
            key: jsonEncode({
              'schemaVersion': 1,
              'items': [
                for (var i = 0; i < 20; i++) {'id': 'n$i', 'value': i},
              ],
            }),
          },
        );
        expect(c.notes.read(), hasLength(2));
      },
    );
  });

  group('object documents', () {
    JsonObjectStore<Map<String, dynamic>> objectStore(
      InMemoryKeyValueStore store,
      AppLogger logger,
    ) => JsonObjectStore<Map<String, dynamic>>(
      document: JsonDocumentStore(
        store: store,
        logger: logger,
        key: key,
        legacyKey: legacyKey,
        name: 'note',
        bodyKey: 'data',
      ),
      fromJson: (j) => j,
      toJson: (j) => j,
    );

    test('round-trips under the data body key', () async {
      final store = InMemoryKeyValueStore();
      final s = objectStore(store, _RecordingLogger());
      await s.write({'current': 7});

      final raw = jsonDecode(store.readString(key)!) as Map<String, dynamic>;
      expect(raw['data'], {'current': 7});
      expect(s.read(), {'current': 7});
    });

    test('a body of the wrong shape reads as null, not a crash', () {
      final store = InMemoryKeyValueStore({
        key: jsonEncode({'schemaVersion': 1, 'data': 'a string'}),
      });
      final logger = _RecordingLogger();
      expect(objectStore(store, logger).read(), isNull);
      expect(logger.events, contains('storage.document.record_skipped'));
    });
  });
}
