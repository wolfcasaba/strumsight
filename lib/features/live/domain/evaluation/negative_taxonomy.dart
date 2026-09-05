/// Hard-negative sound-category taxonomy (E14-R15, ADR 0521 D7).
///
/// A hard negative is a non-guitar sound source that a confidence-only
/// classifier can mistake for a real onset/strum/chord — the measured root
/// cause `ml/negatives.py` records: the model is often just as confident on
/// the false onset as on a true one, so a fixed category list plus a typed
/// validator is the product-side complement to that training-side finding.
/// [NegativeTaxonomy] is the fixed list a capture segment must be labelled
/// against; [NegativeTaxonomySample] models an already-captured segment set
/// referencing that list by category id. Neither type carries or reads raw
/// audio — a segment names a category and a `sourceRef` pointing at material
/// that lives outside the repository (ADR 0249, ADR 0521 D8). This file is
/// `dart:io`-free: reading either JSON file off disk is the caller's job.
library;

import 'dart:convert';

/// Typed failure kinds for taxonomy/sample parsing and category lookup.
enum NegativeTaxonomyErrorKind {
  malformedValue,
  missingField,
  unknownField,
  unknownSchemaVersion,
  tooFewCategories,
  duplicateCategoryId,
  unknownCategory,
}

/// A typed taxonomy/sample failure. Never a bare [FormatException],
/// [TypeError] or [StateError] — every rejection names its [kind] and,
/// where applicable, the offending JSON [path] (ADR 0521 D7). In particular,
/// an unknown category id is [NegativeTaxonomyErrorKind.unknownCategory],
/// never silently folded into an `other` bucket.
final class NegativeTaxonomyException implements Exception {
  const NegativeTaxonomyException(this.kind, this.message, {this.path});

  final NegativeTaxonomyErrorKind kind;
  final String message;
  final String? path;

  @override
  String toString() =>
      'NegativeTaxonomyException(${kind.name})'
      '${path == null ? '' : ' at $path'}: $message';
}

/// The only taxonomy-file schema version this file accepts.
const String supportedNegativeTaxonomySchemaVersion = '1';

/// The only sample-file schema version this file accepts.
const String supportedNegativeTaxonomySampleSchemaVersion = '1';

/// ADR 0521 D7: a taxonomy must name at least this many hard-negative
/// categories. The boundary is inclusive — exactly this many is accepted.
const int minimumNegativeTaxonomyCategoryCount = 10;

/// One hard-negative category: a non-guitar sound source that can be
/// mistaken for a real recognition event.
final class NegativeTaxonomyCategory {
  NegativeTaxonomyCategory({
    required this.id,
    required this.label,
    required this.description,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError.value(
        description,
        'description',
        'must not be empty',
      );
    }
  }

  final String id;
  final String label;
  final String description;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'description': description,
  };
}

/// A parsed, validated hard-negative taxonomy (ADR 0521 D7). [categories]
/// always number at least [minimumNegativeTaxonomyCategoryCount] and never
/// repeat an [NegativeTaxonomyCategory.id] — both are enforced at
/// construction, never left to a caller to check.
final class NegativeTaxonomy {
  NegativeTaxonomy({
    required this.schemaVersion,
    required List<NegativeTaxonomyCategory> categories,
  }) : categories = List<NegativeTaxonomyCategory>.unmodifiable(categories) {
    if (this.categories.length < minimumNegativeTaxonomyCategoryCount) {
      throw NegativeTaxonomyException(
        NegativeTaxonomyErrorKind.tooFewCategories,
        'taxonomy names ${this.categories.length} categories, fewer than '
        'the required minimum of $minimumNegativeTaxonomyCategoryCount',
      );
    }
    final seenIds = <String>{};
    for (final category in this.categories) {
      if (!seenIds.add(category.id)) {
        throw NegativeTaxonomyException(
          NegativeTaxonomyErrorKind.duplicateCategoryId,
          'category id "${category.id}" is declared more than once',
        );
      }
    }
  }

  final String schemaVersion;
  final List<NegativeTaxonomyCategory> categories;

  /// Looks up [categoryId], throwing a typed [NegativeTaxonomyException]
  /// (`kind: unknownCategory`) rather than returning `null` or folding into
  /// a catch-all "other" bucket — an unlisted category is a data-entry
  /// error to surface, not a valid taxonomy member to paper over (ADR 0521
  /// D7).
  NegativeTaxonomyCategory categoryById(String categoryId) {
    for (final category in categories) {
      if (category.id == categoryId) return category;
    }
    throw NegativeTaxonomyException(
      NegativeTaxonomyErrorKind.unknownCategory,
      'no taxonomy category named "$categoryId"',
      path: 'categoryId',
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'categories': <Map<String, Object?>>[
      for (final category in categories) category.toJson(),
    ],
  };
}

/// One captured hard-negative segment, labelled with exactly one
/// [NegativeTaxonomy] category id. [sourceRef] points at the external
/// capture the segment came from — the actual audio never enters the
/// repository (ADR 0249, ADR 0521 D8).
final class NegativeTaxonomySegment {
  NegativeTaxonomySegment({
    required this.id,
    required this.categoryId,
    required this.startMs,
    required this.endMs,
    this.sourceRef,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (categoryId.trim().isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'must not be empty');
    }
    if (startMs < 0) {
      throw ArgumentError.value(startMs, 'startMs', 'must not be negative');
    }
    if (endMs < startMs) {
      throw ArgumentError.value(
        endMs,
        'endMs',
        'must be >= startMs ($startMs)',
      );
    }
  }

  final String id;
  final String categoryId;
  final int startMs;
  final int endMs;
  final String? sourceRef;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'categoryId': categoryId,
    'startMs': startMs,
    'endMs': endMs,
    'sourceRef': sourceRef,
  };
}

/// A parsed hard-negative capture-segment sample, every segment already
/// validated against the [NegativeTaxonomy] it was parsed with (see
/// [NegativeTaxonomyParser.parseSample]) — a sample never carries a segment
/// naming a category the taxonomy does not have.
final class NegativeTaxonomySample {
  NegativeTaxonomySample({
    required this.schemaVersion,
    required List<NegativeTaxonomySegment> segments,
  }) : segments = List<NegativeTaxonomySegment>.unmodifiable(segments);

  final String schemaVersion;
  final List<NegativeTaxonomySegment> segments;
}

const _taxonomyRootKeys = <String>{'schemaVersion', 'categories'};
const _categoryKeys = <String>{'id', 'label', 'description'};
const _sampleRootKeys = <String>{'schemaVersion', 'segments'};
const _segmentKeys = <String>{
  'id',
  'categoryId',
  'startMs',
  'endMs',
  'sourceRef',
};

/// Parses [NegativeTaxonomy] and [NegativeTaxonomySample] from JSON (ADR
/// 0521 D7). Every rejection surfaces as a typed [NegativeTaxonomyException]
/// naming its [NegativeTaxonomyErrorKind] and, where applicable, the
/// offending JSON path — never a bare [FormatException] or [TypeError].
final class NegativeTaxonomyParser {
  const NegativeTaxonomyParser();

  NegativeTaxonomy parseJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw NegativeTaxonomyException(
        NegativeTaxonomyErrorKind.malformedValue,
        'taxonomy is not valid JSON: ${error.message}',
      );
    }
    return parse(_asMap(decoded, 'taxonomy'));
  }

  NegativeTaxonomy parse(Map<String, Object?> json) {
    _checkKeys(json, _taxonomyRootKeys, 'taxonomy');
    final schemaVersion = _requireString(json, 'schemaVersion', 'taxonomy');
    if (schemaVersion != supportedNegativeTaxonomySchemaVersion) {
      throw NegativeTaxonomyException(
        NegativeTaxonomyErrorKind.unknownSchemaVersion,
        'unsupported schemaVersion "$schemaVersion" '
        '(expected "$supportedNegativeTaxonomySchemaVersion")',
        path: 'taxonomy.schemaVersion',
      );
    }
    final rawCategories = _asList(
      _requireField(json, 'categories', 'taxonomy'),
      'taxonomy.categories',
    );
    final categories = <NegativeTaxonomyCategory>[
      for (var i = 0; i < rawCategories.length; i++)
        _parseCategory(
          _asMap(rawCategories[i], 'taxonomy.categories[$i]'),
          'taxonomy.categories[$i]',
        ),
    ];
    return NegativeTaxonomy(
      schemaVersion: schemaVersion,
      categories: categories,
    );
  }

  NegativeTaxonomyCategory _parseCategory(
    Map<String, Object?> json,
    String path,
  ) {
    _checkKeys(json, _categoryKeys, path);
    return NegativeTaxonomyCategory(
      id: _requireString(json, 'id', path),
      label: _requireString(json, 'label', path),
      description: _requireString(json, 'description', path),
    );
  }

  /// Parses a capture-segment sample and validates every segment's
  /// `categoryId` against [taxonomy], throwing a typed
  /// [NegativeTaxonomyException] (`kind: unknownCategory`) on the first
  /// segment naming a category [taxonomy] does not have.
  NegativeTaxonomySample parseSampleJsonString(
    String source,
    NegativeTaxonomy taxonomy,
  ) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw NegativeTaxonomyException(
        NegativeTaxonomyErrorKind.malformedValue,
        'sample is not valid JSON: ${error.message}',
      );
    }
    return parseSample(_asMap(decoded, 'sample'), taxonomy);
  }

  NegativeTaxonomySample parseSample(
    Map<String, Object?> json,
    NegativeTaxonomy taxonomy,
  ) {
    _checkKeys(json, _sampleRootKeys, 'sample');
    final schemaVersion = _requireString(json, 'schemaVersion', 'sample');
    if (schemaVersion != supportedNegativeTaxonomySampleSchemaVersion) {
      throw NegativeTaxonomyException(
        NegativeTaxonomyErrorKind.unknownSchemaVersion,
        'unsupported schemaVersion "$schemaVersion" '
        '(expected "$supportedNegativeTaxonomySampleSchemaVersion")',
        path: 'sample.schemaVersion',
      );
    }
    final rawSegments = _asList(
      _requireField(json, 'segments', 'sample'),
      'sample.segments',
    );
    final segments = <NegativeTaxonomySegment>[
      for (var i = 0; i < rawSegments.length; i++)
        _parseSegment(
          _asMap(rawSegments[i], 'sample.segments[$i]'),
          'sample.segments[$i]',
          taxonomy,
        ),
    ];
    return NegativeTaxonomySample(
      schemaVersion: schemaVersion,
      segments: segments,
    );
  }

  NegativeTaxonomySegment _parseSegment(
    Map<String, Object?> json,
    String path,
    NegativeTaxonomy taxonomy,
  ) {
    _checkKeys(json, _segmentKeys, path);
    final categoryId = _requireString(json, 'categoryId', path);
    // Throws NegativeTaxonomyException(unknownCategory) for an id the
    // taxonomy does not list — the same typed failure a direct
    // NegativeTaxonomy.categoryById lookup would give.
    taxonomy.categoryById(categoryId);
    return NegativeTaxonomySegment(
      id: _requireString(json, 'id', path),
      categoryId: categoryId,
      startMs: _requireInt(json, 'startMs', path),
      endMs: _requireInt(json, 'endMs', path),
      sourceRef: _optionalString(json, 'sourceRef'),
    );
  }

  // --- typed field access helpers -----------------------------------

  void _checkKeys(Map<String, Object?> json, Set<String> allowed, String path) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        throw NegativeTaxonomyException(
          NegativeTaxonomyErrorKind.unknownField,
          'unrecognised field "$key"',
          path: '$path.$key',
        );
      }
    }
  }

  Object? _requireField(Map<String, Object?> json, String key, String path) {
    if (!json.containsKey(key)) {
      throw NegativeTaxonomyException(
        NegativeTaxonomyErrorKind.missingField,
        '"$key" is required',
        path: '$path.$key',
      );
    }
    return json[key];
  }

  String _requireString(Map<String, Object?> json, String key, String path) =>
      _asString(_requireField(json, key, path), '$path.$key');

  int _requireInt(Map<String, Object?> json, String key, String path) =>
      _asInt(_requireField(json, key, path), '$path.$key');

  String? _optionalString(Map<String, Object?> json, String key) {
    final raw = json[key];
    if (raw == null) return null;
    return _asString(raw, key);
  }

  Map<String, Object?> _asMap(Object? value, String path) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key as String, v));
    }
    throw NegativeTaxonomyException(
      NegativeTaxonomyErrorKind.malformedValue,
      'expected an object',
      path: path,
    );
  }

  List<Object?> _asList(Object? value, String path) {
    if (value is List) return value;
    throw NegativeTaxonomyException(
      NegativeTaxonomyErrorKind.malformedValue,
      'expected an array',
      path: path,
    );
  }

  String _asString(Object? value, String path) {
    if (value is String) return value;
    throw NegativeTaxonomyException(
      NegativeTaxonomyErrorKind.malformedValue,
      'expected a string',
      path: path,
    );
  }

  int _asInt(Object? value, String path) {
    if (value is int) return value;
    throw NegativeTaxonomyException(
      NegativeTaxonomyErrorKind.malformedValue,
      'expected an integer',
      path: path,
    );
  }
}
