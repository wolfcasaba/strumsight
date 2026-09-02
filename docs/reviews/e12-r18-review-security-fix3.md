# E12-R18 — független biztonsági review (fix3), READ-ONLY

- **Ág / HEAD:** `sonnet-impl/e12-r18-threat-model-and-release-security-scan` @ `d12180a6`
- **Vizsgált javító kör:** `30651086` („harmadik javító kör: S10/S11 + S12/S13")
- **Izolált klón:** `/tmp/e12r18-rev1` (a `d12180a6` detached HEAD-en); a kör-munkapéldány
  `/home/ubuntu/ss-sonnet-impl-e12-r18` és a `main` repó NEM módosult (mérve: `git status --porcelain` üres,
  `git rev-parse HEAD` = `d12180a6`).
- **Kiindulási mérce:** `python3 tool/release/security_scan.py --only guards` → `OK — no critical or fatal finding.` **EXIT=0**

---

## 1. Leletenkénti zárás-ellenőrzés

| Lelet | Státusz | Bizonyíték |
|---|---|---|
| **S10** — Dart `@Skip(...)` az első direktíva fölött `library;` NÉLKÜL | **ZÁRVA** (funkcionálisan) | lásd 1.1 |
| **S11** — modul-szintű `pytest.skip(..., allow_module_level=True)` | **RÉSZBEN ZÁRVA** — csak a 0. oszlopos alak; lásd ÚJ-2/ÚJ-3 | lásd 1.2 |
| **S12** — osztály-szintű `@pytest.mark.skip` a 400 bájtos ablakon kívül | **ZÁRVA** (új hamis pozitívval: ÚJ-4) | lásd 1.3 |
| **S13** — hamis pozitív: testvér-teszt `skip:`-je a group törzsében | **ZÁRVA — de REGRESSZIÓT hozott (ÚJ-1)** | lásd 1.4 |
| **S14** — degenerált fixture (nem mutation-kill tanú) | **NYITOTT, sőt kiterjedt** (S10/S11 celláira is) | lásd 1.5 + §2 |

### 1.1 S10 — ZÁRVA

Rontás a VALÓS fán (`@Skip(...)` beszúrva az első `import` fölé, `library;` nélkül):

```
$ head -6 test/tooling/check_secrets_test.dart
// strumsight:allow-secret-file — ...
@Skip('temporarily disabled')
import 'dart:io';

$ python3 tool/release/security_scan.py --only guards
security_scan: 1 finding(s).
- [critical] guards: T-RELEASE-02 (release-chain): guard.test 'flags provider token literals by their own
  prefix' is present but disabled (skip/xfail marker) in test/tooling/check_secrets_test.dart — ...
EXIT=1
$ python3 tool/release/security_scan.py   # teljes futás
FULL EXIT=1
```

Az előző review-ban ez a vektor EXIT 0 volt. **Zárva.**

### 1.2 S11 — a NEVEZETT alak zárva, az idióma NEM

Rontás (`backend/tests/test_diagnostics.py` elejére, 0. oszlopban):

```
$ sed -n '1,8p' backend/tests/test_diagnostics.py
"""Lab-mode diagnostics collector: ..."""

import pytest
pytest.skip('flaky', allow_module_level=True)

import asyncio
...
$ python3 tool/release/security_scan.py --only guards
security_scan: 3 finding(s).
- [critical] guards: T-DIAG-01 ... is present but disabled (skip/xfail marker) ...
- [critical] guards: T-DIAG-02 ...
- [critical] guards: T-DIAG-03 ...
EXIT=1
```

A pontos, dokumentált alak tehát zárva. A regex viszont `(?m)^pytest\.skip\(` — **kizárólag 0. oszlop**;
minden behúzott, de továbbra is modul-szintű változat átmegy (ÚJ-2), és az `importorskip` idióma sem
szerepel a jelzők között (ÚJ-3). A kód doc-commentje explicit érvel a 0. oszlopos szűkítés mellett
(„a `pytest.skip(...)` egy függvénytörzsben MINDIG behúzott") — az állítás igaz, de a MEGFORDÍTÁSA
(„behúzott ⇒ nem modul-szintű") hamis, és éppen ez a rés.

### 1.3 S12 — ZÁRVA (mutation-kill bizonyítékkal)

Rontás a valós fán: `@pytest.mark.skip(...)` a `class TestAuthThrottle:` fölé, + 6 string-mentes filler
metódus, hogy a guard-`def` a 400 bájtos előtag-ablakon KÍVÜL kerüljön (a `_strip_python_trivia` a
docstringeket kivágja, ezért a padding nem lehet docstring — az első próbám ezen csúszott meg):

```
STRIPPED class->def distance: 1090
$ python3 tool/release/security_scan.py --only guards        # ÚJ eszköz
- [critical] guards: T-API-02 (backend-api): guard.test 'test_login_brute_force_gets_429_with_retry_after'
  is present but disabled (skip/xfail marker) in backend/tests/test_hardening.py — ...
EXIT=1
$ git checkout 30651086^ -- tool/release/security_scan.py
$ python3 tool/release/security_scan.py --only guards        # RÉGI eszköz
security_scan: OK — no critical or fatal finding.
EXIT=0
```

**Zárva, valódi piros úttal.**

### 1.4 S13 — a hamis pozitív zárva

Rontás: a `test/privacy/consent_enforcement_test.dart` `A4` groupjába egy TESTVÉR teszt saját
`skip: 'flaky on CI'` argumentummal, a guard-teszt mellé:

```
$ python3 tool/release/security_scan.py --only guards        # ÚJ eszköz
security_scan: OK — no critical or fatal finding.
EXIT=0
$ git checkout 30651086^ -- tool/release/security_scan.py
$ python3 tool/release/security_scan.py --only guards        # RÉGI eszköz
- [critical] guards: T-EGRESS-01 (client-egress): guard.test 'upload() with consent false never touches
  the wire adapter' is present but disabled (skip/xfail marker) — ...
EXIT=1
```

A hamis pozitív zárva. **DE a szűkítés árat kért: lásd ÚJ-1 (MAJOR regresszió).**

### 1.5 S14 — NYITOTT

A fix3 a teszt-fájlt CSAK bővítette (`git show --numstat 30651086` → `test/tooling/security_scan_test.dart
221 0`, nulla törlés), az S8 „library-szintű `@Skip`" cellájának degenerált fixture-je (a
`security_scan_test.dart` 856–866. sora) változatlan: az `@Skip('whole file disabled')` ~40 karakterre van
a `test(` hívástól, tehát benne van a RÉGI, hívás-lokális 200 karakteres előtag-ablakban. A cella így a
régi eszközzel is zöld ⇒ nem tanú. **S14 nem lett kezelve** — sőt a hibaosztály MEGISMÉTLŐDÖTT az S10 és
S11 új celláira is (§2).

---

## 2. Mutation-kill: a fix3 ÚJ cellái a RÉGI (`30651086^`) eszközzel

```
$ bash /tmp/e12r18-rev1/tools/prepare-flutter-generated.sh
$ git checkout 30651086^ -- tool/release/security_scan.py
$ flutter test test/tooling/security_scan_test.dart
...
00:04 +42 -3: Some tests failed.
```

| Új cella | Régi eszközzel | Tanú? |
|---|---|---|
| S10 — `@Skip(...)` az első `import` fölött, `library;` nélkül | **+29 → ZÖLD (PASS)** | **NEM** |
| S11 — csupasz, behúzatlan `pytest.skip(...)` modul-szinten | **+30 → ZÖLD (PASS)** | **NEM** |
| S12 — `@pytest.mark.skip` az osztályon, 30 filler metódussal | **PIROS `[E] Expected: <1> Actual: <0>`** | igen |
| S13a — testvér `skip: true` a közös groupban | **PIROS `[E] Expected: <0> Actual: <1>`** | igen |
| S13b — `skip:`-alakú részlet a group SAJÁT leírásában | **PIROS `[E] Expected: <0> Actual: <1>`** | igen |
| S13c — „a group-szintű skip TOVÁBBRA IS tilt" regressziós cella | ZÖLD (regressziós cella, elvárt) | n.a. |

**Ok (mért):** mindkét nem-tanú cella fixture-je degenerált.
- S10 fixture: `@Skip('...')\nimport 'dart:convert';\n\nvoid main() {\n  test(` — az `@Skip(` ~70 karakterre
  van a `test(` hívástól, tehát a RÉGI `_dart_guard_status` 200 karakteres `prelude` ablakában van
  (`_DART_SKIP_MARKERS = ("skip:", "@Skip(")`).
- S11 fixture: `import pytest\npytest.skip(...)\n\n\ndef test_the_real_thing():` — a `pytest.skip(` benne van
  a `_PY_SKIP_MARKERS`-ben ÉS a RÉGI 400 karakteres `def`-előtag-ablakban.

Vagyis a két MAJOR javítás (`_dart_file_skipped` átírása és a `_PY_MODULE_LEVEL_SKIP_CALL`) **egyáltalán
nincs teszttel lefedve**: ha valaki visszaállítja őket, a suite zöld marad. Ez az S14 hibaosztálya,
ezúttal a kör két legfontosabb javításán.

---

## 3. Új leletek

### ÚJ-1 — MAJOR (REGRESSZIÓ): az S13-szűkítés újranyitja a group-szintű elnémítást a kanonikus `skip:`-alakra

`_dart_call_head` a group argumentum-fejét a **callback `()` -jánál levágja**, ezért a
`group('...', () { ... }, skip: 'reason')` alak — a `package:test` dokumentált, tipikus írásmódja, ahol a
named argument a pozicionális callback UTÁN áll — láthatatlan. A fix2 eszköz még elkapta.

Reprodukció a VALÓS fán:

```bash
cd /tmp/e12r18-rev1
# az A4 group záró "  });" -jét cseréld erre:   }, skip: 'temporarily disabled');
python3 tool/release/security_scan.py --only guards
```

Mért kimenet:

```
=== ÚJ (fix3) eszköz ===
security_scan: OK — no critical or fatal finding.
EXIT=0
=== RÉGI (fix2) eszköz ===
- [critical] guards: T-EGRESS-01 (client-egress): guard.test 'upload() with consent false never touches
  the wire adapter' is present but disabled (skip/xfail marker) ...
EXIT=1
```

A tényleges elnémulás bizonyítva (nem statikus feltételezés):

```
$ flutter test test/privacy/consent_enforcement_test.dart
00:00 +2: A4 — ... upload() with consent false never touches the wire adapter
  Skip: temporarily disabled
...
00:01 +9 ~1: All tests passed!
```

Tehát a `T-EGRESS-01` guard (§5.2 „nincs egress consent nélkül" mérése) NEM fut, a release-kapu mégis
EXIT 0. Ez pontosan az S8 által zárt hibaosztály visszanyitása.

**Miért csúszott át:** az S13c regressziós cella (`group('disabled', skip: true, () {`) csak az
argumentum-fej alakot fedi; a callback UTÁNI named-argument alakra nincs cella.

**Javítási irány:** a group `skip:` keresése ne az argumentum-FEJRE korlátozódjon, hanem a group hívás
teljes argumentum-listájára a BESZÁRT `test(`/`group(` hívások argumentumainak kivonásával (pl. a
beágyazott `test(`/`group(` span-ek kimaszkolása után `skip:` keresés), + cella mindkét alakra.

### ÚJ-2 — MAJOR: az S11-javítás megkerülhető BÁRMILYEN behúzással (`if ...:` blokk)

`_PY_MODULE_LEVEL_SKIP_CALL = re.compile(r"(?m)^pytest\.skip\(")` csak a 0. oszlopot fogja. Egy
modul-szintű `if` alá tett hívás ugyanúgy az egész modult átugorja.

Reprodukció (valós fa, `backend/tests/test_diagnostics.py` — 3 guard hordozója):

```python
import os
import pytest

if os.environ.get('STRUMSIGHT_FAST_CI') != '0':
    pytest.skip('slow suite', allow_module_level=True)
```

```
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
EXIT=0
$ cd backend && python3 -m pytest tests/test_diagnostics.py -q ; echo $?
5            # = no tests collected — T-DIAG-01/02/03 mind néma
```

Ugyanez `if True:` alakkal is reprodukálva (EXIT 0 / pytest rc 5).

**Javítási irány:** a jelző ne oszlop-kötött legyen; egy `pytest.skip(`+`allow_module_level` páros
BÁRHOL a fájlban (a trivia-stripelt szövegben) modul-szintű elnémítás — a `allow_module_level` kulcsszó
maga a megkülönböztető jegy egy test-törzsbeli `pytest.skip()`-hez képest.

### ÚJ-3 — MAJOR: `pytest.importorskip(...)` modul-szinten nincs a jelzők között

```
# backend/tests/test_diagnostics.py elejére:
import pytest
pytest.importorskip('some_optional_dep')
```

```
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
EXIT=0
$ cd backend && python3 -m pytest tests/test_diagnostics.py -q ; echo $?
5            # no tests collected
```

Egyetlen sor, teljesen hétköznapi kinézetű, és három release-kapuhoz kötött guardot némít el csendben.

**Javítási irány:** `pytest.importorskip(` felvétele a modul-szintű elnémítás-jelzők közé (ugyanabba a
listába, ahol a `pytest.skip(`+`allow_module_level` lesz).

### ÚJ-4 — MAJOR: az S10 és S11 cellák nem mutation-kill tanúk (az S14 hibaosztály megismétlődése)

Lásd §2. Mérve: a régi eszközzel mindkét cella ZÖLD. A két javítás regresszió-védelme működésképtelen.

**Javítási irány:** a fixture-öket akkorára kell hízlalni, hogy az elnémító a régi hívás-lokális
ablakokon (Dart 200 / Python 400 karakter, a trivia-stripelt szövegben mérve) KÍVÜL essen — az S12 cella
(30 filler metódus) mutatja a helyes mintát. Emellett érdemes normává tenni: minden új `check` cellájának
saját, dokumentált mutation-kill tanúsága van.

### ÚJ-5 — MINOR: az S12-javítás hamis pozitívot hoz a modul-szintű guard-függvényekre

`_python_class_skip_disabled` a `def <guard>(` ELŐTTI UTOLSÓ 0. oszlopos `class`-t veszi, függetlenül
attól, hogy a guard függvény egyáltalán abban az osztályban van-e. Egy modul-szintű guard-függvény, amely
egy (bármilyen, akár teljesen független) skippelt osztály UTÁN áll, tévesen „disabled".

Reprodukció (valós fa, `backend/tests/community/test_access_policy.py`): egy független
`@pytest.mark.skip`-elt `class TestLegacyUnrelated:` beszúrása a modul-szintű
`def test_a2_blocked_public_profile_returns_summary():` FÖLÉ:

```
$ python3 tool/release/security_scan.py --only guards
- [critical] guards: T-COMM-02 (community): guard.test 'test_a2_blocked_public_profile_returns_summary'
  is present but disabled (skip/xfail marker) ...
EXIT=1
$ cd backend && python3 -m pytest tests/community/test_access_policy.py -q \
      -k test_a2_blocked_public_profile_returns_summary
.                                                       [100%]
PYTEST_RC=0        # a guard-teszt FUT és ÁTMEGY
```

Fail-closed (release-t blokkol, nem enged át) ⇒ MINOR, ugyanaz az osztály, mint az S13 volt.
**Javítási irány:** a `class` csak akkor számítson, ha a `def` valóban BEHÚZVA, az osztály törzsében van
(pl. a `class` és a `def` közti szövegben nincs 0. oszlopos `def`/`class`, és a `def` sora behúzott).

### ÚJ-6 — NOTE: `--only guards` nem tölti be a kivétel-nyilvántartást

`exceptions_available = only in (None, "exceptions", "dependencies")` — `--only guards` mellett egy ÉLŐ,
`branch: guards` kivétel sem nyom el semmit. Ez szigorúbb (fail-closed), tehát nem lelet; csak jegyezzük,
mert a mérés első körben emiatt tűnt „nem működő elnyomásnak", és a docstring nem mondja ki.

---

## 4. Fail-closed és kivétel-szemantika (mind MÉRVE, mind ZÖLD)

Szondafa: `/tmp/e12r18-probe` (egy hiányzó `guard.path`-ú `T-PROBE-01` blokk → stabil kritikus lelet),
teljes futás `--secrets-cmd true` mellett, `--today 2026-09-01`.

| Kérdés | Mért kimenet | EXIT |
|---|---|---|
| lejárt kivétel (`expires: 2026-08-31`) | `[critical] exceptions: exceptions[0] ... expired 2026-08-31 — today is 2026-09-01 (exceptions.expired)` + a lelet NEM elnyomva | **1** |
| MA lejáró (`expires: 2026-09-01`) | `OK — no critical or fatal finding.` (INKLUZÍV küszöb) | **0** |
| holnap lejáró (`expires: 2026-09-02`) | `OK — no critical or fatal finding.` | **0** |
| `branch: secrets` | `[critical] ... branch 'secrets' is not exceptable — only ['dependencies','guards'] ... (exceptions.invalid-branch)` | **1** |
| `branch: nonsense` | ugyanaz az `exceptions.invalid-branch` kritikus lelet | **1** |
| élő `guards`/`dependencies` kivétel a `secrets.delegate-failed` id-re, `--secrets-cmd false` | `[critical] secrets: secrets delegate command 'false' exited 1 (secrets.delegate-failed)` — NEM elnyomva | **1** |
| ugyanez `secrets.delegate-unavailable`-re, `--secrets-cmd /nonexistent/binary` | `[critical] secrets: ... could not be run ... (secrets.delegate-unavailable)` — NEM elnyomva | **1** |

**A `secrets` ág elnyelhetetlensége, a lejárat nem-nulla kilépése és az INKLUZÍV küszöb mind tartja
magát. Regressziót itt nem mértem.**

---

## 5. Scope-audit

`tools/scope-audit.py` nem futott (a klónban a brief §4 lista kézzel ellenőrizhető); kézi mérés a
beolvasztott main-csúcshoz (`91ba4a4c`) képest:

```
$ git diff --stat 91ba4a4c...HEAD
 backend/tests/test_security_release.py                                 |  141 ++
 docs/adr/0481-program-threat-model-and-release-security-scan.md        |  139 ++
 docs/reviews/e12-r18-review-security-fix2.md                           |  546 +++
 docs/reviews/e12-r18-review-security-followup.md                       |  350 +++
 docs/reviews/e12-r18-review-security.md                                |  491 +++
 docs/rounds/e12-r18-threat-model-and-release-security-scan.md          | 1130 ++-
 docs/security/exceptions.yaml                                          |   31 +
 docs/security/threat-model.md                                          |  402 +++
 test/tooling/security_scan_test.dart                                   | 1603 ++++
 tool/release/security_scan.py                                          | 1203 ++++
 10 files changed, 5977 insertions(+), 59 deletions(-)
```

A brief §4 `allowed_paths` hat eleme + `docs/adr/0481-*` + `docs/reviews/e12-r18-*`. **Scope-sértés
nincs**; `lib/**` és `backend/app/**` érintetlen (nulla termékkód-fájl a diffben).

---

## 6. Amit NEM mértem

- **A teljes `flutter test` suite / `tools/round-gate.sh`** — nem futtattam; csak a
  `test/tooling/security_scan_test.dart` és a `test/privacy/consent_enforcement_test.dart` futott,
  utóbbi a szándékosan rontott fán.
- **`backend/tests/test_security_release.py`** — nem futtattam.
- **`flutter analyze`** — nem futtattam (a láncolás tilalma miatt külön hívás kellett volna; a kör
  nem Dart-produkciókódot változtat).
- **Az ÚJ-1/ÚJ-2/ÚJ-3/ÚJ-5 hatása az ÚJ tesztfájl celláira** — nem néztem meg, hogy egy javítás mely
  meglévő cellát törné el.
- **Dart-oldali további vektorok:** `@TestOn('browser')`, `@Tags([...])` + `dart_test.yaml`
  `exclude_tags`, `dart_test.yaml` `paths`/`skip`, a `main()` elejére tett korai `return;` — ezeket
  NEM próbáltam ki, ezért nem is jelentem őket leletként (elméleti).
- **Python-oldali további vektorok:** `conftest.py` `collect_ignore`, `pytest.ini` `addopts=--ignore=...`,
  `testpaths` szűkítés — a konfigurációt elolvastam (`backend/pytest.ini`: `pythonpath=.`,
  `testpaths=tests`, `addopts=-q`), de a vektorokat NEM futtattam le, így nem jelentem őket.
- **Unicode/whitespace trükkök a regexekben** — nem próbáltam.
- **A threat-model tartalmi teljessége** (van-e le nem kötött, mért védelem) — ezt a korábbi körök
  fedték, itt nem ismételtem meg.
- **A titok-scan tényleges mintakészlete** (`tool/ci/check_secrets.dart`) — a kör nem érinti.

---

## 7. Verdikt

**CHANGES REQUESTED**

- Nyitott **BLOCKER: 0**
- Nyitott **MAJOR: 4** — ÚJ-1 (S8/group-skip regresszió a kanonikus alakra), ÚJ-2 (behúzott
  `pytest.skip(..., allow_module_level=True)`), ÚJ-3 (`pytest.importorskip`), ÚJ-4 (S10/S11 cellák nem
  mutation-kill tanúk; az S14 hibaosztály nyitva)
- Nyitott **MINOR: 2** — ÚJ-5 (osztály-skip hamis pozitív modul-szintű guard-függvényre), S14 eredeti
  cellája (degenerált S8 „library-szintű `@Skip`" fixture)
- **NOTE: 1** — ÚJ-6

**Indoklás:** a fix3 három leletet valóban lezárt (S10 a nevezett alakra, S12 valódi piros úttal, S13 a
hamis pozitívra), de (a) egy korábban MŰKÖDŐ ellenőrzést mérhetően visszanyitott (ÚJ-1: a
`T-EGRESS-01` consent-guard elnémítható, a kapu EXIT 0 — ez a §5.2 határ mérésének csendes elvesztése),
(b) az S11-javítás alakspecifikus, két egysoros, hétköznapi idióma megkerüli, és (c) a kör két
legfontosabb javításának nincs piros útja. A kivétel-szemantika és a fail-closed viselkedés viszont
sértetlen — ott regressziót nem mértem.

**Nem-tárgyalható termékhatár sérülés (AGENTS.md §5) nincs**: a kör nem érint termékkódot, nem visz be
hálózati hívást, engedélyt, promptot vagy titkot; a diffben nulla `lib/**` és `backend/app/**` fájl van.
Az ÚJ-1 közvetett §5-kockázat (a határt MÉRŐ guard némítható el észrevétlenül), de maga a határ nem sérül.
