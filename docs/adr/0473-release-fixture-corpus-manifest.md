# ADR 0473 — A release fixture-korpusz gépi definíciója: fa-bejárás, tartalom-checksum, fail-closed licenc

- **Státusz:** elfogadva
- **Dátum:** 2026-08-29
- **Kör:** `E12-R12` (Chapter 12, Kör 12)
- **Kapcsolódó:** [`0063`](0063-generated-ml-manifest-and-backend-ci.md)
  (generált ML asset manifest + checksum-gate a `flutter test`-en át),
  [`0447`](0447-release-manifest-provenance-and-sbom.md) (release manifest,
  provenance, SBOM — fail-closed license-feloldás),
  [`0426`](0426-golden-rasterization-on-the-gate-architecture.md) (a UI-goldenek
  a MERGE-KAPU architektúráján mérve),
  [`0321`](0321-gateguard-round-hold-not-chain-halt.md) /
  [`0372`](0372-gate-edit-policy.md) (`tool/ci/**` védett mérce-zóna)

## Kontextus

A `test/fixtures/` fa MA létezik és nagy — a pre-flight mérése (2026-08-29,
`main @ 9880158e`):

- **69 fájl**, ebből **19 `.dart`** (fixture-építő forrás), **2 `README.md`**,
  és **48 adat-fájl** (28 `json`, 9 `musicxml`, 6 `mid`, 2 `mxl`, 1 `gp3`,
  1 `gp5`, 1 `gpx`);
- **8** al-könyvtár: `analysis`, `audio`, `events`, `practice`,
  `practice_generator`, `practice_planner`, `song_trainer`, `vision` — az
  `events/` (6 fájl) 2026-08-28-án került be, tehát a kör előre megírt briefje
  (2026-08-27) még 7-et sorolt;
- **6** gyökér-szintű parity-JSON (`chord_crnn_parity.json`,
  `crnn_live_3c_parity.json`, `crnn_live_parity.json`, `crnn_parity.json`,
  `logmel_parity.json`, `logmel_parity_cases.json`) — a brief §2 hetet írt, mert
  a `chord_crnn_parity.json`-t kétszer sorolta.

Provenance-fedezet ma **egyetlen alfára** van: a
`tool/ci/check_song_fixture_licenses.dart` a `test/fixtures/song_trainer/**`
30 fájljára tart `path` + `provenance` + `licence` + `sha256` négyest egy
`const` listában, a `README.md`-ket kizárva. A fa többi **18** adat-fájljára
(a 6 parity-JSON, `events/**`, `analysis/**`, `practice/**`,
`practice_planner/**`, `vision/**` adatai és az
`audio/song_trainer/pitch_fixture_manifest.json`) nincs se checksum, se
licenc-forrás, se „tartalmaz-e felhasználói adatot" jelölés. Egy
release-regresszió ezért ma nem reprodukálható: a bináris fixture néma
megváltozása senkinél nem pirosodik.

Két további mért tény köti a döntést:

- a `tool/ci/**` a mérce **védett zónája** (`PROTECTED_GLOBS`, ADR 0321/0372),
  tehát a meglévő song-checker ebben a körben nem szerkeszthető — az ÚJ
  ellenőrző a `tool/` gyökérbe kerül, a `tool/check_architecture.dart` mintájára;
- [L530](../LESSONS.md#l530) (E12-R06): egy generált, kiadásra szánt artefaktum
  155 sorban vitte magával a GENERÁLÓ GÉP abszolút `/home/ubuntu/...`
  cache-útvonalát, teljesen zöld gate mellett.

## Döntés

**D1 — A korpusz a FÁBÓL következik, nem a listából.** Az ellenőrző bejárja a
`test/fixtures/` fát, és minden ott talált adat-fájlhoz manifest-bejegyzést
követel. A manifestben szereplő, de a fán nem létező bejegyzés ugyanúgy hiba.

**NEM elfogadható gyengítés:** a manifestből indulni és csak a felsorolt
útvonalakat ellenőrizni — egy új, listázatlan fixture így láthatatlan maradna,
ami pontosan a lezárandó rés.

**D2 — A korpusz gépi definíciója: minden fájl a `test/fixtures/` alatt, KIVÉVE
a `*.dart` forrásokat és a `README.md`-ket.** Mért indok: a `.dart` fixture-ök
FORRÁSKÓDOK — az `analyze` és a fogyasztó tesztek mérik őket, checksumba emelve
viszont minden jövőbeli kör kényszerülne a `test/fixtures/manifest.json`
frissítésére, egy olyan fájlra, ami annak a körnek az `allowed_paths`-ában
nincs benne (krónikus, mesterséges scope-ütközés). A `README.md`-kizárás a
MEGLÉVŐ `check_song_fixture_licenses.dart` mért szabályának átvétele. A
definíció fail-closed marad: minden NEM kizárt kiterjesztés — az újak is —
bejegyzést követel. Mért darabszám a döntés napján: **48**.

**D3 — A checksum a TARTALOMÉ.** Minden bejegyzés `sha256`-ot hordoz, és a
bájtok eltérése az elvárt hash-től nem-nulla kilépés.

**NEM elfogadható gyengítés:** fájlnév- vagy méret-egyezés checksum helyett — a
bináris fixture néma tartalomváltozása pontosan az, amit a manifest mérni
hivatott (ADR 0063 mintája).

**D4 — Ismeretlen licenc = megállás, nem `"unknown"`.** Hiányzó vagy üres
licenc-/forrás-mező nem-nulla kilépés. Ha egy meglévő fixture licence a repóból
nem állapítható meg, a kör kimenete a `stopped` jelzés és a jelentés; kitalált
licenc-érték beírása tilos.

**D5 — A UI-goldenek NEM részei a korpusznak.** A `test/ui/goldens/**` 144 PNG-je
architektúra-függő raszterizációt hordoz (ADR 0426, [L516](../LESSONS.md#l516)),
ezért a manifestbe emelve minden ARM-futáson hamisan pirosodna. A kizárást
CELLA méri, nem csak dokumentum-mondat.

**D6 — Ahol két forrás fedi ugyanazt a fájlt, a kettőnek EGYEZNIE kell.** A
`song_trainer` 30 fájljára a védett `tool/ci/check_song_fixture_licenses.dart`
`const` listája és az új manifest is tart `sha256`-ot. Két független
checksum-forrás némán szétcsúszhat, ezért a kereszt-egyezést cella méri (a
manifest sha256-jának elő kell fordulnia a checker forrásszövegében is). A védett
fájl NEM módosul; az egyezést az új oldal tartja.

**D7 — Repó-relatív útvonalak, gép-független tartalom.** A manifest kizárólag
`test/fixtures/...` alakú, repó-relatív útvonalakat tartalmazhat; abszolút
gép-útvonal (`/home/`, `C:\`) vagy időbélyeg-jellegű, futásonként változó mező
nem kerülhet bele ([L530](../LESSONS.md#l530), ADR 0447 determinisztikus
manifest-mintája).

**D8 — Felhasználói adat: explicit, hamis alapérték.** Minden bejegyzés
`containsUserData` jelölést hordoz; ha bármelyik igaz lenne, az a `stopped`
jelzés esete, nem a manifestbe rejtett tény.

## Következmények

- A `test/fixtures/manifest.json` lesz a release-fixture korpusz **egyetlen
  belépője**; a `dart run tool/check_fixture_manifest.dart` fut a
  `flutter test`-en át (`test/tooling/fixture_manifest_test.dart`), az ADR 0063
  bevált mintája szerint.
- A `tool/ci/check_song_fixture_licenses.dart` **változatlan marad**, és nem
  válik feleslegessé: a song-alfa provenance-szövegeit (`provenance`) továbbra
  is ő hordozza; az új manifest a TELJES fát fedi le és a kettőt D6 köti össze.
- Az `audio/song_trainer/pitch_fixture_manifest.json` a korpusz egy
  **bejegyzése**, nem provenance-forrás: mérve `schemaVersion` + `thresholds` +
  `fixtures` sorokat tartalmazó ADAT-fájl, amelyben se útvonal, se `sha256`, se
  licenc-mező nincs.
- Új fixture felvétele ezentúl manifest-bejegyzés nélkül **megbukik** — ez
  szándékos, fail-closed költség (ADR 0447 mintája).
- Amit ez az ADR NEM dönt el: az `ml/**` tréning-korpusz és a `local_ai/**`
  kiértékelő készlet kezelése (Epic 10 sáv), és a UI-goldenek saját
  verziózása — az ADR 0426 alatt marad.
