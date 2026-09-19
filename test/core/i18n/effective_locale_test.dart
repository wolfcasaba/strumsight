// M5 (re-audit 2026-09-08) — "follow the system" must resolve to the SYSTEM
// language, not to English.
//
// MEASURED before this round: `localeProvider` is `null` by default ("follow
// the system"), and both provider-side call sites — the Today Hub's plan
// copy (`today_providers.dart`) and the generated plan's own text
// (`practice_generator_providers.dart`) — collapsed that `null` straight to
// `Locale('en')`. A Hungarian phone whose owner never opened the language
// setting therefore showed English plan copy inside an otherwise Hungarian
// app.
//
//   A1 — no preference + a Hungarian phone resolves to hu,
//   A2 — no preference + a phone this build has no translation for is en,
//   A3 — an explicit preference wins over the phone, in both directions,
//   A4 — a preference this build cannot honour falls back to en (the same
//        answer `MaterialApp`'s own resolution gives an unsupported
//        `locale:`), never to a third language,
//   A5 — the resolved locale is language-code only, so it can be handed to
//        `lookupAppLocalizations`,
//   A6 — the provider wiring reads the stored preference AND the platform.
library;

import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/i18n/effective_locale.dart';
import 'package:strumsight/core/i18n/locale_provider.dart';
import 'package:strumsight/core/storage/storage_keys.dart';

import '../../support/preference_store.dart';

const _hungarianPhone = <Locale>[Locale('hu', 'HU')];
const _germanPhone = <Locale>[Locale('de', 'DE')];

ProviderContainer _container({
  Map<String, Object>? preferences,
  List<Locale> platformLocales = _hungarianPhone,
}) {
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(preferences),
      platformLocalesProvider.overrideWithValue(platformLocales),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('resolveEffectiveLocale', () {
    test('A1 no preference follows the phone', () {
      expect(
        resolveEffectiveLocale(null, platformLocales: _hungarianPhone),
        const Locale('hu'),
      );
    });

    test('A1b the phone list is honoured in ITS priority order', () {
      expect(
        resolveEffectiveLocale(
          null,
          platformLocales: const [Locale('de'), Locale('hu')],
        ),
        const Locale('hu'),
        reason:
            'the first locale this build actually ships wins — German is '
            'skipped, not treated as "unsupported, therefore English"',
      );
    });

    test('A2 an untranslatable phone falls back to English', () {
      expect(
        resolveEffectiveLocale(null, platformLocales: _germanPhone),
        const Locale('en'),
      );
    });

    test('A2b an empty platform list falls back to English', () {
      expect(
        resolveEffectiveLocale(null, platformLocales: const <Locale>[]),
        const Locale('en'),
      );
    });

    test('A3 an explicit preference wins over the phone', () {
      expect(
        resolveEffectiveLocale(
          const Locale('en'),
          platformLocales: _hungarianPhone,
        ),
        const Locale('en'),
      );
      expect(
        resolveEffectiveLocale(
          const Locale('hu'),
          platformLocales: const [Locale('en')],
        ),
        const Locale('hu'),
      );
    });

    test('A4 a preference this build cannot honour is English', () {
      expect(
        resolveEffectiveLocale(
          const Locale('de'),
          platformLocales: _hungarianPhone,
        ),
        const Locale('en'),
        reason:
            'a cloud-synced settings row naming a language this build does '
            'not ship must not silently switch the app to a THIRD language',
      );
    });

    test('A5 the result carries no country subtag', () {
      final resolved = resolveEffectiveLocale(
        const Locale('hu', 'HU'),
        platformLocales: const <Locale>[],
      );

      expect(resolved, const Locale('hu'));
      expect(resolved.countryCode, isNull);
    });
  });

  group('effectiveLocaleProvider', () {
    test('A6 an unset preference resolves the phone language', () {
      final container = _container();

      expect(container.read(localeProvider), isNull);
      expect(container.read(effectiveLocaleProvider), const Locale('hu'));
    });

    test('A6b a stored preference wins over the phone', () {
      final container = _container(
        preferences: {StorageKeys.locale: 'en'},
        platformLocales: _hungarianPhone,
      );

      expect(container.read(effectiveLocaleProvider), const Locale('en'));
    });

    test('A6c an untranslatable phone still resolves to English', () {
      final container = _container(platformLocales: _germanPhone);

      expect(container.read(effectiveLocaleProvider), const Locale('en'));
    });
  });
}
