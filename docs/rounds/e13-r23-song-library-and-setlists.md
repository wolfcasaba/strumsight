# E13-R23 — Song Library, Overview és Setlist lista UI

- **Státusz:** **READY** — pre-flight lefutva 2026-08-26 (`main @ 76566726`),
  §0.0/B nyolc mért revízióval
- **Típus:** Chapter 13 (UI/UX Design System), Kör 23
- **Kör-azonosító:** `E13-R23`
- **Branch:** `<motor>/e13-r23-song-library-and-setlists`
- **Előfeltétel:** `E13-R22` merge-elve (gyakorlási eredmények)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0275 (legacy route) és 0277 érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES dal-dokumentum
> modellt és repository-t, kiemelten a **forrás/licenc** mezőket — a §5.2
> jelölés csak a mért mezőkre írható meg. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  # §0.0/B/R13 — a brief eredeti három könyvtára (`lib/features/songs/library/`,
  # `lib/features/songs/overview/`, `lib/features/setlists/`) a fán NEM létezik,
  # és a három megnevezett felület MÁR LÉTEZIK a song_trainer presentation
  # rétegében. Az eredeti lista NULLA létező fájlt fedett. A csere a merge-elt
  # E03-R14…R22 briefek user-jóváhagyott literáljainak valódi RÉSZHALMAZA.
  "lib/features/song_trainer/presentation/screens/song_library_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_overview_screen.dart",
  "lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart",
  "lib/features/song_trainer/presentation/widgets/",
  "lib/features/song_trainer/public.dart",
  "lib/app/routing/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/songs/song_library_test.dart",
  "test/features/songs/song_asset_state_test.dart",
  "test/features/songs/setlist_list_test.dart",
  "test/app/navigation/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r23-song-library-and-setlists.md",
]
gate_tests = [
  "test/features/songs/song_library_test.dart",
  "test/features/songs/song_asset_state_test.dart",
  "test/features/songs/setlist_list_test.dart",
  "test/app/navigation/",
  # §0.0/B/R17 — a MEGLÉVŐ, listán KÍVÜLI pinek: futtatni KELL, szerkeszteni
  # TILOS (song_library_screen_test, song_overview_screen_test, a11y-audit;
  # és az app_router_test.dart:303 SongLibraryScreen-pinje).
  "test/features/song_trainer/presentation/",
  "test/app/routing/app_router_test.dart",
  # §0.0/B/R14 (ADR 0426) — a golden-sáv NEM a lokális ARM-gate-en fut:
  # `tools/golden-x86.sh check test/ui/goldens/e13_r23_screens_golden_test.dart`
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a dal-könyvtár és a setlistek felhasználó által létrehozott tartalmat tárolnak és törölnek.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/songs/library/`, `lib/features/songs/overview/`, `lib/features/setlists/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `setlists` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `songs` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek — a shell-destination őr FELVÉVE (H3 önjavító kör, ADR 0112, 2026-08-25)

> ⚠ **Ez a szakasz revideálva.** Az eredeti szöveg „nincs ilyen"-t állított. A
> sáv-szintű mérés szerint ez **hamis** minden olyan Ch13 körre, amelyik a
> routert is engedi — ez a kör ilyen (`lib/app/routing/` az `allowed_paths`-on).

Az E13-R08 óta a `test/app/navigation/` **három** őre route-onként PINNELI,
melyik képernyő-TÍPUS renderelődik: az öt destination
(`adaptive_scaffold_test.dart:196–216`), a tizenegy alútvonal-adapter (`:223–235`),
a tab-visszaállítás (`tab_state_restoration_test.dart`) és a tizenegy legacy
redirect célja (`legacy_route_redirect_test.dart:156–166`). Ez a kör a **Songs
terület** destinationjét és alútvonalát migrálja, amiket ma a
`SongListScreen`, illetve a `SetlistListScreen` típus pinnel — a
destination-builder átkötése tehát pirosra váltja őket.

MÉRT precedens ugyanezen az őrön (E13-R17, izolált klón `main @ 52df92b3`):
`flutter test test/app/navigation/` a bázison `+33 All tests passed`, három
destination-builder átkötése után `+30 -3`. Az őr felvétele az orchestrátornak
tágítás lenne, azaz H3 ([L478](../LESSONS.md)) — ezért kerül a listára MOST.

**A jogosultság PONTOSAN a lecserélt adapter TÍPUSÁNAK átírása** a ténylegesen
érintett cellákban. Minden más állítás — primary navigation megléte, a többi
adapter, a tab-visszaállítás mechanikája, a redirect-aciklikusság — érintetlen
marad; cella törlése, `skip`-je vagy gyengítése **TILOS**. A kör saját
pre-flightja mérje ki (`tools/round-gate.sh test/features/songs/song_library_test.dart test/features/songs/song_asset_state_test.dart test/features/songs/setlist_list_test.dart test/app/navigation/ test/ui/goldens/e13_r23_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart`), PONTOSAN
melyik cellák pirosodnak — a lista tágítása nélkül, mert az őr már rajta van.

Ami továbbra is a listán KÍVÜL van (`test/core/**`, más feature-ek fái): ha egy
elbukik, az `blocked` jelzés és célzott brief-revízió, nem csendes átírás.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/setlists/`, `lib/features/songs/library/`, `lib/features/songs/overview/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0.0/B BRIEF-REVÍZIÓ — 2026-08-26, a kör SAJÁT pre-flightja (`main @ 76566726`)

A `brief-lint` (strict) 0 leletet adott, a hagyaték-mérés `ÁLLAPOT: NINCS`.
Az alábbi nyolc revízió a fán MÉRT, nem feltételezett. **Visszakeresett
előzmény** (`tools/knowledge-rag.mjs`, szűkített → teljes korpusz):
[L478](../LESSONS.md#l478) (a pre-flight csak SZŰKÍTHET; a tágítás H3),
[L486](../LESSONS.md#l486) + [L493](../LESSONS.md#l493) +
[ADR 0426](../adr/0426-golden-rasterization-on-the-merge-gate-architecture.md)
(a golden-raszterizáció csak a merge-kapu ISA-ján mérhető), az E13-R20/H5
halt-jelzés, és a KÖZVETLENÜL előző, merge-elt kör azonos hibaosztályú
feloldása (E13-R22 §0.0/B/R6–R11, `5f4266e3`).

### R13 — a három megnevezett könyvtár NEM létezik; a három felület MÁR LÉTEZIK máshol

```
ls -d lib/features/songs/library lib/features/songs/overview lib/features/setlists
→ (mind a három: nincs ilyen fájl vagy könyvtár)

ls lib/features/song_trainer/presentation/screens/
→ song_library_screen.dart      ← a §3 „dal-könyvtár"
  song_overview_screen.dart     ← a §3 „dal áttekintő nézete"
  setlist_list_screen_v2.dart   ← a §3 „setlist-lista"
  + song_editor/import/import_preview/result/trainer/setup/setlist_session
```

A §0.0/R1 azt állította, hogy „a képernyőket ez a kör hozza létre" — ez
**mérve hamis**: mind a három felület létezik, kettő közülük route-on
regisztrált (`app_router.dart:338` → `SongLibraryScreen`, `:356` →
`SongOverviewScreen`). Az eredeti lista így **nulla létező fájlt** fedett: a
körnek egyetlen olyan engedélyezett fájlja sem lett volna, amin a §1 szerinti
**migráció** elvégezhető.

**Feloldás — útvonal-csere, NEM új jogosultság-osztály.** A csere a merge-elt
E03-R14…R22 briefek user-jóváhagyott `allowed_paths` literáljainak **valódi
részhalmaza** (a három screen-fájl és a `presentation/widgets/` mind ott
szerepel tételesen). A kör tehát **kevesebbet** kap, mint a szomszédai:

| E03-R15/R16/R17/R21 (merge-elt) | E13-R23 (ez a kör) |
|---|---|
| a `presentation/screens/` mind a 10 fájlja | ebből **3** (library, overview, setlist-lista) |
| `presentation/widgets/` (tételesen mind) | `presentation/widgets/` |
| `application/`, `domain/`, `data/` fák is | **egyik sem** — csak OLVASHATÓ |

Az `application/`, `domain/` és `data/` réteg a kör számára **olvasható, de
NEM írható** — a §3 „a dal-dokumentum séma módosítása tilos" tiltása így
gépi is: a scope-audit a listán kívüli írást `VIOLATION`-nel jelzi.

### R14 — a golden-sáv a MERGE-KAPU architektúráján fut (ADR 0426)

A §7 eredeti sora (`~/flutter/bin/flutter test --update-goldens`) **ARM-pixelt**
rögzítene, amit az x86-os CI nulla toleranciával pirosra vált — pontosan ez
állította meg az E13-R20-at **H5**-tel ([L493](../LESSONS.md#l493)). A kör a
merge-elt `tools/golden-x86.sh`-t használja (`record`, majd kötelező `check`),
és a golden-cella **nincs** a lokális `round-gate.sh` sorban:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r23_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r23_screens_golden_test.dart
```

Az A9 mércéje **változatlan**: ugyanaz a nulla toleranciájú komparátor, két
keret (412×915 compact portrait ÉS `textScaleFactor: 2.0`), 0 törölt/skippelt
cella, a PNG-k commitolva. Csak a mérés HELYE került a felvétel mellé.

### R15 — a kör ADR-t NEM ír (H1 volna)

```
ls docs/adr | grep -E '^027[5-8]|^0426'
→ 0275-five-area-shell-behind-a-flag.md
  0277-failure-presentation-model.md
  0278-ai-provenance-is-visible.md
```

A §5 mind az öt kötött döntése MÁR merge-elt ADR-re támaszkodik (0275 legacy
route, 0277 hibabemutatás, 0278 provenance-elv), és a §3 tilos zónája
kimondottan tartalmazza a `docs/adr/**`-ot. Új ADR-szám kiosztása merge-elt
döntés fölé az ADR 0087 §4 szerint tilos, egy meglévő módosítása **H1**.
A pipeline „előre kiosztott ADR: nincs" mezője tehát a mérés szerint helyes:
**nem foglalunk ADR-számot**, ADR-fájl nem születik. (Azonos feloldás, mint
E13-R21 és E13-R22 §0.0/B/R5.)

### R16 — a §5.2 „forrás/licenc" a MÉRT mezőkre szűkül: nincs licenc-mező és nincs „közösségi" forrás

A brief pre-flight-figyelmeztetése ezt kifejezetten kérte. A mérés:

```
grep -n 'license\|License' lib/features/song_trainer/domain/models/*.dart → (üres)
grep -rn 'readOnly\|isEditable\|canEdit\|community' lib/features/song_trainer/domain/models/ → (üres)

enum SongSourceType (song_source.dart:45): legacyLocal, createdInApp,
  strumSightJson, musicXml, compressedMusicXml, midi, guitarPro
SongSummary (song_repository.dart:136): …, capability, sourceType, favorite,
  archived, revision, documentHash, trashed
SongCapabilitySummary (:77): canPersist, canTrain, canExport, chordScoring,
  pitchScoring, lastValidatedAt
SongMetadata: copyright (opcionális szabad szöveg)
```

**Nincs `license` mező és nincs `community` forrástípus.** A §5.2 jelölés
ezért PONTOSAN erre a három mért forrásra írható meg, és semmi másra:

| A §5.2 fogalma | A MÉRT producer |
|---|---|
| „saját importja / beépített" | `SongSummary.sourceType` (`SongSourceType`, 7 stabil kód) |
| „licenc" | `SongMetadata.copyright` — ha `null`, a felület **nem állít** licencet |
| „szerkesztheti-e" | `SongSummary.capability.canPersist` (`false` ⇒ a mentés zárva) |

**A „közösségi" forrás kimarad**, mert nincs mögötte adat — kitalált címke a
provenance MEGHAMISÍTÁSA lenne, azaz pontosan az ADR 0278 elvének megsértése.
Az A2/A3 cella ennek megfelelően a mért mezőkre mér; a §6.1 „A csak olvasható
dal szerkeszthető" hibás implementációt a `canPersist == false` melletti
elérhető szerkesztő-belépő fogja pirosra.

### R17 — a §0.0/R2 „nincs ilyen" MÉRVE HAMIS: négy meglévő pin

```
grep -rln 'SongLibraryScreen\|SongOverviewScreen\|SetlistListScreenV2' test/
→ test/features/song_trainer/presentation/song_library_screen_test.dart
  test/features/song_trainer/presentation/song_overview_screen_test.dart
  test/app/routing/app_router_test.dart            (:303 findsOneWidget)
  test/features/song_trainer/application/setlists/setlist_session_controller_test.dart
```

**A feloldás [L488](../LESSONS.md#l488) szerint NEM a lista tágítása, hanem a
típus HELYBEN tartása.** A kör kötelezettségei:

1. a `SongLibraryScreen`, a `SongOverviewScreen` és a `SetlistListScreenV2`
   **típusneve, fájl-útvonala és konstruktor-szignatúrája változatlan** marad
   (`SongOverviewScreen({required String songId})`,
   `SetlistListScreenV2({required SetlistController controller, required
   DateTime Function() clock})`), és az `app_router.dart:338/356`
   route-regisztrációk sem mozdulnak — a képernyők HELYBEN migrálnak, nem új
   fájlba költöznek;
2. mind a négy pin **zöld marad** — a migráció HOZZÁAD (forrás/licenc jelölés,
   eszköz-készenlét, offline-állapot, setlist-készenlét), nem vesz el:
   meglévő `Key`, `Semantics` címke, szöveg-finder vagy belépő **nem
   törölhető és nem nevezhető át**;
3. a négy teszt a `gate_tests`-ben **fut**, de az `allowed_paths`-on **nincs
   rajta**: a kör futtatja, szerkeszteni nem tudja (az S12-vel azonos minta).
   Ha valamelyik pirosra vált, az **`blocked`** jelzés és célzott
   brief-revízió, nem csendes átírás.

**Ez a bekezdés az `S11` brief-lint lelet KIMONDOTT válasza.** A szabály két
kifutót ad; a kör a MÁSODIKAT választja — a szabály saját szövege szerint:
*„Ha a kör a képernyőt bizonyíthatóan nem cseréli le, a §0.0 mondja ki ezt a
mérést."* A kör a képernyőt **nem cseréli le** (fent, 1. pont), tehát a négy
pin nem a migráció áldozata, hanem a migráció **mércéje**. A tesztek felvétele
az `allowed_paths`-ra tágítás volna, ami az orchestrátornak **H3**
([L478](../LESSONS.md#l478)) — ezért nem történik meg. Azonos kifutó, mint
E13-R22 §0.0/B/R7 (`5f4266e3`, merge-elve).

**Az S11-lelet a pre-flight ELŐTT nem létezett** (`.pipeline/brief-lint-E13-R23.md`
→ „nincs lelet"): az eredeti lista nulla létező fájlt fedett, tehát nem is
tudott meglévő képernyőt érinteni. A lelet az R13 útvonal-cserével jelent meg,
és ezzel a kifutóval zárul.

### R18 — a §0.0/R3 shell-destination premisszája IGAZ, de ez a kör NEM köti át

```
adaptive_scaffold_test.dart:210  → find.byType(SongListScreen)      (legacy)
adaptive_scaffold_test.dart:236  → AppRoutes.songsSetlists: SetlistListScreen
app_router.dart:471/475          → SongListScreen / SetlistListScreen
```

A shell Songs-destinationje ma a **legacy** `lib/features/songs/screens/`
képernyőket rendereli (a `Song`/`Setlist` modellre, aminek nincs
`SongSource`-a, nincs assetje, nincs capabilityje — a §5.2/§5.3 rajta
**elvileg** sem teljesíthető). A migráció célja ezért a song_trainer V2
felület, a shell-destination átkötése pedig **nem** ennek a körnek a dolga:
a legacy képernyők a listán KÍVÜL vannak, az átkötés a `test/app/navigation/`
három őrét pirosra váltaná, és egy fél-migrált Songs-terület maradna.

A `test/app/navigation/` és a `lib/app/routing/` az eredeti listán MARAD (a
szűkítés nem kötelező), de a jogosultság szűk: **kizárólag** az A7
alias/redirect bejegyzés és a hozzá tartozó cella, ha a kör egyáltalán
igényel ilyet. A destination-builder átkötése, cella törlése vagy `skip`-je
**TILOS**.

### R19 — a képernyő-leltár egzakt száma 86, és ez a kör NEM mozdítja el

```
find lib/features -name '*_screen.dart' | wc -l   → 86
test/ui/ui_inventory_test.dart:14                 → hasLength(86)
```

A migráció **helyben** történik (R13), tehát új `*_screen.dart` nem születik
és a szám nem mozdul. A fájl a listán MARAD (a §0.0/R4 jogosultsága
változatlan: **PONTOSAN a szám emelése a TÉNYLEGES értékre**), de a várt diff
**üres**. Kerülőút (képernyő-átnevezés, a `tool/ui_inventory.dart` szabályának
lazítása) TILOS.

### R20 — az A5/A6/§6.1 három cellájának MÉRT producere: `SetlistItemAvailability`

```
song_setlist.dart:12  enum SetlistItemAvailability {
  ready, missingSong, missingAsset, unsupportedTrack,
  requiresMigration, invalidConfig }
song_setlist.dart:87  SongSetlistItem.initialAvailability
song_asset_repository.dart:47   'songAssetRepository.missingAsset'
backing_audio_player.dart:8     'backingAudioPlayer.missingAsset'
```

A §6.1 eszköz-készenléti hármas leképezése tehát nem tetszőleges:

| §6.1 cella | A MÉRT bemenet |
|---|---|
| a küszöb alatt | `SetlistItemAvailability.ready` |
| rajta (a küszöbön) | `SetlistItemAvailability.missingAsset` — a dal **megnyitható**, csak a lejátszás jelöli a hiányt |
| a küszöb fölött | `SetlistItemAvailability.missingSong` — a tétel **nevesítve**, hibásként |

**Mért szerkezeti korlát:** a `SetlistListScreenV2` **nincs** GoRoute-on
regisztrálva, és a konstruktora kötelező `controller` + `clock` argumentumot
kér (`setlist_list_screen_v2.dart:9–18`). Az A5/A6 cellái ezért a widgetet
**közvetlenül** példányosítják (`SetlistController` teszt-dublőrrel), nem
route-navigációval. A route-regisztráció egy KÉSŐBBI kör dolga (E13-R25 §3
setlist-run) — ezt a §10 handoffban nevesítsd.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-24–UI-25 és UI-32 Songs-tartalmak migrációja **offline készenlét** és
**forrás/licenc** jelöléssel (SDD Ch13 Kör 23).

## 2. Jelenlegi állapot — mért tények

- Az R08 shellje és az R12 kártyái készen állnak; a Songs terület
  a shell egyik cél-destinationje.
- Az R10 ADR 0277: az offline nem hiba, a cached tartalom látható marad.
- ~~A dalok egy része **közösségi / csak olvasható** forrásból származhat.~~
  **MÉRVE HAMIS (§0.0/B/R16):** nincs `community` forrástípus és nincs
  licenc-mező. A provenance a `SongSummary.sourceType` (7 kód), a licenc a
  `SongMetadata.copyright` (opcionális), a „szerkeszthető-e" a
  `capability.canPersist`.

## 3. Scope

**Benne van:** a dal-könyvtár folytatás / keresés / szűrés / forrás / készenlét
komponensekkel · a dal áttekintő nézete (szakaszok, haladás, hangolás, eszközök,
elsődleges gyakorlás-akció) · a setlist-lista készenléti és **hiányzó dal**
állapotokkal · compact lista és expanded lista-részlet elrendezés · közösségi /
csak olvasható forrás, hiányzó offline eszköz, elérhető frissítés állapotok ·
route-alias teszt a meglévő útvonalakról.

**NINCS benne (tilos):** a dal-import vagy a szerkesztő (Kör 24) · a tréner
(Kör 25) · a dal-dokumentum séma módosítása · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

> ⚠ A táblázat a §0.0/B/R13 útvonal-cseréje UTÁNI állapotot mutatja; a
> normatív forrás az `ai-router` blokk `allowed_paths` listája.

| Útvonal | Indok |
|---|---|
| `song_trainer/presentation/screens/song_library_screen.dart` | a könyvtár UI-ja |
| `song_trainer/presentation/screens/song_overview_screen.dart` | a dal áttekintő nézete |
| `song_trainer/presentation/screens/setlist_list_screen_v2.dart` | a setlist-lista |
| `song_trainer/presentation/widgets/` | a fenti három felület komponensei |
| `song_trainer/public.dart` | a barrel, ha új komponens exportot igényel |
| `lib/app/routing/` | **kizárólag** az A7 alias/redirect bejegyzés (§0.0/B/R18) |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a dal-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/songs/*_test.dart` (3) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r23-…md` | a §10 handoff |

**Tilos zóna:** a song_trainer `application/`, `domain/`, `data/` fája
(OLVASHATÓ, nem írható) · a legacy `lib/features/songs/` fa · a
`presentation/screens/` másik hét képernyője (editor, import, import_preview,
result, trainer, setup, setlist_session) ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A helyi dal OFFLINE elérhető

A készüléken tárolt dal hálózat nélkül is megnyitható és gyakorolható. Az
offline állapot nem tesz semmit elérhetetlenné, ami helyben megvan.

### 5.2 A forrás és a licenc-státusz LÁTHATÓ

A felhasználónak tudnia kell, milyen forrásból származik a dal, és hogy
szerkesztheti-e. Ez az ADR 0278 provenance-elvének tartalmi megfelelője.

**A §0.0/B/R16 szerint MÉRT alak:** a forrás a `SongSummary.sourceType`
(`SongSourceType` 7 stabil kódja) alapján jelenik meg, a licenc a
`SongMetadata.copyright` alapján — ha `null`, a felület **nem állít**
licencet —, a szerkeszthetőség pedig a `capability.canPersist` alapján.
Kitalált „közösségi" címke **TILOS**: nincs mögötte adat, tehát az ADR 0278
provenance-elvét sértené meg.

**NEM elfogadható gyengítés:** a forrás elrejtése „egységes lista-megjelenés"
kedvéért. A csak olvasható tartalom szerkesztési kísérlete így csak a hibánál
derülne ki.

### 5.3 A hiányzó kísérőhang NEM rejti el a többi tartalmat

Ha a backing track nincs letöltve, a dal szövege, akkordjai és szakaszai
továbbra is elérhetők. Csak az érintett funkció jelöli a hiányt.

**NEM elfogadható gyengítés:** a teljes dal letiltása hiányzó eszköz miatt.
A tartalom nagy része hangfájl nélkül is használható.

### 5.4 A setlist SORRENDJE és készenléte pontos

A sorrend a felhasználóé; a készenlét minden tételre külön látszik, a hiányzó
dal pedig **nevesítve** jelenik meg, nem néma kihagyással.

### 5.5 A legacy route MŰKÖDIK

Az ADR 0275 §3 alkalmazása a Songs területre.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A helyi dal offline megnyitható | `song_asset_state_test.dart` |
| A2 | A forrás és a licenc-státusz látható a listában és az áttekintőben | `song_library_test.dart` |
| A3 | A csak olvasható forrás szerkesztése nem indítható | ugyanott |
| A4 | Hiányzó kísérőhang mellett a többi tartalom elérhető | `song_asset_state_test.dart` |
| A5 | A setlist sorrendje és tételenkénti készenléte helyes | `setlist_list_test.dart` |
| A6 | A hiányzó dal nevesítve jelenik meg a setlistben | ugyanott |
| A7 | A legacy songs/setlists route-ok működnek | `song_library_test.dart` |
| A8 | A keresés és a szűrés állapota megmarad visszatéréskor | ugyanott |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r23_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A forrás nem jelenik meg a listában | **A2** |
| A csak olvasható dal szerkeszthető | **A3** |
| Hiányzó backing track → a dal letiltva | **A4** |
| A hiányzó setlist-tétel némán kimarad | **A6** |
| A legacy route törölve | A7 |
| A szűrő visszatéréskor nullázódik | A8 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**Az eszköz-készenlét három kötelező cellája** (a küszöb: mely eszköz hiányzik):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | minden eszköz megvan | teljes funkcionalitás |
| rajta (a küszöbön) | **a kísérőhang hiányzik**, a dokumentum megvan | a dal **megnyitható**, csak a lejátszás jelöli a hiányt |
| a küszöb fölött | maga a dal-dokumentum hiányzik | a tétel hibásként, **nevesítve** jelenik meg |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tiltsd le a dalt
hiányzó kísérőhang esetén → az **A4** cellának PIROSNAK kell lennie → állítsd
vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/songs/song_library_test.dart test/features/songs/song_asset_state_test.dart test/features/songs/setlist_list_test.dart test/app/navigation/ test/features/song_trainer/presentation/ test/app/routing/app_router_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás — **a merge-kapu
architektúráján** (§0.0/B/R14, ADR 0426); a `--update-goldens` ezen a boxon
ARM-pixelt rögzítene, amit az x86-os CI pirosra vált:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r23_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r23_screens_golden_test.dart
```

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. A könyvtár lista + keresés/szűrés/folytatás, állapotmegőrzéssel.
2. A forrás/licenc jelölés és a csak olvasható zárolás.
3. Az eszköz-készenlét három cellája.
4. A dal áttekintő nézete + elsődleges gyakorlás-akció.
5. A setlist-lista sorrenddel, készenléttel, nevesített hiánnyal.
6. A legacy route-aliasok + a hozzájuk tartozó cella.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A hiányzó eszköz miatti teljes letiltás.** Egyszerű szabály, és
  használhatatlanná tesz egy amúgy teljes dalt (A4).
- **A rejtett forrás.** A szerkesztési kísérlet csak hibánál derül ki, ami a
  felhasználó munkáját viszi (A2/A3).
- **A néma setlist-kihagyás.** Fellépés közben a legrosszabb: a felhasználó nem
  tudja, mi maradt ki (A6).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** Claude Sonnet 5 (`sonnet-impl`). **Kör-fa állapota `main @ 76566726`
felett, a §0.0/B pre-flight nyolc revíziójából (R13–R20) dolgozva.**

### Mit épített a kör

A három megnevezett felület **helyben** migrált (R13/R17: típusnév,
fájl-útvonal, konstruktor-szignatúra és route-regisztráció változatlan):

- **`SongLibraryScreen`** — minden sor forrás-jelvényt kap
  (`SongSourceBadge`, új `presentation/widgets/song_source_badge.dart`,
  megosztva az Overview-val); a `SongCapabilityBadges` egy negyedik jelvénnyel
  bővült (`canPersist == false` → lakat-ikon + `songLibraryReadOnly`
  Semantics-címke). A sor tap-viselkedése a `capability?.canPersist ?? true`
  alapján ágazik: szerkeszthető dal → editor (változatlan), csak olvasható dal
  → Overview (megtekintő mód) + `songLibraryReadOnlySnackBar` — a
  `song-editor-open-<id>` Key VÁLTOZATLAN, csak a cél mozdult (R17 kötelezése).
- **`SongOverviewScreen`** — a `SongTrainerSetupState` NEM hordoz
  forrást/licencet (mért, R16), ezért a képernyő egy SAJÁT, egyszeri
  `songRepositoryProvider.get(_songId)` hívással tölti be a teljes
  dokumentumot csak a forrás/licenc megjelenítéséhez
  (`_SongOverviewScreenState._loadProvenance`), a meglévő
  `SongTrainerSetupController` folyamatát érintetlenül hagyva. Az új tartalom
  (forrás/licenc sor, hiányzó-kísérőhang jelzés) a MEGLÉVŐ tartalom (cím,
  szakaszok, sávok, képességek, Start gomb) UTÁN kerül a `ListView`-ba —
  enélkül a négy pin egyike (`song_overview_screen_test.dart`) az alap
  (800×600) teszt-ablakban pirosra váltott volna, mert a `find.byKey`
  alapból `skipOffstage:true`, és a plusz tartalom a gombot a scrollozatlan
  nézeten kívülre tolta volna (mérve, majd javítva — lásd alább).
- **`SetlistListScreenV2`** — új `SetlistItemAvailabilityBadge` widget
  (`presentation/widgets/setlist_item_availability_badge.dart`), kizárólag
  ikon (lásd alul, miért), a `SetlistItemAvailability` → `ready` /
  `missingAsset` / `missingSong` / egyéb leképezéssel (R20 mért mátrix). A
  kompakt lista minden setlist-kártyáján egy `Wrap` mutatja tételenként a
  jelvényt; a hiányzó dal NEVESÍTVE, külön látható szövegsorként jelenik meg
  (`setlistV2ItemMissingSong({songId})`), nem az ikon-jelvény belsejében. Az
  editor-sheet (expanded nézet) minden tétel `leading` szerepében ugyanezt a
  jelvényt mutatja; a tétel `title`-ja már eddig is a songId-t írta ki, ez
  változatlan maradt.

### Miért ikon-only a `SetlistItemAvailabilityBadge`

Első implementáció Row+Text-et rakott a `missingSong` ágba. A helyi golden
smoke-futás (`flutter test --update-goldens`, csak ellenőrzésre, nem
commitolva) egy VALÓDI `RenderFlex overflowed` hibát mért: a jelvény két
KORLÁTOZOTT-szélességű helyen él — a kompakt kártya `Wrap`-jában (a `ListTile`
subtitle-oszlopa szűkíti) és az editor-sheet `ListTile.leading` sávjában
(fix, keskeny terület). A jelvény ezért MINDIG csak ikon; a nevesítés
(A6) a hívó oldalon, önálló, sortörő `Text` widgetként történik.

### Acceptance-mátrix — melyik teszt bizonyítja melyik cellát

| # | Bizonyíték | Eredmény |
|---|---|---|
| A1 | `song_asset_state_test.dart`: „a fully local song … opens … offline" | ZÖLD — `InMemorySongRepository`, nulla hálózati provider |
| A2 | `song_library_test.dart`: „the source badge is visible…"; `song_asset_state_test.dart` overview-fixture forrás+licenc sora | ZÖLD |
| A3 | `song_library_test.dart`: „tapping a read-only … opens view mode, not the editor" + „an editable … still opens the editor" | ZÖLD |
| A4 | `song_asset_state_test.dart`: „a missing backing asset flags playback only…" | ZÖLD (+ mutáció, lásd lent) |
| A5 | `setlist_list_test.dart`: „setlist order and per-item readiness…" | ZÖLD |
| A6 | `setlist_list_test.dart`: „a missing song is named…" | ZÖLD |
| A7 | `song_library_test.dart`: „legacy /setlists still redirects…" (unit-szintű regresszió `legacyRedirects` ellen — a `lib/app/routing/` fa NEM módosult, R18 szerint erre nem is volt szükség) | ZÖLD |
| A8 | `song_library_test.dart`: „search text and source filter persist after pushing and returning…" | ZÖLD |
| A9 | `test/ui/goldens/e13_r23_screens_golden_test.dart` + 6 PNG a diffben | ZÖLD (lásd lent) |

### Valódi-sértés próba (KÖTELEZŐ, §6.1/A4)

A `song_overview_screen.dart`-ban ideiglenesen az `SongTrainerSetupStatus.ready
when state.hasMissingBackingAsset` ágat egy teljes-dal-letiltásra cseréltem
(`Center(child: Text('blocked: missing backing asset'))`), majd lefuttattam
`flutter test test/features/songs/song_asset_state_test.dart`-ot:

- **Mért kimenet:** az **A4** cella („a missing backing asset flags playback
  only — the rest of the song stays usable") PIROSRA váltott —
  `find.byKey(const Key('song-overview-missing-backing'))` `findsOneWidget`
  helyett `Found 0 widgets` (a teljes törzs a letiltó `Text`-re cserélődött,
  a jelző eltűnt) —, az A1 cella zöld maradt (nincs hiányzó eszköz abban a
  fixtúrában).
- A mutációt visszaállítottam; `git diff` a fájlon üres, a
  `song_asset_state_test.dart` mindkét tesztje újra ZÖLD.

### Golden-felvétel (A9)

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r23_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r23_screens_golden_test.dart
```

Mindkettő 0 kilépési kóddal, 6/6 teszt zöld (`song library`, `song overview`,
`setlist list v2` × {`compact`, `compact_scale2`}). A hat PNG
(`test/ui/goldens/goldens/e13_r23_*.png`) commitolva. A lokális ARM
`--update-goldens` futás csak a Row-overflow felderítésére szolgált — a
generált PNG-k törölve lettek, mielőtt az x86 `record` felvette a véglegeset
(ADR 0426, §0.0/B/R14).

### A záró kapu

```
tools/round-gate.sh test/features/songs/song_library_test.dart test/features/songs/song_asset_state_test.dart test/features/songs/setlist_list_test.dart test/app/navigation/ test/features/song_trainer/presentation/ test/app/routing/app_router_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

Mind a 16 lépés (`format`, `analyze`, 11× `test`, `architecture`, `secrets`,
`l10n`) ZÖLD. A négy R17-pin (`song_library_screen_test.dart`,
`song_overview_screen_test.dart`, `song_trainer_accessibility_test.dart`,
`app_router_test.dart:303`) zöld maradt — egyik `Key`/`Semantics`/szöveg-finder
sem mozdult. A `test/ui/ui_inventory_test.dart` diffje ÜRES (86, R19 szerint).

### Nevesített follow-up

- **`SetlistListScreenV2` route-regisztrációja** — a képernyő ma nincs
  GoRoute-on (R20 mért szerkezeti korlát); a route-bekötés és az A5/A6
  éles navigációs próbája a **E13-R25** (setlist-run) kör dolga.
- A Library lista licenc-oszlopa: a `SongSummary` indexe nem hordoz
  `copyright`-ot, ezért a lista csak forrást mutat, a licenc kizárólag az
  Overview-n jelenik meg (a teljes dokumentum egyszeri betöltése után). Ha egy
  jövőbeli kör a listában is licencet akar mutatni, az a `SongSummary` index
  bővítését igényli (application/domain réteg — ezen a körön kívül esik).

## 11. Review — a Claude tölti ki
