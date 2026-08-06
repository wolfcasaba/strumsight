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

### Megvalósítás

- `camera_coordinate_space.dart`: a sensor, buffer, upright, normalized,
  preview és overlay terekhez külön, immutable ponttípusok, továbbá típusos
  sensor/normalized/preview téglalapok és méretek.
- `camera_transform.dart`: generikus, affine `CameraTransform<From, To>`
  `apply`/`compose`/`inverse` műveletekkel; a transzformációk forrás- és
  céltér-típusa fordítási időben kódolt. A round-trip limit a fájl tetején
  változatlanul `1e-6`. A review F1 döntése: `overlay ≡ preview`, mert az
  overlay a preview-val azonos helyi, logikai pixel-térben rajzolódik; a
  device-pixel-ratio átszámítás a presentation host felelőssége, még e két
  helyi tér létrehozása előtt. Ezt az explicit
  `CameraTransform<PreviewPoint, OverlayPoint>` identitás-transzform rögzíti,
  nem egy későbbi widget gyorskorrekciója.
- `preview_fit.dart`: safe-area offsetet hordozó aspect-fit/fill layout,
  letterbox/content/crop téglalapok, valamint preview-oldali front-mirror.
  A modell bemenete kizárólag az eredeti, nem tükrözött normalized tér.
- Tesztek: 16-cellás független fixture, letterbox/crop/boundary mátrix, és
  `PROPERTY_SEED`-es randomizált round-trip/mirror/rotation/visible-range
  propertyk. A review F1 javítása a `PreviewPoint → OverlayPoint` transzformon
  keresztül előállított overlay pontot méri; az F2 javítása a property
  round-trip hibát a `isRoundTripErrorWithinTolerance` közös segédfüggvényen
  keresztül ellenőrzi.

### Független numerikus fixture-levezetés

A RED teszt megírása előtt futtatott parancs (a képlet a 4×3 sensorból az
8×8 viewportba, rotation után fit/fill skálázás és végül opcionális
preview-mirror):

```bash
python3 -c "from itertools import product
W,H,V=4.0,3.0,8.0
pts=[('corner',(0.0,0.0)),('center',(0.5,0.5)),('asym',(0.25,0.75))]
for rot,mir,mode in product((0,90,180,270),(False,True),('fit','fill')):
    uw,uh=(W,H) if rot in (0,180) else (H,W)
    scale=min(V/uw,V/uh) if mode=='fit' else max(V/uw,V/uh)
    cw,ch=uw*scale,uh*scale
    left,top=(V-cw)/2,(V-ch)/2
    out=[]
    for name,(x,y) in pts:
        if rot==0: u,v=x,y
        elif rot==90: u,v=1-y,x
        elif rot==180: u,v=1-x,1-y
        else: u,v=y,1-x
        px,py=left+u*cw,top+v*ch
        if mir: px=left+cw-(px-left)
        out.append(f'{name}=({px:.6f},{py:.6f})')
    print(f'r{rot} mirror={str(mir).lower()} {mode}: ' + ', '.join(out))"
```

Kimenet (a tesztben kézzel rögzített elvárt értékek):

```text
r0 mirror=false fit: corner=(0.000000,1.000000), center=(4.000000,4.000000), asym=(2.000000,5.500000)
r0 mirror=false fill: corner=(-1.333333,0.000000), center=(4.000000,4.000000), asym=(1.333333,6.000000)
r0 mirror=true fit: corner=(8.000000,1.000000), center=(4.000000,4.000000), asym=(6.000000,5.500000)
r0 mirror=true fill: corner=(9.333333,0.000000), center=(4.000000,4.000000), asym=(6.666667,6.000000)
r90 mirror=false fit: corner=(7.000000,0.000000), center=(4.000000,4.000000), asym=(2.500000,2.000000)
r90 mirror=false fill: corner=(8.000000,-1.333333), center=(4.000000,4.000000), asym=(2.000000,1.333333)
r90 mirror=true fit: corner=(1.000000,0.000000), center=(4.000000,4.000000), asym=(5.500000,2.000000)
r90 mirror=true fill: corner=(0.000000,-1.333333), center=(4.000000,4.000000), asym=(6.000000,1.333333)
r180 mirror=false fit: corner=(8.000000,7.000000), center=(4.000000,4.000000), asym=(6.000000,2.500000)
r180 mirror=false fill: corner=(9.333333,8.000000), center=(4.000000,4.000000), asym=(6.666667,2.000000)
r180 mirror=true fit: corner=(0.000000,7.000000), center=(4.000000,4.000000), asym=(2.000000,2.500000)
r180 mirror=true fill: corner=(-1.333333,8.000000), center=(4.000000,4.000000), asym=(1.333333,2.000000)
r270 mirror=false fit: corner=(1.000000,8.000000), center=(4.000000,4.000000), asym=(5.500000,6.000000)
r270 mirror=false fill: corner=(0.000000,9.333333), center=(4.000000,4.000000), asym=(6.000000,6.666667)
r270 mirror=true fit: corner=(7.000000,8.000000), center=(4.000000,4.000000), asym=(2.500000,6.000000)
r270 mirror=true fill: corner=(8.000000,9.333333), center=(4.000000,4.000000), asym=(2.000000,6.666667)
```

A tolerancia-küszöb három cellájának független mérése:

```bash
python3 -c "import math; tolerance=1e-6; print(f'below={math.nextafter(tolerance, -math.inf):.18g}'); print(f'at={tolerance:.18g}'); print(f'above={math.nextafter(tolerance, math.inf):.18g}')"
```

```text
below=9.99999999999999743e-07
at=9.99999999999999955e-07
above=1.00000000000000017e-06
```

`below` és `at` zöld, az `above` a testelt inkluzív küszöbnél piros.

### Valódi-sértés próba

A `PreviewFit.toModelInput()` ideiglenesen a `a: -1, tx: 1` normalized
mirrorra változott. Ekkor a
`front preview mirroring cannot alter the model input space` teszt PIROS lett
(a várt `NormalizedPoint(0.25, 0.75)` helyett tükrözött érték érkezett).
A helyes `a: 1, tx: 0` modell-input transzformáció visszaállt; a front mirror
csak `PreviewPoint → PreviewPoint` műveletként maradt meg.

### Futott ellenőrzések

- RED: `flutter test test/core/camera/camera_transform_test.dart` — a három
  új contract import hiánya miatt várt fordítási hiba.
- `flutter test test/core/camera/camera_transform_test.dart` — zöld (4 teszt).
- `flutter test test/core/camera/preview_fit_test.dart` — zöld (6 teszt);
  a szándékos normalized-mirror mutáció alatt várt piros (1 teszt).
- `flutter test test/property/camera_transform_property_test.dart` — zöld
  (`PROPERTY_SEED=42`, 4 property).
- `dart format` a hat Dart fájlon — zöld.
- `flutter analyze` kizárólag a hat kör-fájlon — zöld, „No issues found”.
- `tools/round-gate.sh test/core/camera test/property/camera_transform_property_test.dart`
  — **blokkolt az analyze lépésben**: format zöld, majd 882, a körön kívüli
  hiányzó `lib/l10n/app_localizations.dart` importból eredő hiba; ezért a gate
  test és architecture lépése nem indulhatott el.

### Nem futtatott ellenőrzések

- Valós eszközös/natív kamera és overlay widget golden: nincs ebben a pure
  Dart körben; az R24 widget overlay, illetve a device-mátrix feladata.
- A teljes kör-gate zöld lezárása: a scope-on kívüli lokalizáció-generált
  artefaktum hiánya blokkolja; a fenti célzott analyze és tesztek viszont
  ténylegesen lefutottak.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r07-frame-transform-and-overlay-coordinates-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
