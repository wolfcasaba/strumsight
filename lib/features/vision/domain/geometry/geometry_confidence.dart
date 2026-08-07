/// Geometry tracking confidence and drift (SDD Ch6 §17.1, Kör 16).
///
/// A kézzel kalibrált gitárgeometria rövid távú követése két, egymástól
/// FÜGGETLEN jelet mér:
///
///   - **drift** — a tracker javasolt új anchorjai és a manual kalibráció
///     rögzített anchorjai közötti normalizált euklideszi távolság. Ez az
///     SDD §13.4 "gitárgeometria elmozdul a tolerancián túl" triggerének
///     mérőszáma — a R10 öt-értékű `CalibrationInvalidationReason`
///     enumját **nem** bővítjük (R4), hanem ez a küszöbölés a
///     `CalibrationLossMachine` önálló állapotgépében él.
///
///   - **confidence** — a tracker saját megbízhatósági jele, `[0, 1]`
///     zárt tartományban. A mapper-filozófiát követi
///     (`guitar_landmark_mapper.dart`): a kimeneti confidence SOHA nem
///     nőhet — a kalibráció manual, a tracker csak CSÖKKENTHETI a
///     megbízhatóságot, és elveszett geometria alatt a rendszer nem ad
///     gitárspecifikus negatív feedbacket (ADR 0179).
///
/// Mindkét jel normalizált, kamera-térben mért egység — a brief §5.1
/// drift-boundja ehhez a térhez kötött. A küszöbök a fájl tetején
/// konstansként dokumentáltak, és a `python3` számítás a §10 handoffban
/// idézve szolgál.
library;

/// A drift ezen értéke felett a kalibráció `lost` (a frame-ből többé nem
/// követhető biztonságosan).
///
/// Why **0.10** — a normalizált kamera-keret 1.0 széles, és a gitár
/// kézi kalibrációja tipikusan a keret 60–80%-át foglalja el (R10
/// `GuitarCalibration` neck polygon). Egy 10%-os elmozdulás a
/// gitárgeometriát MÁR a keret más felére vitte át, nem "finom remegés".
/// A `recoveryDriftBound` (0.04) a visszatéréshez ennél szigorúbb: a
/// hiszterézis-ablak 0.06 széles, ami kimarja az ingadozást.
const double lostDriftBound = 0.10;

/// A drift ezen értékétől kezdve a rendszer `degraded` (a tracker még
/// tud követni, de a felhasználó már láthatja, hogy a geometria
/// elcsúszott). A `tracking → degraded` átmenet küszöbe.
const double degradedDriftBound = 0.05;

/// A `lost` (vagy `degraded`) állapotból való visszatérés küszöbe.
///
/// Szigorúbb, mint a forward küszöbök (0.04 < 0.05 < 0.10) — ez a
/// hiszterézis-őr, ami megakadályozza, hogy egy drift a határ körül
/// ingadozva villogtassa az állapotot. A §6 acceptance második cellája
/// ezt méri: 17 elemes oszcilláló sequence-re a state-váltások száma
/// `≤ 2` marad.
const double recoveryDriftBound = 0.04;

/// A tracker által szolgáltatott GeometryConfidence küszöbe, ami fölött
/// a geometria forrása `tracked` (és nem `manual`).
///
/// A R10-beli manual anchor a ground truth; a tracker csak akkor írja
/// felül az anchorok bizonyos származtatott következményeit, ha a
/// saját megbízhatósági jele eléri ezt a küszöböt. A küszöb alatt a
/// `CalibrationLossMachine.geometrySource` `manual` marad — ez a
/// „manual anchorokhoz kötött marad" (ADR 0181) gépi megfelelője.
const double trackingConfidenceThreshold = 0.5;

/// One observation's worth of geometry-tracking output.
///
/// Immutable value type. Construction validates inputs so a corrupt
/// tracker can never feed the loss machine a NaN/Infinity drift (brief
/// §5.2 silent-garbage prohibition, `guitar_landmark_mapper` precedent).
final class GeometryConfidence {
  GeometryConfidence({
    required this.confidence,
    required this.drift,
  }) : assert(
         confidence.isFinite && confidence >= 0 && confidence <= 1,
         'GeometryConfidence.confidence must be finite and in [0, 1].',
         ),
       assert(
         drift.isFinite && drift >= 0,
         'GeometryConfidence.drift must be finite and >= 0.',
       );

  /// Tracker-side reliability in `[0, 1]`. Reduced by the loss machine
  /// across frames; never increased (manual anchor is the ground truth,
  /// the tracker can only erode it).
  final double confidence;

  /// Normalized Euclidean distance between the tracker's proposed anchor
  /// and the manual anchor. Compared against [lostDriftBound] to drive
  /// the `tracking → degraded → lost` state machine.
  final double drift;

  /// Whether the tracker's drift exceeds the loss threshold. Above this
  /// bound, the geometry is `lost` and downstream guitar-relative metrics
  /// must suppress output (ADR 0179 capability-aware feedback).
  bool get isLost => drift > lostDriftBound;

  /// Whether the tracker's own confidence reaches
  /// [trackingConfidenceThreshold]. Used by [CalibrationLossMachine] to
  /// attribute `geometrySource` (`manual` vs `tracked`).
  bool get isTracked => confidence >= trackingConfidenceThreshold;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeometryConfidence &&
          other.confidence == confidence &&
          other.drift == drift;

  @override
  int get hashCode => Object.hash(confidence, drift);

  @override
  String toString() =>
      'GeometryConfidence(confidence: ${confidence.toStringAsFixed(3)}, '
      'drift: ${drift.toStringAsFixed(4)})';
}
