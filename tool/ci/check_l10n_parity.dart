import 'dart:convert';
import 'dart:io';

import '../gen_l10n_segments.dart' as segments;

/// The kinds of localization gap enforced by the CI gate.
enum L10nIssueKind {
  missingTranslation,
  extraTranslation,
  placeholderMismatch,
  emptyMessage,
}

/// One localization defect, identified by ARB key.
final class L10nIssue {
  const L10nIssue({
    required this.key,
    required this.kind,
    required this.detail,
  });

  final String key;
  final L10nIssueKind kind;
  final String detail;
}

/// Complete result of comparing the template ARB against a translation.
final class L10nParityReport {
  L10nParityReport({
    required this.templateLocale,
    required this.locale,
    required this.messageCount,
    required List<L10nIssue> issues,
  }) : issues = List.unmodifiable(issues);

  final String templateLocale;
  final String locale;
  final int messageCount;
  final List<L10nIssue> issues;

  bool get isClean => issues.isEmpty;

  String format() {
    if (isClean) {
      return 'L10n parity OK ($templateLocale → $locale, $messageCount message(s)).';
    }
    final output = StringBuffer(
      'L10n parity failed ($templateLocale → $locale, '
      '${issues.length} issue(s)).',
    );
    for (final issue in issues) {
      final description = switch (issue.kind) {
        L10nIssueKind.missingTranslation => 'hiányzik a fordításból',
        L10nIssueKind.extraTranslation => 'csak a fordításban létezik',
        L10nIssueKind.placeholderMismatch => 'eltérő helyőrzők',
        L10nIssueKind.emptyMessage => 'üres üzenet',
      };
      output
        ..writeln()
        ..write(
          '- ${issue.key}: $description${issue.detail.isEmpty ? '' : ' (${issue.detail})'}',
        );
    }
    return output.toString();
  }
}

final RegExp _placeholder = RegExp(r'\{(\w+)\}');

/// Compares a translation ARB against the template ARB.
///
/// This closes the mechanical half of ARCH-008 ("minden user-facing string
/// lokalizált"): it proves every template key has a non-empty translation with
/// the same placeholders.  It deliberately does NOT prove that the UI routes
/// every string through ARB — a hardcoded literal in a widget is invisible
/// here, and stays the reviewer's job (ADR 0138 §7).
L10nParityReport checkL10nParity({
  required File template,
  required File translation,
  String templateLocale = 'en',
  String locale = 'hu',
}) {
  final templateMessages = _messages(template);
  final translationMessages = _messages(translation);
  final issues = <L10nIssue>[];

  for (final entry in templateMessages.entries) {
    final translated = translationMessages[entry.key];
    if (translated == null) {
      issues.add(
        L10nIssue(
          key: entry.key,
          kind: L10nIssueKind.missingTranslation,
          detail: '',
        ),
      );
      continue;
    }
    if (translated.trim().isEmpty) {
      issues.add(
        L10nIssue(key: entry.key, kind: L10nIssueKind.emptyMessage, detail: ''),
      );
      continue;
    }
    final expected = _placeholderNames(entry.value);
    final actual = _placeholderNames(translated);
    if (!_sameSet(expected, actual)) {
      issues.add(
        L10nIssue(
          key: entry.key,
          kind: L10nIssueKind.placeholderMismatch,
          detail:
              '$templateLocale: ${_sorted(expected)} · $locale: ${_sorted(actual)}',
        ),
      );
    }
  }

  for (final key in translationMessages.keys) {
    if (!templateMessages.containsKey(key)) {
      issues.add(
        L10nIssue(key: key, kind: L10nIssueKind.extraTranslation, detail: ''),
      );
    }
  }

  issues.sort((a, b) => a.key.compareTo(b.key));
  return L10nParityReport(
    templateLocale: templateLocale,
    locale: locale,
    messageCount: templateMessages.length,
    issues: issues,
  );
}

/// The locales whose `lib/l10n/app_<locale>.arb` aggregate is GENERATED from
/// ARB segments (`lib/l10n/base/` + `lib/l10n/features/`).
const List<String> generatedLocales = ['en', 'hu'];

/// Whether every generated ARB aggregate on disk still matches its segments.
final class L10nFreshnessReport {
  L10nFreshnessReport({required List<String> problems})
    : problems = List.unmodifiable(problems);

  final List<String> problems;

  bool get isClean => problems.isEmpty;

  String format() {
    if (isClean) {
      return 'L10n aggregate freshness OK (${generatedLocales.join(', ')}).';
    }
    final output = StringBuffer(
      'L10n aggregate freshness failed (${problems.length} issue(s)).',
    );
    for (final problem in problems) {
      output
        ..writeln()
        ..write('- $problem');
    }
    return output.toString();
  }
}

/// Runs the generator's `--check` branch in-process (ADR 0307 §4, E99-R17 D2).
///
/// A gate `l10n` lépése eddig CSAK a paritást mérte, a frissességet nem: a
/// `lib/l10n/app_<locale>.arb` kézzel szerkeszthető maradt, és az elavult
/// aggregátum ZÖLDEN ment át. Ez a hívás a MEGLÉVŐ lépést bővíti, nem vezet
/// be újat — a `tools/round-gate.sh` és a CI composite lépéslistája így
/// változatlan marad (az ADR 0171 paritás-őre nem sérül).
///
/// A generátort RELATÍV IMPORTtal hívjuk, nem alfolyamattal: így a `dart run`
/// egyetlen fordítási egységben méri a két invariánst, és a lépés kimenete
/// nem függ egy beágyazott folyamat útvonalától vagy kilépési kódjától.
L10nFreshnessReport checkGeneratedAggregates({required Directory projectRoot}) {
  final problems = <String>[];
  for (final locale in generatedLocales) {
    final segments.GenerationOutcome outcome;
    try {
      outcome = segments.generateLocale(
        locale: locale,
        projectRoot: projectRoot,
        check: true,
      );
    } on FormatException catch (error) {
      problems.add('[$locale] ${error.message}');
      continue;
    }
    for (final message in outcome.errors) {
      problems.add('[$locale] $message');
    }
    if (outcome.stale) {
      problems.add(
        '[$locale] az aggregátum elavult — futtasd: '
        'dart run tool/gen_l10n_segments.dart --write',
      );
    }
  }
  return L10nFreshnessReport(problems: problems);
}

/// ARB message entries, excluding `@`-prefixed metadata and the `@@` header.
Map<String, String> _messages(File arb) {
  final decoded = jsonDecode(arb.readAsStringSync()) as Map<String, dynamic>;
  return <String, String>{
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value as String,
  };
}

Set<String> _placeholderNames(String message) =>
    _placeholder.allMatches(message).map((match) => match.group(1)!).toSet();

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

String _sorted(Set<String> names) =>
    names.isEmpty ? '—' : (names.toList()..sort()).join(', ');

void main() {
  final root = Directory.current;

  // A két invariáns EGYÜTT dől el: a frissesség hibája nem takarhatja el a
  // paritásét, ezért mindkettő lefut és mindkettő kiíródik, mielőtt a lépés
  // pirosra vált.
  final freshness = checkGeneratedAggregates(projectRoot: root);
  stdout.writeln(freshness.format());

  final report = checkL10nParity(
    template: File('${root.path}/lib/l10n/app_en.arb'),
    translation: File('${root.path}/lib/l10n/app_hu.arb'),
  );
  stdout.writeln(report.format());

  if (!freshness.isClean || !report.isClean) exitCode = 1;
}
