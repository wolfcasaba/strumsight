# E12-R12 — Release fixture corpus és golden data

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 12
- **Kör-azonosító:** `E12-R12`
- **Branch:** `<motor>/e12-r12-release-fixture-corpus-and-golden-data`
- **Előfeltétel:** `E12-R11` merge-elve (az e2e harness a fixture-korpusz első fogyasztója)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0453` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "fixture corpus golden data checksum license manifest regression"` → **[L516](../LESSONS.md#l516)** (a golden ARM↔x86 raszterizációs drift KÉPERNYŐ-FÜGGŐ — egy szomszéd kör gate-sorának öröklése némán rossz kaput telepít) és **[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)** (a goldeneket a MERGE-KAPU architektúráján mérjük). A fixture-manifest ezért **nem** vonja be a UI-goldeneket: azok saját, mért szabály alatt élnek.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** listázd újra a `test/fixtures/` MÉRT tartalmát (a megíráskor: `analysis`, `audio`, `practice`, `practice_generator`, `practice_planner`, `song_trainer`, `vision` könyvtárak + 7 gyökér-szintű parity JSON) és nézd meg a MEGLÉVŐ licenc-ellenőrzőt: `tool/ci/check_song_fixture_licenses.dart`. A kör ezt BŐVÍTI, nem duplikálja.

## 0.0 Mit jelent itt a „release corpus"

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

- `test/fixtures/`: hét al-könyvtár (`analysis`, `audio`, `practice`, `practice_generator`, `practice_planner`, `song_trainer`, `vision`) és hét gyökér-szintű parity-JSON (`chord_crnn_parity.json`, `crnn_live_3c_parity.json`, `crnn_live_parity.json`, `crnn_parity.json`, `logmel_parity.json`, `logmel_parity_cases.json`, `chord_crnn_parity.json`).
- `test/fixtures/audio/song_trainer/pitch_fixture_manifest.json` MÁR létezik — RÉSZLEGES manifest egyetlen alterületre; a kör ezt beemeli, nem lecseréli.
- `tool/ci/check_song_fixture_licenses.dart` MÁR ellenőriz licencet a dal-fixture-ökre; `tool/ci/check_assets.dart` az asset-oldalt.
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
| A1 | A manifest a `test/fixtures/` MINDEN release-releváns fájlját tartalmazza (a checker a fát járja be, nem a listát hiszi el) | `fixture_manifest_test.dart` |
| A2 | Egy fixture tartalmának megváltoztatása a checkert PIROSSÁ teszi | `fixture_manifest_test.dart` (ideiglenes bájt-mutáció) |
| A3 | Hiányzó licenc-mező → nem-nulla kilépés | `fixture_manifest_test.dart` |
| A4 | A `test/ui/goldens/**` NEM szerepel a manifestben | `fixture_manifest_test.dart` kizárás-cellája |
| A5 | Egyetlen fixture sem jelöl felhasználói adatot tartalmazónak; ha mégis, az a `stopped` jelzés esete | a manifest + a teszt cellája |
| A6 | A meglévő `check_assets_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A checker a manifestből indul (nem a fából), így egy új, listázatlan fixture láthatatlan marad | A1 |
| A checksum-ellenőrzés helyett csak fájlméret-egyezés | A2 |
| A licenc-hiány „unknown" értékkel átcsúszik | A3 |
| A goldenek bekerülnek a manifestbe | A4 |

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

1. A fa bejárása és a MÉRT fixture-lista előállítása.
2. `tool/check_fixture_manifest.dart` (fa → manifest összevetés).
3. `test/fixtures/manifest.json` generálása és bekötése.
4. `test/tooling/fixture_manifest_test.dart`.
5. `docs/testing/release-fixture-corpus.md`.
6. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A goldenek bevonása.** Architektúra-függő drift → hamis piros minden ARM-futáson (A4).
- **Kitalált licenc.** Jogi kockázat, amit egy „unknown" érték elrejt (A3).
- **A meglévő részleges manifest kettőzése.** A `pitch_fixture_manifest.json`-t be kell emelni, nem megduplázni.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
