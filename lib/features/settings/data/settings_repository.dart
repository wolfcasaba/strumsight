import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

/// The cloud copy of a user's settings profile (`GET/PUT /settings`).
@immutable
class RemoteSettings {
  const RemoteSettings({
    required this.themeMode,
    required this.locale,
    required this.confidenceThreshold,
    required this.tuningA4,
  });

  final ThemeMode themeMode;
  final Locale? locale; // null => follow the system language
  final double confidenceThreshold;
  final int tuningA4;

  factory RemoteSettings.fromJson(Map<String, dynamic> json) {
    final localeCode = json['locale'] as String?;
    return RemoteSettings(
      themeMode: _themeFromName(json['theme_mode'] as String?),
      locale: (localeCode == null || localeCode.isEmpty)
          ? null
          : Locale(localeCode),
      confidenceThreshold:
          (json['confidence_threshold'] as num?)?.toDouble() ?? 0.45,
      tuningA4: (json['tuning_a4'] as num?)?.toInt() ?? 440,
    );
  }

  static ThemeMode _themeFromName(String? name) {
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }
}

/// Reads/writes the authenticated user's cloud settings. The bearer token is
/// attached by the shared Dio interceptor. An interface so tests use a fake.
abstract interface class SettingsRepository {
  Future<RemoteSettings> fetch();

  /// Partial update — only the keys present are changed. `locale: null` is a
  /// meaningful value (follow system), matching the backend contract.
  Future<RemoteSettings> update(Map<String, dynamic> patch);
}

class HttpSettingsRepository implements SettingsRepository {
  HttpSettingsRepository(this._ref);

  final Ref _ref;

  @override
  Future<RemoteSettings> fetch() async {
    final dio = _ref.read(dioProvider);
    final res = await dio.get<Map<String, dynamic>>('/settings');
    return RemoteSettings.fromJson(res.data!);
  }

  @override
  Future<RemoteSettings> update(Map<String, dynamic> patch) async {
    final dio = _ref.read(dioProvider);
    final res = await dio.put<Map<String, dynamic>>('/settings', data: patch);
    return RemoteSettings.fromJson(res.data!);
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => HttpSettingsRepository(ref),
);
