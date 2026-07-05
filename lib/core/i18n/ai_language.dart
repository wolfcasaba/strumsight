import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

/// The language code to request AI output in: the user's chosen app locale
/// (persisted by LocaleNotifier under the 'app_locale' key), else the device
/// locale, else English. Sent as `language` to the AI Edge Functions so M3
/// replies in the user's language.
Future<String> resolveAiLanguage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('app_locale');
    if (code != null && code.isNotEmpty) return code;
  } catch (_) {}
  final dev = ui.PlatformDispatcher.instance.locale.languageCode;
  return dev.isNotEmpty ? dev : 'en';
}
