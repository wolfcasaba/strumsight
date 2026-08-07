# E05-R10 — Camera és guitar calibration domain + verziózott tárolás

- **Státusz:** PLANNING (pre-flight §0.0 lezárva 2026-08-07, kód olvasva: origin/main @ `539d346`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 10; §13.3–13.4, §28
- **Branch:** `codex/e05-r10-calibration-domain-and-store`
- **Előfeltétel:** **E05-R08 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (a
  pipeline-prompt E05-R10 routing-táblája `minimax`-ot ír elő — a brief eredeti
  „Codex (Terra)" jelölése felülírva, lásd §0.0 R7)

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

> ⚠ **Pre-flight LEZÁRVA (§0.0, R1–R7):** `origin/main` @ `539d346` (HEAD ==
> origin/main, nincs drift, nincs párhuzamos inflight kör) + E05-R08 merge
> megerősítve. Két javítás (elavult ADR-hivatkozás; implementer-motor
> felülírva `minimax`-ra) és öt megerősítés/pontosítás — egyik sem igényel ÚJ
> ADR-t. Részletek §0.0. PLANNING→dispatch.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Mérve `origin/main` @ `539d346` (E05-R09 után), orchestrátor Claude Sonnet 5,
2026-08-07.** Előfeltétel (E05-R08 merge) megerősítve, working tree tiszta,
nincs párhuzamos inflight kör (`.pipeline/inflight/` csak ennek a körnek a
markerét tartalmazza). Hét mért tétel — két javítás, öt megerősítés/
pontosítás —, egyik sem igényel ÚJ ADR-t.

**R1 — ADR-hivatkozás elavult (javítva).** A pre-flight callout és az §5.3.
döntés „ADR 0166"-ra, a fejléc „0164"-re hivatkozott. `ls docs/adr | grep
'0164\|0166'` üres — az E05-R01 az eredeti `0161–0166` blokkot `0178–0183`-ra
számozta át. A két döntés ma [`ADR 0181` — „Vision manual calibration
fallback"](../adr/0181-vision-manual-calibration-fallback.md) (a kézi
kalibráció a production út — pontosan ennek a körnek az infrastruktúrája) és
[`ADR 0183` — „Vision no-raw-frame persistence"](../adr/0183-vision-no-raw-frame-persistence.md)
(nincs raw kép a perzisztált profilban). Mindkét hivatkozás javítva a §5.3-ban
és a fejlécben; a bővítés célja változatlan, nincs ÚJ ADR.

**R2 — megerősítve, egy release-mód figyelmeztetéssel.** A `NormalizedPoint`
pontosan úgy létezik, ahogy a brief állítja:
`lib/core/camera/camera_coordinate_space.dart:73`, `core/camera/`-ban (nem
feature-kódban), tehát közvetlenül importálható a domainbe. **DE** a
tartományellenőrzése (`x∈[0,1]`, `y∈[0,1]`) kizárólag `assert`-tel történik
(`camera_coordinate_space.dart:75-76`), ami **release buildben lefut nélkül
marad** — azonos osztály, mint az R07 review carried-forward MAJOR-ja
(`docs/reviews/e05-r07-frame-transform-and-overlay-coordinates-security.md`:
„assert-only validáció", kötelező R13/R15/R24 előtt). A 6. acceptance-cella
(degenerált polygon →
karantén) ezért **nem** támaszkodhat a `NormalizedPoint` konstruktorára: a
`vision_calibration_codec.dart`-nak a meglévő
`lib/core/foundation/json_validation.dart` explicit helpereit kell használnia
(`requireDouble(json, field, min: 0, max: 1)` mintára — lásd a fájl teljes
API-ját), ugyanúgy, ahogy minden más perzisztált modell teszi
(`test/core/storage/persisted_record_validation_test.dart` precedens). Ez
biztosítja, hogy egy tartományon kívüli/degenerált koordináta release
buildben is `JsonRecordException`-t dobjon, ne csendben építsen érvénytelen
objektumot.

**R3 — megerősítve: a „jövőbeli verzió" ág precedense már létezik.** A
migrációs mátrix 4. cellája (vN+1 → kontrollált setup-kérés, nem néma
félreolvasás) nem új mintát igényel:
`lib/core/storage/json_document_store.dart:140-144`
(`JsonDocumentStore._decodeEnvelope`) már pontosan ezt teszi a dokumentum-
burok szintjén — `version > documentSchemaVersion` → `_markCorrupt(raw,
'future_version')`, sosem dob és sosem olvas félre. Az új
`vision_calibration_codec.dart`/`vision_calibration_repository.dart` ugyanezt
az idiómát kövesse a saját séma-verziójára, ne találjon ki másikat.

**R4 — pontosítás: a „record-szintű karantén" a repó KÉT különböző mintája
közül melyiket jelenti.** A repóban ma két, egymástól eltérő korrupció-kezelés
él: (a) **dokumentum-szintű, bájt-megőrző karantén**
(`JsonDocumentStore._corrupt` → `StorageKeys.quarantineOf(key)`, a teljes
dokumentum kerül külön kulcs alá, ha a felső szintű JSON nem dekódolható); (b)
**rekord-szintű, napló-alapú kihagyás** (`JsonCollectionStore.read()`: egy
rekord, amelynek `fromJson`-ja `JsonRecordException`-t dob, kimarad a listából
egy `storage.document.record_skipped` logüzenettel, a bájtjai nem
maradnak meg). A brief 4. acceptance-cellája („csonka JSON / hibás típus /
degenerált polygon → az érintett rekord karanténba kerül, a többi rekord
olvasható marad") a **(b) mintát** írja elő rekord-granularitáson — ez a
meglévő `JsonCollectionStore` + `requireX`-helperek kombinációjával
közvetlenül megvalósítható (pontosan úgy, ahogy a `practice`/`songs`/
`setlists` dokumentumok teszik), **nem** igényel új, bájt-megőrző per-record
quarantine-kulcsot. A „csonka JSON" eset (a teljes dokumentum nem
dekódolható) az (a) mintán fut — ez a repository két szintje, nem egy.

**R5 — megerősítve: a „setup-profil" mező a meglévő, négyértékű
`VisionSetupProfile`-ra hivatkozik.**
`lib/features/vision/domain/vision_setup_profile.dart:6-10` —
`leftHandFocus`/`rightHandFocus`/`fullUpperBody`/`practiceBalanced`. Az SDD
§13.2 hat profilt sorol fel; a `songPerformance`/`experimentalFretboard` az
E05-R08 pre-flight §0.0 (5) pontja szerint explicit deferred. A
`CameraCalibrationProfile` ezt a meglévő enumot használja változatlanul — új
érték hozzáadása ebben a körben scope-on kívüli.

**R6 — megerősítve: a Validity-mátrix öt cellája az SDD §13.4 hét
kiváltójának tudatosan szűkített, ma elérhető részhalmaza.** Az SDD §13.4
hét invalidation-triggert sorol fel; a brief acceptance #5 öt cellát kér
(kameraváltás/orientation/zoom/lejárt időbélyeg/degenerált geometria). A
hiányzó kettő ma nem mérhető: „tracking confidence tartósan alacsony" élő
sessiont és tracking-et igényel (R16, ebben a körben explicit **TILOS**);
„felhasználó új hangszert választ" egy `Instrument`-azonosító domain-fogalmat
igényelne, ami **nem létezik** (`grep -rn "class Instrument\|enum
Instrument" lib/` üres). A hetedik („app verzió/séma breaking változás") nem
a `CalibrationValidity` dolga — azt a **migrációs mechanizmus** (acceptance
#2, R3 fent) fedi, külön rétegen. A brief öt cellája tehát a helyes, ma
elérhető metszet — nem hiányos mérce.

**R7 — implementer-motor felülírva (javítva).** A brief fejléce „Codex
(Terra)"-t jelölt implementerként. A pipeline-prompt E05-R10 routing-táblája
(`.pipeline/prompt-E05-R10-20260807T034419.md` §0) explicit `minimax`-ot ír
elő ehhez a futáshoz — ez a friss, konkrét dispatch-utasítás (AGENTS.md §2
elsőbbségi lista 1–2. pontja) a brief saját, korábban írt javaslatával szemben.
A fejléc `MiniMax M3`-ra javítva; a dispatch a §1.1 nevesített-motor útvonalon
megy (`docs/execution/engine-registry.tsv` → `minimax` → `claude` harness →
`tools/mm-round.sh`).

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
3. **Nincs raw kép a profilban** (ADR 0183) — sem base64 preview, sem thumbnail.
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
