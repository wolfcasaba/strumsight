# E12-R12 — Release fixture corpus és golden data

- **Státusz:** READY (pre-flight 2026-08-29, kód ÚJRAMÉRVE: `main @ 9880158e`; előre megírva 2026-08-27)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 12
- **Kör-azonosító:** `E12-R12`
- **Branch:** `<motor>/e12-r12-release-fixture-corpus-and-golden-data`
- **Előfeltétel:** `E12-R11` merge-elve (az e2e harness a fixture-korpusz első fogyasztója)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`ADR 0473`](../adr/0473-release-fixture-corpus-manifest.md) — a
  pre-flightban megírva. (A batch-terv `0453`-at szánt ide; a §0.0/R1 revízió
  méri, miért `0473` a helyes szám.)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "fixture corpus golden data checksum license manifest regression"` → **[L516](../LESSONS.md#l516)** (a golden ARM↔x86 raszterizációs drift KÉPERNYŐ-FÜGGŐ — egy szomszéd kör gate-sorának öröklése némán rossz kaput telepít) és **[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)** (a goldeneket a MERGE-KAPU architektúráján mérjük). A fixture-manifest ezért **nem** vonja be a UI-goldeneket: azok saját, mért szabály alatt élnek.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** listázd újra a `test/fixtures/` MÉRT tartalmát (a megíráskor: `analysis`, `audio`, `practice`, `practice_generator`, `practice_planner`, `song_trainer`, `vision` könyvtárak + 7 gyökér-szintű parity JSON) és nézd meg a MEGLÉVŐ licenc-ellenőrzőt: `tool/ci/check_song_fixture_licenses.dart`. A kör ezt BŐVÍTI, nem duplikálja. **A pre-flight lefutott — az eredménye a §0.0 revízió.**

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-29, `main @ 9880158e`)

Az előre megírt (2026-08-27) brief mért állításai két napot avultak. A dispatch
előtt újramért tények és a belőlük következő revíziók:

**R1 — Az ADR száma `0453` helyett `0473`.** Mérve:
`tools/round-slots.py reserve-adr --round E12-R12` → **`0473`**; a lemezen a
legmagasabb ADR a `0472` (E12-R11), és `0453` **nem létezik** — a Chapter 12
batch-tartomány azóta máshogy fogyott el. A §1.0.1 szerint a foglaló a mérce,
nem az `ls` és nem a batch-terv; `0453` kiosztása ráadásul már merge-elt
döntések (0454…0472) alá esne, amit a pipeline-prompt §4 tilt.

**R2 — A fixture-fa mért állapota (a §2 helyett ez érvényes).** `find
test/fixtures -type f | wc -l` → **69**. Ebből **19 `.dart`**, **2 `README.md`**,
**48 adat-fájl** (28 `json`, 9 `musicxml`, 6 `mid`, 2 `mxl`, 1 `gp3`, 1 `gp5`,
1 `gpx`). Al-könyvtár **8**, nem 7: a `events/` (6 fájl, 2026-08-28) a brief
megírása UTÁN került be. Gyökér-szintű parity-JSON **6**, nem 7 — a brief §2 a
`chord_crnn_parity.json`-t kétszer sorolta.

**R3 — A korpusz gépi definíciója (ADR 0473 D2).** Korpusz = a `test/fixtures/`
alatti MINDEN fájl, **kivéve** a `*.dart` forrásokat és a `README.md`-ket.
Elvárt bejegyzés-szám a dispatch napján: **48**. Az `A1` „MINDEN
release-releváns fájl" kitétele EZT jelenti — a kizárás fail-closed:
minden nem kizárt kiterjesztés bejegyzést követel.

**R4 — A `pitch_fixture_manifest.json` NEM provenance-manifest.** Mérve: a fájl
`schemaVersion` + `thresholds` + `fixtures` blokkokat tartalmazó ADAT-fájl,
amelyben se útvonal, se `sha256`, se licenc-mező nincs. A brief §2/§9
„részleges manifest, amit be kell emelni" olvasata téves: a fájl a korpusz egy
**bejegyzése**, semmi több. Duplikáció-veszély innen nincs.

**R5 — A valódi duplikáció-kockázat a song-checker.** A
`tool/ci/check_song_fixture_licenses.dart` `const` listája **30**
`song_trainer` fájlra tart `sha256`-ot, és a `tool/ci/**` a
`PROTECTED_GLOBS` **védett mérce-zónája** (ADR 0321/0372) — ebben a körben nem
szerkeszthető. Két független checksum-forrás ugyanarra a 30 fájlra némán
szétcsúszhat → új **A7** kereszt-cella (ADR 0473 D6).

**R6 — [L530](../LESSONS.md#l530) átvitele.** Az E12-R06 generált,
kiadásra szánt artefaktuma 155 sorban vitte magával a generáló gép abszolút
`/home/ubuntu/...` útvonalát, teljesen zöld gate mellett → új **A8** cella:
a manifest kizárólag repó-relatív útvonalakat tartalmaz (ADR 0473 D7).

**Visszakeresés (§4.9, szűkítve ELŐSZÖR):**
`--corpus lessons,halts,adr` → [ADR 0447](../adr/0447-release-manifest-provenance-and-sbom.md)
(fail-closed license-feloldás, determinizmus), [ADR 0063](../adr/0063-generated-ml-manifest-and-backend-ci.md)
(a checksum-gate a `flutter test`-en át érvényesül, a manifest generált),
[L530](../LESSONS.md#l530) (abszolút útvonal a generált artefaktumban);
teljes korpuszon: `test/tooling/release_manifest_test.dart` és
`test/tooling/ml_asset_manifest_test.dart` a követendő gate-teszt-minta (a
tool-t sima könyvtárként importálja, ideiglenes projekt-gyökéren mér).

## 0.0.1 Mit jelent itt a „release corpus"

Nem új hangfájlokat gyűjt a kör. A MÉRT fixture-készlet MA létezik, de nincs egyetlen manifestje, amiből egy release-regresszió reprodukálható: hiányzik a checksum, a licenc-forrás és a séma-verzió. A kör ezt a hiányt zárja, és a `test/fixtures/manifest.json`-t teszi az egyetlen belépővé.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "test/fixtures/manifest.json",
  "tool/check_fixture_manifest.dart",
  "test/tooling/fixture_manifest_test.dart",
  "docs/testing/release-fixture-corpus.md",
  "docs/rounds/e12-r12-release-fixture-corpus-and-golden-data.md",
]
gate_tests = [
  "test/tooling/fixture_manifest_test.dart",
  "test/tooling/check_assets_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy meglévő fixture licence NEM állapítható meg a repóból, a kimenet a `stopped` jelzés és jelentés — kitalált licenc-mező beírása TILOS.

## 1. Cél

Verziózott, checksummal és licenccel ellátott fixture-korpusz, amelyen a release-regresszió reprodukálható, és amelyben nincs érzékeny felhasználói adat.

## 2. Jelenlegi állapot — mért tények

- `test/fixtures/`: **8** al-könyvtár (`analysis`, `audio`, `events`, `practice`, `practice_generator`, `practice_planner`, `song_trainer`, `vision`) és **6** gyökér-szintű parity-JSON (`chord_crnn_parity.json`, `crnn_live_3c_parity.json`, `crnn_live_parity.json`, `crnn_parity.json`, `logmel_parity.json`, `logmel_parity_cases.json`). Összesen **69 fájl**: 19 `.dart`, 2 `README.md`, **48 adat-fájl** (§0.0/R2–R3).
- `test/fixtures/audio/song_trainer/pitch_fixture_manifest.json` MÁR létezik, de **NEM provenance-manifest** — küszöb- és eset-adatokat tartalmazó ADAT-fájl, tehát a korpusz egy BEJEGYZÉSE (§0.0/R4).
- `tool/ci/check_song_fixture_licenses.dart` MÁR ellenőriz licencet **30** `song_trainer` fixture-re (`path` + `provenance` + `licence` + `sha256` `const` listában, a `README.md`-ket kizárva); `tool/ci/check_assets.dart` az asset-oldalt. A `tool/ci/**` **védett zóna** — ebben a körben nem szerkeszthető (§0.0/R5).
- `tool/check_fixture_manifest.dart` **nem létezik** (a `tool/ci/` fa a MÉRCE védett zónája — ADR 0321/0372, `protect_factory_files.py` `PROTECTED_GLOBS` —, ezért az ÚJ ellenőrző a `tool/` gyökérbe kerül, a `tool/check_architecture.dart` mintájára).
- `test/fixtures/manifest.json` (globális) **nem létezik**; `ml/fixtures/release/` és `local_ai/evaluation/` **nem létezik** (az utóbbi az Epic 10 sáv terméke lenne — ez a kör NEM hozza létre).
- A UI-goldenek `test/ui/goldens/` alatt élnek, ADR 0426 mért szabálya alatt.

## 3. Scope

**Benne van:** `test/fixtures/manifest.json` — MINDEN release-releváns fixture: útvonal, sha256, méret, séma-verzió, licenc/forrás, „tartalmaz-e felhasználói adatot" jelölés · `tool/check_fixture_manifest.dart` — hiányzó bejegyzés, elmozdult checksum, hiányzó licenc-mező → nem-nulla kilépés · `test/tooling/fixture_manifest_test.dart` · `docs/testing/release-fixture-corpus.md` (mi tartozik a korpuszba és mi NEM: a UI-goldenek és az ML tréning-korpusz kifejezetten kívül).

**NINCS benne (tilos):**

- **A `test/ui/goldens/**` bevonása** (ADR 0426 / [L516](../LESSONS.md#l516) saját szabálya).
- Új fixture-fájl hozzáadása vagy meglévő átnevezése/törlése.
- `ml/**` és `local_ai/**` korpusz létrehozása.
- `docs/adr/**` — az ADR 0453-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `test/fixtures/manifest.json` | ÚJ — a globális fixture-manifest |
| `tool/check_fixture_manifest.dart` | ÚJ — az ellenőrző |
| `test/tooling/fixture_manifest_test.dart` | a §6 cellái |
| `docs/testing/release-fixture-corpus.md` | ÚJ — a korpusz HATÁRAI |

**Tilos zóna:** `test/fixtures/**` minden meglévő adatfájlja · `test/ui/goldens/**` · `ml/**` · `lib/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0453)

### 5.1 Ismeretlen licenc = megállás, nem „unknown"

**NEM elfogadható gyengítés:** `"license": "unknown"` beírása és a checker átengedése — egy jogilag tisztázatlan fixture a release-korpuszban kockázat, nem adminisztratív hiány.

### 5.2 A checksum a TARTALOMÉ, és eltérés esetén a checker PIROS

**NEM elfogadható gyengítés:** csak fájlnév/méret-ellenőrzés; a bináris fixture néma megváltozása pontosan az, amit a manifest mérni hivatott.

### 5.3 A UI-golden NEM része a release-korpusznak

**NEM elfogadható gyengítés:** a goldenek felvétele a manifestbe „a teljesség kedvéért" — a raszterizációs drift architektúra-függő (ADR 0426), és a manifest ettől minden ARM-futáson hamisan pirosodna.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A manifest a `test/fixtures/` MINDEN release-releváns fájlját tartalmazza — a §0.0/R3 definíció szerint (minden fájl, kivéve `*.dart` és `README.md`), a checker a FÁT járja be, nem a listát hiszi el; a mért bejegyzés-szám a dispatch napján **48** | `fixture_manifest_test.dart` (fa-bejárás + darabszám-cella) |
| A2 | Egy fixture tartalmának megváltoztatása a checkert PIROSSÁ teszi | `fixture_manifest_test.dart` (ideiglenes bájt-mutáció) |
| A3 | Hiányzó licenc-mező → nem-nulla kilépés | `fixture_manifest_test.dart` |
| A4 | A `test/ui/goldens/**` NEM szerepel a manifestben | `fixture_manifest_test.dart` kizárás-cellája |
| A5 | Egyetlen fixture sem jelöl felhasználói adatot tartalmazónak; ha mégis, az a `stopped` jelzés esete | a manifest + a teszt cellája |
| A6 | A meglévő `check_assets_test.dart` VÁLTOZATLANUL zöld | a §7 gate |
| A7 | A `song_trainer` alfa 30 fájljára a manifest `sha256`-ja EGYEZIK a védett `tool/ci/check_song_fixture_licenses.dart` `const` listájában lévővel (a védett fájl NEM módosul; a teszt a forrásszövegét olvassa) | `fixture_manifest_test.dart` kereszt-cella (ADR 0473 D6) |
| A8 | A manifest kizárólag repó-relatív útvonalakat tartalmaz — nincs benne `/home/`, `/Users/` vagy `C:\` alakú abszolút gép-útvonal | `fixture_manifest_test.dart` cella ([L530](../LESSONS.md#l530), ADR 0473 D7) |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A checker a manifestből indul (nem a fából), így egy új, listázatlan fixture láthatatlan marad | A1 |
| A checksum-ellenőrzés helyett csak fájlméret-egyezés | A2 |
| A licenc-hiány „unknown" értékkel átcsúszik | A3 |
| A goldenek bekerülnek a manifestbe | A4 |
| A `song_trainer` sha256-ok a két forrásban szétcsúsznak (pl. az új manifest újraszámolás nélkül másolt vagy elgépelt hash-t hoz) | A7 |
| A generátor abszolút gép-útvonalat ír a manifestbe (L530 hibaosztálya) | A8 |
| A `.dart` fixture-forrásokat is bejegyzésbe kényszeríti (49+ bejegyzés), vagy egy adat-fájlt kihagy (47 vagy kevesebb) | A1 (a mért **48**-as darabszám cellája) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** írj egy bájtot egy tetszőleges fixture MÁSOLATÁBA a teszt ideiglenes könyvtárában, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza (az EREDETI fixture-t tilos módosítani).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/fixture_manifest_test.dart test/tooling/check_assets_test.dart
```

A checker közvetlen futtatása (kimenet a §10-be):

```bash
dart run tool/check_fixture_manifest.dart
```

## 8. Implementációs sorrend

1. A fa bejárása és a MÉRT fixture-lista előállítása (§0.0/R3 definíció, 48 fájl).
2. `tool/check_fixture_manifest.dart` (fa → manifest összevetés). **Kötelező forma** (a mért minta: `test/tooling/release_manifest_test.dart`, `test/tooling/ml_asset_manifest_test.dart`, `tool/ci/check_assets.dart`): a fájl exportáljon egy tiszta, `projectRoot`-paraméteres függvényt, amely jelentés-objektumot ad vissza, ÉS legyen `main()`-je, ami nem-nulla `exitCode`-dal zár hiba esetén. Így az A2/A3 cellák IDEIGLENES projekt-gyökéren mérnek, és az EREDETI fixture-öket sosem módosítják. A `sha256`-hoz a már meglévő `package:crypto` (`pubspec.yaml`, `crypto: ^3.0.7`) használandó.
3. `test/fixtures/manifest.json` generálása és bekötése.
4. `test/tooling/fixture_manifest_test.dart`.
5. `docs/testing/release-fixture-corpus.md`.
6. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A goldenek bevonása.** Architektúra-függő drift → hamis piros minden ARM-futáson (A4).
- **Kitalált licenc.** Jogi kockázat, amit egy „unknown" érték elrejt (A3).
- **Két checksum-forrás szétcsúszása.** A `song_trainer` 30 fájlját a védett `tool/ci/check_song_fixture_licenses.dart` is hash-eli; az új manifestnek a MÉRT bájtokból kell számolnia, és egyeznie kell vele (A7). A `pitch_fixture_manifest.json` NEM manifest-forrás, hanem bejegyzés (§0.0/R4).
- **Abszolút gép-útvonal a generált manifestben** ([L530](../LESSONS.md#l530)) → A8.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
