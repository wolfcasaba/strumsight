import '../foundation/app_failure.dart';

/// The app's only contract for non-secret local persistence (SDD Ch2 §7.4).
///
/// Features depend on this interface, never on `shared_preferences` directly:
/// the plugin is initialised once at boot and injected (see
/// `storage_providers.dart`), which keeps tests hermetic and makes the whole
/// key surface enumerable in [StorageKeys].
///
/// Reads are **synchronous** — the backing store is loaded before the first
/// frame, so a provider can build its initial state without an async gap (the
/// old "default first, overwrite when prefs land" dance that could clobber a
/// user edit mid-flight).
///
/// A read of a key written with a different type returns `null` rather than
/// throwing: a corrupt or type-mismatched value must not take the app down.
/// The value stays on disk, so nothing is destroyed by the fallback.
///
/// Writes never fail silently. A platform-level write failure completes the
/// future with a [StorageException] — callers that must react to it (the
/// migrator, for one) catch it and map it to a [StorageFailure].
abstract interface class KeyValueStore {
  String? readString(String key);
  int? readInt(String key);
  double? readDouble(String key);
  bool? readBool(String key);
  List<String>? readStringList(String key);

  Future<void> writeString(String key, String value);
  Future<void> writeInt(String key, int value);
  Future<void> writeDouble(String key, double value);
  Future<void> writeBool(String key, bool value);
  Future<void> writeStringList(String key, List<String> value);

  Future<void> remove(String key);
  bool contains(String key);
}

/// Thrown by a [KeyValueStore] implementation when the platform refuses an
/// operation. Carries a [FailureCode] so the catch site can build a
/// [StorageFailure] without re-deriving what went wrong.
class StorageException implements Exception {
  const StorageException(this.code, {this.key, this.cause});

  /// One of [FailureCode]'s `storage.*` constants.
  final String code;

  /// The key involved, when the failure is scoped to one.
  final String? key;

  final Object? cause;

  /// Deliberately free of the stored value — a store holds user data.
  @override
  String toString() => 'StorageException($code, key: $key)';
}
