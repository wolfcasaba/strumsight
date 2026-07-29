import 'package:shared_preferences/shared_preferences.dart';

import '../foundation/app_failure.dart';
import '../foundation/app_result.dart';
import 'key_value_store.dart';

/// The production [KeyValueStore]: one `SharedPreferences` instance, created
/// once at boot (SDD Ch2 Kör 5 §5.1) and handed to every consumer through
/// dependency injection.
///
/// This is the ONLY place in `lib/` allowed to touch the plugin.
class SharedPreferencesStore implements KeyValueStore {
  SharedPreferencesStore(this._prefs);

  /// Load the platform store. Returns a [StorageFailure] instead of throwing so
  /// bootstrap can decide what a device without working preferences means —
  /// see `AppBootstrap.run`, which refuses to start rather than silently run on
  /// a store that would drop every write.
  static Future<AppResult<SharedPreferencesStore>> open() async {
    try {
      return Success(
        SharedPreferencesStore(await SharedPreferences.getInstance()),
      );
    } catch (e, stackTrace) {
      return Failure(
        StorageFailure(
          code: FailureCode.storageUnavailable,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  final SharedPreferences _prefs;

  @override
  String? readString(String key) => _read(() => _prefs.getString(key));

  @override
  int? readInt(String key) => _read(() => _prefs.getInt(key));

  @override
  double? readDouble(String key) => _read(() => _prefs.getDouble(key));

  @override
  bool? readBool(String key) => _read(() => _prefs.getBool(key));

  @override
  List<String>? readStringList(String key) =>
      _read(() => _prefs.getStringList(key));

  @override
  Future<void> writeString(String key, String value) =>
      _write(key, () => _prefs.setString(key, value));

  @override
  Future<void> writeInt(String key, int value) =>
      _write(key, () => _prefs.setInt(key, value));

  @override
  Future<void> writeDouble(String key, double value) =>
      _write(key, () => _prefs.setDouble(key, value));

  @override
  Future<void> writeBool(String key, bool value) =>
      _write(key, () => _prefs.setBool(key, value));

  @override
  Future<void> writeStringList(String key, List<String> value) =>
      _write(key, () => _prefs.setStringList(key, value));

  @override
  Future<void> remove(String key) =>
      _write(key, () => _prefs.remove(key), code: FailureCode.storageWrite);

  @override
  bool contains(String key) => _prefs.containsKey(key);

  /// A value stored under a different type throws inside the plugin's cache
  /// cast. Treat it as "not set": the app falls back to its default and the
  /// bytes stay on disk for a migration to look at.
  T? _read<T>(T? Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  /// `set*`/`remove` answer `false` when the platform rejected the operation —
  /// the silent-no-op shape this project keeps getting bitten by. Turn both it
  /// and a thrown platform error into a [StorageException].
  Future<void> _write(
    String key,
    Future<bool> Function() write, {
    String code = FailureCode.storageWrite,
  }) async {
    final bool ok;
    try {
      ok = await write();
    } catch (e) {
      throw StorageException(code, key: key, cause: e);
    }
    if (!ok) throw StorageException(code, key: key);
  }
}
