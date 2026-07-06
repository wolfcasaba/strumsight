import 'package:flutter/material.dart';
import 'package:music_theory/features/settings/data/settings_repository.dart';

/// In-memory settings backend for tests. Holds a [RemoteSettings] and records
/// every `update` patch so tests can assert what was pushed.
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({
    this.themeMode = ThemeMode.system,
    this.locale,
    this.confidenceThreshold = 0.45,
    this.tuningA4 = 440,
  });

  ThemeMode themeMode;
  Locale? locale;
  double confidenceThreshold;
  int tuningA4;

  int fetchCalls = 0;
  final List<Map<String, dynamic>> updates = [];

  /// Make the next N `update` calls throw (simulate offline). Each throwing
  /// attempt is still recorded in [updates] so tests can count retries.
  int failNextUpdates = 0;

  RemoteSettings get _current => RemoteSettings(
        themeMode: themeMode,
        locale: locale,
        confidenceThreshold: confidenceThreshold,
        tuningA4: tuningA4,
      );

  @override
  Future<RemoteSettings> fetch() async {
    fetchCalls++;
    return _current;
  }

  @override
  Future<RemoteSettings> update(Map<String, dynamic> patch) async {
    updates.add(patch);
    if (failNextUpdates > 0) {
      failNextUpdates--;
      throw Exception('offline');
    }
    if (patch.containsKey('theme_mode')) {
      themeMode = RemoteSettings.fromJson({'theme_mode': patch['theme_mode']})
          .themeMode;
    }
    if (patch.containsKey('locale')) {
      final code = patch['locale'] as String?;
      locale = (code == null || code.isEmpty) ? null : Locale(code);
    }
    if (patch.containsKey('confidence_threshold')) {
      confidenceThreshold = (patch['confidence_threshold'] as num).toDouble();
    }
    return _current;
  }
}
