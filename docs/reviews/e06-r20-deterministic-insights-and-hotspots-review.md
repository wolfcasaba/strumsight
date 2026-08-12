# E06-R20 — Review

Brief: `docs/rounds/e06-r20-deterministic-insights-and-hotspots.md`
Diff: `git diff origin/main...codex/e06-r20-deterministic-insights-and-hotspots`
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-12
Verdikt: **APPROVED**

**Frissítés (ugyanaz a nap, a kötelező biztonsági review után):** a
dedikált security review (`...-security.md`) egy MINOR leletet talált
(F1 — `firstEvidenceFor` generikus fallbackje kapcsolat nélküli evidence-t
adhatott vissza). Egy körön belüli javító kör lezárta: commit `4f97bf5e`,
ld. F1 lent a „Státusz" mezővel. A gate-eket és a CI-t erre a commitra is
újra futtattam (ld. „Gate-bizonyíték ellenőrzése" táblázat vége).

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 (FIXED) · NOTE: 6 (2 ebben a review-ban + 4 a security review-ban)

Egy kör-közbeni STOP is történt és fel lett oldva, mielőtt ez a review
elindult (ld. „Kör-előzmény" lent) — ez nem review-lelet, hanem a normál lánc
része (user-döntés 2026-07-31).

## Kör-előzmény (a review kontextusához)

Ez a kör két dispatchban futott le, ugyanazon a branchen:

1. **Első dispatch (Terra) → `stopped`.** Az implementer helyesen megállt:
   „A rush/drag, weak-upstroke és low-signal rule küszöbei nincsenek a
   briefben vagy ADR 0238-ban rögzítve; saját értéket nem választhatok." A
   brief §5.1 valóban csak az OD-01/02/03-at (outlier/drift/improvement)
   oldotta fel, a kilenc szabály közül négyet (rush, drag, weak-upstroke,
   low-signal) nem.
2. **Orchestrátor-feloldás (dokumentált brief-revízió, commit `b3c88399`).**
   OD-04/05/06 hozzáadva, mindhárom a repóban MÁR létező, mért precedensre
   alapozva, nem új szám kitalálásával: OD-04 (rush/drag, ±20 ms) —
   megegyezik a Terra saját, már megírt `_biasThresholdMs`-ével és az
   OD-01/02 számpéldáival; OD-05 (weak upstroke, ×1.2) — a meglévő
   `dynamicsAccentThresholdRatio` (E06-R16/ADR 0234) újrahasznosítása a
   Terra saját 1.25-je helyett; OD-06 (low signal quality, ≥0.05) — a
   meglévő `DynamicsGate.clippedEventRatioUnavailable` (ADR 0234)
   újrahasznosítása a Terra saját 0.10-je helyett, **mert a 0.10 mért holt
   kód lett volna**: a `DynamicsGate` 0.05 fölött MINDEN dynamics-metrikát
   (a `clippedEventRatio`-t is) `unavailable`-re állítja, tehát egy 0.10-es
   szabály-küszöb sosem lett volna elérhető éles pipeline-on.
3. **Második dispatch (Terra, ugyanazon a munkapéldányon, `4aec6d85`) →
   `done`.** A két hibás konstans javítva (1.25→1.2, 0.10→0.05), a
   hozzátartozó tesztek frissítve, **plusz egy új, kötelezővé tett
   integrációs teszt** (`insight_rules_test.dart:279-381`), ami a VALÓDI
   `buildDynamicsMetrics`/`DynamicsGate` kimenetén bizonyítja, hogy a
   0.05-ös küszöb elérhető (ratio=0.05 → `degraded`, tüzel), és hogy a
   ceiling tényleg létezik (magasabb clip-arány → `unavailable`, a szabály
   `null`-t ad).

Ez a mérték (mért gyökérok + mért precedens, nem invenció) a review egyik fő
ellenőrzési tárgya volt lent, nem csak elfogadtam bemondásra.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Szabály-mátrix — 18 cella | ✅ | `insight_rules_test.dart` — mind a kilenc szabály trigger+non-trigger párral (18/18 eset lefedve, ld. sor 18-433) |
| 2 | Outlier-küszöb hármas (59.9/60.0/60.1) | ✅ | uo. sor 90-109, `python3 -c` szerint 20×3=60.0 |
| 3 | Drift-küszöb hármas (29.9/30.0/30.1) + 3-páros nem-tüzel | ✅ | uo. sor 131-190 |
| 4 | Rush/drag-küszöb hármas (OD-04, ±20 ms) | ✅ | uo. sor 18-88, helyes polaritás (negatív=korai=rush, pozitív=késő=drag, `timing_metrics.dart:13` doc-comment szerint) |
| 5 | Upstroke-küszöb hármas (OD-05, ×1.2) | ✅ | uo. sor 192-233 |
| 6 | Jelminőség-küszöb hármas (OD-06, ≥0.05) | ✅✅ | uo. sor 265-277 (szintetikus határpár) + sor 279-381 (**valódi** `buildDynamicsMetrics`/`DynamicsGate` integrációs teszt, a §6.1 „ne csak kézzel épített fixture" mérce-sora) |
| 7 | Referenciális integritás | ✅ | `analysis_insight_property_test.dart` — 200 seedelt (`PROPERTY_SEED`, alap 42) trial, factIds/evidenceIds mindegyike létezik; **saját mutáció-próbával függetlenül megerősítve** (ld. lent) |
| 8 | `unavailable` bemenet → csak 1 insight | ✅ | `insight_rules_test.dart:436-450` — mind a kilenc szabály lefut egy unavailable-timing kontextuson, pontosan 1 (`data.insufficient`) tüzel |
| 9 | Maximum-policy — pontosan 4 látható | ✅ | `insight_ranker_test.dart:24-86` — 9 bemenetből 4 látható + 5 rangsorolt `additionalInsights` |
| 10 | Prioritás-ütközés determinizmus (100 futás) | ✅ | uo. sor 88-114 — fordított bemenet, 100 ismétlés, mindig `ruleId` szerinti sorrend |
| 11 | Erősség csak evidence-szel | ✅ | uo. sor 116-125 (ranker-szint) + `insight_rules_test.dart:383-416` (szabály-szint: `CompatibleImprovementInsightRule` az EGYETLEN strength-forrás, és csak explicit, meaningful `previousComparison` mellett tüzel — sosem metrika-érték alapján találja ki) |
| 12 | Lokalizációs paritás | ✅ | `insight_rules_test.dart:460-558` — mind a kilenc szabály valódi trigger-kontextusból kiolvasott `messageKey`/`messageArgs`-a ellenőrizve mindkét ARB-ben; ARB-diff önállóan is ellenőrizve (19+19 sor, 9 kulcs, helyes placeholder-metaadat mindkét nyelven) |
| 13 | Nincs szöveg a kódban | ✅ | uo. sor 452-458 — ASCII-only forrás-ellenőrzés + nincs `AppLocalizations` import |
| 14 | Action sealed | ✅ | uo. sor 560-570 — exhaustive `switch`, default ág nélkül fordul |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**

Kétszeresen ellenőrizve: (1) a gépi `scope_audit=ok` a jelzésfájlban
(`scope_audit_base=b3c88399`, `scope_audit_changed=15`); (2) saját
`git diff --stat origin/main...HEAD` egy friss GitHub-klónban — mind a 15
módosított fájl (a brief önmagán kívül) a §4 listáján van, beleértve az ÚJ
`test/fixtures/analysis/insights/insight_fixtures.dart`-ot (a H3 self-heal
által nyitott könyvtár alatt) és a pre-flight által hozzáadott
`docs/adr/0238-...md`-t. A tilos zóna (`ai_tutor/**`,
`audio_analysis/presentation/**`, `analyze/**`,
`audio_analysis/domain/analysis_insight.dart`) érintetlen.

## Próbatesztek (eldobható, ebben a review-ban futtatva, visszaállítva)

**Valódi-sértés próba (brief §6.1 utolsó sora, kötelező):** a
`RushBiasInsightRule.evaluate()`-et ideiglenesen úgy módosítottam egy
elkülönített `/tmp` klónban, hogy a biztonságos `context.insight()` factory
helyett közvetlenül konstruáljon egy `EvidenceBackedAnalysisInsight`-ot egy
NEM létező factId-vel (`'timing.mutation_probe_fake_metric.v1'`). A
referenciális integritás property **PIROSRA váltott** (`Expected: contains
'timing.mutation_probe_fake_metric.v1' — does not contain`), pontosan a
brief által elvárt módon. Visszaállítva (`git checkout --`), a property újra
zöld. **Ez bizonyítja, hogy a property-teszt valódi védelmet ad, nem csak
dekoráció** — a másik nyolc szabály mindegyike is a SAJÁT biztonságos
`context.insight()` hívásán át tér vissza (nem konstruál közvetlenül), tehát
a védelem nem csak a mintavett szabályra, hanem szerkezetileg mind a
kilencre érvényes.

## F1 javító kör (a security review lelete, ebben a körben lezárva)

### F1 — MINOR — `firstEvidenceFor` kapcsolat nélküli evidence-t adhatott vissza

- **Fájl:** `lib/features/audio_analysis/domain/insights/insight_rule.dart:101-120` (javítás előtt)
- **Probléma (a security review, `...-security.md`, mérve):** ha egy szabály
  által kért `factId` metrikájának nincs a dokumentum evidence-halmazában
  szereplő, nem-üres `evidence`-e, a metódus csendben az ELSŐ timeline
  eseményre/szegmensre/hotspotra esett vissza — a ténnyel való kapcsolat
  nélkül. Formálisan „létező ID" (a referenciális integritás property ezt
  nem kapta el), de szemantikailag hamis „evidence".
- **Hatás:** egy jövőbeli, valódi bekötésnél (Tutor/UI) egy insight
  teljesen kapcsolattalan eseményre mutathatna „bizonyítékként".
- **Kötelező javítás:** a generikus fallback opt-in-né tétele
  (`allowDocumentFallback` named param, alap `false`); csak az
  `InsufficientDataInsightRule` kapja `true`-val (az ő „ténye" definíció
  szerint mindig evidence nélküli unavailable metrika — neki a generikus
  „legalább valamire mutass" horgony helyes).
- **Ellenőrzés:** új teszt (`insight_rules_test.dart`, „rush bias does not
  use unrelated document evidence") — **saját mutáció-próbával
  megerősítve**: a fallback-guard sorának ideiglenes törlésekor ez a teszt
  PIROSRA váltott, visszaállítás után zöld.
- **Státusz:** **FIXED** (`4f97bf5e`, `fix(audio-analysis): constrain
  insight evidence fallback`). Scope-audit erre a commitra is `ok`
  (`scope_audit_base=bd8026ad`, `scope_audit_changed=4` — mind a négy fájl,
  `insight_rule.dart`/`insight_rules.dart`/`insight_rules_test.dart`/a
  brief §10 handoff-frissítése, a §4 listáján belül).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját futás, friss GitHub-klón, `/tmp/review-e06-r20`) |
| analyze | zöld | ✅ (saját futás) |
| test test/features/audio_analysis | zöld (397 teszt) | ✅ (saját futás) |
| test test/property | zöld (89 teszt, `PROPERTY_SEED=42`) | ✅ (saját futás) |
| test test/app | zöld (69 teszt) | ✅ (saját futás) |
| architecture | zöld (12 allowlistelt, meglévő eltérés — nem új) | ✅ (saját futás) |
| secrets | zöld (2343 fájl, 0 lelet) | ✅ (saját futás) |
| l10n parity | zöld (1079 üzenet) | ✅ (saját futás) |
| CI — Full Gate (no APK) | zöld | ✅ [run 31625433658](https://github.com/wolfcasaba/strumsight/actions/runs/31625433658), `headSha=4aec6d85` (implementáció, F1 előtt) |
| CI — Coverage | zöld | ✅ ugyanaz a run |
| CI — Router CI | zöld | ✅ [run 31625428217](https://github.com/wolfcasaba/strumsight/actions/runs/31625428217), a `4aec6d85` push-án |
| CI — Full Gate (no APK), F1 javítás UTÁN | zöld | ✅ [run 31628788354](https://github.com/wolfcasaba/strumsight/actions/runs/31628788354), `headSha=4f97bf5e` |
| CI — Coverage, F1 javítás UTÁN | zöld | ✅ ugyanaz a run |
| CI — Router CI, F1 javítás UTÁN | zöld | ✅ [run 31628779761](https://github.com/wolfcasaba/strumsight/actions/runs/31628779761), a `4f97bf5e` push-án |
| Gate újrafuttatva (friss GitHub-klón, F1 javítás UTÁN) | zöld (398 teszt `test/features/audio_analysis`-ban, +1 az F1 regresszióteszttel) | ✅ (saját futás, `/tmp/review-e06-r20-2`) |

A `round-ci-plan.py` `full-gate.yml`-t adott (natív/release-útvonal nem
érintett) — a döntés géppel ellenőrizve, nem saját ítélettel.

**A kör branchje `4f97bf5e`-n áll (nem egy később, helyben eltűnt
`6997b2b5` amend-en) — mérve:** az implementer (Codex/Terra) a `done`
jelzést a folyamat teljes leállása ELŐTT küldte el, majd — ugyanabban a
futásban — még módosított egyet a brief §10 handoffján (egy redundáns
mondat törlése, nulla nettó hatás a round-brief fájlra `bd8026ad`-hoz
képest, `git diff --stat bd8026ad 6997b2b5` csak a három kódfájlt
mutatja). Az orchestrátor `wait-for-round.sh`-a a KORÁBBI jelzésre tért
vissza, ezért a CI-dispatch és az összes fenti gate-újrafuttatás a
`4f97bf5e`-n történt — ez `6997b2b5`-höz képest bizonyítottan azonos kód,
csak egy dokumentum-mondattal több. A branch szándékosan `4f97bf5e`-n
maradt (a helyi `6997b2b5` amendet a review eldobta,
`git reset 4f97bf5e` + a round-brief fájl visszaállítása), hogy a
merge-elt SHA pontosan az legyen, amit a fenti CI-run-ök ténylegesen
mértek — ne egy soha nem CI-zett, csak helyben létező commit.

## Architektúra és termékhatárok (AGENTS.md §5/§6)

- **Domain-tisztaság:** `domain/insights/insight_rule.dart` és
  `recommended_action.dart` kizárólag domain-belső importot használ
  (`analysis_capability.dart`, `analysis_document.dart`,
  `analysis_hotspot.dart`, `analysis_metric.dart`,
  `analysis_metric_catalog.dart`) — nincs Flutter/Riverpod/Dio/storage
  import, nincs `BuildContext`.
- **`public.dart` contract:** a hat új fájl additív exportja rendben; a
  RÉGI, tilos-zónás `analysis_insight.dart` nem lett érintve vagy exportálva
  újra.
- **Nincs kész szöveg, nincs callback a domainben** — a 13. és 14. acceptance
  pont ezt gépileg bizonyítja.
- **Lab-only `technique.*` kizárás (ADR 0236 boundary):** `AnalysisInsightContext`
  konstruktora explicit `ArgumentError`-t dob, ha a dokumentum bármely
  metrikája `technique.`-vel kezdődik; a `ChordTransitionHotspotInsightRule`
  emellett a hotspot saját `metricIds`-ét is szűri `isPublicMetricId`-vel —
  két független védelmi réteg ugyanarra a határra.
- **Nincs hálózat, nincs secret, nincs nyers audio-mozgatás** — a modul tiszta
  Dart domain/engine kód, bemenete kizárólag a már publikált
  `AnalysisDocument`/kontextus-objektumok.

## Megállapítások

### N1 — NOTE — `LowSignalQualityInsightRule` neve tágabb, mint a mért forrása

- **Fájl:** `lib/features/audio_analysis/engine/insights/insight_rules.dart:268-297`
- **Megfigyelés:** a szabály a `dynamics.clipped_event_ratio.v1` metrikát
  méri (stroke-esemény szintű clipping-arány), nem a nyers
  `AnalysisDocument.signalQuality` (R07) riportot — mert az utóbbi nem
  katalogizált metrika, tehát nem használható `factId`-ként (ADR 0238
  Döntés 2). Ez **dokumentált, tudatos döntés** (brief §5.1 OD-06), nem
  csendes scope-nyújtás — nem lelet a szó szigorú értelmében, de érdemes
  rögzíteni: ha egy jövőbeli kör a nyers `SignalQualityReport`-ot is
  katalogizálja (`quality.*` metric ID), érdemes lesz megfontolni, hogy a
  „low signal quality" rule ezt használja-e a jelenlegi dynamics-proxy
  helyett vagy mellett.
- **Merge-hatás:** nincs, tájékoztató jellegű.

### N2 — NOTE — `TimingInsightEvidence`/`StrokeBalanceInsightEvidence`/`PreviousMetricComparison` bizalmi kontraktusa egy jövőbeli hívóra hárul

- **Fájl:** `lib/features/audio_analysis/domain/insights/insight_rule.dart:164-234`
- **Megfigyelés:** a három caller-supplied evidence-osztály (`TimingInsightEvidence`,
  `StrokeBalanceInsightEvidence`, `PreviousMetricComparison`) csak
  érték-tartományt (véges, nem-negatív) validál a konstruktorban, nem
  `CapabilityStatus`-t — a „csak megbízható mérésből" garancia a JÖVŐBELI
  hívóra hárul, aki ezeket populálja (ma senki, ez a modul bekötetlen). Ez
  konzisztens a brief §9 kockázatában már rögzített, azonos jellegű OD-03
  R25-függőséggel, és nem sérti egyetlen mérhető acceptance criteriont sem
  ma — egy jövőbeli bekötő kör pre-flightjának érdemes explicit ellenőriznie,
  hogy a hívó tényleg csak `available`/`degraded` alapon tölti fel ezeket.
- **Merge-hatás:** nincs, follow-up egy jövőbeli bekötő körnek.

## Merge-döntés

ADR 0052 szerint: minden gate zöld (lokálisan újrafuttatva ÉS a CI-run
linkje zöld, exact-SHA `4aec6d85`) ÉS nincs nyitott BLOCKER/MAJOR/MINOR →
**merge engedélyezett.** A két NOTE nem blokkol.

Dedikált biztonsági review (a brief `risk = "high"` miatt kötelező, AGENTS.md
§15.1): [`docs/reviews/e06-r20-deterministic-insights-and-hotspots-security.md`](e06-r20-deterministic-insights-and-hotspots-security.md) —
ld. külön.
