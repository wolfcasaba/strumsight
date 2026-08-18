# E99-R14 független review — GOV-08

- **Review branch / HEAD:** `minimax/e99-r14-engine-policy-measured` / `75617abcc3916d911c8535ec800be8abb9a7834f`
- **Review base:** `ba99bc562b62205c26650c31ddcff6ebd0c32f54`
- **Módszer:** izolált klón (`/tmp/e99-r14-review.1OSSQn/repo`), scope-audit, célzott gate és eldobható tesztellenőrzések.
- **Verdikt:** **CHANGES REQUIRED**

## MAJOR

### M1 — A kötelező `--epic <kód>` szűrés nincs implementálva

**Hely:** `tools/round-metrics.py:457-458`

A brief D3 egyértelműen `--epic <kód>` szűrést kér az `--engines` statisztikához. A CLI jelenleg maga jelzi, hogy a kapcsoló „jelenleg nem szűkít”, és az értéket sehol nem adja át a parsing/summarizing útnak. Emiatt például `--engines --epic E07` ugyanazt az összes epicet tartalmazó kimenetet adja, nem az E07 mintát.

**Javítás:** az epicet a `következő kör:` eseményből szűrd még a motoronkénti összegzés előtt; egészítsd ki a rögzített-fixtúrás tesztet pozitív és negatív epic-cellával.

### M2 — A tesztek futás közben a tracked production forrást írják át

**Hely:** `tools/tests/test_engine_override_ttl.py:188-236`, `tools/tests/test_round_metrics_engines.py:170-178`

Mindkét falszifikációs teszt közvetlenül felülírja a repository `tools/round-pipeline.sh`, illetve `tools/round-metrics.py` fájlját. A `tearDown` csak normál unittest-lefutáskor állít vissza; párhuzamos futás, megszakítás vagy processzthalál mellett módosított production forrás maradhat, illetve a tesztek versenyezhetnek egymással és a gate-tel. Ez nem biztonságos CI-tesztminta.

**Javítás:** a falszifikációt ideiglenes, külön másolaton futtasd (a szükséges minimális tool/registry függőségekkel), és soha ne írd a checkout tracked fájljait.

### M3 — A D2 teszthorog a brief kizárólagos módosítási zónáján kívül van, és a valódi úttal duplikált logikát tart fenn

**Hely:** `tools/round-pipeline.sh:1441-1503`

A brief §5 csak a motor-override blokkot és a hozzá tartozó log/ntfy hívást engedi módosítani. A `--engine-override-evaluate` új top-level `case` ág ezen kívül van. Ráadásul a TTL/kor ellenőrzést külön implementálja, így a teszt a másolatot, nem a tényleges kör-kiválasztási utat méri.

**Javítás:** távolítsd el a duplikált teszthorgot; a D2 viselkedését a normál motor-override út kontrollált, ideiglenes tesztkörnyezetben mérd. A javítás maradjon a brief engedélyezett fájljain belül.

### M4 — A brief kötelező teljes tooling-suite-ja piros

**Bizonyíték:** az izolált klónban futtatva:

```text
$ /tmp/ss-heal-r12-pytest/bin/python3 -m pytest tools/tests -q
4 failed, 485 passed, 527 subtests passed in 266.81s
```

A hibák:

- `tools/tests/test_orchestrator_rotation.py::IndependenceTest::test_a_terra_led_round_swaps_the_implementer_to_claude`
- `tools/tests/test_orchestrator_rotation.py::IndependenceTest::test_the_legacy_codex_engine_name_is_covered_too` (`codex`, `terra` subtest)
- `tools/tests/test_reviewer_independence.py::ReviewerIndependenceTest::test_halt_rather_than_self_review_when_no_other_engine_exists`

Az alapértelmezett `/usr/bin/python3` ráadásul nem tartalmaz `pytest`-et (`No module named pytest`), ezért a briefben előírt pontos parancs ezen a boxon eleve nem indítható. A hibák látszólag környezeti/baseline eredetűek, de a DoD 3 explicit módon zöld teljes suite-ot követel; ez a kör jelen állapotában nem merge-elhető.

## Ellenőrzések

- `python3 tools/scope-audit.py --repo /home/ubuntu/ss-minimax-e99-r14 --brief docs/rounds/e99-r14-gov-08-engine-policy-measured.md --base ba99bc562b62205c26650c31ddcff6ebd0c32f54` → `OK` (6 változott útvonal).
- `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` → zöld: format, analyze, célzott Flutter-teszt, architecture, secrets, l10n.
- `git diff --check` → zöld.

## Következő lépés

Egy MiniMax javító kör szükséges M1–M3-ra. M4 miatt a javítás után ismét teljes tooling-suite kell; zöld teljes suite nélkül a CI-dispatch és merge tiltott.

## Javítás utáni független re-review — 2026-08-18

- **Javítási commit:** `88910482` (`fix(tools): E99-R14 repair pass — M1 --epic filter, M2 isolated falsification copies, M3 unified evaluate hook`)
- **Friss upstream merge után ellenőrzött HEAD:** `81cc1d23108598391128a257a8b661bc6ec1dff5`

### Lezárt leletek

- **M1 lezárva:** `--engines --epic E07` ténylegesen csak `E07-R*` eseményeket aggregál; pozitív, negatív és részleges-átfedési fixtúrás cellák vannak.
- **M2 lezárva:** a falszifikáció a `engine-profile.sh` és a metrics script ideiglenes másolatán fut. A célzott teszt után a review checkout tiszta maradt.
- **M3 lezárva:** a top-level `--engine-override-evaluate` hook törölve. A kiértékelésnek egy közös implementációja van `tools/engine-profile.sh:evaluate` alatt, amelyet a tényleges motor-override blokk hív.

### Re-review bizonyíték

```text
$ /tmp/ss-heal-r12-pytest/bin/python3 -m pytest \
    tools/tests/test_engine_override_ttl.py \
    tools/tests/test_round_metrics_engines.py -q
17 passed in 0.65s

$ tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
format, analyze, célzott Flutter-teszt, architecture, secrets, l10n: zöld

$ /tmp/ss-heal-r12-pytest/bin/python3 -m pytest tools/tests -q
4 failed, 508 passed, 546 subtests passed in 267.96s
```

Az utolsó futás ugyanazt a négy, E99-R14-től független motor-függetlenségi
hibát adja, mint a javítás előtt. E javításuk a brief §5 szerinti tilos
`round-pipeline.sh` területet vagy a nem engedélyezett tesztfájlokat érintené.

**Végső verdikt: CHANGES REQUIRED / merge tiltott.** A javított E99-R14 diff
önmagában elfogadható, de a brief kötelező teljes tooling-suite DoD-ja nem
teljesül, ezért CI-dispatch és merge nem indítható.

## Friss, upstream-szinkron re-review — 2026-08-18

- **Ellenőrzött HEAD:** `7a1b26466912` (tartalmazza az `origin/main`
  `d67d102a` self-healját).
- **Módszer:** friss GitHub-klón (`/tmp/review-e99-r14-fresh.PEpf4f/repo`),
  scope-audit a tényleges `origin/main` bázishoz, futtatható gate, teljes
  tooling-suite JUnit eredménnyel és célzott kód-/falszifikációs audit.

### Lezárt korábbi leletek

- **M1:** a `--engines --epic` szűrés az aggregáció előtt működik; pozitív,
  negatív és kevert-fixtúrás cellák mérik.
- **M2:** a falszifikációk kizárólag ideiglenes scriptmásolatokat módosítanak.
- **M3:** nincs top-level teszthorog; a driver és a teszt ugyanazt az
  `engine-profile.sh evaluate` kiértékelést használja.
- **M4:** az upstream `80cdb46a` hermetikussá tette a driver-tesztek
  környezetét. A friss teljes suite JUnit-ja: `tests=1063`, `failures=0`,
  `errors=0` (268.467 s).

### MAJOR

#### M5 — Lejárt override-nál elveszik a motor neve a kötelező audit- és ntfy-üzenetből

**Hely:** `tools/engine-profile.sh:163-168`,
`tools/round-pipeline.sh:1773-1776`.

Az `engine_override_evaluate` lejáratkor csak az `EXPIRED` literált írja ki,
majd törli az override-fájlt. A hívó ezt változatlanul naplózza és küldi
értesítésben, ezért a tényleges esemény `MOTOR-OVERRIDE LEJÁRT: EXPIRED`, nem
a brief D2 által megkövetelt `MOTOR-OVERRIDE LEJÁRT: <motor>`. A törlés után a
motor már nem állítható vissza a fájlból, így ez valódi auditálhatósági veszteség.

**Bizonyíték:** a lejárati ágban az egyetlen stdout `EXPIRED`; a hívó ezt
`$evaluate_output`-ként interpolálja. A jelenlegi teszt csak a törlést és az
exit-kódot méri, a log-/notify-üzenet motornevét nem.

**Javítási irány:** az értékelő adja át a lejárt motornevet strukturáltan
(például `EXPIRED:<motor>`), a driver pedig ebből képezze a pontos log- és
ntfy-szöveget; ehhez adj a valódi driver-úton futó regressziós cellát.

### Ellenőrzések

- `python3 tools/scope-audit.py --repo <fresh-clone> --brief ... --base origin/main`
  → `OK` (7 changed path(s), 1 generated/ignored).
- `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart`
  → zöld (format, analyze, célzott teszt, architecture, secrets, l10n).
- `/tmp/ss-heal-r12-pytest/bin/python3 -m pytest tools/tests -q --junitxml=...`
  → JUnit: 1 063 teszt, 0 failure, 0 error.
- `tools/tests/test_engine_override_ttl.py` és
  `tools/tests/test_round_metrics_engines.py` → 17 passed.

**Verdikt: CHANGES REQUIRED.** M5 nyitott; merge tilos a javítás és új
független review előtt.
