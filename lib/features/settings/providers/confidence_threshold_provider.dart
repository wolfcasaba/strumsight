import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Minimum confidence (0..1) below which a detected strum is treated as
/// "unsure". Persisted; defaults to 0.45 (matches the mid/low ramp boundary).
class ConfidenceThresholdNotifier extends Notifier<double>
    with PersistedPreference<double> {
  static const defaultValue = 0.45;

  @override
  double build() {
    final v = preferences.readDouble(StorageKeys.confidenceThreshold);
    return v == null ? defaultValue : v.clamp(0.0, 1.0);
  }

  Future<void> set(double value) async {
    state = value.clamp(0.0, 1.0);
    await persist(
      StorageKeys.confidenceThreshold,
      (store) => store.writeDouble(StorageKeys.confidenceThreshold, state),
    );
  }
}

final confidenceThresholdProvider =
    NotifierProvider<ConfidenceThresholdNotifier, double>(
      ConfidenceThresholdNotifier.new,
    );
