/// The recognition-aggregate telemetry event of the opt-in beta
/// (SDD Ch14 Kör 41, ADR 0542 D5).
///
/// It follows `telemetry_event.dart`'s rule literally: the prohibition on
/// carrying raw user content is STRUCTURAL. There is no audio field, no
/// free-text field, no `Map<String, dynamic>` payload, no device identifier
/// and no raw millisecond count on [RecognitionTelemetryEvent] — every
/// member is a closed enum, a bucket, a bool, or the rotating pseudonym.
/// A field that does not exist cannot leak; the redactor is the second line
/// of defence, never the first.
///
/// The one place free-form data can still arrive is the diagnostic context a
/// future sink might want to attach. It is an ARGUMENT of
/// [RecognitionTelemetryCodec.encode], never a stored field, and it passes
/// through an allowlist there — a key the allowlist does not name is
/// dropped, not forwarded, because a denylist forwards every key it has not
/// heard of yet.
library;

import 'telemetry_consent.dart';
import 'telemetry_event.dart';
import 'telemetry_redactor.dart';

/// Which recognition band an aggregate describes.
enum RecognitionTelemetryBand { strumDirection, chordLabel, onsetDetection }

/// Which shipped recogniser produced the aggregate.
///
/// A closed enum keyed to the assets in `assets/ml/model_manifest.json` plus
/// the DSP path, exactly like [TelemetryCapability]: a free "model version"
/// string would reopen the free-text hole the event contract closes, and a
/// checkpoint filename is itself a build fingerprint.
enum RecognitionTelemetryModel {
  /// The live NNLS-chroma → dictionary → Viterbi chord path (no ML asset).
  nnlsChroma,
  strumCrnn,
  strumCrnnLive,
  strumCrnnLive3c,
  chordCrnn,
}

/// The input-quality band the aggregate was collected under.
///
/// Declared here rather than reused from `lib/features/live/**` on purpose:
/// `lib/core/` may not import a feature (architecture rule 1), and a core
/// copy that drifts is better than a layering violation. The mapping from
/// the live signal-quality state machine to this bucket is the consumer's
/// documented job.
enum RecognitionTelemetryQualityBucket { good, fair, poor, unusable }

/// A count expressed as a bucket, never as a raw number — the same reason
/// `TelemetryDurationBucket` exists: an exact count is a low-entropy but
/// still free numeric channel, and every SLO in the beta report is a rate,
/// not a tally.
///
/// Boundaries are inclusive on the lower edge: `0, [1,5), [5,20), [20,100),
/// [100,∞)`.
enum RecognitionTelemetryCountBucket {
  none(upperExclusive: 1),
  c1To4(upperExclusive: 5),
  c5To19(upperExclusive: 20),
  c20To99(upperExclusive: 100),
  c100AndAbove(upperExclusive: null);

  const RecognitionTelemetryCountBucket({required this.upperExclusive});

  /// The bucket's exclusive upper bound, or `null` for the top bucket.
  final int? upperExclusive;

  /// Maps a measured count to its bucket. [count] must be `>= 0`.
  static RecognitionTelemetryCountBucket fromCount(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must be >= 0');
    }
    for (final bucket in RecognitionTelemetryCountBucket.values) {
      final upper = bucket.upperExclusive;
      if (upper == null || count < upper) return bucket;
    }
    return RecognitionTelemetryCountBucket.c100AndAbove;
  }
}

/// One privacy-safe recognition aggregate.
final class RecognitionTelemetryEvent {
  const RecognitionTelemetryEvent({
    required this.band,
    required this.model,
    required this.qualityBucket,
    required this.acceptedCount,
    required this.rejectedCount,
    required this.verdictLatencyBucket,
    required this.userCorrected,
  });

  final RecognitionTelemetryBand band;
  final RecognitionTelemetryModel model;
  final RecognitionTelemetryQualityBucket qualityBucket;

  /// How many verdicts the decision state machine ACCEPTED in the window.
  final RecognitionTelemetryCountBucket acceptedCount;

  /// How many it rejected/abstained on. Reported alongside [acceptedCount]
  /// because an accuracy without its coverage is exactly the confidently
  /// wrong number Ch14 §9 forbids.
  final RecognitionTelemetryCountBucket rejectedCount;

  final TelemetryDurationBucket verdictLatencyBucket;

  /// Whether the user corrected the recognition during the window. A bool,
  /// never the correction itself — "what they played instead" is user
  /// content.
  final bool userCorrected;

  /// The catalogue event this aggregate is reported as.
  TelemetryEvent get envelopeEvent => TelemetryEvent(
    name: TelemetryEventName.recognitionQualityReported,
    category: TelemetryEventCategory.detection,
    result: TelemetryOperationResult.success,
    durationBucket: verdictLatencyBucket,
    capability: switch (model) {
      RecognitionTelemetryModel.nnlsChroma => TelemetryCapability.onDeviceDsp,
      RecognitionTelemetryModel.strumCrnn ||
      RecognitionTelemetryModel.strumCrnnLive ||
      RecognitionTelemetryModel.strumCrnnLive3c ||
      RecognitionTelemetryModel.chordCrnn => TelemetryCapability.onDeviceMl,
    },
  );
}

/// A recognition aggregate together with the pseudonym it is reported under.
///
/// There is deliberately NO context/metadata FIELD here: a stored
/// `Map<String, Object?>` would be a free-form payload slot on a telemetry
/// type, which is the exact hole ADR 0484 D1 closes. Diagnostic context, if
/// a future sink has any, is passed to
/// [RecognitionTelemetryCodec.encode] as an argument and survives only if
/// the allowlist names it.
final class RecognitionTelemetryEnvelope {
  const RecognitionTelemetryEnvelope({
    required this.event,
    required this.pseudonym,
  });

  final RecognitionTelemetryEvent event;

  /// The rotating pseudonym from the consent record. There is no other
  /// identifier on this envelope, by construction.
  final TelemetryPseudonymId pseudonym;
}

/// Encodes an envelope into the exact, closed key set the beta report reads.
///
/// The encoder is an ALLOWLIST in both directions:
/// - the event's own fields are written key by key (there is no reflection,
///   no `toJson` on an open model, no spread of a caller map), and
/// - the caller's `diagnosticContext` contributes only keys named in
///   [allowedContextKeys], whose values are additionally sent through
///   [TelemetryRedactor]. A denylist would forward every key it has not
///   heard of yet, which is precisely how a new field leaks.
abstract final class RecognitionTelemetryCodec {
  /// Every key the encoder may ever emit, at any depth. The redaction
  /// property test declares this set independently and compares — a new,
  /// unreviewed key makes the difference non-empty and the test red.
  static const Set<String> allowedKeys = <String>{
    'schemaVersion',
    'pseudonymId',
    'band',
    'model',
    'qualityBucket',
    'acceptedCountBucket',
    'rejectedCountBucket',
    'verdictLatencyBucket',
    'userCorrected',
    ...allowedContextKeys,
  };

  /// The only diagnostic-context keys that survive encoding. Each is a
  /// closed, hand-picked name whose value is a bucket or an enum name —
  /// never a path, a filename, an account id or a device identifier.
  static const Set<String> allowedContextKeys = <String>{
    'rolloutStage',
    'sessionSurface',
  };

  /// Bumped whenever the emitted key set changes, so a report reader can
  /// tell an old payload from a new one without guessing.
  static const int schemaVersion = 1;

  /// The longest enum-name-shaped context token accepted. Long enough for
  /// every value in the closed enums this layer reports, far too short for
  /// a path, a sentence or a base64 blob.
  static const int maxContextTokenLength = 32;

  /// Encodes [envelope]. The returned map contains only [allowedKeys].
  ///
  /// [diagnosticContext] is treated as UNTRUSTED input: a key the allowlist
  /// does not name never reaches the result, whatever its value.
  static Map<String, Object?> encode(
    RecognitionTelemetryEnvelope envelope, {
    Map<String, Object?> diagnosticContext = const <String, Object?>{},
  }) {
    final event = envelope.event;
    final encoded = <String, Object?>{
      'schemaVersion': schemaVersion,
      'pseudonymId': envelope.pseudonym.value,
      'band': event.band.name,
      'model': event.model.name,
      'qualityBucket': event.qualityBucket.name,
      'acceptedCountBucket': event.acceptedCount.name,
      'rejectedCountBucket': event.rejectedCount.name,
      'verdictLatencyBucket': event.verdictLatencyBucket.name,
      'userCorrected': event.userCorrected,
    };
    for (final key in allowedContextKeys) {
      if (!diagnosticContext.containsKey(key)) continue;
      final value = diagnosticContext[key];
      // An allowlisted KEY is not an allowlisted VALUE. Only three shapes
      // survive:
      //   * a bool or an int (a flag or a bucket index), and
      //   * a String that is ENUM-NAME shaped — letters and digits only,
      //     at most [maxContextTokenLength] characters.
      // Everything else is dropped: a nested map or list would smuggle
      // unreviewed keys past the top-level allowlist, and a free string
      // would carry a filename, a path or a serial number through a key
      // whose NAME was reviewed once and whose CONTENT never is.
      if (value is bool || value is int) {
        encoded[key] = value;
      } else if (value is String && _isEnumNameShaped(value)) {
        // The shared redactor stays in the path as a second line of
        // defence even though an enum-shaped token cannot trip it.
        encoded[key] = TelemetryRedactor.sanitizeText(value);
      }
    }
    return encoded;
  }

  /// Whether [value] looks like an enum's `name`: a leading ASCII letter
  /// followed by letters and digits only. Written with code-unit checks
  /// rather than a pattern so this file declares no second regular
  /// expression next to the shared redactor's (ADR 0484 D2).
  static bool _isEnumNameShaped(String value) {
    if (value.isEmpty || value.length > maxContextTokenLength) return false;
    for (var index = 0; index < value.length; index += 1) {
      final unit = value.codeUnitAt(index);
      final isLetter =
          (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);
      final isDigit = unit >= 0x30 && unit <= 0x39;
      if (index == 0 && !isLetter) return false;
      if (!isLetter && !isDigit) return false;
    }
    return true;
  }
}
