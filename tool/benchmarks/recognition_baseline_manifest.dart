// Recognition baseline manifest generator/checker (E14-R02, ADR 0354).
//
// Pure Dart: no `dart:ui`, nothing from `lib/**`, no package dependency
// beyond `dart:convert`/`dart:io` — a schema-library dependency would need a
// `pubspec.yaml` change, which is this round's forbidden zone (ADR 0354 D8).
// Also does not import the sibling `real_audio_dsp_baseline.dart`, which
// transitively pulls `dart:ui` and cannot run under plain `dart run`
// (docs/eval/real-audio-dsp-baseline.md records that measurement directly).
//
// Validates `evaluation/recognition/baseline_manifest.json` against
// `evaluation/recognition/baseline_manifest_schema.json` with a hand-written
// subset of JSON Schema draft-07 (`type`, `required`,
// `additionalProperties`, `const`, `enum`, `oneOf`, `not`, `$ref`,
// `pattern`, `minimum`, `minLength`, `minItems`, `maxItems`,
// `minProperties`) — the same "checker enforces the contract by hand" shape
// `tool/check_fixture_manifest.dart` and `evaluation_manifest_parser.dart`
// already use — then deterministically renders
// `docs/eval/recognition-baseline-index.md` from the validated manifest.
// `--check` only validates and diffs the render against the file already on
// disk; the default mode (re)writes it.
import 'dart:convert';
import 'dart:io';

/// Manifest schema contract version this checker understands.
const recognitionBaselineManifestSchemaVersion = '1.0';

/// One problem found while validating the manifest against the schema.
final class ManifestIssue {
  const ManifestIssue({required this.path, required this.message});

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Result of validating — and, if clean, rendering — a recognition baseline
/// manifest.
final class RecognitionBaselineManifestReport {
  RecognitionBaselineManifestReport({
    required List<ManifestIssue> issues,
    required this.renderedIndex,
  }) : issues = List.unmodifiable(issues);

  final List<ManifestIssue> issues;

  /// The deterministically-rendered Markdown index, or `null` when
  /// validation failed — a broken manifest never renders a report
  /// (ADR 0354 D6).
  final String? renderedIndex;

  bool get isClean => issues.isEmpty;

  String formatIssues() {
    if (isClean) return 'Recognition baseline manifest OK.';
    final buffer = StringBuffer('Recognition baseline manifest check failed.');
    for (final issue in issues) {
      buffer
        ..writeln()
        ..write('- $issue');
    }
    return buffer.toString();
  }
}

/// Validates [manifestJsonText] against [schemaJsonText] and, if valid,
/// deterministically renders the human-readable index. Never touches a
/// clock or a random source (ADR 0354 D5): every value in the render comes
/// from the manifest text, including the `generatedAt` timestamp.
RecognitionBaselineManifestReport buildRecognitionBaselineManifestReport({
  required String schemaJsonText,
  required String manifestJsonText,
}) {
  final issues = <ManifestIssue>[];

  Object? schema;
  try {
    schema = jsonDecode(schemaJsonText);
  } on FormatException catch (error) {
    issues.add(
      ManifestIssue(path: '<schema>', message: 'invalid JSON: $error'),
    );
  }

  Object? manifest;
  try {
    manifest = jsonDecode(manifestJsonText);
  } on FormatException catch (error) {
    issues.add(
      ManifestIssue(path: '<manifest>', message: 'invalid JSON: $error'),
    );
  }

  if (schema is! Map<String, Object?> || manifest is! Map<String, Object?>) {
    if (schema is! Map<String, Object?>) {
      issues.add(
        const ManifestIssue(
          path: '<schema>',
          message: 'schema root must be a JSON object',
        ),
      );
    }
    if (manifest is! Map<String, Object?>) {
      issues.add(
        const ManifestIssue(
          path: '<manifest>',
          message: 'manifest root must be a JSON object',
        ),
      );
    }
    return RecognitionBaselineManifestReport(
      issues: issues,
      renderedIndex: null,
    );
  }

  issues.addAll(_validate(manifest, schema, schema, r'$'));

  if (issues.isNotEmpty) {
    return RecognitionBaselineManifestReport(
      issues: issues,
      renderedIndex: null,
    );
  }

  return RecognitionBaselineManifestReport(
    issues: issues,
    renderedIndex: _renderIndex(manifest),
  );
}

// --- Hand-written JSON Schema (draft-07 subset) validator ------------------

/// Schema keywords this checker actually enforces. Closed set (ADR 0354 D8):
/// a keyword outside this set AND [_documentationSchemaKeywords] is treated
/// as an unknown/unsupported constraint, never as a silent no-op.
const _restrictiveSchemaKeywords = <String>{
  'type',
  'required',
  'additionalProperties',
  'properties',
  'items',
  'const',
  'enum',
  'oneOf',
  'not',
  r'$ref',
  'pattern',
  'minimum',
  'minLength',
  'minItems',
  'maxItems',
  'minProperties',
};

/// Schema keywords this checker deliberately ignores because they carry no
/// validation semantics (documentation/metadata only). Anything not in this
/// set and not in [_restrictiveSchemaKeywords] is an unknown keyword.
const _documentationSchemaKeywords = <String>{
  r'$schema',
  r'$id',
  'title',
  'description',
  'definitions',
  'examples',
  'default',
};

List<ManifestIssue> _validate(
  Object? instance,
  Map<String, Object?> schema,
  Map<String, Object?> rootSchema,
  String path,
) {
  final resolved = _resolveRef(schema, rootSchema);
  final issues = <ManifestIssue>[];

  for (final key in resolved.keys) {
    if (!_restrictiveSchemaKeywords.contains(key) &&
        !_documentationSchemaKeywords.contains(key)) {
      issues.add(
        ManifestIssue(
          path: path,
          message:
              'schema declares unknown/unsupported keyword "$key" — '
              'fail-closed rather than silently ignored (ADR 0354 D8)',
        ),
      );
    }
  }

  if (resolved.containsKey('const')) {
    final constValue = resolved['const'];
    if (!_deepEquals(instance, constValue)) {
      issues.add(
        ManifestIssue(
          path: path,
          message:
              'must equal ${jsonEncode(constValue)}, got '
              '${jsonEncode(instance)}',
        ),
      );
      return issues;
    }
  }

  final enumValues = resolved['enum'];
  if (enumValues is List) {
    final matchesEnum = enumValues.any((value) => _deepEquals(instance, value));
    if (!matchesEnum) {
      issues.add(
        ManifestIssue(
          path: path,
          message: 'must be one of $enumValues, got ${jsonEncode(instance)}',
        ),
      );
      return issues;
    }
  }

  final type = resolved['type'];
  if (type != null && !_matchesType(instance, type)) {
    issues.add(
      ManifestIssue(
        path: path,
        message: 'must be of type $type, got ${_typeNameOf(instance)}',
      ),
    );
    return issues;
  }

  final pattern = resolved['pattern'];
  if (pattern is String && instance is String) {
    if (!RegExp(pattern).hasMatch(instance)) {
      issues.add(
        ManifestIssue(path: path, message: 'must match pattern $pattern'),
      );
    }
  }

  final minLength = resolved['minLength'];
  if (minLength is int && instance is String && instance.length < minLength) {
    issues.add(
      ManifestIssue(
        path: path,
        message: 'must be at least $minLength character(s)',
      ),
    );
  }

  final minimum = resolved['minimum'];
  if (minimum is num && instance is num && instance < minimum) {
    issues.add(ManifestIssue(path: path, message: 'must be >= $minimum'));
  }

  if (instance is List) {
    final minItems = resolved['minItems'];
    if (minItems is int && instance.length < minItems) {
      issues.add(
        ManifestIssue(
          path: path,
          message: 'must have at least $minItems item(s)',
        ),
      );
    }
    final maxItems = resolved['maxItems'];
    if (maxItems is int && instance.length > maxItems) {
      issues.add(
        ManifestIssue(
          path: path,
          message: 'must have at most $maxItems item(s)',
        ),
      );
    }
    final itemSchema = resolved['items'];
    if (itemSchema is Map<String, Object?>) {
      for (var index = 0; index < instance.length; index++) {
        issues.addAll(
          _validate(instance[index], itemSchema, rootSchema, '$path[$index]'),
        );
      }
    }
  }

  if (instance is Map<String, Object?>) {
    final minProperties = resolved['minProperties'];
    if (minProperties is int && instance.length < minProperties) {
      issues.add(
        ManifestIssue(
          path: path,
          message: 'must have at least $minProperties propert(y/ies)',
        ),
      );
    }

    final required = resolved['required'];
    if (required is List) {
      for (final key in required) {
        if (key is String && !instance.containsKey(key)) {
          issues.add(
            ManifestIssue(
              path: path,
              message: 'missing required property "$key"',
            ),
          );
        }
      }
    }

    final properties = resolved['properties'];
    final propertySchemas = properties is Map<String, Object?>
        ? properties
        : const <String, Object?>{};
    final additional = resolved['additionalProperties'];

    for (final entry in instance.entries) {
      final key = entry.key;
      final propertySchema = propertySchemas[key];
      if (propertySchema is Map<String, Object?>) {
        issues.addAll(
          _validate(entry.value, propertySchema, rootSchema, '$path.$key'),
        );
      } else if (additional == false) {
        issues.add(
          ManifestIssue(
            path: '$path.$key',
            message:
                'unexpected property (not declared, '
                'additionalProperties: false)',
          ),
        );
      } else if (additional is Map<String, Object?>) {
        issues.addAll(
          _validate(entry.value, additional, rootSchema, '$path.$key'),
        );
      }
      // additional == true, or the keyword is absent: no constraint.
    }
  }

  final oneOf = resolved['oneOf'];
  if (oneOf is List) {
    final branchResults = <List<ManifestIssue>>[
      for (final branch in oneOf)
        if (branch is Map<String, Object?>)
          _validate(instance, branch, rootSchema, path),
    ];
    final matching = branchResults.where((result) => result.isEmpty).length;
    if (matching != 1) {
      issues.add(
        ManifestIssue(
          path: path,
          message:
              'must match exactly one alternative (matched $matching of '
              '${branchResults.length})',
        ),
      );
    }
  }

  final not = resolved['not'];
  if (not is Map<String, Object?>) {
    final forbidden = _validate(instance, not, rootSchema, path);
    if (forbidden.isEmpty) {
      issues.add(
        ManifestIssue(
          path: path,
          message: 'must not match the forbidden shape',
        ),
      );
    }
  }

  return issues;
}

Map<String, Object?> _resolveRef(
  Map<String, Object?> schema,
  Map<String, Object?> rootSchema,
) {
  final ref = schema[r'$ref'];
  if (ref is! String) return schema;
  if (!ref.startsWith('#/')) {
    throw StateError(
      'unsupported \$ref (only local #/... pointers are supported): $ref',
    );
  }
  Object? cursor = rootSchema;
  for (final segment in ref.substring(2).split('/')) {
    if (cursor is Map<String, Object?>) {
      cursor = cursor[segment];
    } else {
      cursor = null;
    }
  }
  if (cursor is! Map<String, Object?>) {
    throw StateError('\$ref could not be resolved: $ref');
  }
  return cursor;
}

bool _matchesType(Object? instance, Object? type) {
  if (type is List) {
    return type.any((oneType) => _matchesType(instance, oneType));
  }
  return switch (type) {
    'object' => instance is Map<String, Object?>,
    'array' => instance is List,
    'string' => instance is String,
    'integer' => instance is int,
    'number' => instance is num,
    'boolean' => instance is bool,
    'null' => instance == null,
    _ => false,
  };
}

String _typeNameOf(Object? instance) {
  if (instance == null) return 'null';
  if (instance is Map) return 'object';
  if (instance is List) return 'array';
  if (instance is String) return 'string';
  if (instance is bool) return 'boolean';
  if (instance is int) return 'integer';
  if (instance is num) return 'number';
  return instance.runtimeType.toString();
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!_deepEquals(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}

// --- Deterministic Markdown renderer ----------------------------------------

String _renderIndex(Map<String, Object?> manifest) {
  final corpus = manifest['corpus']! as Map<String, Object?>;
  final configuration = manifest['configuration']! as Map<String, Object?>;
  final models = (manifest['models']! as List).cast<Map<String, Object?>>();
  final metricBlocks = manifest['metricBlocks']! as Map<String, Object?>;
  final bpm = manifest['bpm']! as Map<String, Object?>;

  final buffer = StringBuffer()
    ..writeln('# Recognition baseline — evidence index')
    ..writeln()
    ..writeln(
      '<!-- GENERATED by tool/benchmarks/recognition_baseline_manifest.dart '
      'from evaluation/recognition/baseline_manifest.json. Do not hand-edit; '
      're-run `dart run tool/benchmarks/recognition_baseline_manifest.dart`. -->',
    )
    ..writeln()
    ..writeln('Generated at: ${manifest['generatedAt']}')
    ..writeln()
    ..writeln(
      'This index renders the machine-readable recognition baseline '
      'manifest ([ADR 0354](../adr/0354-recognition-baseline-manifest-and-evidence-index.md)). '
      'It links to, and does not duplicate, the measurement narrative in '
      '[`real-audio-dsp-baseline.md`](real-audio-dsp-baseline.md) and the '
      'activation contract in '
      '[`recognition-release-guard.md`](recognition-release-guard.md). Every '
      'number below carries its own source file and measurement command — '
      'see `evaluation/recognition/baseline_manifest.json` for the full '
      'record.',
    )
    ..writeln()
    ..writeln('## Corpus')
    ..writeln()
    ..writeln('| Field | Value |')
    ..writeln('|---|---|')
    ..writeln('| Corpus ID | `${corpus['corpusId']}` |')
    ..writeln('| Corpus SHA-256 | `${corpus['corpusSha256']}` |')
    ..writeln('| Recording count | ${corpus['recordingCount']} |')
    ..writeln('| Event count | ${corpus['eventCount']} |')
    ..writeln('| Skipped recordings | ${corpus['skippedRecordingCount']} |')
    ..writeln()
    ..writeln(
      'The corpus itself is never committed to this repository — only its '
      'identity hash and counts (ADR 0354 D1).',
    )
    ..writeln()
    ..writeln('## App commit and configuration')
    ..writeln()
    ..writeln('- App commit: `${manifest['appCommit']}`')
    ..writeln('- ${manifest['appCommitNote']}')
    ..writeln()
    ..writeln('| Configuration field | Value |')
    ..writeln('|---|---|')
    ..writeln('| chunkSize | ${configuration['chunkSize']} |')
    ..writeln('| strumRefiner | ${configuration['strumRefiner'] ?? 'null'} |')
    ..writeln('| chromaMedianWindow | ${configuration['chromaMedianWindow']} |')
    ..writeln('| bassWeight | ${configuration['bassWeight'] ?? 'null'} |')
    ..writeln()
    ..writeln('## Models')
    ..writeln();

  if (models.isEmpty) {
    buffer
      ..writeln('None. ${manifest['modelsRationale']}')
      ..writeln();
  } else {
    buffer
      ..writeln('| Name | SHA-256 |')
      ..writeln('|---|---|');
    for (final model in models) {
      buffer.writeln('| ${model['name']} | `${model['sha256']}` |');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Metric blocks')
    ..writeln();
  final blockKeys = metricBlocks.keys.toList()..sort();
  for (final blockKey in blockKeys) {
    final block = metricBlocks[blockKey]! as Map<String, Object?>;
    final status = block['status'] as String;
    buffer
      ..writeln('### $blockKey — $status')
      ..writeln();
    if (status == 'not-measured') {
      buffer
        ..writeln('Reason: ${block['notMeasuredReason']}')
        ..writeln();
      continue;
    }
    _writeMetricsTable(buffer, block['metrics']! as Map<String, Object?>);
  }

  buffer
    ..writeln('## BPM — RETRACTED')
    ..writeln()
    ..writeln('**This claim is retracted.** ${bpm['retractedReason']}')
    ..writeln();
  _writeMetricsTable(buffer, bpm['metrics']! as Map<String, Object?>);

  return buffer.toString();
}

void _writeMetricsTable(StringBuffer buffer, Map<String, Object?> metrics) {
  buffer
    ..writeln('| Metric | Value | n | Source | Command |')
    ..writeln('|---|---:|---:|---|---|');
  final metricKeys = metrics.keys.toList()..sort();
  for (final metricKey in metricKeys) {
    final metric = metrics[metricKey]! as Map<String, Object?>;
    final value = (metric['value']! as num).toDouble();
    final unit = metric['unit'] as String?;
    final formattedValue = _formatMetricValue(value, unit);
    final n = metric['n'];
    final nDisplay = n == 1 ? '1 (n=1 — single sample, not evidence)' : '$n';
    final sourceFile = metric['sourceFile'];
    final command = metric['command'];
    buffer.writeln(
      '| $metricKey | $formattedValue | $nDisplay | `$sourceFile` | '
      '`$command` |',
    );
  }
  buffer.writeln();
}

String _formatMetricValue(double value, String? unit) {
  return switch (unit) {
    'ratio' => '${(value * 100).toStringAsFixed(3)}%',
    'bpm' => '${value.toStringAsFixed(3)} BPM',
    'ms' => '${value.toStringAsFixed(3)} ms',
    _ => value.toStringAsFixed(3),
  };
}

// --- CLI ---------------------------------------------------------------

void main(List<String> arguments) {
  var checkOnly = false;
  var schemaPath = 'evaluation/recognition/baseline_manifest_schema.json';
  var manifestPath = 'evaluation/recognition/baseline_manifest.json';
  var indexPath = 'docs/eval/recognition-baseline-index.md';

  var index = 0;
  while (index < arguments.length) {
    final argument = arguments[index];
    if (argument == '--check') {
      checkOnly = true;
      index++;
    } else if (argument == '--schema' && index + 1 < arguments.length) {
      schemaPath = arguments[index + 1];
      index += 2;
    } else if (argument == '--manifest' && index + 1 < arguments.length) {
      manifestPath = arguments[index + 1];
      index += 2;
    } else if (argument == '--index' && index + 1 < arguments.length) {
      indexPath = arguments[index + 1];
      index += 2;
    } else {
      stderr.writeln(
        'Usage: dart run tool/benchmarks/recognition_baseline_manifest.dart '
        '[--check] [--schema PATH] [--manifest PATH] [--index PATH]',
      );
      exitCode = 64;
      return;
    }
  }

  final schemaFile = File(schemaPath);
  final manifestFile = File(manifestPath);

  if (!schemaFile.existsSync()) {
    stderr.writeln(
      'recognition_baseline_manifest: schema file not found: $schemaPath',
    );
    exitCode = 2;
    return;
  }
  if (!manifestFile.existsSync()) {
    stderr.writeln(
      'recognition_baseline_manifest: manifest file not found: $manifestPath',
    );
    exitCode = 2;
    return;
  }

  final report = buildRecognitionBaselineManifestReport(
    schemaJsonText: schemaFile.readAsStringSync(),
    manifestJsonText: manifestFile.readAsStringSync(),
  );

  if (!report.isClean) {
    stderr.writeln(report.formatIssues());
    exitCode = 1;
    return;
  }

  final renderedIndex = report.renderedIndex!;
  final indexFile = File(indexPath);

  if (checkOnly) {
    if (!indexFile.existsSync()) {
      stderr.writeln(
        'recognition_baseline_manifest: index file not found: $indexPath '
        '(run without --check to render it)',
      );
      exitCode = 1;
      return;
    }
    final onDisk = indexFile.readAsStringSync();
    if (onDisk != renderedIndex) {
      stderr.writeln(
        'recognition_baseline_manifest: $indexPath is stale — re-run '
        'without --check to regenerate it.',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Recognition baseline manifest OK; $indexPath is up to date.',
    );
    return;
  }

  indexFile.writeAsStringSync(renderedIndex);
  stdout.writeln('Recognition baseline manifest OK; wrote $indexPath.');
}
