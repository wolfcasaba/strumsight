# ADR 0194 — Tutor and Analysis vision evidence adapters (minimization and claim-guard contract)

- **Státusz:** Elfogadva (E05-R27 pre-flight, 2026-08-08)
- **Kör:** E05-R27 — AI Tutor és Analysis evidence adapterek
- **Implementer motor:** Terra (Codex CLI, `~/.codex-terra`, `gpt-5.6-terra`,
  `tools/codex-round.sh`) — az ADR-t az orchesztrátor (Claude Sonnet 5) írta a
  pre-flightban (ADR 0055, pipeline-prompt §0 — nincs előre kiosztott ADR).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) Kör 27; §27
- **Kontext-ADR-ek:** [0141](0141-ai-tutor-prompt-output-schema-injection-boundary.md)
  (a Tutor redakciós/prompt-építési határa, amin ez a kör NEM léphet át),
  [0176](0176-cross-feature-public-barrel-recognition.md) (nested
  `public.dart` barrel elismerése — ugyanaz a mechanizmus, mint 0192/0193),
  [0188](0188-vision-safety-claim-guard.md) (a MEGLÉVŐ, tartalom-osztály-
  alapú `SafetyClaimGuard` — más tengely, ld. Kontextus 6. pont),
  [0189](0189-vision-audio-sync-contract.md) (`ClockMapping`/
  `SessionTimestamp` — a közös session-idő forrása),
  [0190](0190-vision-observation-fusion-and-evidence.md)
  (`VisionEvidence`/`ObservationState` — ez a kör ERRE épül, nem új
  vocabulary), [0192](0192-practice-vision-integration-contract.md) /
  [0193](0193-song-trainer-vision-integration-contract.md) (a két testvér-kör,
  ugyanaz a narrow-barrel minta).

## Kontextus

A kör-brief (2026-08-05, batch-írás) fejléce „Nincs ÚJ ADR (0161/0162 + 0141
bővítése)"-t írt elő. A pipeline-prompt §0 táblája ugyanakkor explicit
`nincs`-et adott át ADR-ként, „te írod meg a pre-flightban" kitétellel. A
pre-flight (pipeline-prompt §1, két kötelező mérési szabály) minden
hivatkozott ADR-számot, útvonalat és típust kigrepelt a feltételezés helyett:

1. **„ADR 0161" és „ADR 0162" nem létező fájlok.** `ls docs/adr | grep -E
   '^01(61|62)'` → 0 találat; `find docs/adr -iname '*0161*' -o -iname
   '*0162*'` → 0 találat. Ez ugyanaz a mért mintázat, mint a korábbi négy
   eset (0170→0189 E05-R21, „0162"→0190 E05-R22, „ADR 0165"→0182 E05-R25/R26):
   a 2026-08-05-i batch-brief-írás egy jövőbeli ADR-számra hivatkozott, amely
   a köztes körök (R21–R26, kilenc ADR: 0185–0193) miatt a végrehajtás
   időpontjára nem realizálódott az eredeti helyén. Nincs mit „bővíteni" — a
   döntéseket ITT, ÚJ ADR-ként kell rögzíteni.
2. **A `TutorVisionContextAdapter` fájlútvonala nem létező könyvtárra
   mutatott.** A brief `lib/features/ai_tutor/data/context/
   tutor_vision_context_adapter.dart`-ot írt elő; `lib/features/ai_tutor/
   data/context/` nem létezik. Mind a nyolc MEGLÉVŐ tutor-oldali
   context-adapter (`analyze_context_adapter.dart`,
   `practice_context_adapter.dart`, `song_trainer_context_adapter.dart`,
   `progress_context_adapter.dart`, `streak_context_adapter.dart`,
   `settings_context_adapter.dart` + a két „_result_" változat) egységesen
   `lib/features/ai_tutor/application/context/adapters/` alatt él, ugyanazt a
   `TutorContextField? adapt(...)` mintát követve. A tesztjeik tükörként
   `test/features/ai_tutor/application/context/adapters/<név>_test.dart`
   alatt élnek.
3. **`VisionContextSnapshot`-nak nem volt saját teszt-útvonala.** A brief
   három tesztfájlt sorolt fel, de az AC #1 („a kör kulcsbizonyítéka")
   kifejezetten a `VisionContextSnapshot` pinnelt kulcshalmazáról szól,
   aminek nem volt dedikált fájlja.
4. **A `VisionClaimGuard` tesztje rossz könyvtárban.** A brief
   `test/features/vision/domain/vision_claim_guard_test.dart`-ot (lapos) írt
   elő, míg a forrás `lib/features/vision/domain/integration/
   vision_claim_guard.dart` (beágyazott `integration/` alatt) — a könyvtár
   már ma is tükrözve van a tesztfában
   (`test/features/vision/domain/integration/
   vision_integration_barrel_boundary_test.dart`, E05-R26), tehát az egyezés
   a bevett minta, nem új precedens.
5. **A brief a WIDE `lib/features/vision/public.dart`-ot sorolta fel
   exportcélként**, miközben a HANDOFF.md §3 KÉTSZER explicit előírta
   (R25/R26 pre-flightjai előtt) hogy minden ÚJ cross-feature
   vision-fogyasztó a SZŰK, nested barrelt
   (`lib/features/vision/domain/integration/public.dart`, ADR 0176/0193
   mintája) használja — pontosan azért, mert a wide barrel nyers
   landmark/geometry/provider típusokat is exportál, szimbólum-szintű korlát
   nélkül (`tool/check_architecture.dart` csak fájlnév-mintát néz). Mivel a
   két új fájl (`vision_context_snapshot.dart`, `vision_claim_guard.dart`)
   pont ugyanabba a `domain/integration/` könyvtárba kerül, mint a meglévő
   `vision_practice_contract.dart`/`vision_song_contract.dart`, a helyes
   exportpont a MEGLÉVŐ szűk barrel — nem a wide.
6. **A „VisionClaimGuard" névhasonlósága a MEGLÉVŐ `SafetyClaimGuard`-dal**
   (`lib/features/vision/domain/safety/safety_claim_guard.dart`, E05-R20,
   ADR 0188) félreértésre adhat okot, de a két őr ORTOGONÁLIS: a
   `SafetyClaimGuard` azt dönti el, MELYIK TARTALOM-OSZTÁLYBA tartozó állítás
   engedhető meg egyáltalán (orvosi/diagnosztikai határ — fail-closed
   allowlist claim-kódra), a brief ÚJ `VisionClaimGuard`-ja pedig azt, hogy
   egy adott állításhoz VAN-E ELÉG BIZONYÍTÉK (confidence-küszöb × evidence
   jelenléte — fail-closed). A kettő EGYÜTT él, nem összevonandó.
7. **A brief absztrakt „aggregátum + insight-kód + confidence +
   observability" mezőlistája NEM új vokabulárium — a kód már tartalmazza
   mind a négyet, korábbi körökből:**
   - `VisionEvidence` (`lib/features/vision/domain/evidence/
     vision_evidence.dart`, E05-R22/ADR 0190): `confidence: double [0,1]`,
     `observationState: ObservationState {observed, inferred, notObservable,
     experimental}`.
   - `InsightCode`/`VisionInsight`
     (`lib/features/vision/domain/feedback/insight_code.dart`, E05-R23):
     zárt, 11-értékű kódkatalógus + `VisionInsight{code, policyVersion,
     evidenceIds, confidence, priority, direction}`.
   - `FeedbackPolicy`/`FeedbackPolicies`
     (`lib/features/vision/domain/feedback/feedback_policy.dart`):
     confidence-küszöb-alapú, fail-closed katalógus-lookup
     (`positiveConfidenceThreshold`/`negativeConfidenceThreshold`) — ugyanaz
     az ALAK, mint amit a brief a `VisionClaimGuard`-tól elvár, csak a
     real-time cue rendszerre alkalmazva.
   A `VisionContextSnapshot` mezőit tehát ezekre kell építeni (insight-kód =
   `InsightCode`, confidence = `VisionInsight.confidence`/
   `VisionEvidence.confidence`, observability = `ObservationState`), és
   KIFEJEZETTEN kizárva a `VisionEvidence.value` (a nyers metrika-double) —
   az adatminimalizálás a látszólag ártalmatlan számot is kizárja, csak a
   levezetett/minősítő mező marad.
8. **A „közös session-idő" (brief §5 pont 5) konkrét típusa
   `SessionTimestamp`** (`lib/features/vision/domain/sync/vision_clock.dart`,
   E05-R21/ADR 0189) — egyszerű, monotonic mikroszekundum-wrapper, amit a
   `ClockMapping`/`CalibrationSample` már ma is használ. Az Analysis-oldali
   adapter ezt használja a közös idő reprezentációjára wall-clock `DateTime`
   helyett — a teljes kalibrációs/drift-apparátus (`ClockMapping`)
   újrafelhasználása NEM kötelező ebben a körben (az egy ÉLŐ, egyidejű
   audio+vision mérési probléma megoldása; az Analysis egy RÖGZÍTETT klip
   utólagos vision-hivatkozása, egyszerűbb probléma), de a típus és a „sosem
   `DateTime`" elv igen.
9. **Az SDD Kör 27 saját feladatlistája**
   (`docs/sdd/06-epic-05-computer-vision.md` „Kör 27 → Feladatok") egy
   nyolcadik tételt tartalmaz, ami a brief scope-jából (§3/§4) teljesen
   hiányzik: „Frissítsd a Chapter 5/7 integrációs dokumentációt." A „Chapter
   5" = `docs/sdd/05-epic-04-ai-guitar-teacher.md` (Epic 4, AI Tutor),
   „Chapter 7" = `docs/sdd/07-epic-06-audio-analysis-2.md` (Epic 6, Audio
   Analysis) — az index (`00-index.md`) függőségi képe explicit jelöli:
   „Chapter 6 Computer Vision └──▶ Chapter 5 / 7 evidence integration". Ez a
   kör zárja ezt a függőségi élt — a dokumentáció-frissítés a kör MUNKÁJÁNAK
   bizonyítéka, nem mellékes adminisztráció.

## Döntés

1. **ADR-szám: 0194.** A brief minden `0161`/`0162`/„bővítés" hivatkozása ide
   mutat; a fejléc §0.0 revízióval jelzi az eltérést.
2. **`VisionContextSnapshot`**
   (`lib/features/vision/domain/integration/vision_context_snapshot.dart`,
   ÚJ) mezői KIZÁRÓLAG: insight-kód (`InsightCode`, meglévő), confidence
   (`double [0,1]`), observability (`ObservationState`, meglévő), és a brief
   §6 szerinti minimális azonosító/idő-metaadat (session-idő,
   `SessionTimestamp`). **NEM tartalmazhat:** `VisionEvidence.value`,
   semmilyen `landmarks`/`geometry`/kép-URI típust, semmilyen debug mezőt —
   még flag mögött sem. A szerializált kulcshalmaz egy pinnelt konstans lista
   ellen tesztelt (brief AC #1).
3. **`VisionClaimGuard`**
   (`lib/features/vision/domain/integration/vision_claim_guard.dart`, ÚJ) egy
   önálló, a `FeedbackPolicy`-val AZONOS ALAKÚ (de attól független
   katalógusú/küszöbű) fail-closed kapu: bemenet egy opcionális
   evidence-hivatkozás (jelenlét) + confidence, kimenet engedélyezett-állítás
   VAGY a determinisztikus `notObservable` fallback-kód (ugyanaz a névalak,
   mint az `ObservationState.notObservable`/a meglévő
   `visionInsightSetupNotObservable` biztonsági kódkonvenció). Ortogonális a
   MEGLÉVŐ `SafetyClaimGuard`-hoz (Kontextus 6. pont) — nem összevonandó, nem
   helyettesíti.
4. **Cross-modal `inferred` provenance a meglévő `ObservationState.inferred`
   értéket használja újra** — nincs új háromállapotú/négyállapotú enum
   bevezetve csak erre a célra.
5. **A Tutor-oldali adapter kimenete valódi `TutorContextField`, a meglévő
   redaktált úton keresztül — ehhez `lib/features/ai_tutor/application/
   context/tutor_context_snapshot.dart` KIZÁRÓLAG additív bővítést kap:** egy
   `vision` érték a `TutorContextFieldKey` enumhoz, egy `vision` érték a
   `ContextSourceFeature` enumhoz. Semmilyen más sor nem változik ebben a
   fájlban. Mérve biztonságos: a két enumon kívül nincs kimerítő
   (exhaustive) `switch` rájuk a `context_purpose.dart`-on (ami
   `ContextPurpose`-ra exhaustive, nem erre a kettőre) és a
   `context_budget.dart` kézzel karbantartott (nem exhaustive)
   `truncationPriority` listáján kívül — egyik fájl sem törik el egy új
   enum-értéktől, és egyik sem esik ebbe a körbe (a `context_purpose.dart`
   egyetlen `ContextPurpose` sem engedélyezi még az új mezőt, tehát a
   `TutorContextAssembler` élesben ma is mindig kihagyja — production
   viselkedés bitre változatlan, a korábbi vision-integrációs körök „hívó
   még nincs" mintáját követve).
6. **Fájlútvonal-javítások** (Kontextus 2/3/4. pont): a forrás
   `tutor_vision_context_adapter.dart` a `lib/features/ai_tutor/
   application/context/adapters/` alá kerül (nem `data/context/`); a
   `vision_claim_guard_test.dart` a
   `test/features/vision/domain/integration/` alá (nem lapos `domain/`); a
   `tutor_vision_context_adapter_test.dart` a `test/features/ai_tutor/
   application/context/adapters/` alá; ÚJ
   `test/features/vision/domain/integration/vision_context_snapshot_test.dart`
   a hiányzó kulcsbizonyíték-teszthez.
7. **Exportpont a szűk, nested barrel**
   (`lib/features/vision/domain/integration/public.dart`, MEGLÉVŐ, ADR
   0176/0193 mintája) — a wide `lib/features/vision/public.dart` NEM
   változik ebben a körben (Kontextus 5. pont).
8. **Analysis↔Vision közös idő: `SessionTimestamp`**
   (`lib/features/vision/domain/sync/vision_clock.dart`, MEGLÉVŐ)
   újrahasznosítva az `analysis_vision_reference.dart` session-idő
   mezőjéhez; wall-clock `DateTime` az adapteren belül nem fordulhat elő
   (Kontextus 8. pont).
9. **SDD Chapter 5/7 dokumentáció-frissítés a scope RÉSZE** (Kontextus 9.
   pont) — két kis, additív, célzott beszúrás:
   `docs/sdd/05-epic-04-ai-guitar-teacher.md` (az Epic 4 lezáró szakasza elé,
   rövid bekezdés) és `docs/sdd/07-epic-06-audio-analysis-2.md` (a „##
   Insight és integráció" DoD-checklist alá, egy sor). Mindkettő az
   `allowed_paths`-hoz adva.

## Következmények

- `lib/features/vision/domain/integration/vision_context_snapshot.dart`,
  `vision_claim_guard.dart` — új, minimalizált evidence-kontraktus a meglévő
  `VisionEvidence`/`InsightCode` fölött.
- `lib/features/vision/domain/integration/public.dart` — additív export (2 új
  sor), a wide barrel változatlan.
- `lib/features/ai_tutor/application/context/adapters/
  tutor_vision_context_adapter.dart` — új, a meglévő nyolc testvér-adapter
  mintáját követi.
- `lib/features/ai_tutor/application/context/tutor_context_snapshot.dart` —
  additív enum-bővítés (2 érték), semmi más.
- `lib/features/analyze/model/analysis_vision_reference.dart`,
  `lib/features/analyze/providers/analysis_vision_adapter.dart` — új,
  `SessionTimestamp`-alapú hivatkozás.
- `docs/sdd/05-epic-04-ai-guitar-teacher.md`,
  `docs/sdd/07-epic-06-audio-analysis-2.md` — kis, additív integrációs
  jegyzet.
- Négy teszt fájl (egy új: `vision_context_snapshot_test.dart`; három
  javított útvonalú).
- Production viselkedés bitre változatlan: mindkét feature flag
  (`visionTutorIntegrationEnabled`, `visionAnalysisIntegrationEnabled`)
  marad `false`, nincs élő hívó.

## Elutasított alternatívák

- **`tutor_vision_context_adapter.dart` saját, `TutorContextField`-től
  független kimeneti típussal, a `tutor_context_snapshot.dart` érintetlenül
  hagyva.** Elvetve: a brief saját §5 pont 4 döntése explicit megköveteli,
  hogy a beillesztés „ugyanazon a redaktált úton" történjen — egy
  párhuzamos, a redaktoron kívüli típus strukturálisan pont azt a bypasst
  tenné lehetővé, amit a döntés tilt, és egy kockázat=high, kötelező
  security-review-t kapó körnél ez valószínű BLOCKER/MAJOR lelet lenne. A
  választott additív enum-bővítés nulla production-hatású, és a jövőbeli
  valódi bekötés természetes bővítési pontot kap.
- **A `SafetyClaimGuard` kiterjesztése a `VisionClaimGuard` funkcióval, egy
  közös osztályba.** Elvetve: más tengely (tartalom-osztály vs.
  bizonyíték-elégségesség), más bemenet (claim-kód vs. confidence+evidence),
  más réteg-felelősség; összevonás visszamenőleg módosítaná egy LEZÁRT kör
  (E05-R20) viselkedését (H2 kockázat) egy olyan körben, aminek ez nem
  scope-ja.
- **A `ClockMapping`/kalibráció teljes apparátusának újrafelhasználása az
  Analysis-adapterben.** Elvetve: az élő, egyidejű audio+vision
  latency-mérés problémája (E05-R21) más, mint egy RÖGZÍTETT klip utólagos,
  egyetlen session-belüli időreferenciája; a `SessionTimestamp` típus (a
  mechanizmus KÖZÖS RÉSZE) elég a „nem wall clock" garanciához, a
  drift/kalibráció overkill.
- **A SDD Chapter 5/7 dokumentáció-frissítés kihagyása, mert „csak
  dokumentáció".** Elvetve: az SDD-kör saját, explicit feladatsora
  tartalmazza; kihagyása egy follow-up kört generálna egy tisztán
  adminisztratív, alacsony kockázatú tétel miatt.
