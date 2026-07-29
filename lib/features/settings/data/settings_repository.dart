import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/network/api_client.dart';
import '../../auth/public.dart';

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

  factory RemoteSettings.fromJson(Map<String, Object?> json) {
    final themeName = json['theme_mode'];
    final localeValue = json['locale'];
    final thresholdValue = json['confidence_threshold'];
    final tuningValue = json['tuning_a4'];

    if (themeName is! String ||
        !ThemeMode.values.any((mode) => mode.name == themeName)) {
      throw const FormatException('Invalid remote theme mode.');
    }
    if (localeValue != null &&
        (localeValue is! String || localeValue.trim().isEmpty)) {
      throw const FormatException('Invalid remote locale.');
    }
    if (thresholdValue is! num ||
        !thresholdValue.isFinite ||
        thresholdValue < 0 ||
        thresholdValue > 1) {
      throw const FormatException('Invalid remote confidence threshold.');
    }
    if (tuningValue is! int || tuningValue < 400 || tuningValue > 480) {
      throw const FormatException('Invalid remote tuning reference.');
    }

    final localeCode = localeValue as String?;
    return RemoteSettings(
      themeMode: ThemeMode.values.firstWhere((mode) => mode.name == themeName),
      locale: (localeCode == null || localeCode.isEmpty)
          ? null
          : Locale(localeCode),
      confidenceThreshold: thresholdValue.toDouble(),
      tuningA4: tuningValue,
    );
  }
}

/// Reads/writes the authenticated user's cloud settings. The bearer token is
/// attached by the shared Dio interceptor. An interface so tests use a fake.
abstract interface class SettingsRepository {
  Future<AppResult<RemoteSettings>> fetch();

  /// Partial update — only the keys present are changed. `locale: null` is a
  /// meaningful value (follow system), matching the backend contract.
  Future<AppResult<RemoteSettings>> update(Map<String, Object?> patch);
}

class HttpSettingsRepository implements SettingsRepository {
  HttpSettingsRepository(this._client);

  final ApiClient _client;

  @override
  Future<AppResult<RemoteSettings>> fetch() =>
      _client.getJson('/settings', decode: RemoteSettings.fromJson);

  @override
  Future<AppResult<RemoteSettings>> update(Map<String, Object?> patch) =>
      _client.putJson(
        '/settings',
        data: patch,
        decode: RemoteSettings.fromJson,
      );
}

final class DisabledSettingsRepository implements SettingsRepository {
  const DisabledSettingsRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<AppResult<RemoteSettings>> fetch() async => _disabled;

  @override
  Future<AppResult<RemoteSettings>> update(Map<String, Object?> patch) async =>
      _disabled;
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final client = ref.watch(accountApiClientProvider);
  return client == null
      ? const DisabledSettingsRepository()
      : HttpSettingsRepository(client);
});
