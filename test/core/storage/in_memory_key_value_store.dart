import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/storage/key_value_store.dart';

/// Test double for [KeyValueStore] (E01-R05).
///
/// Mirrors the production store's observable behaviour: a value read as the
/// wrong type answers `null`, and a write to a key listed in [failingKeys]
/// throws a [StorageException] the way a rejecting platform store does — so a
/// test can exercise the "the write did not happen" path without a device.
class InMemoryKeyValueStore implements KeyValueStore {
  InMemoryKeyValueStore([Map<String, Object>? initial])
    : values = {...?initial};

  final Map<String, Object> values;

  /// Keys whose writes (and removes) fail.
  final Set<String> failingKeys = {};

  /// Every write/remove that reached the store, in order — lets a test assert
  /// that a migration did NOT delete the old key.
  final List<String> writeLog = [];

  @override
  String? readString(String key) => _read<String>(key);

  @override
  int? readInt(String key) => _read<int>(key);

  @override
  double? readDouble(String key) => _read<double>(key);

  @override
  bool? readBool(String key) => _read<bool>(key);

  @override
  List<String>? readStringList(String key) => _read<List<String>>(key);

  T? _read<T>(String key) {
    final value = values[key];
    return value is T ? value : null;
  }

  @override
  Future<void> writeString(String key, String value) => _write(key, value);

  @override
  Future<void> writeInt(String key, int value) => _write(key, value);

  @override
  Future<void> writeDouble(String key, double value) => _write(key, value);

  @override
  Future<void> writeBool(String key, bool value) => _write(key, value);

  @override
  Future<void> writeStringList(String key, List<String> value) =>
      _write(key, List<String>.unmodifiable(value));

  @override
  Future<void> remove(String key) async {
    _guard(key);
    writeLog.add('remove:$key');
    values.remove(key);
  }

  @override
  bool contains(String key) => values.containsKey(key);

  Future<void> _write(String key, Object value) async {
    _guard(key);
    writeLog.add('write:$key');
    values[key] = value;
  }

  void _guard(String key) {
    if (failingKeys.contains(key)) {
      throw StorageException(FailureCode.storageWrite, key: key);
    }
  }
}
