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

/// One property context StrumSight actually uses for user-facing text.
final _textPropertyPattern = RegExp(
  r"(Text|label|title|message|hintText|semanticLabel|tooltip|description)"
  r"\s*[:(]\s*'([^']{3,})'",
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

String? _classify(String literalContent) {
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

Set<_Violation> _scan(Iterable<String> scopeDirs) {
  final violations = <_Violation>{};
  for (final dirPath in scopeDirs) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final match in _textPropertyPattern.allMatches(lines[i])) {
          final violationClass = _classify(match.group(2)!);
          if (violationClass == null) continue;
          violations.add((
            file: entity.path,
            line: i + 1,
            violationClass: violationClass,
          ));
        }
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
