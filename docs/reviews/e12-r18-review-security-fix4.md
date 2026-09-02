# E12-R18 — független biztonsági review (fix4 re-review), READ-ONLY

- **Vizsgált SHA:** `cc2a7699` (fix4 commitjai: `646f58ef`, `77290fe8`, `cc2a7699`)
- **Izolált klón:** `/tmp/e12r18-rev2` (detached HEAD `cc2a7699`), `bash tools/prepare-flutter-generated.sh` lefutott
- **A kör-munkapéldány (`/home/ubuntu/ss-sonnet-impl-e12-r18`) és a `main` repó NEM módosult** — minden rontás a klónban történt, minden probe után `git checkout -- <fájl>`; a klón `git status --porcelain` a mérések végén ÜRES.
- **Kiindulási mérce:** `python3 tool/release/security_scan.py --only guards` → `OK` **EXIT=0**; `python3 tool/release/security_scan.py` → `OK` **EXIT=0**

---

## 1. Leletenkénti zárás-ellenőrzés (mind a VALÓS fa rontásával mérve)

| Lelet | Státusz | Mért bizonyíték |
|---|---|---|
| **ÚJ-1a** — Dart `group(..., skip: …, () {…})` (argumentum-FEJ) | **ZÁRVA** | §1.1 |
| **ÚJ-1b** — Dart `group('…', () {…}, skip: 'reason')` (callback UTÁN, kanonikus alak) | **ZÁRVA** | §1.1 |
| **ÚJ-2** — behúzott, modul-szintű `pytest.skip(..., allow_module_level=True)` | **ZÁRVA** (`if os.environ...` és `if True:` alak is) | §1.2 |
| **ÚJ-3** — modul-szintű `pytest.importorskip(...)` | **ZÁRVA** (0. oszlop és behúzott alak is) | §1.3 |
| **ÚJ-4** — az S10/S11 cellák nem mutation-kill tanúk | **ZÁRVA** | §3, a `30651086^` eszközzel mindkettő PIROS |
| **ÚJ-5** — `_python_class_skip_disabled` hamis pozitív modul-szintű guard-`def`-re | **ZÁRVA** | §1.4 |
| **ÚJ-6** — `--only guards` nem tölti be a kivétel-nyilvántartást (docstring) | **ZÁRVA** (dokumentálva + mérve) | §1.5 |
| **S14** — degenerált fixture az S8 „library-szintű `@Skip`" cellán | **ZÁRVA** | §3, a `4783c9f7` (pre-S8-fix) eszközzel PIROS |

### 1.1 ÚJ-1 — mindkét alak ZÁRVA

Rontás a valós fán, `test/privacy/consent_enforcement_test.dart`, az `A4` group (a `T-EGRESS-01`,
AGENTS.md §5.1 „nyers audio nem hagyja el az eszközt consent nélkül" mérője).

**(b) `skip:` a callback UTÁN** — a fix3-ban visszanyílt, kanonikus `package:test` alak.
A 175. sor `  });` → `  }, skip: 'temporarily disabled');`:

```
$ python3 tool/release/security_scan.py --only guards
security_scan: 1 finding(s).
- [critical] guards: T-EGRESS-01 (client-egress): guard.test 'upload() with consent false never touches
  the wire adapter' is present but disabled (skip/xfail marker) in test/privacy/consent_enforcement_test.dart
  — a silenced protection is release-blocking, not a silent regression (ADR 0481 D2) (T-EGRESS-01)
GUARDS_EXIT=1
$ python3 tool/release/security_scan.py
FULL_EXIT=1
```

**(a) `skip:` az argumentum-fejben** — `..., skip: 'temporarily disabled', () {`:

```
$ python3 tool/release/security_scan.py --only guards
- [critical] guards: T-EGRESS-01 ... is present but disabled (skip/xfail marker) ...
GUARDS_EXIT=1
```

**Az S13 hamis-pozitív cellák NEM nyíltak vissza** (mind a VALÓS fán mérve, `GUARDS_EXIT=0`):

| S13-vektor | Mért |
|---|---|
| S13a — testvér `test('a flaky sibling', () {...}, skip: 'flaky on CI')` ugyanabban a groupban | `OK`, **EXIT=0** |
| S13b — `skip:`-alakú részlet a group SAJÁT leírás-stringjében (`'... (never skip: true)'`) | `OK`, **EXIT=0** |
| S13d (saját, új probe) — egy TELJESEN FÜGGETLEN, `}, skip: 'disabled');` alakban skippelt testvér-group a fájlban | `OK`, **EXIT=0** |

Az S13d azért fontos: az új `_dart_call_own_text` a beágyazott hívásokat maszkolja; ha a maszkolás
elszivárogna, egy szomszédos skippelt group is elbuktatná a guardot. Nem szivárog.

### 1.2 ÚJ-2 — ZÁRVA

Rontás: `backend/tests/test_diagnostics.py` (3 guard hordozója, `T-DIAG-01/02/03`).

```python
import os
import pytest

if os.environ.get('STRUMSIGHT_FAST_CI') != '0':
    pytest.skip('slow suite', allow_module_level=True)
```

```
$ python3 tool/release/security_scan.py --only guards
security_scan: 3 finding(s).
- [critical] guards: T-DIAG-01 ... is present but disabled (skip/xfail marker) ...
- [critical] guards: T-DIAG-02 ...
- [critical] guards: T-DIAG-03 ...
GUARDS_EXIT=1
$ cd backend && python3 -m pytest tests/test_diagnostics.py -q ; echo $?
PYTEST_RC=5      # = no tests collected → a némulás valós, nem feltételezés
```

`if True:` alakkal ugyanez: **3 finding, EXIT=1, PYTEST_RC=5**.
Regresszió-ellenőrzés a 0. oszlopos (S11-es) alakra: **3 finding, EXIT=1, PYTEST_RC=5** — nem nyílt vissza.

### 1.3 ÚJ-3 — ZÁRVA

```
# backend/tests/test_diagnostics.py elejére: `pytest.importorskip('some_optional_dep')`
$ python3 tool/release/security_scan.py --only guards   → 3 finding, GUARDS_EXIT=1 ; PYTEST_RC=5
# ugyanez `if True:` alá behúzva
$ python3 tool/release/security_scan.py --only guards   → 3 finding, GUARDS_EXIT=1 ; PYTEST_RC=5
```

### 1.4 ÚJ-5 — ZÁRVA (izolált probe-bal)

Az előző review probe-ja (`@pytest.mark.skip`-elt független osztály közvetlenül a modul-szintű guard-`def`
FÖLÉ) **még mindig EXIT=1-et ad**, de ez NEM a `_python_class_skip_disabled`, hanem a `def`-lokális
400 karakteres előtag-ablak (`_PY_SKIP_MARKERS`) — a két hatás keveredik. Ezért a `class`-t 30 filler
metódussal az ablakon KÍVÜLRE toltam:

```
$ # mért távolság a trivia-stripelt szövegben:
UJ-5 STRIPPED class->def distance: 2589   (>400 = az ablakon kívül)
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
GUARDS_EXIT=0
$ cd backend && python3 -m pytest tests/community/test_access_policy.py -q \
      -k test_a2_blocked_public_profile_returns_summary
.    [100%]      # a guard FUT és ÁTMEGY → a hamis pozitív megszűnt
```

Ellenőriztem, hogy a szűkítés **nem ölte meg az S12 igaz pozitívot**: ugyanez a rontás a guard SAJÁT
osztályán (`backend/tests/test_hardening.py`, `class TestAuthThrottle:` + 30 filler, stripelt távolság
**2589**) → `T-API-02 ... is present but disabled`, **EXIT=1**.

### 1.5 ÚJ-6 — ZÁRVA

A modul-docstring (és így a `--help`) most kimondja: „Under `--only guards`, the exceptions registry is
never loaded at all, so a LIVE `branch: guards` exception has NO effect there … This is intentionally the
stricter (fail-closed) direction, not a bug."
Mérve is: élő `branch: guards` kivétel a `T-EGRESS-01`-re, a guard rontva:
`--only guards` → **EXIT=1** (nem nyom el), teljes futás `--secrets-cmd true` → **EXIT=0** (elnyom, ez a
dokumentált, tulajdonos+lejárat mögé kötött viselkedés).

---

## 2. Regresszió-tábla (a korábban ZÁRT leletek)

Minden sor a VALÓS fa rontásával, `python3 tool/release/security_scan.py --only guards`.

| Korábbi lelet | Vektor | Mért | Visszanyílt? |
|---|---|---|---|
| **S8** (Dart) | `@Skip('whole file disabled')` + `library;` a fájl elején (`check_secrets_test.dart`) | `T-RELEASE-02 ... disabled`, **EXIT=1** | NEM |
| **S8** (Dart, group) | `group(..., skip:, () {...})` az `A4`-en | `T-EGRESS-01 ... disabled`, **EXIT=1** | NEM |
| **S8** (Python) | modul-szintű `pytestmark = pytest.mark.skip(...)` | 3 finding, **EXIT=1** | NEM |
| **S8** (Python, lista) | `pytestmark = [pytest.mark.xfail(...)]` | 3 finding, **EXIT=1** | NEM |
| **S9** (guard-cél pinnelés) | **NEM mértem fa-rontással.** Csak a suite `MINOR-2 … (S9)` cellája zöld a tiszta fán, és a `4783c9f7` eszközzel nem esett el → a cella nem regresszált | — | nem mérve közvetlenül |
| **S10** | `@Skip('temporarily disabled')` az első `import` fölött, `library;` NÉLKÜL | `T-RELEASE-02 ... disabled`, **EXIT=1** | NEM |
| **S11** | 0. oszlopos `pytest.skip('flaky', allow_module_level=True)` | 3 finding, **EXIT=1**, `PYTEST_RC=5` | NEM |
| **S12** | osztály-szintű `@pytest.mark.skip` a guard SAJÁT osztályán, 2589 karakter távolságban | `T-API-02 ... disabled`, **EXIT=1** | NEM |
| **S13** | S13a / S13b / S13d hamis-pozitív vektorok | mind `OK`, **EXIT=0** | NEM |
| **MAJOR-1** | élő `branch: guards` + `branch: dependencies` kivétel a `secrets.delegate-failed` / `-unavailable` id-kre, `--secrets-cmd false` ill. `/nonexistent/binary` | `[critical] secrets: … delegate command 'false' exited 1`, **EXIT=1**; `[critical] secrets: … could not be run`, **EXIT=1** — NEM elnyomva | NEM |
| **MAJOR-1** | `branch: secrets` bejegyzés | `[critical] exceptions: … branch 'secrets' is not exceptable … (exceptions.invalid-branch)`, **EXIT=1** | NEM |
| **MAJOR-2a** | Dart guard-teszt ÁTNEVEZVE (`… prefix` → `… prefix v2`) | `… not found in …`, **EXIT=1** | NEM |
| **MAJOR-2b** | Dart guard-teszt KIKOMMENTELVE (`// test('…'`) | `… not found in …`, **EXIT=1** | NEM |
| **MAJOR-2c** | Python guard `def` átnevezve (`…_v2`) | `… not found in …`, **EXIT=1** | NEM |
| **MAJOR-2d** | Dart per-teszt `skip:` argumentum | `… disabled (skip/xfail marker)`, **EXIT=1** | NEM |
| **MAJOR-2e** | Python per-teszt `@pytest.mark.skip` dekorátor | `T-DIAG-03 … disabled`, **EXIT=1** | NEM |

**Regressziót nem mértem.**

---

## 3. Mutation-kill tábla

`git checkout <régi-sha> -- tool/release/security_scan.py` + `flutter test test/tooling/security_scan_test.dart`
(a `flutter test` és `flutter analyze` SOHA nem volt egy hívásban láncolva).

### 3a. A fix4 ÚJ cellái a fix4 ELŐTTI (`9759f5d5`) eszközzel → **`+50 -4`**

| Cella | Régi eszközzel | Tanú? |
|---|---|---|
| ÚJ-1 — `group(..., () {...}, skip: true)` (callback UTÁN) tiltja a guardot | **PIROS `[E]`** | **igen** |
| ÚJ-2 — behúzott `pytest.skip(..., allow_module_level=True)` `if` blokkban | **PIROS `[E]`** | **igen** |
| ÚJ-3 — modul-szintű `pytest.importorskip(...)` | **PIROS `[E]`** | **igen** |
| ÚJ-5 — skippelt osztály UTÁNI modul-szintű guard-`def` NEM disabled | **PIROS `[E]`** | **igen** |
| ÚJ-1 hamis-pozitív cella (testvér `skip:` a saját callbackje után) | ZÖLD | n.a. (hamis-pozitív cella) |

Azaz **a fix4 mind a négy viselkedés-változtatásának saját piros útja van.**

### 3b. Az S10/S11 HÍZLALT fixture-ök a `30651086^` (= `f252034d`, fix2) eszközzel → **`+46 -8`**

| Cella | `30651086^` eszközzel | Tanú? (ÚJ-4 mércéje) |
|---|---|---|
| **S10** — `@Skip(...)` az első `import` fölött, a 200 karakteres ablakon KÍVÜL | **PIROS `[E]`** | **igen — ÚJ-4 zárva** |
| **S11** — 0. oszlopos `pytest.skip(...)`, a 400 karakteres ablakon KÍVÜL | **PIROS `[E]`** | **igen — ÚJ-4 zárva** |
| ÚJ-2, ÚJ-3, S12, S13a, S13b, ÚJ-1-hamis-pozitív | PIROS | igen |
| S8 „library-szintű `@Skip`" (S14) | ZÖLD | **rossz eszköz** — az S8-at már a `f252034d` javította, lásd 3c |

### 3c. S14 — a hízlalt S8-cella a HELYES tanú-eszközzel (`f252034d^` = `4783c9f7`, pre-S8-fix) → **`+43 -11`**

| Cella | `4783c9f7` eszközzel | Tanú? |
|---|---|---|
| **S8/3 — Dart library-szintű `@Skip(...)` + `library;`, a 200 karakteres ablakon KÍVÜL** | **PIROS `[E]`** | **igen — S14 zárva** |
| S8/1 `pytestmark = pytest.mark.skip(...)` | PIROS `[E]` | igen |
| S8/2 `pytestmark = [pytest.mark.skip(...)]` | PIROS `[E]` | igen |
| S8/4 `group(..., skip: true)` | PIROS `[E]` | igen |
| S10, S11, ÚJ-2, ÚJ-3, S12, S13c, ÚJ-1 | PIROS `[E]` | igen |

---

## 4. Tiszta fa (hamis pozitív ellenőrzés)

```
$ git status --porcelain          # ÜRES
$ python3 tool/release/security_scan.py --only guards     → OK        EXIT=0
$ python3 tool/release/security_scan.py                   → OK        EXIT=0
$ flutter test test/tooling/security_scan_test.dart       → 00:05 +54: All tests passed!
$ cd backend && python3 -m pytest tests/test_security_release.py -q
............                                              [100%]      (12 passed)
```

A szigorítások a tiszta fán **nem hoztak be fail-closed hamis pozitívot**.

---

## 5. Új leletek

### FP-A — MINOR: `pytest.importorskip(...)` egy TESZT-TÖRZSÖN belül az egész modult „disabled"-nek jelöli

**Minősítés: követő kör javasolt (nem regresszió, nem merge-blokkoló).** Fail-closed irány (a release-t
blokkolja, nem enged át), és a fix4 docstringje tudatos kompromisszumként ki is mondja
(„its presence anywhere in the module is treated as a module-wide silencer"). Mégis jelentem, mert ez a
`pytest.importorskip` **dokumentált, függvény-szintű** használata, és a fix4 tesztfájl hamis-pozitív cellája
csak a `pytest.skip`-változatra létezik (`ÚJ-2B`), az `importorskip`-re nem.

Reprodukció (valós fa, `backend/tests/test_diagnostics.py`, egy teszt törzsében):

```python
def test_optional_dep_thing():
    yaml = pytest.importorskip('yaml')
    assert yaml is not None
```

```
$ python3 tool/release/security_scan.py --only guards
security_scan: 3 finding(s).   # T-DIAG-01/02/03 mind "is present but disabled"
GUARDS_EXIT=1
$ cd backend && python3 -m pytest tests/test_diagnostics.py -q
..............     [100%]      # a 3 guard MIND FUT és ÁTMEGY
```

**Javítási irány:** az `importorskip` csak akkor számítson modul-szintűnek, ha nincs `def`/`class`
0. oszlopos blokkon belül (pl. a hívás sorát megelőző legközelebbi 0. oszlopos `def`/`class` és a hívás
között nincs behúzás-visszatérés), + hamis-pozitív cella a függvény-törzsbeli alakra.

### FP-B — MINOR (ELŐZŐLEG IS MEGLÉVŐ, nem fix4-regresszió): a `def`-lokális 400 karakteres ablak átlóg a szomszéd tesztre

**Minősítés: követő kör javasolt (nem regresszió, nem merge-blokkoló).** Fail-closed.

Egy legális, futásidejű `pytest.skip('…')` egy MÁSIK teszt törzsében, ha a guard `def`-je 400 karakteren
belül követi, elbuktatja a guardot:

```python
def test_plain_conditional_skip():
    if False:
        pytest.skip('not applicable here')
    assert True


def test_diagnostics_rejects_bad_token(...):   # a guard
```

```
$ python3 tool/release/security_scan.py --only guards
- [critical] guards: T-DIAG-03 ... is present but disabled (skip/xfail marker) ...
GUARDS_EXIT=1
$ cd backend && python3 -m pytest tests/test_diagnostics.py -q
..............     [100%]      # a guard FUT és ÁTMEGY
```

Ez a `_PY_SKIP_MARKERS`-ben lévő `"pytest.skip("` + a `_python_guard_status` 400 karakteres előtag-ablak
együtthatása; a kód a fix4 diffben **változatlan** (`git diff 9759f5d5..cc2a7699` nem érinti), tehát
**nem a fix4 hozta be**. A fix4 saját `ÚJ-2B` cellája éppen ezt kerüli ki 30 fillerrel — vagyis a hiba
ismert, csak nincs róla cella.

**Mindkét új lelet ugyanannak a „végtelen finomítási osztálynak" (statikus skip-heurisztika
hamis-pozitív oldala) a következő rétege, és MINDKETTŐ fail-closed. Egyik sem merge-blokkoló.**

---

## 6. Amit NEM mértem

- **Teljes `flutter test` suite / `tools/round-gate.sh` / `flutter analyze`** — nem futtattam. Csak
  `test/tooling/security_scan_test.dart` (54/54 zöld) és `backend/tests/test_security_release.py`
  (12 passed) futott, plusz a szándékosan rontott fán a `backend/tests/*` célfájlok `pytest -q`-val.
- **`test/privacy/consent_enforcement_test.dart` tényleges `Skip:` kimenete a fix4 fán** — az ÚJ-1
  rontásnál a `security_scan` EXIT-kódját mértem, de a `flutter test`-tel nem futtattam újra a
  consent-fájlt (a fix3 review már bizonyította, hogy ez az alak valóban némít).
- **S9 (guard-cél pinnelés) fa-rontásos regressziós probe** — csak a suite `MINOR-2 … (S9)` cellájának
  zöldjére támaszkodom.
- **`tools/scope-audit.py` / diff-scope** — a fix4 diff csak `tool/release/security_scan.py`,
  `test/tooling/security_scan_test.dart` és `docs/rounds/e12-r18-*.md` (`git diff --stat 9759f5d5..cc2a7699`);
  nulla `lib/**`, nulla `backend/app/**` — de teljes scope-auditot nem futtattam.
- **Dart-oldali további némító vektorok:** `@TestOn(...)`, `@Tags([...])` + `dart_test.yaml` `exclude_tags`,
  `dart_test.yaml` `paths`/`skip`, korai `return;` a `main()` elején — NEM próbáltam.
- **Python-oldali további vektorok:** `conftest.py` `collect_ignore`, `pytest.ini` `addopts=--ignore=`,
  `testpaths` szűkítés — NEM próbáltam.
- **Unicode/whitespace trükkök a regexekben** (`pytest .skip(`, `pytest .skip(` stb.) — NEM próbáltam.
- **A threat-model tartalmi teljessége** (van-e le nem kötött, mért védelem) — korábbi körök tárgya,
  itt nem ismételtem.
- **`tool/ci/check_secrets.dart` mintakészlete** — a kör nem érinti.

---

## 7. Verdikt

**APPROVED**

- Nyitott **BLOCKER: 0**
- Nyitott **MAJOR: 0** — az ÚJ-1 (mindkét `skip:`-alak), ÚJ-2, ÚJ-3, ÚJ-4 mind ZÁRVA, saját mért piros
  úttal; a MINOR ÚJ-5, S14 és a NOTE ÚJ-6 is ZÁRVA.
- Nyitott **MINOR: 2** — FP-A (`importorskip` teszt-törzsben) és FP-B (400 karakteres `def`-előtag-ablak
  átlógása); mindkettő **fail-closed** és **követő kör javasolt (nem regresszió, nem merge-blokkoló)`**.
  FP-B a fix4 előtt is jelen volt.

**Indoklás:** a fix4 először zárja le a `skip`-elnémítás mindkét irányát egyszerre — a kanonikus, callback
utáni Dart `group(..., skip:)` alakot ÉS az S13 hamis pozitívjait, valamint a Python modul-szintű
`pytest.skip`/`importorskip` idiómákat indentációtól függetlenül —, és **ez az első fix-kör, amelyben minden
új viselkedés-változtatásnak van saját, általam újramért mutation-kill tanúja** (`9759f5d5` ellen 4 piros),
sőt a korábbi körök két nem-tanú cellája (S10/S11) és az S14 cella is valódi tanúvá hízott (`30651086^`
ellen 2 piros, `4783c9f7` ellen az S8-library cella piros). A kivétel-szemantika (`secrets` ág
elnyelhetetlensége, `branch: secrets` mint kritikus lelet) és a `not found` ág (átnevezés/kikommentelés)
sértetlen. A tiszta fán a kapu EXIT=0 és a suite 54/54 zöld — a szigorítások nem hoztak be
release-blokkoló hamis pozitívot a repó valós fájljaira.

**Nem tárgyalható termékhatár sérülése (AGENTS.md §5) nincs:** a fix4 diff nulla `lib/**` és
`backend/app/**` fájlt érint, nem visz be hálózati hívást, engedélyt, promptot, titkot vagy naplózást.
A `T-EGRESS-01`/`T-EGRESS-02` (§5.1/§5.2) guardok elnémítása mostantól mindkét Dart `skip:`-alakban
release-blokkoló kritikus lelet — a határt MÉRŐ bizonyíték csendes elvesztése lezárult.
