# E05-R23 — Feedback policy és realtime cue budget

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-08, kód mérve: main @ `6afcede`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 23; §9.7, §23.3–23.4
- **Branch:** `codex/e05-r23-feedback-policy-and-cue-budget`
- **Előfeltétel:** **E05-R20, E05-R22 merge** (mindkettő zöld, `main`-en; ellenőrizve)
- **Brief szerzője:** Claude (batch, 2026-08-05) · **Pre-flight revízió:**
  Claude Sonnet 5 (2026-08-08) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/feedback/insight_code.dart",
  "lib/features/vision/domain/feedback/feedback_policy.dart",
  "lib/features/vision/domain/feedback/cue_budget.dart",
  "lib/features/vision/application/feedback_policy_engine.dart",
  "lib/features/vision/domain/safety/vision_safety_policy.dart",
  "lib/features/vision/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/domain/feedback_policy_test.dart",
  "test/features/vision/application/feedback_policy_engine_test.dart",
  "docs/adr/0191-feedback-policy-and-cue-budget.md",
  "docs/rounds/e05-r23-feedback-policy-and-cue-budget.md",
]
gate_tests = [
  "test/features/vision",
  "test/core/l10n_parity_test.dart",
]
native_gate = false
```

> ✅ **Pre-flight ELVÉGEZVE (2026-08-08).** Eredmény lásd §0.0. Rövid
> összefoglaló: a brief „0162" előzetes ADR-hivatkozása **sosem lett fájl**
> (ugyanaz a mintázat, mint E05-R21/R22-nél) — `tools/round-slots.py
> reserve-adr` **0191**-et adott, lásd
> [`docs/adr/0191-feedback-policy-and-cue-budget.md`](../adr/0191-feedback-policy-and-cue-budget.md).
> **Mért scope-rés:** az R20 `SafetyClaimGuard` katalógusa
> (`vision_safety_policy.dart`) egy **zárt** `Map` kilenc, kizárólag
> posture-kóddal — a fretting (6 metrika) és picking (7 metrika) családnak
> **nulla** bejegyzése van, és a fájl saját doc-commentje + [ADR
> 0188](../adr/0188-vision-safety-claim-guard.md) §Következmények explicit
> kimondja, hogy **ez a kör (R23)** bővíti a katalógust. A fájl hiányzott az
> eredeti `allowed_paths`-ból — **pótolva** (additív-only: lásd §0.0/2). A
> `vision_safety_policy.dart` már ma is `public.dart`-ból exportált, tehát nem
> új modulhatár nyitása.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING.** A pipeline-prompt §1 két kötelező mérési szabálya (elérhetetlen
cél-státusz / erőforrás-tulajdonlás) szerint, plusz a brief saját pre-flight
feladata (R20 safety-guard allowlist újraolvasása). Teljes indoklás: [ADR
0191](../adr/0191-feedback-policy-and-cue-budget.md) Kontextus szakasza — itt
csak az összefoglaló és a brief-re gyakorolt hatás.

1. **ADR-szám: a brief „0162" hivatkozása sosem lett fájl** (nem elavult
   foglalás, mint a 0170→0189 minta E05-R21-nél, hanem sosem realizált terv —
   `ls docs/adr | grep 0162` nulla találat; ugyanaz a mintázat, mint
   E05-R22-nél, ahol a „0162" hivatkozás is üres bizonyult).
   `tools/round-slots.py reserve-adr --round E05-R23` → **0191**.
2. **Mért scope-rés — `vision_safety_policy.dart` hiányzott az
   `allowed_paths`-ból, pótolva.** Az architekturális döntés #6 („minden
   insight-kód átmegy az R20 safety guardján") és az acceptance §6 első
   cellája („és átmegy a safety guardon") **nem teljesíthető** a jelenlegi
   `allowed_paths`-szal: a `SafetyClaimGuard.evaluate` production ágon
   kizárólag `VisionSafetyPolicy.catalog`-ból dönt (a `declaredClass`
   override doc-commentje szerint „Production callers MUST omit it and rely
   on the catalog"), a katalógus pedig egy **zárt, statikus** `Map` kilenc
   bejegyzéssel — mind posture (`shoulderAsymmetry`×2, `torsoLean`×2,
   `elbowDrift`×2, `neckProxy`×2, +1 aggregát). A fretting (`FrettingMetricId`,
   6 érték: `wristDeviationProxy`, `handToNeckDistance`, `chordChangeTravel`,
   `readyPositionTime`, `positionStability`, `fingerSpreadProxy`) és picking
   (`PickingMetricId`, 7 érték: `strokeDirection`, `strokeAmplitude`,
   `strokeSpeed`, `strokeLinearity`, `downUpAsymmetry`,
   `beatToBeatConsistency`, `pickingZone`) családnak **nulla** katalógus-
   bejegyzése van ma (`grep -rn "fretting\|picking" lib/features/vision/domain/safety/vision_safety_policy.dart`
   nulla találat) — bármely új, ezekre a családokra épülő `InsightCode` a
   guardon **mindig** `"not in catalog"` hibával elutasítva futna, azaz a
   katalógus-teszt garantáltan PIROS maradna változatlan `allowed_paths`
   mellett. Ez **nem** vak lista-tágítás: a fájl saját doc-commentje
   („A future posture metric (R23 / R27) extends this map") és [ADR
   0188](../adr/0188-vision-safety-claim-guard.md) §Következmények 3. pontja
   („A jövőbeli R23 (feedback policy) […] erre a katalógusra épül; a
   katalógus bővítése […] mindig új, a guard által ellenőrzött bejegyzést
   igényel") **explicit ezt a kört nevezi meg** a tervezett bővítés
   végrehajtójaként — az `allowed_paths` hiánya brief-írási mulasztás, nem
   szándékos korlátozás. **Kötött korlát a bővítésre:** csak ÚJ kulcs-érték
   pár adható a `catalog`-hoz; a meglévő 9 bejegyzés kulcsa, értéke és a
   `VisionSafetyClaimClass` enum **nem módosul, nem törlődik** (R20 lezárt
   kör viselkedése bitre változatlan marad — H2 nem sérül). A meglévő
   `safety_claim_guard_test.dart` négy generikus tesztje
   (`VisionSafetyPolicy.catalog.keys`/`.values` felett iterál, nincs
   kőbe-vésett darabszám) automatikusan lefedi az új bejegyzéseket is —
   **nem** kell hozzáérni, ezért nincs az `allowed_paths`-on.
3. **`ObservationState.experimental` elérhetetlen marad (öröklött R22
   mérés, [ADR 0190](../adr/0190-vision-observation-fusion-and-evidence.md)
   Döntés 4).** A mai három metrika-katalógusból (fretting/picking/posture)
   egyik capability-enumnak sincs kísérleti értéke, tehát a valódi
   `ObservationFusion` pipeline-on keresztül **nem** állítható elő
   `experimental` evidence. A `FeedbackPolicyEngine`/`FeedbackPolicy` teszt
   ahol ezt az ágat gyakorolja, `VisionEvidence`-t **közvetlenül**
   konstruáljon (`observationState: ObservationState.experimental`), ne a
   fúzión keresztül — ugyanaz a mintázat, mint az R22 saját tesztjeiben.
4. **SDD §23.4 hattagú javasolt prioritási sorrend vs. a brief §5/2+§6
   kéttagú acceptance-je: nem ütközik, a brief a MINIMUM mérce.** A hattagú
   lista (nem megfigyelhető/setup → sync-probléma → stabil nagy-hatású minta →
   romló forma → kisebb inkonzisztencia → kísérleti) **javasolt** sorrend
   (SDD §23.4 „Javasolt sorrend"); a brief §6 „Prioritás-teszt" cellája csak a
   setup-elsőbbséget és az azonos-prioritású döntő determinizmusát követeli
   **kötelezően**. Az implementer szabadon finomíthatja a numerikus
   prioritás-skálát a hattagú SDD-listára, amíg a kötött két invariáns
   (setup > technikai; azonos prioritás → determinisztikus) áll — ez nem
   brief-revízió, hanem implementációs szabadságfok, dokumentálva itt, hogy a
   review ne várjon szó szerinti hattagú enumot.
5. **Erőforrás-tulajdonlás (pipeline-prompt §1/2): nem releváns.** A brief
   egyetlen acceptance-cellája sem rendel lease/lock/handle/subscription-t
   egy réteghez; a `FeedbackPolicyEngine` tisztán domain/application
   számítás (`VisionEvidence` lista → `VisionInsight` lista), nincs
   `.acquire(`-hívása vagy erőforrás-tulajdonlása.

## 1. Cél

`VisionEvidence` → **korlátozott, stabil, lokalizálható** `VisionInsight`:
verziózott policy-registry, capability/confidence/duration/cooldown kapukkal,
és **egyszerre legfeljebb egy** realtime cue.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R22 ad verziózott, provenance-szal ellátott evidence-t; **insight nincs**.
- Az R20 `SafetyClaimGuard`-ja fail-closed allowlist — ez a kör **minden**
  insight-kódot ezen visz át. **Mérve (§0.0/2): a katalógus ma kilenc,
  kizárólag posture-kódot tartalmaz — fretting/picking családra nulla
  bejegyzés** — ez a kör bővíti a `VisionSafetyPolicy.catalog`-ot additív
  módon (lásd §4, §5/6).
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
| `.../domain/safety/vision_safety_policy.dart` | meglévő | **§0.0/2: additív-only** katalógus-bővítés (fretting/picking + szükséges posture insight-kód) |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** `visionInsight*` kulcs |
| `test/features/vision/*` | ÚJ | policy + engine tesztek |
| `docs/adr/0191-*.md` | ÚJ | feedback policy/cue budget szerződés (§0.0/1) |
| `docs/rounds/e05-r23-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; meglévő ARB kulcs átírása; a `vision_safety_policy.dart`
meglévő 9 bejegyzésének vagy a `VisionSafetyClaimClass` enumnak módosítása/
törlése (csak ÚJ bejegyzés adható hozzá, §0.0/2). Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A domain nem tartalmaz UI-mondatot.** Az insight **kód + paraméterek**;
   a szöveg ARB-ból jön. **NEM elfogadható:** angol/magyar mondat a
   `feedback_policy.dart`-ban, még „fallbackként" sem.
2. **Setup/observability cue előbb, mint technikai cue.** Ha a keret rossz
   vagy a geometria elveszett, a felhasználó azt kapja, nem technikai kritikát
   (SDD §23.3/§23.4 „Javasolt sorrend" 1. helye; ADR 0191 §Döntés 2 — a brief
   eredeti „ADR 0162" hivatkozása sosem lett fájl, §0.0/1). **NEM elfogadható:**
   párhuzamos megjelenítés „hogy mindkettőt lássa".
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
   ezt kimerítően méri. A katalógus (`vision_safety_policy.dart`, §0.0/2, §4)
   **additív módon** bővül minden új `InsightCode`-hoz szükséges bejegyzéssel;
   a meglévő 9 posture-bejegyzés és a `VisionSafetyClaimClass` enum
   változatlan marad. **NEM elfogadható:** a guard lazítása, egy fallback
   „ismeretlen kód → allowed" ág, vagy a `declaredClass` production-hívási
   override használata (a doc-comment szerint test-only).
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
- **Safety-katalógus bővítés (§0.0/2):** minden új `InsightCode`-hoz helyes
  `VisionSafetyClaimClass` deklarálandó a `vision_safety_policy.dart`-ban
  (sosem `diagnosis`/`injuryPrediction`/`painExplanation`/`recoveryAdvice`/
  `harmfulJudgment`), és a kód-string maga sem tartalmazhat tiltott lexémát
  (`SafetyClaimGuard._forbiddenLexemes`) — ez a katalógus-teszt + a meglévő
  `safety_claim_guard_test.dart` generikus tesztjei által kimerítően mérve.

**STOP:** hardcode-olt mondat, több párhuzamos cue vagy a negatív-küszöb
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r23-feedback-policy-and-cue-budget-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
