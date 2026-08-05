# E05-R15 — Guitar coordinate system és homography

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 15; §17.2–17.4, §18
- **Branch:** `codex/e05-r15-guitar-coordinates-and-homography`
- **Előfeltétel:** **E05-R07, E05-R10, E05-R13 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

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

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R07/R10/R13 merge; olvasd újra
> az R10 `GuitarCalibration` anchor-mezőit (normalizált tér!) és az R07
> tér-típusait. Nincs ÚJ ADR. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

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
