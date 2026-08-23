# E10-R20 — Hybrid retrieval, reranking és provenance

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 20
- **Kör-azonosító:** `E10-R20`
- **Branch:** `<motor>/e10-r20-hybrid-retrieval-and-provenance`
- **Előfeltétel:** `E10-R19` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0434` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "hybrid retrieval reranking deterministic score breakdown"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `TutorClaimValidator`/`TutorClaim` (`lib/features/ai_tutor/domain/services/tutor_claim_validator.dart`) TÉNYLEGES `evidenceRefs`/`unsupportedClaimEvidence` mezőit — a "provenance" ITT nem egy új `ClaimProvenance` osztály, hanem a MEGLÉVŐ claim-validációs mechanizmus kiterjesztése retrieval-forrásokra. Eltérésnél §0.0 brief-revízió.

## 0.0 Pre-flight kiegészítés — a SDD "provenance" szó ELAVULT feltevést sugall

**Nincs `ClaimProvenance` osztály a projektben** (lásd E10-R01 §0.0 pont 4). A tényleges mechanizmus `TutorClaimValidator`/`TutorClaim` (`evidenceRefs: Set<String>`) — [ADR 0135](../adr/0135-tutor-knowledge-governance.md), [ADR 0136](../adr/0136-tutor-knowledge-retrieval.md). Ez a kör a hibrid retrieval EREDMÉNYÉT úgy alakítja, hogy a `TutorSourceRef.chunkId` közvetlenül felhasználható legyen `evidenceRefs`-ként — NEM egy párhuzamos provenance-rendszert épít.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/offline_ai/application/hybrid_retrieval_service.dart",
  "lib/features/offline_ai/domain/retrieval_score_breakdown.dart",
  "local_ai/evaluation/run_retrieval_eval.py",
  "test/features/offline_ai/application/hybrid_retrieval_service_test.dart",
  "docs/rounds/e10-r20-hybrid-retrieval-and-provenance.md",
]
gate_tests = [
  "test/features/offline_ai/application/hybrid_retrieval_service_test.dart",
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

## 1. Cél

A lexical (Kör 18) és embedding (Kör 19) eredményeket determinisztikus, magyarázható pipeline egyesítse — stabil `chunkId`-vel, ami közvetlenül `TutorClaim.evidenceRefs`-ként használható.

## 2. Jelenlegi állapot — mért tények

- A Kör 18 lexical retriever és a Kör 19 vektor-index (FAKE embeddinggel) stabil kimenetet ad — ez a kör ezeket kombinálja.
- A `TutorClaimValidator` (Chapter 5) MA a `TutorClaim.evidenceRefs`-et egy MÁR LÉTEZŐ forrás-halmazzal veti össze — ez a kör garantálja, hogy a retrieval eredményének `chunkId`-je ugyanabban a formátumban van, amit a validator elfogad.

## 3. Scope

**Benne van:** hibrid score normalizálás és konfigurálható súlyozás (lexical + embedding + skill/evidence alignment boost − duplicate/stale penalty) · chunk-szám és összes token-budget korlátozás · determinisztikus reranking (generatív reranker NEM kötelező) · debug módban score-breakdown + index-verzió minden eredményhez · nem létező vagy nem approved forrás SOSEM kerülhet promptba · retrieval evaluation report (recall@k, MRR, citation coverage).

**NINCS benne (tilos):**

- A `TutorClaimValidator` módosítása — ez a kör csak KOMPATIBILIS kimenetet termel hozzá.
- `docs/adr/**` — az ADR 0434-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/application/hybrid_retrieval_service.dart` | ÚJ — a kombinálás és reranking |
| `lib/features/offline_ai/domain/retrieval_score_breakdown.dart` | ÚJ — a magyarázható score-komponensek |
| `local_ai/evaluation/run_retrieval_eval.py` | ÚJ — recall@k/MRR/citation coverage |
| `test/features/offline_ai/application/hybrid_retrieval_service_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/ai_tutor/domain/services/tutor_claim_validator.dart` (csak KOMPATIBILIS formátumot termel, nem módosítja) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0434)

### 5.1 Csak `approvalStatus == approved` chunk kerülhet a végső eredménybe — a Kör 18 szűrése ITT MÉG EGYSZER, defenzíven érvényesül

**NEM elfogadható gyengítés:** annak feltételezése, hogy a Kör 18 lexical retriever és a Kör 19 vektor-index MÁR kiszűrte a nem approved chunköket, ezért itt nem kell újra ellenőrizni — a hibrid réteg a SAJÁT, független szűrését is elvégzi (defense in depth), mert egy jövőbeli, közvetlenül a nyers indexet lekérdező hívó megkerülhetné az egyik szűrőréteget.

### 5.2 A reranking determinisztikus, ugyanaz a bemenet mindig ugyanazt a sorrendet adja

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Csak lexical eredmény esetén (embedding hiba) a hibrid szolgáltatás helyesen degradál | `hybrid_retrieval_service_test.dart` |
| A2 | Csak embedding eredmény esetén (lexical üres) helyesen degradál | `hybrid_retrieval_service_test.dart` |
| A3 | Egyenlő score esetén (tie) determinisztikus, stabil sorrend | `hybrid_retrieval_service_test.dart` |
| A4 | Duplikált chunk (ugyanaz a `chunkId` mindkét forrásból) egyszer szerepel a végeredményben | `hybrid_retrieval_service_test.dart` |
| A5 | Nem approved chunk a hibrid rétegen is KIESIK, még ha valamiért bekerülne a bemenetbe | `hybrid_retrieval_service_test.dart` |
| A6 | A chunk-szám és token-budget korlát betartva | `hybrid_retrieval_service_test.dart` |
| A7 | A reranking determinisztikus (ugyanaz a bemenet → ugyanaz a kimenet, ismételt futtatással ellenőrizve) | `hybrid_retrieval_service_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hibrid réteg feltételezi, hogy minden bemeneti chunk approved, nem szűr újra | A5 |
| A duplicate-penalty hiányzik, egy chunk kétszer szerepel | A4 |
| A reranking egy nem-stabil sort (pl. hash-alapú, nem determinisztikus tie-break) használ | A7 |
| A token-budget korlát nincs érvényesítve, túl sok chunk kerül a kimenetbe | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** távolítsd el a hibrid rétegbeli defenzív `approvalStatus` szűrést, adj be egy nem approved chunköt közvetlenül a bemeneti listába, futtasd a tesztet → az **A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/application/hybrid_retrieval_service_test.dart
```

## 8. Implementációs sorrend

1. `retrieval_score_breakdown.dart` — a magyarázható score-komponensek modellje.
2. `hybrid_retrieval_service.dart` — normalizálás, súlyozás, defenzív approval-szűrés, duplicate/stale penalty.
3. Determinisztikus reranking, stabil tie-break.
4. Chunk-szám/token-budget korlát.
5. `run_retrieval_eval.py` — recall@k, MRR, citation coverage FIXTURE corpuson.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A defenzív szűrés elhagyása "mert már úgyis szűrve van".** Pontosan ez a fajta feltételezés vezetett a projekt más részein már mért hibákhoz (rétegek közötti hallgatólagos bizalom) — ez a kör explicit UJRA szűr (5.1, A5).
- **A nem-determinisztikus tie-break.** Instabil citation-sorrendet eredményezne felhasználói szemszögből (A7).
- **A duplikáció.** Redundáns, helypazarló promptot eredményezne, csökkentve a hasznos context-arányt (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
