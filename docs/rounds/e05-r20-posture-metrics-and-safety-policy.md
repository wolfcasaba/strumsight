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
(0188) + két javítás (elavult ADR-hivatkozás; implementer-motor placeholder),
nulla scope-eltérés.** Az eredeti PREPARED szöveg 2026-08-05-én íródott, az
E05-R14/R18/R19 kód létezése és az ADR 0177 elfogadása előtt.

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
      esettel, és **visibility-mátrix** (alatt / rajta / fölött).
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

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r20-posture-metrics-and-safety-policy-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.

> **Reviewer figyelem:** safety-kritikus kör — a `security-reviewer` ágens
> bevonása KÖTELEZŐ (claim-osztályok, fail-closed allowlist).
