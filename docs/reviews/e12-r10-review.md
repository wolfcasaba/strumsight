# E12-R10 — Review (Claude, orchestrátor/reviewer)

- **Kör:** `E12-R10` — Idempotens integration dispatcher és outbox
- **Branch:** `sonnet-impl/e12-r10-idempotent-dispatcher-and-outbox`
- **Review-elt HEAD:** `56580e8e`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Javító körök:** 1 (a `stopped` jelzés utáni R7 mérce-felület csere)
- **ADR:** [`0469`](../adr/0469-outbox-idempotency-is-measured-on-the-ledger-effect.md)
- **Módszer:** READ-ONLY review izolált `/tmp/ss-review-e12-r10` klónban, három
  saját, az implementerétől FÜGGETLEN valódi-sértés próbával.

## VÉGSŐ DÖNTÉS: APPROVED

**0 BLOCKER · 0 MAJOR · 0 MINOR · 3 NOTE**

A kör a `lib/**` diff nélkül szállítja a hiányzó MÉRCÉT: kilenc cella, mind a
ledger-HATÁSON mérve. Az orchestrátor három független mutációval igazolta, hogy
a cellák teherhordók — nem dekoráció.

## 1. Amit a kör szállít

| Fájl | |
|---|---|
| `test/core/events/idempotency_test.dart` (230 sor) | **A1** (100 ismétlés egy batch drainben, eltérő `ledgerId`-kkel) + **A1b** (100 × enqueue→drain pár) |
| `test/core/events/outbox_resume_test.dart` (488 sor) | **A2** resume, **A3** out-of-order, **A4** hibatűrés, **A5** karantén-továbbdolgozás, küszöb-hármas × 3 |
| `docs/contracts/event-catalog.md` | „Outbox-invariánsok — MÉRT (E12-R10, ADR 0469)" alszakasz, invariánsonként a mérő cellával |
| `docs/adr/0469-…` | D1–D6 (D1 az 1. javító körben módosítva — lásd §3) |
| `docs/rounds/e12-r10-…` | §0.0 R1–R6 pre-flight + §0.0.0 R7 revízió + §10 handoff |

`lib/**` diff: **NINCS** — a §5.3/D6 szerint javítás csak MÉRT piros cellára
jár, és a mérce-felület cseréje után egyetlen cella sem volt piros a két
engedélyezett `lib/` fájl miatt.

## 2. Gépi mérce — mit futtattam magam

**Scope-audit** (a helyes bázisokon, `python3 tools/scope-audit.py`):

```
Legacy scope audit OK (5f7ccf3e0063..0d8181a0c1ed, 3 changed path(s), 0 generated/ignored)
Legacy scope audit OK (929c8da27f7f..56580e8e7bb8, 4 changed path(s), 0 generated/ignored)
```

> A jelzésfájlban látott két `scope_audit=VIOLATION` mindkét esetben az
> ORCHESTRÁTOR saját artefaktuma volt, nem az implementeré: (1) az első
> futásnál a munkapéldány gyökerébe tett `.round-prompt-e12-r10.md` (nem
> követett fájl, de az audit minden változott utat mér); (2) a javító körnél az
> audit bázisa a `0d8181a0` volt, ezért a saját R7 commitom (`929c8da2`,
> `docs/adr/0469-…`) az auditált tartományba esett. A helyes bázisokon mindkét
> implementer-diff tiszta. **Tanulság a lánc számára: az implementer-promptot
> SOHA ne a munkapéldányba írd** (`/tmp` alá való) — lásd `docs/LESSONS.md`.

**Izolált baseline** (`/tmp/ss-review-e12-r10`, `56580e8e`):

```
00:00 +9: All tests passed!
```

## 3. Az 1. javító kör: a `stopped` HELYES volt

Az első implementer-futás `stopped`-ot jelzett, mert MINDEN cella pirosra bukott
a `ProfileProjector.rebuild()`-en. **Az orchestrátor függetlenül újramérte** egy
eldobható próbateszttel, a VALÓDI `LocalRewardLedgerRepository`-val:

```
00:00 +0 -1: PROBE: rebuild() over a NON-EMPTY single-page real ledger [E]
  Bad state: ledger page cursor did not advance
  package:strumsight/features/gamification/application/profile_projector.dart 49:9  ProfileProjector.rebuild
```

A hiba valós (lásd §5 NOTE-1). A feloldás **nem** a tilos zóna feloldása volt,
hanem a kör SAJÁT, még nem merge-elt artefaktumának revíziója (ADR 0087 §2): a
`rebuild()` csak azért került az útba, mert a pre-flight (ADR 0469 D1) azt
választotta mérce-felületnek. A mérce lényege — a HATÁS, sosem a hívásszám —
változatlan; a felület a `readPage`-en összegzett egyenleg lett (§0.0.0 R7).

## 4. Három FÜGGETLEN valódi-sértés próba (az implementerétől eltérő mutációk)

Mindhárom az izolált klónban futott, a `lib/` visszaállításával utána.

**P1 — a `maxAttempts` feltétel gyengítése** (`>=` → `>`,
`local_activity_outbox_repository.dart:286`) — a §6.1 mátrix erre a sorra a
küszöb-hármas „rajta" celláját ígéri:

```
00:00 +4 -3: Some tests failed.
  … maxAttempts threshold triplet … rajta: … the record is quarantined as attemptLimitReached
  … maxAttempts threshold triplet … fölötte: …
```

PIROS: a „rajta" és a „fölötte" cella (plusz az A5). Az „alatta" cella helyesen
ZÖLD maradt — az a mutáció csak késlelteti a karantént. **A hármas diszkriminál.**

**P2 — nem idempotens ledger** (a `_processedEventIds` szűrés törlése,
`local_reward_ledger_repository.dart:77`) — a dupla HATÁS, amit a kör kizárni
hivatott:

```
00:00 +0 -1: A1 — 100 repeats of one sourceEventId, single batch drain … [E]
  Expected: <10>
    Actual: <1000>
```

**Ez a döntő bizonyíték a D1-re:** egy hívásszám-alapú állítás ezt a mutációt
ZÖLDEN átengedte volna (a hívások száma nem változott), az egyenleg-mérés
viszont százszoros hatást mutat.

**P3 — a perzisztált resume kikapcsolása** (a `_ensureLoaded` pending-visszatöltő
ciklusa üres listán fut):

```
00:00 +0 -1: A2 — resume after a mid-drain process kill … [E]
  Expected: ['activity-crash-resume']
    Actual: MappedListIterable<ActivityOutboxRecord, String>:[]
00:00 +0 -2: A3 — out-of-order delivery matches the sequential run … [E]
  Expected: [20685, 20675]
    Actual: []
```

PIROS: A2 és A3. **A resume tehát a perzisztált állapotból megy** (D3), nem egy
in-memory objektum folytatásából.

## 5. Leletek

Nincs BLOCKER, MAJOR vagy MINOR. Három NOTE:

**NOTE-1 — `ProfileProjector.rebuild()` reziduális L349-hibája (a kör LELETE,
javítása KÜLÖN kör).** A `profile_projector.dart:48–49` stall-guardja egy NEM
ÜRES, de EGYETLEN oldalra férő ledgeren dob: a `readPage` helyesen
`nextCursor: null`-t ad az utolsó (itt: egyetlen) oldalon, az első iteráció
helyi `cursor`-a szintén `null`, tehát `page.entries.isNotEmpty && null == null`.
Az L349 fixe (`be823c74`) csak az ÜRES ledger esetét zárta. A meglévő regresszió
(`level_curve_test.dart:48`) azért nem fogta meg, mert `pageSize: 1`-gyel három
bejegyzésen lapoz — ott az utolsó oldalon a `cursor` már nem `null`.
**Hatás ma:** a `rebuild()`-nek nincs hívója a `lib/` fán, ezért felhasználót
nem ér el — de a Chapter 9 fő use case-e („a profil a főkönyvből teljes
egészében újraépíthető") ma egyetlen bejegyzésnél dobna. **Javasolt javítás:**
a guard csak akkor jelezzen, ha a cursor NEM haladt ÉS az oldal nem az utolsó —
pl. a `page.nextCursor != null && page.nextCursor == cursor` alak. A fájl e kör
tilos zónájában van; a lelet a `docs/LESSONS.md`-be kerül.

**NOTE-2 — A1 és A1b két KÜLÖNBÖZŐ őrt mér, és ez jó így.** A P2 mutáció alatt
az A1 pirosra váltott, az **A1b viszont zöld maradt**: az enqueue-oldali
`hasProcessedEvent` szűrés (`local_activity_outbox_repository.dart:153`) attól a
mutációtól még működött. A két cella tehát nem redundáns — A1 a ledger-oldali,
A1b az enqueue-oldali dedupot méri. Érdemes ezt a szereposztást egy jövőbeli
körben a cellák doc-commentjében is kimondani.

**NOTE-3 — a küszöb-hármas „alatta" cellája report-alakot mér, nem egyenleget.**
Ez helyes (az „alatta" állapot definíció szerint még nem ért a ledgerhez), de
így ez az egyetlen cella, amely nem a HATÁSON zár. A P1 próba igazolta, hogy a
hármas egésze diszkriminál, tehát ez nem gyengeség — csak tudni kell róla.

## 6. Acceptance-teljesítés

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | ✅ | egyenleg **és** bejegyzés-darabszám; P2 pirosra viszi |
| A1b | ✅ | `accepted == false` + `supersededByLedger` a 2. ismétléstől, egyenleg nem nő |
| A2 | ✅ | MÁSODIK repository ugyanarra a store-ra; P3 pirosra viszi |
| A3 | ✅ | out-of-order == sorrendhelyes egyenleg, mindkét `sourceEventId` egyszer, `epochDay` túléli; P3 pirosra viszi |
| A4 | ✅ | két bukó drain után sem dob és nem görget vissza; a harmadik zárja, egyszeres egyenleggel |
| A5 | ✅ | `attemptLimitReached` + a mögötte álló rekord UGYANABBAN a passzban ack-elődik; P1 pirosra viszi |
| küszöb-hármas | ✅ | alatta/rajta/fölötte, a DRAIN ELŐTTI perzisztált számlálón (D5); P1 diszkriminál |
| A6 | ✅ | `event-catalog.md` „Outbox-invariánsok — MÉRT" alszakasz, cellánkénti hivatkozással |

## 7. Merge-feltételek

- Review: **APPROVED**, 0 nyitott lelet.
- Scope-audit: **OK** mindkét implementer-diffre.
- Zöld kapu: a `full-gate.yml` + `router-ci.yml` exact-SHA zöldje a merge SHA-n
  (a `tools/round-ci-plan.py` `dispatch = full-gate.yml`, `native_gate = false`,
  `router_ci_expected = true`).
