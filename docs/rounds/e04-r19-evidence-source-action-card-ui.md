# E04-R19 — Evidence, source és action card UI

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-05, base `e8ae7ee`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 19; §35
- **Branch:** `minimax/e04-r19-evidence-source-action-card-ui`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R09, R11, R18 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (UI-dominált kör, ADR 0069 mért szabály)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/presentation/widgets/tutor_evidence_chip.dart",
  "lib/features/ai_tutor/presentation/widgets/tutor_source_sheet.dart",
  "lib/features/ai_tutor/presentation/widgets/tutor_action_card.dart",
  "lib/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/presentation/tutor_action_card_test.dart",
  "test/features/ai_tutor/presentation/tutor_evidence_source_test.dart",
  "test/features/ai_tutor/presentation/practice_plan_preview_screen_test.dart",
  "docs/rounds/e04-r19-evidence-source-action-card-ui.md",
]
gate_tests = [
  "test/features/ai_tutor/presentation",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R09/R11/R18 merge; olvasd újra
> `AGENTS.md` (**§15.6 MiniMax-szabály**), Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR
> (R01 0132/0133 bővítése). `rg`: az R11 action + R09 plan public felülete; az R18
> chat-fa mai alakja. **ARB gen:** `flutter gen-l10n` a gate előtt. PREPARED→PLANNING,
> brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll (MiniMax M3)

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP on scope conflict:** listán kívüli fájl,
hiányzó public contract, ellentmondó acceptance esetén `stopped` — **nincs néma
scope-tágítás és nincs kód-kommentben megindokolt mércegyengítés** (MiniMax mért hibamódja).

## 0.0 Tervezési baseline és pre-flight revízió

**Motor:** MiniMax M3 — UI-dominált kör (ADR 0069, örökölt `minimax` override).

**Base:** `main @ e8ae7ee` (E04-R18 merge után; E04-R09/R11/R18 mind merge-elve). Local HEAD = origin/main.

**ADR-döntés (mért): NINCS új ADR.** A kör a már **merge-elt** ADR 0132
(privacy & consent — a model-label sosem kerüli meg a localizationt/sanitizert)
és ADR 0133 (tool-confirmation — előnézet + megerősítés + **typed executor**)
hatálya alá esik; mindkettő E04-R01 baseline-döntés. Új ADR-t merge-elt döntés
fölé osztani tilos (pipeline-prompt §4), és a közvetlen elődkörök (R13/R14/R17/**R18**)
mind ADR nélkül, epic-ADR hatállyal zárultak. A `reserve-adr` által kiadott
0176 markert felszabadítottam.

**Mért pre-flight ellenőrzések (a brief hivatkozott felületei ellen):**

1. **Stale/„nem fut" (elérhetetlen-státusz mérés):** a `stale` UI-állapotot a
   `tutor_action_validator.dart:71` produkálja — `!metadata.expiresAt.isAfter(context.now)`
   → `TutorActionValidationIssue.expired` → `ActionConfirmation.blocked([expired])`.
   Az `ActionConfirmationService._confirmOnce` a `confirm`-nél ÚJRA validál, így a
   lejárt proposal **soha nem éri el** az `executor.execute`-ot (§5.4 teljesül).
   Reprodukáló input: bármely action `expiresAt <= now`.
2. **Typed executor (erőforrás-tulajdonlás mérés):** `TutorActionExecutor.execute(TutorAction)`
   csak validáció után hívódik; nyers route → `TutorActionValidationIssue.rawRouteForbidden`.
   A UI kizárólag `ActionConfirmationService`-en át hív — nincs nyers-string/route végrehajtás.
3. **Idempotens double-tap:** `_confirmedClientActionIds` + `_inFlightConfirmations`
   (kulcs: `clientActionId`).
4. **Exact action-preview:** `TutorActionPreview{kind: TutorActionPreviewKind, fields: UnmodifiableMapView}`;
   `TutorActionPreviewKind {profileUpdate, planSave, sessionLaunch}`.
5. **Plan-preview + edit:** `PracticePlanDraft.copyWith(blocks: …)` +
   `PracticePlanSource.userEdited` (R09 felület, nincs új domain-logika).
6. **Provenance-négyes (measured/trend/knowledge/inference):** nincs egyetlen
   egyesítő domain-enum; a négy chip a prezentációs réteg új enumja, ami a meglévő
   domain-fogalmakra képez: `DebriefFactProvenance.measuredFact`→measured,
   `.computedTrend`→trend, `tutor_source_ref` (knowledgeVersion/chunkIndex)→knowledge,
   `StudentProfileFieldProvenance.*Inferred`→inference. text+ikon+szín a11y-kontraktus
   a widgetben mérve.
7. **public.dart:** ma üres boundary (csak `library;`); a kör additív exportot ad
   a hívó UI-widgetekhez.

A CI-terv a diff commitolása után újramérve (üres diffnél fail-closed `build-apk.yml`);
a kör tisztán Dart+ARB+docs → várható `full-gate.yml`, és `docs/rounds/**` érintés
miatt a Router CI is a kapu része.

## 1. Cél

A tutor **állításainak és műveleteinek** átlátható, megerősíthető megjelenítése —
provenance, exact action-preview, és validált plan-preview.

## 2. Jelenlegi állapot

- Nincs evidence/action UI. R09 plan + R11 action + R18 chat-fa kész — a widgetek erre kötnek.
- A modell-oldali label sosem kerülheti meg a localizationt/sanitizert (SDD Kör 19/6).

## 3. Scope

**Benne:** measured/trend/knowledge/inference chip, source/evidence detail-sheet,
action-preview kártya **exact paraméterekkel**, confirm/reject/stale/failed state,
practice-plan preview + edit, provenance **text+icon** (nem csak szín), semantic
description, confirmation UTÁN csak typed executor.

**Kívül — TILOS:** új action/plan domain-logika (R09/R11), valódi navigáció-végrehajtás,
nyers route/URL a modelltől, source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../presentation/widgets/tutor_evidence_chip.dart` | ÚJ | provenance chip |
| `.../presentation/widgets/tutor_source_sheet.dart` | ÚJ | forrás-részletező |
| `.../presentation/widgets/tutor_action_card.dart` | ÚJ | exact action-preview |
| `.../presentation/screens/practice_plan_preview_screen.dart` | ÚJ | plan preview + edit |
| `lib/l10n/app_en.arb`, `app_hu.arb` | meglévő | UI-stringek (additív) |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/presentation/*` | ÚJ | widget-tesztek |
| `docs/rounds/e04-r19-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje, nyers route/URL. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. Az action-preview **exact paramétert** mutat; confirmation UTÁN **csak typed
   executor** fut (ADR 0133). **NEM elfogadható:** nyers route/URL vagy nem-előnézett action.
2. A modell-label **nem kerüli meg** a localizationt/sanitizert.
3. Provenance **text+icon**, nem csak szín (a11y).
4. **Stale proposal nem fut** (R11 policy a UI-ban is látszik).

## 6. Acceptance criteria (runnable artifact + mátrix — MiniMax-kötelező)

- [ ] evidence-sheet; source-mapping; inference-warning; confirm; reject; **stale**;
      double-tap (idempotens); invalid-action; plan-edit; large-text; **semantics** —
      mind widget-teszt.
- [ ] **Provenance-mátrix:** measured/trend/knowledge/inference chip mind text+icon+szín
      hármassal (nem csak szín) — cellánként tesztelt.
- [ ] Confirmation után csak typed executor — teszt; reviewer eldobható mutációval
      (nyers-string executor) pirosra váltja.

A mérce **futtatható artefaktum** (widget-teszt-lista), nem prompt-szöveg.

## 7. Kötelező ellenőrzések

Szó szerinti gate (ezt futtasd, változtatás nélkül):

```bash
tools/round-gate.sh test/features/ai_tutor/presentation
```

Egyetlen lokális gate, külön processzek, nincs `&&`/pipe/`tail`. ARB-változásnál
`flutter gen-l10n` a gate előtt. Full CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. RED provenance + exact-action + stale + typed-executor tesztek.
2. evidence-chip + source-sheet.
3. action-card + plan-preview + ARB.
4. `flutter gen-l10n`; gate.

## 9. Kockázatok

- Szín-only provenance (a11y-bukás) — text+icon kötelező.
- Modell-label sanitizer-megkerülés — minden label localization/sanitizer-en át.

**STOP:** nyers route/URL, nem-előnézett action vagy mércegyengítés helyett dokumentált
brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r19-evidence-source-action-card-ui-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
