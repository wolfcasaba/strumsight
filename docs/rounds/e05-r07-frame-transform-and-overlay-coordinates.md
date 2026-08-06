# E05-R07 — Frame transform és overlay koordinátarendszer

- **Státusz:** PLANNING (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`; pre-flight 2026-08-06, mérve: main @ `b6408f0`)
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

**Pre-flight mért megerősítés (2026-08-06, `main` @ `b6408f0`, nem revízió):**
mindkét előfeltétel (E05-R03, E05-R06) merge-elve, `origin/main` == lokális
HEAD == `b6408f0`, a brief `5d082dc` baseline-ja ennek ősje (nincs köztes
kód-diff a camera modulban a batch-írás óta a két függő kör diffjén kívül).
Nincs új ADR (megerősítve). `lib/core/camera/camera_frame.dart` ténylegesen
kimérve: a §2 „rotationt hordozza" leírás a típusos `orientation`
(`CameraOrientation`: `portraitUp`/`landscapeRight`/`portraitDown`/
`landscapeLeft`) mezőre utal — nincs szó szerinti `rotation` mező. Ez NEM
scope-ütközés: az `allowed_paths` egyike sem módosítja/importálja a
`camera_frame.dart`-ot, a §5 architekturális döntései (rotation
{0,90,180,270} mint a transzformáció saját, `CameraFrame`-től független
paramétere) és a §6 fixture-mátrix nem függ a szó szerinti mezőnévtől — a
`CameraOrientation` → e réteg rotation-paraméter leképezés egy KÉSŐBBI kör
(kézszerep/overlay bekötés) dolga. `test/property/dsp_property_test.dart`
PROPERTY_SEED mintája (env → `int.tryParse ?? 42`, `math.Random(seed)`,
`print('PROPERTY_SEED=$seed')`) a HORIZON konvenció szerint reprodukálva.
Erőforrás-tulajdonlási ellenőrzés (`\.acquire(` grep) **N/A** — ez a kör
nem allokál lease/lock/handle/subscription-t, pure math réteg.

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

### 6.1 Küszöb-mátrix — a round-trip tolerancia három cellája

A §5 4. pontja dokumentált tolerancia-konstanst ír elő. A teszt mind a három
cellát mérje (a cellák értékét `python3 -c`-vel számold ki, ne idealizált
rácsból):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alatt | tolerancia − 1 ulp-nyi eltérés | ZÖLD |
| rajta | pontosan a tolerancia | ZÖLD (a határ **inkluzív**) |
| fölött | tolerancia + 1 ulp-nyi eltérés | **PIROS** |

A konstans megemelése a mért értékhez tiltott: az a mérce gyengítése, nem
javítás — ilyenkor dokumentált brief-revízió kell.

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
