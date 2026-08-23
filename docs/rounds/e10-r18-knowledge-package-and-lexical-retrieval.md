# E10-R18 — Knowledge package és lexical retrieval

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 18
- **Kör-azonosító:** `E10-R18`
- **Branch:** `<motor>/e10-r18-knowledge-package-and-lexical-retrieval`
- **Előfeltétel:** `E10-R17` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0432` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/ai_tutor/domain/models/tutor_source_ref.dart` (`TutorSourceRef`, `chunkId => '$sourceId#${chunkIndex + 1}'`) TÉNYLEGES mezőit — az ÚJ `LocalKnowledgeChunk` erre épít forrás-azonosításra, nem talál ki új sémát. Eltérésnél §0.0 brief-revízió.

## 0.0 Pre-flight kiegészítés — a SDD "nincs retrieval" feltevése TÉVES, de a MEGLÉVŐ rendszer más csomag-életciklusra épül

**A projektben MÁR LÉTEZIK egy működő, tesztelt lexikai retrieval** Chapter 5-ből:
`lib/features/ai_tutor/data/knowledge/knowledge_retriever.dart` (`KnowledgeRetriever`,
token-súlyozott cím/tartalom-score, skill/locale/difficulty szűrők,
`TutorSourceRef` kimenettel) + `knowledge_index.dart` + `asset_knowledge_repository.dart`
(**ADR 0136**, E04-R07). A pontszámítás NEM klasszikus BM25 (nincs IDF-tag), hanem
egy egyszerűbb, cím/tartalom-súlyozott token-overlap — a brief korábbi
"BM25" megfogalmazása pontatlan volt, javítva.

**Miért kell mégis ÚJ kód ebben a körben, nem a meglévő bővítése:** az
`AssetKnowledgeRepository` `rootBundle.loadString`-ot használ
(`assets/tutor_knowledge` — APK-build-időben BEÉGETETT, statikus asset).
A SDD §12/§18 Offline AI knowledge package-e ezzel szemben LETÖLTHETŐ,
ALÁÍRT, VERZIÓZOTT, futásidőben FRISSÍTHETŐ csomag — teljesen más
életciklus, amit a `rootBundle`-alapú repository nem tud kiszolgálni.
Ez a kör ezért egy ÚJ `lexical_retriever.dart`-ot ad az `offline_ai`
feature-ben, de:
- a KIMENETI azonosítót (`chunkId`) a MEGLÉVŐ `TutorSourceRef` konvencióval
  konzisztensen definiálja;
- a pontszámítás ALGORITMUSÁT a bevált `KnowledgeRetriever` cím/tartalom-
  súlyozott mintáját követve tervezi (NEM egy önkényes új BM25-implementációt
  kitalálva) — a §8.3 pontban a `title_token_weight`/`content_token_weight`
  konstansok a meglévő `KnowledgeRetriever.titleTokenWeight`/
  `contentTokenWeight` értékeit veszik referenciának.
- a Chapter 5 `AssetKnowledgeRepository`/`KnowledgeRetriever` VÁLTOZATLAN
  marad — ez a kör NEM helyettesíti, egy PÁRHUZAMOS, downloadable-package-
  kompatibilis utat épít.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "lexical retrieval knowledge base source approval"` → **ADR 0136** (Deterministic offline tutor knowledge retrieval, E04-R07, bm25#3 emb#2) — a fenti pontos precedens.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/offline_ai/domain/local_knowledge_chunk.dart",
  "lib/features/offline_ai/data/lexical_retriever.dart",
  "local_ai/knowledge/manifest_schema.md",
  "local_ai/knowledge/fixtures/",
  "test/features/offline_ai/data/lexical_retriever_test.dart",
  "docs/rounds/e10-r18-knowledge-package-and-lexical-retrieval.md",
]
gate_tests = [
  "test/features/offline_ai/data/lexical_retriever_test.dart",
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

Teljesen offline alap-retrieval, ami kis erőforrású (Tier 1) eszközön is működik, embedding modell nélkül — magyarázható, source-ID-t megőrző, cím/tartalom-súlyozott token-score kereséssel (a MEGLÉVŐ `KnowledgeRetriever` bevált mintája, letölthető-csomag-kompatibilis útra vive).

## 2. Jelenlegi állapot — mért tények

- A `TutorSourceRef` (Chapter 5) adja a chunk-azonosítás sémáját (`sourceId#chunkIndex+1`) — ez a kör ezt HASZNÁLJA, nem talál ki párhuzamos azonosítót.
- A `KnowledgeRetriever`/`KnowledgeIndex` (Chapter 5, ADR 0136) MÁR MEGVAN, de `AssetKnowledgeRepository`-n (statikus, build-időben beégetett `rootBundle` asset) keresztül tölt — lásd §0.0. Ez a kör NEM ezt módosítja, hanem egy PÁRHUZAMOS, letölthető-csomag-kompatibilis utat épít, ugyanazt a pontszámítási MINTÁT követve.
- A Kör 8 aláírt-csomag mintáját (`ModelPackageManifest`) a knowledge package KÜLÖN manifesttel követi (SDD §18.1: "definiáld a signed knowledge package manifestet külön a model package-től") — ez a kör a manifest SÉMÁJÁT dokumentálja, a valódi aláírás-ellenőrzés a Kör 8 verifierét ÚJRAHASZNÁLJA (nem ír új crypto-kódot).

## 3. Scope

**Benne van:** `LocalKnowledgeChunk` séma (chunkId, contentVersion, language, title, body, skillTags, difficultyRange, sourceId, approvalStatus, checksum) · verziózott chunk-parser és lexical index build/load · magyar nyelvi normalizálás (diakritika-megőrzéssel) és kontrollált tokenizálás · cím/tartalom-súlyozott, magyarázható lexical score (a `KnowledgeRetriever` mintája) · skill-tag/difficulty/locale/source filterek · atomikus, rollback-képes index-update · magyar ragozott alakokra és gitárszakkifejezésekre retrieval fixture.

**NINCS benne (tilos):**

- Embedding-alapú retrieval — ez Kör 19 dolga.
- Új aláírás-ellenőrző kód — a Kör 8 verifierét hívja.
- `docs/adr/**` — az ADR 0432-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/domain/local_knowledge_chunk.dart` | ÚJ — a chunk-séma |
| `lib/features/offline_ai/data/lexical_retriever.dart` | ÚJ — cím/tartalom-súlyozott token-score kereső, a `KnowledgeRetriever` mintáján |
| `local_ai/knowledge/manifest_schema.md` | ÚJ — a knowledge package manifest dokumentációja |
| `local_ai/knowledge/fixtures/` | ÚJ — magyar/angol retrieval fixture-ök |
| `test/features/offline_ai/data/lexical_retriever_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/core/security/**` (csak importálja a Kör 8 verifierét) · `lib/features/ai_tutor/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0432)

### 5.1 A promptba KIZÁRÓLAG jóváhagyott (`approvalStatus`) csomagból származó chunk kerülhet

Community poszt, komment, tetszőleges weboldal, felhasználói fájl, modell saját válasza vagy nyers DSP dokumentáció SOSEM válhat automatikus retrieval-forrássá (SDD §12.1).

**NEM elfogadható gyengítés:** egy "ideiglenes" retrieval-forrás hozzáadása egy még nem jóváhagyott chunk-halmazból "gyorsabb teszteléshez" — az `approvalStatus` szűrés a retriever BELSEJÉBEN fut, nem a hívó felelőssége.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Magyar ragozott alak (pl. "akkordváltásnál") megtalálja a releváns chunköt | `lexical_retriever_test.dart` |
| A2 | Angol kifejezés ugyanígy megtalálható | `lexical_retriever_test.dart` |
| A3 | Skill-tag/difficulty/locale filter szűkíti a találatokat | `lexical_retriever_test.dart` |
| A4 | Nem jóváhagyott (`approvalStatus != approved`) chunk sosem kerül a találatok közé | `lexical_retriever_test.dart` |
| A5 | Ismeretlen locale kontrolláltan kezelt (üres találat vagy explicit hiba, nem crash) | `lexical_retriever_test.dart` |
| A6 | Index-update közbeni hiba esetén a RÉGI index marad használható (rollback) | `lexical_retriever_test.dart` |
| A7 | Korrupt chunk az indexelés során kihagyott, nem állítja meg a teljes buildet | `lexical_retriever_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A tokenizálás eltávolítja az ékezeteket normalizálás közben, elrontva a magyar egyezést | A1 |
| A retriever nem szűri az `approvalStatus`-t | A4 |
| Az index-update félbeszakadás esetén használhatatlan indexet hagy | A6 |
| Egy korrupt chunk elhasalja a teljes index-buildet | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** távolítsd el az `approvalStatus` szűrést a retrieverből, adj hozzá egy nem-approved chunköt a fixture-höz, futtasd a tesztet → az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/data/lexical_retriever_test.dart
```

## 8. Implementációs sorrend

1. `LocalKnowledgeChunk` séma, `TutorSourceRef`-kompatibilis `chunkId`.
2. Magyar/angol nyelvi normalizálás, diakritika-megőrzéssel.
3. `lexical_retriever.dart` — cím/tartalom-súlyozott token-score, filterek, `approvalStatus` szűrés.
4. Atomikus index-update + rollback.
5. Fixture-ök magyar ragozott alakokra és szakkifejezésekre.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A diakritika-vesztés a normalizálásban.** Alapvetően rontaná a magyar retrieval minőségét (A1).
- **Az approvalStatus szűrés kihagyása.** Nem jóváhagyott tartalom kerülhetne a promptba (A4, 5.1).
- **Az index-update félbeszakadása.** Ha nem atomikus, a felhasználó egy használhatatlan indexszel maradna frissítés közben (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
