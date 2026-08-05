# Review — E04-R08 Deterministic debrief és coaching fallback

- **Kör:** E04-R08
- **Branch:** `codex/e04-r08-deterministic-debrief-coaching`
- **Implementer:** Codex (`gpt-5.6-terra`, örökölt kézi override)
- **Reviewer:** Claude Opus 4.8 (független, read-only)
- **Implementer commit:** `cb5ee6c` (rebase után; eredeti `d69b7ed`)
- **Verdikt:** **APPROVED** — 0 BLOCKER / 0 MAJOR / 0 MINOR / 1 NOTE

## 1. Módszer

Izolált `/tmp/review-e04-r08` klón (a közös working tree-t nem érintve). A gate
saját kézzel újrafuttatva; scope-audit a brief §0.0-revideált engedélyezett
lista ellen; eldobható valódi-sértés próba a determinizmus-guardra.

## 2. Gate — újrafuttatva (izolált klón)

`flutter pub get` + `flutter gen-l10n` (gitignore-olt l10n előfeltétel), majd:

```
tools/round-gate.sh test/features/ai_tutor/application
  format        → ZÖLD
  analyze       → ZÖLD
  test          → ZÖLD (35 passed; ebből a kör 14 új tesztje)
  architecture  → ZÖLD (12 allowlisted deviation)
MINDEN GATE ZÖLD  (exit 0)
```

Router CI a rebase-elt head-en (`30977592980`) **success** (a brief-metaadat +
pipeline-integrációs pytest sáv). A teljes suite + property + APK a build-apk CI-ban.

## 3. Scope-audit

`git diff --name-only 00a0ba3...HEAD` (a rebase-bázistól) — pontosan a
§0.0-revideált engedélyezett lista, semmi azon kívül:

```
docs/rounds/e04-r08-deterministic-debrief-coaching.md   (§10 handoff + §0.0)
lib/features/ai_tutor/domain/models/debrief_fact.dart
lib/features/ai_tutor/domain/models/coaching_insight.dart
lib/features/ai_tutor/application/debrief/session_debrief_builder.dart
lib/features/ai_tutor/application/debrief/deterministic_coach.dart
lib/l10n/app_en.arb
lib/l10n/app_hu.arb
test/features/ai_tutor/application/session_debrief_builder_test.dart
test/features/ai_tutor/application/deterministic_coach_test.dart
```

`public.dart` **nem** módosult (a §0.0 D2 revízió szerint) — a lezárt E04-R01
`ai_tutor_boundary_test.dart` nulla-export invariánsa érintetlen. Nincs
kereszt-feature belső import (a legacy Practice típusokat nem importálja; a
parity-t saját érték-egyezéssel méri).

## 4. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | Forgatókönyvek (late bias / wrong direction / low chord / first session / improvement / non-comparable / low evidence) determinisztikus, **hu+en** output | `deterministic_coach_test.dart` „renders every acceptance scenario from both ARB catalogs" (6 forgatókönyv × en+hu, minden mező non-empty) | ✅ |
| A2 | Low evidence → uncertainty text, NEM 0%/hamis állítás; küszöb-mátrix | „uses explicit uncertainty text for low evidence without a zero claim" (pairedEventCount=7 → `CoachingUncertainty.lowEvidence`, uncertaintyText non-empty, explanation `isNot(contains('0%'))`); a küszöb (8) alatt=7 vs rajta/fölött=8/20 tesztelt | ✅ |
| A3 | No unsupported claim: minden insighthoz evidence-ref; camera/vizuális claim soha; eldobható mutáció (evidence-ref elhagyása) → RED | grounding a `CoachingInsight`/`DebriefFact` konstruktorban kikényszerített (üres `evidenceRefs` → `ArgumentError`); a teszt EZT a mutációt méri (`throwsArgumentError`); „never claims a visual or camera diagnosis" ARB-scan (camera/visual/finger/hand/fret/kamera/vizuális/ujj/kéz/bund) | ✅ |
| A4 | Legacy parity: R01 `practice_coach_bias_late_v1` fixture → egyezés | „keeps legacy bias-late as the one primary priority focus" → `insight.code == 'practice.insight.bias_late'` (a legacy `PracticeInsightCode.biasLate` kódja); a direction/chord kód a legacy fix sorrendben | ✅ |

## 5. Valódi-sértés próba (eldobható, futtatva + visszaállítva)

A determinizmus-guard diszkriminációjának igazolására a `DeterministicCoach`
tie-break komparátorában a `left.code.compareTo(right.code)` fallbacket
neutralizáltam (csak `priorityComparison`). A „uses the stable fact code as its
deterministic tie break" teszt **RED** lett (line 67, `+0 -1`), a fájl azonnal
visszaállítva. → A shuffle-invariáns guard valóban fog. A grounding-guard
diszkriminációját maga a kör tesztje bizonyítja (üres evidence-ref → throw).

## 6. Architektúra / termékhatár

- Tiszta domain/application, determinisztikus: **egész basis-point aritmetika**,
  nincs óra/véletlen/lebegőpont; stabil rendezés `(priority↑, code↑)`.
- Grounding az SDD §21.3 szerint: `measuredFact` ≥1 session evidence-ref,
  `computedTrend` (improvedFromPrevious) ≥2 összehasonlítható evidence-group +
  2 evidence-ref, konstruktor-kikényszerítve.
- Nincs `.acquire()` / lease / hálózat / mic / audio-raw a rétegen (§1.2 N/A).
- `CoachingInsight` teljes SDD §14.3 mezőkészlet: code, title/explanation
  loc-key, evidence-refs, priority, suggested-action template, uncertainty,
  conflicting-evidence flag.

## 7. NOTE (nem blokkol)

- **N1:** A `DeterministicCoach.coach` **pontosan egy** elsődleges insightot ad
  (a legmagasabb prioritású fact). A brief §5.2 „legfeljebb egy(-két) elsődleges
  fókusz" — az egy insight ezen belül van (≤ kettő), így megfelelő. Ha egy
  későbbi UI-kör (R19/R20) másodlagos fókuszt is meg akar jeleníteni, a
  fact-lista (priority-rendezett, teljes) már rendelkezésre áll — nem igényel
  domain-változást. Follow-up, nem e kör hiánya.

## 8. Merge-döntés

Zöld kapu minden eleme a kör-branchre nézve látott: gate (izolált klón) zöld,
Router CI zöld, build-apk CI a végső head-en (lásd PR). Nulla OPEN BLOCKER/MAJOR
→ **APPROVED**, squash-merge engedélyezett.
