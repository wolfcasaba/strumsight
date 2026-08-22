# ADR 0392 — Analysis/Vision/Tutor/Practice-Generator gamification adapterek: kizárólag caller-fed jel, ai_tutor-import nulla, a mért Vision-integrációs boundary

- **Státusz:** elfogadva (E08-R26 pre-flight)
- **Dátum:** 2026-08-22
- **Kör:** `E08-R26` — Analysis, Vision, Tutor és Practice Generator integráció
- **Kapcsolódó:** [`0390`](0390-practice-and-learn-gamification-adapter-boundary.md),
  [`0391`](0391-song-gamification-adapter-standalone-bonus-and-hashed-song-id.md),
  [`0388`](0388-mastery-milestone-multi-session-evidence-and-explainable-badge.md),
  [`0289`](0289-mastery-is-evidence-not-xp.md)

## Kontextus

A kör-brief (2026-08-18-i írás, „ADR: nincs — ez a kör nem hoz kötött
architekturális döntést") négy pontban tett olyan hallgatólagos feltevést,
amit a pre-flight méréssel megcáfolt vagy pontosított:

**1. `ai_tutor/public.dart` NEM üres feltételezésből indult ki, valójában
szándékosan és VÉGLEGESEN üres.** Mérve: a fájl tartalma két sor
(`library;` + doc-comment), és egy MERGE-ELT, dedikált guard
(`test/features/ai_tutor/ai_tutor_boundary_test.dart`, E04-R01) kipinneli,
hogy `lib/features/ai_tutor/public.dart` **nem tartalmazhat** import/export
direktívát. Ez nem hiányosság, hanem lezárt architekturális döntés (L139,
`docs/LESSONS.md`) — az `ai_tutor` feature-nek ma nincs semmilyen elérhető
domain-típusa cross-feature fogyasztók számára. Megerősítő precedens: a
`practice_generator` már ma is dokumentáltan NULLA importtal dolgozik
(`lib/features/practice_generator/data/adapter/tutor_plan_proposal_adapter.dart`
fejléce: „The frozen `ai_tutor` public boundary exports no reachable domain
type, so this adapter never imports that feature” — saját, hívó-fed
`TutorPlanOutline` típust definiál helyette).

**2. `lib/features/analyze/model/analyze_result.dart` (`AnalyzeResult`) NEM
hordoz forrás-hash vagy elemző-verzió mezőt.** Mérve: a teljes fájlban
(`class AnalyzeResult` és a beágyazott `TimelineChord`/`TimelineStrum`/
`MlChordDiagnostics` típusok) nincs `sourceHash`/`analyzerVersion`/
`clipHash` jellegű mező. A `lib/features/audio_analysis/` (V2, ADR 0220 —
`audioAnalysisV2Enabled` minden környezetben `false`, tehát NEM éles út) MÁR
hordoz ilyet (`AnalysisCacheKey.inputFingerprint`/`.analyzerVersion`,
`AudioFingerprint.compute`), de ez egy másik, ma nem élő feature-höz
tartozik — a brief cél-mappája (`lib/features/analyze/`) helyes (ez az éles
út, `app_router.dart` erre routol), csak a hash/verzió mezők hiányoznak
róla.

**3. A brief `minVisionConfidence` névvel hivatkozott küszöb szó szerint nem
létezik ilyen néven a kódban, és a hozzá tartozó guard NEM a
`vision/public.dart` (top-level) boundaryn keresztül érhető el.** Mérve:
`lib/features/vision/domain/integration/vision_claim_guard.dart`
(`VisionClaimGuard._minimumConfidence = 0.70`) csak a
`lib/features/vision/domain/integration/public.dart` (egy MÁSIK, szűkebb,
kifejezetten cross-feature-fogyasztóknak szánt public barrel — saját
fejléce: „Domain-safe Vision contracts available to feature integrations…
Cross-feature consumers must depend on aggregate evidence only”) exportján
keresztül érhető el; a top-level `lib/features/vision/public.dart` ezt NEM
exportálja újra. A `masteryEvidenceConfidenceThreshold = 0.70`
(`lib/features/gamification/application/mastery_evaluator.dart`) egy
FÜGGETLEN, saját konstans, ami kommentben hivatkozza a
`VisionClaimGuard`-ot (ADR 0388 §3) — a két érték ma egyezik (0.70), de nem
ugyanaz a Dart-szimbólum.

**4. A brief §5.3 „terv-befejezés" előírása egy MA EL NEM ÉRHETŐ
állapotátmenetre hivatkozik.** Mérve: `grep -rn "PlanStatus\." lib/features/
practice_generator/` — a `PlanStatus.completed` enum-érték LÉTEZIK, de
SEHOL nem kerül beállításra (`draft`→`active`→`paused` élek mértek, a
`completed`/`archived`/`superseded`/`cancelled` élekhez tartozó kódút
nincs). Ezzel szemben a blokk/nap-szintű `PracticeItemStatus.completed`
(más típus, más hatókör) MÁR ma is reachable és beállításra kerül — ez az az
út, amin keresztül a brief §5.3 premisze („a blokkok már jutalmazódtak a
saját forrásukon, gyakorlás/dal") ténylegesen igaz, mert egy blokk
végrehajtása a `practice`/`songs` feature-ön át fut (mérve:
`plan_execution_coordinator.dart` a `practice.PracticeSessionConfig`-ot
indítja), tehát a MEGLÉVŐ `gamification_practice_adapter.dart`/
`gamification_song_adapter.dart` már jutalmazza. A plan-SZINTŰ (egész terv)
befejezés-esemény forrása tehát ma nem egy domain-átmenet, hanem csak a
hívó fél (jövőbeli UI-kör) tudása arról, hogy „ez volt az utolsó blokk".

## Döntés

1. **`gamification_tutor_adapter.dart` az `ai_tutor` csomagból ZÉRÓ
   szimbólumot importál — véglegesen, nem csak ebben a körben.** A tutor
   adapter kizárólag a `gamification/public.dart`-ot importálja, és saját,
   hívó-fed jel-típust definiál (a `practice_generator`
   `TutorPlanOutline`-jával azonos mintán) minden olyan bemenethez, amire a
   §5.1 logikának szüksége van (pl. hogy egy adott végrehajtott gyakorlás a
   tutor egy konkrét javaslatából ered-e). A beszélgetés önmagában (§5.1)
   emiatt strukturálisan sem juthat XP-hez: az adapternek nincs
   `TutorConversation`/`TutorTurn` bemenete, mert ilyet nem tud importálni —
   a NULLA-import maga a garancia, nem csak egy futásidejű `if`.
2. **`gamification_analysis_adapter.dart` saját, hívó-fed jel-típusán
   (`AnalysisGamificationSignal` vagy hasonló) `sourceHash`/`analyzerVersion`
   mezőt visz — a hívó (nem ez a kör; egy jövőbeli Library/Analyze-képernyő
   kör) tölti ki, az `AnalyzeResult` maga nem bővül.** A dedup (§5.4, A4/A5)
   ezen a két hívó-fed mezőn dolgozik, ugyanúgy, ahogy a
   `SongGamificationSignal`/`PracticeGamificationSignal` is tisztán
   hívó-fed adatot hordoz (ADR 0390/0391 mintája) — nem az `analyze/`
   belsejéből olvas ki semmit, tehát az A6 (csak public szerződés) sérülés
   nélkül teljesül akkor is, ha a mezők forrása (a hash számítása) egy másik
   feature-ben dől el.
3. **`gamification_vision_adapter.dart` a `lib/features/vision/domain/
   integration/public.dart` barrelen át importál** (nem a top-level
   `vision/public.dart`-on, ami a `VisionClaimGuard`-ot nem exportálja
   újra) — ez a SZŰKEBB, kifejezetten cross-feature-fogyasztóknak szánt
   boundary, és tartalmazza a §5.2 minőségi kapuhoz szükséges
   `VisionClaimGuard`/`_minimumConfidence` egyenértékű, mért 0.70 küszöböt.
   Az A6 architektúra-guard mindkét `public.dart` importot elfogadott
   boundary-ként kezeli a `vision/` gyökér alatt (a `domain/integration/
   public.dart` MAGA is egy `public.dart` nevű barrel, tehát a meglévő
   „csak `public.dart` importálható" ellenőrzési minta — lásd
   `_forbiddenGamificationInternalImports`, E08-R24 — természetes
   kiterjesztéssel, útvonal-prefix nélkül, jelöli megfelelőnek).
4. **`gamification_plan_adapter.dart` NEM a `PlanStatus.completed`
   átmenetre reagál (az ma nem reachable, és a hozzá tartozó kódutak —
   `active_plan_controller.dart`, `generation_orchestrator.dart` — a
   tilos zónában vannak).** Az adapter saját, hívó-fed jelet fogad (pl.
   `planCompleted: bool` + a már kifizetett blokk-azonosítók halmaza), a
   `SongGamificationSignal.fullSongCompleted`/session-bookkeeping mintáját
   követve (ADR 0391 2. döntés): a hívó (egy jövőbeli, ezen a körön KÍVÜLI
   UI-kör) dönti el, mikor „fejeződött be" a terv, az adapter csak a
   bónusz-méretezést és a duplázás-tiltást (§5.3, A3) végzi a kapott jelen.
   Ez a kör tehát a plan-befejezés UI-wiringját NEM végzi el (nincs is az
   `allowed_paths`-on) — csak a tiszta adapter-logikát, tesztelve
   szintetikus (nem éles) `planCompleted` jelekkel.

## Következmények

- A brief §2/§5/§8 implementáció-szintű hivatkozásai (a négy mappanév
  ellenőrzése, `minVisionConfidence` névhasználat) a fenti mért nevekre/
  útvonalakra frissülnek (§0.0 brief-revízió, ugyanebben a pre-flightban) —
  az A1–A8 acceptance kritériumok külső, megfigyelhető viselkedésként
  változatlanok maradnak.
- Egy jövőbeli kör, amely a négy adaptert ténylegesen bekapcsolja a hívó
  UI-kódba (Analyze/Library screen a hash+verzióhoz, Vision session screen a
  confidence-hez, egy jövőbeli plan-befejezés UI a `planCompleted`
  jelhez), ennek az ADR-nek a caller-fed szerződését örökli — nem nyithatja
  újra, hogy „az adapter olvassa ki saját magának" a hash/verzió/plan-státusz
  értékeket a forrás feature belsejéből.
- Ha az `ai_tutor` public boundary valaha bővül (a pinned E04-R01 guard
  megváltoztatásával, ami ezen a körön kívül eső döntés), a tutor adapter
  NULLA-import garanciája automatikusan erősebb feltevéssé válik — ekkor egy
  külön kör dönthet arról, kíván-e élni az új felülettel; ez a döntés itt
  NEM előlegeződik meg.

## Elutasított alternatívák

- **`gamification_tutor_adapter.dart` az `ai_tutor` domain-modelljeiből
  (pl. `TutorConversation`, `TutorTurn`) importálna, hogy „lássa" a
  beszélgetést és explicit módon nullázza az XP-t:** a pinned E04-R01 guard
  ezt egyből pirosra vinné (`ai_tutor_boundary_test.dart`), és a tilos zóna
  (`ai_tutor`en belüli bármely más fájl) miatt a guard módosítása sem opció
  — elutasítva a nulla-import garancia javára.
- **`AnalyzeResult` bővítése `sourceHash`/`analyzerVersion` mezővel ebben a
  körben:** a `lib/features/analyze/model/analyze_result.dart` NINCS az
  `allowed_paths`-on (csak az `application/gamification_analysis_adapter.dart`
  van), a bővítés tilos zóna-sértés lenne — elutasítva a hívó-fed jel-típus
  javára.
- **A `vision/public.dart` (top-level) bővítése a `VisionClaimGuard`
  újra-exportjával, hogy egyetlen importútvonal legyen:** a `vision/
  public.dart` NINCS az `allowed_paths`-on — elutasítva; a már létező,
  kifejezetten cross-feature célra írt `domain/integration/public.dart`
  boundary használata mind pontosabb, mind kevesebb fájlt érint.
- **A `gamification_plan_adapter.dart` az `active_plan_controller.dart`/
  `PlanStatus.completed`-ből olvasná ki a befejezést, előbb egy transition
  hozzáadásával:** mindkét fájl tilos zóna, és egy plan-státusz-átmenet
  hozzáadása kötött architekturális döntés lenne magának a
  `practice_generator` domainnek — elutasítva a hívó-fed jel javára, ami az
  adaptert a forrás feature belső állapotgépétől függetleníti.

## Mérce

Az E08-R26 brief §6/§6.1 cellái (A1–A8): a beszélgetés-only cella (A1)
`gamification_tutor_adapter.dart`-nak `ai_tutor`-import NÉLKÜL kell
pirosra vinnie egy megpróbált „elköteleződési XP"-t (a §6.1 valódi-sértés
próba); a Vision bizalmi mátrix (A2) a `domain/integration/public.dart`-on
át importált küszöbbel dolgozik; a dedup (A4/A5) a hívó-fed
`sourceHash`/`analyzerVersion` mezőkön; a terv-bónusz (A3) a hívó-fed
`planCompleted` jelen; az A6 architektúra-guard (`architecture_dependency_test.dart`)
mind a négy adapterre kiterjesztve ellenőrzi, hogy csak a fenti,
mért `public.dart` barrelek importálhatók.
