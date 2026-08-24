import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The minimum length ratio the pseudo-locale transform must reach (ADR 0424
/// §5.4) — long enough that clipping caused by real Hungarian translations
/// (which run longer than English) shows up before it ships.
const double ssPseudoLocaleExpansionFactor = 1.6;

/// `{identifier}` ICU placeholders — matched non-greedily and non-nested,
/// which is all [ssPseudoLocalize] needs: it never rewrites what's inside
/// the braces, only the literal text around them.
final RegExp _placeholderPattern = RegExp(r'\{[^{}]+\}');

/// Same-length lookalike replacements for common Latin letters — a purely
/// cosmetic stress signal (real pseudo-loc tooling does the same); it never
/// changes string length, so it cannot affect the expansion ratio below.
const Map<String, String> _accentLookalikes = {
  'a': 'á',
  'A': 'Á',
  'e': 'é',
  'E': 'É',
  'i': 'í',
  'I': 'Í',
  'o': 'ó',
  'O': 'Ó',
  'u': 'ú',
  'U': 'Ú',
  'c': 'ç',
  'C': 'Ç',
  'n': 'ñ',
  'N': 'Ñ',
  's': 'ś',
  'S': 'Ś',
  'y': 'ý',
  'Y': 'Ý',
  'z': 'ź',
  'Z': 'Ź',
  'g': 'ǵ',
  'G': 'Ǵ',
};

String _accent(String literal) =>
    literal.split('').map((ch) => _accentLookalikes[ch] ?? ch).join();

/// Breakable filler (spaced every 4 characters, like real words) so the
/// padding can still wrap in a layout instead of forcing an artificial,
/// unbreakable overflow.
String _filler(int minChars) {
  final buffer = StringBuffer();
  var written = 0;
  while (written < minChars) {
    if (written > 0 && written % 4 == 0) buffer.write(' ');
    buffer.write('~');
    written++;
  }
  return buffer.toString();
}

/// Test-only pseudo-localization transform (ADR 0424 §5.4/§5.7): expands
/// [input] by at least [ssPseudoLocaleExpansionFactor] while leaving every
/// `{placeholder}` token untouched, so widget tests can catch layout
/// clipping before a real, longer translation does. This is NOT a
/// registered [Locale] — StrumSight ships only en/hu, and `supportedLocales`
/// lives in `lib/app/strumsight_app.dart`, outside this round's scope.
String ssPseudoLocalize(String input) {
  if (input.isEmpty) return input;

  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in _placeholderPattern.allMatches(input)) {
    buffer.write(_accent(input.substring(cursor, match.start)));
    buffer.write(match.group(0));
    cursor = match.end;
  }
  buffer.write(_accent(input.substring(cursor)));
  final transformed = buffer.toString();

  final minLength = (input.length * ssPseudoLocaleExpansionFactor).ceil();
  final body = '[$transformed]';
  if (body.length >= minLength) return body;

  final filler = _filler(minLength - body.length);
  return '[$transformed $filler]';
}

/// Test-side `Localizations` ancestor (ADR 0424 §5.7 — a wrapper, not a new
/// locale): mounts [child] under the app's real en delegates so
/// design-system components that expect an ambient `Localizations` render
/// correctly, while the pseudo-localized text itself is supplied by the
/// caller via [child], not by this wrapper.
Widget ssPseudoLocaleTestHarness({
  required Widget child,
  double textScale = 1.0,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: Scaffold(body: child),
  );
}
