# E05-R07 — Frame transform és overlay koordinátarendszer

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 7; §18
- **Branch:** `codex/e05-r07-frame-transform-and-overlay-coordinates`
- **Előfeltétel:** **E05-R03, E05-R06 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/camera/camera_transform.dart",
  "lib/core/camera/camera_coordinate_space.dart",
  "lib/core/camera/preview_fit.dart",
  "test/core/camera/camera_transform_test.dart",
  "test/core/camera/preview_fit_test.dart",
  "test/property/camera_transform_property_test.dart",
  "docs/rounds/e05-r07-frame-transform-and-overlay-coordinates.md",
]
gate_tests = [
  "test/core/camera",
  "test/property/camera_transform_property_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R03/R06 merge; olvasd újra az
> R06 `CameraFrame` metaadat-mezőit (rotation, mirror, crop, width/height) és a
> `test/property/` mai `PROPERTY_SEED` mintáját (`test/property/dsp_property_test.dart`).
> Nincs ÚJ ADR. PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

**Pure Dart**, platformfüggetlen koordináta-transzformáció a sensor → upright →
normalized → preview → overlay terek között, minden orientation/crop/mirror
kombinációra, property-tesztekkel bizonyított invariánsokkal.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- Nincs koordináta-réteg; a `CameraFrame` (E05-R03/R06) hordozza a rotationt,
  mirror state-et, cropot és a méreteket.
- `test/property/` ma 16 property-teszt; a **HORIZON konvenció** szerint a seed
  a `PROPERTY_SEED` env-ből jön (hiányában 42), a küszöbök **%-alapúak**, és a
  CI külön HARD lépést futtat `PROPERTY_SEED=${{ github.run_id }}`-vel.
- A repóban **nincs** ad hoc koordináta-matek widgetekben (a vision UI még nem létezik) —
  ez a kör teremti meg azt az egyetlen helyet, ahonnan később mindenki dolgozik.

## 3. Scope

**Benne:** `CameraCoordinateSpace` enum + típusbiztos pont/téglalap
reprezentáció, komponálható `CameraTransform` (`compose`, `inverse`,
`apply`), aspect-**fit** és aspect-**fill** preview mapping, safe-area/letterbox
offset, front-preview mirror kezelés úgy, hogy a **modell bemenete NEM tükrözött**.

**Kívül — TILOS:** widget/overlay rajzolás (R24), homography és gitárkoordináta
(R15), inference, camera adapter módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/core/camera/camera_transform.dart` | ÚJ | komponálható transzformáció |
| `lib/core/camera/camera_coordinate_space.dart` | ÚJ | terek + típusos pontok |
| `lib/core/camera/preview_fit.dart` | ÚJ | fit/fill + letterbox offset |
| `test/core/camera/*` | ÚJ | fixture + boundary tesztek |
| `test/property/camera_transform_property_test.dart` | ÚJ | round-trip/mirror invariáns |
| `docs/rounds/e05-r07-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Egyetlen igazságforrás:** a presentation **kizárólag** ezt a mappinget
   használhatja overlayhez. **NEM elfogadható** widgetbe írt „gyors" korrekció
   (`1 - x`, `swap(w,h)`) — a későbbi körök review-ja ezt BLOCKER-ként kezeli.
2. **A tér típusban van kódolva** (nem puszta `Offset`): egy `PreviewPoint`
   nem adható át ott, ahol `NormalizedPoint` kell. **NEM elfogadható** a
   `double x, y` szintű, tér nélküli API.
3. **A front kamera tükrözése preview-oldali.** A model input **nem tükrözött**;
   a kézszerep-hozzárendelés (R13) a nem tükrözött téren dolgozik.
   **NEM elfogadható** a tükrözés beépítése a normalized térbe.
4. **Round-trip tolerancia dokumentált szám** (nem „elhanyagolható"): a
   `apply(inverse(p))` eltérése ≤ **1e-6** normalizált egységben; a property
   teszt ezt méri, és a küszöb a fájl tetején konstansként áll.
5. **Nincs `dynamic`, nincs `dart:ui` függés** ebben a rétegben (pure Dart,
   `lib/core/` szabály: nem importálhat feature-t, és a domain framework-mentes).

## 6. Acceptance criteria

- [ ] **Numerikus fixture-mátrix:** rotation {0,90,180,270} × mirror {be,ki} ×
      fit {fit,fill} = **16 cella**, cellánként legalább 3 ismert pont
      (sarok, közép, aszimmetrikus pont) elvárt kimenettel. A fixture-értékek
      **kézzel kiszámoltak** (a §10 tartalmazza a levezetés `python3 -c` sorát),
      nem az implementációból generáltak.
- [ ] **Property teszt (seed a `PROPERTY_SEED`-ből):** (a) `inverse ∘ apply`
      round-trip ≤ 1e-6; (b) kétszeres tükrözés = identitás; (c) 4×90° forgatás
      = identitás; (d) a fit/fill mapping **bennmarad** a preview téglalapban.
- [ ] **Letterbox-teszt:** nem egyező képarányoknál a fit-nél van offset, a
      fill-nél van crop — mindkettő számmal ellenőrizve, a határon (azonos
      képarány) offset = 0.
- [ ] **Valódi-sértés próba (§10-ben dokumentálva):** a mirror alkalmazásának
      áthelyezése a normalized térbe → a property (b) vagy a fixture-mátrix
      PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/camera test/property/camera_transform_property_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. A golden overlay teszt az R24 dolga
(ott van widget); itt a bizonyíték numerikus.

## 8. Implementációs sorrend

1. Kézi fixture-mátrix kiszámolása (`python3 -c`), RED tesztek.
2. Terek + típusos pontok.
3. Transform + compose/inverse.
4. Preview fit/fill + letterbox; property teszt; gate.

## 9. Kockázatok

- **A fixture az implementációból generálódik** → a teszt önmagát igazolja.
  Ellenszer: a §10-ben a levezetés parancsa és kimenete.
- **Lebegőpontos zaj** a 90°-os forgatásoknál: egész-alapú swap kell, nem
  `sin/cos` — a 4×90° identitás-property ezt fogja meg.

**STOP:** `dart:ui`/widget-függés bevezetése, tér nélküli API vagy a tolerancia
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r07-frame-transform-and-overlay-coordinates-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
