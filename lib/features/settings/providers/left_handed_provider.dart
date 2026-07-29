import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Whether to render chord diagrams **left-handed** (high-E string on the left).
/// Persisted locally; a per-player physical preference (like the capo), not
/// synced. Default: right-handed.
class LeftHandedController extends Notifier<bool>
    with PersistedPreference<bool> {
  @override
  bool build() => preferences.readBool(StorageKeys.leftHanded) ?? false;

  Future<void> set(bool value) async {
    state = value;
    await persist(
      StorageKeys.leftHanded,
      (store) => store.writeBool(StorageKeys.leftHanded, value),
    );
  }
}

final leftHandedProvider = NotifierProvider<LeftHandedController, bool>(
  LeftHandedController.new,
);
