# E07-R14 — Review

Brief: `docs/rounds/e07-r14-time-budget-allocator.md`  
Diff: `2595fe22..83881126`  
Reviewer: Codex / gpt-5.6-terra (izolált klón) · Dátum: 2026-08-16  
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1/A4 | Hard maximum és pontos öt-budget összeg | ✅ | `time_budget_allocator_test.dart`, `planner_time_budget_property_test.dart`; az izolált gate zöld. |
| A2/A3/A5/A6 | Determinisztikus blokkok, fragment- és micro-plan szabály | ✅ | célzott unit- és property-tesztek zöldek. |
| A7 | Rövidítés **és hosszabbítás** typed, indokolt change-settel | ❌ | F1: csak a hard-limit miatti rövidítés létezik. |
| A8 | A publikált policy-paraméterek ténylegesen szabályozzák az allokációt | ❌ | F2: `roundingIncrement` és `ceilingMinutes` inert. |

## Scope-audit

Az izolált klónban futtatott audit: `Legacy scope audit OK (2595..83881126, 9 changed, 0 ignored)`.
Engedélyezett fájlokon kívüli implementer-változás: nincs.

## Megállapítások

### F1 — MAJOR — Hiányzik az extend-today typed döntési útja

- **Fájl:** `lib/features/practice_generator/domain/service/time_budget_allocator.dart:40-57,149-180,300-349`
- **Probléma:** `TimeBudgetScaling` csak `none` és `shortened` értéket tartalmaz, `_detectScaling` kizárólag `asked > clamped` esetet jelöl, a `_buildChangeSet` pedig emiatt csak rövidítéskor készül. Az ADR 0298 döntés 4 és a brief §5.6 expliciten a napi keret rövidítését **vagy hosszabbítását** írja elő typed `systemAdaptation` change-ként. A jelenlegi `requestedTotal <= maximum` út `none`-t és `null` change-setet ad, tehát az extend-today viselkedés nem kifejezhető és nincs mérve.
- **Hatás:** a hívó nem tudja bizonyíthatóan megkülönböztetni a felhasználói kérést követő, illetve a rendszer által hosszabbított napi tervet; az ADR szerződése hiányos.
- **Kötelező javítás:** vezess be explicit hosszabbítási scaling/evidence/change-set utat az elfogadott contractnak megfelelő bemenettel, és teszteld, hogy a rövidítéshez hasonlóan typed `PlanChangeReason.systemAdaptation`, `timeBudget` cél és indokolt before/after adat jön létre.
- **Ellenőrzés:** új célzott A7 cella a hosszabbításra, plusz property/fixture, amely a change-setet és az exact/hard-max invariánsokat is méri.
- **Státusz:** OPEN

### F2 — MAJOR — A policy két publikus, dokumentált szerződésmezője nem hat az eredményre

- **Fájl:** `lib/features/practice_generator/domain/policy/time_allocation_policy.dart:53-114,192-201`; `lib/features/practice_generator/domain/service/time_budget_allocator.dart:182-254`
- **Probléma:** a `roundingIncrement` „minden tervezett blokkra alkalmazott floor-rounding step”-ként van dokumentálva, de az allocator csak teljes percekkel (`inMinutes`, `~/`) dolgozik és sehol nem olvassa ezt a mezőt. A `ceilingMinutes` „planned upper bound”-ként publikus, de `templateFor` a 60 perc fölötti minden értéknél ugyanazt az extra-large template-et választja; a mező sehol nem vesz részt döntésben. A meglévő policy-teszt csak default értékeket és konstruktor-validációt mér, ezért egy eltérő értékű policy hibásan zöld marad.
- **Hatás:** a dokumentált policy-provenance félrevezető: a hívó konfigurálhat értéket, amely nem befolyásolja az allokációt. Ez architektúrális/contract-sértés, nem puszta teszthiány.
- **Kötelező javítás:** vagy építsd be mindkét mezőt a determinisztikus elosztási/template-döntésbe a brief/ADR floor-rounding és felső-korlát szabályával, vagy távolítsd el őket a publikus policy-contractból és frissítsd a rövid, kör-saját brief/ADR leírást. Az elfogadott eredményt eltérő (nem default) policy-értékekkel célzott teszteknek kell megkülönböztetniük.
- **Ellenőrzés:** célzott policy/allocator teszt, amely legalább két különböző `roundingIncrement` és egy eltérő `ceilingMinutes` értéknél eltérő, de hard-max-kompatibilis megfigyelhető eredményt vagy dokumentált elutasítást igazol.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ izolált `tools/round-gate.sh` |
| analyze | zöld | ✅ izolált `tools/round-gate.sh` |
| célzott unit/property tesztek | zöld | ✅ 17 allocator + 5 policy + property cella |
| architecture/secrets/l10n | zöld | ✅ izolált `tools/round-gate.sh` |
| teljes CI suite + randomizált property + APK | még nem dispatch-elt | — review-leletek mellett merge nem indítható |

## Merge-döntés

Az ADR 0052 feltételei nem teljesülnek: két nyitott MAJOR lelet van. Javító implementer-kör és ismételt független review szükséges.
