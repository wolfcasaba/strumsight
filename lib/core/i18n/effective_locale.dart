import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'locale_provider.dart';

/// English — the last resort, never the answer to "follow the system".
const Locale _fallbackLocale = Locale('en');

/// The locale provider-side code must render its copy in (re-audit
/// 2026-09-08, M5).
///
/// [localeProvider] is `null` for "follow the system", and that is its
/// DEFAULT: a user who never opened the language setting has `null` stored.
/// Both provider-side call sites used to collapse that `null` straight to
/// English, so a Hungarian phone whose owner never picked a language by hand
/// read an English plan label inside an otherwise Hungarian app — the widget
/// side (`MaterialApp.locale: null`) has always resolved the platform locale
/// for exactly that case, and this is the same resolution for code that has
/// no `BuildContext`.
///
/// Order of precedence:
///
///   1. an explicit [preferred] locale — the user's own choice wins, even
///      over a differently-configured phone;
///   2. [platformLocales], in the platform's own priority order;
///   3. [_fallbackLocale], reached only when this build ships no translation
///      for any of them (including a cloud-synced settings row naming a
///      language this build does not have).
///
/// The returned locale is always language-code-only, so it can be handed to
/// `lookupAppLocalizations` — which matches on the language code — without
/// a country/script subtag that no ARB file is keyed by.
Locale resolveEffectiveLocale(
  Locale? preferred, {
  required List<Locale> platformLocales,
}) {
  if (preferred != null) {
    return _supportedOrNull(preferred) ?? _fallbackLocale;
  }
  for (final candidate in platformLocales) {
    final supported = _supportedOrNull(candidate);
    if (supported != null) return supported;
  }
  return _fallbackLocale;
}

Locale? _supportedOrNull(Locale candidate) {
  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == candidate.languageCode) {
      return Locale(candidate.languageCode);
    }
  }
  return null;
}

/// The platform's preferred locales, highest priority first.
///
/// A provider rather than a direct dispatcher read inside
/// [effectiveLocaleProvider] so a test can state what language the phone is
/// in, and so the one platform read on the tree stays in a single,
/// overridable place. `locales` is empty on some hosts — the single `locale`
/// is the documented fallback there.
///
/// `PlatformDispatcher.instance` rather than
/// `WidgetsBinding.instance.platformDispatcher`: they are the same object in
/// the running app, but the binding one is only reachable AFTER a binding
/// exists, and this provider is read from plain (non-widget) provider tests
/// where none has been initialized.
final platformLocalesProvider = Provider<List<Locale>>((_) {
  final dispatcher = PlatformDispatcher.instance;
  final locales = dispatcher.locales;
  return locales.isEmpty ? <Locale>[dispatcher.locale] : locales;
});

/// [localeProvider] resolved against the platform — what provider-side code
/// reads when it needs a CONCRETE locale, never `localeProvider` itself.
final effectiveLocaleProvider = Provider<Locale>(
  (ref) => resolveEffectiveLocale(
    ref.watch(localeProvider),
    platformLocales: ref.watch(platformLocalesProvider),
  ),
);
