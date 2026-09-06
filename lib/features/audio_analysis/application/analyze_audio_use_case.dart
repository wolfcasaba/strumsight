import '../domain/analysis_document.dart';
import '../domain/analysis_input.dart';
import 'analysis_isolate_runner.dart';

/// Starts an injected V2 document pipeline. The composition root owns the
/// stage list; this use case deliberately has no DSP policy of its own.
///
/// **2026-09-05 — a placeholder megszűnt.** A [call] korábban CSAK a
/// seed-dokumentumot kapta, és a hangot maga gyártotta le:
/// `samples: const <double>[]`. A saját docstringje mondta ki, hogy „a future
/// round that plumbs real capture audio into the controller replaces this
/// placeholder with the caller's actual PCM" — addig viszont a felvételi
/// folyamat bekötése CSENDET elemzett volna, és eredményt mutatott volna rá.
///
/// Az [audio] ezért KÖTELEZŐ, nem opcionális alapértékkel. Egy elhagyható
/// paraméter visszahozná ugyanazt a hibát: egy jövőbeli hívó némán üres
/// hangot elemezne, és a fordító nem szólna érte.
final class AnalyzeAudioUseCase {
  const AnalyzeAudioUseCase(this._runner);

  final AnalysisRunner _runner;

  /// Elindít egy elemzést a [seed] dokumentum-vázzal és a VALÓDI [audio]
  /// mintákkal.
  AnalysisRunHandle call(
    AnalysisDocument seed, {
    required ValidatedPcmAnalysisInput audio,
  }) => _runner.start(AnalysisRunRequest(seed: seed, audio: audio));
}
