import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimum confidence (0..1) below which a detected strum is treated as
/// "unsure". Persisted; defaults to 0.45 (matches the mid/low ramp boundary).
class ConfidenceThresholdNotifier extends Notifier<double> {
  static const _key = 'confidence_threshold';
  static const defaultValue = 0.45;
  SharedPreferences? _prefs;

  @override
  double build() {
    _load();
    return defaultValue;
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final v = _prefs!.getDouble(_key);
    if (v != null) state = v.clamp(0.0, 1.0);
  }

  Future<void> set(double value) async {
    state = value.clamp(0.0, 1.0);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_key, state);
  }
}

final confidenceThresholdProvider =
    NotifierProvider<ConfidenceThresholdNotifier, double>(
  ConfidenceThresholdNotifier.new,
);
