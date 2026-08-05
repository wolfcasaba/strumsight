# E04-R10 — Tutor Tool contract és read-only registry

- **Státusz:** PLANNING (pre-flight mérve 2026-08-05, main @ `acc84d9`; előre megírva 2026-08-04, main @ `fbe1e82`)
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
  "test/features/ai_tutor/domain/tutor_tool_registry_test.dart",
  "test/features/ai_tutor/application/read_only_tutor_tools_test.dart",
  "docs/rounds/e04-r10-tool-contract-and-registry.md",
]
# §0.0 D2 revízió: `lib/features/ai_tutor/public.dart` ELTÁVOLÍTVA a listáról
# (a ai_tutor_boundary_test.dart nulla-export invariánsa bármely exporttól
# RED-re váltana; e körnek nincs hívója — R11/R12/R16/R19 fogyasztja). Üresen marad.
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

**Mérve 2026-08-05, main @ `acc84d9`.** Előfeltétel OK: E04-R02 (`db778c4`) és
E04-R05 (`55d640d`) merge-elve. A `lib/features/ai_tutor/domain/tools/` és
`application/tools/` üres (greenfield). `AppResult`/`AppFailure` mérve:
`lib/core/foundation/app_result.dart` (`sealed AppResult<T>` → `Success`/`Failure`,
`AppResult.success`/`.failure`), `lib/core/foundation/app_failure.dart`
(`sealed AppFailure` + `ValidationFailure` [`validation.invalid_input`],
`UnknownFailure` [`unknown`], `ConfigurationFailure`, … ; `FailureCode` kódlista).

- **D1 — ÚJ ADR [0137](../adr/0137-ai-tutor-readonly-tool-contract.md)**
  (read-only tool contract & registry). A legmagasabb létező 0136 → 0137 szabad.
  Ez **külön** normatív döntés (typed read-only tool-allowlist, fail-closed,
  provider-független schema), az ADR 0133 (write/launch **megerősítés**) a
  komplementer oldal — R10 az olvasó/compute oldalt rögzíti. Az ADR-t az
  orchestrátor írta és commitolja a pre-flight commitban (nem az implementer
  fájlja).

- **D2 — engedélyezett-lista SZŰKÍTÉS:** `lib/features/ai_tutor/public.dart`
  eltávolítva (a `ai_tutor_boundary_test.dart` nulla-import/export invariánsa
  bármely exporttól RED-re váltana; e körnek nincs hívója). A tesztek a tool-
  osztályokat **közvetlenül** a domain/application útvonalról importálják, nem a
  barrelen át. Azonos revízió, mint R07/R08/R09.

- **D3 — `AppFailure`-leképezés meglévő kódokkal:** a `lib/core/foundation/`
  (`app_failure.dart` + `FailureCode`) a kör scope-ján **kívül** van. A
  tool-exception → AppFailure a **meglévő** subtypeokat használja:
  invalid-input / permission-mismatch / unknown-tool → `ValidationFailure`
  (`validation.invalid_input`); váratlan throw → `UnknownFailure` (`unknown`).
  A tool-specifikus kimeneti állapotok (oversized-report, timeout, provenance) a
  tool **saját** `tutor_tool_result.dart` modelljében élnek, **nem** új
  `FailureCode`-ként. Új `FailureCode` felvétele a core contractot érintené →
  `stopped`.

- **D4 — §1.2 erőforrás-tulajdonlás N/A:** nincs `.acquire()`/lease/lock/handle
  a `lib/features/ai_tutor/` alatt (mérve `rg "\.acquire\("`, 0 találat) —
  greenfield read-only compute, egyetlen input sem szerez erőforrást.

PREPARED→PLANNING, a brief + ADR 0137 commitolva az implementer ELŐTT.

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
   **arbitrary file/network/code tool TILOS** ([ADR 0137](../adr/0137-ai-tutor-readonly-tool-contract.md),
   komplementer az ADR 0133 write/launch-megerősítéssel). **NEM elfogadható:** „csak
   egy" hálózati vagy fájl-tool.
2. Unknown tool **fail-closed**; a model csak **turn-specifikus** allowlistet kap.
3. Minden output provenance + size-limit report; tool-exception → **AppFailure**
   (nem nyers throw). **D3 (mérve):** a `lib/core/foundation/` scope-on KÍVÜL —
   ne adj hozzá `FailureCode`-ot; a meglévő subtypeokat használd: invalid/permission/
   unknown-tool → `ValidationFailure` (`validation.invalid_input`), váratlan throw →
   `UnknownFailure` (`unknown`). Az oversized/timeout/provenance a tool SAJÁT
   `tutor_tool_result.dart` modelljében él, nem globális kódként.
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

- **Szállítva:** typed `TutorTool` contract, providerfüggetlen input-schema,
  immutable request/turn-policy és provenance/timeout/size-report result;
  versionált, fail-closed registry; két zárt kezdeti local tool
  (`getContextField`, `summarizeContext`); behelyettesíthető fake registry.
- **Acceptance → teszt:** `tutor_tool_registry_test.dart` méri a registry
  verziót, turn-allowlistet, unknown-tool fail-closed viselkedést,
  invalid-input/permission-mismatch `ValidationFailure`-t, váratlan kivétel
  `UnknownFailure`-t, timeout resultot és az alatta/rajta/fölötte size-limit
  mátrixot. `read_only_tutor_tools_test.dart` méri a provenance-t, a
  secret-redactiont, az input-validációt, a network-tool eldobható mutációját
  pirosra váltó allowlistet és a fake registry orchestration használatát.
- **Futtatva:** `flutter test test/features/ai_tutor/domain/tutor_tool_registry_test.dart test/features/ai_tutor/application/read_only_tutor_tools_test.dart`
  → 12 zöld; `tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/application`
  → format, analyze, mindkét célzott test-suite és architecture zöld.
- **Eltérés / nem futtatott ellenőrzés:** CI teljes `flutter test`, property gate
  és release APK nem lokális implementer-feladat; az orchestrátor futtatja.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r10-tool-contract-and-registry-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
