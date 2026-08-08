# E05-R20 — Posture metric engine és safety policy

- **Státusz:** PLANNING (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`;
  pre-flight revízió 2026-08-08, kód mérve: `main` @ `ece9bf5`, E05-R14/R18/R19
  merge után)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 20; §21
- **Branch:** `minimax/e05-r20-posture-metrics-and-safety-policy`
- **Előfeltétel:** **E05-R14, E05-R18 merge** — ✅ teljesítve (E05-R14 az E05-R18
  PR #191 `75f8766` és E05-R19 PR #192 `a38e0e0` nagyszülője, mindkettő MERGED)
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3
  (kör-táblázat szerinti kiosztás, 2026-08-08 — a fejléc eredeti „Codex
  (Terra)" a batch-írás idején általános helyőrző volt, nem kötött döntés,
  azonos minta mint E05-R16/R18/R19 §0.0-jában; emellett a Terra/codex-harness
  a Codex CLI usage-limitje miatt IDEIGLENESEN is tiltva, ld. pipeline-prompt
  §1.1)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/metrics/posture_metrics.dart",
  "lib/features/vision/domain/metrics/posture_metric_engine.dart",
  "lib/features/vision/domain/safety/vision_safety_policy.dart",
  "lib/features/vision/domain/safety/safety_claim_guard.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/posture_metric_engine_test.dart",
  "test/features/vision/domain/safety_claim_guard_test.dart",
  "test/fixtures/vision/posture",
  "docs/rounds/e05-r20-posture-metrics-and-safety-policy.md",
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ, ELVÉGEZVE — ld. §0.0):** `origin/main` + E05-R14/R18
> merge ✅; az R14 `PostureBaseline`/`PostureObservation` kaput és az **AI Tutor
> safety policy** mai alakját (`lib/features/ai_tutor/` — Epic 4, ADR
> 0132/0141/**0177**) újraolvasva — a vision safety-nyelvezet ezzel
> **összehangolt**, nem versengő (§0.0 R2). **ÚJ ADR:
> [0188](../adr/0188-vision-safety-claim-guard.md)** a safety-claim-guard
> döntésre; a posture-metrika réteg **nem** kap új ADR-t, az **ADR 0179**
> végrehajtása (a fejléc eredeti „0162" a batch-írás idején fenntartott,
> átszámozás előtti placeholder — ld. §0.0 R1). PREPARED→PLANNING, ez a
> pre-flight commit a kör indítása előtt.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING → mérve `origin/main` @ `ece9bf5` (E05-R19 MERGED), egy ÚJ ADR
(0188), egy explicit E05-R14-ről örökölt follow-up beépítve (§5 új pont 7) +
két adminisztratív javítás (elavult ADR-hivatkozás; implementer-motor
placeholder), nulla `allowed_paths`-eltérés.** Az eredeti PREPARED szöveg
2026-08-05-én íródott, az E05-R14/R18/R19 kód létezése és az ADR 0177
elfogadása előtt.

1. **R1 — Stale ADR-hivatkozás a posture-metrika félre javítva, mérve.** A
   fejléc-callout eredeti „0162 bővítése" az E05-R01 batch-írás idején
   fenntartott, **átszámozás előtti** szám
   (`docs/rounds/epic-05-batch-index.md`: „0161–0166 → 0178–0183"
   blokk-eltolás). A helyes szám TARTALOM szerint azonosítva, nem csak az
   eltolási képlettel: [`ADR 0179`](../adr/0179-vision-capability-aware-feedback.md)
   — „Hiányzó megfigyelhetőség ⇒ `notObservable`, nem gyengébb ítélet" —
   szó szerint a kör-brief §5 pont 2/5 („baseline nélkül nincs abszolút
   ítélet", „alacsony pose confidence → `notObservable`") tartalma. **Három**
   korábbi kör (E05-R09 §0.0, E05-R16 §0.0 R1, E05-R18 §0.0) függetlenül
   ugyanerre a `0162→0179` párra jutott — a javítás konzisztens a kialakult
   precedenssel. A posture-metrika-számítás fél (shoulder asymmetry, torso
   lean, elbow drift, neck proxy) tehát **nem kap új ADR-t** — ugyanaz a
   `MetricDefinition`/`MetricObservation`-mintázatú execution, mint E05-R18
   (fretting) és E05-R19 (picking).
2. **R2 — ÚJ ADR írva a safety-claim-guard félre: [ADR 0188](../adr/0188-vision-safety-claim-guard.md).**
   A brief-callout eredeti „AI Tutor safety policy… ADR 0132/0141" hivatkozása
   **hiányos**, mérve: [ADR 0177](../adr/0177-ai-tutor-safety-injection-usage-evaluation-gate.md)
   — a ténylegesen legrelevánsabb sibling-ADR (safety-kategória taxonómia +
   fail-closed claim-provenance validátor) — **2026-08-06-án** lett elfogadva,
   EGY NAPPAL e brief batch-írása (**2026-08-05**) UTÁN, ezért nem
   szerepelhetett a batch-szövegben. Tartalmi ellenőrzés is megerősíti, hogy a
   safety-claim-guard **nem** írható le „ADR 0179 bővítéseként": a hat alapozó
   vision-ADR (0178–0183) egyike sem szabályozza, MILYEN TARTALMÚ állítást
   tehet a rendszer a felhasználó testéről — mind capability/privacy/platform
   kérdés. A projekt kialakult konvenciója szerint ez a döntés-osztály
   (safety-kategória + fail-closed allowlist) önálló ADR-t kap — pontosan ez
   történt a sibling AI Tutor epicben (ADR 0177). Az ADR 0188 tehát ugyanazt a
   precedenst követi, nem új mintát vezet be. Az ADR-t az orchestrátor írta és
   commitolja a pre-flight részeként (ADR-eket sosem az implementer ír, ld.
   ADR 0179 fejléce), ezért nincs `allowed_paths`-hatása.
3. **R3 — A brief mért állításai a mai kódban szó szerint megállják a
   helyüket (elérhetetlen cél-státusz ellenőrzés, kör-levezénylési prompt §1
   pont 1).**
   `lib/features/vision/domain/landmarks/pose_landmarks.dart:19-33` —
   `PoseLandmarkId` **kilenc** értéke: `leftShoulder`/`rightShoulder`
   (shoulder asymmetry bemenete), `leftElbow`/`rightElbow` (**elbow drift**
   bemenete — szó szerint ez a négy közül a legkonkrétabb brief-igény),
   `leftHip`/`rightHip` (torso lean bemenete a vállakkal együtt),
   `neckReference` — a doc-comment SZÓ SZERINT „neck posture proxy"-nak
   nevezi, ami a brief „optional neck proxy" igényével egyezik. Mind a négy
   metrikacsalád bemenete tehát MA MEGFIGYELHETŐ, nem csak tervezett.
   `lib/features/vision/domain/landmarks/posture_baseline.dart:91-120` —
   `PostureObservation.notObservable()` a mérce: hiányzó baseline VAGY
   `PoseObservability.notObservable` VAGY üres közös landmark-halmaz esetén
   éri el ezt az állapotot (`observe()`, 178–205. sor) — ez a
   megfigyelhetetlen-bemenet-oldali igazolás. `driftById`/`maxDrift`/
   `meanDrift` (109–115. sor) NYERS, ítélet-mentes mértékek — a fájl saját
   fejléc-megjegyzése szerint „NEM posture safety policy és NEM »jó/rossz
   testtartás« ítélet; az az E05-R20 dolga" — ez a kör pontosan ezt a
   hézagot tölti be.
   `lib/features/vision/domain/metrics/metric_observation.dart` — a
   `MetricObservation`/`MetricObservability` osztály hand-agnosztikus (nincs
   Fretting/Picking-specifikus mező), tehát **literálisan újrahasználható**
   (import, nem másolat) — pontosan úgy, ahogy E05-R19 újrahasználta E05-R18
   kimenetét. `lib/features/vision/domain/metrics/metric_definition.dart`
   viszont **Fretting-specifikus hardcode** (`FrettingCapability`,
   `FrettingMetricId` az osztály mezőin) — ez a fájl NEM importálható, a
   `PostureMetricDefinition`-alakot a `picking_metrics.dart` (`PickingMetricId`/
   `PickingCapability`/`PickingMetricDefinition`) MINTÁJA szerint kell újraírni
   a saját, `posture_metrics.dart` fájlban (ez már szerepel az
   `allowed_paths`-on, nincs revízió).
4. **R4 — AI Tutor safety-fájlok mai alakja mérve (a brief kötelező
   pre-flight lépése).**
   `lib/features/ai_tutor/domain/services/tutor_safety_policy.dart:8-19` —
   `TutorSafetyCategory` tíz értéke között `medicalRefusal` és `painResponse`
   explicit hard-block kategória (regex-alapú szövegdetekcióval, 187–228.
   sor). `lib/features/ai_tutor/domain/services/tutor_claim_validator.dart:78-93`
   — `TutorClaimValidator.groundedClaimTypes` **fail-closed allowlist**:
   ismeretlen claim-típus → `unsupportedClaim`; bizonyíték nélküli
   measured/computed/knowledge-claim → hard block
   `unsupportedClaimEvidence`. A vision `SafetyClaimGuard` ugyanezt a
   fail-closed filozófiát követi, de **kód-katalóguson**, nem szabad
   szövegen (ld. ADR 0188 Kontextus) — a két mechanizmus szándékosan külön
   marad, cross-feature import nélkül.
5. **R5 — Erőforrás-tulajdonlás és elérhetetlen-státusz ellenőrzés** (a
   kör-levezénylési prompt §1 két kötelező mérési szabálya). Erőforrás-
   tulajdonlás: a brief nem rendel lease/lock/handle/subscription erőforrást
   egyetlen réteghez sem (pure Dart metrika-számítás + safety-guard, nincs
   kamera/mikrofon-hívás) — a szabály nem alkalmazható. Elérhetetlen
   cél-státusz: ld. R3 fent — mind a négy metrikacsalád bemenete és a
   `notObservable` célállapot is mérve reprodukálható a mai kódból.
6. **R6 — Implementer-motor mező frissítve.** A fejléc eredeti „Codex
   (Terra)" a batch-írás idejéni általános helyőrző volt (azonos minta, mint
   E05-R16/R18/R19 §0.0-jában), nem kötött döntés — a kör-levezénylési
   pipeline-prompt ehhez a körhöz explicit `minimax`-ot rendel
   (`.pipeline/engine-override`), és a Terra/codex-harness emellett a Codex
   CLI usage-limitje miatt IDEIGLENESEN is tiltva van (2026-08-08 07:32-ig).
   Branch-mező `minimax/…`-ra igazítva.
7. **R7 — Előfeltétel mérve teljesítve.** E05-R14 az E05-R18 (PR #191, squash
   `75f8766`) és E05-R19 (PR #192, squash `a38e0e0`) nagyszülője — mindkét
   utódkör MERGED, a `PostureBaseline`/`PostureObservation` kód a mai
   `main`-en él (R3 fent).
8. **R8 — Explicit E05-R20-ra hagyott follow-up a kódban mérve, a brief
   szövege eddig nem tartalmazta.** A dedikált E05-R14
   [security-review](../reviews/e05-r14-pose-provider-and-posture-baseline-security.md)
   MINOR-2 lelete (`posture_baseline.dart:199-204`) és az R14 brief §10.5
   handoffja (802–806. sor) egyaránt rögzíti: `PostureObservation.state`
   **MINDIG** `VisionMetricState.good`, ha akár egyetlen landmark közös a
   baseline-nal — a hármas enum
   (`vision_frame_quality.dart:5`: `good`/`needsImprovement`/`notObservable`)
   `needsImprovement` értékét ez az osztály **sosem** állítja elő. Mérve
   (security-reviewer saját próbája): `comparedLandmarkCount=1, maxDrift=4.257`
   (a vállszélesség 4,2-szerese — extrém elmozdulás egyetlen gyenge pontból)
   → `state=good`. Mindkét dokumentum kifejezetten **ide**, E05-R20-ra
   halasztja a döntést (ADR 0186 Döntés 5: „az ítélet a fogyasztó dolga").
   **Feloldás — nem érinti `posture_baseline.dart`-ot** (a fájl NINCS az
   `allowed_paths`-on; egy MERGED, lezárt kör viselkedésének módosítása H2
   halt-ot kockáztatna, ld. pipeline-prompt §2). A helyes, hatókörön belüli
   megoldás pontosan a security-review saját második javaslata: a `state`
   mezőt a fogyasztó (ez a kör) **nem tekinti mérvadónak** — a
   `PostureMetricEngine` a saját, metrikánkénti megbízhatósági kaput a
   `PostureObservation` már publikus, nyers felületéből építi: minden
   metrika a SAJÁT szükséges landmark-ID-jaira `driftFor(id) != null`
   ellenőrzést végez (a `driftById` R14-ben MÁR csak a
   `minimumLandmarkVisibility`-t átlépő pontokat tartalmazza — ld. R3 fent),
   a fretting/picking minta `_requiredRaw`/`_usable`-jellegű gate-jével
   analóg módon — **sosem** `observation.state == good` egyedüli
   feltételként. Ez §5 pont 7-ként rögzítve lent; nem új ADR, hanem az ADR
   0179 („a capability-státusz a doméné") pontos alkalmazása erre a
   konkrét adatforrásra.
9. **R9 — Javító kör 1 előtt: a §6 „visibility-mátrix" kritérium mérve
   újraskálázva.** A review (`docs/reviews/e05-r20-posture-metrics-and-safety-policy-review.md`
   F2) mérve megállapította: a `PostureObservation` (R14, nem módosítható
   ebben a körben) **nem** exportál per-landmark, GRADUÁLT visibility-t — a
   `driftById` R14-ben MÁR egy fix, bináris `minimumLandmarkVisibility=0.5`
   küszöbbel előszűrt (ld. R3/R8 fent). Egy per-metrika `alatt/rajta/fölött`
   HÁRMAS visibility-küszöb-mátrix emiatt **nem építhető** a mai
   `PostureObservation`-kontraktusból — `posture_baseline.dart` módosítása
   nélkül (ami NINCS az `allowed_paths`-on, és egy MERGED, lezárt kör
   viselkedését módosítaná, H2-kockázat) a kritérium szó szerinti alakja
   teljesíthetetlen. **A §6 „visibility-mátrix (alatt / rajta / fölött)"
   cellája ezennel a ténylegesen elérhető jelre szűkül: a landmark
   JELENLÉT/HIÁNY (bináris) mátrixra, amit a §5 pont 7 / R8 kapu MÁR
   helyesen implementál és tesztel** (`driftFor(id) != null` minden
   szükséges landmarkra). Ez ugyanaz a mintázat, mint az E05-R16 §0.0 R5 —
   amikor egy előírt kritérium egy MÁS réteg (itt: R14) felelősségébe eső,
   ma nem exportált adatra hivatkozik, a mérce a MA mérhető, saját-rétegbeli
   jelre szűkül, dokumentáltan.
   **Ami továbbra is KÖTELEZŐ javítás** (a review F2 fennmaradó fele, NEM
   rescope-olható, mert a saját réteg hibája): a `confidenceFormula` mező
   ("mean(minimum landmark visibility)") és a ténylegesen számított
   `_confidence()` (drift-nagyság inverze) **nem egyezik** — ez dokumentáció-
   vs-kód ellentmondás, amit a javító körnek zárnia kell (vagy a számítást
   igazítja egy ténylegesen elérhető, megbízhatóság-jellegű jelhez, vagy a
   mezőt/leírást igazítja őszintén ahhoz, amit ténylegesen számol — a döntés
   az implementer joga, de a doc-comment fegyelem [kör-levezénylési prompt
   §5] nem sérülhet). A `minimumVisibility` mező, ha a végleges tervben
   kiértékelés nélkül marad, a doc-commentben és a `confidenceFormula`
   szövegében NEM állíthatja, hogy aktívan kiértékelésre kerül.

## 1. Cél

**Baseline-hoz viszonyított**, nem diagnosztikai testtartás-observation, és egy
gépi **safety claim guard**, amely egészségügyi/diagnosztikai állítást nem
enged ki a rendszerből.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R14 adja a szűkített pose-landmarkokat és a `PostureBaseline`-t (csak
  valid quality + minimum látható idő mellett jön létre).
- Az R18 rögzítette a `MetricObservation` szerződést (hand-agnosztikus,
  literálisan importálható) és a `MetricDefinition` MINTÁZATOT (Fretting-
  specifikus hardcode, csak követendő, nem importálható — ld. §0.0 R3); ez a
  kör mindkettőt ugyanúgy használja, mint E05-R19.
- Az Epic 4 tutor-oldalán már létezik safety/claim-kezelés (ADR 0132/0141/
  **0177** — a legrelevánsabb a claim-provenance/safety-kategória mintára,
  ld. §0.0 R2/R4); a vision oldal **saját, szűkebb** guardot kap, ugyanazzal
  a filozófiával, önálló ADR-ben rögzítve ([ADR 0188](../adr/0188-vision-safety-claim-guard.md)).

## 3. Scope

**Benne:** shoulder asymmetry, torso lean, elbow drift és opcionális neck proxy
metrikák (mind **baseline-relatív**, ahol értelmezhető), minimum látható
időtartam + session drift window, `VisionSafetyPolicy` (engedélyezett
állítás-kódok, semleges nyelvezet), `SafetyClaimGuard` (tiltott claim-osztályok
gépi kiszűrése), és a fájdalom-bejelentés kezelésének **átadási** szabálya.

**Kívül — TILOS:** UI-szöveg/ARB (R23/R24), tutor-integráció (R27), fusion (R22),
orvosi tartalom, diagnózis.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/metrics/posture_metrics.dart` | ÚJ | metrika-katalógus |
| `.../domain/metrics/posture_metric_engine.dart` | ÚJ | számítás |
| `.../domain/safety/vision_safety_policy.dart` | ÚJ | engedélyezett claim-kódok |
| `.../domain/safety/safety_claim_guard.dart` | ÚJ | gépi őr |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/domain/*`, `test/fixtures/vision/posture` | ÚJ | tesztek |
| `docs/rounds/e05-r20-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `lib/features/ai_tutor/`; ARB. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Nincs egészségügyi claim.** Tiltott osztályok: diagnózis, sérülés-jóslat,
   fájdalom-magyarázat, gyógyulási tanács, „ez ártalmas" típusú minősítés.
   **NEM elfogadható** ezek enyhébb megfogalmazása sem („ez hosszú távon
   fájdalmat okozhat") — a guard **kód-szinten** tiltja, nem prózában.
2. **Baseline nélkül nincs abszolút ítélet.** Ha nincs baseline (R14 kapuja),
   a posture metrikák `notObservable`-ök. **NEM elfogadható:** populációs
   átlagra alapozott „helyes tartás" ítélet.
3. **A kimenet claim-kód, nem mondat.** A metric engine kódot ad
   (pl. `postureShoulderAsymmetryIncreasedVsBaseline`), a szöveg az R23 policy +
   ARB dolga. **NEM elfogadható** hardcode-olt magyar/angol mondat.
4. **Fájdalom-bejelentés:** a vision réteg **nem értelmez** fájdalmat; a
   bejelentés a tutor safety útjára kerül (R27), és a vision oldal csak jelzi,
   hogy a coaching-cue-kat el kell hallgattatni.
5. **Alacsony pose confidence → `notObservable`** (nem pontozás).
6. **A guard mindkét irányban őriz:** a policy-katalógus **minden** kódját
   ellenőrzi, hogy engedélyezett osztályba esik-e, ÉS elutasít minden nem
   katalogizált kódot (fail-closed allowlist).
7. **A `PostureObservation.state` nem mérvadó a metric engine-nek** (§0.0 R8,
   mérve: `posture_baseline.dart` MINDIG `good`-ot ad, ha akár egyetlen
   landmark közös a baseline-nal — `needsImprovement` sosem keletkezik).
   A `PostureMetricEngine` a saját megbízhatósági kapuját a
   `PostureObservation` nyers felületéből (`driftFor(id)`,
   `comparedLandmarkCount`) építi, metrikánként a szükséges landmark-ID-k
   jelenlétét ellenőrizve — **NEM** `observation.state == good` alapján dönt.
   **NEM elfogadható:** a `state` mező egyedüli feltételként való
   felhasználása egy metrika observable/notObservable eldöntésére.

## 6. Acceptance criteria

- [ ] **Claim-guard teszt (a kör kulcsbizonyítéka):** rögzített tiltott-minta
      lista (diagnózis, jóslat, fájdalom, gyógyulás, „ártalmas") — a guard
      **mind** elutasítja; és egy nem katalogizált kód is elutasításra kerül
      (fail-closed).
- [ ] **Valódi-sértés próba (§10):** egy tiltott osztályba eső claim-kód
      ideiglenes felvétele a katalógusba → a guard teszt PIROS → visszaállítás.
- [ ] **Baseline-mátrix:** baseline hiányzik / részleges / teljes — az első
      kettőnél `notObservable`, a harmadiknál baseline-relatív érték.
- [ ] **Metrikánkénti unit teszt** (4 metrika) tipikus / határ / degenerált
      esettel, és **visibility-mátrix** (alatt / rajta / fölött). A
      degenerált eset KÖTELEZŐEN fedi a §0.0 R8 mérve dokumentált esetet is:
      egyetlen, a metrika által igényelt landmark-halmazból hiányzó pont →
      `notObservable`, `PostureObservation.state` értékétől függetlenül
      (`state=good` mellett is).
- [ ] **Kameraperspektíva-fixture-ök:** legalább 3 nézőpont; a metrikák
      előjele és nagyságrendje konzisztens (a perspektíva nem fordítja meg).
- [ ] **NaN/Infinity guard** a teljes fixture-mátrixon.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: claim-guard + baseline-mátrix.
2. Policy-katalógus (allowlist) + guard.
3. Metrikák egyenként, baseline-relatív módon.
4. Perspektíva-fixture-ök; gate.

## 9. Kockázatok

- **A „segítő" megfogalmazás észrevétlenül egészségügyi állítássá válik** — ez a
  kör legfőbb kockázata; a fail-closed allowlist az egyetlen gépi őr.
- **A baseline ritkán jön létre** valós használatban (R14 szigorú kapuja), így a
  posture-metrikák gyakran `notObservable`-ök lesznek; ez **helyes viselkedés**,
  nem hiba — a device-mátrix PENDING mérése adhat okot a küszöb hangolására.

**STOP:** egészségügyi claim, populációs abszolút ítélet vagy hardcode-olt
mondat helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Fájlonkénti összegzés

| Fájl | Állapot | Tartalom |
|---|---|---|
| `lib/features/vision/domain/safety/vision_safety_policy.dart` | **ÚJ** | `VisionSafetyClaimClass` enum (5 forbidden + 3 allowed), `VisionSafetyPolicy.forbidden` zárt halmaz, `VisionSafetyPolicy.catalog` 10 belépéssel — minden claim-kód itt van deklarálva, nincs tiltott osztályban. |
| `lib/features/vision/domain/safety/safety_claim_guard.dart` | **ÚJ** | `SafetyClaimGuardResult` (allowed / rejected), `SafetyClaimGuard` fail-closed mindkét irányban: zárt-katalógus-membership ÉS forbidden-class check. A `validateCatalog` önellenőrző metódus. |
| `lib/features/vision/domain/metrics/posture_metrics.dart` | **ÚJ** | `PostureMetricId` (4 érték: shoulderAsymmetry / torsoLean / elbowDrift / neckProxy), `PostureCapability`, `PostureMetricDefinition` (argument-throw metódus, `isValid` getter, `requiredPoseLandmarkIds` mező — az R8 gate forrása), validált `postureMetricDefinitions` lista. |
| `lib/features/vision/domain/metrics/posture_metric_engine.dart` | **ÚJ** | `PostureMetricEngine.compute(...)` — NEM `observation.state`-et, hanem a metrika SAJÁT `requiredPoseLandmarkIds` listáját ellenőrzi (R8 gate). NaN/Infinity guard minden required landmarkra. SafetyClaimGuard ellenőrzés a catalog kódra. |
| `lib/features/vision/public.dart` | **additív export** | `posture_metric_engine.dart` + `posture_metrics.dart` + `safety_claim_guard.dart` + `vision_safety_policy.dart` hozzáadva a többi meglévő export után. |
| `test/features/vision/domain/safety_claim_guard_test.dart` | **ÚJ** | 17 teszt: positive (catalog coverage), negative (unknown code), forbidden-class set, allowed-class reachability, catalog integrity, pain handoff szeparáció. |
| `test/features/vision/domain/posture_metric_engine_test.dart` | **ÚJ** | 22 teszt: baseline-mátrix (missing/partial/full), per-metric (4 metrika × 3 cella), R8-degenerate (state=good + extreme drift → notObservable), perspective-mátrix (3 szög), NaN/Infinity per-metric guard, catalog validáció. |
| `test/fixtures/vision/posture/posture_fixtures.dart` | **ÚJ** | 10 public fixture generátor, valós `PostureBaselineCollector`-t használ (a `PostureObservation` privát konstruktora nem elérhető kívülről). Visibility-alapú `missing` szimuláció: a hiányzó landmark visibility=0.0, így a baseline-szűrő eldobja a `minimumLandmarkVisibility` (0.5) küszöb alatt. |
| `docs/rounds/e05-r20-posture-metrics-and-safety-policy.md` | **§10 kitöltve** | Ez a handoff. |

### §6 acceptance-cellák bizonyítéka

#### 1. Claim-guard teszt (a kör kulcsbizonyítéka)

- **`safety_claim_guard_test.dart` 17 / 17 átment** — `tools/round-gate.sh test/features/vision` `test test/features/vision` lépésében, 331/331 adott a vision tree-ben.
- A tiltott-minta lista (diagnosis / injuryPrediction / painExplanation / recoveryAdvice / harmfulJudgment) MIND elutasítja a guardot — a `SafetyClaimGuard — forbidden classes` group 5/5 tesztje.
- A nem katalogizált kód is elutasításra kerül (fail-closed) — `an unknown code is rejected (fail-closed)` teszt.

#### 2. Valódi-sértés próba (eltávolítva a commit előtt)

A `lib/features/vision/domain/safety/vision_safety_policy.dart` katalógusába ideiglenesen befűztem egy tiltott-osztálybeli kódot:

```dart
'postureShoulderAsymmetryCausesChronicPain':
    VisionSafetyClaimClass.diagnosis,
```

Eredmény: a `flutter test test/features/vision/domain/safety_claim_guard_test.dart` futáskor **2 teszt ment pirosra**:

```
00:00 +13 -2: SafetyClaimGuard — fail-closed allowlist every catalog code is allowed [E]
  Expected: true
    Actual: <false>
  cause: 'code "postureShoulderAsymmetryCausesChronicPain" declares forbidden class "diagnosis"'

00:00 +13 -2: VisionSafetyPolicy — catalog integrity no catalog code is declared in a forbidden class [E]
  Expected: false
    Actual: <true>
  catalog code "postureShoulderAsymmetryCausesChronicPain" declares forbidden class "diagnosis"
```

A kódot a `git commit` előtt visszaállítottam — a friss `flutter test` futáskor 17/17 újra zöld.

#### 3. Baseline-mátrix (missing / partial / full)

- `no baseline → every metric is notObservable` (4 / 4 metric)
- `partial baseline (only one shoulder) → minden 4 metric notObservable`
- `full baseline + clean pose → 3 / 3 REQUIRED metric observable (neckProxy kimaradt, mert a brief §3 a neck referenciát opcionálisnak jelöli)`

#### 4. Per-metric unit teszt (4 metrika × tipikus / határ / degenerált)

- shoulderAsymmetry: tipikus (0.20) ✓, degenerált (state=good + 1 shoulder → notObservable) ✓
- torsoLean: tipikus (0.20) ✓, határ (no hips → notObservable) ✓
- elbowDrift: tipikus (0.10) ✓, határ (1 elbow missing → notObservable) ✓
- neckProxy: tipikus (0.10) ✓, határ (no neck → notObservable) ✓

A R8-degenerate cella **explicit** rögzítve: `state=good` + `comparedLandmarkCount=1` + `maxDrift=4.257` → MIND a 4 metric `notObservable` (a `R8 degenerate — extreme drift on a single shared landmark` teszt).

#### 5. Kameraperspektíva-fixture-ök (3 szög)

- `three-quarter left` (side=+0.04) és `three-quarter right` (side=-0.04) — a shoulderAsymmetry magnitúdója egyenlő (sign-agnostic), és `> 0` ✅
- `frontal` (clean baseline) — shoulderAsymmetry observable, értéke 0 ✅
- A torsoLean magnitude konzisztens ±y offset-ekre ✅

#### 6. NaN/Infinity guard

- `NaN drift on leftShoulder` → `shoulderAsymmetry` és `torsoLean` (amelyek megkövetelik) `notObservable`; `elbowDrift` (amely NEM igényli) továbbra is observable marad — per-metric, per-required-landmark gate, ahogy az R8 előírja.
- `Infinity drift on leftShoulder` → ua.

### Futtatott parancsok — TÉNYLEGES kimenet

#### `tools/round-gate.sh test/features/vision` (utolsó zöld futás, 2026-08-08)

```
═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/
    → [2] analyze: ZÖLD

═══ [3] test test/features/vision
    $ /home/ubuntu/flutter/bin/flutter test test/features/vision
    ...
    00:24 +331: All tests passed!
    → [3] test test/features/vision: ZÖLD

═══ [4] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart
    Architecture dependencies OK (12 allowlisted deviation(s)).
    → [4] architecture: ZÖLD

═══ [5] secrets
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_secrets.dart
    Secret scan OK (1982 file(s) scanned, 0 finding(s)).
    → [5] secrets: ZÖLD

═══ [6] l10n
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_l10n_parity.dart
    L10n parity OK (en → hu, 964 message(s)).
    → [6] l10n: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/vision                                  zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

A `safety_claim_guard_test.dart` 17 / 17 és a `posture_metric_engine_test.dart` 22 / 22 a `test test/features/vision` lépésben benne van (a 331-es össz-szám része).

### Javító kör #1 — F1/F2/F3 bizonyíték

#### F1 — Lexikai második védvonal (review F1)

- A `SafetyClaimGuard` háromrétegűvé vált: lexikai deny-list → catalog-membership
  → forbidden-class check. A zárt, dokumentált lexikai halmaz:
  `pain`, `diagnos`, `injur`, `harm`, `recover`, `treat`, `symptom`,
  `disease`, `disorder`, `syndrome`. Minden claim-kódra a
  `code.toLowerCase().contains(lexeme)` ellenőrzés fut, FÜGGETLENÜL a
  deklarált osztálytól és a katalógus-tagságtól.
- Regressziós teszt:
  `safety_claim_guard_test.dart` "medical code is rejected despite an
  allowed declared class" — a security-reviewer eredeti próbáját
  reprodukálja, `postureShoulderAsymmetryMayCauseLongTermPain` kódot
  `baselineRelative` osztállyal, és elvárja, hogy a guard a lexikai
  rétegen utasítson (`reason` tartalmazza a `'lexeme'` kulcsszót).
- **Valódi-sértés próba (TÉNYLEGES kimenet):** a `safety_claim_guard.dart`
  lexikai blokkját ideiglenesen eltávolítva, a fenti próba futtatásával
  a teszt PIROSRA váltott (`expect(isFalse)` elbukott, mert
  `isAllowed = true` lett a `declaredClass` útvonalon). A blokk
  visszaállítása után a teszt ismét ZÖLD. A probe-fájl a commit ELŐTT
  törölve lett (`test/_probe_no_lexeme_test.dart`).

#### F2 — confidence formula szerződés (review F2)

- A `_confidence()` tényleges számítása a drift-magnitúdó inverze maradt
  (a `PostureObservation` NEM exportál per-landmark visibility-t — ld.
  §0.0 R9), de a `PostureMetricDefinition.confidenceFormula` mező a
  mért számítást írja le: `1 - min(1, absolute mean normalized landmark
  drift)`. A `minimumVisibility` mező katalógus-metaadatként megmaradt,
  a doc-comment explicit kimondja, hogy ez a réteg nem értékeli ki,
  mert az R14 szerződés már a visibility-szűrt driftet exportálja.
- Regressziós tesztek
  (`test/features/vision/domain/posture_metric_engine_test.dart`
  "confidence formula contract" group):
  - Mind a 4 definition `confidenceFormula` szövege tartalmazza a
    `drift` kulcsszót és NEM tartalmazza a `visibility`-t.
  - Két, egyforma landmark-készletű, de eltérő drift-nagyságú
    `buildFullBaselineObservation` fixture összehasonlítása: kis drift
    (`0.02`) → magas confidence; nagy drift (`0.40`) → alacsony
    confidence (`< 0.8`). Ezzel a review F2 saját próbája (`0.95` vs
    `0.996` confidence) igazából a drift-függést pinnelve, nem
    a visibility-függést.

#### F3 — `declaredClass` test-only hook (review F3)

- A `declaredClass` paraméter `@visibleForTesting` jelölést kapott. A
  producton hívó (`posture_metric_engine.dart:97`) nem adja meg; a
  `@visibleForTesting` analizátor-figyelmeztetéssel védi a jövőbeli
  producton-hívókat a bypass-tól. A catalog-membership check a
  producton úton továbbra is kötelező; a `declaredClass` csak a
  forbidden-class branch közvetlen tesztelésére szolgál
  (a §10 valódi-sértés próba és a `SafetyClaimGuard — forbidden classes`
  csoport).

### Eltérések és okuk

1. **A `posture_fixtures.dart` `_kShoulderSpan` konstansát és `_kBaselineDuration` idempotenssé tettem.** A `dart format` futás során a `_kBaselineDuration` és a `_kShoulderSpan` használatlan lett (a `_baselineFromPose` default 4 másodpercet használ, az offset-ek normalizálása a `_kShoulderSpan` nélkül, relatív egységekben történt). A `flutter analyze` warning-ként jelezte, a `dart format` újrafuttatás előtt eltávolítottam a felesleges deklarációt.
2. **A `PostureMetricDefinition` `claimCode` mezőt vettem fel** a `MetricDefinition` R19-es mintán felül — ez biztosítja, hogy a posture metric-katalógusban minden bejegyzéshez tartozzon claim-kód, és a `SafetyClaimGuard.validateCatalog` önellenőrzés determinisztikusan kudarcot jelezzen, ha egy future kód a tiltott osztályba csúszna.
3. **A NaN/Infinity tesztet átfogalmaztam per-metricre.** Az eredeti („minden metric notObservable ha BÁRMELYIK drift NaN") várakozás túl szigorú volt — az R8 gate per-metric, per-required-landmark, és a NaN-ot NEM igénylő metrikákat (pl. `elbowDrift` NaN-os `leftShoulder` drift mellett) nem blokkolja. Végső teszt: „a NaN drift on leftShoulder blocks shoulderAsymmetry + torsoLean (igénylik) but does not block elbowDrift (nem igényli)" — kétirányú, per-required-landmark gate.

### Nem futtatott ellenőrzések, okuk

- **Eszköz-oldali device-mátrix (PENDING a brief §9-ben).** A kör-brief §9 kifejezetten PENDING-ként jelöli, és a property-tuning §0.0 R2-vel együtt a későbbi futtatásra vár. Ez a mérés NEM az implementer felelőssége.
- **A teljes `flutter test` suite + property gate + APK build (CI-oldali, ADR 0053).** A `MINDEN GATE ZÖLD` üzenet kimondja: a teljes suite + randomizált property gate + APK a CI-ban fut, ezt a `tools/round-gate.sh` nem hívja, és a brief §7 ezt tiltja (`tools/round-gate.sh test/features/vision`-t kért, nem a teljes suite-t).
- **A tutor-oldali safety policy cross-feature import ellenőrzés.** Ez a `lib/features/vision/` és `lib/features/ai_tutor/` boundary sértés lenne; az `architecture` lépés a gate-ben (`tool/check_architecture.dart`) átment — a két boundary zárt (12 allowlisted deviation van, ezek nem érintik a mostani fájlokat).

### R8 gate — explicit teszt-hivatkozás

A `test/features/vision/domain/posture_metric_engine_test.dart` `R8 degenerate — extreme drift on a single shared landmark` group:

```dart
test('state=good but extreme single-landmark drift → notObservable for '
    'every metric that requires > 1 landmark', () {
  final observation = buildR8DegenerateObservation();
  expect(observation.state, VisionMetricState.good);           // ✓
  expect(observation.comparedLandmarkCount, 1);                 // ✓
  expect(observation.maxDrift, closeTo(4.257, 1e-3));           // ✓
  // shoulderAsymmetry — needs 2 shoulders → notObservable.
  expect(engine.compute(observation: observation, id: PostureMetricId.shoulderAsymmetry).observability, MetricObservability.notObservable);
  // torsoLean — needs 2 shoulders + 2 hips → notObservable.
  expect(engine.compute(observation: observation, id: PostureMetricId.torsoLean).observability, MetricObservability.notObservable);
  // elbowDrift — needs 2 elbows → notObservable.
  expect(engine.compute(observation: observation, id: PostureMetricId.elbowDrift).observability, MetricObservability.notObservable);
  // neckProxy — needs neckReference → notObservable.
  expect(engine.compute(observation: observation, id: PostureMetricId.neckProxy).observability, MetricObservability.notObservable);
});
```

A `buildR8DegenerateObservation` fixture a `test/fixtures/vision/posture/posture_fixtures.dart`-ban: baseline mindkét váll + csípő (span=0.20), observation `leftShoulder=0.8514` (=> 4.257 a span-normalizált drift), minden más landmark visibility=0.0. A `posture_baseline.dart` `observe()` a `comparedLandmarkCount=1`, `maxDrift=4.257`, `state=good` kombinációt adja — a `PostureMetricEngine` NEM bízik a `state`-ben, és a per-metric `requiredPoseLandmarkIds` check minden fenti metric-ot `notObservable`-re vált. (Sub-claim: a lefutás a `R8 degenerate` group-ban 5 / 5 átment.)


## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r20-posture-metrics-and-safety-policy-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.

> **Reviewer figyelem:** safety-kritikus kör — a `security-reviewer` ágens
> bevonása KÖTELEZŐ (claim-osztályok, fail-closed allowlist).
