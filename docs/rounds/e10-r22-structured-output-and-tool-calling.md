# E10-R22 — Structured output és local tool calling

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 22
- **Kör-azonosító:** `E10-R22`
- **Branch:** `<motor>/e10-r22-structured-output-and-tool-calling`
- **Előfeltétel:** `E10-R21` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0436` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/ai_tutor/domain/tools/tutor_tool_registry.dart` (`TutorToolRegistry.execute()`, `schemasForTurn()`) és a `lib/features/ai_tutor/application/orchestration/action_confirmation_service.dart` (`ActionConfirmationService.propose()`) TÉNYLEGES API-ját. Eltérésnél §0.0 brief-revízió.

**Visszakeresett előzmény:** a `TutorToolRegistry`/`ActionConfirmationService` MÁR ismert, kódból mért ADR-jei — **ADR 0133** (tool-confirmation döntés), **ADR 0139** (propose→preview→confirm mechanika), **ADR 0287** (no-automatic-tool-execution) — közvetlen precedens az 5.1/5.2 kötött döntésekhez; nem kellett új RAG-keresés, mert ezek a §0.0 saját grounding-kutatásából már azonosítottak.

## 0.0 Pre-flight kiegészítés — a SDD "confirmation coordinator" nem létező névre hivatkozik

**Nincs "Chapter 5 confirmation coordinator" osztály.** A tényleges mechanizmus `ActionConfirmationService` (propose→preview→confirm, `clientActionId` idempotencia) — [ADR 0133](../adr/0133-ai-tutor-tool-confirmation.md), [ADR 0139](../adr/0139-ai-tutor-action-proposal-confirmation.md), [ADR 0287](../adr/0287-no-automatic-tool-execution-in-the-tutor.md). A "tool registry" pedig a MÁR LÉTEZŐ `TutorToolRegistry` (`readLocal`/`computeLocal` permission-osztályok). **Ez a kör a HELYI structured-output parsert adja, ami a `TutorToolRegistry.execute()`-be és az `ActionConfirmationService.propose()`-ba illeszti be a helyi modell tool-draftjait — nem hoz létre párhuzamos registry-t vagy confirmation-mechanizmust.**

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/offline_ai/application/local_structured_output_parser.dart",
  "lib/features/ai_tutor/application/local_tool_call_adapter.dart",
  "local_ai/evaluation/run_tool_eval.py",
  "test/features/offline_ai/application/local_structured_output_parser_test.dart",
  "test/features/ai_tutor/application/local_tool_call_adapter_test.dart",
  "docs/rounds/e10-r22-structured-output-and-tool-calling.md",
]
gate_tests = [
  "test/features/offline_ai/application/local_structured_output_parser_test.dart",
  "test/features/ai_tutor/application/local_tool_call_adapter_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** egyik `allowed_paths` sem egyezik szó szerint a `high_risk_path_fragments` listával, de a kör közvetlenül a `TutorToolRegistry.execute()`-hez és az `ActionConfirmationService`-hez kapcsolódik — egy hibás implementáció jogosulatlan állapotmódosító műveletet engedhetne meg megerősítés nélkül, ami az `authorization` kategóriával azonos kockázat.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

Csak megbízható structured-output capability esetén engedhető tool-draft, a MEGLÉVŐ `TutorToolRegistry`+`ActionConfirmationService` teljes schema+confirmation pipeline-ján át.

## 2. Jelenlegi állapot — mért tények

- `TutorToolRegistry.execute(TutorToolRequest) → Future<AppResult<TutorToolResult>>` MÁR LÉTEZIK, `readLocal`/`computeLocal` permission-nal — ez a kör ezt HÍVJA, nem duplikálja.
- `ActionConfirmationService.propose(TutorActionProposal, {required context}) → ActionConfirmation` MÁR LÉTEZIK — a helyi modell tool-draftja EZEN át kap preview+confirmation-t, ugyanúgy, mint a cloud tutor.
- A Kör 15 `RuntimeCapabilities` (Kör 2 definiálta, Kör 7 tölti fel valós adattal) mondja meg, támogat-e a runtime constrained/JSON-decodingot.

## 3. Scope

**Benne van:** Chapter 5 response envelope helyi parsere (a §13.2 SDD tool-output envelope formátum) · grammar/JSON constrained generation használata, HA a runtime támogatja (`RuntimeCapabilities` flag) · ha NEM támogatja, a tool calling feature-flaggel TILTOTT, amíg az evaluation nem igazolja a parseres megoldást · tool név/argumentum/schema-verzió/confirmation-flag validáció · ismeretlen mező/enum kontrollált kezelése · tool exact-match és negative corpus evaluation · a tool NEM execute-olódik a stream callbacken belül · minden tool draft `ActionConfirmationService.propose()`-on át jelenik meg previewként.

**NINCS benne (tilos):**

- A `TutorToolRegistry` vagy az `ActionConfirmationService` MÓDOSÍTÁSA — csak HÍVJA őket.
- `docs/adr/**` — az ADR 0436-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/application/local_structured_output_parser.dart` | ÚJ — a Kör 22 SDD §13.2 envelope-parser |
| `lib/features/ai_tutor/application/local_tool_call_adapter.dart` | ÚJ — a helyi tool-draft → `ActionConfirmationService.propose()` híd |
| `local_ai/evaluation/run_tool_eval.py` | ÚJ — exact-match/negative corpus evaluation |
| `test/features/offline_ai/application/local_structured_output_parser_test.dart` | a §6 cellái |
| `test/features/ai_tutor/application/local_tool_call_adapter_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/ai_tutor/domain/tools/tutor_tool_registry.dart` (csak HÍVJA) · `lib/features/ai_tutor/application/orchestration/action_confirmation_service.dart` (csak HÍVJA) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0436)

### 5.1 A tool NEM execute-olódhat a modell-output stream callbackjén belül

A tool-draft parsolása és a `execute()` hívása MINDIG a stream befejezése (vagy egy explicit tool-draft esemény) UTÁN, egy külön aszinkron lépésben történik — sosem szinkron a token-callback belsejében.

**NEM elfogadható gyengítés:** egy "gyorsítás" célú optimalizáció, ami a tool-hívást elindítja, amint a JSON felismerhetőnek tűnik a streamben, mielőtt a teljes struktúra validálva lenne.

### 5.2 Capability hiányában a tool calling feature-flaggel tiltott, nem "próbálkozik és néha sikerül"

Ha a `RuntimeCapabilities` nem jelez megbízható constrained/JSON-decodingot, a `localAiToolCallingEnabled` flag (Kör 1) hatástalanítja a tool-draft parsolást — a modell CSAK szöveges választ adhat.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Érvényes tool-draft a `TutorToolRegistry.execute()`-ig jut, `ActionConfirmationService.propose()`-on át | `local_tool_call_adapter_test.dart` |
| A2 | Ismeretlen tool-név elutasított, `execute()` nem hívódik | `local_tool_call_adapter_test.dart` |
| A3 | Malformed JSON kontrolláltan kezelt, nem crash | `local_structured_output_parser_test.dart` |
| A4 | Több egyidejű tool-hívás egy válaszban mindegyik külön preview-t kap | `local_tool_call_adapter_test.dart` |
| A5 | A modell által javasolt `confirmed: true` flag figyelmen kívül hagyva — a confirmation MINDIG a `ActionConfirmationService` valódi felhasználói interakciójától függ | `local_tool_call_adapter_test.dart` |
| A6 | Argumentum-injekciós kísérlet (pl. path traversal egy fájlnév-argumentumban) a domain-validáción elakad | `local_tool_call_adapter_test.dart` |
| A7 | `RuntimeCapabilities.toolCalling == false` esetén a parser egyáltalán nem próbál tool-draftot kinyerni | `local_structured_output_parser_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A tool a stream callbackben, validáció előtt execute-olódik | A1 (a preview lépés kimarad) |
| A modell `confirmed: true` mezője közvetlenül átmegy a `propose()` `context`-jébe, kihagyva a valódi felhasználói megerősítést | A5 |
| A capability-flag hiányában is megpróbálja parse-olni a tool-JSON-t | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd, hogy a modell `confirmed: true` mezője közvetlenül a `propose()` elé kerüljön felhasználói interakció nélkül, futtasd a tesztet → az **A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/application/local_structured_output_parser_test.dart test/features/ai_tutor/application/local_tool_call_adapter_test.dart
```

## 8. Implementációs sorrend

1. `local_structured_output_parser.dart` — a §13.2 envelope parsolása, capability-gate.
2. `local_tool_call_adapter.dart` — híd a `TutorToolRegistry`/`ActionConfirmationService` felé.
3. Tool exact-match és negative corpus.
4. `run_tool_eval.py`.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A modell-oldali "confirmed" flag becsapása.** A legsúlyosabb kockázat: ha a modell kimenete önmagában elég lenne a megerősítéshez, az teljesen kiiktatná a felhasználói kontrollt (A5, 5.1's testvér-elve).
- **A stream-közbeni tool-execution.** Race-eket és félig validált argumentumok végrehajtását kockáztatná (5.1).
- **A capability-gate megkerülése.** Egy nem megbízható runtime-on "megpróbálkozás" hamis pozitív tool-hívásokat eredményezne (A7, 5.2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
