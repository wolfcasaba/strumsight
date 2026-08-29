# Release fixture corpus

**Belépő:** `test/fixtures/manifest.json` · **ellenőrző:**
`tool/check_fixture_manifest.dart` · **gate-teszt:**
`test/tooling/fixture_manifest_test.dart` · **döntés:** [ADR 0473](../adr/0473-release-fixture-corpus-manifest.md)

Ez a dokumentum a korpusz HATÁRAIT írja le: mi tartozik bele, mi nem, és
miért. A gépi kikényszerítés a fent felsorolt tesztfájlban él — ez a
dokumentum a szándékot rögzíti, nem duplikálja a mérést.

## Mi a "release fixture corpus"

A `test/fixtures/` fa alatt élő, **release-regresszió reprodukálásához**
szükséges adat-fixture-ök zárt listája: checksum, méret, licenc/forrás és
"tartalmaz-e felhasználói adatot" jelöléssel ellátva, egyetlen
`test/fixtures/manifest.json` fájlban. A cél: ha egy fixture bájtjai néma
kézzel megváltoznak (rossz merge, hibás generátor, sérült checkout), a gate
ezt PIROSSA teszi — ma ez csak a `song_trainer` alfára igaz
(`tool/ci/check_song_fixture_licenses.dart`), a fa többi 18 adat-fájljára
nem volt ilyen védelem.

## A korpusz gépi definíciója (ADR 0473 D2)

**Minden fájl a `test/fixtures/` alatt, KIVÉVE:**

- `*.dart` fixture-építő FORRÁSOK — ezeket az `analyze` és a fogyasztó
  tesztek mérik, nem ez a manifest;
- `README.md` fájlok (a meglévő `check_song_fixture_licenses.dart` mért
  szabályának átvétele);
- maga a `test/fixtures/manifest.json` — önmagát nem tudja checksumolni
  (fixpont-probléma: a saját hash-e a saját tartalmától függne).

A definíció **fail-closed**: minden ÚJ, nem kizárt kiterjesztésű fixture
automatikusan bejegyzést követel — a checker a FÁT járja be, nem a manifest
listáját hiszi el (D1). Mért darabszám 2026-08-29-én: **48**.

## Mi NEM tartozik a korpuszba

- **`test/ui/goldens/**`** — a UI-golden PNG-k raszterizációja
  architektúra-függő ([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md),
  [L516](../LESSONS.md#l516)): egy ARM-on felvett golden x86 CI-n hamisan
  pirosodna, és fordítva. A goldenek saját, a merge-kapu architektúráján mért
  szabály alatt élnek — ezt a manifest bevonása aláásná. A checker ezt cellával
  méri (A4): egy `test/ui/goldens/**` alá mutató manifest-bejegyzés maga is
  hiba (a bejegyzés nem `test/fixtures/` alatti útvonalra mutat).
- **`ml/**` tréning-korpusz** és **`local_ai/**` kiértékelő készlet** — az
  Epic 10 sáv terméke, ezt az ADR 0473 kifejezetten nem dönti el.
- A `test/fixtures/` alatti `*.dart` fixture-építő kód és a `README.md`
  fájlok (fent, D2).

## A manifest mezői

```json
{
  "schemaVersion": 1,
  "fixtures": [
    {
      "path": "test/fixtures/...",
      "bytes": 123,
      "sha256": "64 alsó-hex karakter",
      "license": "...",
      "source": "...",
      "containsUserData": false
    }
  ]
}
```

- `path` — repó-relatív, `test/fixtures/` alatti útvonal. Abszolút
  gép-útvonal (`/home/`, `/Users/`, `C:\`) vagy időbélyeg-jellegű,
  futásonként változó mező nem kerülhet a fájlba
  ([L530](../LESSONS.md#l530), ADR 0473 D7) — ezt a checker a manifest teljes
  szövegén szkenneli, a parse-olt mezőktől függetlenül.
- `sha256` — a fájl TARTALMÁNAK checksuma (`package:crypto`), nem méret- vagy
  névegyezés (D3).
- `license` / `source` — mindkettő kötelező, nem üres string, és nem lehet
  placeholder. Ismeretlen licenc esetén a helyes válasz a `stopped` jelzés,
  NEM egy helykitöltő érték beírása (D4) — ezt a checker GÉPILEG kényszeríti
  ki: az üres/hiányzó eset mellett a normalizált (trim + kisbetűs) mező nem
  lehet eleme a `tool/check_fixture_manifest.dart`-ból exportált
  `placeholderProvenanceValues` listának (`unknown`, `unspecified`, `n/a`,
  `na`, `tbd`, `todo`, `none`, `-`, `?`, `fixme` — kis- és nagybetűs alakban
  is). Ha egy fixture valódi licence/forrása nem állapítható meg, a válasz a
  `stopped` jelzés, nem a placeholder beírása.
- `containsUserData` — explicit `bool`, nincs hallgatólagos alapérték (D8).
  Ha bármelyik fixture `true`-t igényelne, az a `stopped` jelzés esete: egy
  release-korpuszban nincs helye felhasználói adatnak.

## Kereszt-egyezés a `song_trainer` alfával (ADR 0473 D6)

A `song_trainer` 30 fájljára a védett `tool/ci/check_song_fixture_licenses.dart`
`const` listája is tart `sha256`-ot. Ez a manifest NEM váltja ki azt a
fájlt — a `provenance`-szövegeket továbbra is a védett checker hordozza —,
hanem a két forrás sha256-jának egyeznie kell: a `fixture_manifest_test.dart`
A7 cellája ezt méri (a manifest sha256-ja szó szerint előfordul a védett
checker forrásszövegében). A `tool/ci/**` fa ebben és minden más körben
védett mérce-zóna (ADR 0321/0372); az egyezést az ÚJ oldal (ez a manifest)
tartja fenn, nem a régi.

## Hogyan futtasd

```bash
dart run tool/check_fixture_manifest.dart
tools/round-gate.sh test/tooling/fixture_manifest_test.dart test/tooling/check_assets_test.dart
```

Új fixture hozzáadásakor: futtasd a checkert, vedd fel a hiányzó bejegyzést a
manifestbe a mért `sha256`/`bytes` értékkel, és a forrás/licenc kitöltése
előtt állapítsd meg a valódi eredetet — kitalált érték tilos.
