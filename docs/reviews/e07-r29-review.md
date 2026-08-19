# E07-R29 — Review

Brief: `docs/rounds/e07-r29-accessibility-privacy-hardening.md`  
Diff: `d105d7be..fce7dc2f`  
Reviewer: Codex (független, izolált klón) · Dátum: 2026-08-19  
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 1 · MAJOR: 1 · MINOR: 0 · NOTE: 0

Az izolált `/tmp/review-e07-r29` klónban a scope-audit zöld volt, de két
eldobható, valós sértést mérő teszt is piros lett. A merge addig tilos, amíg
mindkettőhöz nem tartozik tartós regressziós teszt és a javítás nem megy át a
teljes kör-gate-en.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A6 | A privacy export nem visz ki free textet | ✅ | `planner_privacy_test.dart`, real-violation probe zöld a `fce7dc2f`-en |
| A7 | A user-initiated delete/export minden planner-adatot kezel, más feature adatát nem | ❌ | F1 és F2 eldobható sértéspróba |
| A1–A5 | UI, ARB és accessibility változások | még nem elfogadott | a BLOCKER/MAJOR miatt a teljes verdict nem adható ki |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e07-r29 --brief
docs/rounds/e07-r29-accessibility-privacy-hardening.md --base
d105d7be1f95af1dc97d5bac1fdbbbe8690e7893` → OK; 15 módosított útvonal,
0 generált/ignorált sértés.

## Megállapítások

### F1 — MAJOR — A delete/export elveszíti a korábbi planner-adatok felfedezését restart után

- **Fájl:** `lib/features/practice_generator/data/local/local_practice_plan_repository.dart:156-176, 581-607, 628-687, 756-760`
- **Probléma:** A `knownDraftKeysSync()` és az archive-indexek felfedezése
  kizárólag az in-memory `_writtenKeys` listából történik. Ez a lista új
  `LocalPracticePlanRepository` példányban üres. Az aktív pointeren kívüli,
  korábban eltárolt draftok és archive-only planek ezért restart után sem az
  exportba, sem a delete-all sweepbe nem kerülnek.
- **Hatás:** A „minden practice-planning datum” A7 szerződés hamis; a learner
  kérésére végzett törlés után érzékeny, korábbi adatok a device-on maradnak.
- **Mért bizonyíték:** izolált, eldobott teszt: writer létrehozott
  `restart-draft` draftot és `archive-only-plan` revisiont, majd egy friss
  reader ugyanazon store felett `deleteAllPlanningData()`-t hívott. A teszt
  `Expected: false, Actual: true` értékkel bukott a megmaradt draft keynél.
- **Kötelező javítás:** Tartós, perzisztált planner-owned manifest/migráció
  vagy más, restart-álló felfedezési mechanizmus kell az engedélyezett local
  repository scope-on belül; nem használható process-lokális lista. A
  meglévő, manifest előtti rekordokra is adjon dokumentált, tesztelt utat.
- **Ellenőrzés:** állandó teszt két repository-példánnyal, amely draftot és az
  aktív tervtől eltérő archive-plan rekordot seedel, majd igazolja a delete és
  export hiánytalan eredményét restart után.
- **Státusz:** OPEN

### F2 — BLOCKER — Az alap evidence delete bármely planId-ra az összes evidence-et törli

- **Fájl:** `lib/features/practice_generator/domain/repository/practice_evidence_repository.dart:116-124`
- **Probléma:** Ha nincs `outcomePlanLookup`, a fake az `owner = planId`
  értéket adja minden rekordnak, tehát `deleteForPlan(PlanId('a'))` minden
  tárolt evidence-et eltávolít, függetlenül az outcome eredeti tervétől.
- **Hatás:** Egy felhasználó által indított, plan-scoped privacy delete más
  tervhez tartozó mérési adatot töröl; ez közvetlen adatvesztés és megsérti a
  brief §5.7 szűk határát.
- **Mért bizonyíték:** izolált, eldobott tesztben az alap
  `InMemoryPracticeEvidenceRepository` két külön outcome-idhez tartozó
  rekordot kapott. `deleteForPlan('plan-a')` után a `plan-b` rekord is `null`
  volt (`Expected: not null, Actual: null`).
- **Kötelező javítás:** A plan–outcome tulajdonlást kötelezően, adatalapon kell
  reprezentálni, vagy a delete use case csak a lokális archive tényleges
  outcome-id-jait törölheti. A `null` lookup nem jelentheti azt, hogy minden
  rekord a hívó planhez tartozik.
- **Ellenőrzés:** állandó regressziós teszt az alap implementációval, két
  tervhez tartozó evidence-szel; az egyik terv törlése után a másik sértetlen.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| implementer round-gate | 14 zöld lépés | a későbbi review-lelet miatt újra futtatandó javítás után |
| scope audit | zöld | ✅ saját futtatás |
| review probes | nincs | ❌ két valós sértéspróba piros |
| CI | nincs dispatch | ❌ review után esedékes |

## Merge-döntés

Az ADR 0052 alapján merge tilos: F2 BLOCKER és F1 MAJOR nyitott.
