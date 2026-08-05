# E05-R16 — Guitar geometry tracking és calibration loss

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 16; §17.1, §13.4
- **Branch:** `codex/e05-r16-geometry-tracking-and-calibration-loss`
- **Előfeltétel:** **E05-R10, E05-R15 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

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

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R10/R15 merge; olvasd újra az
> R10 invalidation reason listáját (a calibration loss ezekre képez) és az R15
> kondíció-küszöbét. Nincs ÚJ ADR (0164 bővítése). PREPARED→PLANNING, brief
> commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

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
   (ADR 0162). A kimenet `notObservable` + Recalibrate cue. **NEM elfogadható:**
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
