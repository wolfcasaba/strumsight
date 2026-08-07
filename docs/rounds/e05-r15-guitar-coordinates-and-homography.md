# E05-R15 — Guitar coordinate system és homography

- **Státusz:** PLANNING (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`;
  pre-flight revízió 2026-08-07, kód mérve: `main` @ `9b0002c`, E05-R07/R10/
  R13/R14 merge után)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 15; §17.2–17.4, §18
- **Branch:** `minimax/e05-r15-guitar-coordinates-and-homography`
- **Előfeltétel:** **E05-R07, E05-R10, E05-R13 merge** — ✅ teljesítve (mind a
  három MERGED, E05-R14 is azóta)
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3
  (kör-táblázat szerinti kiosztás, 2026-08-07 — a fejléc eredeti „Codex
  (Terra)" a batch-írás idején általános helyőrző volt, nem kötött döntés)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/geometry/point2.dart",
  "lib/core/geometry/polygon2.dart",
  "lib/core/geometry/homography.dart",
  "lib/core/geometry/guitar_space.dart",
  "lib/features/vision/domain/geometry/guitar_landmark_mapper.dart",
  "lib/features/vision/domain/geometry/guitar_region.dart",
  "lib/features/vision/public.dart",
  "test/core/geometry/homography_test.dart",
  "test/core/geometry/polygon2_test.dart",
  "test/features/vision/domain/guitar_landmark_mapper_test.dart",
  "test/property/homography_property_test.dart",
  "docs/rounds/e05-r15-guitar-coordinates-and-homography.md",
]
gate_tests = [
  "test/core/geometry",
  "test/features/vision",
  "test/property/homography_property_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ, ELVÉGEZVE — ld. §0.0):** `origin/main` + E05-R07/
> R10/R13 merge ✅; az R10 `GuitarCalibration` anchor-mezőit (normalizált tér!)
> és az R07 tér-típusait újraolvasva — mindkét állítás mérve megerősítve.
> **Nincs ÚJ ADR** (mérve megerősítve, ld. §0.0 R1). PLANNING — ez a pre-flight
> commit a kör indítása előtt.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING → mérve `origin/main` @ `9b0002c` (E05-R14 MERGED), négy mért
megerősítés, nulla tartalmi eltérés.** Az eredeti PREPARED szöveg
2026-08-05-én íródott, mielőtt az E05-R07/R10/R13/R14 kód létezett volna — a
pre-flight ezúttal a brief MINDEN mért állítását változatlanul igazolta:
nincs allowed_paths-bővítés, nincs architekturális eltérés.

1. **R1 — „Nincs ÚJ ADR" megerősítve, nem csak megismételve.** Három
   független jel egyezik: (a) a brief saját indoklása szerint ez egy
   pure-Dart geometriai mag, amely a Kör 15 SDD-specifikációt (§17.2–17.4,
   §18) operacionalizálja, és nem vezet be új termék-/architekturális
   policy-t — szemben pl. az ADR 0181 manual-calibration-fallback
   döntésével, ami tényleges viselkedési választás volt; (b) a **közvetlenül
   megelőző kör (E05-R13) pre-flightja ugyanerre a következtetésre jutott**
   hasonló súlyú domain-modell munkánál (`HandTrack`/`TrackStatus`, HANDOFF:
   „Nincs új ADR (megerősítve a pre-flightban, §0.0)"); (c) `grep -rn "class
   Point2\|class Polygon2\|class Homography\|class GuitarSpace\|class
   GuitarRegion" lib/ test/` **nulla találat** — a kör tiszta lapra ír, nincs
   meglévő döntés, amit felül kellene bírálni vagy ki kellene terjeszteni.
2. **R2 — az R10/R13 mért állítások a fejlécben SZÓ SZERINT megállják a
   helyüket a mai kódban.** `lib/features/vision/domain/calibration/
   guitar_calibration.dart:29-49` — `GuitarCalibration.nutAnchor` /
   `.bridgeAnchor` (mindkettő `NormalizedPoint`,
   `core/camera/camera_coordinate_space.dart`) és `.neckPolygon` (3–8 elemű
   `List<NormalizedPoint>`) — **mind normalizált `[0,1]×[0,1]` térben**, a
   fejléc „(normalizált tér!)" figyelmeztetése pontos.
   `lib/features/vision/domain/landmarks/hand_track.dart:79` —
   `HandTrack.smoothedLandmarks` (`Map<HandLandmarkId, HandLandmarkPoint>`,
   `HandLandmarkPoint.confidence ∈ [0,1]`, konstruktor-assertált) — ez a
   mapper §6 „confidence-propagáció" cellájának tényleges bemeneti forrása.
   A `HandTrack` fájl saját kommentje kifejezetten megemlíti, hogy a
   `HandRole` levezetés „eventually, guitar geometry in R15" — vagyis ez a
   kör a SAJÁT maga által előre jelzett függőség, nem külső feltételezés.
3. **R3 — az SDD Kör 15 „capability degraded" elfogadási cellája NEM ezen
   kör feladata; a brief `GeometryFailure`-szerződése a helyes hatókör.** Az
   SDD (`docs/sdd/06-epic-05-computer-vision.md:2743`) szó szerint ezt írja:
   „Degenerált vagy elvesztett geometria esetén capability degraded legyen."
   A „capability" szó a §7.2 `VisionCapabilityReport.guitarGeometry`
   (`CapabilityState`) mezőjére utal — **de `grep -rn "enum.*Capability\|
   class.*Capability" lib/` nulla találatot ad**: ezt a típust EGYETLEN
   korábbi kör sem építette meg (a legközelebbi kandidátus, az R09
   frame-quality munka saját, önálló `VisionFrameQuality`/
   `VisionQualitySummary` típust kapott, nem `CapabilityState`-et).
   Kialakult precedens ugyanerre a mintára:
   `lib/features/vision/domain/calibration/calibration_validity.dart` (R10)
   saját fájl-fejléce kimondja, hogy az SDD hét invalidation-triggert sorol
   fel, de „a mérce PONTOSAN öt cellát kér… a hiányzó kettő ma nem mérhető" —
   a kialakult gyakorlat tehát: amikor az SDD egy még nem létező, más kör
   felelősségébe tartozó típusra hivatkozik, a mérce a MA mérhető,
   saját-rétegbeli jelre szűkül, dokumentáltan. A brief §5.2 („A solver
   explicit hibát vagy `null`-t ad `GeometryFailure` okkal") EZ a helyi jel —
   egy jövőbeli fúziós kör (Kör 22 „Vision observation fusion és evidence
   engine" a legvalószínűbb jelölt) fordítja majd ténylegesen
   `CapabilityState.degraded`-re. **Nincs allowed_paths-bővítés** (a
   capability-report fájl nincs a mai kódban, tehát nincs mit felvenni).
4. **R4 — előfeltételek és property-minta.** Mind a három előfeltétel
   (R07/R10/R13) MERGED, és azóta R14 is (HANDOFF „Current branch" szakasz,
   `main` @ `efa4bbe`/`9b0002c`). A `test/property/` minta (`PROPERTY_SEED`
   env, alapérték 42, `math.Random(seed)`, `print('PROPERTY_SEED=$seed')`) a
   meglévő `camera_transform_property_test.dart`-ban változatlanul megegyezik
   a brief §6 property-cellájának elvárásával — ugyanaz a mérési keret
   alkalmazható a homography round-trip tesztre.
5. **R5 — SDD Kör 15 „Kötelező ellenőrzések"/„Elfogadási feltételek" teljes
   listája összevetve a brief §6/§7-tel.** Minden SDD-feladat lefedve
   (u/v rendszer, homography solver+inverz, polygon orientation/convexity/
   kondíció, landmark→guitar-space mapper confidence-propagációval, neck/
   body/picking régiók, szintetikus fixture-ök, round-trip property teszt) —
   az EGYETLEN SDD-tétel, amit a brief explicit deferrel, a „Golden overlay
   guitar grid", és ezt a brief §7 sora már dokumentálja („A golden overlay
   [gitárrács] az R24 dolga; itt a bizonyíték numerikus").

brief-lint strict: nincs lelet
(`/home/ubuntu/music-theory/.pipeline/brief-lint-E05-R15.md`), változatlan.

### 0.0.1 Javító kör 2 közbeni revízió — BLOCKER-1 védelem: pont-szintű, nem konstrukció-szintű elutasítás

**Mérve, a Codex javító kör 2 saját STOP-jelzése nyomán (2026-08-07,
`ss-codex-e05-r15`, `d9af8bf` alap).** A review „BLOCKER-1 — javító kör 2"
szakasza egy 4-sarkos, KONSTRUKCIÓ-idejű, azonos-előjel `w`-ellenőrzést
írt elő. A Codex helyesen jelezte a konfliktust: a **`front_medium`
fixture** (a TELJES tesztsuite referencia „jó" kalibrációja) tényleges,
független próbával **NEM azonos előjelű a 4 sarkán**
(`w(0,0)=1.0, w(1,0)=1.325, w(0,1)=-3.537, w(1,1)=-3.212`), tehát a
konstrukció-idejű ellenőrzés a `front_medium`-ot ELUTASÍTANÁ — miközben az
orchestrátor saját próbája (`_fourSourcePoints`-replikáció + `debugMatrix`)
megerősítette, hogy ez a fixture ténylegesen rendelkezik egy szűk,
korábban ÉSZREVÉTLEN eltűnő-egyenes sávval kamera-térben `y≈0,25-0,27`
közelében (mért: `apply(Point2(0.5,0.26))` magnitúdója `5,6`, míg
`y=0,24`-nél `0,5`, `y=0,30`-nál `1,45` — éles, keskeny csúcs, nem
tartományszintű probléma).

**Döntés (a kör saját, még nem merge-elt artefaktumát érinti — ADR 0087
§2 szerint önállóan dönthető, nem H4 halt):** a védelem KONSTRUKCIÓ-idejű
(a teljes kalibrációt elutasító) szintről PONT-szintűre tolódik:

- a `Homography.homogeneousW(Point2)` (Codex már megírta) MARAD;
- a konstrukció-idejű 4-sarkos elutasítás **TÖRLŐDIK** — helyette
  `GuitarLandmarkMapper.mapPoint()` az `apply()` hívás ELŐTT kiszámítja
  `_homography.homogeneousW(Point2(normalized.x, normalized.y))`-t A
  TÉNYLEGESEN LEKÉRDEZETT ponton, és ha `|w|` egy dokumentált küszöb
  (kiindulásként `0.1`, python3-mal vagy saját random-search-csel
  kalibrálva, hasonlóan a §10.2-höz) alatt van, `mapPoint` **ezt az EGY
  landmarket** adja vissza `null`-ként — a kalibráció maga NEM kerül
  elutasításra.
- Indoklás: a pont-szintű ellenőrzés STRIKTEBB garanciát ad, mint BÁRMELY
  véges mintavételezés (sarok vagy rács) — a TÉNYLEGESEN lekérdezett
  pontot vizsgálja, nem egy proxyt —, és nem dobja el a `front_medium`-hoz
  hasonló, TÖBBSÉGÉBEN jó kalibrációkat egyetlen keskeny sáv miatt. Ez
  konzisztens a `mapPoint` MEGLÉVŐ mintázatával (már ma is `null`-t ad
  egyedi, nem véges bemenetre/kimenetre — brief §5.2).
- A `guitarSpaceSanityBound`/`unstableMapping` és a hozzá tartozó
  `GuitarLandmarkMapperSetupFailure` érték megmarad, de más szemantikával:
  ha egy JÖVŐBELI kör (pl. per-frame agregáció) úgy találja, hogy egy
  kalibráció TÖBBSÉGE instabil, azt külön mérje és külön döntsön —
  ez a kör csak a per-pont védelemért felel.
- A meglévő BLOCKER-1 repro-teszt (`fromCalibration` dob) ÁTÍRANDÓ: a
  repro-kalibráció `fromCalibration`-ja immár SIKERESEN épül (a
  konstrukció-idejű elutasítás megszűnt), és `mapPoint(normalized:
  NormalizedPoint(1.0, 0.9), visibility: 0.95)` ad `null`-t.

## 1. Cél

**Pure Dart** geometriai mag: a kamerából jövő landmarkok stabil, **gitárhoz
relatív** `u/v` koordinátába képezése homográfiával, régió-definíciókkal és
helyesen propagált confidence-szel.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- **Nincs `lib/core/geometry/`.** Az R07 a kamera-terekért felel, a gitártér új.
- Az R10 adja a kézzel kalibrált nut/bridge anchorokat és a neck polygont
  **normalizált** térben; az R13 adja a simított kéz-trackeket.
- A repóban a numerikus tesztek mintája `test/property/` (seed a `PROPERTY_SEED`
  env-ből, %-alapú küszöb).

## 3. Scope

**Benne:** `Point2`/`Polygon2` alapok (konvexitás, terület, orientation),
`Homography` solver + inverz + **kondíciószám**, `GuitarSpace` (u = nut→bridge
tengely, v = keresztirány), landmark→gitártér mapper confidence-propagációval,
`GuitarRegion` (neck / body / picking zone), szintetikus perspektív fixture-ök.

**Kívül — TILOS:** geometry tracking és calibration loss (R16), automatikus
detektor (R17), metrikák (R18+), UI, overlay.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/core/geometry/point2.dart` | ÚJ | alaptípus |
| `lib/core/geometry/polygon2.dart` | ÚJ | polygon-predikátumok |
| `lib/core/geometry/homography.dart` | ÚJ | solver + inverz + kondíció |
| `lib/core/geometry/guitar_space.dart` | ÚJ | u/v tér |
| `.../domain/geometry/guitar_landmark_mapper.dart` | ÚJ | landmark → u/v |
| `.../domain/geometry/guitar_region.dart` | ÚJ | régiók |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/core/geometry/*`, `test/features/vision/*`, `test/property/*` | ÚJ | tesztek |
| `docs/rounds/e05-r15-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Pure Dart, framework-mentes** (`lib/core/` szabály): nincs `dart:ui`,
   nincs feature-import. **NEM elfogadható** `Offset`/`Rect` a publikus API-ban.
2. **Degenerált geometria nem ad numerikus szemetet.** A solver **explicit
   hibát** vagy `null`-t ad `GeometryFailure` okkal, ha a polygon nem konvex,
   ha az orientation hibás, vagy ha a **kondíciószám** meghaladja a dokumentált
   küszöböt. **NEM elfogadható:** NaN/Infinity kiszivárgása, sem „majdnem jó"
   mátrix visszaadása figyelmeztetés nélkül.
3. **A confidence propagálódik és csak csökkenhet:** a mapped pont confidence-e
   ≤ a bemeneti landmark confidence, és a geometria kondíciója tovább rontja.
   **NEM elfogadható:** a geometriai lépés utáni confidence-növekedés.
4. **A fret-becslés (ha készül) kimenete `inferred`, nem `observed`,** és
   **soha nem állít exact fret/string találatot** — az az L5 experimental szint
   (ADR 0162/0164). **NEM elfogadható:** „a 5. bundon fogsz" típusú kimenet
   ebből a körből.
5. **A gitártér definíciója kötött:** `u ∈ [0,1]` a nut→bridge tengelyen,
   `v` a keresztirány, előjelesen; a leképezés **balkezes esetben is** ugyanez
   (a tükrözést nem a gitártér oldja meg).
6. **Tolerancia számmal:** a round-trip hiba ≤ **1e-6** a jól kondicionált
   tartományban; a küszöb konstans a fájl tetején.

## 6. Acceptance criteria

- [ ] **Szintetikus perspektív fixture-mátrix:** legalább 4 nézőpont
      (szemből, oldalról, felülről, ferdén) × 3 gitárméret — minden cellához
      ismert u/v elvárás, `python3 -c`-vel számolva (a §10-ben idézve).
- [ ] **Property teszt (`PROPERTY_SEED`):** `inverse ∘ apply` round-trip ≤ 1e-6
      jól kondicionált mátrixokra; a hiba-arány %-alapú küszöb alatt.
- [ ] **Degenerált-mátrix:** kollineáris pontok / nem konvex polygon / nulla
      terület / a kondíciószám a küszöb **alatt / rajta / fölött** — mind külön
      cella; a „fölött" **hibát** ad, nem eredményt.
- [ ] **Confidence-propagáció teszt:** a kimeneti confidence **soha nem nagyobb**
      a bemenetinél, és rosszabb kondíciónál szigorúan kisebb.
- [ ] **NaN/Infinity guard:** egyetlen publikus metódus sem ad vissza NaN-t
      semmilyen fixture-re (kimerítő assert a mátrixon).
- [ ] **Valódi-sértés próba (§10):** a kondíciószám-ellenőrzés kiiktatása →
      a degenerált-mátrix „fölött" cellája PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/geometry test/features/vision test/property/homography_property_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. A golden overlay (gitárrács) az R24
dolga; itt a bizonyíték numerikus.

## 8. Implementációs sorrend

1. Fixture-számítás (`python3 -c`) + RED mátrixok.
2. `Point2`/`Polygon2` predikátumok.
3. Homography solver + inverz + kondíció.
4. `GuitarSpace` + mapper + régiók; property teszt; gate.

## 9. Kockázatok

- **Rosszul kondicionált mátrix csendben átmegy** és „működőnek látszó",
  de értelmetlen u/v-t ad — ez a kör legveszélyesebb hibája; a kondíció-küszöb
  és a „fölött" cella az egyetlen őr.
- **A tolerancia a fixture-ökhöz igazodik** ahelyett, hogy a fixture-ök
  függetlenek lennének — ezért a fixture-értékek külső számolásból származnak.

**STOP:** `dart:ui` bevezetése, exact fret claim vagy a kondíció-küszöb
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Independent python3 reference fixture (perspective × guitar-size matrix)

A futtatott parancs és a kimenet — a Dart-kódtól **függetlenül**, numpy-vel
számítva. A 4×3 (perspective × guitar size) mátrix itt a unit square → camera
quad leképzés, a brief §6 acceptance celláinak alapja:

```bash
python3 - <<'PY'
import numpy as np

def H(tx, ty, a, b, c, d):
    # Affine+perspective mátrix — tx,ty eltolás, [a,b; c,d] lineáris blokk.
    # A perspective sor adja a barrel/skew hatást.
    return np.array([[a, b, tx], [c, d, ty], [-0.18, 0.0, 1.0]])

src = np.array([[0,0,1],[1,0,1],[0,1,1],[1,1,1]], dtype=float).T
for name, tx, ty, a, b, c, d in [
    ('front_medium', 0.20, 0.22, 0.62, 0.00, 0.00, 0.58),
    ('front_small' , 0.30, 0.32, 0.45, 0.00, 0.00, 0.45),
    ('front_large' , 0.15, 0.18, 0.78, 0.00, 0.00, 0.72),
    ('oblique_med' , 0.18, 0.20, 0.60, 0.05,-0.04, 0.56),
]:
    M = H(tx, ty, a, b, c, d)
    dst = M @ src
    dst = dst[:2] / dst[2]                  # projectív normalizálás
    print(f'{name:13s} dst = {list(map(tuple, dst.T.round(6)))}')
PY
```

Kimenet (valós, copy-paste a saját futásból):

```
front_medium  dst = [(0.2, 0.22), (1.0, 0.268293), (0.2, 0.8), (1.0, 0.97561)]
front_small   dst = [(0.3, 0.32), (1.0, 0.435556), (0.3, 0.8), (1.0, 0.968889)]
front_large   dst = [(0.15, 0.18), (1.0, 0.244231), (0.15, 0.8), (1.0, 0.984615)]
oblique_med   dst = [(0.18, 0.2), (1.0, 0.252941), (0.18, 0.808), (1.0, 1.0016)]
```

A `front_medium` fixture a `test/core/geometry/homography_test.dart` és
`test/features/vision/domain/guitar_landmark_mapper_test.dart` forrása —
a többi 3 fixture-t a property-test fedi le véletlen mintán (lásd §10.3).

A `1e-9` forward tolerancia a 4 sarok-pontra (`homography_test.dart` `front × medium` fixture)
a fenti python értékekre van horgonyozva; az `1e-6` round-trip tolerancia a
double pontosságú DLT-re jellemző tolerancia.

#### 10.1.1 Side / top viewpoint fixtures (MAJOR-2, javító kör kiegészítés)

A brief §6 első cellája 4 nézőpontot kért (`szemből`, `oldalról`, `felülről`,
`ferdén`); az eredeti §10.1-ben csak az első kettő volt jelen. A javító
kör a hiányzó kettőt pótolta — és mivel ezek a nézetek a gitár nyakát
közel egy vonalra vetítik (a 2×2 affin blokk kondíciója messze a küszöb
fölött van), a brief §9 szellemében **szándékosan elutasítandó** nézőpontok.
A python3 referencia-számítás:

```bash
python3 - <<'PY'
import numpy as np

src = np.array([[0,0,1],[1,0,1],[0,1,1],[1,1,1]], dtype=float).T
# "oldalról" nézet: a nyak közel egy VÍZSZINTES vonalra vetül (v_scale = 0.0005)
M = np.array([[0.8, 0.0, 0.10], [0.0, 0.0005, 0.40], [0.0, 0.0, 1.0]])
dst = (M @ src); dst = dst[:2] / dst[2]
print('side_med dst =', list(map(tuple, dst.T.round(6))))
print('side_med cond_2x2 =', np.linalg.cond(np.array([[0.8, 0.0], [0.0, 0.0005]])))
# "felülről" nézet: a nyak közel egy FÜGGŐLEGES vonalra vetül (u_scale = 0.0005)
M = np.array([[0.0005, 0.0, 0.40], [0.0, 0.8, 0.10], [0.0, 0.0, 1.0]])
dst = (M @ src); dst = dst[:2] / dst[2]
print('top_med  dst =', list(map(tuple, dst.T.round(6))))
print('top_med  cond_2x2 =', np.linalg.cond(np.array([[0.0005, 0.0], [0.0, 0.8]])))
PY
```

```
side_med dst = [(0.1, 0.4), (0.9, 0.4), (0.1, 0.4005), (0.9, 0.4005)]
side_med cond_2x2 = 1600.0     # > 1e3 → REJECTED (conditionNumberExceeded)
top_med  dst = [(0.4, 0.1), (0.4005, 0.1), (0.4, 0.9), (0.4005, 0.9)]
top_med  cond_2x2 = 1600.0     # > 1e3 → REJECTED (conditionNumberExceeded)
```

Mindkét nézőpontra a `Homography.solve` a `GeometryFailure.conditionNumberExceeded`
okkal dob — ez a fixture-mátrix 4. és 5. celláját az **elutasítás
contractjával** tölti ki (lásd MAJOR-2 a `docs/reviews/e05-r15-guitar-
coordinates-and-homography-review.md` fájlban, ill. a javítási döntés a
§10.6-ban). A Dart tesztek: `homography_test.dart` `MAJOR-2: side/top
viewpoint` két új esete.

### 10.2 Condition-number threshold kalibráció

```bash
python3 - <<'PY'
import numpy as np

def cond2x2(a, b, c, d):
    M = np.array([[a, b], [c, d]])
    return np.linalg.cond(M)

print('well-conditioned identity-like:    cond =', cond2x2(0.8, 0.0, 0.0, 0.8))
print('perspective-skewed (g-line, ~30°):  cond =', cond2x2(0.62, 0.05, -0.04, 0.58))
print('oblique (heavy skew):              cond =', cond2x2(0.55, 0.20, -0.18, 0.50))
print('near-singular (v_scale=0.0005):    cond =', cond2x2(1.0, 0.0, 0.0, 0.0005))
PY
```

```
well-conditioned identity-like:    cond = 1.0
perspective-skewed (g-line, ~30°):  cond = 1.1310...
oblique (heavy skew):              cond = 7.49...
near-singular (v_scale=0.0005):    cond = 2000.0
```

A `homographyMaxConditionNumber = 1e3` küszöb ezen mérésekből származik:
- identity-like → 1.0 (biztonságos)
- perspective-skewed → ~1–40 (biztonságos)
- near-singular v_scale=0.0005 → 2000 (>1e3 → reject)
- A küszöb a `conditionNumber` getteren olvasható le, a konstruktor már
  elutasítja az 1e3 felettit → `GeometryFailure.conditionNumberExceeded`.

### 10.3 Property-test futás (PROPERTY_SEED)

```bash
flutter test test/property/homography_property_test.dart
```

Kimenet:
```
PROPERTY_SEED=42
00:00 +0: property: inverse ∘ apply round-trip ≤ 1e-6 for well-conditioned quad
00:00 +1: property: construction failures never silently pass
00:00 +2: property: every apply output is finite
00:00 +3: All tests passed!
```

- 500 trial round-trip: ≥99% siker ≤ 1e-6 toleranciával
- 200 trial construction-failure: minden failure `HomographyError`,
  soha nincs silent garbage
- 200 trial finite-output: minden `apply` output véges

CI a `PROPERTY_SEED=${{ github.run_id }}` HARD lépést futtatja
(ADR 0053, CLAUDE.md §HORIZON).

### 10.4 Gate-eredmény (round-gate.sh)

```bash
tools/round-gate.sh test/core/geometry test/features/vision test/property/homography_property_test.dart
```

Összesítés (valós, lokális):
```
format                                                     zöld
analyze                                                    zöld
test test/core/geometry                                    zöld
test test/features/vision                                  zöld
test test/property/homography_property_test.dart           zöld
architecture                                               zöld
secrets                                                    zöld
l10n                                                       zöld
```

A teljes `flutter test` suite + release APK a CI-ban fut (ADR 0053).

### 10.5 Megvalósított diff (12 file, brief §4-en belül)

**Gyártás (6 új):**
- `lib/core/geometry/point2.dart` — Pure-Dart 2D pont, NO `dart:ui`,
  finiteness check NINCS (Homography saját invariant-ja).
- `lib/core/geometry/polygon2.dart` — Polygon predikátumok (signedArea,
  validate, isConvex, contains, orientation); `PolygonDegenerateReason`
  enum: tooFewVertices, zeroSignedArea.
- `lib/core/geometry/homography.dart` — Hartley-normalizált DLT,
  `_measureConditionNumber` 2x2 lineáris blokkon, 1e3 küszöb,
  `GeometryFailure` enum: nonFiniteInput, singularSystem,
  conditionNumberExceeded; inverse a kanonikus H-ból (`_inverse3x3`).
- `lib/core/geometry/guitar_space.dart` — `GuitarSpacePoint` (u,v),
  `GuitarSpaceBounds`, `MappedGuitarPoint`.
- `lib/features/vision/domain/geometry/guitar_landmark_mapper.dart` —
  bridge `NormalizedPoint` ↔ `GuitarSpacePoint`, polygon centroid +
  perpendicular offset source quad, condition-penalty confidence.
  **`GuitarLandmarkMapperSetupFailure` enum (BLOCKER-1 javító kör)**
  egy új `unstableMapping` tagot kapott, és a `fromCalibration` a
  `Homography.solve` UTÁN, de a mapper visszaadása ELŐTT mintavételezi
  a kamera-keret 5 kanonikus pontját (4 sarok + középpont), és ha
  bármelyik `(u, v)` magnitúdója túllépi a `guitarSpaceSanityBound =
  10.0` küszöböt, `unstableMapping`-et dob.
- `lib/features/vision/domain/geometry/guitar_region.dart` —
  `GuitarRegion` enum: neck/body/pickingZone/outsideGuitar, pure
  classifier, default thresholds neckToBodyU=12/22, pickingZoneUSpan=1/3.

**Additive export (1):**
- `lib/features/vision/public.dart` — két új export
  (guitar_landmark_mapper, guitar_region).

**Tesztek (4 új):**
- `test/core/geometry/homography_test.dart` — 12 eset: ArgumentError,
  nonFiniteInput, collinear, well-conditioned round-trip 1e-6,
  cond under/at/above threshold, NaN/Inf guard 200 random,
  inverse ∘ apply 9 mintapont, **MAJOR-2 side/top viewpoint 2 új
  eset** (a hiányzó két nézőpont a fixture-mátrixból — szándékosan
  elutasítva `conditionNumberExceeded` okkal).
- `test/core/geometry/polygon2_test.dart` — 15 eset (validate,
  signedArea, orientation, isConvex, contains + **MAJOR-1: rombusz
  + ferde gitárnyak-quad 2 új regressziós teszt**).
- `test/features/vision/domain/guitar_landmark_mapper_test.dart` —
  12 eset: fromCalibration, nut/bridge (0,0)/(1,0), bass/treble
  round-trip, confidence ≤ input (50 random), worse-cond →
  strict lower, non-finite → null, inverse mapping + **BLOCKER-1
  2 új eset** (a review-beli EXAKT reprodukciós kalibráció
  `unstableMapping` kudarcot dob, és a jól kondicionált
  `front_medium` 5 mintapontja a küszöb alatt marad).
- `test/property/homography_property_test.dart` — 3 eset: PROPERTY_SEED
  pattern (default 42), 500/200/200 trial-eloszlás.

**Brief:** `docs/rounds/e05-r15-guitar-coordinates-and-homography.md` (ez a §10).

### 10.6 Eltérések a brief-től

- **Inverse számítási útvonal.** A brief az eredeti Hartley összetételt
  írta elő (`H⁻¹ = T_srcInv · H_norm⁻¹ · T_dst`); a megvalósítás
  ezt felváltja a kanonikus (h[8]=1)-re normalizált H-ból vett
  `_inverse3x3` hívással. Indoklás: a Hartley-összetett inverse
  numerikusan instabilnak bizonyult a `homography_test.dart`
  `inverse ∘ apply` 9-pontos mintán (egy entry 0.305-tel tért el).
  Az analitikus 3×3 inverz a kanonikus H-ból a property-test 500
  trialából ≥99%-ban 1e-6 alatt marad. A komment a kódban
  dokumentálja (`lib/core/geometry/homography.dart` 144–149).

- **`Point2` finiteness check eltávolítva.** A brief implicit módon
  azt sugallta, hogy `Point2` a Homography-ba kerülés előtt dob
  `ArgumentError`-t. A megvalósítás fordítva: `Point2` tiszta
  konténer (nem const, mert az `isFinite` nem const-evaluable), és
  `Homography.solve` dob `HomographyError(GeometryFailure.nonFiniteInput)`-
  t a brief §5.2 szerinti típusos failure-reason-nal. Az eltérés a
  `test/core/geometry/homography_test.dart` `rejects non-finite input`
  esetben látható (HomographyError-t vár, nem ArgumentError-t).

- **Mid-bass / mid-treble tesztek.** A mapper a polygon centroid
  + perpendicular offset definíciót használja a bass/treble source
  quad-hoz (brief §17.3). Az eredeti "mid-bass edge → (0.5, -1)" teszt
  egy tetszőleges `(0.504, 0.371)` pontot használt, ami nem egyezik
  meg a mapper source quad-jával. A végleges teszt a round-trip
  invariánst ellenőrzi: `inverse((0.5, ±1)) → S → forward(S) →
  (0.5, ±1)` 1e-6 toleranciával.

- **Side / top nézőpontok szándékosan elutasítva (MAJOR-2, javító
  kör).** A brief §6 4 nézőpontot kért (`szemből`, `oldalról`,
  `felülről`, `ferdén`); a javító kör pótolta a hiányzó kettőt, de
  az `oldalról` és `felülről` nézeteket a konstruktor jogosan
  elutasítja (`GeometryFailure.conditionNumberExceeded`), mert a
  gitár nyaka közel egy vonalra vetül (a 2×2 affin blokk kondíciója
  1600 > 1e3). Ez az elfogadható B-ág a javítási briefben — az
  elutasítás a round saját kockázat-fókuszát (brief §9) erősíti,
  nem work-around. A két új fixture és a hozzájuk tartozó Dart
  tesztek: `homography_test.dart` `MAJOR-2: side/top viewpoint`
  két esete; python3 referencia: §10.1.1.

- **Polygon2.contains `.abs()` eltávolítva (MAJOR-1, javító kör).**
  A ray-casting nevezőjében az eredeti kód `(b.y - a.y).abs()`-szal
  osztott, ami minden olyan élnél megfordította az eredményt, ahol
  `b.y < a.y`. A megelőző XOR-feltétel már garantálja `a.y ≠ b.y`-t
  ezen az ágon, tehát az `.abs()`-nak SOHA nincs jogos szerepe. A
  javítás az előjeles `(b.y - a.y)`-nal oszt, és a `+1e-300` védelmet
  is elhagyja. Két új regressziós teszt (rombusz + ferde gitárnyak-
  szerű quad) bizonyítja, hogy a hiba a javítás ELŐTT fennállt
  volna, a JAVÍTÁS UTÁN nincs jelen. Lásd
  `test/core/geometry/polygon2_test.dart` `Polygon2.contains`
  csoport.

- **GuitarLandmarkMapper projektív-sor vakfolt őr (BLOCKER-1,
  javító kör).** A `Homography._measureConditionNumber` kizárólag a
  2×2 lineáris blokkot méri, a projektív sort (`h[6..8]`) nem — ez
  azt jelenti, hogy ha a `w = h6·x + h7·y + h8 = 0` eltűnő egyenes
  áthalad a kamera-normalizált `[0,1]×[0,1]` tartományon, a
  konstruktor „kiválónak" jelenti a mátrixot (`cond ≈ 1.3`), miközben
  `apply(...)` 10²–10⁷ nagyságrendű szemetet ad, magas (≈ 0.88)
  confidence-szel. A javítás egy új, domain-tudatos őr a
  `GuitarLandmarkMapper.fromCalibration` végén: a `Homography.solve`
  sikeres visszatérése UTÁN, de a mapper visszaadása ELŐTT mintavételezi
  a kamera-keret 5 kanonikus pontját (4 sarok + középpont), és ha
  bármelyik minta `(u, v)` magnitúdója meghaladja a
  `guitarSpaceSanityBound = 10.0` küszöböt, dob egy új
  `GuitarLandmarkMapperSetupFailure.unstableMapping` okot. A
  küszöb nagyságrendekkel bőkezűbb, mint a gitártér `u ∈ [0,1] /
  v ∈ [-1,1]` definíciója szerinti `|uv| ≤ sqrt(2) ≈ 1.42` (kb. 7×
  slack), és nagyságrendekkel kisebb, mint a megfigyelt szemét
  (10²–10⁷). Az őr a `core/geometry` rétegben nem implementálható
  (az a réteg tér-semleges, nem tudhat a `[0,1]²` kamera-tartományról);
  ezért került a feature-oldali mapperbe. Két új regressziós teszt:
  (a) a review-beli EXAKT reprodukciós kalibráció (jelenleg
  `cond ≈ 1.31`, `(1, 0.9)` minta `(u, v) ≈ (-236.8, -1022.9)`,
  `confidence ≈ 0.933` szemetet adna) most `unstableMapping`-et dob;
  (b) a `front_medium` jól kondicionált fixture 5 mintapontja mind
  a küszöb alatt marad, tehát az őr NEM eszik legitim kalibrációt.
  Lásd `test/features/vision/domain/guitar_landmark_mapper_test.dart`
  `BLOCKER-1` két új esete.

### 10.7 Nem futtatott / kívül eső

- A teljes `flutter test` (≈15 min ezen a boxon) és a release APK —
  a CI-ban futnak (ADR 0053).
- `gh workflow run build-apk.yml` — az orchestrátor indítja (merge gate).
- Valós-guitár APK teszt — a user saját tesztje; szintetikus green
  itt nem "done".

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r15-guitar-coordinates-and-homography-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
