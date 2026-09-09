/// Model-bound confidence-calibration artefact (E14-R21 strum, E14-R32
/// chord; ADR 0536/0540).
///
/// This file defines the ONLY shape a calibrated confidence may come from:
/// a versioned artefact that names the model it was fitted for
/// (`modelId` + `modelSha256`), the corpus it was fitted on
/// (`corpusId` + `corpusSha256`), and the fold that produced it
/// (`foldId` + `sampling`). Nothing here fits anything — fitting happens in
/// `ml/honest_eval.py::section_calib` on a HELD-OUT fold and is emitted as
/// this artefact by CI (`ml-train.yml`, see
/// `docs/eval/training-and-holdout-repro.md`).
///
/// **Why the shipped Dart knots are NOT promoted into an artefact.**
/// `lib/features/live/engine/ml/live_crnn_classifier.dart::calibrate`
/// carries a piecewise-linear knot list (`0.50→0.55 … 1.00→0.87`). Its own
/// source —
/// `ml/honest_eval.py::section_calib`'s docstring — records that those knots
/// were fitted on the SAME eval fold the accuracy was reported on, i.e.
/// in-sample. An in-sample mapping cannot bound the risk of an unseen strum,
/// so promoting it would manufacture a number the measurement does not
/// support (ADR 0271: UNKNOWN > CONFIDENTLY WRONG). The artefact format can
/// REPRESENT it — [CalibrationSampling.inSample] — but
/// [ConfidenceCalibrationResolver] refuses to serve it, so
/// `StrumPrediction.calibratedConfidence` and
/// `ChordPrediction.calibratedConfidence` stay `null` until a held-out
/// artefact exists.
///
/// This file never opens a file or a socket: reading the artefact bytes is
/// the caller's job (`data/evaluation/calibration_artefact_loader.dart`).
library;

import 'dart:convert';

/// Which recognition band an artefact calibrates. An artefact is never
/// band-agnostic: a strum profile served to the chord path (or the reverse)
/// is a typed refusal, not a silent identity.
enum CalibrationBand {
  strum,
  chord;

  static CalibrationBand fromJson(Object? value) => switch (value) {
    'strum' => CalibrationBand.strum,
    'chord' => CalibrationBand.chord,
    _ => throw CalibrationConfigException(
      CalibrationConfigErrorKind.malformedValue,
      'unknown band "$value" (expected "strum" or "chord")',
      path: 'calibration.band',
    ),
  };

  String toJson() => name;
}

/// How the fold that produced the artefact relates to the fold its accuracy
/// was reported on. [inSample] artefacts are representable but never served
/// (see the library doc).
enum CalibrationSampling {
  heldOut,
  inSample;

  static CalibrationSampling fromJson(Object? value) => switch (value) {
    'heldOut' => CalibrationSampling.heldOut,
    'inSample' => CalibrationSampling.inSample,
    _ => throw CalibrationConfigException(
      CalibrationConfigErrorKind.malformedValue,
      'unknown sampling "$value" (expected "heldOut" or "inSample")',
      path: 'calibration.provenance.sampling',
    ),
  };

  String toJson() => name;
}

/// The mapping family an artefact carries.
enum CalibrationMappingKind {
  /// `calibrated == raw` — a real, declarable state (a model measured to be
  /// already calibrated), never an implicit fallback for a missing artefact.
  identity,

  /// Monotone piecewise-linear interpolation between knots.
  piecewiseLinear;

  static CalibrationMappingKind fromJson(Object? value, String path) =>
      switch (value) {
        'identity' => CalibrationMappingKind.identity,
        'piecewiseLinear' => CalibrationMappingKind.piecewiseLinear,
        _ => throw CalibrationConfigException(
          CalibrationConfigErrorKind.malformedValue,
          'unknown mapping kind "$value" (expected '
          'identity/piecewiseLinear)',
          path: path,
        ),
      };

  String toJson() => name;
}

enum CalibrationConfigErrorKind {
  malformedValue,
  missingField,
  unknownField,
  unknownSchemaVersion,
  nonMonotonic,
  outOfRange,
  tooFewKnots,
  duplicateClassKey,
}

/// A typed artefact-parse failure. Never a bare [FormatException] or
/// [TypeError] — every rejection names its [kind] and, where applicable, the
/// offending JSON [path] (same shape as
/// `RecognitionGateConfigException`, ADR 0511 D6).
final class CalibrationConfigException implements Exception {
  const CalibrationConfigException(this.kind, this.message, {this.path});

  final CalibrationConfigErrorKind kind;
  final String message;
  final String? path;

  @override
  String toString() =>
      'CalibrationConfigException(${kind.name})'
      '${path == null ? '' : ' at $path'}: $message';
}

/// The only artefact schema version this code accepts. An unrecognised
/// version is a typed error, never a fall-back to a default mapping.
const String supportedCalibrationSchemaVersion = '1';

/// The model an artefact is bound to. Both fields are compared verbatim:
/// a matching id with a different sha256 is a MISMATCH (the weights changed
/// under the calibration).
final class CalibrationModelIdentity {
  const CalibrationModelIdentity({
    required this.modelId,
    required this.modelSha256,
  });

  final String modelId;
  final String modelSha256;

  bool matches(CalibrationModelIdentity other) =>
      modelId == other.modelId && modelSha256 == other.modelSha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'modelId': modelId,
    'modelSha256': modelSha256,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalibrationModelIdentity &&
          other.modelId == modelId &&
          other.modelSha256 == modelSha256;

  @override
  int get hashCode => Object.hash(modelId, modelSha256);
}

/// Where an artefact's numbers came from. Every field is REQUIRED and
/// non-empty: an artefact that cannot say which corpus and which fold
/// produced it is not evidence, and [ConfidenceCalibrationProfile.parse]
/// rejects it.
final class CalibrationProvenance {
  const CalibrationProvenance({
    required this.corpusId,
    required this.corpusSha256,
    required this.foldId,
    required this.sampling,
    required this.observationCount,
    required this.fittedAtCommit,
    required this.producedBy,
  });

  final String corpusId;
  final String corpusSha256;

  /// The fold identifier inside that corpus (e.g. `logo-fold-3`).
  final String foldId;

  final CalibrationSampling sampling;

  /// How many labelled observations the mapping was fitted on. `0` is a
  /// parse error, not "a measurement of nothing" (ADR 0354 D2 precedent).
  final int observationCount;

  /// The repository commit the fitting script ran at.
  final String fittedAtCommit;

  /// The command/workflow that emitted the artefact, e.g.
  /// `ml-train.yml sections=calib`.
  final String producedBy;

  Map<String, Object?> toJson() => <String, Object?>{
    'corpusId': corpusId,
    'corpusSha256': corpusSha256,
    'foldId': foldId,
    'sampling': sampling.toJson(),
    'observationCount': observationCount,
    'fittedAtCommit': fittedAtCommit,
    'producedBy': producedBy,
  };
}

/// One `(rawConfidence, calibratedConfidence)` knot.
final class CalibrationKnot {
  const CalibrationKnot({required this.raw, required this.calibrated});

  final double raw;
  final double calibrated;

  Map<String, Object?> toJson() => <String, Object?>{
    'raw': raw,
    'calibrated': calibrated,
  };
}

/// A monotone confidence mapping. Two families only ([CalibrationMappingKind]);
/// both are total on `0..1` and both are non-decreasing, so a higher raw
/// score can never map to a lower calibrated confidence (the invariant
/// `test/property/calibration_monotonicity_property_test.dart` samples).
final class CalibrationMapping {
  const CalibrationMapping._(this.kind, this.knots);

  /// `calibrated == raw`, clamped to `0..1`.
  const CalibrationMapping.identity()
    : this._(CalibrationMappingKind.identity, const <CalibrationKnot>[]);

  /// Validates and builds a piecewise-linear mapping:
  ///
  /// * at least two knots;
  /// * every `raw`/`calibrated` inside `0..1`;
  /// * `raw` STRICTLY increasing (a repeated x would make the map
  ///   ambiguous — and a division by zero);
  /// * `calibrated` non-decreasing (monotone by construction, so no fitted
  ///   artefact can invert the ordering of two confidences).
  factory CalibrationMapping.piecewiseLinear(
    List<CalibrationKnot> knots, {
    String path = 'calibration.mapping',
  }) {
    if (knots.length < 2) {
      throw CalibrationConfigException(
        CalibrationConfigErrorKind.tooFewKnots,
        'a piecewise-linear mapping needs at least 2 knots, got '
        '${knots.length}',
        path: path,
      );
    }
    for (var i = 0; i < knots.length; i++) {
      final knot = knots[i];
      if (knot.raw < 0 || knot.raw > 1) {
        throw CalibrationConfigException(
          CalibrationConfigErrorKind.outOfRange,
          'knot raw ${knot.raw} is outside 0..1',
          path: '$path.knots[$i].raw',
        );
      }
      if (knot.calibrated < 0 || knot.calibrated > 1) {
        throw CalibrationConfigException(
          CalibrationConfigErrorKind.outOfRange,
          'knot calibrated ${knot.calibrated} is outside 0..1',
          path: '$path.knots[$i].calibrated',
        );
      }
      if (i == 0) continue;
      if (knot.raw <= knots[i - 1].raw) {
        throw CalibrationConfigException(
          CalibrationConfigErrorKind.nonMonotonic,
          'knot raw values must be strictly increasing '
          '(${knots[i - 1].raw} then ${knot.raw})',
          path: '$path.knots[$i].raw',
        );
      }
      if (knot.calibrated < knots[i - 1].calibrated) {
        throw CalibrationConfigException(
          CalibrationConfigErrorKind.nonMonotonic,
          'knot calibrated values must be non-decreasing '
          '(${knots[i - 1].calibrated} then ${knot.calibrated})',
          path: '$path.knots[$i].calibrated',
        );
      }
    }
    return CalibrationMapping._(
      CalibrationMappingKind.piecewiseLinear,
      List<CalibrationKnot>.unmodifiable(knots),
    );
  }

  final CalibrationMappingKind kind;
  final List<CalibrationKnot> knots;

  /// Maps [raw] to a calibrated confidence in `0..1`. Outside the knot
  /// range the mapping is CLAMPED to the end knot (never extrapolated — an
  /// extrapolated tail is a number no fold ever measured).
  double apply(double raw) {
    final clamped = raw < 0
        ? 0.0
        : raw > 1
        ? 1.0
        : raw;
    switch (kind) {
      case CalibrationMappingKind.identity:
        return clamped;
      case CalibrationMappingKind.piecewiseLinear:
        if (clamped <= knots.first.raw) return knots.first.calibrated;
        for (var i = 1; i < knots.length; i++) {
          if (clamped <= knots[i].raw) {
            final lower = knots[i - 1];
            final upper = knots[i];
            final t = (clamped - lower.raw) / (upper.raw - lower.raw);
            final span = upper.calibrated - lower.calibrated;
            return lower.calibrated + span * t;
          }
        }
        return knots.last.calibrated;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.toJson(),
    'knots': <Map<String, Object?>>[for (final knot in knots) knot.toJson()],
  };
}

/// A chord class key: root pitch class plus quality (`A` + `min`). The chord
/// artefact may carry one mapping per class ON TOP OF the default mapping —
/// per-class calibration is the ADR 0540 D3 seam, not a promise that such a
/// fit exists.
final class ChordClassKey {
  const ChordClassKey({required this.root, required this.quality});

  /// Parses `"A#m"` → root `A#`, quality `min`; `"C"` → root `C`, quality
  /// `maj`. The two RESERVED evaluation labels
  /// ([recognitionNoChordLabel], [recognitionUnknownChordLabel]) are NOT
  /// chord classes and are rejected here.
  static ChordClassKey? tryParseLabel(String label) {
    if (label.isEmpty ||
        label == recognitionNoChordLabel ||
        label == recognitionUnknownChordLabel) {
      return null;
    }
    var index = 1;
    if (label.length > 1 && (label[1] == '#' || label[1] == 'b')) index = 2;
    final root = label.substring(0, index);
    if (!_rootNames.contains(root)) return null;
    final suffix = label.substring(index);
    final quality = switch (suffix) {
      '' => 'maj',
      'm' => 'min',
      _ => suffix,
    };
    return ChordClassKey(root: root, quality: quality);
  }

  static const Set<String> _rootNames = <String>{
    'C',
    'C#',
    'Db',
    'D',
    'D#',
    'Eb',
    'E',
    'F',
    'F#',
    'Gb',
    'G',
    'G#',
    'Ab',
    'A',
    'A#',
    'Bb',
    'B',
  };

  final String root;
  final String quality;

  /// The artefact's wire form: `"<root>:<quality>"`.
  String get wireKey => '$root:$quality';

  @override
  String toString() => wireKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordClassKey &&
          other.root == root &&
          other.quality == quality;

  @override
  int get hashCode => Object.hash(root, quality);
}

/// The evaluation label for "no chord is sounding". Mirrors the literal
/// `recognition_metrics.dart` reports `chordNoChordF1` against — a machine
/// mirror keeps the two from drifting.
const String recognitionNoChordLabel = 'noChord';

/// The evaluation label for "a chord is sounding, but it is not one this
/// model supports" (open-set, E14-R32). Distinct from
/// [recognitionNoChordLabel] by construction: `recognition_metrics.dart`
/// counts it in `chordUnknownFalseAccept`, a different metric.
const String recognitionUnknownChordLabel = 'unknown';

/// A parsed, model-bound calibration artefact.
final class ConfidenceCalibrationProfile {
  const ConfidenceCalibrationProfile({
    required this.schemaVersion,
    required this.artefactVersion,
    required this.band,
    required this.model,
    required this.provenance,
    required this.defaultMapping,
    required this.perClassMappings,
  });

  final String schemaVersion;

  /// The artefact's own version string, e.g. `strum-live3c-heldout-v1`.
  final String artefactVersion;

  final CalibrationBand band;
  final CalibrationModelIdentity model;
  final CalibrationProvenance provenance;
  final CalibrationMapping defaultMapping;

  /// Chord band only; empty for a strum artefact.
  final Map<ChordClassKey, CalibrationMapping> perClassMappings;

  /// `true` only for a HELD-OUT artefact (see the library doc).
  bool get isServable => provenance.sampling == CalibrationSampling.heldOut;

  /// Applies the mapping for [chordClass] when the artefact carries one,
  /// otherwise the default mapping. Never consults the model binding — that
  /// is [ConfidenceCalibrationResolver]'s job, so a caller cannot bypass it
  /// by reaching for the mapping directly with a mismatched model.
  double applyRaw(double rawConfidence, {ChordClassKey? chordClass}) {
    final mapping = chordClass == null
        ? defaultMapping
        : perClassMappings[chordClass] ?? defaultMapping;
    return mapping.apply(rawConfidence);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'artefactVersion': artefactVersion,
    'band': band.toJson(),
    'model': model.toJson(),
    'provenance': provenance.toJson(),
    'mapping': defaultMapping.toJson(),
    'perClassMappings': <String, Object?>{
      for (final entry in _sortedPerClassEntries())
        entry.key.wireKey: entry.value.toJson(),
    },
  };

  List<MapEntry<ChordClassKey, CalibrationMapping>> _sortedPerClassEntries() {
    final entries = perClassMappings.entries.toList()
      ..sort((a, b) => a.key.wireKey.compareTo(b.key.wireKey));
    return entries;
  }

  /// Parses an artefact from its JSON text. Every failure is a typed
  /// [CalibrationConfigException] — there is no partially parsed profile and
  /// no default-filled field.
  static ConfidenceCalibrationProfile parseJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw CalibrationConfigException(
        CalibrationConfigErrorKind.malformedValue,
        'calibration artefact is not valid JSON: ${error.message}',
        path: 'calibration',
      );
    }
    return parse(_asMap(decoded, 'calibration'));
  }

  static ConfidenceCalibrationProfile parse(Map<String, Object?> json) {
    _checkKeys(json, _rootKeys, 'calibration');
    final schemaVersion = _requireString(json, 'schemaVersion', 'calibration');
    if (schemaVersion != supportedCalibrationSchemaVersion) {
      throw CalibrationConfigException(
        CalibrationConfigErrorKind.unknownSchemaVersion,
        'unsupported schemaVersion "$schemaVersion" (expected '
        '"$supportedCalibrationSchemaVersion")',
        path: 'calibration.schemaVersion',
      );
    }
    final band = CalibrationBand.fromJson(
      _requireField(json, 'band', 'calibration'),
    );
    final modelJson = _asMap(
      _requireField(json, 'model', 'calibration'),
      'calibration.model',
    );
    _checkKeys(modelJson, _modelKeys, 'calibration.model');
    final model = CalibrationModelIdentity(
      modelId: _requireNonEmptyString(
        modelJson,
        'modelId',
        'calibration.model',
      ),
      modelSha256: _requireNonEmptyString(
        modelJson,
        'modelSha256',
        'calibration.model',
      ),
    );
    final provenance = _parseProvenance(
      _asMap(
        _requireField(json, 'provenance', 'calibration'),
        'calibration.provenance',
      ),
    );
    final defaultMapping = _parseMapping(
      _asMap(
        _requireField(json, 'mapping', 'calibration'),
        'calibration.mapping',
      ),
      'calibration.mapping',
    );
    final perClass = <ChordClassKey, CalibrationMapping>{};
    final rawPerClass = json['perClassMappings'];
    if (rawPerClass != null) {
      final perClassJson = _asMap(rawPerClass, 'calibration.perClassMappings');
      for (final entry in perClassJson.entries) {
        final path = 'calibration.perClassMappings.${entry.key}';
        final parts = entry.key.split(':');
        if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
          throw CalibrationConfigException(
            CalibrationConfigErrorKind.malformedValue,
            'per-class key must be "<root>:<quality>"',
            path: path,
          );
        }
        final key = ChordClassKey(root: parts[0], quality: parts[1]);
        if (perClass.containsKey(key)) {
          throw CalibrationConfigException(
            CalibrationConfigErrorKind.duplicateClassKey,
            'per-class key "${key.wireKey}" appears twice',
            path: path,
          );
        }
        perClass[key] = _parseMapping(_asMap(entry.value, path), path);
      }
    }
    if (band == CalibrationBand.strum && perClass.isNotEmpty) {
      throw CalibrationConfigException(
        CalibrationConfigErrorKind.unknownField,
        'a strum artefact must not carry per-class mappings — the strum '
        'band has no chord classes',
        path: 'calibration.perClassMappings',
      );
    }
    return ConfidenceCalibrationProfile(
      schemaVersion: schemaVersion,
      artefactVersion: _requireNonEmptyString(
        json,
        'artefactVersion',
        'calibration',
      ),
      band: band,
      model: model,
      provenance: provenance,
      defaultMapping: defaultMapping,
      perClassMappings: Map<ChordClassKey, CalibrationMapping>.unmodifiable(
        perClass,
      ),
    );
  }

  static CalibrationProvenance _parseProvenance(Map<String, Object?> json) {
    const path = 'calibration.provenance';
    _checkKeys(json, _provenanceKeys, path);
    final observationCount = _requireInt(json, 'observationCount', path);
    if (observationCount <= 0) {
      throw CalibrationConfigException(
        CalibrationConfigErrorKind.outOfRange,
        'observationCount must be > 0 — an artefact fitted on nothing is '
        'not a measurement',
        path: '$path.observationCount',
      );
    }
    return CalibrationProvenance(
      corpusId: _requireNonEmptyString(json, 'corpusId', path),
      corpusSha256: _requireNonEmptyString(json, 'corpusSha256', path),
      foldId: _requireNonEmptyString(json, 'foldId', path),
      sampling: CalibrationSampling.fromJson(
        _requireField(json, 'sampling', path),
      ),
      observationCount: observationCount,
      fittedAtCommit: _requireNonEmptyString(json, 'fittedAtCommit', path),
      producedBy: _requireNonEmptyString(json, 'producedBy', path),
    );
  }

  static CalibrationMapping _parseMapping(
    Map<String, Object?> json,
    String path,
  ) {
    _checkKeys(json, _mappingKeys, path);
    final kind = CalibrationMappingKind.fromJson(
      _requireField(json, 'kind', path),
      '$path.kind',
    );
    switch (kind) {
      case CalibrationMappingKind.identity:
        if (json.containsKey('knots')) {
          throw CalibrationConfigException(
            CalibrationConfigErrorKind.unknownField,
            'an identity mapping must not declare knots',
            path: '$path.knots',
          );
        }
        return const CalibrationMapping.identity();
      case CalibrationMappingKind.piecewiseLinear:
        final rawKnots = _asList(
          _requireField(json, 'knots', path),
          '$path.knots',
        );
        final knots = <CalibrationKnot>[
          for (var i = 0; i < rawKnots.length; i++)
            _parseKnot(
              _asMap(rawKnots[i], '$path.knots[$i]'),
              '$path.knots[$i]',
            ),
        ];
        return CalibrationMapping.piecewiseLinear(knots, path: path);
    }
  }

  static CalibrationKnot _parseKnot(Map<String, Object?> json, String path) {
    _checkKeys(json, _knotKeys, path);
    return CalibrationKnot(
      raw: _requireDouble(json, 'raw', path),
      calibrated: _requireDouble(json, 'calibrated', path),
    );
  }
}

const _rootKeys = <String>{
  'schemaVersion',
  'artefactVersion',
  'band',
  'model',
  'provenance',
  'mapping',
  'perClassMappings',
};
const _modelKeys = <String>{'modelId', 'modelSha256'};
const _provenanceKeys = <String>{
  'corpusId',
  'corpusSha256',
  'foldId',
  'sampling',
  'observationCount',
  'fittedAtCommit',
  'producedBy',
};
const _mappingKeys = <String>{'kind', 'knots'};
const _knotKeys = <String>{'raw', 'calibrated'};

/// Why a calibrated confidence is unavailable. Every value is a REASON the
/// caller can surface or log — never a silent `null`.
enum CalibrationUnavailableReason {
  /// No artefact has been loaded for this band. This is the shipped state
  /// (E14-R21/R32): no held-out fit exists yet.
  noArtefact,

  /// The artefact names a different model id or a different sha256 than the
  /// weights actually loaded — fail-closed (ADR 0536 D4).
  modelMismatch,

  /// The artefact calibrates the other band.
  bandMismatch,

  /// The artefact was fitted in-sample (see the library doc).
  inSampleArtefact,
}

/// The result of asking for a calibrated confidence: EITHER a value OR a
/// reason, never both and never neither.
final class CalibrationOutcome {
  const CalibrationOutcome._(this.calibratedConfidence, this.unavailableReason);

  const CalibrationOutcome.value(double calibratedConfidence)
    : this._(calibratedConfidence, null);

  const CalibrationOutcome.unavailable(CalibrationUnavailableReason reason)
    : this._(null, reason);

  /// `null` exactly when [unavailableReason] is non-null.
  final double? calibratedConfidence;
  final CalibrationUnavailableReason? unavailableReason;

  bool get isAvailable => calibratedConfidence != null;
}

/// The single place a calibrated confidence may be produced. Holds the
/// artefact (or none) for one band and refuses to serve anything it cannot
/// justify.
///
/// The shipped default is [ConfidenceCalibrationResolver.absent] — every
/// call returns [CalibrationUnavailableReason.noArtefact], which is why
/// `StrumPrediction.calibratedConfidence` and
/// `ChordPrediction.calibratedConfidence` stay `null` (ADR 0505 D2, ADR 0536
/// D1). Wiring the resolver into those predictions is PKG-A's wave-2 task;
/// this class is the value it will read.
final class ConfidenceCalibrationResolver {
  const ConfidenceCalibrationResolver({required this.band, this.profile});

  /// No artefact for [band] — the shipped state.
  const ConfidenceCalibrationResolver.absent(CalibrationBand band)
    : this(band: band);

  final CalibrationBand band;
  final ConfidenceCalibrationProfile? profile;

  /// Maps [rawConfidence] through the artefact, or explains why it cannot.
  /// [loadedModel] is the identity of the weights that ACTUALLY produced
  /// [rawConfidence] — the binding is checked on every call, so a model
  /// swap can never leave a stale mapping in place.
  CalibrationOutcome calibrate({
    required double rawConfidence,
    required CalibrationModelIdentity loadedModel,
    ChordClassKey? chordClass,
  }) {
    final artefact = profile;
    if (artefact == null) {
      return const CalibrationOutcome.unavailable(
        CalibrationUnavailableReason.noArtefact,
      );
    }
    if (artefact.band != band) {
      return const CalibrationOutcome.unavailable(
        CalibrationUnavailableReason.bandMismatch,
      );
    }
    if (!artefact.model.matches(loadedModel)) {
      return const CalibrationOutcome.unavailable(
        CalibrationUnavailableReason.modelMismatch,
      );
    }
    if (!artefact.isServable) {
      return const CalibrationOutcome.unavailable(
        CalibrationUnavailableReason.inSampleArtefact,
      );
    }
    return CalibrationOutcome.value(
      artefact.applyRaw(rawConfidence, chordClass: chordClass),
    );
  }
}

// --- typed field access helpers ------------------------------------------

void _checkKeys(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw CalibrationConfigException(
        CalibrationConfigErrorKind.unknownField,
        'unrecognised field "$key"',
        path: '$path.$key',
      );
    }
  }
}

Object? _requireField(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key)) {
    throw CalibrationConfigException(
      CalibrationConfigErrorKind.missingField,
      '"$key" is required',
      path: '$path.$key',
    );
  }
  return json[key];
}

String _requireString(Map<String, Object?> json, String key, String path) =>
    _asString(_requireField(json, key, path), '$path.$key');

String _requireNonEmptyString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = _requireString(json, key, path);
  if (value.isEmpty) {
    throw CalibrationConfigException(
      CalibrationConfigErrorKind.malformedValue,
      '"$key" must not be empty',
      path: '$path.$key',
    );
  }
  return value;
}

double _requireDouble(Map<String, Object?> json, String key, String path) {
  final value = _requireField(json, key, path);
  if (value is num) return value.toDouble();
  throw CalibrationConfigException(
    CalibrationConfigErrorKind.malformedValue,
    'expected a number',
    path: '$path.$key',
  );
}

int _requireInt(Map<String, Object?> json, String key, String path) {
  final value = _requireField(json, key, path);
  if (value is int) return value;
  throw CalibrationConfigException(
    CalibrationConfigErrorKind.malformedValue,
    'expected an integer',
    path: '$path.$key',
  );
}

Map<String, Object?> _asMap(Object? value, String path) {
  if (value is Map) {
    return value.map((key, v) => MapEntry(key as String, v));
  }
  throw CalibrationConfigException(
    CalibrationConfigErrorKind.malformedValue,
    'expected an object',
    path: path,
  );
}

List<Object?> _asList(Object? value, String path) {
  if (value is List) return value;
  throw CalibrationConfigException(
    CalibrationConfigErrorKind.malformedValue,
    'expected an array',
    path: path,
  );
}

String _asString(Object? value, String path) {
  if (value is String) return value;
  throw CalibrationConfigException(
    CalibrationConfigErrorKind.malformedValue,
    'expected a string',
    path: path,
  );
}
