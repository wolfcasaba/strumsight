# E12-R13 — Review (Device matrix és device lab nyilvántartás)

- **Kör:** `E12-R13` · **Branch:** `sonnet-impl/e12-r13-device-matrix-and-device-lab`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `tools/mm-round.sh`)
- **Reviewer:** Claude (Opus 5), orchesztrátor — READ-ONLY review, izolált klónban mérve
- **Reviewelt HEAD:** `75ec69bc` (implementer commitok: `d77f3c95`, `6e8053ce`, `75ec69bc`)
- **Brief:** [`docs/rounds/e12-r13-device-matrix-and-device-lab.md`](../rounds/e12-r13-device-matrix-and-device-lab.md)
- **Dátum:** 2026-08-29

## 1. VÉGSŐ DÖNTÉS (1. menet): **CHANGES REQUESTED** — 1 MAJOR

A kör tartalmilag erős: a mátrix csak MÉRT eszközöket visz be, a GA-scope lista a
zárt SDD-szótárból jön, a Dart-oldali mérce `package:yaml` nélkül megy, és a
Python eszközt gépileg méri. **Egy mért hibaosztály viszont nyitva maradt: a
kötelező tesztcsomag kiüresíthető anélkül, hogy bármelyik cella pirosra váltana.**

## 2. Scope-audit

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r13 \
    --brief docs/rounds/e12-r13-device-matrix-and-device-lab.md --base cb6ce20a
Legacy scope audit OK (cb6ce20a8fbb..75ec69bc9479, 5 changed path(s), 0 generated/ignored)
```

A commitolt fájlhalmaz pontosan az engedélyezett öt útvonal:

```
docs/rounds/e12-r13-device-matrix-and-device-lab.md
docs/testing/device-lab.md
docs/testing/device-matrix.yaml
test/tooling/device_matrix_test.dart
tool/device_report.py
```

`docs/manual-testing/**`, `lib/**`, `pubspec.yaml`, `.github/**`, `tools/**`
érintetlen. Az első audit-futás egyetlen leletet adott
(`prompt-e12-r13.md`) — ez az **orchesztrátor** saját, soha nem commitolt
prompt-fájlja volt a munkafában, nem az implementer diffje; a fájl áthelyezése
után az audit tiszta.

## 3. Független mérés — izolált klón, valódi-sértés próbák

Klón: `/tmp/e12r13-review` @ `75ec69bc`, `tools/prepare-flutter-generated.sh` után.

**Baseline:** `flutter test test/tooling/device_matrix_test.dart` → `+99: All tests passed!`

Hét eldobható mutáció a VALÓDI `docs/testing/device-matrix.yaml`-on (mindegyik
után `git checkout` visszaállítás):

| # | Mutáció | Eredmény | Verdikt |
|---|---|---|---|
| P1 | minden `release_blocking: true` → `false` | `+96 -3: Some tests failed.` | ✅ az A2 fog |
| P2 | `ram_gb: 6` → `ram_gb: unknown` (pixel_6a) | `+98 -1: Some tests failed.` | ✅ az A1 helykitöltő-cellája fog |
| P3 | `core_support: supported` → `unsupported` (pixel_6a) | `+98 -1: Some tests failed.` | ✅ az A3 fog |
| P4 | `provenance` sorszám → `:99999` (a fájl végén túl) | `+98 -1: Some tests failed.` | ✅ az A5 fog |
| P5 | az `onboarding` GA-capability törölve | `+97 -2: Some tests failed.` | ✅ az A7 fog |
| P6 | **`required_suite: []` egy `release_blocking: true` eszközön** | **`+99: All tests passed!`** | ❌ **F1 MAJOR** |
| P7 | capability nem létező eszköz-id-ra hivatkozik | `+98 -1: Some tests failed.` | ✅ fog |

## 4. Leletek

### F1 — MAJOR: egy `release_blocking: true` eszköz kötelező tesztcsomagja kiüresíthető, és a kapu ZÖLD marad

**Fájl:** `docs/testing/device-matrix.yaml` (séma) + `test/tooling/device_matrix_test.dart` (a hiányzó cella)

**Mért hibaszcenárió.** A `required_suite` mező NINCS a kilenc kötelező
azonosító-mező között (A1), és semmilyen cella nem méri, hogy egy blokkoló eszköz
csomagja nem üres. Így egy önmagában szabályos szerkesztés kiüresíti:

```
$ # mindkét release_blocking: true eszköz required_suite mezője []-re állítva
$ flutter test test/tooling/device_matrix_test.dart
00:00 +99: All tests passed!

$ python3 tool/device_report.py --matrix docs/testing/device-matrix.yaml --check
device_report check: every mandatory run is recorded.
$ echo $?
0
```

Az utolsó két sor a lelet lényege: **eredmény-fájl nélkül**, egyetlen lefuttatott
mérés nélkül a release-readiness check azt jelenti, hogy „minden kötelező futás
rögzítve van", és 0-val lép ki. A változatlan mátrixon ugyanez a parancs helyesen
26 hiányzó futást sorol fel és 1-gyel lép ki.

Ez pontosan a kör §9-ben nevesített **látszat-lefedettség** kockázata és az
[L546](../LESSONS.md#l546) (E12-R12) hibaosztálya: a checker egy szabályosnak
látszó szerkesztéstől kiüresedik, a teszt pedig ezt zöldként rögzíti. Az A2
invariáns formálisan teljesül (van blokkoló eszköz), csak épp semmit nem mér —
a capability → blokkoló eszköz → kötelező mérés láncnak a harmadik szeme őrizetlen.

**Javítás (a kör saját fájljain belül):**

1. `test/tooling/device_matrix_test.dart` — új cellák:
   - fixture-negatív: egy `release_blocking: true` eszköz `required_suite: []`
     értékkel **PIROS**, a hibaüzenet nevezze meg az eszközt;
   - fixture-negatív: egy `release_blocking: true` eszköz, amelynek a
     `required_suite`-jából hiányzik a szótár legalább egy kötelező eleme
     (a 13-ból), **PIROS**;
   - valódi-fájl cella: mindkét blokkoló eszköz csomagja pontosan a 13 elemű
     kötelező szótár (a `local_ai_load_ttft` nélküli §18.2-lista);
   - `required_suite` felvétele az A1 kötelező-mező listájába (üres és hiányzó
     egyaránt hiba).
2. `tool/device_report.py` — a `--check` **fail-closed**: ha egy
   `release_blocking: true` eszköz `required_suite`-ja üres vagy hiányzik, az
   nem „0 hiányzó futás", hanem hiba (nem-nulla kilépés, az eszköz megnevezésével).
   Gépi bizonyíték: az A4 csoport új cellája `Process.runSync('python3', …)`-szel
   fixture-mátrixon.

### F2 — MINOR: a `ram_gb`/`soc` értékek forrása nincs a gépileg ellenőrzött `provenance`-ban

**Fájl:** `docs/testing/device-matrix.yaml:33,50,67,84`

Minden eszköz `provenance`-a a `vision-device-matrix.md` sorára mutat — ott
viszont csak a **kamera-spec** szerepel. A `ram_gb` és a `soc` MÉRT forrása a
`vision-performance-benchmark.md:117-120`, amit ma csak a `device-lab.md` §6
prózája mond ki („cross-checked against … for RAM"), gépi ellenőrzés nélkül. Az
A5 cellája így a hivatkozás LÉTEZÉSÉT méri, de nem azt, hogy a mátrix minden mért
mezőjének van forrása.

**Javítás:** egy második, ugyanúgy validált mező (pl.
`spec_provenance: docs/manual-testing/vision-performance-benchmark.md:117`), az
A5 „létező fájl:sor" ellenőrzésébe és az A1 kötelező-mező listájába bekötve.

### N1 — NOTE: a nem-mapping `--results` fájl csendben üresre esik vissza

`tool/device_report.py:107-108` — ha a `--results` fájl nem mappinggé dekódol, a
`results` üres marad, figyelmeztetés nélkül. **Nem ad hamis zöldet** (üres
eredményhalmaz ⇒ minden kötelező futás hiányzik ⇒ nem-nulla kilépés), ezért ez
csak megjegyzés; egy explicit hibaüzenet mégis olcsóbbá tenné a hibakeresést egy
elgépelt eredmény-fájlnál.

## 5. Ami rendben van (mért, nem bemondásos)

- **A1–A3, A5–A8:** a P1–P5, P7 próbák mindegyike pirosra viszi a megfelelő
  cellát a VALÓDI fájlon — a cellák nem tautologikusak.
- **A4:** a Python eszközt a teszt `Process.runSync('python3', …)`-szel,
  ideiglenes fixture-könyvtárakon méri, skip-ág nélkül (a `python3 --version`
  önellenőrző cella a fájl végén); a §7 parancs valódi, nem-nulla kimenete a
  §10-ben szerepel.
- **A8 (L527):** az önvédő cella a `Process.run`, `.runSync` ÉS `.start`
  belépési pontot is nézi — pontosan az a vakfolt, ami az E12-R03-ban átment.
- **R3 (`package:yaml` nélkül):** a teszt saját, szűkített olvasót visz, és a
  `device-lab.md` §3 a nyelvtant szerkesztési szerződésként kiírja; öt
  parser-cella méri a részhalmaz határait.
- **Nincs kitalált adat:** a Samsung Galaxy S23 és a Pixel 4a indokolt kihagyása
  (`device-lab.md` §6) a helyes, őszinte döntés — mért RAM/SoC nélkül nem kerültek be.
- **A tilos zóna sértetlen:** a hat `docs/manual-testing/` dokumentum bájtra
  változatlan.

## 6. Javító kör után (2. menet)

_Kitöltés a javító kör mérése után._
