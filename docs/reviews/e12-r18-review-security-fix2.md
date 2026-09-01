<!-- strumsight:allow-secret-file -->
# E12-R18 — biztonsági review, MÁSODIK javító kör (S8 + S9 zárása)

| | |
|---|---|
| **Reviewer** | Claude (független biztonsági reviewer, ADR 0055 §15.1 — READ-ONLY) |
| **Dátum** | 2026-09-01 |
| **Review-klón** | `/tmp/review3-e12-r18` (izolált; `ss-sonnet-impl-e12-r18` és `music-theory` érintetlen) |
| **Mért HEAD** | `20fdd4a4` (`Merge origin/main into E12-R18 (upstream sync #2)`) |
| **Felülvizsgált commit** | `f252034d` — „[E12-R18] második javító kör: S8 fájl/group-szintű elnémítás + S9 guard-cél pinnelés" |
| **Előzmények** | `docs/reviews/e12-r18-review-security.md` (4 MAJOR + 3 MINOR), `docs/reviews/e12-r18-review-security-followup.md` (7/7 ZÁRVA, ÚJ: S8 MAJOR-latens, S9 MINOR) |

Minden alábbi kimenet a fenti klónban, saját futásból származik. Minden rontás
után `git checkout -- <fájl>`; a fa a review végén tiszta (`git status --short`
üres). A jelentés SZINTETIKUS fixture-öket idéz; valódi titok nincs benne.

---

## Verdikt: **CHANGES REQUESTED**

**Amit a commit tényleg megcsinál:** az S9 ZÁRVA (piros út mérve), és az S8
mind a NÉGY *nevesített* forgatókönyve ZÁRVA (plusz két, korábban nem mért
python-variáns is). A javítás iránya helyes, a Dart-oldali „import-határos"
szűkítés a valós fán NEM ad hamis pozitívat.

**Amiért mégis CHANGES REQUESTED:** az S8 *hibaosztálya* — „fájl-szintű
elnémítás mellett a kapu EXIT 0-t ad" — **nem zárult**. Két, a VALÓS fán
reprodukált, egysoros megkerülés maradt, mindkettő ugyanazokat a guardokat
némítja el, amiket az S8 kifogásolt:

* **S10 (MAJOR-latens):** Dart `@Skip('…')` a `library;` direktíva NÉLKÜL, az
  első `import` fölött → `flutter test` „All tests skipped", a scan **EXIT 0**.
  Ez a javítás saját 2. forgatókönyvét egyetlen token (`library;`) törlésével
  kerüli meg.
* **S11 (MAJOR-latens):** python `pytest.skip('…', allow_module_level=True)` a
  modul tetején → a modul teljesen kihagyva, a scan **EXIT 0**, T-DIAG-01/-02/-03
  egyszerre néma.

Mindkettő olcsón zárható (lásd a javasolt irányokat). Amíg nyitva vannak, az a
kötés, amivel a followup APPROVED-ot adott („az S8 a CI-bekötés előtt
záruljon"), nem teljesült.

Ezt erősíti a mutation-kill: a négy új S8-cellából **három** valódi tanú, a
Dart library-`@Skip` cella viszont a JAVÍTÁS ELŐTTI eszközzel is zöld
(**S14**) — vagyis épp az a kód, amit az S10 megkerül, a suite szempontjából
lefedetlen.

---

## 1. Termékhatár — RENDBEN

```
$ git show --stat f252034d
 ...2-r18-threat-model-and-release-security-scan.md | 156 +++++++++++++
 test/tooling/security_scan_test.dart               | 251 +++++++++++++++++++++
 tool/release/security_scan.py                      |  95 +++++++-
 3 files changed, 496 insertions(+), 6 deletions(-)
```

`lib/**`, `backend/app/**`, `backend/tests/**`, `.github/**`, `tools/**`,
`docs/adr/**`, `docs/security/**` — egyik sincs érintve. A commit három fájlja:
kör-dokumentum, gate-teszt, gate-eszköz. Új fixture-ök mind szintetikusak
(`pytestmark = pytest.mark.skip(reason='whole file disabled')`,
`@Skip('whole file disabled')`, `test('the real thing', …)`); valódi kulcs,
token vagy PoC nincs a diffben.

## 2. Alapállapot a javított fán — nincs hamis piros

```
$ python3 tool/release/security_scan.py
security_scan: OK — no critical or fatal finding.
FULL_EXIT=0
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
GUARDS_EXIT=0
```

Ez egyben az implementer által dokumentált csapda cáfolata is: a
`security_scan_test.dart` string-literálba ágyazott fixture-jei tartalmaznak
`@Skip('whole file disabled')\nlibrary;` (`:869-870` a diff szerint) és
`group('disabled', skip: true, …)` (`:895`) alakot, és a fájl MAGA guard-cél
(`T-RELEASE-03`) — mégsem lesz belőle „present but disabled". Két független ok
mérve:

* `_dart_file_skipped` (`tool/release/security_scan.py:582-596`) a fájl első
  `import`/`part`/`export` direktívája ELŐTTI fejlécre szűkít, a fixture pedig
  a `main()`-en belüli string;
* a `T-RELEASE-03` guard-teszt (`a dependency line without an upper bound is a
  critical finding`, `security_scan_test.dart:346`) az `A6` group-ban van
  (`:345`), az összes `skip:` előfordulás pedig más groupokban (`:671-677`,
  `:891-895`).

Ez utóbbi **véletlen elrendezés, nem invariáns** — lásd S13.

---

## S8 — fájl- és group-szintű elnémítás → a NEVESÍTETT forgatókönyvek ZÁRVA

Mind a négy támadás a followup SAJÁT, akkor ZÖLD próbája, most újrafuttatva.

### S8/1 — python modul-szintű `pytestmark = pytest.mark.skip(...)` → **PIROS**

```
$ (backend/tests/test_diagnostics.py tetejére:
   pytestmark = pytest.mark.skip(reason='whole file disabled'))
$ python3 tool/release/security_scan.py --only guards
security_scan: 3 finding(s).
- [critical] guards: T-DIAG-01 (diagnostics-upload): guard.test 'test_diagnostics_session_id_cannot_escape_data_dir' is present but disabled (skip/xfail marker) in backend/tests/test_diagnostics.py — a silenced protection is release-blocking, not a silent regression (ADR 0481 D2) (T-DIAG-01)
- [critical] guards: T-DIAG-02 (diagnostics-upload): guard.test 'test_diagnostics_oversize_endpoint_returns_413' is present but disabled (skip/xfail marker) in backend/tests/test_diagnostics.py — … (T-DIAG-02)
- [critical] guards: T-DIAG-03 (diagnostics-upload): guard.test 'test_diagnostics_rejects_bad_token' is present but disabled (skip/xfail marker) in backend/tests/test_diagnostics.py — … (T-DIAG-03)
EXIT=1
```

Mind a három elnémított guard nevesítve. ✅

### S8/1b — `pytestmark = [ … ]` LISTA-alak (a followup NEM mérte) → **PIROS**

Három variáns, mind ugyanarra a fájlra, mind **EXIT=1**, mind 3 leletet ad:

```
=== VARIANT: pytestmark = [\n    pytest.mark.skip(reason='off'),\n]
security_scan: 3 finding(s).                      REAL_EXIT=1
=== VARIANT: pytestmark = [pytest.mark.usefixtures('x'), pytest.mark.xfail(reason='off')]
security_scan: 3 finding(s).                      REAL_EXIT=1
=== VARIANT: pytestmark = pytest.mark.skipif(True, reason='off')
security_scan: 3 finding(s).                      REAL_EXIT=1
```

A lista-alak (beleértve a nem-skip markerrel *kevert* listát), az `xfail` és a
`skipif` is fogva van (`skipif` a `pytest.mark.skip` részstringje). ✅

### S8/2 — Dart library-szintű `@Skip(...)` + `library;` → **PIROS**

```
$ (test/tooling/vision_model_integrity_test.dart tetejére:
   @Skip('whole file disabled')
   library;)
$ python3 tool/release/security_scan.py --only guards
security_scan: 1 finding(s).
- [critical] guards: T-MODEL-01 (model-package): guard.test 'bad checksum fails the integrity gate' is present but disabled (skip/xfail marker) in test/tooling/vision_model_integrity_test.dart — a silenced protection is release-blocking, not a silent regression (ADR 0481 D2) (T-MODEL-01)
EXIT=1
```
✅ (De lásd **S10**: a `library;` sor törlésével ugyanez a némítás visszanyílik.)

### S8/3 — Dart `group(..., skip: true)` a guard-teszt körül → **PIROS**

`test/tooling/check_secrets_test.dart:33-45` becsomagolva:

```
  group('disabled', skip: true, () {
  test('flags provider token literals by their own prefix', () {
    …
  });
  });

$ python3 tool/release/security_scan.py --only guards
security_scan: 1 finding(s).
- [critical] guards: T-RELEASE-02 (release-chain): guard.test 'flags provider token literals by their own prefix' is present but disabled (skip/xfail marker) in test/tooling/check_secrets_test.dart — … (T-RELEASE-02)
EXIT=1
```
✅

### S8/3b — további Dart-variánsok (saját bővítés)

| Variáns | Eredmény |
|---|---|
| **A** — egymásba ágyazott group (`group('outer', skip: true, () { group('inner', () { test(…) }) })`) | **EXIT=1**, `T-RELEASE-02` disabled ✅ |
| **C** — `test('…', skip: 'flaky', () {…})` STRING-értékű skip | **EXIT=1**, `T-RELEASE-02` disabled ✅ |
| **B** — testvér-teszt `skip: true`-val, a guard-teszt NEM skipelt, közös, NEM skipelt group | **EXIT=1** → **HAMIS POZITÍV**, lásd **S13** |

---

## S9 — a guard-cél csendes visszagyengítésének piros útja → **ZÁRVA**

A followup pontos rontása (`docs/security/threat-model.md:105-106`
visszaállítva a gyengébb célra):

```
id: T-CLIENT-01
…
guard:
  path: test/core/storage/secure_store_test.dart
  test: round-trips a secret
```

A scan maga továbbra is EXIT 0 (a gyengébb teszt LÉTEZIK — ez a lelet lényege):

```
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.       SCAN_EXIT=0
```

de a gate-teszt MOST piros, pontosan egy cellával:

```
$ flutter test test/tooling/security_scan_test.dart
00:03 +32 -1: MINOR-2 — … each known id resolves to its OWN shipped guard.path + guard.test — a silent retarget to a weaker guard is a critical finding, not a pass (S9) [E]
  Expected: true
    Actual: <false>
  T-CLIENT-01 no longer resolves to its shipped guard.path (test/features/auth/token_store_test.dart) + guard.test (round-trips a token under the documented secure key) in the threat model
  test/tooling/security_scan_test.dart 1114:9         main.<fn>.<fn>
00:04 +41 -1: Some tests failed.
```

A followup mérése (37/37 zöld ugyanerre a rontásra) ezzel megdőlt: **S9 ZÁRVA.**

Megjegyzés (NOTE): a cella regexe a szállított blokk MEZŐSORRENDJÉT is rögzíti
(`id → component → threat → release_gate → guard.path → guard.test`,
`security_scan_test.dart:1100-1110`); egy ártatlan átrendezés is pirosít. Ez
fail-closed irány, nem lelet, de a jövőbeli szerkesztőnek tudnia kell róla.

---

## Új leletek

### S10 — MAJOR (latens): Dart `@Skip(...)` a `library;` NÉLKÜL megkerüli az új fájl-szintű ellenőrzést

**Hely:** `tool/release/security_scan.py:578` — `_DART_LIBRARY_SKIP =
re.compile(r"@Skip\([^)]*\)\s*\n\s*library\b")`, használat `:582-596`
(`_dart_file_skipped`).

**Failure scenario (VALÓS fán mérve).** A támadó/karbantartó a
`test/tooling/vision_model_integrity_test.dart` legelső sora elé írja:

```
@Skip('whole file disabled — no library directive')
import 'dart:convert';
```

(azaz ugyanaz, mint az S8/2, csak a `library;` sor nélkül).

```
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
SCAN_EXIT=0

$ flutter test test/tooling/vision_model_integrity_test.dart
00:00 +0: (suite)
  Skip: whole file disabled — no library directive
00:00 +0 ~1: All tests skipped.
```

Tehát a modell-integritás guard (`T-MODEL-01`) TELJESEN néma, a kapu OK-t mond.

**Miért működik ez Dartban.** A `package:test` a fájl ELSŐ direktívájának
metaadatát olvassa, nem kifejezetten a `library`-ét —
`~/.pub-cache/hosted/pub.dev/test_core-0.6.19/lib/src/runner/parse_metadata.dart:68`:

```dart
_annotations = directives.isEmpty ? [] : directives.first.metadata;
```

Vagyis az `import` fölé tett `@Skip(...)` teljes értékű fájl-szintű skip —
és ez az idióma valid Dart, nem hibás kód. A `library;` alak, amire a javítás
regexe épül, csak az EGYIK írásmód.

**Sértett szabály.** Ugyanaz, mint az S8-nál: ADR 0481 D2 + a scan saját,
ebben a commitban BŐVÍTETT docstringje (`security_scan.py:12-19`), amely már
kifejezetten állítja, hogy a „file-wide silencer (… a Dart library-level
`@Skip(...)` above `library;`)" is kritikus lelet. A docstring itt túlígér: a
mérés szerint a `library;` nélküli — teljesen szokásos — alak átmegy.

**Javasolt irány.** A `library` követelmény elhagyása: a fájl első
direktívája ELŐTTI fejlécben (ugyanaz a `_DART_IMPORT_OR_PART` határ, amit a
javítás már kiszámol) bármely `@Skip(` előfordulás fájl-szintű némításnak
számítson. A fejléc-szűkítés miatt ez a valós fa string-fixture-jeire továbbra
sem illeszkedik (a fejléc az első `import` előtt véget ér); érdemes a
direktíva NÉLKÜLI fájlra is határt húzni (első deklaráció), nehogy a fejléc az
egész fájl legyen.

### S11 — MAJOR (latens): python `pytest.skip(..., allow_module_level=True)` továbbra is zöld

**Hely:** `tool/release/security_scan.py:562-563` (`_PY_MODULE_SKIP_MARKERS =
("pytest.mark.skip", "pytest.mark.xfail")`) + `:409` (`"pytest.skip("` csak a
`def` fölötti **400 karakteres** ablakban nézve, `_python_guard_status:488-489`).

**Failure scenario (VALÓS fán mérve).** `backend/tests/test_diagnostics.py`
tetejére:

```python
import pytest
pytest.skip('whole file disabled', allow_module_level=True)
```

```
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
SCAN_EXIT=0

$ cd backend && python3 -m pytest tests/test_diagnostics.py
1 skipped in 0.01s
```

A modul teljes egészében kihagyva, `T-DIAG-01` (path traversal), `T-DIAG-02`
(oversize) és `T-DIAG-03` (token-kapu) egyszerre néma — pontosan az S8/1
kimenete —, a kapu mégis EXIT 0. A `pytest.skip(` marker azért nem fog, mert a
guard-`def`-ek 1640 / 5177 / 7410 bájtnál kezdődnek, a 400 karakteres
prelude-ablakon jóval kívül.

**Javasolt irány.** A `_python_module_skip_disabled` bővítése egy
modul-szintű (nem indentált) `pytest.skip(` / `allow_module_level=True`
mintára — ugyanaz a „bárhol a modulban" logika, ami a `pytestmark`-nál már
működik.

### S12 — MINOR (latens): osztály-szintű `@pytest.mark.skip` a 400 karakteres ablakon kívül

**Hely:** `tool/release/security_scan.py:488-489` — a dekorátor-keresés
`stripped[idx-400 : idx]`.

**Failure scenario (kontrollált fixture-en mérve, `/tmp/s8probe`).** Egy
guard-teszt, amely osztályban van és nem az első metódus:

```python
import pytest

@pytest.mark.skip(reason='class disabled')
class TestEverything:
    def test_filler_0(self): …          # 30 kitöltő metódus
    …
    def test_the_real_thing(self):
        assert True
```

```
$ python3 tool/release/security_scan.py --root /tmp/s8probe \
      --threat-model threat-model.md --only guards
security_scan: OK — no critical or fatal finding.
EXIT=0

$ python3 -m pytest guarded.py -q
sssssssssssssssssssssssssssssss   [100%]
31 skipped in 0.03s
```

**Miért MINOR és nem MAJOR:** a MAI fán nem realizálható. Végigmértem az
összes python guard-célt — a `class` és a `def` távolsága:

```
T-API-01     backend/tests/test_auth.py                    dist=n/a (modul-szintű)
T-API-02     backend/tests/test_hardening.py               dist=29
T-DIAG-01/02/03  backend/tests/test_diagnostics.py         dist=n/a (modul-szintű)
T-MEDIA-01/02/03 backend/tests/community/test_media_upload.py  dist=n/a
T-COMM-01    …/test_challenge_verification.py              dist=n/a
T-COMM-02    …/test_access_policy.py                       (a legközelebbi `class` a `_RowRef` helper, nem a teszt gazdája)
```

Az egyetlen osztályba ágyazott guard (`T-API-02`) az osztály ELSŐ metódusa
(29 bájt), tehát az osztály-dekorátor beleesik az ablakba. A lelet akkor válik
élessé, ha egy guard-tesztet később osztályba mozgatnak, vagy fölé metódusok
kerülnek — ez néma, észrevétlen romlás.

**Javasolt irány.** A `def <name>(` fölötti legközelebbi `^class ` sor
dekorátorainak külön vizsgálata (ablak-független), vagy egyszerűen `ast`-alapú
feldolgozás a python ágon.

### S13 — MINOR: `_dart_enclosing_group_skipped` HAMIS POZITÍVOT ad testvér- és string-beli `skip:`-re

**Hely:** `tool/release/security_scan.py:602-612` — `if match.start() +
len(span) > call_start and "skip:" in span`. A `span` a group teljes
szövege, string-tartalommal együtt (`_dart_call_span:493-520` csak a
zárójel-egyensúlyhoz ugorja át a stringeket, a visszaadott szeletbe
beleteszi őket).

**Failure scenario (VALÓS fájlon mérve).** Egy ÁRTATLAN szerkesztés:
`test/tooling/check_secrets_test.dart`-ban a guard-teszt köré kerül egy NEM
skipelt group, benne egy független, flaky teszttel:

```
  group('mixed', () {
    test('unrelated flaky', skip: true, () { expect(1, 1); });
    test('flags provider token literals by their own prefix', () { … });
  });
```

```
$ python3 tool/release/security_scan.py --only guards
security_scan: 1 finding(s).
- [critical] guards: T-RELEASE-02 (release-chain): guard.test 'flags provider token literals by their own prefix' is present but disabled (skip/xfail marker) in test/tooling/check_secrets_test.dart — …
EXIT=1
```

A guard-teszt NINCS elnémítva, mégis „present but disabled" — a kapu egy
tényszerűen HAMIS állítással blokkolja a release-t. Ugyanez történik, ha a
group szövegében pusztán egy STRING-literál tartalmaz `skip:`-et (ez a
`security_scan_test.dart` saját fixture-mintája).

**Miért MINOR:** fail-closed irány (nem enged át némított guardot), tehát nem
határsértés. De két valós következménye van: (a) a valós fa zöldsége a
guard-tesztek és a `skip:`-et tartalmazó fixture-ök jelenlegi
GROUP-elrendezésén múlik — nincs rá teszt, hogy ez így is maradjon; (b) a
hamis piros természetes „javítása" a guard-teszt kimozgatása vagy a cella
gyengítése.

**Javasolt irány.** A group `skip:` keresését a group hívás
ARGUMENTUM-fejére szűkíteni (a záró `() {` előtti rész), és a string-literál
tartalmakat a keresés elől maszkolni.

### S14 — MINOR: az S8/2 (Dart library-`@Skip`) cella NEM méri a hozzá tartozó javítást

**Hely:** `test/tooling/security_scan_test.dart:855-889` (a `T-FIXTURE-15`
cella fixture-je) vs. `tool/release/security_scan.py:582-596`
(`_dart_file_skipped`).

**Mérés (mutation-kill, lásd lent).** A RÉGI eszközzel (`git checkout
f252034d^ -- tool/release/security_scan.py`) az ÚJ cellák közül **három**
pirosodik, a negyedik — épp a Dart library-`@Skip` cella — **zöld marad**.

**Miért.** A cella fixture-je egy 6 soros fájl:

```
@Skip('whole file disabled')
library;

void main() {
  test('the real thing', () {
```

Itt az `@Skip(` a `test(` hívástól kevesebb mint 200 karakterre van, tehát a
JAVÍTÁS ELŐTTI, teszt-lokális szabály (`"@Skip(" in prelude`, `:553`,
200 karakteres ablak) már önmagában pirosít. A cella így nem tudja
megkülönböztetni a régi és az új viselkedést: a `_dart_file_skipped` függvény
törölhető lenne, és a suite zöld maradna.

**Következmény.** A Dart fájl-szintű ellenőrzés a suite szempontjából
lefedetlen — és pontosan ez az a kód, amelyet az **S10** megkerül. A valós
guard-fájlok több ezer karakteresek, ahol a 200 karakteres ablak NEM ér el a
fejlécig.

**Javasolt irány.** A fixture bővítése úgy, hogy a `test(` hívás a fejléctől
200 karakternél messzebb legyen (pl. kitöltő tesztek/kommentek beszúrása), és
egy második cella a `library;` NÉLKÜLI alakra (S10).

---

## Mutation-kill — a RÉGI eszköz az ÚJ cellák alatt

```
$ git checkout f252034d^ -- tool/release/security_scan.py
$ flutter test test/tooling/security_scan_test.dart
00:04 +39 -3: Some tests failed.

Failing tests:
  … S8 … a Dart `group(..., skip: true)` wrapping the guard.test silences it even though the test's own call carries no marker
  … S8 … a module-level `pytestmark = [pytest.mark.skip(...)]` list form silences the whole python file too
  … S8 … a module-level `pytestmark = pytest.mark.skip(...)` silences the whole python file even though the test itself carries no marker

$ git checkout HEAD -- tool/release/security_scan.py
$ git status --short
?? docs/reviews/e12-r18-review-security-fix2.md      (csak EZ a jelentés, commitolatlanul)
$ python3 tool/release/security_scan.py
security_scan: OK — no critical or fatal finding.    EXIT=0
```

**Értékelés.** A négy új S8-cellából **három** valódi mutation-kill-tanú
(pontosan a `_python_module_skip_disabled` és a `_dart_enclosing_group_skipped`
javításokat fedik). A negyedik — `T-FIXTURE-15`, Dart library-`@Skip` —
**nem tanú**: a régi eszközzel is zöld → **S14**. Az **S9**-cella szintén nem
pirosodik a régi ESZKÖZZEL, de ez helyes: az S9 javítása kizárólag a
tesztfájlban van, piros útját a threat-model rontása bizonyítja (fent).

---

## Regresszió-ellenőrzés — a hét korábban zárt lelet nem nyílt vissza

### MAJOR-1 — kivétel nem nyelheti el a `secrets` ágat

```
$ python3 tool/release/security_scan.py --exceptions /tmp/exc_secrets.yaml --secrets-cmd /bin/false
security_scan: 2 finding(s).
- [critical] exceptions: exceptions[0] (finding='secrets.delegate-failed'): branch 'secrets' is not exceptable — only ['dependencies', 'guards'] findings can ever be suppressed; `secrets` can never be waved away (ADR 0481 D3) (exceptions.invalid-branch)
- [critical] secrets: secrets delegate command '/bin/false' exited 1:  (secrets.delegate-failed)
EXIT=1

$ python3 tool/release/security_scan.py --exceptions /tmp/exc_guards.yaml --secrets-cmd /bin/false
security_scan: 1 finding(s).
- [critical] secrets: secrets delegate command '/bin/false' exited 1:  (secrets.delegate-failed)
EXIT=1
```

Élő, jövőbeli lejáratú kivétel (`finding: secrets.delegate-failed`) sem
`branch: secrets`, sem `branch: guards` alatt nem nyeli el a titok-ágat. ✅

### MAJOR-2 — kikommentelt / átnevezett / skip-markeres guard

```
=== M2a: python guard-teszt átnevezve _v2 utótaggal ===
- [critical] guards: T-DIAG-03 …: guard.test 'test_diagnostics_rejects_bad_token' not found in backend/tests/test_diagnostics.py       EXIT=1
=== M2b: a Dart guard-teszt kikommentelve ===
- [critical] guards: T-RELEASE-02 …: guard.test 'flags provider token literals by their own prefix' not found in test/tooling/check_secrets_test.dart   EXIT=1
=== M2c: @pytest.mark.skip közvetlenül a guard-teszt fölött ===
- [critical] guards: T-DIAG-03 …: guard.test 'test_diagnostics_rejects_bad_token' is present but disabled (skip/xfail marker) …        EXIT=1
```
✅

### Zöld alapállapot

```
$ flutter test test/tooling/security_scan_test.dart
00:03 +42: All tests passed!

$ flutter test test/tooling/check_secrets_test.dart
00:00 +13: All tests passed!

$ cd backend && python3 -m pytest tests/test_security_release.py tests/test_hardening.py
29 passed in 33.02s
```

A `security_scan_test.dart` cellaszáma 37 → **42** (a négy S8-cella + az S9-cella).

---

## Amit NEM mértem

- A teljes `tools/round-gate.sh`-t, a teljes Flutter-suite-ot és a teljes
  backend-suite-ot (a kör-dokumentum §10 állításai) — csak a kör két
  gate-fájlját + a két megnevezett backend-tesztfájlt futtattam.
- `flutter analyze` (a CI méri; a brief kifejezetten kihagyatja).
- A MINOR-4 / MINOR-5 (JSON futás-metaadat, egy-klauzulás advisory-illesztés)
  státuszát — a koordinátor korábban kivette a körből.
- A `--format json` kimenet tartalmát a mostani rontások alatt (csak a
  szöveges kimenetet és az exit-kódot mértem).
- A `conftest.py`-alapú némítást (`collect_ignore`, `--ignore`, gyűjtés
  átirányítása) és a Dart `@Tags`/`test_on`-alapú kizárást — ezek is a
  „silencer" osztályba tartoznak, de nem próbáltam ki.
- Nem mértem, hogy a scan bekötése a CI-be megtörtént-e (a kör szándéka
  szerint nem).

---

## Nyitott leletek

| Súlyosság | Darab | Lelet |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 2 | **S10** (Dart `@Skip` `library;` nélkül → EXIT 0, valós fán mérve), **S11** (`pytest.skip(allow_module_level=True)` → EXIT 0, valós fán mérve) |
| MINOR | 3 | **S12** (osztály-szintű skip a 400 karakteres ablakon kívül), **S13** (hamis pozitív testvér-/string-beli `skip:`-re), **S14** (az S8/2 cella fixture-je degenerált — a régi eszközzel is zöld) |
| NOTE | 1 | az S9-cella regexe a threat-model mezősorrendjét is rögzíti |

Zárva ebben a körben: **S8 (a négy nevesített forgatókönyv + két python-variáns)**,
**S9**. Regresszió: nincs.

**Verdikt: CHANGES REQUESTED** — az S8 hibaosztálya két, a valós fán
reprodukált, egysoros vektorral (S10, S11) nyitva marad; mindkettő ugyanazt a
hatást éri el, amit a javítás le akart zárni. A javítás egyébként helyes és
mérhető; az S10/S11 zárása néhány soros bővítés ugyanabban a két függvényben.
