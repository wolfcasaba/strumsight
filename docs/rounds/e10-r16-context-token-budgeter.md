# E10-R16 — Context token budgeter és prompt compiler

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 16
- **Kör-azonosító:** `E10-R16`
- **Branch:** `<motor>/e10-r16-context-token-budgeter`
- **Előfeltétel:** `E10-R15` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0430` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "token budget truncation priority safety preserved"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 15 `model_chat_template.dart` tokenizáló API-ját — a budgeter PONTOS token countot vár tőle, nem becslést. Eltérésnél §0.0 brief-revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/offline_ai/application/context_token_budgeter.dart",
  "lib/features/offline_ai/application/local_prompt_compiler.dart",
  "test/features/offline_ai/context_token_budgeter_property_test.dart",
  "docs/rounds/e10-r16-context-token-budgeter.md",
]
gate_tests = [
  "test/features/offline_ai/context_token_budgeter_property_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** egyik `allowed_paths` sem egyezik szó szerint a `high_risk_path_fragments` listával, de ez a kör a SDD egyik legkritikusabb biztonsági invariánsát hordozza: a safety policy és a current user message SOHA nem vágódhat le csendben — egy hibás truncation a §14.2 prompt injection boundary-t vagy a §5.3 fail-closed elvet sértené közvetve.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A prompt mindig beleférjen a modell contextjébe; a legfontosabb (safety + user message) tartalom SOHA nem vész el a truncation során.

## 2. Jelenlegi állapot — mért tények

- A Kör 15 tokenizáló API-ja PONTOS token countot ad — ez a kör erre épít, nem becslésre.
- A `TutorContextSnapshot` (Chapter 5, MÁR LÉTEZIK) `estimatedSizeBytes`/`canonicalJson` mezői BYTE-alapú méretet adnak, NEM token countot — ez a kör a Kör 15 tokenizerével számol PONTOS tokent, a `TutorContextSnapshot` byte-mérete csak tájékoztató, nem használható limitként.

## 3. Scope

**Benne van:** pontos token-count alapú context budgeter · output reserve + template overhead foglalás · prioritási sorrend: safety > user message > evidence > tool schema > retrieval > memory > history · deterministic truncation, chunk-level kiválasztással · túl hosszú current user message esetén kontrollált hiba vagy explicit rövidítési flow · debug context report (komponens token count + eldobási reason, szöveg NÉLKÜL) · property teszt több ezer random komponens-kombinációval.

**NINCS benne (tilos):**

- A tényleges retrieval vagy tool-schema tartalom előállítása — ez Kör 18-22 dolga; ez a kör OPAK komponenseket kap bemenetként (méret + prioritás-cimke), nem generálja a tartalmukat.
- `docs/adr/**` — az ADR 0430-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/application/context_token_budgeter.dart` | ÚJ — a budgeter |
| `lib/features/offline_ai/application/local_prompt_compiler.dart` | ÚJ — a prompt-összeállítás |
| `test/features/offline_ai/context_token_budgeter_property_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/offline_ai/data/**` (a retrieval/RAG implementáció Kör 18+ dolga) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0430)

### 5.1 A safety policy és a current user message SOHA nem truncálódik csendben

Ha a kettő összesített mérete önmagában meghaladná a limitet, a compiler KONTROLLÁLT hibát ad (`ContextOverflowFailure`), NEM vágja le egyiket sem csendben.

**NEM elfogadható gyengítés:** egy "arányos csökkentés minden komponensre" stratégia, ami a safety policy szövegét is arányosan rövidítené — a safety policy MÉRETE fix, csak a KEVÉSBÉ prioritásos komponensek (history, majd memory, majd retrieval) csökkenthetők vagy dobhatók el, ebben a sorrendben.

### 5.2 A truncation determinisztikus és magyarázható

Ugyanaz a komponens-halmaz mindig ugyanazt a truncation-eredményt adja; a debug report megmondja, melyik komponens miért esett ki, de a report NEM tartalmazza a komponensek tényleges szövegét.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A compiled prompt SOHA nem lépi túl a deklarált token-limitet | `context_token_budgeter_property_test.dart` — property |
| A2 | Az output reserve mindig foglalt, sosem "elfogyaszthatja" a bemeneti komponens-tér | `context_token_budgeter_property_test.dart` |
| A3 | A current user message MINDIG megmarad, akkor is, ha minden más komponens kiesik | `context_token_budgeter_property_test.dart` — property |
| A4 | A safety policy MINDIG megmarad | `context_token_budgeter_property_test.dart` — property |
| A5 | Túl hosszú current user message esetén kontrollált hiba, nem csendes vágás | `context_token_budgeter_property_test.dart` |
| A6 | A tool schema opcionálisan kieshet, ha nem releváns a turnhoz | `context_token_budgeter_property_test.dart` |
| A7 | A debug report nem tartalmaz komponens-szöveget, csak méretet és reason-t | `context_token_budgeter_property_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A truncation arányosan csökkenti a safety policyt is | A4 |
| A budgeter nem foglal output reserve-et, a teljes limitet bemenetre engedi | A2 |
| A current user message a history-val EGYÜTT esik ki, ha túl sok komponens van | A3 |
| A debug report a komponens teljes szövegét is kiírja | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** módosítsd a prioritási sorrendet úgy, hogy a safety policy a history UTÁN kerül csak be, futtasd a property tesztet → az **A4** cellának PIROSNAK kell lennie (a property teszt talál egy olyan bemenetet, ahol a safety policy kiesik) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/context_token_budgeter_property_test.dart
```

## 8. Implementációs sorrend

1. A prioritási sorrend enum + komponens-modell (opak méret+prioritás, tartalom nélkül a budgeterben).
2. `context_token_budgeter.dart` — a truncation algoritmus, output reserve foglalással.
3. `local_prompt_compiler.dart` — a végleges prompt összeállítása a megmaradt komponensekből.
4. A debug report (szöveg nélkül).
5. Property teszt: több ezer random komponens-kombináció, safety+user-message invariáns.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A safety policy csendes csorbulása.** A legsúlyosabb lehetséges hiba ebben a körben — közvetve a teljes prompt injection boundary-t gyengítené (A4, 5.1).
- **A property teszt gyenge bemenet-tere.** Ha a generátor nem fedi le a "minden komponens egyszerre túl nagy" szélsőséges esetet, a hiba rejtve maradna.
- **A tokenizer-függőség pontossága.** Ha a Kör 15 tokenizere pontatlan becslést adna (ne adjon — lásd Kör 15 §5.1), ez a kör hibásan számolna — ezért ez a kör a Kör 15 API-ját MOCK-olja a property tesztben egy determinisztikus, ismert token-számláló függvénnyel, nem valós tokenizerrel.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
