# E07-R14 — Review

Brief: `docs/rounds/e07-r14-time-budget-allocator.md`
Diff: `2595fe22..d3ca4cfc`
Reviewer: Codex / gpt-5.6-terra (izolált klón) · Dátum: 2026-08-16
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1/A4 | Hard maximum és pontos öt-budget összeg | ✅ | `time_budget_allocator_test.dart`, `planner_time_budget_property_test.dart`; az izolált gate zöld. |
| A2/A3/A5/A6 | Determinisztikus blokkok, fragment- és micro-plan szabály | ✅ | célzott unit- és property-tesztek zöldek. |
| A7 | Rövidítés **és hosszabbítás** typed, indokolt change-settel | ✅ | `extendToday`, `extended` scaling, typed evidence és 80-trial property cella. |
| A8 | A publikált policy-paraméterek ténylegesen szabályozzák az allokációt | ✅ | Nem-default rounding- és ceiling-policy unit/property cellák. |

## Scope-audit

Az ismételt izolált audit: `Legacy scope audit OK (2595fe22..d3ca4cfc8e86, 10 changed path(s), 1 generated/ignored)`.
Engedélyezett fájlokon kívüli implementer-változás: nincs.

## Megállapítások

### F1 — MAJOR — Hiányzik az extend-today typed döntési útja

- **Fájl:** `lib/features/practice_generator/domain/service/time_budget_allocator.dart:40-57,149-180,300-349`
- **Probléma:** `TimeBudgetScaling` csak `none` és `shortened` értéket tartalmaz, `_detectScaling` kizárólag `asked > clamped` esetet jelöl, a `_buildChangeSet` pedig emiatt csak rövidítéskor készül. Az ADR 0298 döntés 4 és a brief §5.6 expliciten a napi keret rövidítését **vagy hosszabbítását** írja elő typed `systemAdaptation` change-ként. A jelenlegi `requestedTotal <= maximum` út `none`-t és `null` change-setet ad, tehát az extend-today viselkedés nem kifejezhető és nincs mérve.
- **Hatás:** a hívó nem tudja bizonyíthatóan megkülönböztetni a felhasználói kérést követő, illetve a rendszer által hosszabbított napi tervet; az ADR szerződése hiányos.
- **Kötelező javítás:** vezess be explicit hosszabbítási scaling/evidence/change-set utat az elfogadott contractnak megfelelő bemenettel, és teszteld, hogy a rövidítéshez hasonlóan typed `PlanChangeReason.systemAdaptation`, `timeBudget` cél és indokolt before/after adat jön létre.
- **Ellenőrzés:** új célzott A7 cella a hosszabbításra, plusz property/fixture, amely a change-setet és az exact/hard-max invariánsokat is méri.
- **Státusz:** FIXED (`d3ca4cfc`): explicit `extendToday` bemenet, `extended` scaling és `timeBudget.extendedToAvailable` evidence; unit- és 80-trial property-cellával ismét ellenőrizve.

### F2 — MAJOR — A policy két publikus, dokumentált szerződésmezője nem hat az eredményre

- **Fájl:** `lib/features/practice_generator/domain/policy/time_allocation_policy.dart:53-114,192-201`; `lib/features/practice_generator/domain/service/time_budget_allocator.dart:182-254`
- **Probléma:** a `roundingIncrement` „minden tervezett blokkra alkalmazott floor-rounding step”-ként van dokumentálva, de az allocator csak teljes percekkel (`inMinutes`, `~/`) dolgozik és sehol nem olvassa ezt a mezőt. A `ceilingMinutes` „planned upper bound”-ként publikus, de `templateFor` a 60 perc fölötti minden értéknél ugyanazt az extra-large template-et választja; a mező sehol nem vesz részt döntésben. A meglévő policy-teszt csak default értékeket és konstruktor-validációt mér, ezért egy eltérő értékű policy hibásan zöld marad.
- **Hatás:** a dokumentált policy-provenance félrevezető: a hívó konfigurálhat értéket, amely nem befolyásolja az allokációt. Ez architektúrális/contract-sértés, nem puszta teszthiány.
- **Kötelező javítás:** vagy építsd be mindkét mezőt a determinisztikus elosztási/template-döntésbe a brief/ADR floor-rounding és felső-korlát szabályával, vagy távolítsd el őket a publikus policy-contractból és frissítsd a rövid, kör-saját brief/ADR leírást. Az elfogadott eredményt eltérő (nem default) policy-értékekkel célzott teszteknek kell megkülönböztetniük.
- **Ellenőrzés:** célzott policy/allocator teszt, amely legalább két különböző `roundingIncrement` és egy eltérő `ceilingMinutes` értéknél eltérő, de hard-max-kompatibilis megfigyelhető eredményt vagy dokumentált elutasítást igazol.
- **Státusz:** FIXED (`d3ca4cfc`): a ceiling mint effective upper bound és a non-primary slotok floor-roundingja a policy-ból olvasódik; eltérő policyval unit- és 60-trial property-cellák mérik.

### F3 — MINOR — Stale belső doc-link

- **Fájl:** `lib/features/practice_generator/domain/service/time_budget_allocator.dart:246-247`
- **Probléma:** a `_decideScaling` doc-comment a már átnevezett `_detectScaling` metódusra hivatkozik.
- **Hatás:** csak API-dokumentációs pontatlanság, futási viselkedést nem érint.
- **Javasolt követés:** a következő, ezt a fájlt érintő körben nevezd át a hivatkozást.
- **Státusz:** OPEN (MINOR)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ izolált `tools/round-gate.sh` |
| analyze | zöld | ✅ izolált `tools/round-gate.sh` |
| célzott unit/property tesztek | zöld | ✅ ismételt izolált futás: 25 allocator + 5 policy + 3 property cella |
| architecture/secrets/l10n | zöld | ✅ izolált `tools/round-gate.sh` |
| teljes CI suite + randomizált property + APK | még nem dispatch-elt | — a review zöld; a merge előtti CI még kötelező |

## Merge-döntés

Az ismételt független review szerint nincs nyitott BLOCKER vagy MAJOR. A CI exact-SHA evidence és a záró diff-check után az ADR 0052 szerinti merge engedélyezett.
