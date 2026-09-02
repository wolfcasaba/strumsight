# E12-R32 review — Staged rollout 1–20 százalék

- **Reviewer:** Claude (orchestrátor, ADR 0055) — read-only review, production-szerkesztés nélkül.
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `tools/mm-round.sh`).
- **Branch:** `sonnet-impl/e12-r32-staged-rollout-1-to-20-percent` @ `6abbe822` (a `23cdeb09` upstream-szinkron merge után; az eredeti review `a723749d`-n készült)
- **Dátum:** 2026-09-02 (első verdikt), 2026-09-02 újramérés a H7 önjavító kör merge-e után

## VÉGSŐ DÖNTÉS: **APPROVED** — a kör diffje ellen NINCS nyitott lelet, és a §7 gate a H7 önjavító kör merge-e után ZÖLD

A kör négy terméke elkészült, a scope tiszta, a saját mércéje zöld. Az első
verdikt **HALT (H7)** volt, mert a brief §7 gate-je a Kör 30
`freeze_policy_test.dart`-ját is futtatja, és az akkor **az `origin/main`-en is
PIROS** volt (a gyökérok mérése változatlanul a §3-ban). Ezt a
kör-hatáskörön kívüli regressziót a **`4de5643f` (PR #530, E12-R32/H7 önjavító
kör)** javította a `main`-en; a kör-ág az upstream-szinkron (ADR 0087 §0.3)
után tartalmazza. A halt oka tehát megszűnt — lásd §5.

## 1. Scope-audit

| Mérés | Eredmény |
|---|---|
| `scope_audit` (gépi, `mm-round.sh`, base `852633f3`) | `ok`, 5 változott fájl |
| Változott fájlok | `docs/release/rollout-decision.md`, `docs/release/staged-rollout-log.md`, `tool/release/verify_rollout_decision.py`, `test/tooling/rollout_decision_test.dart`, `docs/rounds/e12-r32-…md` (§10) |
| Tilos zóna érintve | nem (`lib/**`, `backend/**`, `.github/**`, `tools/**`, `docs/adr/**`, `docs/release/blockers.md`, `docs/operations/**` mind érintetlen) |

## 2. A diff mért állapota

- `python3 tool/release/verify_rollout_decision.py` (csupasz hívás, a szállított fán) → **exit 0**, `ok — 3 decision row(s), 15 observation row(s)`.
- `test/tooling/rollout_decision_test.dart` → **28/28 cella zöld** (a `round-gate.sh` [3] lépése).
- `dart format` → zöld; `flutter analyze` → zöld.

Reviewer-oldali kódolvasás (leletek nélkül, megerősítésként):

1. **A kettős igazságforrás tartva.** Az ellenőrző a kötelező mutató-halmazt
   és a blokkoló verdikteket a `docs/operations/slo.yaml`-ből olvassa
   (`load_slo_schema`), a küszöböt a `rollout-decision.md` `rollout-steps`
   táblájából (`load_rollout_decision`) — egyik sincs a Python forrásba
   másolva (brief §0.0.1 P2).
2. **Fail-closed parserek.** Hiányzó/üres marker-blokk, alakra nem illő sor,
   oszlopszám-eltérés, ismeretlen `slo.yaml` sor-alak → `VerifyError` → exit 2
   (L566/L571/L573/L575); A9 mind a négy blokkra cellát ad.
3. **A küszöb INKLUZÍV.** `observed < min_hours` a feltétel, és a `23`/`24`/`25`
   cellahármas ténylegesen megkülönbözteti a `<` és a `<=` implementációt — a
   „pontosan rajta" cella pirosra váltana szigorú `>`-nél.
4. **A2 valódi-sértés próba a VALÓS `blockers.md` ellen fut** (nem fixture-
   másolat), és van hozzá izoláló pár-cella tiszta `--blockers` felülírással —
   így az R5 nem takarja el az R6/R7/R8 bukását és fordítva.
5. **Az őszinteség megtartva:** minden megfigyelés-sor `source`-a `manual`, a
   `measured_value` `n/a`/`unknown` párosítása kétirányúan kikényszerített, és
   a napló a kill-switch utat MÉRT `[EMBERI]` előfeltételként jelöli
   (nincs kitalált automatizmus — brief §0 STOP-protokoll).

### NOTE-1 (nem blokkoló, jövőbeli kör anyaga)

Az R7 lefedettség-ellenőrzés (`validate_approved_slo_coverage`) a cohortot
figyelmen kívül hagyja: egy `approved` lépcső, amelynek MINDEN kötelező
mutatója csak `platform:android` bontásban van jelen (az `all` sor nélkül),
átmegy. A `release-dashboard.md` „no silent intersection" szabályát ez nem
sérti, de a Kör 33 (`verify_ga_record.py`) érdemes, hogy a `cohort`-onkénti
teljességet is mérje.

## 3. A (MÁR FELOLDOTT) blokkoló, kör-hatáskörön kívüli regresszió (H7) — az első verdikt oka

```
tools/round-gate.sh test/tooling/rollout_decision_test.dart test/tooling/freeze_policy_test.dart
→ format zöld | analyze zöld | rollout_decision_test ZÖLD | freeze_policy_test PIROS (1)
  outcome=code_failure, exit_code=10, failed_step="test test/tooling/freeze_policy_test.dart"
```

A két bukó cella a `freeze_policy_test.dart` „sanity — the shipped documents
validate against the real tree" csoportjából való. A gyökérok MÉRVE:

```
$ git checkout --detach origin/main && python3 tool/release/verify_freeze.py
verify_freeze: 1 finding(s):
  - backend/tests/test_production_smoke_contract.py: not classified under any
    freeze change class … commit message: '[E12-R31] Production deployment és
    internal production cohort (ADR nincs) (#527)…' (A1)
exit 1
```

- A hibát a **már merge-elt `accd30c2` (E12-R31, PR #527)** okozza: a
  freeze-korszakban felvett `backend/tests/test_production_smoke_contract.py`
  egyik freeze-osztályba sem esik (`docs/`, `CHANGELOG.md`, `tool/release/`,
  `test/tooling/`, vagy `blocker-fix` egy hivatkozott P0/P1/P2 id-vel).
- **Az `origin/main` maga is piros** erre a mércére — a bukás E12-R32 diffje
  NÉLKÜL is reprodukálható (a fenti detached-HEAD mérés).
- **Miért nem fogta meg a CI:** a `freeze_policy_test.dart` sanity cellái
  shallow klónban (`actions/checkout` alapértelmezés) a fail-closed ágat
  állítják (exit 2, elérhetetlen freeze-base), tehát CI-ban zöldek; a
  teljes-történetű boxon viszont ténylegesen osztályoznak. A Full Gate zöldje
  ezt a hibaosztályt szerkezetileg nem látja.

**Miért nem javítja ez a kör:** a feloldás a
`docs/release/feature-freeze.md` módosítása (a `release-tooling` osztály
kiterjesztése a `backend/tests/`-re, VAGY a `freeze_base_sha` előreléptetése)
— ez a fájl a Kör 30 merge-elt terméke, és **nincs rajta a kör
`allowed_paths` listáján** (H3), a viselkedése pedig egy lezárt kör
szerződése (H2). A mérce nem lazítható a gate_tests szűkítésével sem: a brief
A6 cellája kifejezetten a `freeze_policy_test.dart` változatlan zöldjét kéri.

## 4. Javasolt feloldás az önjavító kör számára (MEGVALÓSULT — `4de5643f`, PR #530)

1. `docs/release/feature-freeze.md` `freeze-classes` táblájában a
   `release-tooling` osztály útvonal-listája egészüljön ki a
   `backend/tests/` prefixszel (a `backend/tests/**` ugyanolyan
   release-tooling jellegű, mint a `test/tooling/**`) — VAGY a
   `freeze_base_sha` léptetése a Kör 31 merge-commitja utáni SHA-ra, ha a
   program szándéka a freeze-korszak újraindítása.
2. A `freeze_policy_test.dart:85-101` `--since` cellájának kipinnelt
   `4ac78365` konstansát az 1. pont választásával összhangban kell tartani.
3. Ezután a `tools/round-gate.sh test/tooling/rollout_decision_test.dart
   test/tooling/freeze_policy_test.dart` újrafuttatása, és a kör a
   CI-dispatch → merge lépésnél folytatható — az E12-R32 diffje ellen nincs
   nyitott lelet.

## 5. Újramérés a H7 önjavító kör merge-e után (2026-09-02, második session)

A `main` időközben megkapta a `4de5643f` (PR #530) javítást: a
`docs/release/feature-freeze.md` `release-tooling` osztálya kiterjedt a NEM
szállított verifikációs útvonalakra (köztük a `backend/tests/`-re), és a Kör 30
`freeze_policy_test.dart` +45 sorral bővült a hozzá tartozó cellákkal. A kör-ág
az ADR 0087 §0.3 szerinti upstream-szinkronnal (`merge --no-ff origin/main`,
`23cdeb09`, konfliktusmentes, `git diff --check` tiszta) felvette ezt.

| Mérés a szinkronizált `6abbe822` HEAD-en | Eredmény |
|---|---|
| `tools/round-gate.sh test/tooling/rollout_decision_test.dart test/tooling/freeze_policy_test.dart` | **MINDEN GATE ZÖLD** — format, analyze, `rollout_decision_test` (28 cella), `freeze_policy_test` (36 cella), architecture, secrets (4186 fájl, 0 lelet), l10n (en→hu 2298 üzenet) |
| `python3 tool/release/verify_rollout_decision.py --log docs/release/staged-rollout-log.md` | exit 0 — `ok — 3 decision row(s), 15 observation row(s)` |
| `python3 tools/scope-audit.py --base origin/main` | `Legacy scope audit OK (23cdeb09679c..6abbe822e9e5, 6 changed path(s), 1 generated/ignored)` |
| A kör saját diffje (`git diff --name-only origin/main HEAD`) | `docs/release/rollout-decision.md`, `docs/release/staged-rollout-log.md`, `tool/release/verify_rollout_decision.py`, `test/tooling/rollout_decision_test.dart`, `docs/rounds/e12-r32-…md`, `docs/reviews/e12-r32-review.md` (a review saját jelentése — L251) |

A §2 kódolvasás leletei változatlanok: nincs nyitott BLOCKER/MAJOR/MINOR. A
NOTE-1 (R7 cohort-lefedettség) továbbra is nem blokkoló, a Kör 33 anyaga.

**A merge feltétele innen:** exact-SHA CI (Full Gate + Router CI) a merge SHA-n.
