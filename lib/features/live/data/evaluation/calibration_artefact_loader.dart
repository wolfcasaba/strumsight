/// Loads a [ConfidenceCalibrationProfile] artefact (E14-R21/R32, ADR
/// 0536/0540).
///
/// This file has NO `dart:io`, no `rootBundle` and no plugin import: the
/// bytes arrive through an injected [CalibrationArtefactReader], so the
/// loader is unit-testable without a Flutter binding and works identically
/// on an asset, a file or a downloaded artefact. Reading is the caller's
/// job — deciding what the bytes mean is this file's.
///
/// **Nothing is swallowed.** A malformed artefact does not degrade to "no
/// calibration": it returns [CalibrationLoadStatus.invalid] carrying the
/// typed [CalibrationConfigException], and the caller MUST surface it (the
/// runtime-info fallback reason is the intended sink, ADR 0536 D6). A
/// silent `try/catch` here would reproduce exactly the class of bug
/// `docs/LESSONS.md` L619 records.
library;

import 'package:strumsight/features/live/domain/evaluation/confidence_calibration_profile.dart';

/// Returns the artefact's UTF-8 text, or `null` when there is no artefact at
/// the given path. Implementations must NOT translate a parse failure into
/// `null` — only absence.
typedef CalibrationArtefactReader = Future<String?> Function(String path);

/// The canonical asset path for a model's calibration artefact:
/// `assets/ml/<modelId>.calibration.json`.
///
/// The artefact is deliberately a SEPARATE file from the weights: a
/// re-calibration must be shippable without re-exporting the model, and the
/// artefact names the weights it belongs to (`modelSha256`), so the pair can
/// never drift silently. Adding a real artefact also needs a `pubspec.yaml`
/// asset line — assets are listed file-by-file there.
String calibrationAssetPathFor(String modelId) =>
    'assets/ml/$modelId.calibration.json';

enum CalibrationLoadStatus {
  /// A well-formed artefact was found and parsed.
  loaded,

  /// No artefact exists for this model — the SHIPPED state (E14-R21/R32:
  /// no held-out fit has been produced yet).
  absent,

  /// An artefact exists but is not a valid artefact.
  invalid,
}

/// The outcome of one load attempt. Exactly one of [profile] / [error] is
/// non-null, and both are `null` for [CalibrationLoadStatus.absent].
final class CalibrationLoadResult {
  const CalibrationLoadResult._(
    this.status,
    this.assetPath,
    this.profile,
    this.error,
  );

  const CalibrationLoadResult.loaded(
    String assetPath,
    ConfidenceCalibrationProfile profile,
  ) : this._(CalibrationLoadStatus.loaded, assetPath, profile, null);

  const CalibrationLoadResult.absent(String assetPath)
    : this._(CalibrationLoadStatus.absent, assetPath, null, null);

  const CalibrationLoadResult.invalid(
    String assetPath,
    CalibrationConfigException error,
  ) : this._(CalibrationLoadStatus.invalid, assetPath, null, error);

  final CalibrationLoadStatus status;
  final String assetPath;
  final ConfidenceCalibrationProfile? profile;
  final CalibrationConfigException? error;

  /// A log line (never a user-facing string — it is not localised and names
  /// internal paths).
  String describe() {
    switch (status) {
      case CalibrationLoadStatus.loaded:
        final loaded = profile!;
        return 'calibration loaded from $assetPath '
            '(${loaded.artefactVersion}, '
            '${loaded.provenance.sampling.name})';
      case CalibrationLoadStatus.absent:
        return 'no calibration artefact at $assetPath';
      case CalibrationLoadStatus.invalid:
        return 'invalid calibration artefact at $assetPath: $error';
    }
  }
}

/// Reads and validates one band's calibration artefact.
final class CalibrationArtefactLoader {
  const CalibrationArtefactLoader(this.read);

  final CalibrationArtefactReader read;

  /// Loads the artefact for [model] and checks it against [expectedBand]
  /// and the model binding. A band or model mismatch is
  /// [CalibrationLoadStatus.invalid] — not "absent" — because an artefact
  /// that exists but does not belong here is a build/packaging error
  /// someone must see.
  Future<CalibrationLoadResult> load({
    required CalibrationModelIdentity model,
    required CalibrationBand expectedBand,
  }) async {
    final path = calibrationAssetPathFor(model.modelId);
    final source = await read(path);
    if (source == null) return CalibrationLoadResult.absent(path);
    final ConfidenceCalibrationProfile profile;
    try {
      profile = ConfidenceCalibrationProfile.parseJsonString(source);
    } on CalibrationConfigException catch (error) {
      // Not swallowed: the typed error travels out in the result.
      return CalibrationLoadResult.invalid(path, error);
    }
    if (profile.band != expectedBand) {
      return CalibrationLoadResult.invalid(
        path,
        CalibrationConfigException(
          CalibrationConfigErrorKind.malformedValue,
          'artefact calibrates the ${profile.band.name} band, but the '
          '${expectedBand.name} band asked for it',
          path: 'calibration.band',
        ),
      );
    }
    if (!profile.model.matches(model)) {
      return CalibrationLoadResult.invalid(
        path,
        CalibrationConfigException(
          CalibrationConfigErrorKind.malformedValue,
          'artefact is bound to ${profile.model.modelId}@'
          '${profile.model.modelSha256}, but the loaded weights are '
          '${model.modelId}@${model.modelSha256}',
          path: 'calibration.model',
        ),
      );
    }
    return CalibrationLoadResult.loaded(path, profile);
  }

  /// Builds the resolver a prediction path should hold. An absent or invalid
  /// artefact yields [ConfidenceCalibrationResolver.absent], so the
  /// prediction's `calibratedConfidence` stays `null` — the failure is
  /// reported through [CalibrationLoadResult], never through a made-up
  /// number.
  static ConfidenceCalibrationResolver resolverFrom(
    CalibrationBand band,
    CalibrationLoadResult result,
  ) => switch (result.status) {
    CalibrationLoadStatus.loaded => ConfidenceCalibrationResolver(
      band: band,
      profile: result.profile,
    ),
    CalibrationLoadStatus.absent ||
    CalibrationLoadStatus.invalid => ConfidenceCalibrationResolver.absent(band),
  };
}
