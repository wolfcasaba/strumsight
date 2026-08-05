# E05-R23 — Feedback policy és realtime cue budget

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 23; §9.7, §23.3–23.4
- **Branch:** `codex/e05-r23-feedback-policy-and-cue-budget`
- **Előfeltétel:** **E05-R20, E05-R22 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/feedback/insight_code.dart",
  "lib/features/vision/domain/feedback/feedback_policy.dart",
  "lib/features/vision/domain/feedback/cue_budget.dart",
  "lib/features/vision/application/feedback_policy_engine.dart",
  "lib/features/vision/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/domain/feedback_policy_test.dart",
  "test/features/vision/application/feedback_policy_engine_test.dart",
  "docs/rounds/e05-r23-feedback-policy-and-cue-budget.md",
]
gate_tests = [
  "test/features/vision",
  "test/core/l10n_parity_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R20/R22 merge; olvasd újra az
> R20 `SafetyClaimGuard` allowlistjét (minden insight-kódnak át kell mennie
> rajta) és az R22 confidence-modelljét. Nincs ÚJ ADR (0162 végrehajtása).
> PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

`VisionEvidence` → **korlátozott, stabil, lokalizálható** `VisionInsight`:
verziózott policy-registry, capability/confidence/duration/cooldown kapukkal,
és **egyszerre legfeljebb egy** realtime cue.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R22 ad verziózott, provenance-szal ellátott evidence-t; **insight nincs**.
- Az R20 `SafetyClaimGuard`-ja fail-closed allowlist — ez a kör **minden**
  insight-kódot ezen visz át.
- Az ARB-ban ma `visionSetup*` és `visionCalibration*` kulcsok vannak (R08/R11);
  az insight-szövegek `visionInsight*` prefixet kapnak.

## 3. Scope

**Benne:** `InsightCode` (zárt katalógus), `FeedbackPolicy` (kódonként
`requiredCapability`, confidence-küszöb, minimum időtartam, cooldown,
prioritás), `CueBudget` (egyszerre egy realtime cue; session-summary max
**két** elsődleges technikai fókusz), `FeedbackPolicyEngine`, pozitív
improvement insight **csak összehasonlítható ablakokból**, en+hu ARB kulcsok.

**Kívül — TILOS:** UI/megjelenítés (R24), fusion módosítása (R22),
persistence (R28), tutor (R27), hardcode-olt mondat a domainben.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/feedback/insight_code.dart` | ÚJ | zárt kód-katalógus |
| `.../domain/feedback/feedback_policy.dart` | ÚJ | kódonkénti kapuk |
| `.../domain/feedback/cue_budget.dart` | ÚJ | cue-korlát |
| `.../application/feedback_policy_engine.dart` | ÚJ | evidence → insight |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** `visionInsight*` kulcs |
| `test/features/vision/*` | ÚJ | policy + engine tesztek |
| `docs/rounds/e05-r23-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; meglévő ARB kulcs átírása. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A domain nem tartalmaz UI-mondatot.** Az insight **kód + paraméterek**;
   a szöveg ARB-ból jön. **NEM elfogadható:** angol/magyar mondat a
   `feedback_policy.dart`-ban, még „fallbackként" sem.
2. **Setup/observability cue előbb, mint technikai cue.** Ha a keret rossz
   vagy a geometria elveszett, a felhasználó azt kapja, nem technikai kritikát
   (ADR 0162). **NEM elfogadható:** párhuzamos megjelenítés „hogy mindkettőt lássa".
3. **Egyszerre legfeljebb EGY aktív realtime cue**, kódonkénti cooldownnal.
   **NEM elfogadható:** „max 2, ha rövidek" enyhítés.
4. **Low-confidence negatív cue elnyomott.** A negatív (kritikai) insightokhoz
   **magasabb** confidence-küszöb tartozik, mint a pozitívokhoz — ez a
   „no feedback is better than false feedback" elv gépi alakja.
   **NEM elfogadható** azonos küszöb mindkét irányra.
5. **Pozitív improvement csak összehasonlítható ablakokból**: azonos gyakorlat,
   azonos capability-szint, azonos metrika. **NEM elfogadható** eltérő
   feltételek közti „javultál" állítás.
6. **Minden insight-kód átmegy az R20 safety guardján** — a katalógus-teszt
   ezt kimerítően méri.
7. **A policy verziózott** (`policyVersion`), és az insight hordozza a verziót.

## 6. Acceptance criteria

- [ ] **Katalógus-teszt:** **minden** `InsightCode`-hoz létezik policy-bejegyzés
      (capability + confidence + duration + cooldown + prioritás), **és** en+hu
      ARB kulcs, **és** átmegy a safety guardon. Hiányzó bármelyik → PIROS.
- [ ] **Cooldown-teszt injektált órával:** a cooldown **alatt / rajta / fölött**
      — az első kettőben nincs ismételt cue, a harmadikban van.
- [ ] **Prioritás-teszt:** egyszerre setup + technikai insight jelölt →
      **csak a setup** jelenik meg; és két azonos prioritású jelölt esetén a
      választás determinisztikus (kétszeri futás azonos).
- [ ] **Confidence-mátrix:** pozitív és negatív insight külön küszöbbel, mindkettő
      **alatt / rajta / fölött** = 6 cella; a negatív küszöb szigorúbb (assert).
- [ ] **Session-summary korlát:** ≥ 5 jelölt fókusz → **legfeljebb 2** kerül a
      summarybe, determinisztikus sorrendben.
- [ ] **Golden summary fixture:** rögzített evidence-lista → bit-stabil insight
      lista (kétszeri futás azonos).
- [ ] **Lokalizációs paritás** zöld.
- [ ] **Valódi-sértés próba (§10):** a negatív-küszöb leszállítása a pozitívéra
      → a confidence-mátrix PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/core/l10n_parity_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: katalógus-, cooldown-, prioritás- és confidence-mátrix.
2. `InsightCode` katalógus + policy-bejegyzések.
3. `CueBudget` + engine.
4. ARB kulcsok; golden summary; gate.

## 9. Kockázatok

- **Cue-spam:** a cooldown injektált óra nélkül nem tesztelhető → a
  determinizmus feltétele az injektált óra.
- **A katalógus és az ARB elcsúszik** (kód van, szöveg nincs) — a katalógus-teszt
  ezt kimerítően köti össze.

**STOP:** hardcode-olt mondat, több párhuzamos cue vagy a negatív-küszöb
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r23-feedback-policy-and-cue-budget-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
