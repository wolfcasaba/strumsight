# E07-R07 — Legacy Learn és Progress evidence adapterek

- **Státusz:** PLANNING (pre-flight revízió alatt 2026-08-15; kiinduló `main @ 4c770e03`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 7
- **Kör-azonosító:** `E07-R07`
- **Branch:** `<motor>/e07-r07-legacy-evidence-adapters`
- **Előfeltétel:** `E07-R06` merge-elve (SkillEstimate reducer)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0293`](../adr/0293-legacy-evidence-adapter-identity-and-mapping-contract.md)

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a TÉNYLEGES legacy
> forrásokat indítás előtt — `lib/features/learn/` lecke-modellje (difficulty,
> skill-tagek, best accuracy mezőnevei) és `lib/features/progress/` napló-modellje
> (aktív idő, session-típus). A brief §2 táblái ezekre hivatkoznak; ha a nevek
> eltérnek, §0.0 revízió, Státusz → PLANNING.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/application/port/skill_snapshot_reader.dart",
  "lib/features/practice_generator/data/adapter/legacy_lesson_catalog_adapter.dart",
  "lib/features/practice_generator/data/adapter/legacy_progress_evidence_adapter.dart",
  "lib/features/practice_generator/data/adapter/legacy_mapping_table.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/adapter/legacy_lesson_catalog_adapter_test.dart",
  "test/features/practice_generator/adapter/legacy_progress_evidence_adapter_test.dart",
  "docs/adr/0293-legacy-evidence-adapter-identity-and-mapping-contract.md",
  "docs/rounds/e07-r07-legacy-evidence-adapters.md",
]
gate_tests = [
  "test/features/practice_generator/adapter/legacy_lesson_catalog_adapter_test.dart",
  "test/features/practice_generator/adapter/legacy_progress_evidence_adapter_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

### 0.0 Pre-flight revízió (2026-08-15, `main @ 4c770e03`)

- A brief-lint jelentésben nincs B*/S* lelet. A `learn/public.dart` ténylegesen
  exportálja a `model/lesson.dart`-ot: a publikus `Lesson` `id`, `name`, `bpm`,
  `difficulty`, `beatsPerBar`, `events` és `totalBeats` mezőket adja. **Nincs
  skill-tag és nincs best-accuracy mező.** A skill-besorolás ezért kizárólag a
  kör saját, explicit `LegacySkillMappingTable`-jából jöhet; név-, akkord-,
  kategória- vagy difficulty-heurisztika tilos. A best accuracyt csak a hívó
  adhatja át explicit `LegacyLessonOutcome` bemenetként, saját stabil outcome
  ID-val és explicit időpontokkal; a belső Learn provider olvasása tilos.
- A `progress/public.dart` a `PracticeEntry`-t exportálja. Annak tényleges
  mezői `day`, `source`, `seconds`, `strokes`, `chords`, `directionAccuracy`;
  a „session-típus” a stabil `PracticeSource source`, az aktív idő a `seconds`.
  A rekordnak nincs stabil outcome-ID-ja, időbélyege (csak epoch napja), vagy
  skill-kapcsolata. Ezért a progress adapter csak egy hívó által adott
  `LegacyProgressOutcome` wrapperből állíthat elő evidence-et: benne kötelező
  a `PracticeEntry`, a cél skill ID, a stabil source outcome ID, valamint a
  `measuredAt` és `capturedAt`. Magából a `PracticeEntry`-ből ilyen adatot
  kitalálni (időből, sorrendből vagy tartalom-hashből) tilos.
- A `SkillEvidence` provenance-ja jelenleg az `EvidenceSource`,
  `sourceOutcomeId` és `measurementVersion` mezőkből áll; külön
  mapping-version mező nincs. A mapping-tábla verziója ezért az adapter által
  átadott **pozitív `measurementVersion`** lesz. A kimenet `source` értéke
  `learn`, illetve `progress`; a Progress `seconds` értéke normalizálás nélkül
  nem lehet teljesítményérték, mert az R06 reducer a performance-ot `[0,1]`-re
  clampeli. A progress adapter csak a hívó explicit, `[0,1]`-es normalizált
  performance-értékét fogadja el.
- Az új `ADR 0293` e nyilvános, explicit identity/mapping szerződést rögzíti.
  A brief `allowed_paths` listája kizárólag e kör saját ADR-artefaktumával
  bővült; a Learn/Progress feature tartalma, a domain és minden védett zóna
  változatlanul tilos.

## 1. Cél

A meglévő Learn és Progress adatokból használható skill evidence — **a
generátor domainjének szennyezése nélkül** (SDD Ch8 Kör 7).

## 2. Jelenlegi állapot — mért tények

- Az R05 `SkillEvidence`-e és a `PracticeEvidenceRepository` port kész.
- A SDD Ch8 §4.3 köti: *„A generátor domainjét nem szabad az ideiglenes
  adapterhez igazítani."* Az adapter alkalmazkodik, nem a domain.
- Az architektúra-őr (R01 óta) tiltja a generátor és más feature-ök közti
  belső importot — az adapter **csak a másik feature `public.dart`-ját**
  használhatja.

## 3. Scope

**Benne van:** `SkillSnapshotReader` port · lecke-katalógus adapter a publikus
`Lesson` és hívó által adott, identity-val ellátott outcome alapján · gyakorlási
napló adapter hívó által adott, identity- és skill-kapcsolattal ellátott wrapper
alapján · **verziózott mapping tábla** · fixture a beépített lecke-katalógushoz
· a saját ADR 0293.

**NINCS benne (tilos):** a Practice Engine katalógusa (Kör 8) · Analyze/Vision
evidence (Kör 25) · a domain módosítása az adapter kedvéért · más feature
**belső** fájljának importja · más ADR módosítása · `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `application/port/skill_snapshot_reader.dart` | **ÚJ** — a port |
| `data/adapter/legacy_lesson_catalog_adapter.dart` | **ÚJ** |
| `data/adapter/legacy_progress_evidence_adapter.dart` | **ÚJ** |
| `data/adapter/legacy_mapping_table.dart` | **ÚJ** — verziózott mapping |
| `public.dart` | a barrel bővítése |
| `test/…/adapter/*_test.dart` (2 db) | a §6 cellái |
| `docs/adr/0293-legacy-evidence-adapter-identity-and-mapping-contract.md` | **ÚJ** — explicit legacy identity/mapping határ |
| `docs/rounds/e07-r07-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/learn/**`, `lib/features/progress/**` és minden
más feature **tartalma** (olvasni a `public.dart`-jukon át igen, írni nem) ·
`lib/app/**` · `docs/adr/**` (kivéve a saját, új ADR 0293) · `docs/sdd/**` ·
`tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 Explicit mapping nélkül NINCS következtetés

Ha egy leckéhez nincs skill-mapping, az adapter **nem talál ki** skillt
heurisztikából (névhasonlóság, kategória). Ismeretlen lecke → nincs evidence,
nem „valószínűleg ez".

**NEM elfogadható gyengítés:** „a lecke címében szerepel az akkord neve, tehát
akkordváltás-evidence". Az kitalált adat, az ADR 0253 §3 tiltásának megfelelője.

### 5.2 A mapping tábla VERZIÓZOTT

A tábla pozitív verziója az evidence `measurementVersion` provenance mezője.
Egy későbbi mapping-változás így megkülönböztethető a tanuló tényleges
változásától.

### 5.3 A legacy evidence FORRÁSKÉNT jelölt és GYENGÉBB

A legacy adat forrás-megbízhatósága alacsonyabb (ADR 0261 policy) — a
`SkillEvidence.source` ezt kimondja, nem a súly rejtve.

### 5.4 Ismeretlen lecke NEM okoz összeomlást

Az adapter kihagyja, és **jelzi** (figyelmeztetés), de nem dob kivételt.

### 5.5 A mapping DETERMINISZTIKUS

Ugyanaz a legacy bemenet ugyanazt az evidence-halmazt adja, sorrendtől
függetlenül. Duplikált legacy bejegyzés az R05 dedup-kulcsán (hívó által adott
forrás outcome ID) egyszer kerül be. Egy azonosító vagy skill-kapcsolat nélküli
`PracticeEntry` figyelmeztetéssel kimarad; adapter nem szintetizál kulcsot.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Explicit mapping nélküli leckéhez NEM keletkezik evidence | `legacy_lesson_catalog_adapter_test.dart` |
| A2 | Ismeretlen lecke nem dob kivételt, csak figyelmeztetést | ugyanott |
| A3 | A mapping tábla pozitív verziója az evidence `measurementVersion` provenance-ében van | mindkét adapter-teszt |
| A4 | A legacy evidence `source`-a legacy-ként jelölt | ugyanott |
| A5 | Ugyanaz a bemenet → ugyanaz a kimenet, sorrendtől függetlenül | `legacy_progress_evidence_adapter_test.dart` |
| A6 | Duplikált legacy bejegyzés EGYSZER kerül be | ugyanott |
| A7 | Az adapter csak `public.dart`-on át ér el más feature-t | architektúra-őr + diff |
| A8 | Outcome-ID, skill-kapcsolat vagy explicit normalizált érték nélküli Progress rekord nem ad evidence-et | `legacy_progress_evidence_adapter_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Heurisztikus skill-találgatás névből | **A1** |
| Ismeretlen leckére kivétel | A2 |
| A mapping verzió nincs a provenance-ben | A3 |
| A legacy evidence ugyanolyan erős, mint a mért | A4 |
| A bemenet sorrendje számít | A5 |
| A dedup az időbélyegre épül | A6 |
| Belső import a `learn`/`progress` feature-ből | A7 |
| A Progress adapter `PracticeEntry`-ből szintetizál outcome ID-t vagy skillt | A8 |

**A mapping három kötelező cellája** (a határ: a mapping megléte):

| Cella | Bemenet | Elvárt |
|---|---|---|
| van mapping | ismert lecke-azonosító | evidence keletkezik, legacy forrásjelöléssel |
| a határon | ismert lecke, de **üres** skill-lista a mappingben | **nincs** evidence, figyelmeztetés — nem találgatás |
| nincs mapping | ismeretlen lecke-azonosító | nincs evidence, figyelmeztetés, nincs kivétel |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vezess be
névhasonlóság-alapú fallback mappinget → az **A1** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/adapter/legacy_lesson_catalog_adapter_test.dart test/features/practice_generator/adapter/legacy_progress_evidence_adapter_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `skill_snapshot_reader.dart` port.
2. `legacy_mapping_table.dart` — verziózott, explicit tábla + fixture.
3. Lecke-katalógus adapter (§5.1 tiltással).
4. Gyakorlási napló adapter.
5. Tesztek a §6.1 három mapping-cellájával.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A találgatás csábítása.** „Nyilván ez a skill" — és a rendszer olyan
  bizonyítékra tervez, ami sosem volt mérve (A1).
- **A domain idomítása.** Ha az adapter kényelmetlen, a kísértés a domaint
  átszabni. A SDD Ch8 §4.3 ezt tiltja; ilyenkor `stopped` és brief-revízió.
- **A legacy adat túlsúlyozása.** Sok régi adat elnyomhatná a keveset, de
  pontosat — a forrás-megbízhatóság (ADR 0261) ezt kezeli, ne az adapter.
- **Hiányzó legacy identitás.** A `PracticeEntry` önmagában nem outcome;
  az adapter nem gyárthat stabilnak látszó azonosítót vagy skill-kapcsolatot.

## 10. Implementation handoff — az implementer tölti ki

**Implementáció:** `application/port/skill_snapshot_reader.dart` — közös
`SkillSnapshotReader<TSnapshot>` port, `SkillSnapshotResult` (evidence +
warnings, sosem kivétel). `data/adapter/legacy_mapping_table.dart` —
`LegacyMappingTable` (pozitív `version`, explicit `entries` lista,
`skillIdsFor` `null`-t ad ismeretlen lecke-azonosítóra, üres listát ad ismert,
de skill nélküli mappingre) + a beépített `LegacyMappingTable.builtIn`.
`data/adapter/legacy_lesson_catalog_adapter.dart` — `LegacyLessonOutcome`
(hívó által adott `lesson: Lesson`, `sourceOutcomeId`, `measuredAt`,
`capturedAt`, `performance`) + `LegacyLessonCatalogAdapter`, mindig
`EvidenceSource.learn` forrással, `measurementVersion` = a mapping tábla
verziója. `data/adapter/legacy_progress_evidence_adapter.dart` —
`LegacyProgressOutcome` (a `skillId`, `sourceOutcomeId`,
`normalizedPerformance` mind nullable — a hiányos hívói bemenet
figyelmeztetéssel kimarad, sosem dob) + `LegacyProgressEvidenceAdapter`,
`EvidenceSource.progress` forrással. A `public.dart` bővítve mind a négy új
fájllal.

**Valódi-sértés próba (§6.1, A1) — ténylegesen lefuttatva:** a
`legacy_lesson_catalog_adapter.dart`-ba ideiglenesen behuzaloztam egy
név-heurisztikus fallbacket (`if (skillIds == null && outcome.lesson.name
.contains('G Major')) skillIds = ['chord.gMajor'];`) egy `'G Major Warm-Up'`
nevű, a mapping táblában NEM szereplő leckére. `flutter test
test/.../legacy_lesson_catalog_adapter_test.dart` ekkor ténylegesen PIROSAT
adott a "real-violation probe" cellára:
`Expected: empty / Actual: [Instance of 'SkillEvidence']` — a fallback
evidence-et gyártott ott, ahol nincs explicit mapping (A1 megsértve). A
fallbacket ezután eltávolítottam; `git diff` a fájlra üres (bájtra pontosan a
commitolt változat), és a teljes gate újra lezöldült (lásd alább). Ez
megerősíti, hogy a jelenlegi kódban kizárólag az explicit mapping hiánya
tartja pirosra válthatóvá az A1 cellát — nincs rejtett heurisztika.

**Gate — tényleges futás (2026-08-15, ezen a branchen):**

```
tools/round-gate.sh test/features/practice_generator/adapter/legacy_lesson_catalog_adapter_test.dart test/features/practice_generator/adapter/legacy_progress_evidence_adapter_test.dart
```

`format` ZÖLD · `analyze` ZÖLD (`No issues found!`) ·
`test .../legacy_lesson_catalog_adapter_test.dart` ZÖLD (7 teszt, `+7 All
tests passed!`) · `test .../legacy_progress_evidence_adapter_test.dart` ZÖLD
(11 teszt, `+11 All tests passed!`) · `architecture` ZÖLD (12 engedélyezett
eltérés, új nem került hozzá) · `secrets` ZÖLD · `l10n` ZÖLD.
**MINDEN GATE ZÖLD.**

`git status --short` a jelzés előtt tiszta (minden módosítás commitolva).

### 10.1 Javító kör (F1/F2, ugyanaz a Sonnet implementer) — 2026-08-15

**F1 javítás.** A `LegacyMappingTable.builtIn` a review által mért, kitalált
ID-kat (`g-major-first-strum`, `c-to-g-swap`, `d-major-basics`) valódi,
`lib/features/learn/model/lesson.dart` `Lessons.all`-ban létező ID-kra
cserélte: `first-strums` → `chord.gMajor`, `two-chord-change` →
`chord.cMajor`, `eighth-drive` → `chord.dMajor` (tábla `version: 2`). Új
teszt (`legacy_lesson_catalog_adapter_test.dart`, „builtIn mapping (review
F1)" csoport) a valódi `Lessons.all`-ból keres egy, a `builtIn` táblában
mappingelt leckét, és bizonyítja, hogy az adapter rajta keresztül tényleges
evidence-et ad — nem csak a fixture-ön.

**F2 javítás.** A mapping szerződés egy outcome → egy skill kapcsolatra
szűkült: `LegacySkillMapping.skillIds` (`List<String>`) helyett
`LegacySkillMapping.skillId` (`String?`, `null` = ismert lecke, nincs
skill-jel). Az „ismeretlen lecke" vs. „ismert lecke, üres mapping" határ
megkülönböztetéséhez (ami a régi kódban a lista üres/`null` volta volt) egy
új `LegacyMappingLookup` (`found` + `skillId`) érték-típus és
`LegacyMappingTable.lookup(lessonId)` metódus került be a
`skillIdsFor`/`skillIdFor` nullable-only visszatérés helyett. A
`LegacyLessonCatalogAdapter` így outcome-onként **legfeljebb egy**
`SkillEvidence`-et gyárt — a korábbi `for (final skillId in skillIds)` ciklus
megszűnt. Regressziós teszt (`legacy_lesson_catalog_adapter_test.dart`, „one
outcome, one skill (review F2)" csoport) az adapter kimenetét
`EvidenceAggregator.ingest` + `InMemoryPracticeEvidenceRepository` láncon át
is ellenőrzi: a tárolt evidence a várt `skillId`-val elérhető
`findByOutcomeId`-on. A `legacy_progress_evidence_adapter_test.dart` fixture
mapping-táblája ugyanerre az API-ra frissült (`skillIds: ['x']` →
`skillId: 'x'`); a Progress adapter szerződése változatlan (mindig egyetlen,
hívó által adott `skillId`).

**Gate — javító futás (2026-08-15, ugyanezen a branchen):**

```
tools/round-gate.sh test/features/practice_generator/adapter/legacy_lesson_catalog_adapter_test.dart test/features/practice_generator/adapter/legacy_progress_evidence_adapter_test.dart
```

`format` ZÖLD (2 fájl újraformázva a `dart format` első futása után, majd a
gate megismételve) · `analyze` ZÖLD (`No issues found!`) ·
`test .../legacy_lesson_catalog_adapter_test.dart` ZÖLD (9 teszt, `+9 All
tests passed!` — a korábbi 7 + az F1 + az F2 regresszió) ·
`test .../legacy_progress_evidence_adapter_test.dart` ZÖLD (12 teszt, `+12
All tests passed!`) · `architecture` ZÖLD (12 engedélyezett eltérés) ·
`secrets` ZÖLD · `l10n` ZÖLD. **MINDEN GATE ZÖLD.**

Csak az engedélyezett `legacy_mapping_table.dart`,
`legacy_lesson_catalog_adapter.dart`, a két adapter-teszt és ez a brief-fájl
módosult; a `legacy_progress_evidence_adapter.dart` implementációja
változatlan (csak a fixture-je frissült a teszben).

## 11. Review — a Claude tölti ki
