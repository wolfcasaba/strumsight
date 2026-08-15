# E07-R05 — SkillEvidence normalizálás és evidence repository

- **Státusz:** PLANNING (pre-flight rev. 2026-08-15, `main @ c4497773`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 5
- **Kör-azonosító:** `E07-R05`
- **Branch:** `<motor>/e07-r05-skill-evidence-normalisation`
- **Előfeltétel:** `E07-R04` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0260`](../adr/0260-skill-evidence-privacy-and-deduplication.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R02–R04 tényleges
> kimenetét. Mérd meg a projekt **naplózási mintáját**
> (`grep -rln "AppLogger\|debugPrint\|logger" lib/core/`), mert a §5.4
> redakciós szabály erre épül. Eltérésnél §0.0 revízió, Státusz → PLANNING.

### 0.0 Pre-flight revízió (2026-08-15)

- A mért `main @ c4497773`-en a naplózási standard `lib/core/logging/app_logger.dart`
  `AppLogger`: strukturált `event + fields`, a hívóoldal nem megbízható a
  redakcióra, és a release-default `NoopAppLogger`. `LogRedactor` a `pcm`,
  `audio`, `wav`, `clip` és más érzékeny kulcsokat is teljesen redaktálja.
- Az A5-öt ezért az `EvidenceAggregator`-hoz adott, tesztben gyűjthető
  `AppLogger`-rel kell mérni. Az aggregátor csak stabil outcome-azonosítót és
  discomfort-kategóriát adhat mezőként; a self-report szabad szövege sem
  eseményben, sem mezőben, sem kivételben nem szerepelhet. A default logger
  `const NoopAppLogger()`; a domain továbbra is Flutter-, clock- és logolás-
  független.
- A `docs/adr/0260-…` már elfogadott és a tilos zónában van; ez a kör nem
  ír új ADR-t és nem módosítja a meglévőt. Az eredetileg kimért `46338f48`
  baseline helyett a jelen revízió célbázisa `c4497773`.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/skill_evidence.dart",
  "lib/features/practice_generator/domain/repository/practice_evidence_repository.dart",
  "lib/features/practice_generator/application/service/evidence_aggregator.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/evidence/skill_evidence_test.dart",
  "test/features/practice_generator/evidence/evidence_aggregator_test.dart",
  "test/features/practice_generator/evidence/evidence_repository_fake_test.dart",
  "docs/rounds/e07-r05-skill-evidence-normalisation.md",
]
gate_tests = [
  "test/features/practice_generator/evidence/evidence_aggregator_test.dart",
  "test/features/practice_generator/evidence/skill_evidence_test.dart",
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

A különböző mérési források közös, **confidence-aware** evidence formába
rendezése (SDD Ch8 Kör 5).

## 2. Jelenlegi állapot — mért tények

### 2.1 A források, amikből evidence lesz

Learn (lecke-eredmények), Progress (gyakorlási napló), Analyze V2
(elemzési metrikák — **shadow-only**, minden flag OFF), és a tanuló saját
jelzései (kényelmetlenség). A **konkrét adapterek a Kör 7-8 dolga**; ez a kör
a közös formát és a tárolót építi.

### 2.2 Az Analyze V2 nem élő — legacy adapteren át lát

A GOV-30c óta a V2 lánc futtatható, de minden flagje OFF. A SDD Ch8 §4.3
tiltása érvényes: **a generátor domainjét nem szabad az ideiglenes
adapterhez igazítani.**

### 2.3 Adatvédelmi kiindulás: a dokumentum sosem hordoz nyers médiát

Az ADR 0254 §2 rögzítette az elemzésre: a PCM soha nem lesz dokumentum. Ez a
kör ugyanezt viszi tovább az evidence-re — **nyers audio/videó nem része a
modellnek**.

## 3. Scope

**Benne van:**

1. `SkillEvidence` + provenance modell (forrás, mérési verzió, időpont,
   confidence, `validUntil`).
2. **Deduplikáció** source outcome ID alapján.
3. Recency és elévülés kezelése.
4. **Performance evidence** és **discomfort self-report** SZÉTVÁLASZTVA.
5. `PracticeEvidenceRepository` port + **in-memory fake**.
6. Bounded query API skill és időtartomány szerint.

**NINCS benne (tilos):**

- Skill-becslés, súlyozás, reducer — az a Kör 6.
- Konkrét legacy adapterek — azok a Kör 7-8.
- **Nyers audio/videó bármilyen formában** (A1).
- Flutter import, `DateTime.now()`, `Random` a domainben.
- Más `lib/features/**`, `lib/app/**`, `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/skill_evidence.dart` | **ÚJ** — evidence + provenance |
| `domain/repository/practice_evidence_repository.dart` | **ÚJ** — port + in-memory fake |
| `application/service/evidence_aggregator.dart` | **ÚJ** — dedup, elévülés, bounded query |
| `public.dart` | a barrel bővítése |
| `test/…/evidence/*_test.dart` (3 db) | a §6 cellái |
| `docs/rounds/e07-r05-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/**` · minden más `lib/features/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0260)

### 5.1 Nyers média SOHA nem kerül az evidence-be

Sem minta, sem képkocka, sem fájlútvonal a nyers felvételhez. Az evidence
**származtatott mérőszámokat** hordoz, plus a forrás azonosítóját.

**NEM elfogadható gyengítés:** „csak egy rövid részlet a hibás ütemről".
Az evidence perzisztálódik és exportálható.

### 5.2 A deduplikáció kulcsa a FORRÁS outcome ID-ja

Ugyanaz a gyakorlás nem kerülhet be kétszer, akkor sem, ha két adapter is
látja. A kulcs a forrás azonosítója, nem az időbélyeg vagy a tartalom-hash.

### 5.3 A discomfort NEM átlagolódik a performance-ba

A kényelmetlenség önálló jelzés, saját skálán. Ha beleátlagolódna a
teljesítmény-pontszámba, egy fájdalmas gyakorlás „gyenge teljesítménynek"
látszana, és a rendszer **többet** gyakoroltatna belőle.

**NEM elfogadható gyengítés:** közös `score` mező forrás-címkével.

### 5.4 Érzékeny szöveg SOHA nem kerül naplóba

A tanuló szabad szöveges megjegyzése (pl. fájdalom leírása) nem naplózható.
A napló azonosítót és kategóriát írhat, tartalmat nem.

### 5.5 Jövőbeli és érvénytelen időbélyeg KONTROLLÁLT

Jövőbeli mérési időpont, negatív időtartam, `validUntil < measuredAt` →
hiba, nem csendes elfogadás vagy korrekció.

### 5.6 Az elévült evidence NEM tűnik el, csak elveszti a súlyát

Az elévülés a **lekérdezésnél** dől el (`validUntil`, recency), a tárolóból
nem törlünk automatikusan. A Kör 6 reducerének kell látnia, hogy volt régi
adat — az ADR 0256 „megváltoztathatatlan múlt" elvének folytatása.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | **Nincs nyers média** az evidence-ben (típusszinten sem) | `skill_evidence_test.dart` + a szerializált JSON vizsgálata |
| A2 | Ugyanaz a source outcome ID kétszer → EGY evidence | `evidence_aggregator_test.dart` |
| A3 | Két különböző forrás ugyanarról a gyakorlásról → EGY evidence | `evidence_aggregator_test.dart` |
| A4 | Discomfort külön mezőben, nem a performance-ban | `skill_evidence_test.dart` |
| A5 | Érzékeny szöveg nem kerül naplóba | `evidence_aggregator_test.dart` — gyűjtő logger, redakciós cella |
| A6 | Jövőbeli / érvénytelen időbélyeg kontrollált hiba | `skill_evidence_test.dart` |
| A7 | A confidence a `[0,1]` tartományban marad | `skill_evidence_test.dart` — property-jellegű cella |
| A8 | Elévült evidence lekérdezéskor esik ki, a tárolóból NEM törlődik | `evidence_repository_fake_test.dart` |
| A9 | A bounded query tiszteletben tartja a skill- és időhatárt | `evidence_repository_fake_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Fájlútvonal a nyers felvételhez az evidence-ben | **A1** (a JSON-vizsgálat) |
| A dedup kulcsa az időbélyeg | A2/A3 |
| Discomfort beleátlagolva a performance-ba | **A4** |
| A szabad szöveg naplózva | **A5** |
| Jövőbeli időbélyeg csendben „most"-ra javítva | A6 |
| A confidence normalizálás nélkül | A7 |
| Az elévült evidence törlése a tárolóból | **A8** |

**Az elévülés három kötelező cellája** (a határ: `validUntil`):

| Cella | Bemenet | Elvárt |
|---|---|---|
| érvényes | lekérdezés `validUntil` ELŐTT | benne van a találatban |
| a határon | lekérdezés pontosan `validUntil`-kor | **benne van** (a határ inkluzív) |
| elévült | lekérdezés `validUntil` UTÁN | nincs a találatban, de a tárolóban MEGVAN |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írd bele a
tanuló szabad szövegét a naplóba → az **A5** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/evidence/evidence_aggregator_test.dart test/features/practice_generator/evidence/skill_evidence_test.dart test/features/practice_generator/evidence/evidence_repository_fake_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `skill_evidence.dart` — modell, provenance, validáció (§5.1, §5.3, §5.5).
2. `practice_evidence_repository.dart` — port + in-memory fake.
3. `evidence_aggregator.dart` — dedup, elévülés, bounded query, redakció.
4. Tesztek a §6.1 három elévülés-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „csak egy kis részlet" csábítása.** Az evidence perzisztálódik és
  exportálható — a nyers média bekerülése adatvédelmi incidens (A1).
- **A közös `score` mező.** Egyszerűbb modell, és a fájdalmat gyengeséggé
  fordítja: a rendszer többet gyakoroltatna abból, ami fáj (A4).
- **A napló.** A hibakeresés kedvéért a szabad szöveg naplózása kézenfekvő,
  és pont a legérzékenyebb adatot viszi ki (A5).
- **Az elévült adat törlése.** „Takarításnak" hat, de elveszi a reducer
  lehetőségét, hogy lássa: volt régi mérés (A8).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
