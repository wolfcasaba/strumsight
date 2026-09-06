/// A felvételi folyamat seed-dokumentuma (2026-09-05).
///
/// **Miért kell.** Az `AnalysisRunRequest` egy `AnalysisDocument` seed-et kér.
/// Egy MÁR meglévő elemzés újrafuttatásakor ez természetes — a hívónak van
/// dokumentuma. Egy friss felvételnél viszont nincs: a dokumentumot éppen a
/// futás állítja elő. Enélkül a felvételi képernyőknek nem volt mit átadniuk,
/// és ezért maradt a `capture/` hármas bekötetlen.
///
/// **Mit NEM tesz.** Nem talál ki eredményt. A metrikák, a hotspotok, az
/// insightok és az idővonal ÜRESEK, a jelminőség pedig `measured: false` —
/// ez a mező pontosan erre való. Egy kitalált jelminőség-jelentés vagy egy
/// `complete` állapotú, metrika nélküli dokumentum azt állítaná, hogy a
/// futás megtörtént és nem talált semmit; az igazság az, hogy még el sem
/// indult.
///
/// **A futó ma csak a `mode`-ot olvassa ki belőle** (`v2_analysis_runner.dart`
/// `_runFullChain`: `decodedSeed.mode`), a többi mezőt a folyamat maga
/// állítja elő. A seed ettől függetlenül a felvételről szóló IGAZ metaadatot
/// viszi (forrás, hossz, mintavételi frekvencia), nem tölteléket — ha egy
/// későbbi kör több mezőt kezd olvasni, ne kelljen visszamenőleg kitalálni,
/// mi volt igaz.
library;

import '../domain/analysis_capability.dart';
import '../domain/analysis_document.dart';
import '../domain/analysis_hotspot.dart';
import '../domain/analysis_insight.dart';
import '../domain/analysis_metric.dart';
import '../domain/analysis_warning.dart';
import '../domain/analysis_input.dart';
import '../domain/analysis_input_summary.dart';
import '../domain/analysis_mode.dart';
import '../domain/analysis_provenance.dart';
import '../domain/analysis_timeline.dart';
import '../domain/signal_quality_report.dart';

/// A seed-dokumentum azonosítójának előtagja. A futás azonosítója marad a
/// horgony — a keletkező dokumentum `id`-ja ebből származik.
const String captureSeedIdPrefix = 'capture-seed';

/// A még nem mért jelminőség. Minden érték nulla, és a `measured: false`
/// mondja ki, hogy ezek NEM mérési eredmények.
SignalQualityReport unmeasuredSignalQuality() => SignalQualityReport(
  overall: 0,
  peakDbfs: 0,
  rmsDbfs: 0,
  noiseFloorDbfs: 0,
  clippedSampleRatio: 0,
  silentRatio: 0,
  tonalness: 0,
  measured: false,
);

/// Seed-dokumentum egy FRISS felvételhez.
///
/// [runId] a felvétel azonosítója, [audio] a ténylegesen rögzített PCM.
/// A hossz a mintaszámból és a mintavételi frekvenciából SZÁMOLT érték —
/// nem a hívó állítása.
AnalysisDocument captureSeedDocument({
  required String runId,
  required PcmAnalysisInput audio,
  required DateTime createdAt,
  AnalysisMode mode = AnalysisMode.freePlay,
}) {
  final duration = Duration(
    microseconds: audio.sampleRate <= 0
        ? 0
        : (audio.samples.length * Duration.microsecondsPerSecond) ~/
              audio.sampleRate,
  );
  // A lenyomat a futás azonosítójából: a seed még nem ismeri a hang
  // tartalmi ujjlenyomatát (azt a folyamat számolja). Egy kitalált
  // tartalom-hash itt azt sugallná, hogy a hangot már feldolgoztuk.
  final fingerprint = '$captureSeedIdPrefix:$runId';
  return AnalysisDocument(
    id: '$captureSeedIdPrefix-$runId',
    schemaVersion: analysisDocumentSchemaVersion,
    createdAt: createdAt.toUtc(),
    mode: mode,
    input: AnalysisInputSummary(
      source: audio.source,
      duration: duration,
      sampleRate: audio.sampleRate,
      channelCount: audio.channelCount,
      fingerprint: fingerprint,
    ),
    provenance: AnalysisProvenance(
      appVersion: 'capture',
      analyzerVersion: 'pending',
      pipelineVersion: 'pending',
      stageVersions: const <String, String>{},
      // A DSP-konfiguráció a folyamaté; a seed nem ismeri.
      dspConfigHash: 'pending',
      modelManifestIds: const <String>[],
      inputFingerprint: fingerprint,
      platform: 'capture',
      featureFlagSnapshot: const <String, bool>{},
    ),
    signalQuality: unmeasuredSignalQuality(),
    capabilities: const <CapabilityReport>[],
    timeline: AnalysisTimeline(duration: duration),
    metrics: const <AnalysisMetricResult>[],
    hotspots: const <AnalysisHotspot>[],
    insights: const <AnalysisInsight>[],
    warnings: const <AnalysisWarning>[],
    // `degraded`, NEM `complete`: a futás még el sem indult, tehát semmi
    // sem készült el. A `complete` egy metrika nélküli dokumentumon azt
    // állítaná, hogy lefutott és nem talált semmit.
    completion: AnalysisCompletion(status: AnalysisCompletionStatus.degraded),
  );
}
