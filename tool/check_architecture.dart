import 'dart:io';

import 'gen_public_barrel.dart' as barrel;

/// Existing architecture deviations, recorded as
/// `<source file> -> <imported file or package URI>`.
///
/// This allowlist may only shrink. Adding an entry requires a written
/// justification and an ADR. The check intentionally fails for stale entries,
/// so a resolved deviation cannot remain hidden here.
const architectureAllowlist = <String>{
  'lib/features/analyze/engine/clip_analyzer.dart -> lib/features/live/engine/dsp/chord_dictionary.dart',
  'lib/features/analyze/engine/clip_analyzer.dart -> lib/features/live/engine/dsp/dsp_config.dart',
  'lib/features/analyze/engine/clip_analyzer.dart -> lib/features/live/engine/dsp/live_pipeline.dart',
  'lib/features/analyze/engine/clip_analyzer.dart -> lib/features/live/engine/dsp/nnls_chroma.dart',
  'lib/features/analyze/engine/clip_analyzer.dart -> lib/features/live/engine/dsp/strum_direction_classifier.dart',
  'lib/features/analyze/engine/clip_analyzer.dart -> lib/features/live/engine/dsp/viterbi_chord_decoder.dart',
  'lib/features/analyze/engine/ml_chord_decoder.dart -> lib/features/live/engine/dsp/cqt_extractor.dart',
  'lib/features/analyze/engine/ml_chord_decoder.dart -> lib/features/live/engine/dsp/viterbi_chord_decoder.dart',
  'lib/features/analyze/engine/ml_chord_decoder.dart -> lib/features/live/engine/ml/chord_crnn.dart',
  'lib/features/analyze/providers/analyze_providers.dart -> lib/features/live/engine/ml/chord_crnn.dart',
  'lib/features/analyze/providers/analyze_providers.dart -> lib/features/live/engine/ml/crnn_strum_net.dart',
  'lib/features/analyze/providers/analyze_providers.dart -> lib/features/live/engine/ml/strum_crnn.dart',
};

/// Architecture boundaries enforced by the first dependency guard.
enum ArchitectureRule {
  coreMustNotImportFeatures,
  sharedDomainMustRemainFrameworkIndependent,
  crossFeatureImportsMustUsePublicApi,
  designSystemImportsMustUsePublicBarrel,
  rawVisionPayloadMustNotPersist,
  rawVisionPayloadMustNotEnterProviderState,
}

/// One dependency that violates an [ArchitectureRule].
final class ArchitectureViolation {
  const ArchitectureViolation({
    required this.sourcePath,
    required this.target,
    required this.rule,
  });

  final String sourcePath;
  final String target;
  final ArchitectureRule rule;

  String get key => '$sourcePath -> $target';
}

/// Complete result of checking a project against an exact allowlist.
final class ArchitectureReport {
  ArchitectureReport({
    required List<ArchitectureViolation> violations,
    required Set<String> allowlist,
  }) : violations = List.unmodifiable(violations),
       unexpectedViolations = List.unmodifiable(
         violations.where(
           (violation) =>
               violation.rule !=
                   ArchitectureRule.crossFeatureImportsMustUsePublicApi ||
               !allowlist.contains(violation.key),
         ),
       ),
       staleAllowlistEntries = List.unmodifiable(
         (allowlist
             .difference(
               violations
                   .where(
                     (item) =>
                         item.rule ==
                         ArchitectureRule.crossFeatureImportsMustUsePublicApi,
                   )
                   .map((item) => item.key)
                   .toSet(),
             )
             .toList()
           ..sort()),
       );

  /// Every violation found in the source tree, including allowlisted ones.
  final List<ArchitectureViolation> violations;

  /// Violations absent from the checked allowlist.
  final List<ArchitectureViolation> unexpectedViolations;

  /// Allowlist entries whose dependency no longer violates a rule.
  final List<String> staleAllowlistEntries;

  bool get isClean =>
      unexpectedViolations.isEmpty && staleAllowlistEntries.isEmpty;

  /// Human-readable CLI/test failure output.
  String format() {
    if (isClean) {
      return 'Architecture dependencies OK '
          '(${violations.length} allowlisted deviation(s)).';
    }

    final output = StringBuffer('Architecture dependency check failed.');
    if (unexpectedViolations.isNotEmpty) {
      output.writeln();
      output.writeln(
        'Unexpected violation(s) — fix them; adding an allowlist entry '
        'requires justification and an ADR:',
      );
      for (final violation in unexpectedViolations) {
        output.writeln(
          '- ${violation.key} '
          '[${_ruleDescription(violation.rule)}]',
        );
      }
    }
    if (staleAllowlistEntries.isNotEmpty) {
      output.writeln();
      output.writeln(
        'Stale allowlist entry/entries — remove them because the allowlist '
        'may only shrink:',
      );
      for (final entry in staleAllowlistEntries) {
        output.writeln('- $entry');
      }
    }
    return output.toString().trimRight();
  }
}

/// Checks all Dart import/export/part dependencies below `<projectRoot>/lib`.
///
/// Relative URIs and `package:strumsight/...` URIs are normalized to the same
/// repository-relative `lib/...` form before applying the boundary rules.
ArchitectureReport checkArchitecture({
  required Directory projectRoot,
  Set<String> allowlist = architectureAllowlist,
}) {
  final libDirectory = Directory('${projectRoot.absolute.path}/lib');
  if (!libDirectory.existsSync()) {
    throw FileSystemException(
      'Architecture check requires a lib/ directory',
      libDirectory.path,
    );
  }

  final dartFiles =
      libDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final violations = <ArchitectureViolation>[];

  for (final file in dartFiles) {
    final sourcePath = _projectRelativePath(projectRoot, file);
    final source = file.readAsStringSync();
    for (final dependency in _directiveUris(source)) {
      final targetPath = _resolveProjectUri(sourcePath, dependency.uri);
      _collectViolations(
        violations: violations,
        sourcePath: sourcePath,
        rawUri: _canonicalUriForRules(dependency.uri),
        targetPath: targetPath,
      );
      if (dependency.isPart && targetPath != null) {
        // A part shares its owner's library scope and imports. Check that
        // relationship in both directions so a feature cannot absorb a file
        // physically located under core and bypass the core boundary.
        _collectViolations(
          violations: violations,
          sourcePath: targetPath,
          rawUri: sourcePath,
          targetPath: sourcePath,
        );
      }
    }
    _collectRawVisionPayloadViolations(
      violations: violations,
      sourcePath: sourcePath,
      source: source,
    );
  }

  final uniqueViolations = <String, ArchitectureViolation>{
    for (final violation in violations)
      '${violation.rule.index}:${violation.key}': violation,
  }.values.toList();
  uniqueViolations.sort((left, right) {
    final keyOrder = left.key.compareTo(right.key);
    if (keyOrder != 0) return keyOrder;
    return left.rule.index.compareTo(right.rule.index);
  });
  return ArchitectureReport(violations: uniqueViolations, allowlist: allowlist);
}

const _rawVisionPayloadTypes = <String>{
  'VisionImage',
  'GrayscaleFrame',
  'Uint8List',
  'ByteData',
  'ByteBuffer',
  'VisionPixelFormat',
};

void _collectRawVisionPayloadViolations({
  required List<ArchitectureViolation> violations,
  required String sourcePath,
  required String source,
}) {
  const visionPrefix = 'lib/features/vision/';
  if (!sourcePath.startsWith(visionPrefix)) return;

  final code = _codeWithoutTrivia(source);
  if (sourcePath.startsWith('${visionPrefix}data/persistence/')) {
    for (final type in _rawVisionPayloadTypes) {
      if (_containsIdentifier(code, type)) {
        violations.add(
          ArchitectureViolation(
            sourcePath: sourcePath,
            target: 'raw vision payload $type in persistence',
            rule: ArchitectureRule.rawVisionPayloadMustNotPersist,
          ),
        );
      }
    }
  }

  if (!sourcePath.startsWith('${visionPrefix}application/')) return;
  for (final body in _providerStateBodies(code)) {
    for (final type in _rawVisionPayloadTypes) {
      if (_containsIdentifier(body, type)) {
        violations.add(
          ArchitectureViolation(
            sourcePath: sourcePath,
            target: 'raw vision payload $type in provider state',
            rule: ArchitectureRule.rawVisionPayloadMustNotEnterProviderState,
          ),
        );
      }
    }
  }
}

bool _containsIdentifier(String source, String identifier) =>
    RegExp('\\b${RegExp.escape(identifier)}\\b').hasMatch(source);

Iterable<String> _providerStateBodies(String source) sync* {
  final declarations = RegExp(
    r'(?:(?:abstract|base|final|interface|sealed)\s+)*class\s+'
    r'[A-Za-z_$][A-Za-z0-9_$]*State\b',
  );
  for (final declaration in declarations.allMatches(source)) {
    final openingBrace = source.indexOf('{', declaration.end);
    if (openingBrace < 0) continue;
    final closingBrace = _matchingBrace(source, openingBrace);
    if (closingBrace == null) continue;
    yield source.substring(openingBrace + 1, closingBrace);
  }
}

int? _matchingBrace(String source, int openingBrace) {
  var depth = 0;
  for (var index = openingBrace; index < source.length; index++) {
    final character = source.codeUnitAt(index);
    if (character == _leftBrace) depth++;
    if (character == _rightBrace) depth--;
    if (depth == 0) return index;
  }
  return null;
}

String _codeWithoutTrivia(String source) {
  final output = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (character == _slash && index + 1 < source.length) {
      final next = source.codeUnitAt(index + 1);
      if (next == _slash) {
        while (index < source.length && source.codeUnitAt(index) != _lineFeed) {
          output.write(' ');
          index++;
        }
        continue;
      }
      if (next == _asterisk) {
        var depth = 1;
        output.write('  ');
        index += 2;
        while (index < source.length && depth > 0) {
          if (index + 1 < source.length &&
              source.codeUnitAt(index) == _slash &&
              source.codeUnitAt(index + 1) == _asterisk) {
            depth++;
            output.write('  ');
            index += 2;
          } else if (index + 1 < source.length &&
              source.codeUnitAt(index) == _asterisk &&
              source.codeUnitAt(index + 1) == _slash) {
            depth--;
            output.write('  ');
            index += 2;
          } else {
            output.write(source.codeUnitAt(index) == _lineFeed ? '\\n' : ' ');
            index++;
          }
        }
        continue;
      }
    }
    final raw =
        (character == _lowercaseR || character == _uppercaseR) &&
        index + 1 < source.length &&
        _isQuote(source.codeUnitAt(index + 1));
    if (_isQuote(character) || raw) {
      final literal = _readString(source, raw ? index + 1 : index, raw: raw);
      final length = literal.nextIndex - index;
      output.write(' ' * length);
      index = literal.nextIndex;
      continue;
    }
    output.writeCharCode(character);
    index++;
  }
  return output.toString();
}

void _collectViolations({
  required List<ArchitectureViolation> violations,
  required String sourcePath,
  required String rawUri,
  required String? targetPath,
}) {
  if (sourcePath.startsWith('lib/core/') &&
      targetPath != null &&
      targetPath.startsWith('lib/features/')) {
    violations.add(
      ArchitectureViolation(
        sourcePath: sourcePath,
        target: targetPath,
        rule: ArchitectureRule.coreMustNotImportFeatures,
      ),
    );
  }

  if (_isSharedDomain(sourcePath) &&
      _isForbiddenDomainDependency(rawUri, targetPath)) {
    violations.add(
      ArchitectureViolation(
        sourcePath: sourcePath,
        target: targetPath ?? rawUri,
        rule: ArchitectureRule.sharedDomainMustRemainFrameworkIndependent,
      ),
    );
  }

  if (_isDesignSystemBarrelBypass(sourcePath, targetPath)) {
    violations.add(
      ArchitectureViolation(
        sourcePath: sourcePath,
        target: targetPath!,
        rule: ArchitectureRule.designSystemImportsMustUsePublicBarrel,
      ),
    );
  }

  final sourceFeature = _featureName(sourcePath);
  final targetFeature = targetPath == null ? null : _featureName(targetPath);
  if (sourceFeature != null &&
      targetFeature != null &&
      sourceFeature != targetFeature &&
      !_isFeaturePublicBarrel(targetPath, targetFeature)) {
    violations.add(
      ArchitectureViolation(
        sourcePath: sourcePath,
        target: targetPath!,
        rule: ArchitectureRule.crossFeatureImportsMustUsePublicApi,
      ),
    );
  }
}

/// A cross-feature import is legal only when it targets a `public.dart` barrel
/// of the destination feature. Both the feature-root barrel
/// (`lib/features/<f>/public.dart`) and any deliberately-authored nested barrel
/// (e.g. `lib/features/song_trainer/domain/public.dart`, designated by ADR 0089
/// as *the* cross-feature entry point) are reviewed public surfaces and count.
/// Reaching any non-`public.dart` file inside the feature remains a violation.
/// See ADR 0176 (ADR 0112 self-heal, 2026-08-06) for the measured rationale.
bool _isFeaturePublicBarrel(String? targetPath, String targetFeature) {
  if (targetPath == null) return false;
  return targetPath.startsWith('lib/features/$targetFeature/') &&
      targetPath.endsWith('/public.dart');
}

/// The design system (`lib/core/design_system/**`) has exactly one entry point
/// for the rest of `lib/`: its `public.dart` barrel (E13-R02 contract, pinned
/// by `test/core/architecture_dependency_test.dart` — "real production source
/// reaches the design system only via public.dart"). Anything else is a deep
/// import that couples a screen to the design system's internal file layout.
///
/// MEASURED (E15-R09, H5 self-heal, ADR 0112, 2026-09-03): until this rule
/// existed, the contract was measured ONLY by the full CI suite. A migration
/// round's targeted gate (`gate_tests`) and the gate's own `architecture` step
/// both ran green over 24 deep imports across five migrated Tutor screens, and
/// the violation surfaced only in CI — twice — which is an H5 halt of the whole
/// round pipeline. Placing it here means every round's `tools/round-gate.sh`
/// `architecture` step measures it locally, before any push.
///
/// The design system's own files are exempt: internal cohesion is what the
/// barrel exists to hide.
bool _isDesignSystemBarrelBypass(String sourcePath, String? targetPath) {
  const designSystemRoot = 'lib/core/design_system/';
  if (targetPath == null) return false;
  if (!targetPath.startsWith(designSystemRoot)) return false;
  if (sourcePath.startsWith(designSystemRoot)) return false;
  return targetPath != '${designSystemRoot}public.dart';
}

bool _isSharedDomain(String sourcePath) =>
    sourcePath.startsWith('lib/core/music/') ||
    sourcePath.startsWith('lib/core/audio/codec/') ||
    sourcePath.startsWith('lib/features/practice/domain/');

bool _isForbiddenDomainDependency(String rawUri, String? targetPath) {
  const forbiddenPackagePrefixes = <String>[
    'package:flutter/',
    'package:flutter_localizations/',
    'package:flutter_riverpod/',
    'package:riverpod/',
    'package:dio/',
    'package:shared_preferences/',
  ];
  if (forbiddenPackagePrefixes.any(rawUri.startsWith)) return true;
  if (rawUri.startsWith('package:flutter_gen/gen_l10n/')) return true;
  return targetPath == 'lib/l10n.dart' ||
      (targetPath?.startsWith('lib/l10n/') ?? false);
}

String? _featureName(String path) {
  const prefix = 'lib/features/';
  if (!path.startsWith(prefix)) return null;
  final remainder = path.substring(prefix.length);
  final separator = remainder.indexOf('/');
  if (separator <= 0) return null;
  return remainder.substring(0, separator);
}

String? _resolveProjectUri(String sourcePath, String uri) {
  final parsedUri = Uri.tryParse(uri);
  if (parsedUri == null) return null;
  if (parsedUri.scheme == 'package') {
    const projectPackagePrefix = 'strumsight/';
    final packagePath = parsedUri.path;
    if (packagePath.startsWith(projectPackagePrefix)) {
      return _normalizePath(
        'lib/${packagePath.substring(projectPackagePrefix.length)}',
      );
    }
    return null;
  }
  if (uri.isNotEmpty && !uri.startsWith('/') && !parsedUri.hasScheme) {
    final separator = sourcePath.lastIndexOf('/');
    final sourceDirectory = separator < 0
        ? ''
        : sourcePath.substring(0, separator);
    return _normalizePath('$sourceDirectory/${parsedUri.path}');
  }
  return null;
}

String _canonicalUriForRules(String uri) {
  final parsedUri = Uri.tryParse(uri);
  if (parsedUri == null) return uri;
  if (parsedUri.scheme == 'package') return 'package:${parsedUri.path}';
  if (!parsedUri.hasScheme) return parsedUri.path;
  return '${parsedUri.scheme}:${parsedUri.path}';
}

String _normalizePath(String path) {
  final segments = <String>[];
  for (final segment in path.replaceAll(r'\', '/').split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

String _projectRelativePath(Directory projectRoot, File file) {
  final rootPath = projectRoot.absolute.path.replaceAll(r'\', '/');
  final filePath = file.absolute.path.replaceAll(r'\', '/');
  final prefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
  if (!filePath.startsWith(prefix)) {
    throw FileSystemException(
      'Dart source is outside the project root',
      file.path,
    );
  }
  return filePath.substring(prefix.length);
}

Iterable<({String uri, bool isPart})> _directiveUris(String source) sync* {
  var index = 0;
  while (index < source.length) {
    index = _skipTrivia(source, index);
    if (index >= source.length) return;

    final character = source.codeUnitAt(index);
    if (_isQuote(character)) {
      index = _readString(source, index).nextIndex;
      continue;
    }
    if (!_isIdentifierStart(character)) {
      index++;
      continue;
    }

    final tokenStart = index;
    index++;
    while (index < source.length &&
        _isIdentifierPart(source.codeUnitAt(index))) {
      index++;
    }
    final token = source.substring(tokenStart, index);
    if ((token == 'r' || token == 'R') &&
        index < source.length &&
        _isQuote(source.codeUnitAt(index))) {
      index = _readString(source, index, raw: true).nextIndex;
      continue;
    }
    if (token != 'import' && token != 'export' && token != 'part') continue;
    if (token == 'part') {
      final afterTrivia = _skipTrivia(source, index);
      if (_identifierAt(source, afterTrivia, 'of')) {
        final directive = _readDirective(source, afterTrivia + 'of'.length);
        for (final uri in directive.uris) {
          yield (uri: uri, isPart: false);
        }
        index = directive.nextIndex;
        continue;
      }
    }

    final directive = _readDirective(source, index);
    for (final uri in directive.uris) {
      yield (uri: uri, isPart: token == 'part');
    }
    index = directive.nextIndex;
  }
}

({List<String> uris, int nextIndex}) _readDirective(String source, int index) {
  final uris = <String>[];
  while (index < source.length) {
    index = _skipTrivia(source, index);
    if (index >= source.length) break;
    if (source.codeUnitAt(index) == _semicolon) {
      return (uris: uris, nextIndex: index + 1);
    }
    final character = source.codeUnitAt(index);
    final isRawPrefix =
        (character == _lowercaseR || character == _uppercaseR) &&
        index + 1 < source.length &&
        _isQuote(source.codeUnitAt(index + 1));
    if (_isQuote(character) || isRawPrefix) {
      final literal = _readString(
        source,
        isRawPrefix ? index + 1 : index,
        raw: isRawPrefix,
      );
      uris.add(literal.contents);
      index = literal.nextIndex;
      continue;
    }
    index++;
  }
  return (uris: uris, nextIndex: index);
}

({String contents, int nextIndex}) _readString(
  String source,
  int index, {
  bool raw = false,
}) {
  final quote = source.codeUnitAt(index);
  final triple =
      index + 2 < source.length &&
      source.codeUnitAt(index + 1) == quote &&
      source.codeUnitAt(index + 2) == quote;
  final delimiterLength = triple ? 3 : 1;
  index += delimiterLength;
  final contents = StringBuffer();

  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (!raw && character == _backslash) {
      final escape = _readEscape(source, index);
      contents.write(escape.value);
      index = escape.nextIndex;
      continue;
    }
    if (character == quote) {
      if (!triple ||
          (index + 2 < source.length &&
              source.codeUnitAt(index + 1) == quote &&
              source.codeUnitAt(index + 2) == quote)) {
        return (
          contents: contents.toString(),
          nextIndex: index + delimiterLength,
        );
      }
    }
    contents.writeCharCode(character);
    index++;
  }
  return (contents: contents.toString(), nextIndex: source.length);
}

({String value, int nextIndex}) _readEscape(String source, int index) {
  if (index + 1 >= source.length) {
    return (value: r'\', nextIndex: source.length);
  }

  final escaped = source.codeUnitAt(index + 1);
  final simple = switch (escaped) {
    0x6e => '\n',
    0x72 => '\r',
    0x66 => '\f',
    0x62 => '\b',
    0x74 => '\t',
    0x76 => '\v',
    _ => null,
  };
  if (simple != null) return (value: simple, nextIndex: index + 2);

  if (escaped == _lowercaseX &&
      index + 3 < source.length &&
      _isHexDigit(source.codeUnitAt(index + 2)) &&
      _isHexDigit(source.codeUnitAt(index + 3))) {
    return (
      value: String.fromCharCode(
        int.parse(source.substring(index + 2, index + 4), radix: 16),
      ),
      nextIndex: index + 4,
    );
  }

  if (escaped == _lowercaseU) {
    final unicodeEscape = _readUnicodeEscape(source, index);
    if (unicodeEscape != null) return unicodeEscape;
  }

  // Quotes, backslashes, dollar signs, and other valid single-character
  // escapes represent the escaped character itself.
  return (value: String.fromCharCode(escaped), nextIndex: index + 2);
}

({String value, int nextIndex})? _readUnicodeEscape(String source, int index) {
  final digitsStart = index + 2;
  if (digitsStart >= source.length) return null;

  if (source.codeUnitAt(digitsStart) == _leftBrace) {
    final valueStart = digitsStart + 1;
    var cursor = valueStart;
    while (cursor < source.length &&
        _isHexDigit(source.codeUnitAt(cursor)) &&
        cursor - valueStart < 6) {
      cursor++;
    }
    if (cursor == valueStart ||
        cursor >= source.length ||
        source.codeUnitAt(cursor) != _rightBrace) {
      return null;
    }
    final codePoint = int.parse(
      source.substring(valueStart, cursor),
      radix: 16,
    );
    if (codePoint > 0x10ffff) return null;
    return (value: String.fromCharCode(codePoint), nextIndex: cursor + 1);
  }

  if (digitsStart + 4 > source.length) return null;
  final digits = source.substring(digitsStart, digitsStart + 4);
  if (!digits.codeUnits.every(_isHexDigit)) return null;
  return (
    value: String.fromCharCode(int.parse(digits, radix: 16)),
    nextIndex: digitsStart + 4,
  );
}

bool _identifierAt(String source, int index, String identifier) {
  final end = index + identifier.length;
  if (end > source.length || source.substring(index, end) != identifier) {
    return false;
  }
  return end == source.length || !_isIdentifierPart(source.codeUnitAt(end));
}

int _skipTrivia(String source, int index) {
  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (_isWhitespace(character)) {
      index++;
      continue;
    }
    if (character != _slash || index + 1 >= source.length) return index;

    final next = source.codeUnitAt(index + 1);
    if (next == _slash) {
      index += 2;
      while (index < source.length && source.codeUnitAt(index) != _lineFeed) {
        index++;
      }
      continue;
    }
    if (next != _asterisk) return index;

    var depth = 1;
    index += 2;
    while (index < source.length && depth > 0) {
      if (index + 1 < source.length &&
          source.codeUnitAt(index) == _slash &&
          source.codeUnitAt(index + 1) == _asterisk) {
        depth++;
        index += 2;
      } else if (index + 1 < source.length &&
          source.codeUnitAt(index) == _asterisk &&
          source.codeUnitAt(index + 1) == _slash) {
        depth--;
        index += 2;
      } else {
        index++;
      }
    }
  }
  return index;
}

bool _isWhitespace(int character) =>
    character == 0x20 ||
    character == 0x09 ||
    character == 0x0a ||
    character == 0x0d ||
    character == 0x0c;

bool _isQuote(int character) =>
    character == _singleQuote || character == _doubleQuote;

bool _isIdentifierStart(int character) =>
    (character >= 0x41 && character <= 0x5a) ||
    (character >= 0x61 && character <= 0x7a) ||
    character == 0x5f ||
    character == 0x24;

bool _isIdentifierPart(int character) =>
    _isIdentifierStart(character) || (character >= 0x30 && character <= 0x39);

bool _isHexDigit(int character) =>
    (character >= 0x30 && character <= 0x39) ||
    (character >= 0x41 && character <= 0x46) ||
    (character >= 0x61 && character <= 0x66);

String _ruleDescription(ArchitectureRule rule) => switch (rule) {
  ArchitectureRule.coreMustNotImportFeatures =>
    'core must not depend on features',
  ArchitectureRule.sharedDomainMustRemainFrameworkIndependent =>
    'shared music/audio and practice domains must remain '
        'framework-independent',
  ArchitectureRule.crossFeatureImportsMustUsePublicApi =>
    'cross-feature imports must target public.dart',
  ArchitectureRule.designSystemImportsMustUsePublicBarrel =>
    'design-system imports must target '
        'lib/core/design_system/public.dart',
  ArchitectureRule.rawVisionPayloadMustNotPersist =>
    'raw vision payloads must not enter persistence',
  ArchitectureRule.rawVisionPayloadMustNotEnterProviderState =>
    'raw vision payloads must not enter provider state',
};

const _lineFeed = 0x0a;
const _singleQuote = 0x27;
const _doubleQuote = 0x22;
const _backslash = 0x5c;
const _slash = 0x2f;
const _asterisk = 0x2a;
const _semicolon = 0x3b;
const _leftBrace = 0x7b;
const _rightBrace = 0x7d;
const _lowercaseR = 0x72;
const _uppercaseR = 0x52;
const _lowercaseU = 0x75;
const _lowercaseX = 0x78;

/// Checks that every generated `lib/features/<feature>/public.dart` barrel
/// matches the concatenation of its `public/*.dart` fragments. A stale
/// barrel is a code_failure: a cross-feature consumer can silently lose an
/// export or, worse, shadow another symbol. The brief §4 falsification cell
/// is the back-pressure that keeps this check from being silently removed.
String? _checkGeneratedBarrels(Directory projectRoot) {
  final features = barrel.featuresWithPublicFragments(projectRoot);
  if (features.isEmpty) return null;
  final stale = <String>[];
  for (final feature in features) {
    final entry = barrel.PublicBarrel(
      projectRoot: projectRoot,
      feature: feature,
    );
    if (!entry.isFresh()) {
      stale.add(feature);
    }
  }
  if (stale.isEmpty) return null;
  final buffer = StringBuffer('Generated public barrel(s) out of date:\n');
  for (final feature in stale) {
    buffer.writeln(
      '  - $feature (run: dart run tool/gen_public_barrel.dart --write)',
    );
  }
  return buffer.toString().trimRight();
}

void main(List<String> arguments) {
  try {
    final report = checkArchitecture(projectRoot: Directory.current);
    final barrelError = _checkGeneratedBarrels(Directory.current);
    if (arguments.length == 1 && arguments.single == '--print-allowlist') {
      final hardViolations = report.violations
          .where(
            (item) =>
                item.rule !=
                ArchitectureRule.crossFeatureImportsMustUsePublicApi,
          )
          .toList();
      if (hardViolations.isNotEmpty) {
        stderr.writeln(
          'Cannot generate an allowlist while hard architecture boundaries '
          'are violated:',
        );
        for (final violation in hardViolations) {
          stderr.writeln(
            '- ${violation.key} '
            '[${_ruleDescription(violation.rule)}]',
          );
        }
        exitCode = 1;
        return;
      }
      final entries =
          report.violations
              .where(
                (item) =>
                    item.rule ==
                    ArchitectureRule.crossFeatureImportsMustUsePublicApi,
              )
              .map((item) => item.key)
              .toSet()
              .toList()
            ..sort();
      stdout.writeln('// ${entries.length} current architecture deviation(s)');
      for (final entry in entries) {
        stdout.writeln("  '${entry.replaceAll("'", r"\'")}',");
      }
      return;
    }
    if (arguments.isNotEmpty) {
      stderr.writeln(
        'Usage: dart run tool/check_architecture.dart [--print-allowlist]',
      );
      exitCode = 64;
      return;
    }
    if (report.isClean && barrelError == null) {
      stdout.writeln(report.format());
      return;
    }
    if (!report.isClean) stderr.writeln(report.format());
    if (barrelError != null) stderr.writeln(barrelError);
    exitCode = 1;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Architecture check could not run: $error');
    stderr.writeln(stackTrace);
    exitCode = 2;
  }
}
