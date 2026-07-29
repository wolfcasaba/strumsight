import 'package:flutter/material.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';

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

  /// Make the next N updates return an offline failure. Every attempt is
  /// recorded so tests can prove writes are not replayed automatically.
  int failNextUpdates = 0;

  AppFailure? fetchFailure;
  AppFailure? updateFailure;

  RemoteSettings get _current => RemoteSettings(
    themeMode: themeMode,
    locale: locale,
    confidenceThreshold: confidenceThreshold,
    tuningA4: tuningA4,
  );

  @override
  Future<AppResult<RemoteSettings>> fetch() async {
    fetchCalls++;
    return fetchFailure == null ? Success(_current) : Failure(fetchFailure!);
  }

  @override
  Future<AppResult<RemoteSettings>> update(Map<String, Object?> patch) async {
    updates.add(patch);
    if (updateFailure != null) {
      return Failure(updateFailure!);
    }
    if (failNextUpdates > 0) {
      failNextUpdates--;
      return const Failure(NetworkFailure());
    }
    if (patch.containsKey('theme_mode')) {
      themeMode = ThemeMode.values.byName(patch['theme_mode']! as String);
    }
    if (patch.containsKey('locale')) {
      final code = patch['locale'] as String?;
      locale = (code == null || code.isEmpty) ? null : Locale(code);
    }
    if (patch.containsKey('confidence_threshold')) {
      confidenceThreshold = (patch['confidence_threshold'] as num).toDouble();
    }
    return Success(_current);
  }
}
