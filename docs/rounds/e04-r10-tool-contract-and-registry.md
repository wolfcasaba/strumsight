# E04-R10 — Tutor Tool contract és read-only registry

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 10; §35
- **Branch:** `codex/e04-r10-tool-contract-and-registry`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R02 + E04-R05 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/tools/tutor_tool.dart",
  "lib/features/ai_tutor/domain/tools/tutor_tool_registry.dart",
  "lib/features/ai_tutor/domain/tools/tutor_tool_request.dart",
  "lib/features/ai_tutor/domain/tools/tutor_tool_result.dart",
  "lib/features/ai_tutor/application/tools/read_only_tutor_tools.dart",
  "lib/features/ai_tutor/application/tools/fake_tutor_tool_registry.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/domain/tutor_tool_registry_test.dart",
  "test/features/ai_tutor/application/read_only_tutor_tools_test.dart",
  "docs/rounds/e04-r10-tool-contract-and-registry.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
  "test/features/ai_tutor/application",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R02/R05 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 **0133**
> tool-confirmation bővítése). `rg`: az `AppResult`/`AppFailure` mai alakja
> (`lib/core/`) — a tool-exception AppFailure-ré alakul. PREPARED→PLANNING,
> brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

Typed, **allowlistelt**, tesztelhető tool-rendszer — **kizárólag read-only és
lokális compute** műveletekkel; nincs arbitrary file/network/code tool.

## 2. Jelenlegi állapot

- Nincs tutor tool-rendszer (SDD §3.2/11). `AppResult`/`AppFailure` a hibalapú
  contract-precedens (Epic 1).
- R05 után van redaktált context, amit a compute-toolok fogyasztanak.

## 3. Scope

**Benne:** `TutorTool` (permission + schema), verziózott `TutorToolRegistry`, request/
result modellek, kezdeti **read-only + compute** toolok, explicit input-validáció,
output provenance + size-limit report, unknown-tool fail-closed, turn-specifikus
allowlist, tool-exception → AppFailure, fake registry.

**Kívül — TILOS:** bármely write/launch tool (az R11 action-rendszeré), arbitrary
file/network/code tool, UI, cloud.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/tools/tutor_tool.dart` | ÚJ | permission + schema |
| `.../domain/tools/tutor_tool_registry.dart` | ÚJ | verziózott registry |
| `.../domain/tools/tutor_tool_request.dart` | ÚJ | request modell |
| `.../domain/tools/tutor_tool_result.dart` | ÚJ | result + provenance |
| `.../application/tools/read_only_tutor_tools.dart` | ÚJ | kezdeti read-only toolok |
| `.../application/tools/fake_tutor_tool_registry.dart` | ÚJ | orchestration teszt |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/{domain,application}/*` | ÚJ | registry/tool tesztek |
| `docs/rounds/e04-r10-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Read-only scope:** a kezdeti tool-készlet kizárólag olvasás/lokális compute;
   **arbitrary file/network/code tool TILOS** (ADR 0133). **NEM elfogadható:** „csak
   egy" hálózati vagy fájl-tool.
2. Unknown tool **fail-closed**; a model csak **turn-specifikus** allowlistet kap.
3. Minden output provenance + size-limit report; tool-exception → **AppFailure**
   (nem nyers throw).
4. A schema **providerfüggetlen**.

## 6. Acceptance criteria

- [ ] Registry-version; unknown-tool fail-closed; invalid-input reject; permission-mismatch;
      **oversized output** (alatta/rajta/fölötte a size-limit mátrix); tool-timeout.
- [ ] Provenance minden outputon; **no secret output** teszt.
- [ ] Fake registry orchestration-tesztekhez; tool-exception → AppFailure.
- [ ] **Security allowlist:** nincs arbitrary file/network/code tool — teszt bizonyítja;
      reviewer eldobható mutációval (egy network-tool hozzáadása) pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/application
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED fail-closed + allowlist + size-limit + provenance tesztek.
2. Tool/registry/request/result modellek.
3. Read-only toolok + fake registry.
4. Additív export; gate.

## 9. Kockázatok

- A „hasznos" write/network tool kísértése — TILOS; az R11 kétlépcsős action-rendszere kezeli.
- Size-limit határeset: a max+1 kimenetnek reportálnia kell, nem csendben csonkolni.

**STOP:** write/network/code tool, néma csonkolás vagy allowlist-gyengítés helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r10-tool-contract-and-registry-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
