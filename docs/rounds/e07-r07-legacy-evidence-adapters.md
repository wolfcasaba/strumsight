# E07-R07 — Legacy Learn és Progress evidence adapterek

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ a31bb2b1`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 7
- **Kör-azonosító:** `E07-R07`
- **Branch:** `<motor>/e07-r07-legacy-evidence-adapters`
- **Előfeltétel:** `E07-R06` merge-elve (SkillEstimate reducer)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs (a határt az ADR 0260 már rögzíti)

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

**Benne van:** `SkillSnapshotReader` port · lecke-katalógus adapter
(difficulty, skill-tagek, legjobb pontosság) · gyakorlási napló adapter
(aktív idő, session-típus) · **verziózott mapping tábla** · fixture a beépített
lecke-katalógushoz.

**NINCS benne (tilos):** a Practice Engine katalógusa (Kör 8) · Analyze/Vision
evidence (Kör 25) · a domain módosítása az adapter kedvéért · más feature
**belső** fájljának importja · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `application/port/skill_snapshot_reader.dart` | **ÚJ** — a port |
| `data/adapter/legacy_lesson_catalog_adapter.dart` | **ÚJ** |
| `data/adapter/legacy_progress_evidence_adapter.dart` | **ÚJ** |
| `data/adapter/legacy_mapping_table.dart` | **ÚJ** — verziózott mapping |
| `public.dart` | a barrel bővítése |
| `test/…/adapter/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r07-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/learn/**`, `lib/features/progress/**` és minden
más feature **tartalma** (olvasni a `public.dart`-jukon át igen, írni nem) ·
`lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 Explicit mapping nélkül NINCS következtetés

Ha egy leckéhez nincs skill-mapping, az adapter **nem talál ki** skillt
heurisztikából (névhasonlóság, kategória). Ismeretlen lecke → nincs evidence,
nem „valószínűleg ez".

**NEM elfogadható gyengítés:** „a lecke címében szerepel az akkord neve, tehát
akkordváltás-evidence". Az kitalált adat, az ADR 0253 §3 tiltásának megfelelője.

### 5.2 A mapping tábla VERZIÓZOTT

A tábla verziója az evidence provenance-ébe kerül. Egy későbbi mapping-változás
így megkülönböztethető a tanuló tényleges változásától.

### 5.3 A legacy evidence FORRÁSKÉNT jelölt és GYENGÉBB

A legacy adat forrás-megbízhatósága alacsonyabb (ADR 0261 policy) — a
`SkillEvidence.source` ezt kimondja, nem a súly rejtve.

### 5.4 Ismeretlen lecke NEM okoz összeomlást

Az adapter kihagyja, és **jelzi** (figyelmeztetés), de nem dob kivételt.

### 5.5 A mapping DETERMINISZTIKUS

Ugyanaz a legacy bemenet ugyanazt az evidence-halmazt adja, sorrendtől
függetlenül. Duplikált legacy bejegyzés az R05 dedup-kulcsán (forrás outcome
ID) egyszer kerül be.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Explicit mapping nélküli leckéhez NEM keletkezik evidence | `legacy_lesson_catalog_adapter_test.dart` |
| A2 | Ismeretlen lecke nem dob kivételt, csak figyelmeztetést | ugyanott |
| A3 | A mapping tábla verziója az evidence provenance-ében van | mindkét adapter-teszt |
| A4 | A legacy evidence `source`-a legacy-ként jelölt | ugyanott |
| A5 | Ugyanaz a bemenet → ugyanaz a kimenet, sorrendtől függetlenül | `legacy_progress_evidence_adapter_test.dart` |
| A6 | Duplikált legacy bejegyzés EGYSZER kerül be | ugyanott |
| A7 | Az adapter csak `public.dart`-on át ér el más feature-t | architektúra-őr + diff |

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

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
