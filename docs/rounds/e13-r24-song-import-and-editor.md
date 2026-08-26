# E13-R24 — Song import, preview és editor UI

- **Státusz:** READY (pre-flight 2026-08-26, `main @ 3b88f757` — lásd §0.0/B;
  előre megírva 2026-08-15, kód olvasva: `main @ 74f8a8ec`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 24
- **Kör-azonosító:** `E13-R24`
- **Branch:** `<motor>/e13-r24-song-import-and-editor`
- **Előfeltétel:** `E13-R23` merge-elve (dal-könyvtár)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0284`](../adr/0284-import-preview-is-not-a-commit.md)
  — **MÁR MERGE-ELT (elfogadva, 2026-08-15): ez a kör ADR-t NEM ír** (§0.0/B/R5).
  A foglaló `0429`-et adott: kiosztott, de fel nem használt szám.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES import-
> csővezeték kimenetét (figyelmeztetés és blokkoló hiba típusai, ideiglenes
> fájlok helye) — a §5.1 és §5.3 ezekre a mért típusokra képez felületet.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/presentation/screens/song_import_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_editor_screen.dart",
  "lib/features/song_trainer/presentation/widgets/import_warning_list.dart",
  "lib/features/song_trainer/presentation/widgets/song_metadata_editor.dart",
  "lib/features/song_trainer/presentation/widgets/song_section_editor.dart",
  "lib/features/song_trainer/presentation/widgets/song_event_editor.dart",
  "lib/features/song_trainer/presentation/widgets/measure_grid.dart",
  "lib/features/song_trainer/presentation/widgets/backing_asset_editor.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/songs/import/import_flow_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/editor_keyboard_flow_test.dart",
  "test/fixtures/songs/import/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r24-song-import-and-editor.md",
]
gate_tests = [
  "test/features/songs/import/import_flow_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/editor_keyboard_flow_test.dart",
  "test/ui/goldens/e13_r24_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/features/song_trainer/presentation/song_import_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_preview_screen_test.dart",
  "test/features/song_trainer/presentation/song_editor_screen_test.dart",
  "test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart",
  "test/app/routing/app_router_test.dart",
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

**Kockázat = high, indoklás:** a dal-import KÜLSŐ, nem megbízható fájlt olvas be (import-határ), a szerkesztő pedig felülírja a felhasználó saját tartalmát.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/songs/import/`, `lib/features/songs/editor/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

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

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — nincs ilyen. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/songs/editor/`, `lib/features/songs/import/` könyvtár-előtag
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

## 0.0/B BRIEF-REVÍZIÓ — 2026-08-26, kör-indító pre-flight (`main @ 3b88f757`)

A fenti §0.0 a 2026-08-25-i sáv-szintű batch pre-flight terméke; ez a szakasz
a kör TÉNYLEGES indítása előtt, a fán mérve írja felül. Mérés-eszközök: `find`,
`grep -rn`, `git grep`, a `docs/rounds/e03-r1[456]-*.md` merge-elt
`allowed_paths` blokkjai, és `tools/round-slots.py reserve-adr`.

**Visszakeresett előzmény** (ADR 0312, `node tools/knowledge-rag.mjs`,
szűkített → teljes sorrendben): [L493](../LESSONS.md#l493) + [L486](../LESSONS.md#l486)
+ [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) — a
golden-raszterizációt a merge-kapu architektúráján kell felvenni (R9);
[L488](../LESSONS.md#l488) — a listán kívüli pin-tesztek HELYBEN maradnak, a
képernyő helyben migrál (R7); [L477](../LESSONS.md#l477) — mérd a cella BUKÁSI
képességét, ne csak a zöldjét (R8/R10); [L463](../LESSONS.md#l463) — a briefben
PONTOSAN EGY `ai-router` blokk lehet, ezért a fenti blokk **helyben**
íródott át, nem mellé.

### R5 — az ADR `0284` MÁR MERGE-ELT: ez a kör ADR-t NEM ír

A fejléc „a Claude írja meg a kör indításakor" mondata elavult. Mérve:
`docs/adr/0284-import-preview-is-not-a-commit.md` a fán van, státusza
**elfogadva**, dátuma 2026-08-15, és a §5 mind a hat kötött döntése SZÓ SZERINT
ennek az ADR-nek a Döntés 1–6 pontja. Merge-elt ADR átírása **H1** (ADR 0087 §2),
ezért a kör ADR-t nem ír. A foglaló (`tools/round-slots.py reserve-adr --round
E13-R24`) **`0429`**-et adott — kiosztott, de FEL NEM HASZNÁLT szám marad,
pontosan úgy, mint az E13-R22 `0428`-a. A sávon ez a **hetedik** ADR nélküli
kör egymás után (E13-R17…R24).

### R6 — a brief KÉT megnevezett könyvtára a fán NEM LÉTEZIK (H3-osztály, útvonalcsere)

```
find lib/features/songs -type d      → application data model providers screens theory widgets
```

`lib/features/songs/import/` és `lib/features/songs/editor/` **nincs a fán** —
az eredeti `allowed_paths` tehát **nulla létező fájlt** fedett, és a §0.0/R1
„a képernyőket ez a kör hozza létre, tehát MINDEN szövege új" állítása MÉRVE
hamis. Ez az [L497](../LESSONS.md#l497) hibaosztály **harmadik** előfordulása
ugyanezen a sávon (E13-R22/R6, E13-R23/B, most R6); a `brief-lint --level
strict` ismét „nincs lelet"-et adott.

A három célfelület a `song_trainer` **presentation** rétegében él, mind a három
LÉTEZIK és ma zöld:

| Felület | Tényleges fájl | Sor |
|---|---|---|
| Import folyamat | `lib/features/song_trainer/presentation/screens/song_import_screen.dart` | 97 |
| Import előnézet | `…/screens/song_import_preview_screen.dart` | 61 |
| Szerkesztő | `…/screens/song_editor_screen.dart` | 282 |

A csere a merge-elt, **user-jóváhagyott** E03-R15 és E03-R16 briefek
`allowed_paths` literáljainak valódi RÉSZHALMAZA (mindkét lista tartalmazza
mind a három képernyőt és mind az öt szerkesztő-widgetet; a kör az
`application/`, `domain/`, `data/`, `app/routing/`, `public.dart` és
`pubspec.*` bejegyzéseiket **NEM** veszi át — azok olvashatók, de nem
írhatók). A `guitar_pro_conversion_guidance.dart` szándékosan kimarad: a
`guitar_pro_conversion_guidance_test.dart` pinneli, és a kör nem nyúl hozzá.

### R7 — négy, a listán KÍVÜLI pin-teszt: a képernyők HELYBEN migrálnak

```
grep -rln "SongImportScreen\|SongImportPreviewScreen\|SongEditorScreen" test/
```

- `test/features/song_trainer/presentation/song_import_screen_test.dart`
- `test/features/song_trainer/presentation/song_import_preview_screen_test.dart`
- `test/features/song_trainer/presentation/song_editor_screen_test.dart`
- `test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart`
- `test/app/routing/app_router_test.dart` (`findsOneWidget` a `SongEditorScreen`-re, 3 helyen)

Ez az [L488](../LESSONS.md#l488) **hatodik** alkalmazása: a képernyők HELYBEN
migrálnak — típusnév, fájl-útvonal, konstruktor-szignatúra
(`SongImportScreen()`, `SongImportPreviewScreen({required preview})`,
`SongEditorScreen({required songId})` + `.newDocument()`) és
route-regisztráció **változatlan**. A pin-tesztek a `gate_tests`-be kerültek
(futnak), de az `allowed_paths`-ra **NEM** — nem szerkeszthetők.

**MÉRT, kemény pinek, amiket a migráció nem törhet el:**

| Pin | Hol |
|---|---|
| `find.text('Choose a file')` | import screen |
| `find.text('Import song')`, `find.text('File size: 3 bytes')` | preview |
| **`tester.widget<FilledButton>(find.byType(FilledButton))`** — a preview-n PONTOSAN EGY `FilledButton` lehet | preview |
| `Key('song-editor-save' \| '-measure' \| '-chord' \| '-add-chord' \| '-tempo' \| '-set-tempo' \| '-meter-numerator' \| '-set-meter' \| '-note' \| '-add-note' \| '-attach-backing')` | editor |

A `find.byType(FilledButton)` pin miatt a preview megerősítő gombja `FilledButton`
marad, és a képernyő **nem kaphat második `FilledButton`-t** (`SsButton` sem, ha
az `FilledButton`-t épít).

### R8 — a `fatal.` előtagú előnézet-figyelmeztetésnek NINCS PRODUCERE (ADR 0087 §1/1. mérési szabály)

A §6.1 „blokkoló hiba" cellája ma a `song_import_preview_screen.dart:18`
`warning.startsWith('fatal.')` predikátumára épül. Megmérve, **melyik input
produkálja**:

```
grep -rn "fatal\." lib/features/song_trainer/   → 2 találat, MINDKETTŐ a predikátum maga
grep -n "static const String" …/importers/*.dart → songImport.<formátum>.<kód>, egyetlen `fatal.` sem
```

**Egyetlen production importer sem ad `fatal.` előtagú probe-figyelmeztetést.**
A `fatal.unsupported` literált KIZÁRÓLAG a pin-teszt gyártja szintetikusan. A
valódi blokkoló út MÁS: az elemző kivétele `ImportRegistryException` →
`SongImportController._failure(...)` → `SongImportPhase.failure` +
`state.failureCode` (`songImport.musicXml.doctypeForbidden`,
`songImport.midi.invalidHeader`, `songImport.native.sourceTooLarge`,
`songImport.native.unsupportedFormatVersion`, …), illetve
`confirmPreview()`-ban a `capability.canPersist == false` →
`'songImport.validationFailed'`.

Ezért az **A3/A4 MINDKÉT blokkoló producerre mér**, és a §6.1 táblája
ennek megfelelően íródik át (lásd lent). A `fatal.` ág **NEM törölhető** (a pin
rá támaszkodik), de önmagában nem elég bizonyíték.

### R9 — a golden felvétele a MERGE-KAPU architektúráján (ADR 0426)

A §7 `~/flutter/bin/flutter test --update-goldens` sora **elavult és tiltott**
ezen az aarch64 boxon: pontosan ez adta az E13-R17 két vak javító körét és az
E13-R20 **H5 haltját** ([L493](../LESSONS.md#l493), [L486](../LESSONS.md#l486)).
Érvényes parancs:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r24_screens_golden_test.dart
```

A PNG-k a `test/ui/goldens/goldens/` alá kerülnek (a `test/ui/goldens/`
listaelem fedi). Minta és futó precedens:
`test/ui/goldens/e13_r23_screens_golden_test.dart` (`AppTheme.dark()`, 412×915,
`devicePixelRatio: 1.0`, `textScaler` 1.0 és 2.0).

### R10 — az A6 „csak olvasható forrás" tengelye: a MÉRT predikátum a `canPersist`

`grep -rn "canPersist" lib/features/song_trainer/presentation/` → a zár ma a
**könyvtárban** él (`song_library_screen.dart:199-206`, E13-R23): a
`summary.capability?.canPersist == false` sor megtekintő-módba terel a
szerkesztő HELYETT. A `SongEditorState` **nem hordoz** capability-t, és a
`SongEditorController.load()` **nem validál** — a szerkesztő tehát ma vakon
szerkeszthetőnek tekint mindent, amit közvetlen route-tal (deep link) érnek el.

A `canPersist` MÉRT definíciója (`song_capability_resolver.dart:53-55`):
`final hasFatal = report.hasFatalIssue; final canPersist = !hasFatal;` — tehát
ugyanaz a predikátum, amit a könyvtár használ. A szerkesztő ezt a saját,
listán lévő fájljában, a merge-elt, framework-független `SongValidator` +
`SongCapabilityResolver` domain-szolgáltatásokból számolja ki (a presentation →
`domain/services/**` irányra a `test/core/architecture_dependency_test.dart`
és a `tool/check_architecture.dart` **nem tartalmaz tiltó szabályt** — mérve).

**Az A6 pontosan ennyit állít, többet nem:** `canPersist == false` esetén a
Save le van tiltva, és az EGYETLEN felkínált írási út a **másolat**
(`controller.startNew(...)` ÚJ `SongId`-val és
`SongSource(type: SongSourceType.createdInApp)`-pal), az eredeti dokumentum
pedig a tárolóban **változatlan** marad. A másolat érvényességéről a felület
**nem tesz ígéretet** — a másolat mentése újra validál.

### R11 — az A5 producere mérve: a `save()` a piszkozatot NEM dobja el

`song_editor_controller.dart:414-424`: hiba esetén `_state.copyWith(status:
failure|conflict, failureCode: …)` — a `draft` mező **érintetlen**. Az A5 tehát
nem a controller javítása, hanem a **felület** dolga: a hibát nevesítve
megmutatni ÉS a szerkesztett tartalmat a képernyőn tartani. A cella BUKÁSI
képessége ([L477](../LESSONS.md#l477)): ha a felület a hibaágon
`controller.discard()`-ot hívna vagy üres állapotot renderelne, az A5-nek
pirosra kell váltania.

### R12 — az A2 producere mérve: az `ImportWorkspace` CSAK a `confirmPreview()`-ban nyílik

`song_import_controller.dart:135-144` — a munkakönyvtár az előnézet
MEGERŐSÍTÉSEKOR nyílik, `_finish()` (256-296) pedig minden terminális ágon
`_closeWorkspace`-t hív. Az A2 cellája ezért a **beinjektált**
`workspaceRoot: () async => <temp dir>` fölött mérhető: a megszakítás után a
temp könyvtár listája ÜRES.

### R13 — a képernyő-leltár NEM mozdul: `hasLength(86)` marad

A kör mind a három képernyőt HELYBEN migrálja, ÚJ `lib/features/**/*_screen.dart`
fájlt **nem hoz létre** (R7). A `test/ui/ui_inventory_test.dart` a listán marad
(a §0.0/R4 jogosultsága érvényben), de a **várt diffje ÜRES** — ha az implementer
ezt a fájlt módosítani kényszerül, az azt jelenti, hogy új képernyőt hozott, ami
a HELYBEN-migráció megsértése: `stopped` jelzés és jelentés.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-26–UI-28 **biztonságos** import-, leképezés- és szerkesztési felülete
(SDD Ch13 Kör 24).

## 2. Jelenlegi állapot — mért tények

- Az import csővezeték **létező** réteg: külső, nem megbízható fájlt dolgoz fel,
  és figyelmeztetéseket meg blokkoló hibákat ad vissza.
- Az R13 overlay-rendszere és az R11 űrlapelemei készen állnak.
- Az ADR 0279 kimondta: a megerősítés a következményt nevezi meg.

## 3. Scope

**Benne van:** az import folyamat (üres, választás, másolás, felismerés,
elemzés, megszakítás, hiba) · az import-előnézet sáv-választással,
figyelmeztetésekkel és **blokkoló** hibával · a szerkesztő compact strukturált
és expanded több-paneles elrendezése · mentetlen piszkozat, csak olvasható
forrás, ütközés, visszavonás/újra és mentési hiba állapotok · a húzás-műveletek
**billentyűs/gombos alternatívája** · rosszindulatú, nagy és nem támogatott
fixture-ök felületi integrációja.

**NINCS benne (tilos):** az elemző (parser) vagy az import-csővezeték logikájának
módosítása · a biztonsági ellenőrzések gyengítése · a tréner (Kör 25) ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

> **A §0.0/B/R6 felülírja az alábbi két első sort** — a `songs/import/` és
> `songs/editor/` könyvtár a fán nem létezik; az érvényes lista a fenti
> `ai-router` blokk.

| Útvonal | Indok |
|---|---|
| `song_trainer/presentation/screens/song_import_screen.dart` | az import folyamat felülete (§0.0/B/R6) |
| `song_trainer/presentation/screens/song_import_preview_screen.dart` | az előnézet (§0.0/B/R6) |
| `song_trainer/presentation/screens/song_editor_screen.dart` | a szerkesztő (§0.0/B/R6) |
| `song_trainer/presentation/widgets/{import_warning_list,song_metadata_editor,song_section_editor,song_event_editor,measure_grid,backing_asset_editor}.dart` | a két felület saját widgetjei (a merge-elt E03-R15/R16 listák részhalmaza) |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — az import- és hibaszövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/songs/import/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r24-…md` | a §10 handoff |

**Tilos zóna:** az elemző és az import-csővezeték logikája ·
`lib/features/songs/` a két érintett almappán kívül ·
`lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**`.

## 5. Kötött architekturális döntések (ADR 0284)

### 5.1 Az előnézet NEM publikál és nem ment semmit

A preview kizárólag megmutat. Amíg a felhasználó nem erősít meg, nem keletkezik
tartós rekord, és semmi nem kerül ki a készülékről.

**NEM elfogadható gyengítés:** a dal „ideiglenes" mentése az előnézet
megnyitásakor, hogy egyszerűbb legyen az állapotkezelés. Onnantól a megszakítás
is hagy maga után adatot.

### 5.2 A megszakítás TAKARÍT

Megszakított import után nem marad ideiglenes fájl a készüléken. Ez
acceptance-cella (A2).

### 5.3 A blokkoló hiba NEM kerülhető meg

Ha az elemző blokkoló hibát ad, a felület nem kínál „mindegy, folytasd" utat. A
figyelmeztetés és a blokkoló hiba **két különböző** dolog, és a felületen is
annak látszik.

**NEM elfogadható gyengítés:** a blokkoló hiba figyelmeztetésként kezelése
„hogy a felhasználó ne akadjon el". Az egy nem megbízható fájlt engedne be.

### 5.4 A piszkozat MENTÉSI HIBA UTÁN IS megmarad

Ha a mentés elbukik, a szerkesztett tartalom nem vész el. A projekt már mérte,
hogy a `try/catch`-be fojtott írási hiba néma munkavesztést ad.

### 5.5 A csak olvasható forrás CSAK MÁSOLHATÓ

Szerkesztés helyett a felület saját másolat készítését kínálja (az R23 §5.2
folytatása).

### 5.6 A húzás-műveletnek van BILLENTYŰS/GOMBOS alternatívája

A szakaszok átrendezése nem köthető kizárólag húzáshoz — motorikusan korlátozott
és felolvasót használó felhasználónak is elérhető.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az előnézet nem hoz létre tartós rekordot és nem publikál | `import_flow_test.dart` |
| A2 | A megszakított import után nem marad ideiglenes fájl | ugyanott |
| A3 | A blokkoló hiba nem kerülhető meg — **MINDKÉT mért producerre** (§0.0/B/R8): (a) `fatal.` előtagú előnézet-lelet → a megerősítés letiltva; (b) `SongImportPhase.failure` + `failureCode` → a felület nevesíti a hibát, és **nincs rajta „folytasd mindenképp" affordancia** | `import_blocking_error_test.dart` |
| A4 | A figyelmeztetés és a blokkoló hiba vizuálisan ÉS szemantikusan elkülönül (külön ikon, külön szemantikai címke, külön szín-szerep) | ugyanott |
| A5 | A piszkozat mentési hiba után is megmarad — a hiba **nevesítve látszik**, és a szerkesztett tartalom a képernyőn marad (§0.0/B/R11) | `editor_draft_test.dart` |
| A6 | `canPersist == false` esetén a Save letiltva, és az EGYETLEN írási út a másolat (ÚJ `SongId` + `createdInApp` forrás); az eredeti dokumentum a tárolóban változatlan (§0.0/B/R10) | ugyanott |
| A7 | Az átrendezés billentyűvel/gombbal is elvégezhető | `editor_keyboard_flow_test.dart` |
| A8 | A mentetlen kilépés következménye szövegben megjelenik | `editor_draft_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r24_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az előnézet ideiglenes rekordot ment | **A1** |
| A megszakítás után marad temp fájl | **A2** |
| A blokkoló hiba „folytasd mindenképp" gombbal | **A3** |
| A figyelmeztetés és a blokkoló hiba azonos megjelenésű | A4 |
| A mentési hiba eldobja a piszkozatot | **A5** |
| Csak húzással átrendezhető szakaszok | **A7** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**Az elemző-lelet három kötelező cellája — MÉRT bemenetekkel** (§0.0/B/R8; a
„küszöb" a lelet súlyossága, a bemenet MINDIG a fán létező producer):

| Cella | MÉRT bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | `ImportProbeResult.recognized(warnings: const <String>[])` → `preview.warnings.isEmpty` | nincs lelet-régió; a megerősítés **engedélyezett** |
| rajta (a küszöbön) | `warnings: <String>['songImport.musicXml.timingQuantized']` (valódi `MusicXmlMapWarningCode` konstans, nem `fatal.` előtagú) | a lelet **kiemelten** látszik figyelmeztetésként; a megerősítés **engedélyezett** |
| a küszöb fölött (a) | `warnings: <String>['fatal.unsupported']` | a megerősítés **letiltva**; nincs megkerülő út |
| a küszöb fölött (b) | `SongImportPhase.failure` + `failureCode: 'songImport.musicXml.doctypeForbidden'` | a hiba **nevesítve** látszik; a képernyőn **nulla** megerősítő/„folytasd" affordancia van |

**Az A7 érintési-cél küszöbének három cellája** (küszöb: **48,0 dp**,
ADR 0280 §Döntés 5; a cellák `python3 -c`-vel számolva: `48.0-1 = 47.0`,
`48.0`, `48.0+8 = 56.0`):

| Cella | Bemenet (az átrendező gomb mért `tester.getSize(...)`) | Elvárt |
|---|---|---|
| a küszöb alatt | `47.0` | a cella **PIROS** (`Expected: >= 48.0`) |
| rajta (a küszöbön) | `48.0` | zöld — a küszöb INKLUZÍV |
| a küszöb fölött | `56.0` | zöld |

A cella a **szabályra** mérjen, ne egyetlen konkrét widgetre
([L496](../LESSONS.md#l496)): a szerkesztő MINDEN átrendező affordanciáját
járja végig.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kezeld a blokkoló
hibát figyelmeztetésként (a `fatal.` ág letiltását vedd ki, illetve a `failure`
fázisra tegyél vissza egy megerősítő gombot) → az **A3** MINDKÉT cellájának
PIROSNAK kell lennie → állítsd vissza. A próbát a `+N -M` diffel és a piros
cellák nevével dokumentáld.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/songs/import/import_flow_test.dart test/features/songs/import/import_blocking_error_test.dart test/features/songs/import/editor_draft_test.dart test/features/songs/import/editor_keyboard_flow_test.dart test/ui/goldens/e13_r24_screens_golden_test.dart test/ui/ui_inventory_test.dart test/features/song_trainer/presentation/song_import_screen_test.dart test/features/song_trainer/presentation/song_import_preview_screen_test.dart test/features/song_trainer/presentation/song_editor_screen_test.dart test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart test/app/routing/app_router_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

> ⚠ **§0.0/B/R9 felülírja az alábbi parancsot.** Az `--update-goldens` ezen az
> **aarch64** boxon TILOS (ADR 0426, [L493](../LESSONS.md#l493)): a felvétel a
> merge-kapu **x86_64** architektúráján történik.

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r24_screens_golden_test.dart
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

1. Az import folyamat állapotai + megszakítás és takarítás.
2. Az előnézet — tartós rekord NÉLKÜL.
3. A lelet-súlyosság három cellája (tájékoztató / figyelmeztetés / blokkoló).
4. A szerkesztő compact és expanded elrendezése.
5. A piszkozat megőrzése mentési hiba után + a csak olvasható másolás.
6. Billentyűs/gombos átrendezés (a meglévő fel/le `IconButton`-pár marad a
   mérce, érintési cél **≥ 48 dp** — ADR 0280 §Döntés 5; ezt a hibaosztályt a
   sáv már KÉTSZER fizette ki (E13-R20/MAJOR-1, E13-R21/MAJOR-2), ezért az
   A7 cellája a **méretet is** mérje, ne csak a működést).
7. Golden felvétele: `tools/golden-x86.sh record …` (§7, §0.0/B/R9), a PNG-ket
   commitolni.
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az „ideiglenes" mentés.** Egyszerűsíti az állapotkezelést, és a
  megszakítás után is adatot hagy (A1/A2).
- **A blokkoló hiba felpuhítása.** A felhasználó elakadása kellemetlen; a nem
  megbízható fájl beengedése rosszabb (A3).
- **A néma piszkozat-vesztés.** A projekt már mérte ezt a hibaosztályt: a
  `try/catch`-be fojtott írási hiba nem látszik, csak a munka tűnik el (A5).

## 10. Implementation handoff — az implementer tölti ki

**Felületenként, röviden:**

- **Import folyamat** (`song_import_screen.dart`) — helyben migrált; a
  `failure` fázis a hibát nevesítve mutatja (`Icons.error_outline` + error
  szín-szerep + `Semantics` `songImportBlockingSemantic`), és a kizárólagos
  cselekvés a „Choose a file" (új próbálkozás), **nincs** rajta megerősítő
  affordancia (§0.0/B/R8/(b)).
- **Import előnézet** (`song_import_preview_screen.dart`) — a `fatal.`
  előtagú figyelmeztetés a megerősítést letiltja (`FilledButton.onPressed =
  null`), és `Icons.error_outline` + `Semantics` `Fatal import issue: …`
  jelenik meg, szemben a küszöb alatti/rajta esettel
  (`Icons.warning_amber_outlined`, `ImportWarningList`). Az `ImportWorkspace`
  csak `confirmPreview()`-ban nyílik, megszakításkor mindig zár (A1/A2).
- **Szerkesztő** (`song_editor_screen.dart` + a hat widget) — a Save
  `canPersist`-tel zárolt (`SongCapabilityResolver` a domain rétegből); zárolt
  esetben az egyetlen írási út a másolat (`controller.startNew(...)`, új
  `SongId`, `createdInApp` forrás), az eredeti dokumentum változatlan marad.
  Mentési hiba esetén a `draft` a state-ben érintetlen marad, a hiba
  `failureCode` nevesítve látszik a képernyőn. A szakasz-átrendezés
  fel/le `IconButton`-párral (`song-editor-section-move-{up,down}-<index>`
  kulcsokkal) megy, húzás-widget (`Draggable`/`LongPressDraggable`/
  `ReorderableListView`) egy sincs a fán; minden ilyen gomb `tester.getSize`
  mérete `>= 48.0 dp`.

**A1–A9 cellák helye:**

| Cella | Fájl::teszt |
|---|---|
| A1 | `test/features/songs/import/import_flow_test.dart::'A1: reaching the preview creates no persistent record and writes no temp file'` |
| A2 | `test/features/songs/import/import_flow_test.dart::'A2: cancelling a confirmed import cleans the opened workspace'` |
| A3(a) | `test/features/songs/import/import_blocking_error_test.dart::'above threshold (a): a fatal.-prefixed preview warning disables confirm and looks/reads distinct from a warning'` |
| A3(b) | `test/features/songs/import/import_blocking_error_test.dart::'above threshold (b): the real SongImportPhase.failure + failureCode names the blocking error and offers zero confirm/"continue anyway" affordance'` |
| A4 | ugyanaz a két A3-cella + `'below threshold'`/`'at threshold'` cellák (ikon/szín/Semantics kontraszt) |
| A5 | `test/features/songs/import/editor_draft_test.dart::'A5: a failed save keeps the draft on screen and names the failure code'` |
| A6 | `test/features/songs/import/editor_draft_test.dart::'A6: canPersist == false locks Save; only a copy with a new SongId and createdInApp source can be written, and the original stays untouched'` |
| A7 | `test/features/songs/import/editor_keyboard_flow_test.dart::'moving a section down/up works via a button tap, without any drag gesture'` + `'every reorder affordance meets the >= 48 dp touch target (inclusive)'` |
| A8 | `test/features/songs/import/editor_draft_test.dart::'A8: leaving the editor with unsaved changes names the consequence before the pop is allowed'` |
| A9 | `test/ui/goldens/e13_r24_screens_golden_test.dart::'song import — $suffix'` / `'song import preview — $suffix'` / `'song editor — $suffix'` (`compact`/`compact @2.0×` suffixek) |

**Valódi-sértés próba eredménye (1. lépés, ezen a kör-folytatáson futtatva):**

Sértés: (1) `song_import_preview_screen.dart` — a `FilledButton.onPressed`-ről
levéve a `fatal ? null : …` feltétel (mindig aktív); (2) `song_import_screen.dart`
— a `failure` fázisra egy megerősítő `FilledButton` (`songImportConfirm`
szöveggel) visszatéve a „Choose a file" gomb elé.

Diff: `git diff --shortstat` → **`2 files changed, 10 insertions(+), 4
deletions(-)`**.

`~/flutter/bin/flutter test test/features/songs/import/import_blocking_error_test.dart`
eredménye: **`00:01 +2 -2`** — a négy cellából a két A3-producer cella váltott
pirosra, névvel:

- `above threshold (a): a fatal.-prefixed preview warning disables confirm and
  looks/reads distinct from a warning` — `Expected: null / Actual:
  <Closure: () => void>` (a letiltás megszűnt).
- `above threshold (b): the real SongImportPhase.failure + failureCode names
  the blocking error and offers zero confirm/"continue anyway" affordance` —
  `Expected: no matching candidates / Actual: … Text("Import song")` (a
  visszatett megerősítő gomb megjelent).

A `'below threshold'` és `'at threshold'` cellák zöldek maradtak (nem érintik
a sértett ágat) — ez a mérce elvárt, célzott viselkedése.

Visszaállítás: `git checkout -- lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart lib/features/song_trainer/presentation/screens/song_import_screen.dart`
— utána `git status --short` üres, megerősítve.

**`tools/round-gate.sh` eredménye (a §7 szerinti 15 tesztúttal):** **MINDEN
GATE ZÖLD**, 20 lépés (`format`, `analyze`, 15× `test <fájl>`, `architecture`,
`secrets`, `l10n`). A 15 teszt-lépés összesen **95 zöld tesztet** futtatott
(2+4+3+3+6+1+1+1+2+2+22+44+1+2+1, fájlonként a fenti sorrendben). Az `analyze`
első futása két lelettel jelzett a gate teszt-fájljaiban
(`unnecessary_underscores` az `editor_keyboard_flow_test.dart`-ban, egy
használaton kívüli import a golden-tesztben) — mindkettőt a kör saját,
listán lévő fájljában javítottam (`b536d0c3`), utána a teljes gate
másodszorra zöld.

**Hat golden PNG** (`test/ui/goldens/goldens/`, korábbi commitban rögzítve
x86_64-en, `tools/golden-x86.sh record`):

- `e13_r24_song_import_compact.png`
- `e13_r24_song_import_compact_scale2.png`
- `e13_r24_song_import_preview_compact.png`
- `e13_r24_song_import_preview_compact_scale2.png`
- `e13_r24_song_editor_compact.png`
- `e13_r24_song_editor_compact_scale2.png`

**Mért korlátok:** nincs — a kör mind a §6 acceptance-celláit, a §0.0/B
revíziós pontjait és a valódi-sértés próbát teljesítette a jelen
folytató-futáson.

### Javító kör (review-leletek) — 2026-08-26, `docs/reviews/e13-r24-review.md`

**MAJOR-1 — az A7 érintési-cél cellája.** A reviewer mérése helyes volt: ezen
a témán a Material 3 `IconButton` `MaterialTapTargetSize.padded`
alapértelmezése a render-/hit-test-boxot MINDIG 48×48-ra fújja fel,
függetlenül a `constraints:` paramétertől — a `tester.getSize(...)` ÉS a
`tester.getSemantics(...).rect` egyaránt szerkezetileg konstans 48×48
(reprodukálva: `constraints` eltávolítva → `getSize=Size(48.0, 48.0)`,
`semantics.rect=Rect.fromLTRB(0.0, 0.0, 48.0, 48.0)`; `constraints` 32-re
állítva → ugyanaz). A cella ezért mostantól az `IconButton.constraints`
tulajdonságra mér — ez az egyetlen érték, amit `SongSectionEditor` ténylegesen
birtokol és ami regresszálhat:

```dart
expect(constraints, isNotNull, reason: '… must declare an explicit minimum touch-target constraint');
expect(constraints!.minWidth, greaterThanOrEqualTo(48.0), reason: '… minWidth');
expect(constraints.minHeight, greaterThanOrEqualTo(48.0), reason: '… minHeight');
```

Piros/zöld bizonyíték (mind a hat gombra, `47.0`/`48.0`/`56.0`/eltávolítva
végigsöpörve, a production kódon élesben, majd visszaállítva):

| Bemenet (`constraints:` a production kódban) | Cella eredménye |
|---|---|
| `47.0` (mindkét irányban) | **PIROS** — `Expected: a value greater than or equal to <48.0> / Actual: <47.0> / [<'song-editor-section-move-up-0'>] minWidth` |
| `48.0` (a küszöbön) | zöld (`00:01 +3: All tests passed!`) |
| `56.0` | zöld (`00:01 +3: All tests passed!`) |
| eltávolítva (`constraints` param nélkül) | **PIROS** — `Expected: <true> / Actual: <false> / […] must declare an explicit minimum touch-target constraint` |

A doc-comment a `song_section_editor.dart`-ban átírva: a korábbi „the default
constraints do not guarantee it" állítás (a P1 próba szerint hamis) helyett
most azt mondja ki, amit ténylegesen mértünk — a téma alapértelmezése már
önmagában 48×48-ra hízlalja a gombot, a `constraints:` a deklarált szerződés,
amit a cella közvetlenül olvas, és ami egy jövőbeli téma-váltás (pl.
`shrinkWrap` tap-target méret) esetén is védelmet ad.

**MINOR-1 — `_canPersist()` memoizálva.** `_SongEditorScreenState` három
instance-mezőt kapott (`_canPersistCacheKey`, `_canPersistCacheValue`,
`_canPersistCacheComputed`); `build()` mostantól `_canPersistMemo(...)`-t hív,
ami csak akkor futtatja újra `_canPersist()`-et (és vele a
`SongValidator().validate()`-et), ha `state.persisted` IDENTITÁSA
(`identical`) változott az előző híváshoz képest — nem a tartalma. A
`song_editor_screen_test.dart` két cellája (undo/redo, szerkesztési műveletek)
zöld maradt, tehát a viselkedés nem változott.

**MINOR-2 — `_saveCopy` sorrendje javítva + új cella.** A `song_editor_screen.dart`
`_saveCopy`-ja a `save()` után most ELLENŐRZI az eredményt
(`SongEditorStatus.validationFailed`/`failure`/`conflict`), és hiba esetén
`controller.load(id)`-val VISSZAÁLLÍTJA az eredeti, érintetlen dokumentumot —
a `save()` sosem hív `repository.update()`-et az eredetin (A6), ezért az
újratöltés mindig biztonságos. Új cella (`editor_draft_test.dart`,
`'MINOR-2: saving a copy that is still fatal writes nothing and restores the
editor to the untouched original'`) az A6-tal AZONOS fixture-t használ, de
kihagyja az in-editor javítást (`addChord`) — a másolat így ugyanazt a
fatális hibát viszi tovább, amit az eredeti hordoz.

Piros/zöld bizonyíték (a régi, javítás előtti sorrenden reprodukálva —
`controller.startNew(copy); await controller.save();` a visszaállítás
nélkül —, majd visszaállítva):

- **PIROS** a régi sorrenden: `Expected: SongId:<SongId(legacy-fatal-unfixed)> / Actual: <null>` (`editorController.state.persisted?.id` assertion).
- **ZÖLD** a javított sorrenden: `00:03 +4: All tests passed!` (mind a négy
  `editor_draft_test.dart` cella, A5/A6/MINOR-2/A8).

**MINOR-3 — nyers `TextStyle(color: …)` → téma-token.** Mindhárom hely
(`song_import_screen.dart`, `song_import_preview_screen.dart`,
`song_editor_screen.dart`) `Theme.of(context).textTheme.bodyMedium?.copyWith(
color: …)` alakra cserélve. A golden-teszt (`e13_r24_screens_golden_test.dart`)
mind a hat cellája ZÖLD maradt a csere után (`00:02 +6: All tests passed!`) —
a hibaszínű szöveg egyik golden alapállapotban sem látszik (a hibaágak nem
aktívak az alap-nézetben), ezért nincs golden-elmozdulás és nincs
újrafelvétel.

### Javító kör — teljes kapu (a brief §7 listájával, csővezeték nélkül)

```
tools/round-gate.sh test/features/songs/import/import_flow_test.dart test/features/songs/import/import_blocking_error_test.dart test/features/songs/import/editor_draft_test.dart test/features/songs/import/editor_keyboard_flow_test.dart test/ui/goldens/e13_r24_screens_golden_test.dart test/ui/ui_inventory_test.dart test/features/song_trainer/presentation/song_import_screen_test.dart test/features/song_trainer/presentation/song_import_preview_screen_test.dart test/features/song_trainer/presentation/song_editor_screen_test.dart test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart test/app/routing/app_router_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**MINDEN GATE ZÖLD**, 20 lépés (`format`, `analyze`, 15× `test <fájl>`,
`architecture`, `secrets`, `l10n`). A 15 teszt-lépés összesen **96 zöld
tesztet** futtatott (2+4+4+3+6+1+1+1+2+2+22+44+1+2+1, fájlonként a fenti
sorrendben) — eggyel több, mint a review előtti futáson, a `editor_draft_test.dart`
MINOR-2 cellájával. A `format` és `analyze` első próbálkozásra zöld volt,
második gate-futás nem kellett.

### Javító kör #2 (MAJOR-2) — 2026-08-26, `docs/reviews/e13-r24-review.md` §6.2

**A hiba.** Az 1. javító kör `_saveCopy`-javítása hiba esetén
`await controller.load(id)`-t hívott, hogy a szerkesztőt visszaállítsa az
eredetire. A `load()` viszont `_publishReady(document, document)`-et
publikál, azaz a **draftot IS** a lemezről olvasott dokumentumra állítja — a
felhasználó minden mentetlen szerkesztése (pl. cím-átírás) ezzel
megsemmisült, miközben semmi nem íródott ki (`createCalls == 0`). A
`SongEditorController` az `application/**` tiltott zónában van, ezért a
javításnak a **képernyő** rétegében, a controller MEGLÉVŐ publikus API-jával
kellett megszületnie.

**A javítás két, egymást kiegészítő ág `song_editor_screen.dart`-ban:**

1. **Kliens-oldali előzetes validáció** (`_saveCopy`, `SongValidator` +
   `SongCapabilityResolver` — már importált domain szolgáltatások, a meglévő
   `_canPersist(SongDocument?)` segédfüggvény újrahasznosítva). A másolat
   (`copy`) PONTOSAN a `draft` tartalmát hordozza, csak más `id`/`source`/
   `revision` alatt — ha a `draft` fatálisan hibás, a `copy` IS az lesz. Ezt
   a `controller.startNew(copy)` meghívása ELŐTT ellenőrizzük: ha
   `!_canPersist(copy)`, a controllerhez egyáltalán nem nyúlunk (nincs
   `startNew`, nincs `save()`) — a `persisted` és a `draft` a gombnyomás
   előtti állapotban marad, tehát a felhasználó szerkesztése garantáltan
   megmarad, és a Save zárolt marad (`canPersist(persisted)` a régi,
   validátor-fatális eredetire számol, változatlanul `false`). A bukás okát
   egy `SnackBar` nevesíti (`l10n.songEditorInvalid`).
2. **Képernyő-szintű zároló jelző a repository-hiba ágra**
   (`_SongEditorScreenState._copyWriteFailed`). Ha a másolat átment a
   kliens-oldali validáción, de a `repository.create()` mégis elbukik
   (I/O-hiba) — ezt a kliens-oldali ellenőrzés NEM tudja előre jelezni —, a
   `controller.state.persisted` a `startNew` miatt `null` marad, és
   `_canPersist(null)` mindig `true`. Mivel a controllernek nincs publikus
   API-ja a `persisted` önálló visszaállítására anélkül, hogy a `draft`-ot is
   felülírná (`load()` ezt tenné), a képernyő egy saját, `setState`-tel
   vezérelt boolean-t tart karban (`onCopyWriteFailed` callback, `_EditorBody`
   új konstruktor-paramétere): amíg igaz, a Save zárolt marad és a „Save
   copy" sáv látható marad, függetlenül a controller `persisted`-jétől. A
   jelző automatikusan törlődik, amint `state.persisted` újra nem `null`
   (sikeres mentés vagy friss `load`). A `draft` ezen az ágon is érintetlen
   marad, mert `save()` hibán sosem írja felül.

**Megerősített cella** (`test/features/songs/import/editor_draft_test.dart`,
`'MAJOR-2: a failed copy attempt never discards an edit the user made before
saving'`) — a MINOR-2 fixture-jét bővíti egy cím-átírással a „Save copy"
koppintás ELŐTT (a fatális hivatkozást szándékosan javítatlanul hagyva):

- `repository.createCalls` üres marad (semmi nem íródott ki);
- `editorController.state.draft!.metadata.title` a koppintás UTÁN IS
  `'My careful rename'` — NEM esik vissza `'Legacy Song'`-ra;
- a `SnackBar` a `songEditorInvalid` szöveget mutatja;
- a Save gomb `onPressed` `null` (zárolt marad);
- a „Save copy" gomb újra elérhető.

A meglévő MINOR-2 cella (amely NEM szerkeszt a másolás előtt) VÁLTOZATLAN
maradt és zöld — mivel ezen a fixture-ön a kliens-oldali előzetes ellenőrzés
a `controller.startNew`-t sosem hívja meg, a `persisted`/`draft` a gombnyomás
előtti (eredeti) állapotban marad, ami pontosan megegyezik a cella meglévő
`persisted?.id == id` / `draft?.id == id` állításaival.

**Piros/zöld bizonyíték** (az 1. javító kör régi, `controller.load(id)`-t
hívó ágát ideiglenesen visszaállítva, a kliens-oldali előzetes ellenőrzés
NÉLKÜL, majd visszaállítva):

- **PIROS** a régi ágon (`flutter test test/features/songs/import/editor_draft_test.dart`):
  ```
  MAJOR-2: a failed copy attempt never discards an edit the user made before saving [E]
  Expected: 'My careful rename'
    Actual: 'Legacy Song'
     Which: is different.
            Expected: My careful ...
              Actual: Legacy Son ...
                      ^
             Differ at offset 0
  00:03 +3 -1: MAJOR-2: a failed copy attempt never discards an edit the user made before saving [E]
  ```
  (a régi ág ráadásul a `context`/`onCopyWriteFailed` paramétereket
  kihasználatlanul hagyta — ez csak analyzer-figyelmeztetés, a tesztfutást
  nem érintette.)
- **ZÖLD** a javított ágon: `00:03 +5: All tests passed!` (mind az öt
  `editor_draft_test.dart` cella: A5/A6/MINOR-2/MAJOR-2/A8).

**`tools/round-gate.sh` eredménye (a brief §7 szerinti 15 tesztúttal,
csővezeték nélkül):** **MINDEN GATE ZÖLD**, 20 lépés. A 15 teszt-lépés
összesen **97 zöld tesztet** futtatott
(2+4+5+3+6+1+1+1+2+2+22+44+1+2+1 — az `editor_draft_test.dart` +4 → +5-re nőtt
az új MAJOR-2 cellával; a `song_editor_screen_test.dart` a `_EditorBody`
konstruktorának bővülésével is zöld maradt). A `format` és `analyze` első
próbálkozásra zöld volt.

## 11. Review — a Claude tölti ki

**Verdikt: APPROVED** — 0 nyitott lelet. Teljes jelentés:
[`docs/reviews/e13-r24-review.md`](../reviews/e13-r24-review.md).

A review **két javító kört** kért; mindkét MAJOR **teljesen zöld kapu mögött**
élt, és mindkettőt a reviewer eldobható próbatesztjei találták meg:

| Lelet | Mit mértem | Állapot |
|---|---|---|
| **MAJOR-1** | az A7 érintési-cél cellája a `constraints` 48→32 cseréjére ÉS teljes eltávolítására is ZÖLD maradt — `tester.getSize(IconButton)` a Material `MaterialTapTargetSize.padded` miatt konstans `Size(48.0, 48.0)` (a belső `ConstrainedBox` 40×40). A cella a Material alapértelmezését mérte, nem a kör kódját ([L477](../LESSONS.md#l477); a sáv harmadik érintési-cél lelete, [L496](../LESSONS.md#l496)) | **ZÁRVA** — a cella az `IconButton.constraints`-re mér, bizonyítottan piros `32.0`-nál és `null`-nál |
| **MAJOR-2** (a javító kör vezette be) | a `_saveCopy` hiba-ága `controller.load(id)`-t hívott, ami a **draftot is** felülírta: `"My careful rename"` → `"Legacy Song"`, `createCalls = 0` — az [ADR 0284](../adr/0284-import-preview-is-not-a-commit.md) §Döntés 4 tiltott néma munkavesztése | **ZÁRVA** — a másolat validációja a controller érintése ELŐTT fut; a draft egyik ágon sem íródik felül |
| MINOR-1/2/3 | per-build validáció (mérve 0,53–0,65 ms), `_saveCopy` sorrend, nyers `TextStyle` | **ZÁRVA** |
| NOTE-1/2/3 | expanded több-paneles elrendezés (follow-up), A1/A2 az application réteget méri, `DateTime.now()` a presentationben | nyitva, **nem blokkol** |

**Reviewer-bizonyíték:** a `tools/round-gate.sh` **20/20 ZÖLD, 97 teszt** — HÁROM
különböző, friss izolált `/tmp` klónban futtatva (a review minden fordulójában
újra), nem az implementer kimenetének elfogadásával. Scope-audit:
`OK (3b88f75792f8..08b7b13c4081, 21 changed path(s), 1 generated/ignored)`.

