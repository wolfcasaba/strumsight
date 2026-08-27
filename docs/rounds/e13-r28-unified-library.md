# E13-R28 — Unified Library és Session Detail UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ c732ec75`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 28
- **Kör-azonosító:** `E13-R28`
- **Branch:** `<motor>/e13-r28-unified-library`
- **Előfeltétel:** `E13-R27` merge-elve (elemzési eredmények)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0279 (megerősítés) és 0283 érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel a TÉNYLEGES tárolási és
> szinkron-állapot típusokat, valamint azt, hogy a törlés melyik use case-ben
> él — a §5.4 kimondja, hogy a felület csak belépési pont. Eltérésnél §0.0
> revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/library_v2/",
  "lib/features/song_trainer/public.dart",
  "lib/app/routing/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/library_v2/item_routing_test.dart",
  "test/features/library_v2/corrupt_item_test.dart",
  "test/features/library_v2/delete_confirmation_test.dart",
  "test/features/library_v2/sync_conflict_test.dart",
  "test/app/navigation/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r28-unified-library.md",
]
gate_tests = [
  "test/features/library_v2/item_routing_test.dart",
  "test/features/library_v2/corrupt_item_test.dart",
  "test/features/library_v2/delete_confirmation_test.dart",
  "test/features/library_v2/sync_conflict_test.dart",
  "test/app/navigation/",
  "test/ui/goldens/e13_r28_screens_golden_test.dart",
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

**Kockázat = high, indoklás:** az egységes könyvtár a felhasználó ÖSSZES tartalmát egy felületen listázza és törölhetővé teszi.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/library_v2/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `library_v2` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

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
redirect célja (`legacy_route_redirect_test.dart:156–166`). Ez a kör a
`/profile/library` alútvonalat migrálja `lib/features/library_v2/`-re, amit ma
a `LibraryScreen` típus pinnel — **két** helyen is: az alútvonal-adapter
térképen és az `AppRoutes.library` legacy redirect célján.

MÉRT precedens ugyanezen az őrön (E13-R17, izolált klón `main @ 52df92b3`):
`flutter test test/app/navigation/` a bázison `+33 All tests passed`, három
destination-builder átkötése után `+30 -3`. Az őr felvétele az orchestrátornak
tágítás lenne, azaz H3 ([L478](../LESSONS.md)) — ezért kerül a listára MOST.

**A jogosultság PONTOSAN a lecserélt adapter TÍPUSÁNAK átírása** a ténylegesen
érintett cellákban. Minden más állítás — primary navigation megléte, a többi
adapter, a query/fragment megőrzése a redirectben, a redirect-aciklikusság —
érintetlen marad; cella törlése, `skip`-je vagy gyengítése **TILOS**. A kör
saját pre-flightja mérje ki (`tools/round-gate.sh test/features/library_v2/item_routing_test.dart test/features/library_v2/corrupt_item_test.dart test/features/library_v2/delete_confirmation_test.dart test/features/library_v2/sync_conflict_test.dart test/app/navigation/ test/ui/goldens/e13_r28_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart`),
PONTOSAN melyik cellák pirosodnak — a lista tágítása nélkül, mert az őr már
rajta van.

Ami továbbra is a listán KÍVÜL van (`test/core/**`, más feature-ek fái): ha egy
elbukik, az `blocked` jelzés és célzott brief-revízió, nem csendes átírás.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/library_v2/` könyvtár-előtag
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

### R5 — a `song_trainer` publikus barrel bővítése (H3 önjavító kör, ADR 0112, 2026-08-27)

A kör **kész**, a kapu 12-ből 11 lépésen zöld volt, és a
`test/core/architecture_dependency_test.dart` PONTOSAN három sértéssel állt meg.
Reprodukálva az önjavító körben, a kör saját munkapéldányán
(`/home/ubuntu/ss-sonnet-impl-e13-r28`, HEAD `090990f2`,
`dart run tool/check_architecture.dart`):

```
- lib/features/library_v2/data/setlist_item_source.dart -> lib/features/song_trainer/domain/repositories/setlist_repository.dart [cross-feature imports must target public.dart]
- lib/features/library_v2/data/song_item_source.dart -> lib/features/song_trainer/domain/repositories/song_repository.dart [cross-feature imports must target public.dart]
- lib/features/library_v2/providers/library_v2_providers.dart -> lib/features/song_trainer/application/song_trainer_providers.dart [cross-feature imports must target public.dart]
```

**Ez nem implementer-hiba, hanem a lista hiánya.** A §3 scope kimondja, hogy az
egységes könyvtár a **dal** és a **setlist** tételtípust is listázza; ehhez a
`SongRepository` / `SetlistRepository` szerződés és a két provider kell. A
`lib/features/song_trainer/public.dart` viszont ma **kizárólag két képernyőt**
exportál, tehát a kör a saját listáján belül maradva **nem tudott volna** a
határszabálynak megfelelő importot írni — a lista tágítása pedig H3
([L478](../LESSONS.md)). Ugyanaz a hibaosztály, mint az R1: a kör az egyetlen
használható forrásfájlt nem kapta meg.

**A `domain/public.dart` nem oldja fel:** a nested barrel (ADR 0089/0176) a
`domain/models/**`-ot és a `domain/services/**`-ot exportálja, a
`domain/repositories/**`-ot nem, a provider-szimbólum pedig a nem-publikus
`application/song_trainer_providers.dart`-ban él. A `lib/app/routing/`-ba
költöztetett wiring (a `lib/app/**` nem esik a cross-feature szabály alá)
**ELVETVE**: az a határszabály megkerülése volna.

**MÉRVE az önjavító körben (2026-08-27, a kör munkapéldányán, a próbafolt
utólag visszaállítva):** a barrel három export-sorával és a három import
átkötésével

- `dart run tool/check_architecture.dart` → `Architecture dependencies OK (12 allowlisted deviation(s))` (3 → 0 sértés);
- `flutter analyze lib/` → `No issues found!` (a barrel screen-exportjai nem ütköznek);
- `flutter test test/core/architecture_dependency_test.dart` → `+44 All tests passed`.

**A jogosultság PONTOSAN ennyi** — egyetlen fájl, tisztán **additív**
export-sorok, a meglévő két screen-export érintetlenül:

```dart
export 'domain/repositories/song_repository.dart' show SongQuery, SongRepository;
export 'domain/repositories/setlist_repository.dart' show SetlistRepository;
export 'application/song_trainer_providers.dart'
    show setlistRepositoryProvider, songRepositoryProvider;
```

…majd a fenti három `library_v2` fájl importja `../../song_trainer/public.dart`-ra
áll át. A `show`-klauzula kötelező: a barrel a feature belső felületét NEM
nyithatja ki szélesebbre a ténylegesen szükséges öt szimbólumnál. A
`song_trainer` **bármely más** fájljának módosítása továbbra is `stopped`, és a
`lib/features/song_trainer/**` a tiltott zónában marad a `public.dart` egyetlen
kivételével. A mintát a kör saját fája már követi:
`lib/features/library_v2/data/analysis_item_source.dart` az `audio_analysis`
gyökér-barrelen keresztül importál.

**Őrteszt:** `tools/tests/test_e13_r28_song_trainer_public_barrel_scope.py`
(a mért három halt-útvonal + a barrel scope-ban van; a `song_trainer` szomszédos
belső fájljai NEM). [L508](../LESSONS.md).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-40–UI-41 egységes tétel-lista, tárolási/szinkron-státusz és **biztonságos
adatkezelés** (SDD Ch13 Kör 28).

## 2. Jelenlegi állapot — mért tények

- A könyvtár többféle tételt fog össze (gyakorlás, elemzés, dal, setlist) —
  a route-olásnak típus-biztosnak kell lennie.
- Az R22 kimondta: a sérült rekord izolált. Ez a kör ugyanezt az egységes
  listára terjeszti ki.
- Az ADR 0279 kimondta: a destruktív megerősítés a következményt nevezi meg.

## 3. Scope

**Benne van:** az egységes könyvtár keresés / szűrés / lista-részlet felülete
**típus-biztos** route-olással · a session részletnézete (metaadat,
eredmény-előnézet, jegyzet, export, összehasonlítás, törlés) · sérült tétel
izolálása, tárhely-közeli-limit, helyi/felhő és **szinkron-ütközés** állapotok ·
tárhely-kezelési belépési pont (a tényleges törlést a repository use case
végzi) · a legacy Library route adaptere · lapozás, stabil görgetés, offline
cached tesztek.

**NINCS benne (tilos):** a törlési vagy szinkron-logika implementálása a
felületen · a tárolási séma módosítása · más képernyők migrációja ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/library_v2/` | az egységes könyvtár |
| `lib/features/song_trainer/public.dart` | **kizárólag** a §0.0/R5 öt szimbólumának `show`-os, additív exportja — a dal/setlist tételtípus cross-feature határa; a `song_trainer` minden más fájlja tiltott (§0.0/R5) |
| `lib/app/routing/` | **kizárólag** a legacy alias |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a könyvtár-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/library_v2/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r28-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `library_v2/` és a
`song_trainer/public.dart` KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A sérült tétel NEM töri a listát

Egyetlen olvashatatlan rekord nem viheti magával az egész könyvtárat — hibásként
jelenik meg, a többi elérhető marad (az ADR 0283 §5 kiterjesztése).

### 5.2 A helyi tartalom OFFLINE megnyitható

Ami a készüléken van, hálózat nélkül is elérhető.

### 5.3 A törlés HATÓKÖRE világos

A megerősítés kimondja, mi törlődik: csak a nyers hang, csak az eredmény, vagy
minden. Az ADR 0279 §1 alkalmazása a legveszélyesebb műveletre.

**NEM elfogadható gyengítés:** „Törlöd? Igen/Nem" a hatókör megnevezése nélkül.
A felhasználó nem tudja, mit veszít.

### 5.4 A felület NEM implementál törlési logikát

A tárhely-kezelés belépési pont; a tényleges műveletet a repository use case
végzi. Így a törlés egy helyen mérhető és tesztelhető.

### 5.5 A nyers eszköz hiánya mellett az EREDMÉNY megmarad

Ha a nyers hangot törölték vagy hiányzik, a származtatott elemzés továbbra is
megnyitható. A kettő nem egyetlen egység.

### 5.6 A szinkron-ütközés MEGMONDJA a választást

Nem néma felülírás: a felhasználó látja, melyik verzió melyik, és dönt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A tétel-típusok route-olása típus-biztos, nem téveszt célt | `item_routing_test.dart` |
| A2 | A sérült tétel izolált, a lista működik | `corrupt_item_test.dart` |
| A3 | A helyi tartalom offline megnyitható | ugyanott |
| A4 | A törlés hatóköre a megerősítésben megjelenik | `delete_confirmation_test.dart` |
| A5 | A felület nem implementál törlési logikát (use case-t hív) | `grep` a diffben |
| A6 | A nyers eszköz hiánya mellett az eredmény megmarad | `corrupt_item_test.dart` |
| A7 | A szinkron-ütközés választást kínál, nem néma felülírást | `sync_conflict_test.dart` |
| A8 | A legacy Library route működik | `item_routing_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r28_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy sérült rekord kiüti a listát | **A2** |
| „Törlöd? Igen/Nem" hatókör nélkül | **A4** |
| A törlés a widgetben történik | **A5** |
| A nyers hang hiánya elrejti az eredményt | **A6** |
| A szinkron némán felülír | **A7** |
| A típus szerinti route elágazás hibás célt ad | A1 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A törlés-hatókör három kötelező cellája** (a küszöb: mi törlődik):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | csak a nyers hang | a megerősítés kimondja: **az eredmény megmarad** |
| rajta (a küszöbön) | **csak az eredmény** | a megerősítés kimondja, hogy a nyers hang megmarad |
| a küszöb fölött | a teljes tétel | a megerősítés kimondja, hogy **minden** törlődik és visszafordíthatatlan |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a törlési
megerősítést általános „Igen/Nem"-re → az **A4** cellának PIROSNAK kell lennie
→ állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/library_v2/item_routing_test.dart test/features/library_v2/corrupt_item_test.dart test/features/library_v2/delete_confirmation_test.dart test/features/library_v2/sync_conflict_test.dart test/app/navigation/ test/ui/goldens/e13_r28_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r28_screens_golden_test.dart
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

1. Az egységes lista + típus-biztos route-olás. A dal/setlist forrás a
   `song_trainer` **gyökér-barrelén** keresztül kapcsolódik (§0.0/R5) — belső
   fájlra mutató cross-feature import a `test/core/architecture_dependency_test.dart`-ot
   pirosra váltja.
2. A sérült tétel izolálása és az offline elérhetőség.
3. A session részletnézete (metaadat, előnézet, jegyzet, export).
4. A törlés-hatókör három cellája — use case hívással.
5. A szinkron-ütközés választó felülete.
6. A legacy route adaptere + lapozás, stabil görgetés.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A hatókör nélküli törlés.** A leggyakoribb visszafordíthatatlan
  felhasználói hiba forrása (A4).
- **A felületbe költöző törlési logika.** Kényelmes, és megsokszorozza a
  helyeket, ahol adat veszhet el (A5).
- **A néma szinkron-felülírás.** A felhasználó munkáját viszi el úgy, hogy
  észre sem veszi (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
