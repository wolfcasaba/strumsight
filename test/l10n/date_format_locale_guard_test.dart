import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `DateFormat.MMMd()` / `DateFormat.yMMMd()` with NO locale argument falls
/// back to `Intl.defaultLocale`, which the app never sets — so the string
/// renders `en_US` ("Aug 25") no matter what the user picked, while the
/// sentence around it is Hungarian. AGENTS.md §7 ("minden felhasználói
/// szöveg ARB lokalizáció") is about the same defect class: a user-facing
/// string that ignores the active locale.
///
/// The repo already has two correct references — `SsFormatters` in
/// `lib/core/i18n/ss_formatters.dart` (locale is a REQUIRED parameter) and
/// `WeeklyBars` in `lib/features/progress/widgets/weekly_bars.dart`
/// (`Localizations.localeOf(context).toString()` handed down) — so this
/// guard pins the convention rather than inventing one.
void main() {
  /// `DateFormat.<skeleton>()` with an empty argument list.
  final localelessSkeleton = RegExp(r'\bDateFormat\.[A-Za-z_]\w*\(\s*\)');

  /// Known, still-unfixed call site OUTSIDE this round's file ownership
  /// (round A3 scope rule): `practice_result_screen.dart` belongs to the
  /// practice feature. Listed here so the guard protects everything else
  /// immediately; the entry is itself asserted to still be a violation, so
  /// it cannot silently rot once that file is fixed.
  const knownPending = <String>{
    'lib/features/practice/presentation/screens/practice_result_screen.dart',
  };

  List<String> dartSourcesUnderLib() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((p) => p.endsWith('.dart'))
      // The generated localisation delegates are not hand-written UI code.
      .where((p) => !p.startsWith('lib/l10n/'))
      .toList()
    ..sort();

  Set<String> offenders() => {
    for (final path in dartSourcesUnderLib())
      if (localelessSkeleton.hasMatch(File(path).readAsStringSync())) path,
  };

  test('no user-facing DateFormat skeleton is built without a locale', () {
    expect(
      offenders().difference(knownPending),
      isEmpty,
      reason:
          'DateFormat.<skeleton>() with no locale always renders en_US; pass '
          'Localizations.localeOf(context).toString() the way '
          'lib/features/progress/widgets/weekly_bars.dart does',
    );
  });

  test('the known-pending allowlist has not rotted', () {
    expect(
      knownPending.difference(offenders()),
      isEmpty,
      reason:
          'these files no longer build a locale-less DateFormat — drop them '
          'from knownPending so the guard covers them too',
    );
  });
}
