# ADR 0191 — Feedback policy and realtime cue budget

- **Státusz:** Elfogadva (E05-R23 pre-flight, 2026-08-08)
- **Kör:** E05-R23 — Feedback policy és realtime cue budget
- **Implementer motor:** Codex (Terra) (`codex`-harness, `~/.codex-terra`,
  `tools/codex-round.sh`) — az ADR-t az orchesztrátor (Claude Sonnet 5) írta a
  pre-flightban (ADR 0055, pipeline-prompt §2 — nincs előre kiosztott ADR).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) Kör 23; §9.7, §23.3–23.4
- **Kontext-ADR-ek:** [0179](0179-vision-capability-aware-feedback.md)
  (capability/confidence/observability — a metrika-fél gyökér-elve),
  [0188](0188-vision-safety-claim-guard.md) (zárt claim-kód katalógus és
  fail-closed guard — ez a kör a katalógus deklarált bővítője),
  [0190](0190-vision-observation-fusion-and-evidence.md) (`VisionEvidence`/
  `ObservationState` — ez a kör egyetlen bemenete), [0177](0177-ai-tutor-safety-injection-usage-evaluation-gate.md)
  (a sibling generatív-szöveg réteg determinisztikus-policy-előbb elve)

## Kontextus

Az E05-R22 ([ADR 0190](0190-vision-observation-fusion-and-evidence.md))
verziózott, provenance-szal ellátott `VisionEvidence`-t állít elő
metrikánként (fretting/picking/posture), de **insight-réteg nincs**: semmi
nem dönti el, MELYIK evidence-ből lesz felhasználónak szóló visszajelzés, MI a
sorrend, és mennyi jelenhet meg egyszerre. Az SDD Ch6 §9.7 (`VisionInsight`)
és §23.3–23.4 (feedback budget, insight prioritás) ezt a réteget írja elő; az
5.5/5.6 alapelvek („no feedback is better than false feedback",
„determinisztikus policy a generatív szöveg előtt") kötik a döntést.

A kör-brief 2026-08-05-i batch-írásakor egy „ADR 0162" hivatkozás szerepelt
előzetes tervként (§5 pont 2, „ADR 0162"). **Ez a szám sosem lett fájl**
(`ls docs/adr | grep 0162` nulla találat) — ugyanaz a mintázat, mint az
E05-R22 pre-flightjában talált „0162" hivatkozás (ADR 0190 Kontextus): egy
batch-írási idejű terv, ami sosem valósult meg, nem egy elavult, már
lefoglalt szám (szemben a 0170→0189 mintával E05-R21-nél). A pipeline-prompt
§0 táblája ezért explicit `nincs — te írod meg a pre-flightban` értéket
adott; `tools/round-slots.py reserve-adr --round E05-R23` → **0191**.

**Mért scope-rés a pre-flightban** (pipeline-prompt §1 mérési szabályai +
a brief saját pre-flight-feladata, „olvasd újra az R20 `SafetyClaimGuard`
allowlistjét"): a brief §5 pont 6 („minden insight-kód átmegy az R20 safety
guardján") és a §6 acceptance első cellája ezt KÖTELEZŐVÉ teszi, de a
`vision_safety_policy.dart` **nem** szerepelt az eredeti `allowed_paths`-ban.
Mérve: `SafetyClaimGuard.evaluate` a production ágon kizárólag
`VisionSafetyPolicy.catalog`-ból dönt (a `declaredClass` paraméter
doc-commentje: „Production callers MUST omit it and rely on the catalog"),
és a katalógus egy zárt, statikus `Map` **kilenc** bejegyzéssel, mind
posture-kód (`shoulderAsymmetry`/`torsoLean`/`elbowDrift`/`neckProxy` ×2 +
1 aggregát). A fretting (`FrettingMetricId`, 6 érték) és picking
(`PickingMetricId`, 7 érték) családnak **nulla** bejegyzése van. Bármely
ezekre épülő új `InsightCode` a guardon garantáltan `"not in catalog"`
hibával futna — a katalógus-teszt PIROS maradna, függetlenül az
implementáció minőségétől. A `vision_safety_policy.dart` saját doc-commentje
(„A future posture metric (R23 / R27) extends this map") és [ADR
0188](0188-vision-safety-claim-guard.md) §Következmények 3. pontja („A
jövőbeli R23 (feedback policy) […] erre a katalógusra épül; a katalógus
bővítése […] mindig új, a guard által ellenőrzött bejegyzést igényel")
**explicit ezt a kört nevezi meg** a bővítés végrehajtójaként — az
`allowed_paths` hiánya mérhetően brief-írási mulasztás volt, nem szándékos
korlátozás. A brief §0.0 revíziója pótolta a fájlt, additív-only korláttal
(lásd Döntés 2).

A brief §5 pont 2 („setup cue előbb, mint technikai") és a §6 „Prioritás-
teszt" a kimenet **sorrendjét** köti, de csak két szintre (setup vs.
technikai + azonos-prioritású döntő determinizmus). Az SDD §23.4 hattagú
javasolt sorrendet ad (nem megfigyelhető/setup → sync-probléma → stabil
nagy-hatású minta → romló forma → kisebb inkonzisztencia → kísérleti) — ez
**javasolt**, nem kötött; a brief kéttagú acceptance-je a mérce, a hattagú
lista implementációs finomítási szabadságfok.

## Döntés

1. **ADR-szám: 0191, nem a sosem realizált „0162".** A brief minden „ADR
   0162" hivatkozása ide mutat.
2. **A `VisionSafetyPolicy.catalog` additív módon bővül; a meglévő 9
   bejegyzés és a `VisionSafetyClaimClass` enum változatlan marad.** Minden
   `InsightCode` egy ÚJ kulcs-érték pár a katalógusban, engedélyezett
   (nem-forbidden) osztállyal; a guard szemantikája (fail-closed, kétirányú
   validáció) nem módosul. A `vision_safety_policy.dart` felkerül az
   `allowed_paths`-ra kizárólag ezzel a korláttal — az R20 lezárt kör
   viselkedése a meglévő 9 kódra bitre változatlan marad.
3. **A domain sosem tartalmaz UI-mondatot.** `InsightCode` + a `FeedbackPolicy`
   paraméterei (capability, confidence-küszöb, minimum időtartam, cooldown,
   prioritás) a teljes döntési felszín; a megjelenítendő szöveg kizárólag
   ARB-ból jön (`visionInsight*` kulcsok), a `feedback_policy.dart` egyetlen
   angol/magyar mondatot sem tartalmazhat, még fallbackként sem (SDD §5.6).
4. **Setup/observability cue mindig megelőzi a technikai cue-t.** Ha egy
   evidence `ObservationState.notObservable` (vagy a mögötte álló
   capability/geometria/frame-minőség elégtelen), a felhasználó setup-jellegű
   visszajelzést kap, sosem technikai kritikát ugyanarra az ablakra (SDD
   §23.3/§23.4 1. hely; brief §5 pont 2). Párhuzamos megjelenítés nem
   elfogadható — ez a `CueBudget` egy-aktív-cue szabályának direkt
   következménye (Döntés 5).
5. **Egyszerre legfeljebb EGY aktív realtime cue, kódonkénti cooldownnal.**
   A `CueBudget` egyetlen jelöltet választ ki egy adott pillanatban; a
   választás determinisztikus azonos-prioritású jelöltek között (brief §6
   „Prioritás-teszt": kétszeri futás azonos). A session-summary ettől
   független, kötöttebb korlátja legfeljebb **két** elsődleges technikai
   fókusz (brief §3).
6. **Aszimmetrikus confidence-küszöb: a negatív (kritikai) insight küszöbe
   szigorúbban magasabb, mint a pozitívé.** Ez az SDD §5.5 „no feedback is
   better than false feedback" elvének gépi alakja — bizonytalan mérésnél a
   hiba iránya mindig a hallgatás felé tolódik, sosem egy alátámasztatlan
   kritikai állítás felé. Azonos küszöb mindkét irányra nem elfogadható.
7. **Pozitív improvement insight csak összehasonlítható ablakokból**: azonos
   gyakorlat, azonos capability-szint, azonos metrika között. Eltérő
   feltételek közti „javultál" állítás nem elfogadható — ez ugyanannak az
   5.5 elvnek a pozitív irányú tükre (hamis pozitív visszajelzés is false
   feedback).
8. **A policy verziózott** (`policyVersion`), és minden emittált insight
   hordozza, melyik verzióval készült — reprodukálhatóság és jövőbeli
   policy-migráció alapja, ugyanaz a minta, mint az evidence
   `thresholdsVersion`/`qualityThresholdsVersion` mezője (ADR 0190).
9. **`ObservationState.experimental` teszt-ága közvetlen `VisionEvidence`
   konstrukciót használ, nem a fúziós pipeline-t.** A mai három
   metrika-katalógusból (fretting/picking/posture) egyik capability-enumnak
   sincs kísérleti értéke (ADR 0190 Döntés 4, örökölt mérés) — a
   `FeedbackPolicyEngine` `experimental`-ágának tesztje ezért a `VisionEvidence`
   konstruktort hívja direktben, nem próbál mesterséges triggert kitalálni a
   valódi fúzión keresztül.

**NEM elfogadható:** hardcode-olt angol/magyar mondat a domainben; egynél
több párhuzamosan megjelenő realtime cue; azonos confidence-küszöb a
pozitív/negatív irányra; a safety-guard lazítása vagy a `declaredClass`
production-hívási felhasználása; a `vision_safety_policy.dart` meglévő 9
bejegyzésének vagy a `VisionSafetyClaimClass` enumnak módosítása.

## Következmények

- `lib/features/vision/domain/feedback/` — új `insight_code.dart` (zárt
  katalógus), `feedback_policy.dart` (kódonkénti kapuk), `cue_budget.dart`
  (egy-aktív-cue + session-summary korlát); `application/feedback_policy_engine.dart`
  (evidence lista → insight lista).
- `lib/features/vision/domain/safety/vision_safety_policy.dart` a Döntés
  2 korlátjával bővül — a jövőbeli R27 (AI Tutor integráció) erre az
  insight-katalógusra épít majd, ugyanazzal az additív-only elvvel.
- `lib/l10n/app_en.arb`/`app_hu.arb` `visionInsight*` kulcsokkal bővül,
  additív módon (meglévő `visionSetup*`/`visionCalibration*` kulcs nem
  módosul).
- A `CueBudget` prioritás-skálája implementációs szabadságfok az SDD §23.4
  hattagú javasolt sorrendjén belül, amíg a kötött két invariáns (setup >
  technikai; azonos prioritás → determinisztikus) áll — egy jövőbeli kör
  finomíthatja a skálát új ADR nélkül, ha a két invariáns nem sérül.
- Az UI-rendering (R24), a fusion módosítása (R22 lezárt), a persistence
  (R28) és a tutor-integráció (R27) kívül esik ezen a körön és az
  `allowed_paths`-on.

## Elutasított alternatívák

- **A safety-katalógus bővítését egy KÜLÖN, jövőbeli körre halasztani (ezt a
  kört a 9 meglévő posture-kódra korlátozni).** Elvetve: a brief scope-ja
  (§3) explicit fretting/picking/posture-t átfogó `InsightCode` katalógust
  ír elő, nem csak posture-t; egy posture-only kör nem teljesítené a §6
  katalógus-tesztet a másik két családra, és egy mesterségesen szűkített
  scope ellentmondana a brief §1 céljának. A halasztás emellett szemben állna
  [ADR 0188](0188-vision-safety-claim-guard.md) explicit R23-hivatkozásával.
- **A guard átmeneti lazítása** (pl. ismeretlen kód → `allowed` fallback,
  vagy a `declaredClass` override production-használata) **a katalógus-fájl
  scope-hoz adása helyett.** Elvetve: pontosan az a fail-closed garancia
  sérülne, amit [ADR 0188](0188-vision-safety-claim-guard.md) a kör
  legfőbb kockázata ellen épített; a guard szándékos, mért kontraktja, hogy
  minden új claim-kód új, ellenőrzött katalógus-bejegyzést igényel.
  Kimerítően mérve: `test/features/vision/domain/safety_claim_guard_test.dart`
  négy generikus teszcellája sértetlen marad.
- **Az SDD §23.4 hattagú prioritási listát szó szerint, kötött enumként
  előírni ebben a brief-revízióban.** Elvetve: a hattagú lista „javasolt
  sorrend" (SDD megfogalmazás), nem kötött szerződés; az implementer
  numerikus prioritás-skálája implementációs részlet, amíg a két kötött
  invariáns (setup-elsőbbség, determinisztikus döntetlen) áll — egy korai
  túlspecifikálás egy jövőbeli finomítást felesleges brief-revízióra
  kényszerítene.
- **Egy második, önálló „setup vs. technikai" enum bevezetése az
  `ObservationState`-től függetlenül.** Elvetve: az R22 evidence-modell
  (ADR 0190) már hordozza a szükséges jelet (`notObservable` = nem
  megfigyelhető), egy párhuzamos fogalom idővel szétcsúszna tőle — ugyanaz
  az elv, mint ami az ADR 0190-et a `MetricDefinition.window` egyszeri
  felhasználására kötötte, párhuzamos ablak-fogalom helyett.
