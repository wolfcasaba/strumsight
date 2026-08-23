# E10-R25 — Safety preflight és output guardrails

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 25
- **Kör-azonosító:** `E10-R25`
- **Branch:** `<motor>/e10-r25-safety-preflight-and-output-guardrails`
- **Előfeltétel:** `E10-R24` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0439` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `TutorClaimValidator`/`TutorClaim` MEGLÉVŐ `unsupportedClaimEvidence` validációs ágát — ez a kör ERRE épít a citation-ellenőrzésnél, nem talál ki új claim-sémát. Eltérésnél §0.0 brief-revízió.

**Visszakeresett előzmény:** **ADR 0135** (tutor-knowledge-governance), **ADR 0136** (tutor-knowledge-retrieval) — a `TutorClaimValidator` mögötti kötött döntések, közvetlen precedens az A2/A4 acceptance-cellákhoz.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/offline_ai/application/local_ai_safety_preflight.dart",
  "lib/features/offline_ai/application/local_ai_output_guard.dart",
  "test/features/offline_ai/safety/",
  "docs/rounds/e10-r25-safety-preflight-and-output-guardrails.md",
]
gate_tests = [
  "test/features/offline_ai/safety/",
]
native_gate = false
```

**Kockázat = high, indoklás:** ez a kör a fizikai biztonsági (fájdalom/sérülés) és a hamis-claim elleni védelmet hordozza — mindkettő a felhasználó biztonságát és a termék hitelességét közvetlenül érintő, `safety`/`privacy` kategóriájú kockázat.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

Determinisztikus safety-réteg a model request/response körül — a korlátok NEM kizárólag a modell "jó viselkedésére" épülnek.

## 2. Jelenlegi állapot — mért tények

- A `TutorClaimValidator` (Chapter 5) MÁR validálja a claim-evidence párokat — ez a kör a helyi pipeline-ba KÖTI BE ezt a validátort (a Kör 20 hibrid retrieval `chunkId`-jeivel mint elfogadható `evidenceRefs`).
- A projektben MA nincs semmilyen "scope classifier" (guitar-learning vs. unsupported request elkülönítés) — ez teljesen ÚJ.
- A Kör 21 prompt assembler biztosítja a bemeneti trust-boundary-t — ez a kör a KIMENETI oldalt védi.

## 3. Scope

**Benne van:** egyszerű, magyarázható scope classifier (guitar learning vs. unsupported request) · fájdalom/sérülés safety flow (nem diagnosztizál, javasolja a megszakítást, szakemberi segítséget ajánl tartós panasznál) · fájlrendszer/shell/credential/network tool-igény blokkolása · a response citation-ID létezésének és a claim-type megfelelésének validációja (a `TutorClaimValidator` MEGLÉVŐ mechanizmusán át) · nem támogatott mért állítás jelölése vagy eltávolítása · kritikus schema/safety hiba esetén a streamingből NEM kerül végleges válaszként a hibás blokk megjelenítésre · magyar/angol safe fallback response-ok · promptszöveg NEM tárolódik safety-review céljából consent nélkül.

**NINCS benne (tilos):**

- A `TutorClaimValidator` módosítása — csak HÍVJA.
- `docs/adr/**` — az ADR 0439-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/application/local_ai_safety_preflight.dart` | ÚJ — a kérés-oldali scope classifier + tool-igény blokkolás |
| `lib/features/offline_ai/application/local_ai_output_guard.dart` | ÚJ — a válasz-oldali citation/claim validáció |
| `test/features/offline_ai/safety/` | a §6 cellái |

**Tilos zóna:** `lib/features/ai_tutor/domain/services/tutor_claim_validator.dart` (csak HÍVJA) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0439)

### 5.1 A safety NEM kizárólag prompt-instrukció — determinisztikus, kódszintű guard minden kritikus kategóriára

A fájlrendszer/shell/credential/network tool-igény, a fájdalom/sérülés téma és a nem létező citation mind egy DETERMINISZTIKUS (nem modell-alapú) ellenőrzésen mennek át, mielőtt a válasz eléri a felhasználót.

**NEM elfogadható gyengítés:** "a system promptban már megkértük a modellt, hogy ne csinálja" — ez a SDD §14.4/25.1 explicit tiltása, a safety KÓDSZINTŰ, nem csak instrukciós.

### 5.2 Kritikus safety-violation esetén a hibás blokk NEM jelenik meg véglegesként a streamből

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Fájdalom/sérülés említése esetén a válasz NEM diagnosztizál, javasolja a megszakítást | `test/features/offline_ai/safety/pain_flow_test.dart` |
| A2 | Hamis, nem támogatott mért állítás (pl. kitalált BPM-szám) a `TutorClaimValidator`-on elakad | `test/features/offline_ai/safety/output_guard_test.dart` |
| A3 | Fájlrendszer/shell/hálózat tool-igény blokkolt, mielőtt a `TutorToolRegistry`-hez érne | `test/features/offline_ai/safety/scope_classifier_test.dart` |
| A4 | Nem létező citation-ID a válaszban elutasított | `test/features/offline_ai/safety/output_guard_test.dart` |
| A5 | Nem gitártanulási témájú kérés (pl. általános kérdés) kontrolláltan, nem hallucinált válasszal kezelt | `test/features/offline_ai/safety/scope_classifier_test.dart` |
| A6 | Magyar és angol safe fallback response mindkét nyelven létezik és lokalizált | `test/features/offline_ai/safety/fallback_response_test.dart` |
| A7 | A safety-review NEM tárol promptszöveget consent nélkül | `test/features/offline_ai/safety/output_guard_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A fájdalom-flow a system promptra bízza a helyes viselkedést, kódszintű ellenőrzés nélkül | A1 (egy adversarial teszt-prompt átcsúszik) |
| A citation-ellenőrzés nem fut a válasz minden blokkjára | A4 |
| A fájlrendszer-tool-igény csak logolva van, de nem blokkolt | A3 |
| A safety-guard promptszöveget ment egy diagnosztikai naplóba consent nélkül | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** távolítsd el a citation-létezés ellenőrzését az output guardból, adj egy nem létező `sourceId`-t tartalmazó fixture-választ, futtasd a tesztet → az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/safety
```

## 8. Implementációs sorrend

1. `local_ai_safety_preflight.dart` — scope classifier, tool-igény blokkolás.
2. `local_ai_output_guard.dart` — citation/claim validáció (a `TutorClaimValidator`-on át).
3. A fájdalom/sérülés flow.
4. Magyar/angol safe fallback response-ok.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A promptra bízott safety.** A legfontosabb architekturális kockázat — a modell nem megbízható egyetlen biztonsági rétegként (5.1).
- **A hamis citation elfogadása.** Aláásná a teljes RAG-rendszer hitelességét (A4).
- **A safety-log privacy-sértése.** Egy jóhiszemű "debug célú" naplózás sértené a §14.1/§22 tiltást (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
