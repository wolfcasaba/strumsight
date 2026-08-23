# E10-R19 — Helyi embedding runtime és index (fake embedding réteg)

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 19
- **Kör-azonosító:** `E10-R19`
- **Branch:** `<motor>/e10-r19-local-embedding-runtime-and-index`
- **Előfeltétel:** `E10-R18` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0433` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "embedding vector index dimension normalization fallback"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 18 `LocalKnowledgeChunk` sémáját — a vektor-index ugyanazokra a chunk-azonosítókra épül. Eltérésnél §0.0 brief-revízió.

## 0.0 Hardver/scope-korlát — miért PENDING (narrowed)

A SDD Kör 19 valós, mobilra exportálható embedding modell KIVÁLASZTÁSÁT is előírja (5.1: "Válassz kis, mobilra exportálható multilingual embedding candidate-et") — ez a batch-prep pillanatában NEM dönthető el (nincs valós bake-off, ugyanaz az ok, mint a generatív runtime-nál, Kör 6/7). Ez a brief ezért az embedding runtime KONTRAKTUSÁT és a vektor-index infrastruktúrát szállítja egy DETERMINISZTIKUS FAKE embedding-függvénnyel (pl. karakterek hash-eléséből képzett rögzített dimenziójú vektor) — a valós embedding modell kiválasztása egy jövőbeli, emberi döntést igénylő follow-up (nincs `hold` erre a körre, mert a KONTRAKTUS és a fallback-logika teljesen valós modell nélkül is helyesen implementálható és tesztelhető).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/offline_ai/data/local_embedding_runtime.dart",
  "lib/features/offline_ai/data/vector_index.dart",
  "test/features/offline_ai/data/vector_index_test.dart",
  "docs/rounds/e10-r19-local-embedding-runtime-and-index.md",
]
gate_tests = [
  "test/features/offline_ai/data/vector_index_test.dart",
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

Opcionális szemantikus retrieval kontraktusa és a vektor-index infrastruktúrája, a valós embedding modell kiválasztásától függetlenül tesztelhető — a lexical retrieval (Kör 18) MINDIG elérhető marad fallbackként.

## 2. Jelenlegi állapot — mért tények

- A Kör 18 `LocalKnowledgeChunk` sémája a bemenete a vektor-indexnek — ez a kör ugyanazokra a chunk-azonosítókra épít.
- A projektben MA nincs semmilyen embedding-kód — ez teljesen ÚJ, és a §0.0 szerint FAKE embedding-függvénnyel indul.

## 3. Scope

**Benne van:** `LocalEmbeddingRuntime` adapter interfész, KÜLÖN a generatív runtime-tól · DETERMINISZTIKUS FAKE embedding implementáció a tesztekhez (rögzített dimenzió, rögzített normalizálás) · vektor-index (verzió, dimenzió, normalization policy, checksum) · batch index build + incremental update · thermal/battery-korlátozott háttér-indexelés (policy-szinten, natív thermal jelzés nélkül — lásd Kör 12 mintáját) · embedding-hiba esetén KÖTELEZŐ lexical fallback · felhasználói conversation vagy Community tartalom SOSEM embedelhető automatikusan.

**NINCS benne (tilos):**

- Valódi embedding modell kiválasztása vagy letöltése.
- `docs/adr/**` — az ADR 0433-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/data/local_embedding_runtime.dart` | ÚJ — adapter interfész + FAKE implementáció |
| `lib/features/offline_ai/data/vector_index.dart` | ÚJ — a vektor-index |
| `test/features/offline_ai/data/vector_index_test.dart` | a §6 cellái |

**Tilos zóna:** `android/**` · `lib/features/offline_ai/data/lexical_retriever.dart` (Kör 18 fájlja, csak IMPORTÁLJA fallback célra) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0433)

### 5.1 Az embedding retrieval OPCIONÁLIS capability — a lexical retrieval sosem függ tőle

Embedding-timeout, hiányzó modell vagy dimenzió-mismatch esetén a rendszer KÖTELEZŐEN lexical fallbackre vált, sosem ad üres eredményt vagy hibát a felhasználónak.

**NEM elfogadható gyengítés:** egy "ha nincs embedding, akkor nincs retrieval" ág — a lexical retrieval (Kör 18) MINDIG elérhető, függetlenül az embedding állapotától.

### 5.2 Felhasználói conversation vagy Community tartalom SOSEM kerül automatikus embedelésre

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A vektor-index dimenziója validált — mismatch esetén explicit hiba | `vector_index_test.dart` |
| A2 | A normalizálás konzisztens (minden vektor egységnyi normájú, ha a policy ezt írja elő) | `vector_index_test.dart` |
| A3 | Index-verzió mismatch esetén a régi index NEM keveredik az újjal | `vector_index_test.dart` |
| A4 | Embedding-timeout esetén a hívó lexical fallbacket kap, nem üres eredményt | `vector_index_test.dart` |
| A5 | A vektor-index build sosem kap bemenetként `TutorConversation`-t vagy Community-tartalmat típusszinten (nincs ilyen paraméter az API-ban) | `test/tooling/architecture_dependency_offline_ai_test.dart` (bővítve) |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A dimenzió-ellenőrzés hiányzik, egy rossz méretű vektor bekerül az indexbe | A1 |
| Az embedding-timeout üres eredményt ad fallback helyett | A4 |
| Az index-build API elfogad egy `TutorConversation` paramétert | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** távolítsd el a fallback-hívást az embedding-timeout ágból, futtasd a tesztet → az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

### 6.2 Küszöb-hármas — embedding-timeout (konfigurálható konstans, alapérték 500 ms)

| Cella | Mért időtartam | Elvárt |
|---|---|---|
| alatta | 499 ms | Embedding eredmény felhasználva |
| rajta | 500 ms | Timeout (a küszöb a timeout-oldalé, inkluzív) → lexical fallback |
| fölötte | 501 ms | Timeout → lexical fallback |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/data/vector_index_test.dart
```

## 8. Implementációs sorrend

1. `local_embedding_runtime.dart` — interfész + determinisztikus FAKE implementáció.
2. `vector_index.dart` — verzió, dimenzió, normalizálás, checksum.
3. A lexical fallback bekötése timeout/hiba esetére.
4. Az architektúra-guard bővítése (nincs `TutorConversation`/Community típus az API-ban).
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A fallback kihagyása.** Ha egy embedding-hiba üres retrievalt eredményezne, a tutor válasza megalapozatlanná válna (A4, 5.1).
- **A FAKE embedding valós modellre cserélésének elfelejtése.** A HANDOFF-nak és egy jövőbeli follow-up brief pre-flightjának explicit rögzítenie kell, hogy a production embedding modell kiválasztása még nyitott.
- **A conversation-embedelés kísértése.** "Jobb personalizáció" ürüggyel a felhasználói beszélgetés indexelése sértené az 5.2 invariánst.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
