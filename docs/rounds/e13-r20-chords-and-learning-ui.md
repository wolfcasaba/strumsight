# E13-R20 — Chord Library, Learning Path és Lesson UI

- **Státusz:** READY (kör-indító pre-flight 2026-08-25, `main @ 886cd5b6` — §0.0/R5–R13)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 20
- **Kör-azonosító:** `E13-R20`
- **Branch:** `<motor>/e13-r20-chords-and-learning-ui`
- **Előfeltétel:** `E13-R19` merge-elve (tuner/metronóm)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0282`](../adr/0282-diagram-text-alternative-and-handedness.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel a TÉNYLEGES akkord- és
> lecke-domain modelleket (fogásminta, variáció, előfeltétel mezők), valamint a
> meglévő haladás-tárolást — a §5.3 „legacy haladás megmarad" cellája arra
> hivatkozik. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/chords/",
  "lib/features/learn/",
  "lib/core/design_system/components/music/ss_chord_diagram.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/chords/chord_diagram_semantics_test.dart",
  "test/features/chords/chord_diagram_test.dart",
  "test/features/chords/chord_tap_to_hear_test.dart",
  "test/features/chords/chord_tile_a11y_test.dart",
  "test/features/chords/favorite_chords_test.dart",
  "test/features/learn/continue_card_test.dart",
  "test/features/learn/expected_chord_hint_test.dart",
  "test/features/learn/latency_calibration_screen_test.dart",
  "test/features/learn/learn_rollback_test.dart",
  "test/features/learn/learn_screen_test.dart",
  "test/features/learn/lesson_highway_test.dart",
  "test/features/learn/lesson_list_screen_test.dart",
  "test/features/learn/lesson_score_card_test.dart",
  "test/features/learn/live_scoring_jitter_test.dart",
  "test/features/learn/next_lesson_cta_test.dart",
  "test/features/learn/review_r100_fixes_test.dart",
  "test/features/learn/setlist_expected_hint_test.dart",
  "test/features/learn/visual_offset_test.dart",
  "test/features/learn/waltz_count_in_test.dart",
  "test/features/learn/wrapped_prompt_test.dart",
  "test/features/chords/chord_library_test.dart",
  "test/features/chords/chord_diagram_text_test.dart",
  "test/features/learn/learning_path_test.dart",
  "test/features/learn/lesson_offline_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  "docs/rounds/e13-r20-chords-and-learning-ui.md",
]
gate_tests = [
  "test/features/chords/chord_library_test.dart",
  "test/features/chords/chord_diagram_text_test.dart",
  "test/features/learn/learning_path_test.dart",
  "test/features/learn/lesson_offline_test.dart",
  "test/ui/goldens/e13_r20_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
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

**Kockázat = high, indoklás:** a tanulási felület a felhasználó gyakorlási előzményét (személyes teljesítmény-adat) olvassa és írja.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fája ma **65** l10n-kulcsot használ, és mind feloldható: `app` = 65 kulcs.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `chords` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `learn` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/chords/chord_diagram_semantics_test.dart`
  - `test/features/chords/chord_diagram_test.dart`
  - `test/features/chords/chord_tap_to_hear_test.dart`
  - `test/features/chords/chord_tile_a11y_test.dart`
  - `test/features/chords/favorite_chords_test.dart`
  - `test/features/learn/continue_card_test.dart`
  - `test/features/learn/expected_chord_hint_test.dart`
  - `test/features/learn/latency_calibration_screen_test.dart`
  - `test/features/learn/learn_rollback_test.dart`
  - `test/features/learn/learn_screen_test.dart`
  - `test/features/learn/lesson_highway_test.dart`
  - `test/features/learn/lesson_list_screen_test.dart`
  - `test/features/learn/lesson_score_card_test.dart`
  - `test/features/learn/live_scoring_jitter_test.dart`
  - `test/features/learn/next_lesson_cta_test.dart`
  - `test/features/learn/review_r100_fixes_test.dart`
  - `test/features/learn/setlist_expected_hint_test.dart`
  - `test/features/learn/visual_offset_test.dart`
  - `test/features/learn/waltz_count_in_test.dart`
  - `test/features/learn/wrapped_prompt_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 14 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/chords/`, `lib/features/learn/` könyvtár-előtag
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

### S11 — az örökség-képernyőt PINNELŐ, listán kívüli tesztek (2026-08-25)

A kör lecserél legalább egy MEGLÉVŐ képernyőt, amelynek a TÍPUSÁT a brief
listáján kívül élő teszt pinneli. Mérve a `tools/brief-lint.py` `S11`
szabályával (import ÉS típusnév együtt), a `main @ b28bb1bf` fán:

- `test/app/navigation/adaptive_scaffold_test.dart`
- `test/app/navigation/legacy_route_redirect_test.dart`
- `test/app/navigation/tab_state_restoration_test.dart`
- `test/app/offline_network_guard_test.dart`
- `test/core/screen_size_guard_test.dart`
- `test/features/songs/setlist_flow_test.dart`

Ez pontosan az a halt-osztály, amelyik az **E13-R16/F9**-et (full-gate
32867296946, `hasLength(79)` vs 81) és az **E13-R17/H3**-at (`flutter test
test/app/navigation/` +33 → +30 -3) megállította: az őr a listán kívül él, a
felvétele az orchestrátornak TÁGÍTÁS ([L478](../LESSONS.md)), tehát a kör H3-ban
áll meg, mielőtt egyetlen sor kód megszületne. A fenti fájlok ezért mostantól
az `allowed_paths`-on ÉS a `gate_tests`-en is szerepelnek.

**A jogosultság PONTOSAN a lecserélt képernyő típusának átírása.** Cella
törlése, `skip`-je, küszöb-lazítása vagy az állítás gyengítése TILOS — az a
mérce meghamisítása. Ha a kör bizonyíthatóan nem cseréli le a képernyőt, a kör
pre-flightja mondja ki ezt a mérést, és hagyja a cellákat érintetlenül.

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
- `test/l10n/hardcoded_string_guard_test.dart`
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

### R5 — az ADR `0282` MÁR A `main`-en van: olvasd el, NE írd újra

A pipeline-prompt „az ADR-t te írod meg a pre-flightban" sora **elavult**. Mérve:

```
$ git log --oneline -2 -- docs/adr/0282-diagram-text-alternative-and-handedness.md
e8f8e24b docs(ch13): E13-R18..R21 briefek + ADR 0282
```

Az ADR 0282 tehát **merge-elt döntés**, a `docs/adr/` pedig a tilos zónában van
— újraírása [H1](../adr/0087-autonomous-round-pipeline.md) lenne. A §5 kötött
döntései szó szerint egyeznek az ADR §Döntés hat pontjával; a kör az ADR-t
**hivatkozza**, nem szerkeszti. (Ugyanez a minta, mint az E13-R16 `0281`-e —
`HANDOFF.md` §6.)

### R6 — a design-system komponens NEM olvashat feature-providert (A2 kivitelezése)

Az ÚJ `lib/core/design_system/components/music/ss_chord_diagram.dart` a
design system fájában él, ahol egy gépi őr tiltja a feature-függést. Mérve
(`test/core/architecture_dependency_test.dart`, `design system boundaries
(E13-R02)` group, `real design system source has no feature dependency`):

```
lib/core/design_system/example.dart -> package:strumsight/features/live/public.dart
```

A kezesség forrása viszont **feature-provider**:
`lib/features/settings/providers/left_handed_provider.dart` →
`leftHandedProvider` (mérve; a mai `ChordDiagram` a
`lib/features/chords/widgets/chord_diagram.dart:32`-ben `ref.watch`-csal
olvassa). Az `SsChordDiagram` ezért **nem watch-olhatja** — a kezességet és a
fogásmintát **paraméterként** kapja, a providert a `lib/features/chords/` ill.
`lib/features/learn/` oldali hívó olvassa. Ugyanígy: a design system a
`lib/features/chords/chord_shape.dart` `ChordShape`-et sem importálhatja — a
komponens a saját, feature-független bemeneti típusán dolgozik.

A második őr-ág (`real production source reaches the design system only via
public.dart`) miatt a kör feature-kódja **kizárólag**
`lib/core/design_system/public.dart`-on át érheti el az új komponenst,
`components/music/...` közvetlen importtal SOHA. Pontosan ez a **E13-R16/F8**
hibaosztály (11 sértés, `docs/reviews/e13-r16-review.md`), és a §0.0/S12 óta a
`test/core/architecture_dependency_test.dart` a kör LOKÁLIS kapujában fut, tehát
a lelet már a célzott gate-en piros — nem a 17 perces Full Gate-en.

### R7 — a szemantika-teszt ma az ADR 0282 §2 ELLENKEZŐJÉT pinneli (A2)

Mérve, `test/features/chords/chord_diagram_semantics_test.dart` (a listán van,
§0.0/R2):

```dart
testWidgets('left-handed mirroring flips the DRAWING only — the spoken '
    'fingering stays low-E to high-E', (tester) async {
  await pumpDiagram(tester, 'C', leftHanded: true);
  expect(find.bySemanticsLabel('C chord diagram, fingering: x 3 2 0 1 0'), findsOneWidget);
});
```

A `lib/features/chords/widgets/chord_diagram.dart:78-81` doc-commentje ezt a
round-88-as döntésként rögzíti. Az **ADR 0282 §Döntés 2.** ezt VISSZAFORDÍTJA:
balkezes módban a felolvasott húrsorrend is tükrözött.

**Ez tehát NEM mérce-gyengítés, hanem a merge-elt ADR által előírt
viselkedés-váltás** — a cellát az ÚJ elvárásra kell ráállítani (a §0.0/R2
„ráállítás" jogosultsága), a cella törlése vagy `skip`-je továbbra is TILOS. A
jobbkezes ág (`x 3 2 0 1 0`) és a barre-cella (`x 4 6 6 5 4`) **változatlanul
zöld kell maradjon** — ez a §6.1 „a küszöb alatt" cellája.

### R8 — ÚJ ÚTVONAL NEM KÉSZÜLHET: a részletnézetek `Navigator.push`-sal jönnek

Mérve: a fán CSAK két érintett útvonal létezik —
`AppRoutes.learn = '/learn'` → `LessonListScreen` és
`AppRoutes.chords = '/chords'` → `ChordLibraryScreen`
(`lib/app/routing/app_route.dart:9,19`, `app_router.dart:257,297`). **Akkord-
és lecke-részletnézet útvonala NINCS.**

A `lib/app/routing/**` a §4 tilos zónájában van, tehát új `GoRoute` vagy új
`AppRoutes` konstans felvétele **H3** → `stopped` jelzés. A már merge-elt,
követendő precedens ugyanebben a fában
(`lib/features/learn/screens/lesson_list_screen.dart:242-247`):

```dart
onTap: unlocked
    ? () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => LearnScreen(lesson: lesson)))
```

A részletnézetek tehát útvonal nélküli, feature-en belüli push-sal (vagy
sheet/inline panellel) nyílnak. Ez a `test/tooling/route_literal_guard_test.dart`
(`navigation calls use the central AppRoutes catalogue`, a `gate_tests`-en)
mércéjét is tartja: nincs új útvonal-literál.

### R9 — A4 SZŰKÍTÉS: letöltés-alrendszer NINCS, a mérce a VALÓDI hiányzó erőforrás

Mérve a `lib/features/learn/` és `lib/features/chords/` fán:

- `grep -rn "download\|Download\|offline\|Offline"` → **0 találat**;
- `grep -rn "rootBundle\|AssetBundle"` → **0 találat**; a leckék kód-konstansok
  (`lib/features/learn/model/lesson.dart` `Lessons`), a kíséret pedig **helyben
  szintetizált** (`lib/features/learn/audio/chord_audio.dart` — összegzett
  szinuszok, nem letöltött eszköz);
- a `pubspec.yaml` `assets:` blokkja NEM tartalmaz lecke-eszközt (tutor-tudás,
  tutor-promptok, ML-súlyok — mind becsomagolt);
- a `test/app/offline_network_guard_test.dart` (a `gate_tests`-en) MA is azt
  pinneli, hogy a `LessonListScreen` útvonala **nulla hálózati hívást** tesz
  (`_expectNoNetwork`, `(route: AppRoutes.learn, type: LessonListScreen)`).

**A tanulási felület tehát ma is 100%-ban offline** — „le nem töltött lecke-
eszköz" mint állapot a kódban NEM létezik. Egy csak-a-teszt-kedvéért felvett
letöltés-gomb **mockolt alapfunkció** lenne, amit a projekt kifejezetten tilt.

A brief §5.5 / ADR 0282 §Döntés 4. mérhető magja az **ADR 0277 §Döntés 2.**
(„az offline nem hiba-stílus, a tartalom látható marad, a képernyő nem ürül
ki"). Az **A4 ezért a fán VALÓBAN előálló hiányzó erőforrásokra szűkül** — mindkettő
mért, ma is elérhető bemenet:

1. **nincs diagram-forma:** `ChordShapes.forLabel(label) == null`
   (`chord_shape.dart:74`) — ma `SizedBox.shrink()`, azaz a tartalom **némán
   eltűnik** (`chord_diagram.dart:30`);
2. **nincs lejátszható kíséret:** a `ChordAudio` ismeretlen minőség-utótagra
   `null` hangkészletet ad (`chord_audio.dart` `_quality` térkép).

**Az A4 elvárása:** ilyen bemenetnél a képernyő (a) **működik**, nem vált
hibaállapotra, (b) **megnevezi**, mi hiányzik, és (c) a ténylegesen elérhető
következő lépést kínálja (pl. a lecke kíséret nélküli gyakorlása). A §6.1
falszifikációs sora változatlan: **hiányzó eszköz → hibaállapot ⇒ A4 PIROS**;
kiegészül azzal, hogy a **néma `shrink` (a tartalom nyom nélküli eltűnése) is
A4 PIROS**. Kitalált letöltés-gomb az A4-et NEM teljesíti.

Ez **szűkítés**, nem tágítás: sem az `allowed_paths`, sem a `gate_tests` nem
változik, és a cella továbbra is falszifikálható.

### R10 — A6 konkretizálás: mi a „gyakorlás-akció", és mi bizonyítja

Mérve: az akkordtár ma tapintásra CSAK a hangot szólaltatja meg
(`chord_library_screen.dart:29` → `ref.read(backingProvider).playChord(label)`),
gyakorlás-indítás NINCS. A `/practice/chords` útvonal ugyanezt a
`ChordLibraryScreen`-t építi (`app_router.dart:462`), tehát **nem** paraméterezhető
cél.

Az R8 miatt a gyakorlás-akció a meglévő, útvonal nélküli precedenst követi:
`LearnScreen(lesson: …)` push, ahol a lecke a **megnyitott akkordból** épül
(`Lesson(...)`, `lesson.dart:40`). Az A6 bizonyítéka ezért gépi és éles: a
felnyomott `LearnScreen` leckéjének `chordSequence`-e a MEGNYITOTT akkordot
tartalmazza, nem a lista elsőjét (`chordSequence`, `lesson.dart:123`).

### R11 — A3 kiindulópont: a zárolás ma indoklás NÉLKÜLI (mért)

`lesson_list_screen.dart:249-251`: zárolt leckére koppintva a képernyő egy
`SnackBar(content: Text(l10n.learnLocked))`-et mutat — a feloldás módja sehol.
A feloldási szabály `lesson_progress_provider.dart:36` `isUnlocked`: *a szint
első leckéje, vagy az azonos szinten előtte álló lecke teljesítve*. Az A3 ezt a
KONKRÉT feltételt kéri a felületre (melyik lecke oldja fel), és a
`lesson_progress_provider.dart` **logikája nem módosulhat** (§3 tilalom) — a kör
csak olvassa.

### R12 — a képernyő-leltár mai száma (§0.0/R4 kivitelezése)

`test/ui/ui_inventory_test.dart:14` → `expect(first.screenPaths, hasLength(84))`.
A jogosultság PONTOSAN ennek a számnak a kör tényleges képernyőszámára emelése.

### R13 — az A5 mért tárolása (a „legacy haladás megmarad" cellához)

A haladás `Map<String, double>` (lecke-id → legjobb pontosság), forrása
`lib/features/learn/data/lesson_progress_repository.dart` (`load()`/`save()`),
olvasója `lessonProgressProvider` (`lesson_progress_provider.dart:19`, szinkron
`build()`). Az A5 tehát úgy mérhető, hogy a teszt **előre feltöltött**
repository-val indul, és a migrált felületen a csillagok/„folytatás" a
korábbi értékeket mutatják. A séma (kulcsok, típus) **nem törhető** — ez a §3
tilalma.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-11–UI-14 migrációja közös Learning Mode komponensekre, **balkezes** és
**offline** tartalomtámogatással (SDD Ch13 Kör 20).

## 2. Jelenlegi állapot — mért tények

- Az R11 űrlapelemei (keresés, chip, választó) és az R12 kártyái készen állnak.
- Az R15 lokalizációs kapui élnek — az új szövegek ARB-paritással jönnek.
- Az akkorddiagram grafikus elem: felolvasóval **önmagában néma**.

## 3. Scope

**Benne van:** az akkordtár keresés/szűrés/kedvencek elrendezése · az akkord
részletnézete (diagram, fogás, variációk, gyakorlás-akció) · a tanulási út
**lineáris, hozzáférhető alternatívával** · a lecke részletnézetének készenléti,
előfeltétel-, letöltési és haladás-állapotai · **balkezes** diagram és szöveges
leképezés · hiányzó tartalom / offline / zárolt / migrációs állapotok.

**NINCS benne (tilos):** a tanulási domain-logika vagy az előfeltétel-számítás
módosítása · a haladás-adat sémájának törése · más képernyők migrációja ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/chords/` | az akkordtár UI-ja |
| `lib/features/learn/` | tanulási út + lecke UI |
| `components/music/ss_chord_diagram.dart` | **ÚJ** — diagram + szöveges alternatíva |
| `public.dart` | az export bővítése |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a tartalmi szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (20 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/**` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r20-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a két érintett KIVÉTELÉVEL ·
`lib/core/theme/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0282)

### 5.1 A diagramnak SZÖVEGES alternatívája van

Az akkorddiagram grafikus információ. Felolvasóval a fogás szöveges leírásként
érhető el („E-húr: üres, A-húr: 2. bund, …"). Enélkül a tartalom vak
felhasználónak nem létezik.

**NEM elfogadható gyengítés:** csak az akkord neve semantics labelként. A név
nem mondja meg, hova kell tenni az ujjakat — pont a lecke lényege veszik el.

### 5.2 A balkezes megjelenítés a SZÖVEGET is tükrözi

Nem elég a rajzot tükrözni: a szöveges leírásnak is a balkezes húrsorrendet
kell követnie, különben a két csatorna ellentmond egymásnak.

### 5.3 A meglévő haladás MEGMARAD

A migráció nem nullázhatja a felhasználó eddigi eredményét. Ez
acceptance-cella (A5).

### 5.4 A zárolás OKA világos

„Zárolva" önmagában zsákutca. Meg kell mondani, mi oldja fel.

### 5.5 A hiányzó offline tartalom NEM omlaszt

Ha egy lecke eszköze nincs letöltve, a képernyő működik, és felajánlja a
letöltést — nem hibaállapotba esik (ADR 0277 §2 szellemében).

### 5.6 A gyakorlás-akció HELYESEN paraméterez

Az akkord részletnézetéből indított gyakorlás azzal az akkorddal indul.
Rossz paraméterezés esetén a felhasználó némán mást gyakorol.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A diagramnak szöveges alternatívája van (fogás-leírás) | `chord_diagram_text_test.dart` |
| A2 | Balkezes módban a rajz ÉS a szöveg is tükrözött | ugyanott |
| A3 | A zárolás oka megjelenik | `learning_path_test.dart` |
| A4 | Hiányzó erőforrás (nincs diagram-forma / nincs kíséret) nem omlaszt: a képernyő működik, megnevezi a hiányt és a valóban elérhető következő lépést kínálja — **§0.0/R9 szűkítés**, letöltés-alrendszer a fán nincs | `lesson_offline_test.dart` |
| A5 | A meglévő haladás megmarad a migráció után | `learning_path_test.dart` |
| A6 | A gyakorlás-akció a megnyitott akkorddal paraméterez | `chord_library_test.dart` |
| A7 | A keresés/szűrés/kedvencek működik és állapota megmarad | ugyanott |
| A8 | A tanulási útnak van lineáris, hozzáférhető alternatívája | `learning_path_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r20_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Csak az akkord neve semantics labelként | **A1** |
| Balkezes rajz jobbkezes szöveggel | **A2** |
| „Zárolva" indoklás nélkül | A3 |
| Hiányzó erőforrás → hibaállapot | **A4** |
| Hiányzó erőforrás → néma `SizedBox.shrink()` (a tartalom nyom nélkül eltűnik) | **A4** (§0.0/R9) |
| Kitalált „Letöltés" gomb valódi letöltés-alrendszer nélkül | **A4** — a cellát NEM teljesíti (§0.0/R9) |
| A gyakorlás a lista első akkordjával indul, nem a megnyitottal | **A6** (§0.0/R10) |
| A haladás nullázódik | **A5** |
| A gyakorlás mindig az első akkorddal indul | **A6** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A balkezes leképezés három kötelező cellája** (a küszöb: a kezesség-beállítás):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | jobbkezes (alapértelmezett) | a mai húrsorrend, rajz és szöveg egyezik |
| rajta (a küszöbön) | **balkezes bekapcsolva** | rajz **és** szöveg is tükrözött |
| a küszöb fölött | balkezes + képernyőolvasó | a felolvasott sorrend a tükrözöttet követi |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tükrözd csak a rajzot,
a szöveget ne → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/chords/chord_library_test.dart test/features/chords/chord_diagram_text_test.dart test/features/learn/learning_path_test.dart test/features/learn/lesson_offline_test.dart test/ui/goldens/e13_r20_screens_golden_test.dart test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/offline_network_guard_test.dart test/core/screen_size_guard_test.dart test/features/songs/setlist_flow_test.dart test/core/architecture_dependency_test.dart test/l10n/hardcoded_string_guard_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r20_screens_golden_test.dart
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

1. `ss_chord_diagram.dart` — rajz **és** szöveges alternatíva egy forrásból.
2. A kezesség három cellája.
3. Az akkordtár keresés/szűrés/kedvencek + állapotmegőrzés.
4. Az akkord részletnézete + helyesen paraméterezett gyakorlás-akció.
5. A tanulási út lineáris alternatívával, zárolási okkal.
6. A lecke offline/hiányzó eszköz állapotai.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A néma diagram.** A rajz elkészül, a szöveges alternatíva marad el, és a
  tanulási tartalom fele hozzáférhetetlen lesz (A1).
- **A félig tükrözött balkezes nézet.** A két csatorna ellentmond, ami rosszabb,
  mint a tükrözés hiánya (A2).
- **A haladás elvesztése.** A migráció legdrágább hibája: a felhasználó
  bizalmát viszi (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
