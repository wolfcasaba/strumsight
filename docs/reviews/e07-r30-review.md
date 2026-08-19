# E07-R30 — Review

Brief: `docs/rounds/e07-r30-evaluation-and-epic-closure.md` (§0.0 pre-flight
revízióval)
Diff: `git diff 04c44841893a7676c1aa0415bd36b494cc3cd143...ce9e7ba5e0924dbd5d0a33b45e8a0e62d030c7f4`
(pre-flight commit → implementer commit, izolált klón:
`git clone --branch codex/e07-r30-evaluation-and-epic-closure
https://github.com/wolfcasaba/strumsight.git /tmp/review-e07-r30`)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-19
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nulla hard invariáns-sértés a fixture-korpuszon | ✅ | `planner_golden_fixture_test.dart` zöld (izolált `/tmp` klón); saját valódi-sértés próba (`expectedCandidateIds` → `probe.invalidCandidate`) PIROSRA vitte, majd `git checkout --` visszaállítás után ismét zöld |
| A2 | Azonos bemenet → bitre azonos terv | ✅ | `planner_invariants_property_test.dart`: 80 próba, mindegyikben két egymást követő `generate()` hívás `jsonEncode`-ös bitre-egyezés összevetéssel; a `PracticeGenerationRequest.seed` tartalom-alapú (ADR 0259), nem `PROPERTY_SEED` — a teszt helyesen ezt méri, a `PROPERTY_SEED` csak a próba-választást randomizálja (a meglévő `planner_repair_property_test.dart` mintáját követve) |
| A3 | A property-suite `PROPERTY_SEED`-del fut (42 default) | ✅ | `Platform.environment['PROPERTY_SEED']`, hiányában 42 (a fájl 11-14. sora); saját futtatás `PROPERTY_SEED=7719284`-gyel (a implementer által korábban ki nem próbált érték) is zöld |
| A4 | Az árnyék-mód generál, de nem aktivál | ✅ | `shadow_plan_generator.dart`: saját `_ShadowActivation implements GenerationPlanActivation` (255-262. sor) hívásszámláló, nulla perzisztencia; a fájl importjai (4-24. sor) nem tartalmazzák sem a `data/local/`-t, sem az `active_plan_controller.dart`-ot — grep-pel megerősítve. `ShadowPlanRun.persistentWrites` mindig `0` (66. sor) |
| A5 | A terv-minőségi riport előáll és értelmezhető | ✅ | `tool/practice_plan_eval/plan_quality_report.dart` profilonként `success=`/`hardViolations=`/`activationCalls=`/`persistentWrites=` sort ír, majd összesítést; a §10 handoff idézi a tényleges futás kimenetét (3/3 successful, 0 hard violations) |
| A6 | Késleltetés és memória mérve, §10-ben rögzítve | ✅ | §10: 76 782 mikroszekundum, 3 735 552 byte RSS-delta, explicit "development-box corpus measurement, not an Android performance claim" jelölve |
| A7 | Egyetlen flag sem mozdult | ✅ | `git diff --stat` a teljes diffen: `lib/app/config/feature_flags.dart` NEM szerepel a 7 megváltozott fájl között (saját méréssel, nem az állítás elfogadásával) |
| A8 | A `.github/**` érintetlen | ✅ | ugyanaz a `diff --stat` — nulla `.github/` találat |
| A9 | A completion report megnevezi a nyitott tételeket | ✅ | `docs/sdd/epic-07-completion-report.md` "Open items": human release gate, teljes CI/property/APK mint kötelező merge-evidencia, valós Android-eszköz mérés hiánya, és — különösen — hogy `GenerationOrchestrator.generate()` továbbra is fuzionálja a validálást az aktiválással (a §0.0 architektúra-megjegyzés nyitott következménye, korrektül tovább örökítve, nem elhallgatva) |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e07-r30 --brief
docs/rounds/e07-r30-evaluation-and-epic-closure.md --base 04c44841...`:

```
Legacy scope audit OK (04c44841893a..ce9e7ba5e092, 7 changed path(s), 0 generated/ignored)
```

A 7 megváltozott fájl pontosan a brief (§0.0-revízió utáni) `allowed_paths`
listája — engedélyezett fájlokon kívüli változás: **nincs**.
`.codex-round-status`: `scope_audit=ok`, `gate_shape=ok`.

## Megállapítások

### F1 — NOTE — `ShadowPlanRun.hardViolationCount` hallgat egy `Failure` eredményen

- **Fájl:** `lib/features/practice_generator/application/service/shadow_plan_generator.dart:137-144`
- **Probléma:** ha `orchestrator.generate()` `Failure`-t ad vissza (pl.
  megoldhatatlan validációs hiba javítás után), `plan` `null` lesz, és a kód
  ezért üres `issues` listát rendel a `ShadowPlanRun`-hoz — `hardViolationCount`
  emiatt `0`-t olvas egy ténylegesen hibás futáson is, ahelyett hogy a
  `ValidationFailure.cause`-ban utazó tényleges leleteket surface-elné.
- **Hatás:** ELLENŐRIZVE, hogy ez a kör SAJÁT tesztjeit nem téveszti meg — mind
  a golden fixture, mind a property teszt `result`-ot `isA<Success>()`-ra
  ellenőrzi MIELŐTT `hardViolationCount`-ot olvasná, és a
  `plan_quality_report.dart` is külön `success=` mezőt ír soronként. Egy jövőbeli
  hívó viszont, aki csak `hardViolationCount`-ra hagyatkozna `result` típusának
  ellenőrzése nélkül, hamis "nulla sértés" jelentést kapna egy bukott futáson.
- **Kötelező javítás:** nincs — nem éri el a MINOR/MAJOR küszöböt ebben a
  körben (nincs élő hívó ezen a mintán kívül), de egy jövőbeli, ezt az API-t
  újrahasználó körnek érdemes `ShadowPlanRun.hardViolationCount`-ot a
  `Failure` ágon a `ValidationFailure.cause`-ból táplálnia, vagy a getterhez
  doc-commentet fűznie, hogy csak `Success` mellett értelmezhető.
- **Ellenőrzés:** nem alkalmazandó (NOTE, nem blokkol).
- **Státusz:** OPEN (follow-up jegyzet, nem blokkoló).

## Architektúra és termékhatárok (AGENTS.md §5/§6)

- **Domain-függetlenség:** `shadow_plan_generator.dart` kizárólag
  `practice_generator` domain/application importokat használ (4-24. sor),
  nincs Flutter/Riverpod/Dio import.
- **Kompozíciós gyökér, nem duplikáció:** a `GenerationOrchestrator`-t
  VALÓDI példányként hívja (122-134. sor), a privát `_assemblePlan`-t nem
  írta újra — pontosan a §0.0 iránymutatás szerint. A köztes szolgáltatásokat
  (`SkillEstimateReducer`, `SkillPriorityEngine`, `CandidateSelector`,
  `TimeBudgetAllocator`, `WeeklyScheduler`) a publikus `public.dart`-on át
  használja, saját belső logikát egyik esetben sem duplikál.
- **Nincs rejtett hálózat/perszisztencia:** a teljes diffben nincs `dio`,
  `http`, `SharedPreferences`, fájlrendszer-írás (a `plan_quality_report.dart`
  kizárólag `stdout`-ra ír).
- **Nincs érzékeny adat logban:** a golden fixture-ök statikus, szintetikus
  tanulói profilok (`request.$id` azonosítók, rögzített `DateTime.utc(2026, 8,
  24)` időbélyegek), nincs bennük free-text `userNote`/discomfort mező; a
  riport csak aggregált számokat és stabil exercise/skill ID-kat ír.
- **Lifecycle:** `orchestrator.dispose()` minden `generate()` hívás végén
  meghívva (135. sor), még mielőtt a metódus visszatérne — nincs
  StreamController-szivárgás a shadow-úton.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, §10) | Ellenőrizve (Claude, izolált `/tmp` klón) |
|---|---|---|
| format | zöld | ✅ — `dart format --set-exit-if-changed`: 0 changed |
| analyze | zöld | ✅ — `flutter analyze lib/ test/ tool/`: No issues found |
| test (invariants) | zöld, `PROPERTY_SEED=42` és `=20260819` is | ✅ — újrafuttatva default seeddel ÉS egy harmadik, saját véletlen seeddel (`7719284`) |
| test (golden fixture) | zöld + valódi-sértés próba dokumentálva | ✅ — a próbát ÉN magam is megismételtem (nem csak elfogadtam az állítást): PIROS a rontáskor, ZÖLD a visszaállítás után |
| architecture | zöld | ✅ |
| secrets | zöld | ✅ — 2957 fájl, 0 lelet |
| l10n | zöld | ✅ |
| CI (teljes suite + property + APK) | — (orchestrátor dolga) | ⏳ folyamatban — a review lezárása után dispatch-elve |

## Merge-döntés

ADR 0052 szerint: minden lokális gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
**a review oldaláról a merge nem akadályozott**. A tényleges squash-merge a
CI-dispatch (round-ci-plan.py által kiválasztott workflow + Router CI, ha
releváns) exact-SHA zöld eredménye UTÁN történik, az AGENTS.md §12/§13
szerint.
