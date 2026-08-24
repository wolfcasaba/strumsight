import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against two distinct anti-patterns in the design system's core
/// visual vocabulary (ADR 0424 §5.5): a hardcoded, never-localized English
/// sentence (A3), and a sentence assembled at the call site by gluing an
/// ARB fragment to other literal/dynamic content (A2, §5.1) — Hungarian
/// word order and inflection break the moment two independently-localized
/// pieces get concatenated.
///
/// Scope is EXACTLY these four directories (measured, ADR 0424 §0.0/M5):
///  - `documentation/` is excluded — a dev-only component gallery, never
///    routed into product UI (zero references outside its own file and the
///    barrel export), so its illustrative sample strings are not a leak.
///  - `foundations/`, `themes/`, `icons/` are excluded — token/theme layers
///    that carry no user-facing sentence at all.
const _scopeDirs = <String>[
  'lib/core/design_system/components',
  'lib/core/design_system/accessibility',
  'lib/core/design_system/layouts',
  'lib/core/design_system/motion',
];

/// One property context StrumSight actually uses for user-facing text. Runs
/// against the WHOLE (comment-stripped) file, not line-by-line (F2): a
/// `dart format`-wrapped multi-arg call splits the literal onto its own
/// line (`Text(\n  'Save changes',\n  textAlign: ...\n)`), which a
/// single-line pattern can never see. `\s` (used between the property name
/// and the literal) matches newlines by default, so this bridges that gap.
/// An optional `l10n.x +` / `AppLocalizations.x +` immediately before, or
/// `+ l10n.x` / `+ AppLocalizations.x` immediately after, the literal
/// captures the `'$count ' + t.songs`-shaped concatenation §5.1 names by
/// example (F1) — `_classify` treats either as A2 regardless of what the
/// literal alone would say.
final _textPropertyPattern = RegExp(
  r"(?:Text|label|title|message|hintText|semanticLabel|tooltip|description)"
  r"\s*[:(]\s*"
  r"(?<prefix>(?:(?:l10n\.\w+|AppLocalizations\.\w+)\s*\+\s*)*)"
  r"'(?<literal>(?:[^'\\]|\\.){3,})'"
  r"(?<suffix>(?:\s*\+\s*(?:l10n\.\w+|AppLocalizations\.\w+))*)",
);

/// `${expr}` and bare `$identifier` interpolations inside a string literal.
final _interpolationPattern = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_]\w*');

final _l10nReferencePattern = RegExp(r'\bl10n\.\w+');

/// Real alphabetic word content, i.e. NOT just punctuation/digits left over
/// once interpolations are stripped out.
final _wordLikePattern = RegExp(r'[A-Za-z]{2,}');

/// One violation the guard's scanner found: a source location plus which
/// rule it broke.
typedef _Violation = ({String file, int line, String violationClass});

String? _classify(String literalContent, {required bool concatenatedWithL10n}) {
  // F1: the literal is glued to an ARB fragment via `+` at the call site —
  // sentence concatenation regardless of what the literal alone contains
  // (`'$count '` alone has no `l10n.` reference and would otherwise read as
  // A3, missing the actual defect: word order baked in at the call site).
  if (concatenatedWithL10n) return 'A2';

  final interpolationCount = _interpolationPattern
      .allMatches(literalContent)
      .length;
  final referencesL10n = _l10nReferencePattern.hasMatch(literalContent);
  final literalRemainder = literalContent.replaceAll(_interpolationPattern, '');
  final hasWordLikeRemainder = _wordLikePattern.hasMatch(literalRemainder);

  if (!referencesL10n) {
    // No ARB fragment at all: real words here are a hardcoded string (A3).
    return hasWordLikeRemainder ? 'A3' : null;
  }
  // References an ARB fragment, but glues something else onto it — either
  // a second interpolation or extra literal wording (A2).
  if (interpolationCount >= 2 || hasWordLikeRemainder) return 'A2';
  return null;
}

/// Blanks out `//` and `/* */` comments (preserving length and newlines, so
/// match offsets keep mapping onto real line numbers) without touching
/// string-literal content, even a literal that itself contains `//` (e.g. a
/// URL) — tracked via a minimal quote/escape-aware scan rather than a regex,
/// since a regex can't tell "inside a string" from "inside a comment".
String _stripComments(String source) {
  final buffer = StringBuffer();
  var i = 0;
  final len = source.length;
  while (i < len) {
    final ch = source[i];
    if (ch == "'" || ch == '"') {
      final quote = ch;
      buffer.write(ch);
      i++;
      while (i < len) {
        final c = source[i];
        if (c == r'\' && i + 1 < len) {
          buffer.write(c);
          buffer.write(source[i + 1]);
          i += 2;
          continue;
        }
        buffer.write(c);
        i++;
        if (c == quote) break;
      }
      continue;
    }
    if (ch == '/' && i + 1 < len && source[i + 1] == '/') {
      while (i < len && source[i] != '\n') {
        buffer.write(' ');
        i++;
      }
      continue;
    }
    if (ch == '/' && i + 1 < len && source[i + 1] == '*') {
      buffer.write('  ');
      i += 2;
      while (i < len &&
          !(source[i] == '*' && i + 1 < len && source[i + 1] == '/')) {
        buffer.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < len) {
        buffer.write('  ');
        i += 2;
      }
      continue;
    }
    buffer.write(ch);
    i++;
  }
  return buffer.toString();
}

int _lineOf(String content, int offset) {
  var line = 1;
  for (var i = 0; i < offset; i++) {
    if (content.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

Set<_Violation> _scan(Iterable<String> scopeDirs) {
  final violations = <_Violation>{};
  for (final dirPath in scopeDirs) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final stripped = _stripComments(entity.readAsStringSync());
      for (final match in _textPropertyPattern.allMatches(stripped)) {
        final concatenatedWithL10n =
            match.namedGroup('prefix')!.isNotEmpty ||
            match.namedGroup('suffix')!.isNotEmpty;
        final violationClass = _classify(
          match.namedGroup('literal')!,
          concatenatedWithL10n: concatenatedWithL10n,
        );
        if (violationClass == null) continue;
        violations.add((
          file: entity.path,
          line: _lineOf(stripped, match.start),
          violationClass: violationClass,
        ));
      }
    }
  }
  return violations;
}

void main() {
  // §5.8 — a RATCHET, not an exemption list: exact-set equality against the
  // scan result. A NEW violation turns this red (cannot silently grow); a
  // FIXED violation left in this set ALSO turns it red (the list cannot
  // silently go stale once the underlying line is fixed elsewhere).
  //
  // lib/core/design_system/components/inputs/ss_validation_summary.dart:90
  //   `label: '${l10n.dsFieldErrorSemanticPrefix}: $message'` — A2 sentence
  //   concatenation (an ARB "Error"/"Hiba" prefix glued to the caller's
  //   already-localized `message` via a hardcoded ": " separator). Not
  //   fixable in this round: the only fix is changing what `SsFieldError`
  //   receives at its call sites, all of which are outside E13-R15's
  //   allowed-files list (ADR 0424 §4).
  const frozenViolations = <_Violation>{
    (
      file:
          'lib/core/design_system/components/inputs/ss_validation_summary.dart',
      line: 90,
      violationClass: 'A2',
    ),
  };

  test(
    'no hardcoded or sentence-concatenated text beyond the frozen baseline (A2/A3)',
    () {
      final found = _scan(_scopeDirs);

      final newViolations = found.difference(frozenViolations);
      expect(
        newViolations,
        isEmpty,
        reason:
            'new hardcoded-string / sentence-concatenation violation(s), not '
            'in the frozen baseline: $newViolations',
      );

      final staleFrozenEntries = frozenViolations.difference(found);
      expect(
        staleFrozenEntries,
        isEmpty,
        reason:
            'frozenViolations lists entr(y/ies) that no longer reproduce — '
            'the underlying line changed or was fixed; update the frozen '
            'list (ADR 0424 §5.8: it must track reality exactly, never lag '
            'behind it): $staleFrozenEntries',
      );
    },
  );
}
