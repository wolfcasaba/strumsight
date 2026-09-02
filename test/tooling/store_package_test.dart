import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_data_inventory.dart';

/// E12-R24 — Store listing, privacy and legal package.
///
/// A1: every `AndroidManifest.xml` permission has a named-feature,
/// named-data rationale in `docs/store/permissions-rationale.md`.
/// A2: every `docs/store/data-safety.yaml` category resolves to a real
/// `docs/privacy/data-inventory.yaml` route/field, and every
/// `leaves_device: true` field is covered by one.
/// A3: `docs/store/listing.md` never markets a capability that
/// `docs/testing/device-matrix.yaml` marks `ga_scope: false` (ADR 0477 D1).
/// A4: every `/…`-shaped app-route reference in the store/legal docs
/// exists in `lib/app/routing/app_route.dart`, and no doc claims a
/// client-triggered account-deletion endpoint that does not exist.
/// A5: the legal drafts carry a TERVEZET/DRAFT marker and a named
/// reviewer.
///
/// Every cell reads its "what's allowed" list from a real source file at
/// test time (manifest, data-inventory, device-matrix, app_route.dart) —
/// no permission list, capability list, or route list is hardcoded here
/// (round brief §0.0 R1/R3/R4). Every real-tree assertion below is paired
/// with a self-defense/regression cell that mutates a COPY of the parsed
/// data (never the file on disk) and proves the same check function turns
/// red — the mandatory real-violation probe (brief §6.1/§7) is additionally
/// demonstrated once, by hand, against the actual files; see round brief
/// §10 for that transcript.
void main() {
  final repository = Directory.current;
  String repoPath(String relative) => '${repository.path}/$relative';

  // ---------------------------------------------------------------------
  // A1 — AndroidManifest.xml permissions ↔ permissions-rationale.md
  // ---------------------------------------------------------------------

  group('A1 — every manifest permission has a named-feature, named-data '
      'rationale', () {
    test('the real main-variant manifest permissions are all covered, '
        'with no generic "the plugin requires it" rationale', () {
      final manifestPermissions = readManifestPermissions(
        File(repoPath('android/app/src/main/AndroidManifest.xml')),
      );
      expect(manifestPermissions, isNotEmpty);

      final rationale = parsePermissionRationale(
        File(
          repoPath('docs/store/permissions-rationale.md'),
        ).readAsStringSync(),
      );

      final violations = checkPermissionRationale(
        manifestPermissions: manifestPermissions,
        rationale: rationale,
      );
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('the CAMERA rationale explicitly marks itself optional AND non-GA, '
        'naming computer_vision / ga_scope: false', () {
      final content = File(
        repoPath('docs/store/permissions-rationale.md'),
      ).readAsStringSync();
      final rationale = parsePermissionRationale(content);
      final camera = rationale['android.permission.CAMERA'];
      expect(camera, isNotNull, reason: 'no CAMERA rationale block found');

      final block = _rationaleBlockFor(content, 'android.permission.CAMERA');
      final normalized = block.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        normalized,
        allOf(contains('computer_vision'), contains('ga_scope: false')),
        reason:
            'the CAMERA block must name the computer_vision capability '
            'and its ga_scope: false status (§0.0 R3) — got:\n$block',
      );
    });

    test('the two dev build variants requesting only INTERNET are named and '
        'excluded from the release rationale (§0.0 R3)', () {
      final content = File(
        repoPath('docs/store/permissions-rationale.md'),
      ).readAsStringSync();
      expect(content.toLowerCase(), contains('debug'));
      expect(content.toLowerCase(), contains('profile'));
      expect(content, contains('INTERNET'));

      // Source-measured, not assumed: the debug/profile manifests really
      // do request ONLY INTERNET today.
      for (final variant in ['debug', 'profile']) {
        final permissions = readManifestPermissions(
          File(repoPath('android/app/src/$variant/AndroidManifest.xml')),
        );
        expect(
          permissions,
          {'android.permission.INTERNET'},
          reason: 'the $variant manifest is expected to request only INTERNET',
        );
      }
    });

    // Mandatory real-violation probe, automated as a regression (the round
    // brief §6.1/§7 additionally demonstrates this once by hand against the
    // real file — see round brief §10).
    test('dropping RECORD_AUDIO out of a copy of the rationale map turns the '
        'cell red', () {
      final manifestPermissions = readManifestPermissions(
        File(repoPath('android/app/src/main/AndroidManifest.xml')),
      );
      final rationale = Map<String, PermissionRationale>.of(
        parsePermissionRationale(
          File(
            repoPath('docs/store/permissions-rationale.md'),
          ).readAsStringSync(),
        ),
      )..remove('android.permission.RECORD_AUDIO');

      final violations = checkPermissionRationale(
        manifestPermissions: manifestPermissions,
        rationale: rationale,
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('RECORD_AUDIO'));
    });

    test(
      'a rationale entry consisting only of "the plugin requires it" is '
      'rejected (§5.2 — "a Flutter plugin kéri" alone is not acceptable)',
      () {
        final broken = parsePermissionRationale('''
## android.permission.FIXTURE

- **Function:** The Flutter plugin requires it.
- **Data:** none
- **Optional:** No
''');
        final entry = broken['android.permission.FIXTURE']!;
        expect(
          entry.problems(),
          contains(contains('generic')),
          reason: 'a bare "plugin requires it" statement must be rejected',
        );
      },
    );

    test('the real 5 rationale entries never trip the generic-plugin-only '
        'rejection', () {
      final rationale = parsePermissionRationale(
        File(
          repoPath('docs/store/permissions-rationale.md'),
        ).readAsStringSync(),
      );
      for (final entry in rationale.values) {
        expect(
          entry.problems(),
          isEmpty,
          reason: '${entry.permission}: ${entry.problems().join(', ')}',
        );
      }
    });
  });

  // ---------------------------------------------------------------------
  // A2 — data-safety.yaml ↔ data-inventory.yaml (bidirectional)
  // ---------------------------------------------------------------------

  group('A2 — data-safety.yaml is DERIVED from data-inventory.yaml, '
      'bidirectionally (§5.1, §0.0 R4)', () {
    DataInventory realInventory() => DataInventory.parseFile(
      File(repoPath('docs/privacy/data-inventory.yaml')),
    );
    List<DataSafetyCategory> realDataSafety() => parseDataSafety(
      File(repoPath('docs/store/data-safety.yaml')).readAsLinesSync(),
    );

    test('every real data-safety reference resolves, and every leaves_device: '
        'true field is covered', () {
      final report = checkDataSafety(
        categories: realDataSafety(),
        inventory: realInventory(),
      );
      expect(report.isClean, isTrue, reason: report.violations.join('\n'));
    });

    test('there is at least one category and it covers a non-trivial '
        'number of fields (sanity, not a hardcoded count)', () {
      final categories = realDataSafety();
      expect(categories, isNotEmpty);
      expect(categories.every((c) => c.references.isNotEmpty), isTrue);
    });

    test('dropping the account_credentials category (email/password coverage) '
        'from a copy turns the cell red', () {
      final categories = realDataSafety()
          .where((c) => c.id != 'account_credentials')
          .toList();
      final report = checkDataSafety(
        categories: categories,
        inventory: realInventory(),
      );
      expect(report.isClean, isFalse);
      expect(report.violations.join('\n'), contains('email'));
    });

    test('pointing a reference at a route id the inventory does not declare '
        'turns the cell red', () {
      const broken = <String>[
        'categories:',
        '  - id: fixture_category',
        '    label: "fixture"',
        '    play_category: "fixture"',
        '    collected: true',
        '    shared: false',
        '    optional: true',
        '    purpose: "fixture"',
        '    references:',
        '      - route: nonexistent_route',
        '        field: "email"',
      ];
      final report = checkDataSafety(
        categories: parseDataSafety(broken),
        inventory: realInventory(),
      );
      expect(report.isClean, isFalse);
      expect(report.violations.join('\n'), contains('nonexistent_route'));
    });

    test('pointing a reference at a field name the target route does not '
        'declare turns the cell red', () {
      const broken = <String>[
        'categories:',
        '  - id: fixture_category',
        '    label: "fixture"',
        '    play_category: "fixture"',
        '    collected: true',
        '    shared: false',
        '    optional: true',
        '    purpose: "fixture"',
        '    references:',
        '      - route: account_api',
        '        field: "not_a_real_field"',
      ];
      final report = checkDataSafety(
        categories: parseDataSafety(broken),
        inventory: realInventory(),
      );
      expect(report.isClean, isFalse);
      expect(report.violations.join('\n'), contains('not_a_real_field'));
    });

    test('a rides-only route (no fields of its own) is not spuriously '
        'demanded a category (§0.0 R4)', () {
      final inventory = realInventory();
      final ridesRoutes = inventory.routes.where(
        (r) => r.rides.trim().isNotEmpty,
      );
      expect(ridesRoutes, isNotEmpty);
      for (final route in ridesRoutes) {
        expect(route.fields, isEmpty);
      }
      // The real A2 cell above already proves the full real tree is
      // clean, which is only possible if rides-only routes are not
      // separately demanded — this cell documents WHY (fields: []).
    });
  });

  // ---------------------------------------------------------------------
  // A3 — listing.md capability references ↔ device-matrix.yaml ga_scope
  // ---------------------------------------------------------------------

  group('A3 — listing.md never markets a ga_scope: false capability '
      '(ADR 0477 D1, §0.0 R1)', () {
    List<CapabilityEntry> realCapabilities() => parseCapabilities(
      File(repoPath('docs/testing/device-matrix.yaml')).readAsLinesSync(),
    );
    String realListing() =>
        File(repoPath('docs/store/listing.md')).readAsStringSync();

    test('the real device-matrix.yaml has both GA-true and GA-false '
        'capabilities (sanity — proves this is a real read, not an empty '
        'file)', () {
      final capabilities = realCapabilities();
      expect(capabilities.any((c) => c.gaScope), isTrue);
      expect(capabilities.any((c) => !c.gaScope), isTrue);
    });

    test('every capability id declared in listing.md\'s capabilities-marketed '
        'marker is a real, ga_scope: true capability', () {
      final marketed = parseMarketedCapabilityIds(realListing());
      expect(marketed, isNotEmpty);
      final violations = checkListingCapabilityScope(
        marketedIds: marketed,
        capabilities: realCapabilities(),
      );
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('the real listing.md prose does not mention any of the three '
        'ga_scope: false capabilities under any of their known signatures', () {
      final violations = checkListingProseAgainstCapabilitySignatures(
        listingText: realListing(),
        capabilities: realCapabilities(),
        signaturePatterns: capabilityMarketingSignaturePatterns,
      );
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    // Self-defense (§0.0 R1, §6.1): flip a MARKETED capability's ga_scope
    // in a COPY of the matrix — the cell must FLIP to red, proving the
    // check reads ga_scope live rather than trusting a fixed idea of
    // "this id is always fine".
    test('flipping a marketed capability\'s ga_scope to false in a copy of '
        'the matrix turns the cell red; flipping back restores clean', () {
      final marketed = parseMarketedCapabilityIds(realListing());
      final capabilities = realCapabilities();
      expect(
        checkListingCapabilityScope(
          marketedIds: marketed,
          capabilities: capabilities,
        ),
        isEmpty,
      );

      final targetId = marketed.first;
      final flipped = [
        for (final c in capabilities)
          if (c.id == targetId)
            CapabilityEntry(id: c.id, gaScope: false)
          else
            c,
      ];
      final violations = checkListingCapabilityScope(
        marketedIds: marketed,
        capabilities: flipped,
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains(targetId));

      final restored = [
        for (final c in flipped)
          if (c.id == targetId) CapabilityEntry(id: c.id, gaScope: true) else c,
      ];
      expect(
        checkListingCapabilityScope(
          marketedIds: marketed,
          capabilities: restored,
        ),
        isEmpty,
      );
    });

    test('an id in the marker that the matrix does not declare at all turns '
        'the cell red (typo protection)', () {
      final violations = checkListingCapabilityScope(
        marketedIds: const ['does_not_exist_in_matrix'],
        capabilities: realCapabilities(),
      );
      expect(violations, isNotEmpty);
    });

    // Self-defense for the prose-signature scan, both directions: a
    // currently-GA-true capability that the real listing text legitimately
    // mentions ("audio analysis") becomes forbidden the moment a COPY of
    // the matrix flips it to ga_scope: false — proving the prose scan is
    // ALSO driven by the live matrix, not a fixed forbidden-word list.
    test('prose scan: flipping audio_analysis_core to ga_scope: false in a '
        'copy makes the real listing text (which legitimately says "audio '
        'analysis") fail', () {
      final capabilities = realCapabilities();
      final flipped = [
        for (final c in capabilities)
          if (c.id == 'audio_analysis_core')
            CapabilityEntry(id: c.id, gaScope: false)
          else
            c,
      ];
      final violations = checkListingProseAgainstCapabilitySignatures(
        listingText: realListing(),
        capabilities: flipped,
        signaturePatterns: capabilityMarketingSignaturePatterns,
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('audio_analysis_core'));
    });

    // Other direction: a capability that IS forbidden today (computer_vision,
    // ga_scope: false) stops being flagged the moment a copy of the matrix
    // marks it ga_scope: true — even though the text (a fixture, since the
    // real listing.md never mentions it) uses "coming soon" phrasing, which
    // proves the scan is not fooled by a promise being hedged (§5.3).
    test('prose scan: a forbidden capability keyword, even hedged as "coming '
        'soon", is flagged today, and stops being flagged once its ga_scope '
        'copy flips to true', () {
      const fixtureText =
          'Preview: computer vision technique coaching is on the roadmap, '
          'coming soon.';
      final capabilities = realCapabilities();

      final forbidden = checkListingProseAgainstCapabilitySignatures(
        listingText: fixtureText,
        capabilities: capabilities,
        signaturePatterns: capabilityMarketingSignaturePatterns,
      );
      expect(forbidden, isNotEmpty);
      expect(forbidden.join('\n'), contains('computer_vision'));

      final flippedToTrue = [
        for (final c in capabilities)
          if (c.id == 'computer_vision')
            CapabilityEntry(id: c.id, gaScope: true)
          else
            c,
      ];
      final allowed = checkListingProseAgainstCapabilitySignatures(
        listingText: fixtureText,
        capabilities: flippedToTrue,
        signaturePatterns: capabilityMarketingSignaturePatterns,
      );
      expect(allowed, isEmpty);
    });

    // MAJOR-1 fix: the hand-maintained capabilityMarketingSignaturePatterns
    // map must cover every ga_scope: false capability the LIVE matrix
    // declares — read live, not a hardcoded id list, so growing the matrix
    // without extending the map is caught rather than silently skipped.
    test('every ga_scope: false capability in the real device-matrix.yaml '
        'has a capabilityMarketingSignaturePatterns entry (fail-closed '
        'coverage, MAJOR-1)', () {
      final nonGaIds = realCapabilities()
          .where((c) => !c.gaScope)
          .map((c) => c.id)
          .toSet();
      final missing = nonGaIds.difference(
        capabilityMarketingSignaturePatterns.keys.toSet(),
      );
      expect(
        missing,
        isEmpty,
        reason:
            'capabilityMarketingSignaturePatterns has no entry for: '
            '${missing.join(', ')}',
      );
    });

    // Self-defense (MAJOR-1, P7 reproduction): a ga_scope: false capability
    // with NO signature-pattern entry must turn the prose-scan cell red on
    // its own — proving the map's coverage gap is fail-closed rather than
    // a silent `continue`, regardless of what the prose says.
    test('a ga_scope: false capability with no signature-pattern entry '
        'turns the prose-scan cell red by itself (fail-closed — P7 '
        'reproduction)', () {
      final capabilities = [
        ...realCapabilities(),
        const CapabilityEntry(id: 'band_jam_mode', gaScope: false),
      ];
      final violations = checkListingProseAgainstCapabilitySignatures(
        listingText:
            '**Band Jam Mode.** Play along with a full backing '
            'band, coming soon.',
        capabilities: capabilities,
        signaturePatterns: capabilityMarketingSignaturePatterns,
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('band_jam_mode'));
    });
  });

  // ---------------------------------------------------------------------
  // A4 — app-route references + no fabricated account-deletion endpoint
  // ---------------------------------------------------------------------

  group('A4 — every referenced app route exists, and no doc claims a '
      'fabricated deletion endpoint/route (§0.0 R2)', () {
    // Every doc file this round produced, scanned as text. data-safety.yaml
    // is structured data, not prose, but its `purpose:` fields are free
    // text, so it is included too (MINOR-1) — coverage must be complete
    // across all five shipped documents, not four of five.
    final docFiles = <String>[
      'docs/store/listing.md',
      'docs/store/permissions-rationale.md',
      'docs/store/data-safety.yaml',
      'docs/legal/privacy-policy-draft.md',
      'docs/legal/community-guidelines-draft.md',
    ];

    Set<String> realAppRoutes() => parseAppRoutes(
      File(repoPath('lib/app/routing/app_route.dart')).readAsStringSync(),
    );

    test('the real app_route.dart yields a non-trivial route set (sanity)', () {
      final routes = realAppRoutes();
      expect(routes.length, greaterThan(10));
      expect(routes, contains('/settings'));
      expect(routes, contains('/tutor/privacy'));
      expect(routes, contains('/tutor/data'));
    });

    test('every backtick-quoted app-route token in the real docs exists in '
        'AppRoutes', () {
      final appRoutes = realAppRoutes();
      final violations = <String>[];
      for (final path in docFiles) {
        final content = File(repoPath(path)).readAsStringSync();
        violations.addAll(
          checkRouteReferences(
            content: content,
            appRoutes: appRoutes,
            sourceLabel: path,
          ),
        );
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    // Self-defense — the exact fabricated-route example the round brief
    // names (§0.0 R2, §6.1): `/privacy-center` does not exist as an
    // AppRoutes entry (PrivacyCenterScreen has no dedicated route constant
    // — it is reached via a plain MaterialPageRoute push from Settings).
    test('a fixture doc referencing the fabricated `/privacy-center` route '
        'turns the cell red', () {
      final appRoutes = realAppRoutes();
      expect(appRoutes, isNot(contains('/privacy-center')));
      const fixture =
          'Manage your data at the in-app `/privacy-center` screen.';
      final violations = checkRouteReferences(
        content: fixture,
        appRoutes: appRoutes,
        sourceLabel: 'fixture',
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('/privacy-center'));
    });

    test('none of the real docs claim a fabricated client-triggered account/'
        'auth deletion endpoint', () {
      final violations = <String>[];
      for (final path in docFiles) {
        final content = File(repoPath(path)).readAsStringSync();
        violations.addAll(checkNoFabricatedDeletionEndpoint(content, path));
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('a fixture doc claiming "DELETE /auth/me" turns the cell red', () {
      const fixture = 'Delete your account by calling DELETE /auth/me.';
      final violations = checkNoFabricatedDeletionEndpoint(fixture, 'fixture');
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('DELETE /auth/me'));
    });

    test('the real backend/app/routers/auth.py has exactly the three measured '
        'endpoints, none of them a deletion endpoint (source measurement '
        'backing §0.0 R2)', () {
      final content = File(
        repoPath('backend/app/routers/auth.py'),
      ).readAsStringSync();
      final endpoints = RegExp(
        r'@router\.(\w+)\("([^"]+)"',
      ).allMatches(content).map((m) => '${m.group(1)} ${m.group(2)}').toSet();
      expect(
        endpoints,
        {'post /register', 'post /login', 'get /me'},
        reason:
            'if this set changed, docs/legal/privacy-policy-draft.md §7 '
            'needs a re-check, not just this test',
      );
    });

    test(
      'privacy-policy-draft.md explicitly states no client-triggered '
      'account-deletion endpoint exists today, and names a support channel',
      () {
        final content = File(
          repoPath('docs/legal/privacy-policy-draft.md'),
        ).readAsStringSync();
        final violations = checkDeletionHonesty(
          content,
          'privacy-policy-draft.md',
        );
        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );

    test('a fixture privacy doc missing the honesty statement turns the cell '
        'red', () {
      const fixture = 'We take your privacy seriously.';
      final violations = checkDeletionHonesty(fixture, 'fixture');
      expect(violations, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // A5 — legal drafts carry a TERVEZET/DRAFT marker + named reviewer
  // ---------------------------------------------------------------------

  group('A5 — legal documents are marked TERVEZET/DRAFT with a named '
      'reviewer', () {
    const legalDocs = <String>[
      'docs/legal/privacy-policy-draft.md',
      'docs/legal/community-guidelines-draft.md',
    ];

    test('both real legal drafts carry the marker and a named reviewer', () {
      final violations = <String>[];
      for (final path in legalDocs) {
        final content = File(repoPath(path)).readAsStringSync();
        violations.addAll(checkDraftHeader(content, path));
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('a fixture legal doc with no TERVEZET/DRAFT marker turns the cell '
        'red', () {
      const fixture = '# Some Policy\n\nBody text with no marker at all.';
      final violations = checkDraftHeader(fixture, 'fixture');
      expect(violations, isNotEmpty);
    });
  });
}

// ===========================================================================
// A1 — permissions-rationale.md
// ===========================================================================

final _usesPermissionPattern = RegExp(
  r'<uses-permission\s+android:name="([\w.]+)"\s*/?>',
);

/// Reads the `uses-permission` names straight out of an
/// `AndroidManifest.xml` — no hardcoded permission list (§0.0 R3).
Set<String> readManifestPermissions(File manifest) {
  final content = manifest.readAsStringSync();
  return _usesPermissionPattern
      .allMatches(content)
      .map((m) => m.group(1)!)
      .toSet();
}

final class PermissionRationale {
  const PermissionRationale({
    required this.permission,
    required this.function,
    required this.data,
    required this.optional,
  });

  final String permission;
  final String function;
  final String data;
  final String optional;

  /// §5.2: every attribute must be present, and [function] must not be a
  /// bare "the plugin requires it" statement with no named feature/data.
  List<String> problems() {
    final problems = <String>[];
    if (function.trim().isEmpty) problems.add('Function');
    if (data.trim().isEmpty) problems.add('Data');
    if (optional.trim().isEmpty) problems.add('Optional');
    if (_genericPluginOnlyPattern.hasMatch(function.trim())) {
      problems.add(
        'generic "the plugin requires it" Function with no named feature/data',
      );
    }
    return problems;
  }
}

final _genericPluginOnlyPattern = RegExp(
  r'^(the\s+)?(flutter\s+)?plugin (requires|needs|requests) (it|this)\.?$',
  caseSensitive: false,
);

final _rationaleHeadingPattern = RegExp(
  r'^## (android\.permission\.[A-Z_]+)\s*$',
  multiLine: true,
);

/// Returns the raw text between one `## android.permission.X` heading and
/// the next heading of ANY kind (or EOF) — used where a caller needs the
/// full multi-line block, not just a single extracted bullet value.
String _rationaleBlockFor(String content, String permission) {
  final headings = _rationaleHeadingPattern.allMatches(content).toList();
  for (var i = 0; i < headings.length; i++) {
    if (headings[i].group(1) != permission) continue;
    final start = headings[i].end;
    final nextHeading = RegExp(
      r'^##',
      multiLine: true,
    ).allMatches(content, start).firstOrNull;
    final end = nextHeading?.start ?? content.length;
    return content.substring(start, end);
  }
  return '';
}

/// Extracts the (possibly multi-line, markdown-wrapped) value of a
/// `- **Label:** ...` bullet within [block], stopping at the next bullet or
/// the next `##` heading — a single-line regex would truncate a wrapped
/// sentence at the first `\n`.
String? _extractBulletValue(String block, String label) {
  final start = RegExp('- \\*\\*$label:\\*\\*\\s*').firstMatch(block);
  if (start == null) return null;
  final rest = block.substring(start.end);
  final next = RegExp(r'\n- \*\*|\n##', multiLine: true).firstMatch(rest);
  return rest.substring(0, next?.start ?? rest.length).trim();
}

Map<String, PermissionRationale> parsePermissionRationale(String content) {
  final headings = _rationaleHeadingPattern.allMatches(content).toList();
  final result = <String, PermissionRationale>{};
  for (var i = 0; i < headings.length; i++) {
    final permission = headings[i].group(1)!;
    final block = _rationaleBlockFor(content, permission);
    result[permission] = PermissionRationale(
      permission: permission,
      function: _extractBulletValue(block, 'Function') ?? '',
      data: _extractBulletValue(block, 'Data') ?? '',
      optional: _extractBulletValue(block, 'Optional') ?? '',
    );
  }
  return result;
}

/// A1: every manifest permission must have a rationale entry with no
/// [PermissionRationale.problems].
List<String> checkPermissionRationale({
  required Set<String> manifestPermissions,
  required Map<String, PermissionRationale> rationale,
}) {
  final violations = <String>[];
  for (final permission in manifestPermissions) {
    final entry = rationale[permission];
    if (entry == null) {
      violations.add(
        '$permission has no rationale entry in '
        'docs/store/permissions-rationale.md',
      );
      continue;
    }
    final problems = entry.problems();
    if (problems.isNotEmpty) {
      violations.add(
        '$permission rationale is missing: ${problems.join(', ')}',
      );
    }
  }
  return violations;
}

// ===========================================================================
// A2 — data-safety.yaml (restricted YAML subset, mirrors
// tool/check_data_inventory.dart's routes/fields nesting grammar)
// ===========================================================================

final class DataSafetyReference {
  const DataSafetyReference({required this.route, required this.field});
  final String route;
  final String field;
}

final class DataSafetyCategory {
  const DataSafetyCategory({
    required this.id,
    required this.label,
    required this.playCategory,
    required this.collected,
    required this.shared,
    required this.optional,
    required this.purpose,
    required this.references,
  });

  final String id;
  final String label;
  final String playCategory;
  final bool collected;
  final bool shared;
  final bool optional;
  final String purpose;
  final List<DataSafetyReference> references;
}

String _unquoteYamlValue(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

final _dsCategoryStart = RegExp(r'^  - id:\s*(.*)$');
final _dsCategoryKv = RegExp(r'^    (\w+):\s?(.*)$');
final _dsReferenceStart = RegExp(r'^      - route:\s*(.*)$');
final _dsReferenceKv = RegExp(r'^        (\w+):\s?(.*)$');

/// Parses `docs/store/data-safety.yaml`'s restricted grammar — NOT a
/// general YAML parser (`package:yaml` is a transitive-only dependency on
/// this tree, §0.0), scoped to exactly this document's own shape.
List<DataSafetyCategory> parseDataSafety(List<String> lines) {
  final categories = <DataSafetyCategory>[];

  String? id, label, playCategory, purpose;
  bool? collected, shared, optional;
  var references = <DataSafetyReference>[];

  String? refRoute, refField;
  var inReference = false;

  void flushReference() {
    if (!inReference) return;
    references.add(
      DataSafetyReference(route: refRoute ?? '', field: refField ?? ''),
    );
    refRoute = refField = null;
    inReference = false;
  }

  void flushCategory() {
    flushReference();
    if (id == null) return;
    categories.add(
      DataSafetyCategory(
        id: id!,
        label: label ?? '',
        playCategory: playCategory ?? '',
        collected: collected ?? false,
        shared: shared ?? false,
        optional: optional ?? false,
        purpose: purpose ?? '',
        references: List<DataSafetyReference>.unmodifiable(references),
      ),
    );
    id = label = playCategory = purpose = null;
    collected = shared = optional = null;
    references = <DataSafetyReference>[];
  }

  for (final raw in lines) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    if (raw.trim() == 'categories:') continue;
    if (raw.trim().startsWith('schema_version:')) continue;

    final categoryStart = _dsCategoryStart.firstMatch(raw);
    if (categoryStart != null) {
      flushCategory();
      id = _unquoteYamlValue(categoryStart.group(1)!);
      continue;
    }

    final referenceStart = _dsReferenceStart.firstMatch(raw);
    if (referenceStart != null) {
      flushReference();
      inReference = true;
      refRoute = _unquoteYamlValue(referenceStart.group(1)!);
      continue;
    }

    final referenceKv = inReference ? _dsReferenceKv.firstMatch(raw) : null;
    if (referenceKv != null) {
      final key = referenceKv.group(1)!;
      final value = _unquoteYamlValue(referenceKv.group(2)!);
      if (key == 'field') {
        refField = value;
      } else {
        throw FormatException('data-safety.yaml: unknown reference key "$key"');
      }
      continue;
    }

    final categoryKv = !inReference ? _dsCategoryKv.firstMatch(raw) : null;
    if (categoryKv != null) {
      final key = categoryKv.group(1)!;
      final value = categoryKv.group(2)!;
      switch (key) {
        case 'label':
          label = _unquoteYamlValue(value);
        case 'play_category':
          playCategory = _unquoteYamlValue(value);
        case 'collected':
          collected = value.trim() == 'true';
        case 'shared':
          shared = value.trim() == 'true';
        case 'optional':
          optional = value.trim() == 'true';
        case 'purpose':
          purpose = _unquoteYamlValue(value);
        case 'references':
          break; // nested block starts on the following `- route:` lines.
        default:
          throw FormatException(
            'data-safety.yaml: unknown category key "$key"',
          );
      }
      continue;
    }

    throw FormatException('data-safety.yaml: unrecognized line: $raw');
  }
  flushCategory();

  return categories;
}

final class DataSafetyReport {
  const DataSafetyReport(this.violations);
  final List<String> violations;
  bool get isClean => violations.isEmpty;
}

/// A2, both directions (§0.0 R4): every category reference resolves to a
/// real inventory route id / field name, and every `leaves_device: true`
/// inventory field is covered by at least one category.
DataSafetyReport checkDataSafety({
  required List<DataSafetyCategory> categories,
  required DataInventory inventory,
}) {
  final violations = <String>[];
  final routesById = {for (final r in inventory.routes) r.id: r};

  for (final category in categories) {
    for (final ref in category.references) {
      final route = routesById[ref.route];
      if (route == null) {
        violations.add(
          'data-safety category "${category.id}" references unknown route '
          'id "${ref.route}"',
        );
        continue;
      }
      final fieldExists = route.fields.any((f) => f.name == ref.field);
      if (!fieldExists) {
        violations.add(
          'data-safety category "${category.id}" references field '
          '"${ref.field}" on route "${ref.route}", which has no such field',
        );
      }
    }
  }

  final covered = <String>{
    for (final category in categories)
      for (final ref in category.references) '${ref.route}::${ref.field}',
  };
  for (final route in inventory.routes) {
    for (final field in route.fields) {
      if (!field.leavesDevice) continue;
      final key = '${route.id}::${field.name}';
      if (!covered.contains(key)) {
        violations.add(
          'inventory field "${route.id}/${field.name}" has leaves_device: '
          'true but no docs/store/data-safety.yaml category references it',
        );
      }
    }
  }

  return DataSafetyReport(violations);
}

// ===========================================================================
// A3 — listing.md ↔ device-matrix.yaml capabilities
// ===========================================================================

final class CapabilityEntry {
  const CapabilityEntry({required this.id, required this.gaScope});
  final String id;
  final bool gaScope;
}

final _capabilityStart = RegExp(r'^  - id:\s*(.*)$');
final _capabilityKv = RegExp(r'^    (\w+):\s?(.*)$');

/// Restricted reader for JUST the `capabilities:` block of
/// `docs/testing/device-matrix.yaml` (id + ga_scope) — mirrors
/// `test/tooling/device_matrix_test.dart`'s `parseDeviceMatrix` grammar
/// (2-space list items, 4-space kv), scoped to only what A3 needs. No
/// `package:yaml` (§0.0 R1).
List<CapabilityEntry> parseCapabilities(List<String> lines) {
  final capabilities = <CapabilityEntry>[];
  var inCapabilities = false;
  var i = 0;
  while (i < lines.length) {
    final raw = lines[i];
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) {
      i++;
      continue;
    }
    if (raw == 'capabilities:') {
      inCapabilities = true;
      i++;
      continue;
    }
    if (!raw.startsWith(' ')) {
      inCapabilities = false;
      i++;
      continue;
    }
    if (!inCapabilities) {
      i++;
      continue;
    }
    final header = _capabilityStart.firstMatch(raw);
    if (header == null) {
      i++;
      continue;
    }
    final id = _unquoteYamlValue(header.group(1)!);
    var gaScope = false;
    var gaScopeSeen = false;
    i++;
    while (i < lines.length) {
      final kv = _capabilityKv.firstMatch(lines[i]);
      if (kv == null) break;
      if (kv.group(1) == 'ga_scope') {
        gaScope = kv.group(2)!.trim() == 'true';
        gaScopeSeen = true;
      }
      i++;
    }
    if (!gaScopeSeen) {
      throw FormatException(
        'device-matrix.yaml: capability "$id" has no ga_scope',
      );
    }
    capabilities.add(CapabilityEntry(id: id, gaScope: gaScope));
  }
  return capabilities;
}

final _capabilitiesMarketedPattern = RegExp(
  r'<!--\s*capabilities-marketed:\s*(.*?)\s*-->',
  dotAll: true,
);

/// Reads listing.md's own author-declared "which capability ids does this
/// listing market" marker — a self-declared list checked against the
/// device-matrix source, NOT a list this test hardcodes (§0.0 R1).
List<String> parseMarketedCapabilityIds(String listingContent) {
  final match = _capabilitiesMarketedPattern.firstMatch(listingContent);
  if (match == null) {
    throw FormatException('listing.md has no capabilities-marketed marker');
  }
  return match
      .group(1)!
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// A3 (marker-based): every id listing.md declares as marketed must exist
/// in the matrix AND be `ga_scope: true`.
List<String> checkListingCapabilityScope({
  required List<String> marketedIds,
  required List<CapabilityEntry> capabilities,
}) {
  final violations = <String>[];
  final byId = {for (final c in capabilities) c.id: c};
  for (final id in marketedIds) {
    final entry = byId[id];
    if (entry == null) {
      violations.add(
        'listing.md markets unknown capability id "$id" (not declared in '
        'docs/testing/device-matrix.yaml)',
      );
      continue;
    }
    if (!entry.gaScope) {
      violations.add(
        'listing.md markets "$id", but device-matrix.yaml has ga_scope: '
        'false for it',
      );
    }
  }
  return violations;
}

/// Lexical signatures used to detect PROSE mentions of a capability — this
/// maps an id to how it might be worded, it does NOT say which ids are
/// GA-scope (that always comes from the live [CapabilityEntry] list passed
/// in below), so it is not the "beégetett GA-lista" §0.0 R1 forbids.
const Map<String, String> capabilityMarketingSignaturePatterns = {
  'computer_vision':
      r'computer vision|vision coach|camera-based (chord|technique)',
  'offline_ai': r'offline ai|on-device ai model|local ai model',
  'ai_tutor': r'ai tutor|ai (guitar )?coach chat|chat with an ai',
  'audio_analysis_core': r'audio analysis',
};

/// A3 (prose scan): flags any GA-false capability whose signature matches
/// [listingText], regardless of hedging ("coming soon") — §5.3. Fail-closed
/// (MAJOR-1): a ga_scope: false capability with no entry in
/// [signaturePatterns] is itself a violation — the map's coverage must be
/// complete, not silently skipped, or an unmapped capability could be
/// marketed with zero prose-scan protection.
List<String> checkListingProseAgainstCapabilitySignatures({
  required String listingText,
  required List<CapabilityEntry> capabilities,
  required Map<String, String> signaturePatterns,
}) {
  final violations = <String>[];
  for (final capability in capabilities) {
    if (capability.gaScope) continue;
    final pattern = signaturePatterns[capability.id];
    if (pattern == null) {
      violations.add(
        'capabilityMarketingSignaturePatterns has no entry for ga_scope: '
        'false capability "${capability.id}" — the prose scan cannot '
        'verify it is unmarketed (fail-closed: add a signature pattern)',
      );
      continue;
    }
    final match = RegExp(pattern, caseSensitive: false).firstMatch(listingText);
    if (match != null) {
      violations.add(
        'listing text mentions "${capability.id}" (matched '
        '"${match.group(0)}"), but device-matrix.yaml has ga_scope: false '
        'for it',
      );
    }
  }
  return violations;
}

// ===========================================================================
// A4 — app-route references + fabricated-deletion-endpoint guard
// ===========================================================================

final _appRouteLiteralPattern = RegExp(
  r"static const String \w+ =\s*'([^']+)';",
);

/// Reads every route string literal declared in `app_route.dart` — no
/// hardcoded route list (§0.0 R2).
Set<String> parseAppRoutes(String content) =>
    _appRouteLiteralPattern.allMatches(content).map((m) => m.group(1)!).toSet();

final _backtickRouteToken = RegExp(r'`(/[a-zA-Z0-9][\w\-/:]*)`');

/// A4: every backtick-quoted, `/`-shaped token in [content] must be a real
/// AppRoutes entry.
List<String> checkRouteReferences({
  required String content,
  required Set<String> appRoutes,
  required String sourceLabel,
}) {
  final violations = <String>[];
  for (final match in _backtickRouteToken.allMatches(content)) {
    final token = match.group(1)!;
    if (!appRoutes.contains(token)) {
      violations.add(
        '$sourceLabel references app route "$token", which does not exist '
        'in lib/app/routing/app_route.dart',
      );
    }
  }
  return violations;
}

final _fabricatedDeletionEndpointPattern = RegExp(
  r'DELETE\s+/(auth|account)[\w/]*',
  caseSensitive: false,
);

/// A4: no doc may claim a client-triggered account/auth deletion endpoint —
/// the fan measurably has none (§0.0 R2, backend/app/routers/auth.py).
List<String> checkNoFabricatedDeletionEndpoint(
  String content,
  String sourceLabel,
) {
  return [
    for (final match in _fabricatedDeletionEndpointPattern.allMatches(content))
      '$sourceLabel claims a client-triggered deletion endpoint '
          '"${match.group(0)}", which does not exist in '
          'backend/app/routers/auth.py',
  ];
}

const _requiredNoDeletionEndpointPhrase =
    'does not have a client-triggered account-deletion endpoint';

/// A4: the privacy policy must say, in these words, that no client-triggered
/// deletion endpoint exists, and must name a support/contact channel —
/// otherwise the honesty requirement (§0.0 R2) is unenforced prose.
List<String> checkDeletionHonesty(String content, String sourceLabel) {
  final violations = <String>[];
  // Normalized (whitespace-collapsed) so a markdown line-wrap in the middle
  // of the required phrase does not produce a false negative.
  final lower = content.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (!lower.contains(_requiredNoDeletionEndpointPhrase)) {
    violations.add(
      '$sourceLabel does not state, in the required words, that no '
      'client-triggered account-deletion endpoint exists '
      '("$_requiredNoDeletionEndpointPhrase")',
    );
  }
  final hasSupportChannel =
      lower.contains('@') &&
      (lower.contains('support') || lower.contains('e-mail'));
  if (!hasSupportChannel) {
    violations.add(
      '$sourceLabel does not name a support/e-mail channel for deletion '
      'requests',
    );
  }
  return violations;
}

// ===========================================================================
// A5 — TERVEZET/DRAFT marker + named reviewer
// ===========================================================================

List<String> checkDraftHeader(String content, String sourceLabel) {
  final violations = <String>[];
  final head = content.length > 1000 ? content.substring(0, 1000) : content;
  if (!RegExp(r'TERVEZET|DRAFT', caseSensitive: false).hasMatch(head)) {
    violations.add('$sourceLabel has no TERVEZET/DRAFT marker near the top');
  }
  if (!RegExp(r'review|felülvizsgál', caseSensitive: false).hasMatch(head)) {
    violations.add(
      '$sourceLabel has no named review-responsible line near the top',
    );
  }
  return violations;
}
