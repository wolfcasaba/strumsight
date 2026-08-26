# E13-R23 — kör-review

- **Kör:** `E13-R23` — Song Library, Overview és Setlist lista UI
- **Branch:** `sonnet-impl/e13-r23-song-library-and-setlists`
- **Reviewelt HEAD:** `77d083e8` (bázis: `main @ 76566726`)
- **Implementer motor:** Claude Sonnet 5 (`sonnet-impl`)
- **Reviewer:** Claude Opus 5 (orchestrátor, read-only)
- **Dátum:** 2026-08-26
- **Verdikt (1. kör):** CHANGES REQUESTED — 0 BLOCKER, 0 MAJOR, 3 MINOR, 3 NOTE
- **Reviewelt javító HEAD:** `5ddbbbaf` (javító kör 1.)
- **VÉGSŐ DÖNTÉS: APPROVED** — 0 BLOCKER, 0 MAJOR, 0 nyitott MINOR (§6)

---

## 1. Amit magam mértem (nem bemondás)

### 1.1 Gate — izolált `/tmp` klónban, saját kézzel

```
git clone --branch sonnet-impl/e13-r23-song-library-and-setlists \
  /home/ubuntu/ss-sonnet-impl-e13-r23 /tmp/review-e13-r23
bash /tmp/review-e13-r23/tools/prepare-flutter-generated.sh
tools/round-gate.sh test/features/songs/song_library_test.dart \
  test/features/songs/song_asset_state_test.dart \
  test/features/songs/setlist_list_test.dart test/app/navigation/ \
  test/features/song_trainer/presentation/ test/app/routing/app_router_test.dart \
  test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart \
  test/tooling/dio_factory_guard_test.dart \
  test/tooling/preferences_plugin_import_guard_test.dart \
  test/tooling/route_literal_guard_test.dart
```

**Eredmény: mind a 16 lépés ZÖLD, `GATE_EXIT=0`** (`format`, `analyze`, 11× `test`,
`architecture`, `secrets`, `l10n`). Ez FÜGGETLEN reprodukció, nem az implementer
kimenetének átvétele.

### 1.2 Scope-audit — a hiteles eszközzel

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r23 \
  --brief docs/rounds/e13-r23-song-library-and-setlists.md --base 76566726
→ Legacy scope audit OK (765667263191..77d083e8a84d, 22 changed path(s), 0 generated/ignored)
```

A 22 fájl mind az `allowed_paths`-on van. A song_trainer `application/`,
`domain/`, `data/` fája **érintetlen** (§0.0/B/R13 tiltása gépileg tartva).

### 1.3 A négy R17-pin — a migráció mércéje, nem áldozata

`test/features/song_trainer/presentation/` (11 fájl) és
`test/app/routing/app_router_test.dart` a gate [7] és [8] lépésében **ZÖLD**.
A `SongLibraryScreen` / `SongOverviewScreen` / `SetlistListScreenV2` típusneve,
útvonala, konstruktor-szignatúrája és route-regisztrációja változatlan; a
`song-editor-open-<id>` Key megmaradt (csak a navigációs CÉL ágazik el).

### 1.4 `ui_inventory` — R19 tartva

`find lib/features -name '*_screen.dart' | wc -l` → **86**;
`test/ui/ui_inventory_test.dart` diffje **ÜRES**. Új képernyő nem született.

### 1.5 Golden (A9) — megnéztem a felvett PNG-ket

6/6 PNG a diffben (`library`, `overview`, `setlist_list` × `compact`,
`compact_scale2`), a merge-kapu ISA-ján felvéve (`tools/golden-x86.sh`,
ADR 0426). Vizuálisan átnézve: **nincs overflow-csík**, a jelvények és a
forrás-chip olvashatóan elférnek, `textScaler: 2.0` mellett a tartalom
görgethető marad. A teszt VALÓDI kapu (`matchesGoldenFile`), nem `skip`-elt
rögzítő.

---

## 2. Leletek

| # | Osztály | Tárgy |
|---|---|---|
| MINOR-1 | MINOR | Az A8 cella csak a „lefedett route" olvasatot méri; a tényleges belépési úton a szűrő MÉRTEN elveszik |
| MINOR-2 | MINOR | A lista alcíme a NYERS `sourceType.code` gép-azonosítót írja ki a lokalizált forrás-chip fölé |
| MINOR-3 | MINOR | Az A2 „licenc … a listában" része nem teljesül — brief-szintű szűkítés kell, nem hallgatás |
| NOTE-1 | NOTE | `capability == null` ⇒ szerkeszthetőnek számít |
| NOTE-2 | NOTE | Az Overview másodszor is dekódolja a teljes dokumentumot, csak megjelenítéshez; a hibát elnyeli |
| NOTE-3 | NOTE | A setlist-készenlét a PERZISZTÁLT `initialAvailability`-ből jön, nem újraszámolva |

### MINOR-1 — az A8 a gyengébb olvasatot méri, és az erősebb MÉRTEN piros

**Fájl:** `test/features/songs/song_library_test.dart:189–255`
(„search text and source filter persist after pushing and returning…").

A cella `context.push`-sal nyit egy route-ot a Library FÖLÉ, majd `pop`-ol. A
`SongLibraryScreen` eközben **soha nem dispose-olódik**, tehát az
`Provider.autoDispose` mögötti `SongLibraryController` állapota triviálisan
megmarad. A teszt saját kommentje ki is mondja: *„The Library screen was never
disposed while covered."*

**Eldobható reviewer-próba** (`/tmp/probe-e13-r23/test/features/songs/probe_a8_strong_test.dart`,
a review után törölve) — ugyanaz a szűrés, de VALÓDI kilépéssel és
visszatéréssel (a `home` lecserélése, azaz dispose, majd vissza):

```
~/flutter/bin/flutter test test/features/songs/probe_a8_strong_test.dart
→ 00:02 +0 -1: PROBE: filter survives a real dispose + re-enter [E]
  Expected: exactly one matching candidate
    Actual: _TextWidgetFinder:<Found 0 widgets with text "Alpha": []>
  A8 strong: the search text must survive a real re-enter
```

**Miért számít ez, és nem elméleti:** a `/song-trainer` **nincs** shell-branchben
(`app_router.dart:337`, top-level `GoRoute`), és az EGYETLEN alkalmazáson belüli
belépője egy `context.push`
(`lib/features/learn/screens/lesson_list_screen.dart:69`). A Library-ból
kilépve (`pop`) a képernyő dispose-olódik, az `Provider.autoDispose`
(`song_trainer_providers.dart:265`) elengedi a kontrollert, és a következő
belépés friss, szűretlen listát ad.

**Miért MINOR és nem MAJOR:** a cella által lefedett olvasat („a listáról
megnyitok egy dalt, majd visszalépek — a szűrő megmarad") a §6.1 hibás
implementációját („a szűrő visszatéréskor nullázódik") VALÓBAN pirosra fogja,
és ez a hétköznapi olvasat. A szigorúbb olvasatot a brief nem mondja ki
egyértelműen, ezért nem tekintem a mérce megsértésének — de mérve nem teljesül,
és a §10 handoff „A8 ZÖLD" sora enélkül a mérés nélkül többet állít a
valóságnál.

**Javasolt irány (a kör SAJÁT fájljaiban megoldható):** a lekérdezést a képernyő
autoDispose-életciklusán TÚL kell tartani — pl. egy nem-autoDispose
query-tartó a `song_library_screen.dart`-ban deklarálva, amit a képernyő
`initState`-ben visszatölt. A cellát egészítsd ki a dispose→újrabelépés
esetével (a fenti próba mintájára), hogy a jövőben gépi őre legyen.

### MINOR-2 — nyers gép-azonosító a felhasználónak, a lokalizált chip fölött

**Fájl:** `lib/features/song_trainer/presentation/widgets/song_summary_tile.dart:29`

```dart
Text(summary.artist ?? summary.sourceType.code),   // ← 'strumSightJson', 'legacyLocal', …
const SizedBox(height: 4),
SongSourceBadge(sourceType: summary.sourceType),   // ← 'StrumSight JSON' (lokalizált)
```

Előadó nélküli dalnál a sor a **fordítatlan enum-kódot** írja ki
(`strumSightJson`, `compressedMusicXml`), közvetlenül a MOST hozzáadott,
lokalizált forrás-chip fölé — tehát ugyanaz az információ kétszer, egyszer
gépi alakban. A `sourceType.code` doc-commentje maga mondja: *„Stable persisted
identifier"* — perzisztencia-azonosító, nem UI-szöveg. A fenti golden
(`e13_r23_song_library_compact.png`) mindkét sorban mutatja.

Ez a fájl a kör `allowed_paths`-án van, és a kör MOST nyúlt hozzá — egy
UI/UX-migrációs körben ez a sor nem maradhat így.

**Javasolt irány:** előadó hiányában ne a `code` legyen a fallback (üres
alcím-sor vagy a lokalizált forráscímke önmagában).

### MINOR-3 — az A2 „licenc a listában" része mérten nem teljesíthető → mondja ki a brief

**Mérés:** `SongSummary` (`song_repository.dart:136–151`) nem hordoz
`copyright`-ot; a licenc csak a teljes `SongDocument.metadata`-ból jön. A kör
ezért a licencet KIZÁRÓLAG az Overview-n mutatja, és ezt a §10 follow-upban
őszintén le is írja.

A brief A2-je viszont szó szerint azt kéri, hogy a forrás **és a
licenc-státusz** látszódjon **„a listában és az áttekintőben"**. A §0.0/B/R16
revízió a licenc PRODUCERÉT mérte ki, a MEGJELENÉSI HELYÉT nem szűkítette.

**Javasolt irány:** a §0.0/B-be egy rövid, mért revízió (R21), amely az A2-t a
tényleges adathoz szűkíti: **forrás mindkét helyen, licenc az áttekintőn**,
azzal a kimondott indokkal, hogy a lista-index bővítése az `application/`
rétegbe esik, ami ezen a körön kívül van. A mérce így nem gyengül, csak igazat
mond.

### NOTE-1 — `capability == null` ⇒ szerkeszthető

`song_library_screen.dart:106`: `summary.capability?.canPersist ?? true`. A
`SongSummary.capability` doc-commentje szerint friss telepítés első indulásán
`null`. Ilyenkor a sor a szerkesztőt nyitja. A megengedő default megegyezik a
kör előtti viselkedéssel, és a `capability` amúgy is „hint, never ground
truth" — ezért nem lelet, csak rögzített tény.

### NOTE-2 — dupla dokumentum-dekódolás, néma olvasási hiba

`song_overview_screen.dart:60–71`: a `_loadProvenance()` a
`songTrainerSetupControllerProvider` betöltésétől FÜGGETLENÜL még egyszer
beolvassa és dekódolja a teljes `SongDocument`-et, kizárólag a forrás/licenc
kiírásához, és `Failure` esetén némán nem tesz semmit. Mindkettő dokumentálva
van a kódban, és a mérvadó betöltési hibát a setup-kontroller külön felszínre
hozza. A tiszta megoldás (a setup-state kiegészítése) az `application/`
rétegbe esne, ami ezen a körön KÍVÜL van — ezért NOTE, nem lelet.

### NOTE-3 — perzisztált készenlét

`SetlistItemAvailabilityBadge` a `SongSetlistItem.initialAvailability` MENTETT
értékét rajzolja, nem a jelenlegi könyvtár ellen újraszámolt állapotot. A
mező neve (`initial…`) ezt vállalja is; az újraszámolás a domain/application
dolga, a köríven kívül.

---

## 3. Acceptance criteria — tételes ellenőrzés

| # | Kritérium | Bizonyíték | Reviewer-verdikt |
|---|---|---|---|
| A1 | helyi dal offline megnyitható | `song_asset_state_test.dart` „a fully local song…" — `InMemorySongRepository`, nulla hálózati provider | **TELJESÜL** (gate [4] zöld) |
| A2 | forrás + licenc látható a listában és az áttekintőben | `song_library_test.dart` „the source badge is visible…"; overview forrás+licenc sor | **RÉSZBEN** — forrás mindkét helyen ✔, licenc csak az áttekintőn → **MINOR-3** |
| A3 | csak olvasható forrás szerkesztése nem indítható | `song_library_test.dart` két cellája (read-only → overview; editable → editor) | **TELJESÜL** — az `AppRoutes.songTrainerEditor` EGYETLEN alkalmazáson belüli belépője a lista-sor (`grep -rn songTrainerEditor lib/`), és az ágazik |
| A4 | hiányzó kísérőhang mellett a többi tartalom elérhető | `song_asset_state_test.dart` + az implementer mutáció-próbája | **TELJESÜL** (gate [4] zöld) |
| A5 | setlist sorrend + tételenkénti készenlét | `setlist_list_test.dart` — pozíció-mérés (`x1 < x2 < x3`) + ikon/szín-ellenőrzés | **TELJESÜL** (gate [5] zöld) |
| A6 | hiányzó dal NEVESÍTVE | `setlist_list_test.dart` — `find.text('Song not found: song-gone')` | **TELJESÜL** — a nevesítés önálló, sortörő `Text`, nem az ikon belsejében |
| A7 | legacy songs/setlists route-ok működnek | `song_library_test.dart` `legacyRedirects` regresszió; `lib/app/routing/` NEM módosult | **TELJESÜL** (regressziós olvasat, §0.0/B/R18 szerint helyes) |
| A8 | keresés/szűrés megmarad visszatéréskor | `song_library_test.dart` push/pop cella | **RÉSZBEN** → **MINOR-1** |
| A9 | golden-felvétel mindhárom képernyőről, 2 keret | `e13_r23_screens_golden_test.dart` + 6 PNG | **TELJESÜL** — x86-on felvéve, valódi kapu |

---

## 4. Architektúra és termékhatárok (AGENTS.md §5–§6)

- **Rétegzés:** a presentation réteg a `domain/models` + `domain/repositories`
  típusait olvassa, írás sehol — `test/core/architecture_dependency_test.dart`
  (gate [9]) és `tool/check_architecture.dart` (gate [14]) is zöld.
- **Plugin-határ:** UI↛plugin megtartva (`preferences_plugin_import_guard`,
  `dio_factory_guard` — gate [11], [12] zöld).
- **Route-literálok:** `route_literal_guard` zöld (gate [13]); az új
  navigáció végig `AppRoutes.*` konstanst használ.
- **Erőforrás-életciklus:** a kör nem nyit mikrofont, hálózatot, wakelockot
  vagy stream-subscriptiont. Az egyetlen új aszinkron út
  (`_loadProvenance`) `mounted`-őrzött.
- **i18n:** minden új felhasználói szöveg ARB-n át, `base/app_{en,hu}.arb`
  FORRÁSBAN, az aggregátum generálva (gate [16] `l10n` zöld) — kézzel írt
  aggregátum nincs.

## 5. Kért javítások (javító kör)

1. **MINOR-1** — a Library szűrő-állapota éljen túl egy valódi dispose→újrabelépést,
   és az A8 cella kapjon erre gépi őrt.
2. **MINOR-2** — a `SongSummaryTile` alcíme ne írjon ki nyers `sourceType.code`-ot.
3. **MINOR-3** — §0.0/B/R21 revízió: az A2 licenc-része az áttekintőre szűkül, mért indoklással.

A goldenek a MINOR-2 után **újrafelvételt** igényelnek
(`tools/golden-x86.sh record` → `check`), a lista raszterizációja változik.

## 6. Javító kör utáni újraellenőrzés (`5ddbbbaf`)

**VÉGSŐ DÖNTÉS: APPROVED** — 0 BLOCKER, 0 MAJOR, 0 nyitott MINOR.

### 6.1 Gate — ÚJRA, friss izolált klónban

```
git clone --branch sonnet-impl/e13-r23-song-library-and-setlists … /tmp/review2-e13-r23
bash /tmp/review2-e13-r23/tools/prepare-flutter-generated.sh
tools/round-gate.sh <a §7 teljes útvonal-listája>
→ MINDEN GATE ZÖLD.  GATE_EXIT=0        (16/16: format, analyze, 11× test, architecture, secrets, l10n)
```

### 6.2 Scope-audit — ÚJRA

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r23 \
  --brief docs/rounds/e13-r23-song-library-and-setlists.md --base 76566726
→ Legacy scope audit OK (765667263191..5ddbbbafb3ac, 23 changed path(s), 1 generated/ignored)
```

Az `1 generated/ignored` a reviewer SAJÁT jelentése (`docs/reviews/e13-r23-review.md`) —
állandó, kód szintű mentesség, nem sértés.

### 6.3 Leletenkénti zárás — mindegyikhez tartozik gépi őr

| Lelet | Javítás | Ellenőrzés (a reviewer MÉRTE) | Állapot |
|---|---|---|---|
| MINOR-1 | `song_library_screen.dart`: file-szintű, **nem-autoDispose** `_songLibraryQueryProvider` tartja a lekérdezést; `initState` visszatölti (`TextEditingController` induló szöveg + `setQuery`), `_applyQuery` minden szűrő-változást elment | **(a)** az 1. körben PIROS reviewer-próba ugyanezen a fán ÚJRA lefuttatva → `00:02 +1: All tests passed!` **(b)** a kör ÚJ A8-cellája valódi-sértés próbával mérve: a providert `autoDispose`-ra mutálva `flutter test song_library_test.dart` → **`+5 -1`**, PONTOSAN az új cella pirosodik, a másik öt zöld marad; a mutáció visszaállítva | **ZÁRVA** |
| MINOR-2 | `song_summary_tile.dart`: az `artist ?? sourceType.code` fallback megszűnt; előadó hiányában az alcím-sor kimarad | a `song-summary-<id>` és `song-source-badge-<id>` Key-ek változatlanok (a négy R17-pin zöld); a lista-golden újrafelvéve x86-on, vizuálisan ellenőrizve: a nyers enum-kód sora eltűnt, a lokalizált chip maradt | **ZÁRVA** |
| MINOR-3 | §0.0/B/**R21** revízió + a §6 A2 sorának igazítása: forrás MINDKÉT helyen kötelező, licenc az áttekintőn | a revízió mért állítását ellenőriztem: `song_library_controller.dart:11–14` szó szerint *„A full document is deliberately never requested here"* — a szűkítés indoklása igaz, és az A2 első fele (forrás) nem gyengült | **ZÁRVA** |

A három NOTE (NOTE-1…NOTE-3) nem blokkol és szándékosan nyitva marad —
mindhárom feloldása az `application/` rétegbe esik, ami ezen a körön kívül van.

### 6.4 A mérce nem gyengült

- A régi, gyengébb A8-cella **változatlanul megmaradt** — a javítás HOZZÁADOTT
  egy erősebb cellát, nem cserélte le a gyengébbet.
- Egyetlen teszt-cella sem lett törölve, `skip`-elve vagy lazítva; a
  `test/ui/ui_inventory_test.dart` diffje **üres** (86).
- A négy R17-pin (`test/features/song_trainer/presentation/`,
  `test/app/routing/app_router_test.dart`) végig zöld és **szerkesztetlen**.
- Az eldobható reviewer-próbák (`probe_a8_strong_test.dart`, a provider-mutáció)
  a review lezárásakor **törölve**; a kör diffjében nincsenek benne.

### 6.5 Zöld kapu (ADR 0052) — exact-SHA

| Kapu | Run | SHA | Eredmény |
|---|---|---|---|
| Reviewer round-gate (lokális, izolált klón) | — | `5ddbbbaf` | **ZÖLD 16/16** |
| Router CI | `32965282494` | `5ddbbbaf` | **success** |
| Full Gate (no APK) | `32965280133` | `5ddbbbaf` | lásd a merge-jegyzetet |

`native_gate = false`, a CI-tervező (`tools/round-ci-plan.py`) `full-gate.yml`-t
írt elő — `build-apk.yml` szándékosan kimarad, a mérce-lánc azonos.
