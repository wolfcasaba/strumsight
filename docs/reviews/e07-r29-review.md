# E07-R29 — Review

Brief: `docs/rounds/e07-r29-accessibility-privacy-hardening.md`
Diff: `d105d7be..8212b0cb` (+ `2aaa487` merge with `origin/main` for CI dispatch)
Reviewer: Codex (független, izolált klón) · Dátum: 2026-08-19
Update: Claude (orchestrátor) — F3 zárás ellenőrzése · Dátum: 2026-08-19
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0 — mind a három lelet (F1/F2/F3)
zárva, tartós regresszióval védve.

Az F1 és F2 a `3e05d243` javításban tartós regressziós tesztet kapott; az
izolált teljes kör-gate zöld. A friss, valós sértéspróba F3-at talált a
`3e05d243`-en; a Codex-eszkalációs javító kör (`8212b0cb`, ld. lent) ezt is
lezárta. Az orchestrátor a `8212b0cb` javítás diffjét saját maga olvasta el
(nem csak a `.codex-round-status` önjelentését fogadta el), és a
`local_repository_test.dart`-ot önállóan, izoláltan lefuttatta: **36/36 zöld**,
köztük az új `F3 — manifest persistence failures` eset. A teljes, még
hátralévő kapu a CI-dispatch (Full Gate + Router CI a végleges HEAD-en).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A6 | A privacy export nem visz ki free textet | ✅ | `planner_privacy_test.dart`, real-violation probe zöld a `fce7dc2f`-en |
| A7 | A user-initiated delete/export minden planner-adatot kezel, más feature adatát nem | ✅ | F1 restart-regresszió + F2 two-plan ownership regresszió + F3 manifest-failure regresszió, mind zöld `8212b0cb`-n |
| A1–A5 | UI, ARB és accessibility változások | ✅ | `planner_accessibility_test.dart` (§10.1/§10.3 evidence map), a §7 round-gate 14/14 zöld a brief §10.6.3 szerint |

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
- **Státusz:** FIXED (`3e05d243`; restart-regresszió a `local_repository_test.dart`-ban)

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
- **Státusz:** FIXED (`0a6315d2`; two-plan default ownership regressziók)

### F3 — MAJOR — A durable manifest írása nincs megvárva, a storage hiba elszakad a mentési eredménytől

- **Fájl:** `lib/features/practice_generator/data/local/local_practice_plan_repository.dart:191-201, 833-835`
- **Probléma:** `_trackWrite`/`_trackRemove` a `Future<void>`-t visszaadó
  `keyValueStore.writeString(manifestKey, ...)` hívást nem várja meg. Ez
  ellentmond a `KeyValueStore` szerződésének („writes never fail silently”).
- **Hatás:** Sikertelen manifest-írásnál a planner mentése `Success`-szal
  tér vissza, a hiba később kezeletlen `StorageException`; így a restart-utáni
  privacy delete/export manifestje hiányozhat anélkül, hogy a user hibát kapna.
- **Mért bizonyíték:** izolált, eldobott teszt a manifest kulcsát
  `failingKeys`-be tette, majd `saveDraft`-ot hívott. A hívás eredménye
  `Actual: <false>` volt az elvárt failure helyett, majd az outputban
  `StorageException(storage.write, key: ss.practice_generator.plan.manifest)`
  kezeletlen aszinkron hibaként jelent meg.
- **Kötelező javítás:** A manifest write/remove legyen a repository async
  írási tranzakciójának része és legyen `await`-elve; hibája `StorageFailure`-
  ként térjen vissza. Adj tartós regressziós tesztet erre a hibautakra.
- **Ellenőrzés:** manifest-kulcsra szimulált write failure esetén a
  `saveDraft`/activate eredménye `Failure`, és nincs unhandled asynchronous
  error.
- **Státusz:** FIXED (`8212b0cb`; `_trackWrite`/`_trackRemove` mostantól
  `await`-eli a `_persistManifest()`-et, a corrupt-pointer ág `StorageException`-t
  rethrow-ol elnyelés helyett; új `F3 — manifest persistence failures`
  regresszió a `local_repository_test.dart`-ban — saját, izolált
  `flutter test test/features/practice_generator/data/local_repository_test.dart`
  futtatással ellenőrizve: **36/36 zöld**, az F3-eset is köztük)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| reviewer round-gate | 14 zöld lépés a `3e05d243`-en | ✅ saját, izolált futtatás |
| implementer round-gate (F3 fix) | `outcome: pass`, `exit_code: 0` a `8212b0cb`-n (brief §10.6.3) | ✅ orchestrátor saját targeted-test futtatással megerősítve (36/36) |
| scope audit | zöld | ✅ saját futtatás; `.codex-round-status` `scope_audit=ok`, `scope_audit_changed=3` |
| review probes | F1/F2/F3 mind zárva | ✅ |
| Router CI | success a `8212b0cb`-n (run 32278531301) | ✅ `gh run list` |
| Full Gate CI | — | ⏳ merge előtt dispatch esedékes (orchestrátor teendője) |

## Merge-döntés

Kódszinten nincs nyitott BLOCKER/MAJOR — a review APPROVED. Merge az ADR 0052
zöld kapuja után engedélyezett: a Full Gate CI dispatch és a Router CI
újrafuttatása a végleges (merge-elt origin/main-t is tartalmazó) HEAD-en még
hátravan, ezt az orchesztrátor a review lezárása UTÁN indítja.
