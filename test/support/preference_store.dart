import 'dart:convert';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/storage_providers.dart';

import '../core/storage/in_memory_key_value_store.dart';

export '../core/storage/in_memory_key_value_store.dart';

/// The preference-store override every container needs since E01-R06.
///
/// `keyValueStoreProvider` has no default on purpose (a silent in-memory
/// fallback would hide dropped writes), so a test that builds any preference
/// provider must inject a store. Pass [initial] to seed values — keyed by
/// `StorageKeys`, i.e. the same keys production reads, so a test cannot pass
/// against a key the app never looks at.
List<Override> preferenceOverrides([Map<String, Object>? initial]) => [
  keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore(initial)),
];

/// Same, when the test needs to inspect the store afterwards.
Override preferenceStoreOverride(InMemoryKeyValueStore store) =>
    keyValueStoreProvider.overrideWithValue(store);

/// A stored collection document in the E01-R07 §7.3 envelope — what the app
/// itself writes for the library, songs, setlists and the practice log.
String storedCollection(List<Map<String, dynamic>> items) =>
    jsonEncode({'schemaVersion': documentSchemaVersion, 'items': items});

/// A stored single-object document (streak, lesson progress).
String storedDocument(Map<String, Object?> data) =>
    jsonEncode({'schemaVersion': documentSchemaVersion, 'data': data});
