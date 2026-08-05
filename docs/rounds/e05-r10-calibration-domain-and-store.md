# E05-R10 — Camera és guitar calibration domain + verziózott tárolás

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 10; §13.3–13.4, §28
- **Branch:** `codex/e05-r10-calibration-domain-and-store`
- **Előfeltétel:** **E05-R08 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/calibration/camera_calibration_profile.dart",
  "lib/features/vision/domain/calibration/guitar_calibration.dart",
  "lib/features/vision/domain/calibration/calibration_validity.dart",
  "lib/features/vision/data/persistence/vision_calibration_repository.dart",
  "lib/features/vision/data/persistence/vision_calibration_codec.dart",
  "lib/features/vision/public.dart",
  "lib/core/storage/storage_keys.dart",
  "test/features/vision/domain/calibration_validity_test.dart",
  "test/features/vision/data/vision_calibration_repository_test.dart",
  "docs/rounds/e05-r10-calibration-domain-and-store.md",
]
gate_tests = [
  "test/features/vision",
  "test/core/storage",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R08 merge; olvasd újra
> `lib/core/storage/storage_keys.dart` (`ss.` névtér, `LegacyStorageKeys`),
> `storage_migrator.dart` (verziózott envelope + karantén) és egy meglévő
> verziózott repository-t (`lib/features/practice/data/`). Nincs ÚJ ADR
> (0164/0166 bővítése). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

Verziózott, migrálható **kalibrációs profil** (kamera + gitárgeometria),
explicit **érvényességi policy** és calibration quality score — raw kép nélkül.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- `lib/core/storage/storage_keys.dart`: `ss.` névtér, kulcsok egy helyen;
  `schemaVersion = 'ss.storage.schema_version'`; a régi kulcsok
  `LegacyStorageKeys`-ben, és a mozgatás **mindig migrációval** történik —
  konstans helyben átírása orphan adatot csinálna.
- `lib/core/storage/storage_migrator.dart` + `json_document_store.dart` +
  `key_value_store.dart` adják a verziózott envelope és karantén mintát.
- Az R08 már ment `ss.vision.setup_profile` + `ss.vision.camera` kulcsot —
  a kalibráció **külön** kulcs, nem ezek bővítése.

## 3. Scope

**Benne:** `CameraCalibrationProfile` (kamera-azonosító absztrakció,
orientation, zoom, setup-profil), `GuitarCalibration` (normalizált nut/bridge
anchorok, neck polygon), `CalibrationValidity` (+ invalidation reason lista),
calibration quality score, JSON codec, verziózott repository idempotens
migrációval és record-szintű karanténnal.

**Kívül — TILOS:** kalibrációs UI (R11), homography (R15), tracking (R16),
raw kép/preview mentése, más feature storage-kulcsa.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/calibration/camera_calibration_profile.dart` | ÚJ | kamera-profil |
| `.../domain/calibration/guitar_calibration.dart` | ÚJ | gitárgeometria |
| `.../domain/calibration/calibration_validity.dart` | ÚJ | érvényesség + okok |
| `.../data/persistence/vision_calibration_repository.dart` | ÚJ | verziózott tár |
| `.../data/persistence/vision_calibration_codec.dart` | ÚJ | JSON round-trip |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `lib/core/storage/storage_keys.dart` | meglévő | **csak új** `ss.vision.*` kulcs |
| `test/features/vision/*` | ÚJ | validity + repo tesztek |
| `docs/rounds/e05-r10-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; meglévő kulcs átírása; `docs/rag`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Verziózott schema + idempotens migráció.** A migráció **kétszer futtatva
   ugyanazt adja**. **NEM elfogadható:** verzió nélküli mentés, vagy „ha nem
   parse-olható, kezdjük elölről" a teljes store törlésével.
2. **Érvénytelen profil nem használható csendben.** A `load` **soha nem ad
   vissza** „majdnem jó" profilt: vagy valid, vagy explicit invalidation
   reasonnel érvénytelen. **NEM elfogadható:** null-visszatérés magyarázat nélkül.
3. **Nincs raw kép a profilban** (ADR 0166) — sem base64 preview, sem thumbnail.
   A tesztnek ezt **kimeneti szinten** kell mérnie (a szerializált JSON-ban nincs
   `image`/`png`/`jpeg`/base64-gyanús mező).
4. **Az anchorok normalizált térben** tárolódnak (R07 `NormalizedPoint`), nem
   pixelben — a kalibráció túléli a felbontásváltást. **NEM elfogadható**
   pixelkoordináta a perzisztált modellben.
5. **Record-szintű karantén:** egy sérült rekord **nem** teheti elérhetetlenné
   a többit (a repó meglévő karantén-mintája).
6. **A domain framework-mentes** — az architektúra-őr méri.

## 6. Acceptance criteria

- [ ] **Round-trip teszt:** modell → JSON → modell bit-stabil (mezőnkénti
      egyenlőség), és a JSON kulcssorrendje determinisztikus.
- [ ] **Migrációs mátrix:** hiányzó verzió (v0) / előző verzió (vN-1) /
      aktuális (vN) / **jövőbeli** (vN+1) — mind a négy cella külön teszt;
      a jövőbeli verzió **nem** olvasódik félre, hanem kontrollált setup-kérés.
- [ ] **Idempotencia:** a migráció kétszeri futtatása azonos eredményt ad.
- [ ] **Korrupció-teszt:** csonka JSON / hibás típus / degenerált polygon →
      az érintett rekord karanténba kerül, a **többi rekord olvasható marad**.
- [ ] **Validity-mátrix:** kameraváltás / orientation-váltás / zoom-változás /
      lejárt időbélyeg / degenerált geometria → mindegyikhez **saját**
      invalidation reason, és mindegyikre külön cella.
- [ ] **Privacy-snapshot teszt:** a szerializált profil kulcskészlete egy
      rögzített, elvárt halmazzal egyezik — új mező csak a snapshot frissítésével
      kerülhet be (így egy raw-kép mező nem csúszhat be észrevétlenül).
- [ ] **Valódi-sértés próba (§10):** pixelkoordináta bevezetése a modellbe →
      a normalizált-tér teszt PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/core/storage
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: round-trip, migrációs mátrix, korrupció, privacy-snapshot.
2. Domain modellek + validity.
3. Codec + repository + migráció.
4. Storage-kulcsok; gate.

## 9. Kockázatok

- **A kulcs helyben átírása** orphan adatot csinál (a repó dokumentált csapdája)
  — új kulcs + migráció az egyetlen út.
- **A „jövőbeli verzió" ág hiánya**: régi app + új adat esetén néma félreolvasás.
  A mátrix negyedik cellája ezt fogja meg.

**STOP:** raw kép mentése, pixel-anchor, meglévő kulcs átírása vagy
mércegyengítés helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r10-calibration-domain-and-store-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
