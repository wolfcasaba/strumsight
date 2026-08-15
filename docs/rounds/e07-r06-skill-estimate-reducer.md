# E07-R06 — SkillEstimate reducer és konfliktuskezelés

- **Státusz:** **PLANNING** (pre-flight lezárva 2026-08-15, kód újramérve:
  `main @ 17670d4f` — a §2 mért állítások [`SkillEvidence` mezői: `source`,
  `confidence`, `validUntil`, külön `discomfort` mező; a
  `PracticeEvidenceRepository` port aláírása] a jelen kódban egyeznek, nincs
  §0.0 revízió; előre megírva 2026-08-15, kód olvasva: `main @ a31bb2b1`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 6
- **Kör-azonosító:** `E07-R06`
- **Branch:** `<motor>/e07-r06-skill-estimate-reducer`
- **Előfeltétel:** `E07-R05` merge-elve (SkillEvidence)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0261`](../adr/0261-skill-estimate-bounded-influence-and-unknown-state.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R05 tényleges
> `skill_evidence.dart` mezőit (confidence, recency, `validUntil`, forrás,
> discomfort külön mezője) és a repository port aláírását. Eltérésnél §0.0
> revízió, Státusz → PLANNING.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/skill_estimate.dart",
  "lib/features/practice_generator/domain/policy/evidence_weight_policy.dart",
  "lib/features/practice_generator/application/service/skill_estimate_reducer.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/skill_estimate/skill_estimate_test.dart",
  "test/features/practice_generator/skill_estimate/skill_estimate_reducer_test.dart",
  "test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart",
  "docs/rounds/e07-r06-skill-estimate-reducer.md",
]
gate_tests = [
  "test/features/practice_generator/skill_estimate/skill_estimate_reducer_test.dart",
  "test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart",
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

Több evidence-ből **stabil**, trendet és bizonytalanságot hordozó skill
snapshot (SDD Ch8 Kör 6).

## 2. Jelenlegi állapot — mért tények

- Az R05 `SkillEvidence`-e hordozza a forrást, a confidence-et, a recencyt és
  a `validUntil`-t, és a **discomfort külön mezőben** van (ADR 0260 §2).
- Az elévült evidence **nem törlődik** a tárolóból (ADR 0260 §5) — a reducer
  látja, hogy volt régi mérés.
- A determinizmus kötelező (ADR 0255 §1): a reducer tiszta függvény, injektált
  idővel, `Random` nélkül.

## 3. Scope

**Benne van:** `SkillEstimate` modell (érték, bizonytalanság, trend, „ismeretlen"
állapot), `EvidenceWeightPolicy` (forrás-megbízhatóság, confidence, recency,
minta-szám), a reducer (súlyozás, outlier- és konfliktus-detektálás, bounded
trend), és egy ember által olvasható evidence-összefoglaló DTO.

**NINCS benne (tilos):** prioritás-motor, jelölt-választás, terv (Kör 12-től) ·
konkrét adapterek (Kör 7-8) · Flutter import, `DateTime.now()`, `Random` ·
más `lib/features/**`, `lib/app/**`, `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/skill_estimate.dart` | **ÚJ** — becslés + bizonytalanság + trend + ismeretlen |
| `domain/policy/evidence_weight_policy.dart` | **ÚJ** — a súlyozás konfigja |
| `application/service/skill_estimate_reducer.dart` | **ÚJ** — a reducer |
| `public.dart` | a barrel bővítése |
| `test/…/skill_estimate/*_test.dart` (3 db) | a §6 cellái |
| `docs/rounds/e07-r06-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/**` · más `lib/features/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0261)

### 5.1 Egyetlen evidence hatása FELÜLRŐL KORLÁTOZOTT

Egy gyakorlás **nem ugrathat több szintet**. A cap a policy explicit
paramétere, nem a súlyozás mellékhatása.

**NEM elfogadható gyengítés:** „elég kicsi súly, úgyis korlátoz". A cap
kimondott, mérhető korlát legyen.

### 5.2 Az „ismeretlen" NEM gyengeség

Ha egy skillre nincs (érvényes) evidence, a becslés **`unknown`**, nem
alacsony érték. A kettő összemosása azt jelentené, hogy a rendszer a soha nem
mért készséget gyakoroltatná legtöbbet.

**NEM elfogadható gyengítés:** `0.0` default érték `unknown` helyett.

### 5.3 A konfliktus MAGAS bizonytalanságot ad, nem átlagot

Ellentmondó evidence (pl. egy kiugró jó és több gyenge) esetén a becslés
bizonytalansága **nő** — nem egyszerűen a közepét vesszük.

### 5.4 A discomfort NEM megy a teljesítmény-értékbe

Az ADR 0260 §2 folytatása: a kényelmetlenség önálló jelként megy tovább, és a
későbbi körökben a nehézség **csökkentése** felé hat.

### 5.5 A reducer determinisztikus

Ugyanaz az evidence-halmaz ugyanazt a becslést adja. A bemenet sorrendje sem
számíthat — a reducer rendez, mielőtt súlyoz.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ugyanaz a bemenet → ugyanaz a becslés, a SORRENDTŐL függetlenül | `skill_estimate_reducer_test.dart` |
| A2 | Egyetlen session nem ugrathat több szintet (explicit cap) | `evidence_weight_policy_test.dart` |
| A3 | Ismételt azonos evidence nem szorozza a hatást | `skill_estimate_reducer_test.dart` |
| A4 | Konfliktus → magasabb bizonytalanság | `skill_estimate_reducer_test.dart` |
| A5 | **Nincs evidence → `unknown`**, nem alacsony érték | `skill_estimate_test.dart` |
| A6 | Elévült evidence súlya csökken, de a tény látszik | `skill_estimate_reducer_test.dart` |
| A7 | A discomfort nem keveredik a teljesítmény-értékbe | `skill_estimate_test.dart` |
| A8 | Az érték és a bizonytalanság a `[0,1]` tartományban marad | property-jellegű cella |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Nincs explicit cap, csak kis súly | **A2** |
| `unknown` helyett `0.0` | **A5** |
| Konfliktus → egyszerű átlag | A4 |
| A bemenet sorrendje számít | A1 |
| Az elévült evidence teljesen eltűnik | A6 |
| Discomfort beleátlagolva | A7 |
| Normalizálás nélküli súlyösszeg | A8 |

**Az evidence-mennyiség három kötelező cellája** (a határ: az első érvényes mérés):

| Cella | Bemenet | Elvárt |
|---|---|---|
| nincs adat | nulla érvényes evidence | **`unknown`**, nem 0.0 |
| a határon | pontosan EGY evidence | érték születik, de **magas bizonytalansággal** és a cap alatt |
| sok adat | sok konzisztens evidence | érték + **alacsony** bizonytalanság |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld az `unknown`
ágat `0.0`-ra → az **A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/skill_estimate/skill_estimate_reducer_test.dart test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart test/features/practice_generator/skill_estimate/skill_estimate_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `skill_estimate.dart` — az `unknown` állapottal együtt.
2. `evidence_weight_policy.dart` — explicit cap, forrás-megbízhatóság, recency.
3. `skill_estimate_reducer.dart` — rendezés, súlyozás, outlier, konfliktus, trend.
4. Tesztek a §6.1 három evidence-mennyiség cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az `unknown` „kényelmes" nullája.** Egy szám mindig egyszerűbb, mint egy
  külön állapot — és a soha nem mért készséget tenné a leggyakoroltatottá (A5).
- **A cap elhagyása.** A súlyozás önmagában „úgyis korlátoz", amíg egy nagyon
  magabiztos forrás meg nem jelenik (A2).
- **A sorrend-függés.** Lebegőpontos összegzésnél észrevétlen; a determinizmust
  rontja el (A1).

## 10. Implementation handoff — az implementer tölti ki

### Implementáció

- `lib/features/practice_generator/domain/model/skill_estimate.dart`: immutable
  `SkillEstimate` unknown/null performance állapottal, bounded ismert értékkel
  és bizonytalansággal, trenddel, valamint privacy-safe `EvidenceSummary` DTO-val.
- `lib/features/practice_generator/domain/policy/evidence_weight_policy.dart`:
  explicit `singleEvidenceInfluenceCap`, determinisztikus source/confidence/
  recency/sample-count súlyozás és stale-dekálás.
- `lib/features/practice_generator/application/service/skill_estimate_reducer.dart`:
  rendezett, outcome-ID szerinti deduplikált reducer; konzervatív baseline-
  frissítés, konfliktus miatti uncertainty-emelés, stale állapot és bounded trend.
- `lib/features/practice_generator/public.dart`: a három új publikus contract exportja.
- `test/features/practice_generator/skill_estimate/`: A1–A8 tesztek, a három
  evidence-mennyiség cella, explicit cap, stale, discomfort-szeparáció és bounds.

### Futtatott ellenőrzések

- RED (TDD): a három új tesztfájl production contract nélkül fordítási hibával
  leállt (hiányzó `SkillEstimate`, `EvidenceWeightPolicy`, `SkillEstimateReducer`);
  ezután a célzott futás **14/14 passed**.
- `dart format lib/features/practice_generator/domain/model/skill_estimate.dart lib/features/practice_generator/domain/policy/evidence_weight_policy.dart lib/features/practice_generator/application/service/skill_estimate_reducer.dart lib/features/practice_generator/public.dart test/features/practice_generator/skill_estimate/skill_estimate_test.dart test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart test/features/practice_generator/skill_estimate/skill_estimate_reducer_test.dart`
  — 7 fájl formázva, majd a gate-ben **1525 files (0 changed)**.
- `tools/round-gate.sh test/features/practice_generator/skill_estimate/skill_estimate_reducer_test.dart test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart test/features/practice_generator/skill_estimate/skill_estimate_test.dart`
  — format zöld; analyze: `No issues found`; a három célzott teszt zöld;
  architecture, secrets és l10n zöld. A gate strukturált eredménye:
  `{"outcome":"pass","exit_code":0,"failed_step":null}`.

### Valódi-sértés próba

- Az `SkillEstimate._unknown` ágát ideiglenesen `level = 0` értékre cseréltem.
  A `flutter test test/features/practice_generator/skill_estimate/skill_estimate_test.dart`
  futásban az A5 piros lett: `Expected: null`, `Actual: <0.0>`.
  Ezután visszaállítottam a helyes `level = null` implementációt, és a teljes
  round gate zöld lett.

### Eltérések és nem futtatott ellenőrzések

- Eltérés nincs a brief scope-jához képest.
- A teljes Flutter suite, friss randomizált property gate és APK-build nem lokális
  implementer-feladat; ezek a CI/orchestrátor merge-kapui.

## 11. Review — a Claude tölti ki
