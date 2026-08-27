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
  "test/features/library/",
  "test/app/navigation/",
  "test/app/routing/app_router_test.dart",
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
saját pre-flightja mérje ki (`tools/round-gate.sh test/features/library_v2/item_routing_test.dart test/features/library_v2/corrupt_item_test.dart test/features/library_v2/delete_confirmation_test.dart test/features/library_v2/sync_conflict_test.dart test/features/library/ test/app/navigation/ test/app/routing/app_router_test.dart test/ui/goldens/e13_r28_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart`),
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

## 0.0/B — KÖR-PRE-FLIGHT, 2026-08-27 (`main @ 768af6ec`, orchestrátor: Claude)

**Visszakeresett előzmény** (`node tools/knowledge-rag.mjs --corpus lessons,halts,adr`
és `--corpus lessons,halts`): [L503](../LESSONS.md#l503) (az `S13` „nem létező
könyvtár" lelet elfedhet egy MÉLYEBB hibát — a brief a fa MÁSIK, azonos témájú
feature-ét írja le), [L497](../LESSONS.md#l497) (a lista fedhet nulla fájlt),
[L478](../LESSONS.md#l478) (a pre-flight csak SZŰKÍTHET; a tágítás H3),
[L499](../LESSONS.md#l499) (egy zöld cella lehet azért zöld, mert az ellenőrzött
forgatókönyv sosem dobja el az állapottartót), [L06](../LESSONS.md) (az elnyelt
hiba néma no-op — minden csendes fallback gyanús),
[ADR 0220](../adr/0220-audio-analysis-v2-parallel-rollout-boundary.md) (V1/V2
párhuzamos rollout: a V1 a teljes átmenet alatt SÉRTETLENÜL fut),
[ADR 0239](../adr/0239-analysis-document-storage.md) +
[ADR 0221](../adr/0221-legacy-analysis-v2-migration-mapping.md) (a V1 Library
store a rollback útvonal miatt olvasható marad),
[ADR 0279](../adr/0279-the-confirmation-states-the-consequence.md),
[ADR 0283](../adr/0283-the-result-claims-no-more-than-was-measured.md),
[ADR 0277](../adr/0277-failure-presentation-model.md).

### B1 — az `S13` lelet feloldása: a lint MÁSODIK ága (a könyvtárat EZ a kör hozza létre)

A `brief-lint` `S13` helyesen mérte, hogy `lib/features/library_v2/` a
verziókövetett fában nem létezik. A lint két utat kínál; **az elsőt (csere a fán
MÉRT rétegre) a mérés KIZÁRJA**, ezért a második érvényes.

Mért állapot (`find lib -iname '*librar*'`, `main @ 768af6ec`):

| Mért | Érték |
|---|---|
| `lib/features/library/` | LÉTEZIK — 6 fájl: `data/library_repository.dart`, `model/analyzed_session.dart`, `providers/library_providers.dart`, `public.dart`, `screens/library_screen.dart`, `screens/session_detail_screen.dart` |
| Ez a fa | a **V1 (legacy) Library**, amit az E06-R21 a V2 `audio_analysis` fába migrált |
| `lib/features/audio_analysis/data/migration/legacy_library_migrator.dart` §6 | szó szerint: *„NEVER touches the legacy `ss.library.sessions` / `library_sessions` keys — the V1 store remains readable for the **rollback path**"* |
| A fát pinnelő, a listán KÍVÜL élő tesztek | `test/features/library/{library_test,library_cap_test,rename_capo_title_test,session_rename_test}.dart` (4) + `test/app/routing/app_router_test.dart` |

A prefix cseréje `lib/features/library/`-re tehát (a) egy **befagyasztott,
rollback-célú** fát nyitna szerkesztésre az [ADR 0220](../adr/0220-audio-analysis-v2-parallel-rollout-boundary.md)
ellenében, és (b) öt, a listán kívüli tesztfájlt tenne kockára — ami `blocked`,
nem feloldás. Az L503 tanulsága itt **fordítva** alkalmazandó: ott a brief a
MÁSIK fát írta le és a valódi képernyők máshol MÁR LÉTEZTEK; itt a valódi
képernyők a legacy fában élnek, és a kör tárgya (az item-unió: gyakorlás,
elemzés, dal, setlist) a V1 analízis-listánál **szélesebb**, tehát nem
migráció-a-helyén.

**Döntés (a lint második ága):** `lib/features/library_v2/` az az ÚJ könyvtár,
amit **EZ a kör hoz létre**. Az `allowed_paths` változatlan — se tágítás, se
szűkítés nem szükséges.

### B2 — a route-szétválasztás szerződése: a kör PONTOSAN egy meglévő buildert ír át

A brief §0.0/R3 azt írta elő, hogy a kör saját pre-flightja mérje ki, pontosan
melyik cellák pirosodnak. **Kimérve** (`grep -rn "LibraryScreen\|SessionDetailScreen"`,
`lib/app/routing/app_router.dart`, `lib/app/config/feature_flags.dart:52`):

`FeatureFlags.adaptiveShellEnabled` **defaultja `false`** (`feature_flags.dart:52`,
`:129`). Ebből következik a teljes pin-térkép:

| Útvonal | Builder | Pinnelő teszt | Shell-flag | Listán? |
|---|---|---|---|---|
| `AppRoutes.library` (`/library`, legacy `HomeShell`) | `app_router.dart:261` → `LibraryScreen` | `test/app/routing/app_router_test.dart:177`, `test/features/library/library_test.dart:82` | **OFF** (default) | **NINCS → TILOS módosítani** |
| `AppRoutes.librarySession` (`/library/session`) | `app_router.dart:302–310` → `SessionDetailScreen` | `test/app/routing/app_router_test.dart:197` | **OFF** (default) | **NINCS → TILOS módosítani** |
| `AppRoutes.profileLibrary` (`/profile/library`, adaptív shell) | `app_router.dart:505–507` → `LibraryScreen` | `test/app/navigation/adaptive_scaffold_test.dart:237` | **ON** | **IGEN** (R3) |
| `AppRoutes.library` → `AppRoutes.profileLibrary` legacy redirect | `adaptive_shell_routes.dart:14` | `test/app/navigation/legacy_route_redirect_test.dart:159` | **ON** | **IGEN** (R3) |

**Szerződés (falszifikálható):** a kör az `app_router.dart`-ban **PONTOSAN EGY**
meglévő buildert ír át — a `AppRoutes.profileLibrary`-ét (`:505–507`) —, és
**hozzáad** egy új route-ot az UI-41-hez
(`AppRoutes.profileLibrarySession = '/profile/library/session/:sessionId'`, új
konstans a `lib/app/routing/app_route.dart`-ban). A `:261` és a `:302–310`
builder, valamint a `lib/features/library/**` fa **érintetlen marad** — se
törlés, se átnevezés, se signature-változás.

Ebből gépileg következik: a listán kívüli öt tesztfájl **zöld marad**, és
pontosan **két** cella pirosodik, mindkettő a listán lévő `test/app/navigation/`
fában — az `adaptive_scaffold_test.dart:237` és a
`legacy_route_redirect_test.dart:159` típus-pinje. A jogosultság PONTOSAN e két
cella típusnevének átírása; minden más állítás (primary navigation, a többi tíz
adapter, a query/fragment megőrzése, az aciklikusság) érintetlen.

**Ezért kerül a `gate_tests`-be — de NEM az `allowed_paths`-ra — a
`test/features/library/` és a `test/app/routing/app_router_test.dart`:** a kör
lokális kapuja MÉRI a befagyasztott V1 pineket, de nem szerkesztheti őket. Ez az
S12-mintázat kiterjesztése (a fa-szintű őrök a lokális kapuba), így a
szerződés-sértés a ~2 perces kör-gate-en bukik, nem a ~17 perces exact-SHA Full
Gate-en. Ha ezek bármelyike pirosra vált: `stopped` + jelentés, **nem** csendes
átírás.

### B3 — a §5.4 törlési use case és a szinkron-státusz típusok MÉRVE

A brief fejlécének kötelező pre-flight kérdése (tárolási/szinkron típusok + hol
él a törlés):

| Kérdés | MÉRT válasz |
|---|---|
| Hol él ma a törlés? | `LibraryController.delete(String id)` — `lib/features/library/providers/library_providers.dart`, a `libraryProvider` notifierén; kifelé a `lib/features/library/public.dart` exportálja. A repository (`LibraryRepository.save`) csak a listát írja. |
| V2 oldal | `AnalysisRepository` (`lib/features/audio_analysis/domain/analysis_repository.dart`) — a document/summary-index gazdája (ADR 0239). |
| Szinkron-státusz típus | `SsAsyncStatus` (`lib/core/design_system/components/feedback/ss_async_state.dart`): `loading, content, empty, failure, permission, blocked, offline, syncPending, degraded`. Az `offline`/`syncPending`/`degraded` ág `_CachedContentBanner`-t rajzol a tartalom FÖLÉ — a helyi tartalom tehát látszik offline is (A3). |
| Szinkron-**ütközés** típus | **NINCS a fán** (`grep -rln "onflict" lib/` → egyetlen library/analysis szinkron-ütközés modell sem). |

**Következmény az A5-re és az A7-re:** a `library_v2/` ütközés-modellje
**prezentációs** modell (a kör saját fájában), a feloldást a felület
**callbackkel delegálja**, és **nem ír tárolót**. Az A5 bizonyítéka ezért
gépiesíthető grep: a `lib/features/library_v2/` fában NEM fordulhat elő
`JsonDocumentStore`, `JsonCollectionStore`, `keyValueStoreProvider`,
`.save(`, `.write(` hívás — a törlés kizárólag a meglévő use case
(`libraryProvider.notifier.delete` / `AnalysisRepository`) hívása lehet. A néma
felülírás tilalma az [L06](../LESSONS.md) általánosítása: a csendes fallback
kontrollált hiba vagy választás, sosem néma.

### B4 — a §5.2/A3 offline-cellája NEM lehet triviálisan zöld (L499)

Az [L499](../LESSONS.md#l499) mért hibaosztálya: a cella azért zöld, mert az
ellenőrzött forgatókönyv sosem dobja el az állapottartót. Az A3 tesztje ezért
**nem** elégedhet meg azzal, hogy egy offline állapotú listán látszik a tétel:
a cellának a **megnyitást** kell mérnie (a helyi tétel részletnézete offline
állapotban is renderel tartalmat), és a teszt mondja ki kommentben, mi a
hálózat-hiány szimulált forrása.

### B5 — a kötelező DS-komponensek listája MÉRVE (a `design_system` TILOS zóna)

Az SDD Ch13 UI-40/UI-41 hét komponenst nevez meg, amelyek **a fán nem
léteznek**: `SsSearchField`, `SsChoiceChip`, `SsListDetail`,
`SsSyncPendingBadge`, `SsOfflineBanner`, `SsInlineMessage`, `SsSectionHeader`.
A `lib/core/design_system/**` ennek a körnek **tilos zóna** (§4), tehát új
komponenst a kör NEM készít — ez **szűkítés**, nem tágítás.

A `lib/core/design_system/public.dart`-ból MÉRT, ténylegesen elérhető
megfelelők (a kör ezeket használja, és **kizárólag a `public.dart`-on át**
importál — a `foundations/**` közvetlen importja az E13-R16/F8 mért hibája,
amit a `test/core/architecture_dependency_test.dart` fog):

| SDD-ben kért | MÉRT helyettesítő a `public.dart`-ból |
|---|---|
| `SsSearchField` | `SsTextField` (`components/inputs/ss_text_field.dart`) |
| `SsChoiceChip` | `SsChoice` (`components/inputs/ss_choice.dart`) |
| `SsListDetail` | `SsAdaptiveScaffold` (`layouts/ss_adaptive_scaffold.dart`) |
| `SsSyncPendingBadge` | `SsStatusBadge` (`components/feedback/ss_status_badge.dart`) |
| `SsOfflineBanner` | `SsAsyncState` `offline`/`syncPending` ága |
| `SsEmptyState` | `SsEmptyState` — LÉTEZIK |
| `SsMetricCard` | `SsMetricCard` — LÉTEZIK |
| `SsToolConfirmationSheet` | `SsToolConfirmationSheet` — LÉTEZIK |
| `SsInlineMessage` | `SsFailureState` / `SsAsyncState` (`components/feedback/`) |
| `SsSectionHeader` | `SsSection` (`components/surfaces/ss_section.dart`) |
| destruktív megerősítés (§5.3, ADR 0279) | `SsConfirmationSheet.show(...)` — `title` + **`consequence`** + `confirmLabel` + `cancelLabel`; a `consequence` a hívó feature l10n-jéből jön |

### B6 — a kör ADR-t NEM ír (a `docs/adr/**` marad tilos zóna)

Az `E13-R28`-hoz a sor-fájl `nincs` ADR-t rendel. A kör §5 döntései MIND
merge-elt ADR-ek alkalmazásai: §5.1 → [0283](../adr/0283-the-result-claims-no-more-than-was-measured.md) §5,
§5.3/§5.4 → [0279](../adr/0279-the-confirmation-states-the-consequence.md) §1,
a §0.0/B2 V1/V2 route-szétválasztás → [0220](../adr/0220-audio-analysis-v2-parallel-rollout-boundary.md)
(a V1 sértetlenül fut a teljes átmenet alatt), §5.6 →
[0277](../adr/0277-failure-presentation-model.md) + [L06](../LESSONS.md).
Új ADR írása merge-elt döntés fölé **H1** volna. A sávon ez a **tizenegyedik**
ADR nélküli kör egymás után (E13-R17…R28) — ugyanaz a mért minta, mint az
E13-R27-nél.

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
a **V1 `lib/features/library/` fa** bármilyen módosítása (befagyasztott
rollback-útvonal, §0.0/B1–B2) · a `AppRoutes.library` (`app_router.dart:261`)
és a `AppRoutes.librarySession` (`:302–310`) builder módosítása ·
új design-system komponens (§0.0/B5) · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/library_v2/` | az egységes könyvtár — **ÚJ könyvtár, ezt a kör hozza létre** (§0.0/B1) |
| `lib/features/song_trainer/public.dart` | **kizárólag** a §0.0/R5 öt szimbólumának `show`-os, additív exportja — a dal/setlist tételtípus cross-feature határa; a `song_trainer` minden más fájlja tiltott (§0.0/R5) |
| `lib/app/routing/` | **kizárólag** a §0.0/B2 szerződése: a `AppRoutes.profileLibrary` builder átírása + a `AppRoutes.profileLibrarySession` route/konstans hozzáadása. A `:261` és `:302–310` builder módosítása **TILOS** |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a könyvtár-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/library_v2/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r28-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `library_v2/` és a
`song_trainer/public.dart` KIVÉTELÉVEL (nevesítve:
`lib/features/library/**` — a befagyasztott V1 fa; a `song_trainer` minden
MÁS fájlja tiltott, §0.0/R5) · `lib/core/design_system/**` ·
`lib/core/theme/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

**Futtatott, de NEM szerkeszthető őrök** (a `gate_tests`-en vannak, az
`allowed_paths`-on **nincsenek** — §0.0/B2 és §0.0/S12): `test/features/library/`
(a V1 pinek), `test/app/routing/app_router_test.dart` (a legacy route-pinek),
`test/core/architecture_dependency_test.dart`, `test/tooling/dio_factory_guard_test.dart`,
`test/tooling/preferences_plugin_import_guard_test.dart`,
`test/tooling/route_literal_guard_test.dart`. Ha ezek bármelyike pirosra vált, a
javítás kizárólag a kör SAJÁT kódjában történhet; cella törlése, `skip`-je vagy
gyengítése gépileg kizárt. Feloldhatatlan lelet → `stopped` + jelentés.

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
| A3 | A helyi tartalom offline **megnyitható** — a lista-megjelenés önmagában NEM elég (§0.0/B4, [L499](../LESSONS.md#l499)): a cella a részletnézet renderelését méri offline állapotban, és a teszt kommentben mondja ki, mi a hálózat-hiány szimulált forrása | `corrupt_item_test.dart` |
| A4 | A törlés hatóköre a megerősítésben megjelenik | `delete_confirmation_test.dart` |
| A5 | A felület nem implementál törlési logikát (use case-t hív) | **gépi grep a diffben:** a `lib/features/library_v2/` fában NINCS `JsonDocumentStore`, `JsonCollectionStore`, `keyValueStoreProvider`, `.save(` vagy `.write(` előfordulás; a törlés kizárólag `libraryProvider.notifier.delete(...)` / `AnalysisRepository` hívás (§0.0/B3) |
| A6 | A nyers eszköz hiánya mellett az eredmény megmarad | `corrupt_item_test.dart` |
| A7 | A szinkron-ütközés választást kínál, nem néma felülírást — a felület a döntést **callbackkel delegálja**, tárolót nem ír (§0.0/B3, [L06](../LESSONS.md)) | `sync_conflict_test.dart` |
| A8 | A legacy Library route működik | `item_routing_test.dart` |
| A10 | **A route-szétválasztás szerződése (§0.0/B2):** a kör az `app_router.dart`-ban PONTOSAN a `AppRoutes.profileLibrary` buildert írja át és HOZZÁAD egy `AppRoutes.profileLibrarySession` route-ot; a `:261` és `:302–310` builder, valamint a `lib/features/library/**` fa érintetlen | `test/features/library/` **és** `test/app/routing/app_router_test.dart` a kör gate-jén VÁLTOZATLANUL zöld + `test/app/navigation/` pontosan a két típus-pin cellájában módosul |
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
| A kör a legacy `/library` buildert (`app_router.dart:261`) is átköti | **A10** — `test/app/routing/app_router_test.dart:177` és `test/features/library/library_test.dart:82` PIROS (mindkettő `adaptiveShellEnabled=false` mellett fut) |
| A kör a `AppRoutes.librarySession` buildert (`:302–310`) átköti | **A10** — `test/app/routing/app_router_test.dart:197` PIROS |
| A kör a befagyasztott V1 `lib/features/library/**` fát módosítja vagy átnevezi | **A10** — a `test/features/library/` négy tesztje PIROS, és a scope-audit `VIOLATION`-t ad |
| A felület offline csak a listát mutatja, de a tétel megnyitása üres/hibás | **A3** (a B4 szerinti erősebb olvasat) |

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
tools/round-gate.sh test/features/library_v2/item_routing_test.dart test/features/library_v2/corrupt_item_test.dart test/features/library_v2/delete_confirmation_test.dart test/features/library_v2/sync_conflict_test.dart test/features/library/ test/app/navigation/ test/app/routing/app_router_test.dart test/ui/goldens/e13_r28_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r28_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r28_screens_golden_test.dart
```

> ⚠ **Pre-flight-javítás (2026-08-27):** a brief eredetileg
> `flutter test --update-goldens`-t írt elő. Ez a boxon **ARM-pixelt** rögzít,
> amit az x86-os CI pirosra vált — mérve az E13-R20/H5 önjavító körben
> ([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md),
> [L493](../LESSONS.md#l493)); a merge-elt precedens (E13-R23…R27) mind a
> `tools/golden-x86.sh`-t használja. A `--update-goldens` **TILOS**.

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

### Mi épült

`lib/features/library_v2/` — az egységes könyvtár, teljesen ÚJ fa:

- **`domain/library_item.dart`** — az öt tétel-változat: `CorruptLibraryItem`,
  `AnalysisLibraryItem`, `PracticeLibraryItem`, `SongLibraryItem`,
  `SetlistLibraryItem` (sealed `LibraryItem` felett), plusz
  `LibraryItemType` (4 valós tartalom-típus) és `LibrarySyncStatus`.
- **`domain/library_item_source.dart`**, **`domain/library_delete_actions.dart`**,
  **`domain/library_delete_scope.dart`** — a forrás- és törlés-portok.
- **`data/`** — négy forrás-adapter, mindegyik a MEGLÉVŐ repository-t
  csomagolja (nem nyit új tárolót, §5.4): `analysis_item_source.dart`
  (`AnalysisRepository`), `practice_item_source.dart` (a
  `PracticeHistoryRepository`-t egy injektált loader-closure-ön át, l.
  lent), `song_item_source.dart` (`SongRepository`), `setlist_item_source.dart`
  (`SetlistRepository`); `analysis_library_delete_actions.dart` a törlés
  use case-t hívja.
- **`providers/library_v2_providers.dart`** — a négy forrást összefésülő
  `libraryV2ItemsProvider` (egy sérült forrás `CorruptLibraryItem`
  placeholdert kap, a többi töretlen marad, §5.1), keresés/szűrés
  providerek, törlés-akció provider.
- **`screens/unified_library_screen.dart`**, **`screens/library_item_detail_screen.dart`**,
  **`widgets/library_delete_section.dart`**, **`widgets/library_theme_scope.dart`**
  — a lista, a típus-biztos részletnézet és a törlés-felület.
- **`lib/app/routing/`** — a §0.0/B2 szerződés PONTOSAN: a
  `AppRoutes.profileLibrary` builder átírva `UnifiedLibraryScreen`-re, és
  hozzáadva `AppRoutes.profileLibrarySession` (`state.extra is LibraryItem`
  redirect-tel a hiányzó/rossz extra esetére). A `:261` (`librarySession` →
  `LibraryScreen`) és a `:302–310` (bare `/library` → `LibraryScreen`)
  builder, valamint a teljes `lib/features/library/**` fa **érintetlen**.

### Acceptance-mátrix (A1–A10)

| # | Bizonyíték | Mért eredmény |
|---|---|---|
| A1 | `item_routing_test.dart` | ZÖLD — mind a négy típus + a corrupt placeholder + a nem-`LibraryItem` `extra` a saját (ill. list-re redirect) tartalmát nyitja |
| A2 | `corrupt_item_test.dart` | ZÖLD — egy törött forrás mellett a többi tétel él, a corrupt detail-nézet nem omlik össze |
| A3 | `corrupt_item_test.dart` | ZÖLD — a §0.0/B4 szerint a cella a RÉSZLETNÉZET renderelését méri offline `syncStatus` mellett, kommentben nevesítve a szimulált forrást |
| A4 | `delete_confirmation_test.dart` | ZÖLD + **valódi-sértés próba lefutott (lásd lent)** |
| A5 | `delete_confirmation_test.dart` (gépi grep) | ZÖLD — nincs `JsonDocumentStore`/`JsonCollectionStore`/`keyValueStoreProvider`/`.save(`/`.write(` a `library_v2/` fában |
| A6 | `corrupt_item_test.dart` | ZÖLD — `hasRawAudio=false, hasResult=true` az eredményt elérhetőnek mutatja |
| A7 | `sync_conflict_test.dart` | ZÖLD — mindkét verzió látszik, a választás callback-kel delegált, nincs tárolóírás (gépi grep is zöld) |
| A8 | `item_routing_test.dart` | ZÖLD — `AppRoutes.library`/`AppRoutes.librarySession` változatlanul a `LibraryScreen`/`SessionDetailScreen`-t építi |
| A9 | `e13_r28_screens_golden_test.dart` + `test/ui/goldens/*.png` | ZÖLD — l. golden-szakasz lent |
| A10 | `test/features/library/` + `test/app/routing/app_router_test.dart` + `test/app/navigation/` | ZÖLD — l. A10-szakasz lent |

### A4 valódi-sértés próba (mért, ebben a folytató körben elvégezve)

`lib/features/library_v2/widgets/library_delete_section.dart`-ban a három
scope-cella (`title, consequence, confirmLabel`) ideiglenesen egyetlen
generic `('Delete?', 'This cannot be undone.', 'Yes')` hármasra lett
cserélve — hatókör nevesítése nélkül, pontosan az 5.3 tiltott mintája.

```
flutter test test/features/library_v2/delete_confirmation_test.dart
```

**Mért kimenet: PIROS, mind a három §6.1 cella.** Mindhárom `expect(find.text(...), findsOneWidget)`
hívás `Found 0 widgets` hibával bukott (a konkrét hatókör-szöveg helyett a
generic szöveg jelent meg), pl.:

```
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Only the raw recording is deleted. The
analysis result stays available.": []>
```

A fájl ezután `git checkout --` paranccsal visszaállítva az eredeti,
scope-nevesített verzióra; a teszt utána ismét ZÖLD (`All tests passed!`,
4/4). A cella tehát ténylegesen érzékeny a tiltott gyengítésre.

### Golden-felvétel (A9)

```
tools/golden-x86.sh record test/ui/goldens/e13_r28_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r28_screens_golden_test.dart
```

Négy PNG commitolva (`test/ui/goldens/goldens/`):
`e13_r28_unified_library_compact.png`, `e13_r28_unified_library_compact_scale2.png`,
`e13_r28_library_item_detail_compact.png`, `e13_r28_library_item_detail_compact_scale2.png`
— 412×915 compact portrait és `textScaleFactor: 2.0`, a két képernyőre
(unified list + item detail). A kör gate-jén a
`test/ui/goldens/e13_r28_screens_golden_test.dart` lépés ZÖLD (4/4 teszt).

### A10 bizonyíték

- `test/features/library/` (V1 pinek): a kör gate-jén **ZÖLD**, 12/12 teszt
  — a legacy fa (`rename_capo_title_test.dart`, `session_rename_test.dart`,
  `library_test.dart`) változatlan.
- `test/app/routing/app_router_test.dart`: a kör gate-jén **ZÖLD**, 22/22
  teszt — a legacy `librarySession`/bare-`/library` route-pár érintetlen
  (l. `lib/app/routing/app_router.dart` diffje: a `:261`-i és `:302–310`-i
  builder szó szerint `LibraryScreen()`/`SessionDetailScreen()` maradt).
- `test/app/navigation/`: a kör gate-jén **ZÖLD**, 33/33 teszt, és **pontosan
  két** típus-pin cella módosult (mindkettő a §0.0/B2 szerint):
  - `adaptive_scaffold_test.dart`: `AppRoutes.profileLibrary: LibraryScreen`
    → `UnifiedLibraryScreen`.
  - `legacy_route_redirect_test.dart`: `AppRoutes.library: LibraryScreen`
    → `UnifiedLibraryScreen`.
  Egyetlen más pin (route→screen leképezés) NEM változott.

### `test/ui/ui_inventory_test.dart`

`hasLength(89)` → `hasLength(91)` — a kör két új production screent ad a
fához (`unified_library_screen.dart`, `library_item_detail_screen.dart`);
a jogosultság PONTOSAN a számemelés (§0.0/R4), más állítás a fájlban
érintetlen. A kör gate-jén ZÖLD.

### Architektúra-kapu — MÉRT állapot és a maradék, kör-hatókörön KÍVÜLI hiány

A folytató munkamenet indulásakor a `test/core/architecture_dependency_test.dart`
**PIROS** volt: 14 „cross-feature imports must target public.dart"
sértéssel. A kör SAJÁT kódjában javítható 11 megoldva (mind import-útvonal
csere egy MÁR teljesen exportáló `public.dart`-ra — `audio_analysis/public.dart`,
`share/public.dart`, `practice/public.dart`; l. a `6605b92c` commit):

- `analysis_item_source.dart`, `analysis_library_delete_actions.dart`,
  `library_item_detail_screen.dart` → `audio_analysis/domain|application|presentation/*`
  helyett `audio_analysis/public.dart` (minden hivatkozott szimbólum már ott él).
- `library_item_detail_screen.dart` → `share/share_service.dart` helyett
  `share/public.dart`.
- `library_v2_providers.dart` → `audio_analysis/application/analysis_providers.dart`
  és `practice/data/local_practice_history_repository.dart` helyett a
  megfelelő `public.dart`.
- `practice_item_source.dart`: a `PracticeHistoryRepository` TÍPUS nincs
  exportálva a `practice/public.dart`-ból (csak a
  `practiceHistoryRepositoryProvider` provider-szimbólum, `show`-val
  szűkítve) — a forrás closure-alapúra lett átalakítva
  (`Future<LibrarySourceLoad> Function() _load`), a típusos leképezés
  a `library_v2_providers.dart`-ba költözött, ahol Dart típuskövetkeztetése
  a `PracticeHistoryRepository`/`PracticeHistoryEntry` nevek KIÍRÁSA nélkül
  is helyesen fordul (nincs `dynamic`, az `flutter analyze` 0 hibával fut).

**3 sértés MARADT, egyetlen közös okra vezethető vissza, és a kör
engedélyezett fájllistáján (§4) KÍVÜL eső javítást igényel:**

```
lib/features/library_v2/data/setlist_item_source.dart -> lib/features/song_trainer/domain/repositories/setlist_repository.dart
lib/features/library_v2/data/song_item_source.dart -> lib/features/song_trainer/domain/repositories/song_repository.dart
lib/features/library_v2/providers/library_v2_providers.dart -> lib/features/song_trainer/application/song_trainer_providers.dart
```

**Ok:** sem a `lib/features/song_trainer/public.dart` (csak 2 screen exportja
van), sem a `lib/features/song_trainer/domain/public.dart` (csak
modell/service exportok, `tool/check_architecture.dart` `_isFeaturePublicBarrel`
szerint egyébként ÉRVÉNYES célpont lenne) nem exportálja a `SongRepository`,
`SongQuery`, `SetlistRepository` típusokat vagy a `songRepositoryProvider`/
`setlistRepositoryProvider` providereket. A `practice`-nél alkalmazott
closure-trükk itt NEM zárja le a rést: a `songRepositoryProvider`/
`setlistRepositoryProvider` SZIMBÓLUM maga csak a nem-public
`song_trainer_providers.dart`-ban él, ezt semmilyen típusinferencia nem
váltja ki — a szimbólum eléréséhez elkerülhetetlen egy nem-`public.dart`
import valahol.

**Miért nem oldható fel ebben a körben:** a javítás
`lib/features/song_trainer/public.dart` és/vagy `domain/public.dart`
bővítését igényelné — ez a §4 tiltott zónájában van
(`lib/features/** a library_v2/ KIVÉTELÉVEL`). Az allowlist-bejegyzés
alternatívája ADR-t igényelne (`tool/check_architecture.dart`: "adding an
allowlist entry requires justification and an ADR"), az ADR-írás pedig a
§B6 szerint **szintén tiltott** ebben a körben (`docs/adr/**` tiltott zóna).

**Funkcionális hatás: NULLA.** Az összes gate-tesztfájl (`item_routing_test.dart`,
`corrupt_item_test.dart`, `delete_confirmation_test.dart`,
`sync_conflict_test.dart`, `library/`, `app/navigation/`,
`app/routing/app_router_test.dart`, a golden teszt, `ui_inventory_test.dart`)
**ZÖLD** — ezek `libraryV2SourcesProvider.overrideWithValue([...])`-vel fake
adatot injektálnak, a valódi `SongItemSource`/`SetlistItemSource` production
wiring-ot egyik gate-teszt sem futtatja át. A maradék 3 sértés kizárólag a
`tool/check_architecture.dart` statikus import-ellenőrzését érinti.

### Nevesített follow-up

Egy KÖVETKEZŐ körnek (song_trainer hatókörrel, tehát nem E13) exportálnia
kell a `SongRepository`, `SongQuery`, `SetlistRepository` típusokat és a
`songRepositoryProvider`/`setlistRepositoryProvider` providereket a
`lib/features/song_trainer/public.dart`-ból (vagy a `domain/public.dart`-ból,
ha a domain-only export elég), hogy a `library_v2/data/song_item_source.dart`
és `setlist_item_source.dart` átválthasson a `public.dart`-ra — ezzel az
architektúra-kapu 14/14 sértése lezárható lenne.

## 11. Review — a Claude tölti ki

**Orchestrátor-mérés, 2026-08-27, HEAD `2fc71cda`, izolált munkapéldány
`/home/ubuntu/ss-sonnet-impl-e13-r28`.** A `scope_audit=ok` (base `9fba0250`),
a fa tiszta.

### A kötelező kapu — a SAJÁT futásom, csonkítatlanul (`/tmp/gate-e13-r28.txt`)

| # | Lépés | Eredmény |
|---|---|---|
| 1 | format | **ZÖLD** |
| 2 | analyze | **ZÖLD** (`No issues found!`) |
| 3 | `test/features/library_v2/item_routing_test.dart` | **ZÖLD** |
| 4 | `test/features/library_v2/corrupt_item_test.dart` | **ZÖLD** |
| 5 | `test/features/library_v2/delete_confirmation_test.dart` | **ZÖLD** |
| 6 | `test/features/library_v2/sync_conflict_test.dart` | **ZÖLD** |
| 7 | `test/features/library/` (a befagyasztott V1 pinek) | **ZÖLD** |
| 8 | `test/app/navigation/` | **ZÖLD** |
| 9 | `test/app/routing/app_router_test.dart` (legacy route-pinek) | **ZÖLD** |
| 10 | `test/ui/goldens/e13_r28_screens_golden_test.dart` | **ZÖLD** |
| 11 | `test/ui/ui_inventory_test.dart` | **ZÖLD** |
| 12 | `test/core/architecture_dependency_test.dart` | **PIROS (1)** |

Gate kilépési kód **10**; a 13–15. lépés (`architecture`, `secrets`, `l10n`)
az első piros lépés után nem futott.

**Az A10 route-szerződés gépileg IGAZOLT:** a 7. és a 9. lépés zöldje pontosan
azt méri, hogy a legacy `:261` / `:302–310` builder és a `lib/features/library/**`
V1 fa érintetlen maradt — ez a §0.0/B2 falszifikálható állítása, és teljesült.

### Az EGYETLEN nyitott lelet — BLOCKER, és a kör hatókörén KÍVÜL esik

```
$ dart run tool/check_architecture.dart
- lib/features/library_v2/data/setlist_item_source.dart -> lib/features/song_trainer/domain/repositories/setlist_repository.dart [cross-feature imports must target public.dart]
- lib/features/library_v2/data/song_item_source.dart    -> lib/features/song_trainer/domain/repositories/song_repository.dart    [cross-feature imports must target public.dart]
- lib/features/library_v2/providers/library_v2_providers.dart -> lib/features/song_trainer/application/song_trainer_providers.dart [cross-feature imports must target public.dart]
```

MÉRT gyökérok: a `lib/features/song_trainer/public.dart` **két képernyőt**
exportál és semmi mást; sem a `SongRepository` / `SongQuery` /
`SetlistRepository` típusokat, sem a `songRepositoryProvider` /
`setlistRepositoryProvider` szimbólumokat. A `practice`-nél működő
closure-trükk itt nem zár: a provider-SZIMBÓLUM maga csak a nem-public
`song_trainer/application/song_trainer_providers.dart`-ban él, tehát a
szimbólum eléréséhez elkerülhetetlen egy nem-`public.dart` import.

### A megoldási tér — MÉRVE, három ág

- **A (javasolt):** `lib/features/song_trainer/public.dart` felvétele az
  `allowed_paths`-ra, és a fenti öt szimbólum exportja. Egy fájl, additív, a
  boundary-szabályt ERŐSÍTI. Ez **lista-tágítás → H3**, tehát user-engedélyt
  igényel — pontosan úgy, ahogy ennek a briefnek a §0.0/R1-e is kapott
  (2026-08-25).
- **B:** a kör szűkítése elemzés + gyakorlás tétel-típusra (a `song`/`setlist`
  forrás elhagyása). Ez a §3 négy tétel-típusát kettőre csökkenti, tehát a
  szállított hatókör csökkentése — user-döntés, nem orchestrátori.
- **C (MÉRVE, de ELVETVE):** a wiring áthelyezése `lib/app/routing/`-ba. Mérés:
  a `lib/app/**` **NEM** esik a cross-feature szabály alá — az
  `app_router.dart:59` MA IS közvetlenül importálja a
  `song_trainer/application/song_trainer_providers.dart`-ot, és a checker nem
  jelzi. A kapu tehát ezzel zöldre menne. **Mégis elvetve:** ez feature-adat
  wiringet tenne a routing rétegbe pusztán a határszabály megkerülésére, és
  túllépné a `lib/app/routing/` §4-ben rögzített, szándékosan szűk
  jogosultságát („kizárólag a §0.0/B2 szerződése"). A mérce megkerülése nem
  feloldás.

### Verdikt

**HALT — H3.** A kód kész és a mérce minden más pontján zöld; a feloldás egy
`allowed_paths`-on kívüli fájl (`lib/features/song_trainer/public.dart`)
szerkesztését vagy a kör hatókörének csökkentését kívánja. Egyik sem az
orchestrátor hatásköre ([L478](../LESSONS.md), ADR 0087 §2 H3). Javító kör
indítása értelmetlen: ugyanebbe a falba futna.
