# E05-R16 — Guitar geometry tracking és calibration loss

- **Státusz:** PLANNING (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`;
  pre-flight revízió 2026-08-07, kód mérve: `main` @ `a3ca8e7`, E05-R10/R15
  merge után)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 16; §17.1, §13.4
- **Branch:** `minimax/e05-r16-geometry-tracking-and-calibration-loss`
- **Előfeltétel:** **E05-R10, E05-R15 merge** — ✅ teljesítve (E05-R10 PR #181
  `39d1c29`, E05-R15 PR #187 `a351ad3`, mindkettő MERGED)
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3
  (kör-táblázat szerinti kiosztás, 2026-08-07 — a fejléc eredeti „Codex
  (Terra)" a batch-írás idején általános helyőrző volt, nem kötött döntés;
  emellett a Terra/codex-harness a Codex CLI usage-limitje miatt
  IDEIGLENESEN is tiltva van ehhez a körhöz)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/geometry/geometry_tracker.dart",
  "lib/features/vision/domain/geometry/geometry_confidence.dart",
  "lib/features/vision/application/calibration_loss_machine.dart",
  "lib/features/vision/data/guitar/edge_geometry_tracker.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/geometry_tracker_test.dart",
  "test/features/vision/application/calibration_loss_machine_test.dart",
  "test/fixtures/vision/geometry",
  "docs/rounds/e05-r16-geometry-tracking-and-calibration-loss.md",
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ, ELVÉGEZVE — ld. §0.0):** `origin/main` + E05-R10/R15
> merge ✅; az R10 öt `CalibrationInvalidationReason` értékét és az R15
> `guitarSpaceSanityBound`/`homographyMaxConditionNumber` párját újraolvasva —
> mindkét állítás mérve megerősítve. **Nincs ÚJ ADR** (ADR 0181 bővítése — a
> fejléc eredeti „0164" elavult szám, ld. §0.0 R1). PREPARED→PLANNING, ez a
> pre-flight commit a kör indítása előtt.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING → mérve `origin/main` @ `a3ca8e7` (E05-R15 MERGED), két javítás
(elavult ADR-hivatkozás; implementer-motor placeholder), nulla
scope-eltérés.** Az eredeti PREPARED szöveg 2026-08-05-én íródott, az
E05-R10/R15 kód létezése előtt.

1. **R1 — Stale ADR-hivatkozás javítva.** A fejléc „(0164 bővítése)" és az §5
   pont 2 „(ADR 0162)" mindkettő az E05-R01 batch-írás idején fenntartott,
   **átszámozás előtti** szám (`docs/rounds/epic-05-batch-index.md`:
   „0161–0166 → 0178–0183" blokk-eltolás — az Epic 4 hátralévő körei a
   tervezett 0161–0170 tartomány fölé futottak, ld. E05-R01 §0.0). A helyes
   számok TARTALOM szerint azonosítva, nem csak az eltolási képlettel:
   [`ADR 0181`](../adr/0181-vision-manual-calibration-fallback.md) — „A
   gitárgeometria production útja a kézi kalibráció… az automatikus
   detektor sosem váltja ki, csak felajánlja" — pontosan ez a kör bővíti
   (a tracker a manual anchorokhoz kötött, kötött drift-bounddal, §5 pont
   1); [`ADR 0179`](../adr/0179-vision-capability-aware-feedback.md) —
   „Hiányzó megfigyelhetőség ⇒ `notObservable`, nem gyengébb ítélet" — szó
   szerint az §5 pont 2 „notObservable + Recalibrate cue" tartalma. Két
   korábbi kör (E05-R10 §0.0 R1, E05-R11 §0.0 R1) függetlenül ugyanerre a
   `0164→0181` / `0162→0179` párra jutott — a javítás konzisztens a
   kialakult precedenssel. **Nincs ÚJ ADR** — mindkét hivatkozott ADR már
   elfogadott (E05-R01, 2026-08-06), ez a kör azok bővítése, nem új döntés.
2. **R2 — Implementer-motor mező frissítve.** A fejléc eredeti „Codex
   (Terra)" a batch-írás idejéni általános helyőrző volt (azonos minta,
   mint E05-R15 §0.0-jában), nem kötött döntés — a kör-levezénylési
   pipeline-prompt ehhez a körhöz explicit `minimax`-ot rendel
   (`.pipeline/engine-override`), és a Terra/codex-harness emellett a Codex
   CLI usage-limitje miatt IDEIGLENESEN is tiltva van (2026-08-08 07:32-ig).
   Branch-mező `minimax/…`-ra igazítva.
3. **R3 — Előfeltétel mérve teljesítve.** E05-R10 MERGED (PR #181, squash
   `39d1c29`) és E05-R15 MERGED (PR #187, squash `a351ad3` — a jelenlegi
   HEAD nagyszülője: `git log --oneline -3` → `a3ca8e7`/`417482d`/`a351ad3`)
   — mindkettő a brief előfeltétele, teljesítve.
4. **R4 — A brief mért állításai a mai kódban szó szerint megállják a
   helyüket.** `lib/features/vision/domain/calibration/
   calibration_validity.dart:18-39` — `CalibrationInvalidationReason`
   **öt** értéke (`cameraDeviceChanged`, `orientationChanged`,
   `zoomChangedBeyondTolerance`, `timestampExpired`, `degenerateGeometry`),
   a fájl saját fejléc-megjegyzésével: „a hiányzó kettő ma nem mérhető
   (tracking confidence → **R16**…)" — ez a kör a saját maga által előre
   jelzett hézagot tölti be, de **külön, önálló állapotgépként**
   (`CalibrationLossMachine`), NEM a meglévő ötértékű enum bővítéseként — a
   fájl nincs az allowed_paths-on, ez tudatos rétegválasztás, nem hiány.
   `lib/features/vision/domain/geometry/guitar_landmark_mapper.dart:73` —
   `guitarSpaceSanityBound = 10.0`, és `core/geometry/homography.dart:37` —
   `homographyMaxConditionNumber = 1e3` — mindkettő létezik, dokumentált; a
   §9 kockázat-listában és a fenti pre-flight callout-ban idézett „R15
   kondíció-küszöb" pontosan ez a kettő.
   `lib/features/vision/domain/calibration/guitar_calibration.dart:29-49` —
   `nutAnchor`/`bridgeAnchor`/`neckPolygon`, mind normalizált `[0,1]×[0,1]`
   térben — ez a §5 pont 1 „manual anchorok" tényleges tárolási helye, amihez
   a drift-boundot mérni kell.
5. **R5 — Az §6 „summary tartalmazza…" cella hatóköre pontosítva, kialakult
   precedens szerint.** `grep -rln "VisionSessionResult\|SessionSummary" lib/
   test/` **nulla találat** — az SDD §9.8 `VisionSessionResult` (a „session
   summary") MÉG NINCS megépítve egyetlen korábbi kör által sem, és nincs az
   allowed_paths-on. Kialakult precedens ugyanerre (E05-R15 §0.0 R3, azonos
   mintázat, mint a fenti R4 öt-vs-hét invalidation reason esete): amikor az
   SDD egy még nem létező, más kör felelősségébe tartozó típusra hivatkozik,
   a mérce a MA mérhető, saját-rétegbeli jelre szűkül, dokumentáltan. Az
   acceptance-cella tehát a `CalibrationLossMachine` SAJÁT kimenetére/
   state-jére vonatkozik (`geometrySource` + mért max-drift mint a machine
   saját, exportált mezői) — egy KÉSŐBBI kör (R22, „Vision observation
   fusion és evidence engine") fordítja majd ténylegesen a
   `VisionSessionResult` mezőire. **Nincs allowed_paths-bővítés.**
6. **R6 — Erőforrás-tulajdonlás és elérhetetlen-státusz ellenőrzés** (a
   kör-levezénylési prompt §1 két kötelező mérési szabálya). Erőforrás-
   tulajdonlás: a brief nem rendel lease/lock/handle/subscription
   erőforrást egyetlen réteghez sem (pure Dart állapotgép + geometria,
   nincs kamera/mikrofon-hívás) — a szabály nem alkalmazható. Elérhetetlen
   cél-státusz: ez egy MEGLÉVŐ reducer/átmenettáblára vonatkozó ellenőrzés;
   a `CalibrationLossMachine` ebben a körben ÚJ, zöldmezős állapotgép —
   nincs korábbi kód, aminek az átmenettábláját a tényleges bemenetekkel
   szemben kellene ellenőrizni. Az acceptance-kritériumok (§6 drift-mátrix +
   hiszterézis-teszt, a cellák a §10-ben python3-mal számolva) MAGUK a
   tervezési szerződés, amit az implementer épít fel — nem egy meglévő
   táblázat, amit auditálni kell.

## 1. Cél

A kézzel kalibrált gitárgeometria **rövid távú** követése, és elmozdulás esetén
**biztonságos érvénytelenítés**: negatív technikai feedback helyett Recalibrate
kérés.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R10 adja a mentett kalibrációt + az invalidation reason listát; az R15 a
  homográfiát és a kondíciószámot; az R11 a Recalibrate műveletet a UI-ban.
- **Nincs** tracking: ma egy kameramozdulás után a geometria csendben rossz
  lenne — ezt a kör zárja le.

## 3. Scope

**Benne:** `GeometryTracker` interfész + könnyű, él-/feature-alapú adapter,
frame-to-frame `GeometryConfidence`, **drift-bound** (a manual anchorokhoz
képest), `CalibrationLossMachine` (tracking → degraded → lost állapotgép),
a geometry-source és a drift rögzítése a session summaryhoz, fixture-szcenáriók
(camera bump, gitár elmozdulás, lassú sodródás).

**Kívül — TILOS:** automatikus gitárdetektor modell (R17), UI (a cue az R24),
metrikák, fusion, model-asset.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/geometry/geometry_tracker.dart` | ÚJ | tracker contract |
| `.../domain/geometry/geometry_confidence.dart` | ÚJ | confidence + drift |
| `.../application/calibration_loss_machine.dart` | ÚJ | állapotgép |
| `.../data/guitar/edge_geometry_tracker.dart` | ÚJ | könnyű adapter |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/*`, `test/fixtures/vision/geometry` | ÚJ | fixture + állapotgép tesztek |
| `docs/rounds/e05-r16-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; ML model-asset; `docs/rag`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A tracker nem írhatja felül korlátlanul a manual anchorokat.** A megengedett
   eltérés **kötött drift-bound** (normalizált egységben, konstans a fájl
   tetején); azon túl a geometria **lost**, nem „követett". **NEM elfogadható:**
   folyamatosan újrahangolt anchor bound nélkül („majd követi"), mert az
   észrevétlen sodródáshoz vezet.
2. **Elveszett geometria alatt nincs gitárspecifikus negatív feedback**
   (ADR 0179). A kimenet `notObservable` + Recalibrate cue. **NEM elfogadható:**
   „alacsony confidence-szel, de adjunk tanácsot".
3. **Az állapotgép hiszterézises:** a `tracking → degraded → lost` átmenetnek
   **más** küszöbe van, mint a visszatérésnek — így nem villog. Mindkét küszöb
   számmal dokumentált.
4. **A geometry-source (manual / tracked) és a mért drift a session summary
   része** — a későbbi evidence provenance-e ebből él (R22).
5. **A tracker adapter cserélhető**; a domain csak a contractot ismeri
   (a R17 esetleges detektora ide illeszkedne, flag mögött).

## 6. Acceptance criteria

- [ ] **Drift-mátrix:** elmozdulás a drift-bound **alatt / pontosan rajta /
      fölött** — az első kettő `tracking`/`degraded`, a harmadik `lost`.
      A cellák értékét `python3 -c` számolja (a §10-ben idézve).
- [ ] **Hiszterézis-teszt:** a `lost`-ból való visszatérés **szigorúbb**
      küszöbhöz kötött; egy oda-vissza ingadozó fixture-en az állapot
      **nem villog** (állapotváltások száma ≤ dokumentált korlát).
- [ ] **Szcenárió-fixture-ök:** (a) kis kamera-bump → követhető; (b) nagy
      elmozdulás → Recalibrate; (c) lassú, kumulatív sodródás → a bound elérésekor
      `lost` (nem „örökké követ").
- [ ] **Feedback-tiltás teszt:** `lost` állapotban a gitárrelatív metrikák
      kimenete `notObservable`, és a negatív insight-út **nem hívódik**
      (hívásszámláló 0).
- [ ] **Valódi-sértés próba (§10):** a drift-bound eltávolítása → a (c)
      szcenárió PIROS → visszaállítás.
- [ ] A summary tartalmazza a geometry-source-t és a maximális driftet.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. A valós eszközös „mozdítsd meg a
kamerát" próba a device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. Fixture-szcenáriók + RED drift/hiszterézis mátrix.
2. `GeometryConfidence` + drift-bound.
3. Tracker contract + könnyű adapter.
4. Állapotgép + summary mezők; gate.

## 9. Kockázatok

- **Az észrevétlen sodródás** a legveszélyesebb kimenet: a felhasználó rossz
  geometrián kapna „technikai" tanácsot. A kumulatív fixture ezt méri.
- **A villogó állapot** rossz UX-et ad (folyton Recalibrate) — a hiszterézis
  küszöbét a valós eszközös mérés (PENDING) hangolhatja, de a bound nem tűnhet el.

**STOP:** detektor-modell behúzása, bound nélküli anchor-frissítés vagy a
feedback-tiltás lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r16-geometry-tracking-and-calibration-loss-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
