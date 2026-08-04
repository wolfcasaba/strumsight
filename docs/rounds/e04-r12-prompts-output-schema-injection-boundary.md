# E04-R12 — Prompt templatek, output schema és injection boundary

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 12; §35
- **Branch:** `codex/e04-r12-prompts-output-schema-injection-boundary`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R05 + E04-R07 + E04-R10 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/application/prompts/prompt_version.dart",
  "lib/features/ai_tutor/application/prompts/prompt_template.dart",
  "lib/features/ai_tutor/application/prompts/tutor_prompt_builder.dart",
  "lib/features/ai_tutor/application/prompts/tutor_output_schema.dart",
  "assets/tutor_prompts/",
  "lib/features/ai_tutor/public.dart",
  "pubspec.yaml",
  "test/features/ai_tutor/prompts/tutor_prompt_builder_test.dart",
  "test/features/ai_tutor/prompts/prompt_injection_test.dart",
  "test/features/ai_tutor/prompts/prompt_snapshot_test.dart",
  "docs/rounds/e04-r12-prompts-output-schema-injection-boundary.md",
]
gate_tests = [
  "test/features/ai_tutor/prompts",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R05/R07/R10 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5 (**§20 prompt/injection**), `HANDOFF.md`. Nincs ÚJ ADR
> (R01 0131/0132 bővítése). `rg`: az R05 redaktált snapshot + R10 tool-schema
> felülete; `pubspec.yaml` assets. PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

**Verziózott, tesztelhető** promptépítés és strukturált modell-output, éles
**trusted/untrusted** tartalmi határral és prompt-injection védelemmel.

## 2. Jelenlegi állapot

- Nincs prompt-réteg (SDD §3.2/10/11). R05 redaktált snapshotot ad, R07 forrás-refet,
  R10 tool-schemát — ezek a prompt-bemenetek.
- A prompt builder **csak redacted contextet** fogadhat (nyers audio/token/secret soha).

## 3. Scope

**Benne:** prompt layer-sorrend + delimiterek, intentenként template (angol system,
explicit response-locale), strukturált output-schema v1, **külön trusted-knowledge
és untrusted user/import** szakasz, verzió-stamping, tool-schema injection csak az
engedélyezett toolokra, snapshot-fixture minden intenthez, adversarial injection-fixture.

**Kívül — TILOS:** chain-of-thought kérés, gateway/cloud hívás (R13+), nyers context
a builderbe, UI.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/prompts/prompt_version.dart` | ÚJ | verzió-stamp |
| `.../application/prompts/prompt_template.dart` | ÚJ | layer + delimiter |
| `.../application/prompts/tutor_prompt_builder.dart` | ÚJ | redacted-only builder |
| `.../application/prompts/tutor_output_schema.dart` | ÚJ | strukturált output v1 |
| `assets/tutor_prompts/` | ÚJ | intentenkénti template-ek |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `pubspec.yaml` | meglévő | assets-bejegyzés (additív) |
| `test/features/ai_tutor/prompts/*` | ÚJ | snapshot + injection tesztek |
| `docs/rounds/e04-r12-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Trusted knowledge és untrusted user/import külön szakasz**, egyértelmű
   delimiterekkel; a builder **csak redacted contextet** fogad (ADR 0132). **NEM
   elfogadható:** untrusted tartalom trusted szakaszba olvasztása.
2. **Nincs chain-of-thought** kérés; az output strukturált schema.
3. Minden prompt-build **verziót** rögzít; tool-schema injection csak az engedélyezett
   toolokra (R10 allowlist).
4. Nincs secret/nyers audio/token a promptban.

## 6. Acceptance criteria

- [ ] Layer-order + locale + redaction + tool-allowlist + untrusted-delimiter +
      no-secret + no-raw-audio + schema-version — mind literálisan tesztelt.
- [ ] **Prompt-injection fixture-készlet:** az adversarial input NEM emel tool-permissiont
      és NEM lép át trusted szakaszba; reviewer eldobható mutációval (delimiter elhagyása)
      pirosra váltja.
- [ ] **Deterministic snapshot** minden intenthez (snapshot-gate aktív).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/prompts
```

Külön processzek, nincs `&&`/pipe/`tail`. `pubspec.yaml` assets CI asset-gate alatt.
CI = orchestrátor exact-SHA dispatch.

## 8. Implementációs sorrend

1. RED injection + snapshot + trusted/untrusted tesztek.
2. Version/template/output-schema.
3. Builder + assets template-ek.
4. `pubspec.yaml` assets; gate.

## 9. Kockázatok

- Snapshot-fragilitás vs. valódi védelem — a snapshot a szerkezeti szerződést rögzíti,
  az injection-fixture a viselkedést.
- Untrusted-tartalom szivárgás trusted szakaszba (fő injection-vektor) — delimiter-teszt.

**STOP:** untrusted→trusted olvasztás, chain-of-thought kérés vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r12-prompts-output-schema-injection-boundary-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
