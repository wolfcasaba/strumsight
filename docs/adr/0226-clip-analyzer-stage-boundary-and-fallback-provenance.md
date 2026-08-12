# ADR 0226 — ClipAnalyzer stage-adapter határ és fallback-provenance mérési szerződés

- **Státusz:** Elfogadva (E06-R09 pre-flight, 2026-08-12)
- **Kör:** E06-R09 — V1 ClipAnalyzer stage adapter és parity
- **Implementer motor:** Terra (`gpt-5.6-terra`), `.pipeline/engine-override=terra` szerint.
- **Kapcsolódó szerződések:** SDD Ch7 §8.4/§10.1, ADR 0176 (`public.dart` határ,
  allowlist csak szűkülhet), az E06-R04 `AnalysisStage<I, O>` szerződés,
  `lib/features/analyze/engine/clip_analyzer.dart` (241 sor, változatlan
  marad), `lib/features/analyze/providers/analyze_providers.dart::
  runClipAnalysis`.

## Kontextus

A brief OD-01 nyitott döntése szerint, ha a `ClipAnalyzer` OSZTÁLY nem
exportált a `lib/features/analyze/public.dart`-on át, a stage a kizárólag
exportált `runClipAnalysis((pcm, sr, weights, labMode, chordWeights))`
szinkron belépőt hívja. Pre-flight méréssel (2026-08-12, `main@71b158b`)
megerősítve: a barrel az `AnalyzeResult`-ot, a providereket (köztük
`runClipAnalysis`/`computeClipAnalysis`-t), a `timeline_view`-t és az
`ml_chord_decoder`-t exportálja — a `ClipAnalyzer` osztály és a `StrumRefiner`
typedef NEM. A kör tilos zónája (`lib/features/analyze/**`) kizárja mind a
közvetlen importot, mind a barrel bővítését — az OD-01 alapértelmezés tehát az
EGYETLEN járható út, nem csupán preferencia.

Ez az út viszont egy MÉRT résre fut: a `runClipAnalysis` visszatérési típusa
csupasz `AnalyzeResult`, nincs oldalcsatorna arra, hogy egy nem-null
`weights` bájtsorozatot a belső `StrumCrnn` ténylegesen felhasznált-e, vagy a
`ClipAnalyzer._refine` saját, változatlan `catch (_)`-ja (`clip_analyzer.dart`
88–111. sor) csendben visszaesett-e a heurisztikus címkékre. A brief §6
„Fallback-provenance” kritériuma három, egymástól megkülönböztetett cellát
vár (`crnn` / `heuristic`+`fallbackReason` / `none`) — ez a `runClipAnalysis`
csupasz visszatérési értékéből ÖNMAGÁBAN nem olvasható ki. A brief §5.5
("ha a strum refiner null volt VAGY kivételt dobott... `heuristic`") és a §6
hármas partíciója (`null` → `none`, dobás → `heuristic`) emellett EGYMÁSNAK
ELLENTMOND — ez a pre-flight második mért lelete.

## Döntés

1. **A hívási határ megerősítve.** A `ClipAnalyzerStage` (és a mögötte hívott
   kód) KIZÁRÓLAG a `lib/features/analyze/public.dart` által exportált
   `runClipAnalysis` belépőt hívja. `ClipAnalyzer` közvetlen konstruálása, a
   `clip_analyzer.dart` közvetlen importja `lib/` alól, vagy a barrel
   bővítése ebben a körben egyaránt tilos (§3 tilos zóna).
2. **`strumRefinerSource` KETTŐS híváson alapuló összevetéssel dől el,**
   amikor a stage-nek van (nem null) jelölt CRNN-súly bájtsorozata:
   - `weights == null` → EGYETLEN hívás, `strumRefinerSource = none` (nincs
     második hívás, triviálisan ismert a bemenetből).
   - `weights != null` → KÉT hívás ugyanazzal a pcm/sampleRate bemenettel,
     `labMode = false`, `chordWeights = null` mindkétszer: egy a jelölt
     súlyokkal (`candidate`), egy kényszerített `null` súllyal (`baseline`).
     Ha a `candidate.strums` MINDEN eleme (irány ÉS confidence) megegyezik a
     `baseline.strums` megfelelő elemével → `strumRefinerSource = heuristic`
     + egy rögzített, névvel ellátott `fallbackReason` (a súly parse- vagy
     classify-hibája a visszatérési értékből nem különböztethető meg — ez
     KIMONDOTT, elfogadott mérési korlát, nem hiba). Ha legalább egy elem
     eltér → `strumRefinerSource = crnn`.
   - **Precedens a kódbázisban, nem új technika:**
     `test/features/analyze/clip_analyzer_ml_test.dart` 78–98. sora már ma is
     kettős `runClipAnalysis`-hívást vet össze (`refined` vs. `baseline`),
     136–146. sora pedig szemét (`Uint8List(16)`) súlyokkal igazolja a
     csendes fallbacket. Az implementer EZT a mintát kövesse.
   - A `labMode`/`chordWeights` pozíció mindkét hívásban `false`/`null`
     marad ebben a körben (OD-02: a Lab/ML-chord ág az E06-R11 dolga).
3. **§5.5 és §6 ellentmondása feloldva a §6 hármas partíciója javára** (ez a
   gépileg mért, acceptance-szintű forrás): `null` → `none`; nem-null, de
   parse- vagy classify-hibás → `heuristic` + `fallbackReason`; nem-null és
   ténylegesen eltérő kimenetet ad → `crnn`. §5.5 szövege ennek megfelelően
   pontosítandó a brief §0.0 revíziójában.
4. **A paritás-mátrix „dobó refiner” cellájának V1-referenciája** a TESZT
   fájlban közvetlenül `ClipAnalyzer(strumRefiner: (pcm, sr, onsets) =>
   throw ...)`-tal épül fel — a teszt-import NEM esik a
   `tool/check_architecture.dart` hatálya alá (a szkenner kizárólag a `lib/`
   fát járja be, mérve: `tool/check_architecture.dart:133`,
   `Directory('${projectRoot.absolute.path}/lib')`), és ez már a meglévő
   `test/features/analyze/clip_analyzer_ml_test.dart:65-69` mintája. A V2
   oldal ugyanerre a fixture-re szemét (nem-null, parse-olhatatlan) súly-
   bájtokkal hívja a stage-et; a `ClipAnalyzer` saját, V1-ben változatlan
   catch-all-ja mindkét oldalon ugyanarra a heurisztikus kimenetre fut, a
   paritás ezen a cellán így triviálisan teljesül.
5. **`test/tooling/` alá egy új fájl kerül az allowed_paths-ba** — a brief
   eredetileg kihagyta, holott a §6 „Architektúra” pont kifejezetten egy
   `test/tooling` alatti gépi őrt vár az „allowlist ≤ 12 bejegyzés”
   invariánsra. A meglévő `test/core/architecture_dependency_test.dart`
   (szintén nincs az allowed_paths-on, és NEM ebben a körben módosul)
   konzisztenciát mér (nincs váratlan/elavult bejegyzés), de LÉTSZÁMOT nem
   pinnel — ez a hiányzó mérce.

## Elutasított alternatívák

- **`ClipAnalyzer` osztály közvetlen importja vagy a barrel bővítése az
  osztály exportjával:** mindkettő a kör tilos zónáját (`lib/features/
  analyze/**`) érintené — H3, nem önállóan feloldható ebben a körben.
- **A stage saját CRNN-parse/validációt futtat** (`CrnnStrumNet.parse`
  közvetlen hívása): új `audio_analysis → live/engine/ml` allowlist-
  bejegyzést igényelne — az allowlist ebben a körben KIZÁRÓLAG szűkülhet
  (ADR 0176), bővítés tilos.
- **`strumRefinerSource` mindig optimista** (`weights != null` ⇒ `crnn`):
  hamis pozitívot adna a szemét-bájt/dobó fixture-ön — közvetlenül ütközne a
  §6 „Fallback-provenance” három, egymástól megkülönböztetett cellájával.
- **Fake/injektált `runClipAnalysis`-helyettesítő a stage saját tesztjében:**
  csak azt igazolná, hogy a stage helyesen címkéz egy KITALÁLT kimenetet, nem
  azt, hogy a VALÓDI `runClipAnalysis` felől helyesen következtet — a kettős-
  hívásos technikát kiegészítheti, nem helyettesítheti.

## Visszavonási feltétel

Ha egy KÉSŐBBI kör (pl. a Lab-ág bekötése, E06-R11) a `ClipAnalyzer` osztályt
vagy egy gazdagabb, oldalcsatornás visszatérési típust (pl.
`(AnalyzeResult, StrumRefinerOutcome)`) tesz exportálttá az
`analyze/public.dart`-on át, a kettős-hívásos következtetés LECSERÉLHETŐ egy
közvetlen, bizonyított jelzésre — ADR-frissítéssel, nem néma cserével.

## Következmények

- Az E06-R09 stage-je 100%-ban az exportált felületen marad; a `ClipAnalyzer`/
  CRNN belső kódjának egyetlen sora sem módosul vagy másolódik.
- A `strumRefinerSource = heuristic` cella egy INFERÁLT (nem közvetlenül
  bizonyított) jelzés — az elméleti hamis-negatív eset (egy sikeresen lefutó
  CRNN véletlenül byte-azonos irány+confidence sorozatot ad, mint a
  heurisztika) gyakorlatilag kizárt a `StrumCrnn.calibrate` ismert,
  lépcsőzetes kalibrációs görbéje (0.62/0.64/0.73/0.83/0.96 csomópontok)
  miatt, amely a heurisztika saját confidence-képletétől eltérő
  értékkészletet ad.
- A `test/tooling/` alá kerülő új fájl a `gate_tests` listával (amely már
  eddig is tartalmazta a `test/tooling`-ot) mostantól konzisztens — csak az
  `allowed_paths` hiányzott.
