# Review — E04-R13: TutorModelGateway és scripted fake

- **Kör:** E04-R13 · **Branch:** `codex/e04-r13-model-gateway-and-fake`
- **Implementer motor:** qwen-plus (`qwen/qwen3.7-plus`, codex-harness, ADR 0140)
- **Orchestrátor / reviewer:** Claude (Opus 4.8) — független, read-only
- **Base:** `main` @ `5d082dc` · **Review-fej:** `8ebab6a` (+ e review-commit)
- **Verdikt:** ✅ **APPROVED** — 0 BLOCKER, 0 MAJOR, 0 MINOR, 3 NOTE
- **ADR:** nincs új — a kör **ADR 0131** (provider-boundary) hatálya alatt (§0.0)

## 1. Jelzés + handoff

A záró implementer-jelzés `status=done` (`head=8ebab6a`, „gate zöld").
A `done`-t **nem** fogadtam el bemondásra: a gate-et magam futtattam újra
izolált `/tmp/review-e04-r13` klónban. A kör két javító körön ment át
(qwen mindkétszer jelzés nélkül `unknown`-ra esett token-kimerülés miatt, de
a munkát commitolta; a hiányokat az orchestrátor mérte ki és javító körökkel
zárta — ld. §4).

## 2. Gate — független újrafuttatás (`/tmp/review-e04-r13`, izolált klón)

```
tools/round-gate.sh test/features/ai_tutor/data
```

| Lépés | Eredmény |
|---|---|
| format | zöld |
| analyze | zöld |
| test (`test/features/ai_tutor/data`, 69 teszt) | zöld — All tests passed! |
| architecture | zöld |
| secrets | zöld |
| l10n | zöld |

## 3. Scope-audit

`git diff --stat origin/main...HEAD` → **8 fájl**, mind a §0.0-revideált
engedélyezett listán belül (5 production `data/model_gateway/*.dart` + 2 teszt +
a brief). **`public.dart` érintetlen** (a §0.0 szűkítés betartva; az
`ai_tutor_boundary_test.dart` üres-boundary invariánsa sértetlen). Listán kívüli
fájl: **nincs**.

## 4. Acceptance criteria — tételes bizonyíték

| §6 kritérium | Bizonyíték |
|---|---|
| ordered events | `contract_test` „ordered events arrive in sequence" — zöld |
| duplicate terminal event | `contract`+`fake` „duplicate terminal … only first" — a `_terminalEmitted` guard, zöld |
| first-event / inactivity / total **mátrix (alatta/rajta/fölötte)** | `fake_test` „timeout matrix" mindhárom timeoutra below/**at**/above (F2+F4 után), injektált `FakeClock` — zöld |
| cancel | „cancel closes the stream" — determinisztikus, zöld |
| late event | „late event after terminal is silently dropped" — zöld |
| tool-call | „tool-call event is emitted" — zöld |
| malformed event | „malformed events pass through" (nem crash) — zöld |
| health | fake success / stub failure — zöld |
| local stub capability-unavailable | `stub start/health` → `Failure(code: 'tutor.model_gateway.unavailable')` — zöld |
| közös contract-suite fake+stub | a `withTimeouts` helper + a suite mindkét implementációt fedi |
| **nincs cloud secret** (reviewer-mutáció pirosra vált) | **mért** — ld. §5 |

## 5. Próbatesztek (eldobható mutációk — visszaállítva)

A §6 „provider-mező/secret hozzáadása pirosra váltja" előírást **méréssel**
igazoltam a `/tmp` klónban (mindkettő visszaállítva, working tree tiszta):

- **Mutáció A — hardcoded cloud secret** a gatewaybe
  (`const String _leakedApiKey = 'sk-live-…'`): a `secrets` gate-lépés
  **pirosra vált** — „Secret scan failed … 2 finding(s): provider token literal /
  credential assigned a long literal". ✅
- **Mutáció B — provider-SDK import** (`package:openai_dart/…`): `analyze`
  **piros** — `uri_does_not_exist` (a provider SDK nincs a `pubspec`-ben, így az
  analyzer maga zárja a határt). ✅

A provider-függetlenség tehát nem csak konvenció: a gate két lépése is
kikényszeríti.

## 6. Architektúra + termékhatárok

- A `TutorModelGateway` `abstract interface class`, csak `AppResult` +
  domain/event típusokat használ; **nincs Flutter UI import, nincs provider-SDK
  import** (ADR 0131 betartva). Az esemény-hierarchia `sealed` (kimerítő
  pattern-match).
- Lifecycle: a fake `cancel()`/terminal minden úton `_cleanup()`-ot hív, a
  `StreamController`-t lezárja; a `withTimeouts` `closeWrapper()` minden
  timeout/hiba/cancel ágon lezár és a forrás-subscription-t bontja. Erőforrás-
  szivárgás nem mért.

## 7. Leletek

Nincs BLOCKER / MAJOR / MINOR. Három nem-blokkoló NOTE (follow-up a hívó
körökre):

- **NOTE-1:** `LocalTutorModelGatewayStub` a nyers `'tutor.model_gateway.unavailable'`
  string-kódot adja `FailureCode` konstans helyett. A `FailureCode` a
  `core/foundation`-ben él, ami e kör tilos zónája — ezért ez in-scope pragmatikus
  választás; amikor a hívó (R16) beköti, érdemes `FailureCode` konstanssá emelni.
- **NOTE-2:** az inaktivitási/teljes timeout **helper (`withTimeouts`) a teszt-
  fájlban él**, nem production kódban, bár a brief §3 in-scope „helper"-ként
  említi. E körben elfogadható: a gateway nyers streamet ad, a valódi timeout-
  kényszerítés a transport (R15) dolga. Ha R14/R15-nek production helper kell,
  ott promotálandó.
- **NOTE-3:** a fake `start()` `disposed` és `already-running` esetre is
  ugyanazt az `UnknownFailure(FailureCode.unknown)`-t adja — a két ok nem
  megkülönböztethető. Kozmetikai; follow-up.

## 8. Javító körök zárása

- **F1** (MAJOR→zárva): 2 használatlan import a contract-tesztben → `analyze`
  pirosra fogta; javító kör #1 (`c39d0b5`) eltávolította.
- **F2** (MAJOR→zárva): hiányzó „rajta"/at-threshold timeout esetek → #1
  hozzáadta; a §6 mátrix teljes.
- **F3** (BLOCKER→zárva): az 5 production fájl untracked maradt (a branch
  fordíthatatlan volt) → javító kör #2 (`d6fa971`) `git add -A`-val bevitte.
- **F4** (BLOCKER→zárva): `FakeClock` (szinkron) vs `StreamController`
  (aszinkron) sequencing-hiba az inaktivitási teszten → #2 (`d6fa971`, majd
  `8ebab6a`) event-queue ürítés + pontosított `emitsInOrder([Delta, emitsError])`
  assertion. Mindegyik hibát a gate PIROSRA fogta a javítás előtt; a zárást a
  zöld gate igazolja.

## 9. Merge-döntés

Zöld kapu minden eleme (format/analyze/architecture/secrets/l10n + a CI teljes
suite + property + APK a branch-fejen) → **squash-merge** engedélyezett.
`main` a dispatch óta `5d082dc`-n áll (nem mozdult). A merge-evidencia a
branch-fejre futó `build-apk` run, exact-SHA.
