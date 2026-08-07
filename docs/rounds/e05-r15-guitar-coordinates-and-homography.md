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

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r15-guitar-coordinates-and-homography-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
