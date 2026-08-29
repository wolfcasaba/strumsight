# E15-R05 — Song Trainer képernyők migrálása

- **Státusz:** READY (előre megírva 2026-08-28 `main @ 4cb32eb0`-n; pre-flight
  revízió — §0.0/R1–R11 — MÉRVE `main @ 4c22d973`-on, 2026-08-29)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 5
- **Kör-azonosító:** `E15-R05`
- **Branch:** `<motor>/e15-r05-song-trainer-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "song trainer editor overview result setup UI migration"` → **[ADR 0125](../adr/0125-song-trainer-setup-configuration-boundary.md)** (a setup-konfiguráció határa) és **[ADR 0092](../adr/0092-song-trainer-practice-engine-integration.md)** (Song Trainer × Practice Engine integráció) — a migráció EZEKET a határokat nem mozdíthatja.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/song_trainer/presentation/screens/song_trainer_screen.dart lib/features/song_trainer/presentation/screens/song_overview_screen.dart lib/features/song_trainer/presentation/screens/song_result_screen.dart lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart lib/features/song_trainer/presentation/screens/setlist_session_screen.dart lib/features/song_trainer/presentation/screens/song_editor_screen.dart lib/features/song_trainer/presentation/screens/song_import_screen.dart lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart lib/features/song_trainer/presentation/screens/song_library_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **9** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

A sáv legnagyobb egyetlen batch-e (kilenc képernyő), és a dal-gyakorlás teljes útját fedi: könyvtár → áttekintés → setup → futás → eredmény, plusz az import és a szerkesztő.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/presentation/screens/song_trainer_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_overview_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_result_screen.dart",
  "lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart",
  "lib/features/song_trainer/presentation/screens/setlist_session_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_editor_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_import_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_library_screen.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/song_trainer/application/setlists/setlist_session_controller_test.dart",
  "test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart",
  "test/features/song_trainer/presentation/song_editor_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_preview_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_screen_test.dart",
  "test/features/song_trainer/presentation/song_library_screen_test.dart",
  "test/features/song_trainer/presentation/song_overview_screen_test.dart",
  "test/features/song_trainer/presentation/song_result_screen_test.dart",
  "test/features/song_trainer/presentation/song_trainer_accessibility_test.dart",
  "test/features/song_trainer/presentation/song_trainer_screen_test.dart",
  "test/features/song_trainer/presentation/trainer_setup_screen_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/song_asset_state_test.dart",
  "test/features/songs/song_library_test.dart",
  "test/features/songs/trainer/playback_only_result_test.dart",
  "test/features/songs/trainer/playhead_loop_sync_test.dart",
  "test/features/songs/trainer/setlist_run_test.dart",
  "test/features/songs/trainer/trainer_setup_test.dart",
  "test/ui/goldens/e13_r23_screens_golden_test.dart",
  "test/ui/goldens/e13_r24_screens_golden_test.dart",
  "test/ui/goldens/e13_r25_screens_golden_test.dart",
  # §0.0/R4 — a batch MIND A 9 képernyőjének VAN goldenje; a migráció ezeket a
  # PNG-ket ÚJRAVESZI a merge-kapu architektúráján (ADR 0426). A negyedik
  # `e13_r23` cella (`setlist_list`, `SetlistListScreenV2`) NEM a batch
  # képernyője — az a két PNG NEM változhat.
  "test/ui/goldens/goldens/e13_r23_song_library_compact.png",
  "test/ui/goldens/goldens/e13_r23_song_library_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r23_song_overview_compact.png",
  "test/ui/goldens/goldens/e13_r23_song_overview_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r24_song_editor_compact.png",
  "test/ui/goldens/goldens/e13_r24_song_editor_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r24_song_import_compact.png",
  "test/ui/goldens/goldens/e13_r24_song_import_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r24_song_import_preview_compact.png",
  "test/ui/goldens/goldens/e13_r24_song_import_preview_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r25_trainer_setup_compact.png",
  "test/ui/goldens/goldens/e13_r25_trainer_setup_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r25_song_trainer_stage_compact.png",
  "test/ui/goldens/goldens/e13_r25_song_trainer_stage_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r25_song_result_compact.png",
  "test/ui/goldens/goldens/e13_r25_song_result_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r25_setlist_run_compact.png",
  "test/ui/goldens/goldens/e13_r25_setlist_run_compact_scale2.png",
  # §0.0/R6 — a §3/§5.3 megengedi az ÚJ ARB-kulcsot (mindkét locale-ra), és az
  # A6 a `song_trainer_screen.dart` HAT mért beégetett angol mondata miatt NEM
  # teljesíthető ARB-írás nélkül.
  # §0.0/R12 JAVÍTÁS: a `lib/l10n/app_{en,hu}.arb` GENERÁLT kimenet
  # (`tool/gen_l10n_segments.dart`), a valódi forrás a `lib/l10n/base/` — az
  # R6 eredetileg a generált fájlokat írta a listára, ami az A6-ot
  # elvégezhetetlenné tette. A listán ezért a FORRÁS van.
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r05-song-trainer-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  # §0.0/R7 — az A6 bizonyítéka: új ARB-kulcs mindkét locale-ban.
  "test/l10n/arb_parity_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/song_trainer/application/setlists/setlist_session_controller_test.dart",
  "test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart",
  "test/features/song_trainer/presentation/song_editor_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_preview_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_screen_test.dart",
  "test/features/song_trainer/presentation/song_library_screen_test.dart",
  "test/features/song_trainer/presentation/song_overview_screen_test.dart",
  "test/features/song_trainer/presentation/song_result_screen_test.dart",
  "test/features/song_trainer/presentation/song_trainer_accessibility_test.dart",
  "test/features/song_trainer/presentation/song_trainer_screen_test.dart",
  "test/features/song_trainer/presentation/trainer_setup_screen_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/song_asset_state_test.dart",
  "test/features/songs/song_library_test.dart",
  "test/features/songs/trainer/playback_only_result_test.dart",
  "test/features/songs/trainer/playhead_loop_sync_test.dart",
  "test/features/songs/trainer/setlist_run_test.dart",
  "test/features/songs/trainer/trainer_setup_test.dart",
  # §0.0/R3 — BASE-lelet: a három golden-teszt-fájl NEM a lokális ARM-kapuban
  # fut (ADR 0426). `main @ 4c22d973`-on, kör-változtatás NÉLKÜL a 20 cellából
  # 2 PIROS (`e13_r23_song_library_compact` és `…_scale2`, 0,19% / 728 px
  # raszter-drift, L516). A golden-sáv mércéje ezért:
  #   tools/golden-x86.sh check test/ui/goldens/e13_r23_screens_golden_test.dart \
  #                             test/ui/goldens/e13_r24_screens_golden_test.dart \
  #                             test/ui/goldens/e13_r25_screens_golden_test.dart
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff felhasználói felületet ír át azon az úton, amit a felhasználó a leggyakrabban jár; egy elveszett állapot- vagy hibajelzés némán rontaná az élményt. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása a review-ban KÖTELEZŐ.

### 0.0 Pre-flight revízió — MÉRVE `main @ 4c22d973` (2026-08-29, orchestrátor)

Minden alábbi állítás ezen a fán, ezen a boxon mért. A revízió a kör SAJÁT,
még nem merge-elt briefjét érinti (ADR 0087 §2), és a listát **nem tágítja**
a feladat felé — az ARB-pár és a golden-PNG-k a MÁR előírt §5.3/§7
követelmények elvégezhetőségéhez kellenek.

**R1 — mind a 9 képernyő MÉG legacy, a §3 scope változatlan.** A brief §7
mérő-parancsa `main @ 4c22d973`-on kilencszer `legacy`-t ad. Kiindulási arány:
`96` képernyőből `51` migrált (mérve: `find lib/features -name '*_screen.dart'`
+ `grep -q design_system`), tehát a kör CÉLARÁNYA **60/96 (62,5%)**.

**R2 — a brief három komponens-neve a fán NEM létezik.** Mérve
(`grep -rhoE "^(final )?class (Ss[A-Za-z0-9_]+)" lib/core/design_system/`):

| Brief-beli név | Létezik? | A valódi név |
|---|---|---|
| `SsCard`, `SsButton`, `SsEmptyState` | igen | — |
| `SsListTile` | **nem** | `SsContentCard` (lista-sor szerep) |
| `SsErrorState` | **nem** | `SsFailureState` |
| `SsMetricTile` | **nem** | `SsMetricCard` |

A §3, §5.2 és §6.1 ennek megfelelően javítva. Ez ugyanaz a lelet, mint az
E15-R04/§0.0/R10 — a Ch15 előre megírt briefjei mind a nem létező neveket
hordozzák.

**R3 — BASE-lelet: a golden-sáv ezen a boxon NEM mérhető, a §7 kapu-sora
ezért nem tartalmazza.** Mérve, a kör előtti fán, az előkészített klónban:

```
flutter test test/ui/goldens/e13_r23_screens_golden_test.dart \
             test/ui/goldens/e13_r24_screens_golden_test.dart \
             test/ui/goldens/e13_r25_screens_golden_test.dart
→ 00:06 +18 -2: Some tests failed.
  e13_r23_screens_golden_test.dart: song library — compact
  e13_r23_screens_golden_test.dart: song library — compact_scale2
  Golden "goldens/e13_r23_song_library_compact_scale2.png":
    Pixel test failed, 0.19%, 728px diff detected.
```

Ez **nem** a kör hibája: aarch64 ↔ x86 raszter-drift (L516), a PNG-k a
merge-kapu architektúráján készültek (ADR 0426). A három golden-teszt-fájl
ezért KIKERÜLT a `gate_tests`-ből és a §7 `round-gate.sh` sorából; a
golden-sáv a `tools/golden-x86.sh check|record` úton mérendő — ugyanaz a
`LocalFileComparator`, ugyanaz a golden-készlet, a CI architektúráján.

**R4 — mind a 9 képernyőnek VAN goldenje, a 18 PNG felkerült a listára.**
Mérve (`grep -rl <osztálynév> test/ui/goldens/*.dart`): `song_library` +
`song_overview` → `e13_r23`; `song_editor` + `song_import` +
`song_import_preview` → `e13_r24`; `trainer_setup` + `song_trainer_stage` +
`song_result` + `setlist_run` → `e13_r25`. A negyedik `e13_r23` cella
(`setlist_list`, `SetlistListScreenV2`) NEM a batch képernyője — a
`e13_r23_setlist_list_compact*.png` páros NEM változhat.

**R5 — a `*ThemeScope`-eltávolítás ebben a batchben NO-OP.** Mérve:
`grep -c ThemeScope` mind a 9 fájlon **0**. Ugyanígy `AppColors`/`AppPalette`:
mind a 9 fájlon **0** — a §2 „a stílusuk … `AppColors` / `AppPalette`
hivatkozásokból jön" állítása MÉRVE téves, a forrás kizárólag
`Theme.of(context)` (0–4 hívás fájlonként). A migráció tehát tiszta
`Theme.of` → `Ss*` csere, burkoló-bontás nélkül.

**R6 — BASE-lelet: az A6 bizonyítéka nem létezik, és a `song_trainer_screen`
ma is sérti az A6-ot.** Két külön mérés:

1. A brief az A6-hoz a `test/l10n/hardcoded_string_guard_test.dart`-ot jelöli
   bizonyítéknak. A teszt hatóköre MÉRVE **kizárólag**
   `lib/core/design_system/{components,accessibility,layouts,motion}`
   (`_scopeDirs`, a fájl 19–24. sora) — a `lib/features/**` egyetlen sorát sem
   nézi. Ez a cella tehát a batchre **nem** bizonyíték.
2. Ugyanez a minta kézzel a 9 képernyőn HAT beégetett, felhasználónak szóló
   angol mondatot mér ki, mind a `song_trainer_screen.dart`-ban:
   `173: 'Song Trainer'` · `188: 'Count-in'` · `252: 'Speed'` ·
   `266` és `345: 'Speed disabled — backing cannot change rate.'` ·
   `346: 'Paused: speed resumes when the session restarts.'` ·
   `406: 'Failed: $failure'`.

Ezért az A6 **kötelező kimenete**: ez a hat szöveg ARB-kulcsot kap `en`-re ÉS
`hu`-ra, a képernyő `l10n.<kulcs>`-ot használ, és a §7 pótló mérése üresen tér
vissza. Az `lib/l10n/app_en.arb` + `app_hu.arb` emiatt van az
`allowed_paths`-on, a `test/l10n/arb_parity_test.dart` pedig a `gate_tests`-en.

**Nem tartozik a kötelező körbe** (mérve, de pre-existing és NEM tiszta
literál): `trainer_setup_screen.dart:179 Text('$bars')` (szám, nem mondat) és
`song_import_preview_screen.dart:33 Text('${l10n.songImportFormat}: …')`
(ARB-fragmens + dinamikus érték összefűzése). Ha az implementer a másodikat
mégis rendezi, az placeholderes ARB-kulcs MINDKÉT locale-ra — de a kör nem
bukik el nélküle.

**R7 — a `gate_tests` kiegészült az `arb_parity_test.dart`-tal**, mert az R6
új ARB-kulcsokat ír elő; a `ui_inventory_test.dart` marad (A5).

**R8 — a `setlist_session_screen.dart` MÉRVE elérhetetlen, mégis a scope-ban
marad.** `grep -rn SetlistSessionScreen lib/` egyetlen találata a saját
definíciója; a `retirement-plan.md:258` `unreachable` verdiktje áll. A
scope-ban tartás indoka MÉRT, nem feltételezés: a képernyőnek VAN
teszt-fedezete (`setlist_run_test.dart`,
`setlist_session_controller_test.dart`, `e13_r25` golden), tehát a migráció
ellenőrizhető, a fájljai pedig már a brief listáján vannak. Az ADR 0471 D7 az
elérhetetlen képernyők **automatikus törlését** tiltja, nem a migrálásukat —
és a kör semmit nem töröl. A §2 „lista-szűkítés" jogát ezért nem használom.

**R9 — a `retirement-plan.md` §4 kör-oszlopa eltolódik ehhez a briefhez.** A
terv §4 táblája ezt a 8 Song Trainer képernyőt az `E15-R09` sorhoz rendeli, az
`E15-R05` sorhoz pedig az AI Tutort — a queue és a megírt briefek viszont
`E15-R05` = Song Trainer, `E15-R09` = AI Tutor. Ugyanaz az eltolódás, amit az
E15-R04 a `migration-status.md`-ben már dokumentált. A `migrate` DÖNTÉS
változatlan, csak a végrehajtó kör száma más. A `retirement-plan.md` ezen a
listán NINCS — a korrekció a `migration-status.md`-be megy, a tervet a kör nem
szerkeszti.

**R10 — hét nyers `CircularProgressIndicator` a batchben** (mérve, fájlonként:
`song_trainer`, `song_overview`, `trainer_setup`, `setlist_session`,
`song_editor`, `song_import`, `song_library` — egy-egy). Az §5.2 szerint
mindegyik a design-rendszer betöltés-komponensére (`SsSkeleton`, vagy
`SsAsyncState`, ha a képernyő már azon a mintán van) kerül.

**R11 — L536 eljárási őr.** A `test/ui/goldens/failures/**` NEM KÖVETETT,
generált artefaktum, amit a gépi scope-audit a diffnek számol (E15-R02: 60 PNG
→ hamis `VIOLATION`). Az orchestrátor pre-flightja a fenti R3-mérés után már
törölte; a `done` jelzés ELŐTT kötelező: `rm -rf test/ui/goldens/failures`.

**R12 — az R6 ARB-útvonala HIBÁS volt, javítva (orchestrátor, a review során).**
Az `lib/l10n/app_en.arb` / `app_hu.arb` MÉRVE **generált** kimenet: a
`tool/gen_l10n_segments.dart` állítja elő a `lib/l10n/base/app_<locale>.arb` és
a `lib/l10n/features/<feature>_<locale>.arb` szegmensek determinisztikus
uniójaként; a közvetlen szerkesztést a kapu `l10n` lépése visszaírja. A
`songTrainer*` kulcsok valódi forrása a `lib/l10n/base/app_{en,hu}.arb`
(mérve: 28-28 `songTrainer` kulcs). Az R6 emiatt az A6-ot elvégezhetetlenné
tette, és az implementer kényszerből MÁS jelentésű, meglévő kulcsot használt
föl (lásd a review F1 leletét). Az `allowed_paths` a FORRÁST kapja meg — ez a
brief §3-ban prózában MÁR megadott jogosultság (`új kulcs FELVEHETŐ …
mindkét locale-ra`) helyes fájlra irányítása, nem a tilos zóna (§4) feloldása:
a `lib/l10n/**` a tiltólistán nincs rajta. A két generált útvonal lekerült.

**Visszakeresés (ADR 0312, KÖTELEZŐ).** `--corpus lessons,halts,adr`:
[L517](../LESSONS.md#l517) (a `textScaler 2.0` keret VALÓDI, addig láthatatlan
elrendezési hibát mér — köztük a kör ELŐTTI kódban),
[L524](../LESSONS.md#l524) (a PNG nélküli variáns-mátrix erősebb mérce, mint
újabb goldenek), [L516](../LESSONS.md#l516) (ARM↔x86 raszter-drift),
[L536](../LESSONS.md#l536) (a golden-`failures/` hamis scope-sértése),
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md),
[ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md),
[ADR 0125](../adr/0125-song-trainer-setup-configuration-boundary.md),
[ADR 0129](../adr/0129-song-trainer-ui-loop-speed-and-result-boundary.md),
[ADR 0092](../adr/0092-song-trainer-practice-engine-integration.md). A
`halts/round-status-E15-R04` merge-elt köre adja a §6.1 három új
falszifikációs sorát: a KÖZVETLENÜL előző, azonos alakú migrációs kör
mindhárom MAJOR-ja ugyanabból a mintából jött (a migráció átlépte a §0.0
határt), ezért itt gépi mérce fogja őket (§7).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a migrációhoz egy `application/`, `domain/` vagy `data/` réteg módosítása kellene, a kimenet a `stopped` jelzés — a viselkedés-változás nem ennek a körnek a hatásköre ([L478](../LESSONS.md#l478)).

## 1. Cél

A batch 9 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `song_trainer_screen.dart`, `song_overview_screen.dart`, `song_result_screen.dart`, `trainer_setup_screen.dart`, `setlist_session_screen.dart`, `song_editor_screen.dart`, `song_import_screen.dart`, `song_import_preview_screen.dart`, `song_library_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 9 képernyő vizuális migrálása (`SsCard`, `SsButton`, `SsContentCard`, `SsEmptyState`, `SsFailureState`, `SsMetricCard`, `SsSection`, `SsSkeleton`, `SsStatusBadge` és társaik; `SsSpacing`/`SsRadius`/`SsTypography` tokenek — §0.0/R2: a brief eredeti `SsListTile` / `SsErrorState` / `SsMetricTile` nevei a fán NEM léteznek) · a `song_trainer_screen.dart` hat beégetett mondatának lokalizálása `en`+`hu` ARB-kulccsal (§0.0/R6, A6) · a `migration-status.md` frissítése a MÉRT új aránnyal (és a §0.0/R9 kör-oszlop-korrekcióval). A `*ThemeScope`-eltávolítás ebben a batchben NO-OP (§0.0/R5: nulla burkoló).

Batch-specifikus kikötések:

- a `song_trainer_screen` transzport-vezérlője (lejátszás, hurok, tempó) VISELKEDÉSBEN változatlan — csak a megjelenítés kerül design-rendszer-komponensekre
- a `song_editor_screen` szerkesztési modellje és validációja (ADR 0125 határ) érintetlen
- az import-út két képernyője megtartja a licenc/forrás-jelvényt és a `canPersist == false` lakat-jelzést

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/song_trainer/presentation/screens/song_trainer_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_overview_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_result_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/setlist_session_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_editor_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_import_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_library_screen.dart` | migráció design-rendszer komponensekre |
| `test/app/routing/app_router_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/application/setlists/setlist_session_controller_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_editor_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_import_preview_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_import_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_library_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_overview_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_result_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_trainer_accessibility_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_trainer_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/trainer_setup_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/import/editor_draft_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/import/import_blocking_error_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/song_asset_state_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/song_library_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/trainer/playback_only_result_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/trainer/playhead_loop_sync_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/trainer/setlist_run_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/trainer/trainer_setup_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r23_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r24_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r25_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |

**Tilos zóna:** a batch feature-einek `application/`, `domain/`, `data/`, `providers/` könyvtárai · minden más `lib/features/**` képernyő · `lib/app/**` · `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ÚJ ADR. Három kötelező szabály:

### 5.1 A viselkedés bitre azonos marad

Ugyanaz az adat, ugyanaz a sorrend, ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés, nem migráció.

### 5.2 Minden állapotnak van design-rendszer-megfelelője

Üres lista → `SsEmptyState`, hiba → `SsFailureState`, betöltés → a design-rendszer betöltés-komponense (`SsSkeleton`, vagy `SsAsyncState`, ha a képernyő már azon a mintán van). **NEM elfogadható gyengítés:** nyers `CircularProgressIndicator` (§0.0/R10: hét darab van) vagy csupasz `Text('Hiba')` meghagyása.

**§0.0/R13 pontosítás (orchestrátor-döntés a review-ban, ADR 0087 §2 — a kör
saját, még nem merge-elt briefje).** A design-rendszer komponense a KÖTELEZŐ
alapeset. Kiváltani KIZÁRÓLAG ott szabad, ahol a komponens szerződése MÉRHETŐEN
nem teljesíthető adat- vagy akció-gyártás nélkül — mérve ezen a fán:
`SsFailureState` egy valódi `AppFailure`-ből származó `SsFailurePresentation`-t
kíván (`ss_failure_state.dart:14-22`), miközben ezeknek a képernyőknek
`String? failureCode`-juk van; az `SsEmptyState.onAction` pedig **kötelező**
(`ss_empty_state.dart:11-19`). Mindkét kiváltás a §5.1/G2, illetve a §5.1/G3
sértése volna, a komponens tágítása pedig a §4 tilos zónája
(`lib/core/design_system/**`). Ilyenkor a helyettesítő **kizárólag
design-rendszer tokenekből és primitívekből** épülhet (`SsColorScheme`,
`SsTypography`, `SsSpacing`, `SsCard`, `SsButton` — nyers `Colors.`,
`textTheme`, `colorScheme` vagy literál térköz TILOS), **és két dolog jár
hozzá:** (a) képernyőnkénti indoklás a §10-ben, (b) egy gépi cella, amely
PIROSRA vált, ha az adott állapot visszakerül nyers Materialra (A2). Indoklás
és cella nélkül a kiváltás gyengítés, nem mérnöki döntés. A design-rendszer
alatta lévő hiánya (nincs `AppFailure` nélküli hibaállapot és nincs akció
nélküli üres állapot) BACKLOG egy olyan körnek, amely a
`lib/core/design_system/**`-hoz nyúlhat.

**Három tiltás, amit az E15-R04 MÁR MÉRT MAJOR-ként (a §7 gépi őrei fogják):**

1. **A képernyő-specifikus hibaszöveg nem cserélhető a `SsFailureState`
   generikus szövegére.** Az eddig használt ARB-kulcs a migráció után is
   használatban van; árván maradt kulcs = A2 piros (E15-R04/MAJOR-1).
2. **`AppFailure`-t kézzel gyártani TILOS.** Az `AppResult.fold` `onFailure`-je
   megkapja a valódi hibát — azt kell továbbadni. `onFailure: (_) => …` +
   kitalált `retryable:` érték = A2 piros (E15-R04/MAJOR-2): a
   `SsFailurePresentation` az akciót PONTOSAN a `retryable` mezőre kulcsolja,
   a hamis `true` végtelen „Újra"-hurkot ad.
3. **Új akció vagy navigáció bevezetése TILOS.** `onAction`, `context.go/push`,
   `ref.invalidate` csak akkor kerülhet a migrált kódba, ha a kör ELŐTTI
   ugyanazon a helyen már ott volt = A2 piros (E15-R04/MAJOR-3).

### 5.3 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a migrált kódba; új szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a 9 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
| A2 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei |
| A3 | A képernyők `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderelnek | a batch variáns-cellái |
| A4 | A típus-pinnelő tesztek VÁLTOZATLANUL zöldek, egyetlen cellájuk sem törölt/`skip`-elt | a §7 gate + `git diff` a teszt-fájlokon |
| A5 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN | a §7 gate |
| A6 | Nincs beégetett felhasználói mondat a 9 migrált fájlban — a §0.0/R6 hat mondata ARB-kulcsot kapott `en`-re ÉS `hu`-ra | a §7 **G4** mérése (üres kimenet) + `test/l10n/arb_parity_test.dart` a kapuban. **§0.0/R6:** a `hardcoded_string_guard_test.dart` MÉRVE csak a `lib/core/design_system/**`-ot nézi, a batchre NEM bizonyíték |
| A7 | A `migration-status.md` a MÉRT új arányt (**60/96**) írja, a mérés parancsával, és rögzíti a §0.0/R9 kör-oszlop-korrekciót | a dokumentum |
| A8 | A 18 batch-golden a merge-kapu architektúráján ÚJRA fel van véve és zöld; a két `e13_r23_setlist_list_*` PNG VÁLTOZATLAN | `tools/golden-x86.sh check …` + `git status --short test/ui/goldens/goldens/` |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás, EZ az A3 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A képernyő megkapja a komponenseket, de a hibaállapot nyers `Text` marad | A2 |
| A migráció csak `en` locale-on lett kipróbálva, a hosszabb `hu` szöveg túlcsordul | A3 |
| A migráció közben egy típus-pinnelő teszt cellája `skip`-re kerül a zöldért | A4 |
| Egy szöveg beégetve kerül a kódba | A6 (§7/**G4**) |
| A képernyő importálja a design-rendszert, de a stílus továbbra is `Theme.of(context)`-ből jön | A1 (a mérés a MIGRÁLT/legacy besorolást is ellenőrzi a kód alapján) |
| A képernyő-specifikus hibaszöveg a `SsFailureState` generikus szövegére cserélődik, az ARB-kulcs árván marad (E15-R04/MAJOR-1) | A2 — §7/**G1** kiírja az eltűnt `l10n.` kulcsot |
| Az `AppResult.fold` `onFailure`-je eldobja a valódi `AppFailure`-t, és kézzel gyártott `retryable:`-t ad (E15-R04/MAJOR-2) | A2 — §7/**G2** kiírja a hozzáadott `retryable:` / `*Failure(` sorokat |
| A migráció ÚJ akciót vagy navigációt vezet be egy megjelenés-körben (E15-R04/MAJOR-3) | A2 — §7/**G3** kiírja a hozzáadott `onAction` / `context.go` / `ref.invalidate` sorokat |
| A golden-újrafelvétel a batchen kívüli PNG-t is átír | A8 — `git status --short test/ui/goldens/goldens/` |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cserélj vissza EGY migrált képernyőn egy `SsFailureState`-et nyers `Text`-re, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza. (Ha a gate ettől zöld marad, az azt jelenti, hogy az A2-nek nincs őre azon a képernyőn — akkor a cellát KELL megírni, nem a próbát elhagyni.)

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/l10n/arb_parity_test.dart test/app/routing/app_router_test.dart test/features/song_trainer/application/setlists/setlist_session_controller_test.dart test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart test/features/song_trainer/presentation/song_editor_screen_test.dart test/features/song_trainer/presentation/song_import_preview_screen_test.dart test/features/song_trainer/presentation/song_import_screen_test.dart test/features/song_trainer/presentation/song_library_screen_test.dart test/features/song_trainer/presentation/song_overview_screen_test.dart test/features/song_trainer/presentation/song_result_screen_test.dart test/features/song_trainer/presentation/song_trainer_accessibility_test.dart test/features/song_trainer/presentation/song_trainer_screen_test.dart test/features/song_trainer/presentation/trainer_setup_screen_test.dart test/features/songs/import/editor_draft_test.dart test/features/songs/import/import_blocking_error_test.dart test/features/songs/song_asset_state_test.dart test/features/songs/song_library_test.dart test/features/songs/trainer/playback_only_result_test.dart test/features/songs/trainer/playhead_loop_sync_test.dart test/features/songs/trainer/setlist_run_test.dart test/features/songs/trainer/trainer_setup_test.dart
```

**A golden-sáv NEM ebben a parancsban van** (§0.0/R3, ADR 0426) — a merge-kapu
architektúráján mérjük, a migráció UTÁN újrafelvétellel, majd ellenőrzéssel:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r23_screens_golden_test.dart test/ui/goldens/e13_r24_screens_golden_test.dart test/ui/goldens/e13_r25_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r23_screens_golden_test.dart test/ui/goldens/e13_r24_screens_golden_test.dart test/ui/goldens/e13_r25_screens_golden_test.dart
```

Az újrafelvétel UTÁN `git status --short test/ui/goldens/goldens/` — kizárólag a
§0.0/R4 tizennyolc PNG-je változhat. Ha az `e13_r23_setlist_list_compact.png`
vagy a `…_scale2.png` is változik, az NEM a batch képernyője: állítsd vissza
(`git checkout -- <png>`) és jelentsd. A `done` jelzés ELŐTT kötelező:
`rm -rf test/ui/goldens/failures` (L536, §0.0/R11).

### 7.1 Négy gépi őr — a kimenetük a §10-be MÁSOLVA

A §5.1/§5.2 három tiltását és az A6-ot ezek mérik. `SCREENS` = a §4 kilenc
`lib/**` útvonala.

```bash
SCREENS="lib/features/song_trainer/presentation/screens/song_trainer_screen.dart lib/features/song_trainer/presentation/screens/song_overview_screen.dart lib/features/song_trainer/presentation/screens/song_result_screen.dart lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart lib/features/song_trainer/presentation/screens/setlist_session_screen.dart lib/features/song_trainer/presentation/screens/song_editor_screen.dart lib/features/song_trainer/presentation/screens/song_import_screen.dart lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart lib/features/song_trainer/presentation/screens/song_library_screen.dart"

# G1 — ELTŰNT ARB-kulcs (E15-R04/MAJOR-1). Kötelezően ÜRES.
for f in $SCREENS; do
  comm -23 <(git show origin/main:$f | grep -oE 'l10n\.[A-Za-z0-9_]+' | sort -u) \
           <(grep -oE 'l10n\.[A-Za-z0-9_]+' $f | sort -u) | sed "s|^|$f |"
done

# G2 — kézzel gyártott hiba / retryable (E15-R04/MAJOR-2). Kötelezően ÜRES.
git diff origin/main..HEAD -- $SCREENS | grep -E '^\+' | grep -E 'retryable:|[A-Za-z]+Failure\('

# G3 — ÚJ akció vagy navigáció (E15-R04/MAJOR-3). Minden sorhoz a §10-ben
#      oda kell írni, hol volt ugyanez a kör ELŐTT (`git show origin/main:<f>`).
git diff origin/main..HEAD -- $SCREENS | grep -E '^\+' | grep -E 'onAction|context\.(go|push|pop)\(|ref\.invalidate'

# G4 — beégetett felhasználói mondat (A6). Kötelezően ÜRES.
grep -nE "(Text|label|title|message|hintText|semanticLabel|tooltip)\s*[:(]\s*'[^']{3,}'" $SCREENS
```

`G1`/`G2`/`G4` nem üres kimenete, vagy egy `G3`-sor indoklás nélkül: a kör NEM
kész. A gyengítés (a mintázat átírása, hogy a grep ne fogja) a §0.0 szerinti
cella-gyengítéssel egyenértékű, tehát TILOS.

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/song_trainer/presentation/screens/song_trainer_screen.dart lib/features/song_trainer/presentation/screens/song_overview_screen.dart lib/features/song_trainer/presentation/screens/song_result_screen.dart lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart lib/features/song_trainer/presentation/screens/setlist_session_screen.dart lib/features/song_trainer/presentation/screens/song_editor_screen.dart lib/features/song_trainer/presentation/screens/song_import_screen.dart lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart lib/features/song_trainer/presentation/screens/song_library_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
```

Elvárt kimenet: kilencszer `MIGRATED`, és a teljes fán `60/96`.

## 8. Implementációs sorrend

1. A §0.0 revízió (R1–R11) elolvasása — az a terv; a `retirement-plan.md`
   §4 kör-oszlopát a §0.0/R9 korrigálja.
2. Képernyőnként: komponens-csere → állapotok (üres/betöltés/hiba, §5.2) →
   tokenek. `*ThemeScope`-eltávolítás nincs (§0.0/R5).
3. A `song_trainer_screen.dart` hat beégetett mondata → ARB-kulcs `en`+`hu`
   (§0.0/R6).
4. A batch célzott widget-tesztjei (állapotok + `textScale 2.0` + `en`/`hu`).
5. A §7.1 négy gépi őr futtatása, a kimenet a §10-be.
6. `tools/golden-x86.sh record` + `check` a három golden-fájlra, majd
   `git status --short test/ui/goldens/goldens/` (A8).
7. A migrációs mérés futtatása, `migration-status.md` frissítése (A7).
8. A valódi-sértés próba a §10-be, majd `rm -rf test/ui/goldens/failures`.

## 9. Kockázatok

- **Néma információvesztés.** A migráció közben elveszett állapot vagy mező a leggyakoribb hiba (A2).
- **Locale-vak elrendezés.** A magyar szövegek hosszabbak; az `en`-re szabott elrendezés túlcsordul (A3).
- **Scope-csúszás a viselkedés felé.** Egy „apró" providers-módosítás a kör mérhetőségét rontja (STOP-eset).

## 10. Implementation handoff — az implementer tölti ki

Ez a kör a `docs/reviews/e15-r05-review.md` javító köre: 3 MAJOR + 9 MINOR +
2 NOTE. A migráció maga (9/9 képernyő) az előző körben készült el és
változatlan; ez a kör kizárólag a lelet-listát zárja.

### 10.1 m5 — commitolatlan munka

A 16 fájl (golden-harness `SsDarkTheme.data()` csere + 12 PNG +
`migration-status.md`) az ELSŐ lépésben commitba került
(`7e24892b`), mielőtt bármi mást érintettem volna.

### 10.2 MAJOR-1 — a szünetelt transzport magyarázata

Új ARB-kulcs mindkét locale-ra a `lib/l10n/base/app_{en,hu}.arb`-ban:

```
songTrainerSpeedResumesOnRestart:
  en: "Paused: speed resumes when the session restarts."
  hu: "Szünet: a sebesség a session újraindításakor tér vissza."
```

Ez a kör előtti (`origin/main`) angol mondat szó szerinti megfelelője. A
`song_trainer_screen.dart:376-380` `_PausedBody` `song-trainer-speed-disabled`
csempéjének subtitle-je most ezt írja ki (nem a fölötte lévő
`trainerPausedPosition` duplikátumát), és az elavult „outside this round's
allowed_paths (ADR 0307)" komment törölve/frissítve. A
`test/features/song_trainer/presentation/song_trainer_screen_test.dart` M4
cellája (`:225-243`) mostantól a PONTOS lokalizált szövegre pinnel
(`l10n.songTrainerSpeedResumesOnRestart`), és külön assertálja, hogy a
subtitle NEM egyezik a `trainerPausedPosition` szöveggel — ez a cella pirosra
váltana, ha a duplikátum-regresszió visszatérne.

`dart run tool/gen_l10n_segments.dart --write` + `flutter gen-l10n` lefutott,
hogy a generált `lib/l10n/app_{en,hu}.arb` és `lib/l10n/app_localizations*.dart`
szinkronba kerüljön az új kulcsokkal (a `lib/l10n/app_*.arb` NEM az
`allowed_paths`-on van — §0.0/R12 —, de a `--write` a `lib/l10n/base/`-ból
determinisztikusan generált, nem kézi szerkesztés; a gate `l10n` lépése
ugyanezt a frissességet követeli meg).

### 10.3 MAJOR-2 — A2 gépi cellák (5 mutált csoport + bónusz)

A brief §6.1 kötelező valódi-sértés próbáját pontosan a devil-advocate mérte
5 csoportjára írtam cellát (a meglévő gate-teszt fájlokba, új fájl nélkül),
plusz az Editor betöltés/hiba csoportjára is:

| Csoport | Fájl | Új cella |
|---|---|---|
| `_LibraryLoading`/`_LibraryError`/`_LibraryEmpty` | `song_library_screen_test.dart` | 3 cella: `SsSkeleton` jelenlét, `SsButton` jelenlét, empty-state szöveg token-színe |
| `_TrainerLoading` | `song_trainer_screen_test.dart` | `SsSkeleton` jelenlét idle állapotban |
| `_FailedBody` | `song_trainer_screen_test.dart` | a hibaszöveg `colors.danger` token-színe (a korábbi „failed status" cella érdemi assertion nélkül állt — most valódi) |
| `_OverviewLoading`/`_OverviewError` | `song_overview_screen_test.dart` | 2 cella: `SsSkeleton`, `SsButton` |
| `_SetupLoading`/`_SetupError` | `trainer_setup_screen_test.dart` | 2 cella: `SsSkeleton`, `SsButton` |
| `_EditorLoading`/`_EditorLoadError` (bónusz) | `song_editor_screen_test.dart` | 2 cella: `SsSkeleton`, danger-token szín (a `_EditorLoadError` `Text`-je `song-editor-load-error` kulcsot kapott, hogy egyértelműen megtalálható legyen) |

A hiba-/betöltés-állapotokat egy-egy célzott repository-dupla váltja ki
(`_PendingGetRepository`/`_PendingRepository` sosem teljesülő `Completer`-rel
a betöltéshez, `_FailingGetRepository`/`_ToggleRepository` `AppResult.failure`-t
adó `list`/`get`-tel a hibához) — ugyanaz a Preview-repo minta, amit a projekt
máshol is használ.

**Megjegyzés a Library hiba-cellához:** a `SongLibraryScreen.initState` MINDIG
láncol egy `setQuery()`-t az első `load()` UTÁN, és a `setQuery()`
feltétel nélkül `SongLibraryStatus.ready`-re publikál — emiatt egy induláskor
bukó repository sosem hagyja a widget-fát megfigyelhetően hiba-állapotban (ez
LÉTEZŐ, kör előtti viselkedés, nem érintettem). A cella ezért egy
`ProviderContainer`-rel mountol egy SIKERES repository-val (ugyanazt az utat
járva, mint az induló `initState`), majd egy MÁSODIK, önálló
`controller.load()` hívást indít — pontosan a retry-gomb saját callback-je,
`setQuery` lánc nélkül — egy immár bukó repository ellen. Ez az EGYETLEN út,
ahol a teszt megfigyelhetően eléri a `SongLibraryStatus.failure`-t.

**Kötelező valódi-sértés próba (a `song-trainer-screen.dart` `_TrainerLoading`
widgetén, nyers kimenettel):**

```
$ # mutáció: SsSkeleton -> CircularProgressIndicator a _TrainerLoading.build()-ban
$ flutter test test/features/song_trainer/presentation/song_trainer_screen_test.dart
...
00:01 +5: idle status renders the design-system skeleton, not a raw spinner
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═══════════════════════════
The following TestFailure was thrown running a test:
Expected: at least one matching candidate
  Actual: _TypeWidgetFinder:<Found 0 widgets with type "SsSkeleton": []>
   Which: means none were found but some were expected
...
00:01 +5 -1: idle status renders the design-system skeleton, not a raw spinner [E]
  Test failed. See exception logs above.
Failing tests:
  .../song_trainer_screen_test.dart: idle status renders the design-system skeleton, not a raw spinner
```

Visszaállítás után (`SsSkeleton` vissza):

```
$ flutter test test/features/song_trainer/presentation/song_trainer_screen_test.dart
...
00:01 +11: All tests passed!
```

A próba PIROSRA váltotta a gate-et a mutáción, és ZÖLDre a visszaállítás
után — az A2-nek mostantól van őre ezen a csoporton, és analóg cellák a
másik négy csoporton.

### 10.4 MAJOR-3 — textScaler 2.0, en ÉS hu, mind a 9 képernyőn

| Képernyő | Teszt-fájl | en | hu |
|---|---|---|---|
| `song_trainer_screen` | `song_trainer_accessibility_test.dart` | megvolt (`takeException` is) | ÚJ cella |
| `song_overview_screen` | `song_overview_screen_test.dart` | ÚJ (loop: `en`+`hu`) | ÚJ |
| `song_result_screen` | `song_result_screen_test.dart` | ÚJ (loop) | ÚJ |
| `trainer_setup_screen` | `trainer_setup_screen_test.dart` | megvolt, `takeException` MOST hozzáadva | ÚJ cella |
| `setlist_session_screen` | `setlist_run_test.dart` | ÚJ (loop, `_localizedApp` bővítve `locale` paraméterrel) | ÚJ |
| `song_editor_screen` | `song_editor_screen_test.dart` | ÚJ (loop) | ÚJ |
| `song_import_screen` | `song_import_screen_test.dart` | ÚJ (loop) | ÚJ |
| `song_import_preview_screen` | `song_import_preview_screen_test.dart` | ÚJ (loop) | ÚJ |
| `song_library_screen` | `song_library_screen_test.dart` | ÚJ (loop) | ÚJ |

Minden új/kiegészített cella `expect(tester.takeException(), isNull)`-t mér a
`MediaQueryData(textScaler: TextScaler.linear(2))` alatt, `en`-en ÉS `hu`-n
(`locale: const Locale('hu')`). Két korrekció útközben mérve:

- a `song_overview_screen` Start gombja `ListView`-ban van, és 2×
  szövegskálán a viewporton kívülre kerül — a cella `scrollUntilVisible`-t
  használ, mint a `trainer_setup` már meglévő mintája (a hiányzó scroll nem a
  gomb hiányát jelezte, hanem hogy nem volt görgetve odáig);
- a `song_import_preview_screen` cellája NEM `find.text('Import song')`-ra
  pinnelt (ez `hu`-n lefordított szöveg lenne, tehát mindig bukna), hanem
  `find.byType(SongImportPreviewScreen)`-re.

### 10.5 MINOR-ok

| # | Állapot |
|---|---|
| m1 | §10-jegyzet: a `976b1d55` G2-átnevezés (`_…Failure`→`_…Error`) tartalmilag valódi (mind a négy widget `String? failureCode` fölött), de a G2 mintázatának kikerülése — nem a §7.1 szellemében. NEM neveztem vissza (a review nem kérte), csak dokumentálom. |
| m2 | JAVÍTVA — új `songTrainerSpeedLabel` kulcs (en/hu) a sebesség-csúszka `Semantics(label:)`-jén a Learn feature `learnSpeed` helyett. |
| m3 | §10-jegyzet + komment-frissítés: `songTrainerFailed` („Session failed: {code}") megtartva a pre-migration „Failed: {code}" helyett — a JELENTÉS azonos (hibakód jelentése), a szöveg nem. Saját kulcs helyett a meglévő reuse maradt, mert azonos jelentésű. |
| m4 | §10-jegyzet + komment-bővítés: `setlist_session_screen.dart` 18px `CircularProgressIndicator`-ja szándékosan raw marad — az `SsSkeleton` tartalom-shimmer, nem inline folyamatban-lévő ikon, a csere megváltoztatná, mit közöl az affordance. |
| m5 | JAVÍTVA — lásd 10.1. |
| m6 | JAVÍTVA — ez a §10 szakasz. |
| m7 | JAVÍTVA — `song_trainer_screen.dart` (`_TrainerLoading`, új `songTrainerLoading` kulcs) és `song_library_screen.dart` (`_LibraryLoading`, új `songLibraryLoading` kulcs) betöltés-állapota most `Semantics(label: …)`-ba csomagolva, mint a `song_overview`/`trainer_setup` mintája. |
| m8 | §10-jegyzet: a `titleLarge`→`typography.titleMedium` (song_overview szekció-fejlécek, trainer_setup fejlécek) vs. `titleLarge`→`typography.titleLarge` (song_import_preview fájlnév-cím) eltérés és a dalcím `headlineSmall`→`titleLarge` lefokozása NEM egységesítve — mindkét leképzés önmagában érvényes tipográfiai döntés (szekció-fejléc vs. lapcím-hangsúly), és az egységesítés három képernyő goldenjét mozdítaná egy megjelenés-kör hatáskörén túli, széles vizuális döntéssel. Backlog egy dedikált tipográfia-körnek. |
| m9 | JAVÍTVA — `song_editor_screen.dart:317` a csak-olvasható lakat-ikon `colors.textSecondary`→`colors.warning` (státusz-értékű token, nem díszként olvas). |
| n6 | JAVÍTVA — a hat új privát állapot-widget (`_TrainerLoading`, `_OverviewLoading`, `_OverviewError`, `_SetupLoading`, `_SetupError`, `_EditorLoading`, `_EditorLoadError`, `_LibraryLoading`, `_LibraryError`, `_LibraryEmpty`) `class`→`final class`, a fájl saját stílusához igazítva; az öt `SsSkeleton` hívási hely (`song_trainer`, `song_overview`, `trainer_setup`, `song_editor`, `song_import`) visszakapta a `const`-ot. |
| n7 | JAVÍTVA — `docs/ui/migration-status.md` ARB-forrás bekezdése frissítve: a `lib/l10n/app_*.arb` GENERÁLT (`tool/gen_l10n_segments.dart`), a hivatkozás korábbi „ADR 0307" (ami valójában a pipeline-átbocsátóképesség ADR-je) törölve, a bekezdés a §0.0/R12 forrás-korrekcióval és az új kulcsokkal frissítve. |

### 10.6 §0.0/R13 — képernyőnkénti indoklás a design-rendszer-kiváltásra

Minden helyen, ahol a `_...Error`/`_...Empty` widget NEM `SsFailureState`/
`SsEmptyState`-et használ, hanem képernyő-lokális, kizárólag design-rendszer
tokenekből épült helyettesítőt:

- **`song_trainer_screen` `_FailedBody`** — `state.transportState.lastFailureCode`
  bare `String?`, nem `AppFailure`; a `SsFailureState` `SsFailurePresentation`-t
  (egy valódi `AppFailure`-ből) kíván. Akció nincs a pre-migration állapotban
  sem (bare `Center(Text)` volt) — nem adtam hozzá egyet.
- **`song_overview_screen` `_OverviewError`, `trainer_setup_screen`
  `_SetupError`** — mindkettő a `songTrainerSetupControllerProvider` közös
  állapotán ül; a `failureCode` bare `String?`
  (`song_trainer_setup_state.dart`). A retry-akció (`onRetry`) MEGVOLT
  pre-migration is (`_loadIfNeeded`) — ez nem új akció, csak a stílusa
  költözött tokenekre.
- **`song_editor_screen` `_EditorLoadError`** — `SongEditorState`-nek nincs
  `AppFailure`/`retryable` mezője ezen az úton; a pre-migration állapot
  akció-mentes bare `Text` volt — akciót NEM adtam hozzá (ez lett volna az
  E15-R04/MAJOR-3 minta).
- **`song_library_screen` `_LibraryError`** — `failureCode` bare
  `SongRepositoryErrorCode` string; a retry (`controller.load`) pre-migration
  is megvolt.
- **`song_library_screen` `_LibraryEmpty`** — az `SsEmptyState.onAction`
  KÖTELEZŐ, a pre-migration üres állapot (mérve: `git show origin/main`)
  akció-mentes bare `Center(Text)` volt — a meglévő FAB import-akció
  bekötése egy `onAction`-be viselkedés-bővítés lenne egy megjelenés-körben.
- **`song_import_screen`** (inline, nem külön widget-osztály) — a
  `SongImportPhase.failure` blokkoló-hiba ága `state.failureCode` bare
  string-re épül, a `SsButton`(„Choose a file") a pre-migration
  `controller.requestSelection`-t hívja, változatlanul.
- **`song_result_screen`, `song_import_preview_screen`,
  `setlist_session_screen`** — nincs önálló, a design-rendszer kötelező
  alapesetét kiváltó hiba-/üres-widgetjük ezen a batchen (a
  `setlist_session_screen` egyetlen raw affordance-a, a 18px spinner, a
  10.5/m4 alatt indokolt).

Mind a design-rendszer tokenjeiből épül (`SsColorScheme`, `SsTypography`,
`SsSpacing`, `SsButton`) — nulla `Colors.`/`textTheme`/`colorScheme` literál
(G4 és a kézi grep is megerősíti).

### 10.7 §7 kapu — nyers végkimenet

```
$ tools/round-gate.sh test/ui/ui_inventory_test.dart test/l10n/arb_parity_test.dart test/app/routing/app_router_test.dart test/features/song_trainer/application/setlists/setlist_session_controller_test.dart test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart test/features/song_trainer/presentation/song_editor_screen_test.dart test/features/song_trainer/presentation/song_import_preview_screen_test.dart test/features/song_trainer/presentation/song_import_screen_test.dart test/features/song_trainer/presentation/song_library_screen_test.dart test/features/song_trainer/presentation/song_overview_screen_test.dart test/features/song_trainer/presentation/song_result_screen_test.dart test/features/song_trainer/presentation/song_trainer_accessibility_test.dart test/features/song_trainer/presentation/song_trainer_screen_test.dart test/features/song_trainer/presentation/trainer_setup_screen_test.dart test/features/songs/import/editor_draft_test.dart test/features/songs/import/import_blocking_error_test.dart test/features/songs/song_asset_state_test.dart test/features/songs/song_library_test.dart test/features/songs/trainer/playback_only_result_test.dart test/features/songs/trainer/playhead_loop_sync_test.dart test/features/songs/trainer/setlist_run_test.dart test/features/songs/trainer/trainer_setup_test.dart
...
    → [1] format: ZÖLD
    → [2] analyze: ZÖLD
    → [3] test test/ui/ui_inventory_test.dart: ZÖLD
    → [4] test test/l10n/arb_parity_test.dart: ZÖLD
    → [5] test test/app/routing/app_router_test.dart: ZÖLD
    → [6] test test/features/song_trainer/application/setlists/setlist_session_controller_test.dart: ZÖLD
    → [7] test test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart: ZÖLD
    → [8] test test/features/song_trainer/presentation/song_editor_screen_test.dart: ZÖLD
    → [9] test test/features/song_trainer/presentation/song_import_preview_screen_test.dart: ZÖLD
    → [10] test test/features/song_trainer/presentation/song_import_screen_test.dart: ZÖLD
    → [11] test test/features/song_trainer/presentation/song_library_screen_test.dart: ZÖLD
    → [12] test test/features/song_trainer/presentation/song_overview_screen_test.dart: ZÖLD
    → [13] test test/features/song_trainer/presentation/song_result_screen_test.dart: ZÖLD
    → [14] test test/features/song_trainer/presentation/song_trainer_accessibility_test.dart: ZÖLD
    → [15] test test/features/song_trainer/presentation/song_trainer_screen_test.dart: ZÖLD
    → [16] test test/features/song_trainer/presentation/trainer_setup_screen_test.dart: ZÖLD
    → [17] test test/features/songs/import/editor_draft_test.dart: ZÖLD
    → [18] test test/features/songs/import/import_blocking_error_test.dart: ZÖLD
    → [19] test test/features/songs/song_asset_state_test.dart: ZÖLD
    → [20] test test/features/songs/song_library_test.dart: ZÖLD
    → [21] test test/features/songs/trainer/playback_only_result_test.dart: ZÖLD
    → [22] test test/features/songs/trainer/playhead_loop_sync_test.dart: ZÖLD
    → [23] test test/features/songs/trainer/setlist_run_test.dart: ZÖLD
    → [24] test test/features/songs/trainer/trainer_setup_test.dart: ZÖLD
    → [25] architecture: ZÖLD
    → [26] secrets: ZÖLD
    → [27] l10n: ZÖLD
MINDEN GATE ZÖLD.
```

### 10.8 §7.1 négy gépi őr — nyers kimenet

```
$ # G1 — ELTŰNT ARB-kulcs
(üres)

$ # G2 — kézzel gyártott hiba / retryable
(üres)

$ # G3 — ÚJ akció vagy navigáció
+/// component mandates an [SsEmptyState.onAction] (§5.2), and the legacy
+/// Wiring the existing FAB's import action into a new `onAction` here would
```

A két G3-találat DOKUMENTUM-kommentben van (`song_library_screen.dart`,
`_LibraryEmpty` doc-comment, MIÉRT nincs `onAction`), változatlan a kör
kezdete (`7e24892b`) óta — nem ez a kör vezette be, és tényleges kódsor
egyik sem.

```
$ # G4 — beégetett felhasználói mondat
lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart:187:                DropdownMenuItem<int>(value: bars, child: Text('$bars')),
```

Ez a §0.0/R6 kifejezetten NEM kötelező kivétele (szám-interpoláció, nem
mondat) — a brief szó szerint kimondja, hogy ennek hiánya nem bukik el.

### 10.9 Migrációs mérés

```
$ for f in ...9 képernyő...; do grep -q design_system "$f" && echo MIGRATED || echo legacy; done
MIGRATED lib/features/song_trainer/presentation/screens/song_trainer_screen.dart
MIGRATED lib/features/song_trainer/presentation/screens/song_overview_screen.dart
MIGRATED lib/features/song_trainer/presentation/screens/song_result_screen.dart
MIGRATED lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart
MIGRATED lib/features/song_trainer/presentation/screens/setlist_session_screen.dart
MIGRATED lib/features/song_trainer/presentation/screens/song_editor_screen.dart
MIGRATED lib/features/song_trainer/presentation/screens/song_import_screen.dart
MIGRATED lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart
MIGRATED lib/features/song_trainer/presentation/screens/song_library_screen.dart
```

Teljes fa: **60/96** (62,5%), változatlan a kör előtti méréshez képest (ez a
kör nem migrált új képernyőt, csak a meglévő 9 migrációját javította).

### 10.10 Golden-sáv

```
$ tools/golden-x86.sh record test/ui/goldens/e13_r23_screens_golden_test.dart test/ui/goldens/e13_r24_screens_golden_test.dart test/ui/goldens/e13_r25_screens_golden_test.dart
...
02:11 +20: All tests passed!

$ tools/golden-x86.sh check  test/ui/goldens/e13_r23_screens_golden_test.dart test/ui/goldens/e13_r24_screens_golden_test.dart test/ui/goldens/e13_r25_screens_golden_test.dart
...
02:10 +20: All tests passed!

$ git status --short test/ui/goldens/goldens/
(üres — egyetlen PNG sem mozdult)
```

A nulla PNG-diff azért várt: a kör kódváltoztatásai (subtitle-szöveg a
PAUSED állapotban, lakat-szín a `canPersist == false` szerkesztő-ágon,
`Semantics`-csomagolás, `final class`/`const`) egyike sem esik a golden
fixture-ök rögzített állapotaiba (a `song_trainer_stage` golden a RUNNING
állapotot rögzíti, nem a PAUSED-et; a `song_editor` golden fixture-je nem
`canPersist == false`) — konzisztens az eredeti kör n2-jegyzetével, mely
szerint ez a három képernyő PNG-je pixel-semleges maradt.

### 10.11 Amit NEM futtattam

Semmi a brief §7/§7.1/§10 listájáról nem maradt ki. A CI-oldali teljes suite
+ randomizált property gate + release APK ezen a boxon nem futtatható (AGENTS
mért korlát) — CI-diszpecselés az orchestrátor feladata a merge előtt.

`rm -rf test/ui/goldens/failures` lefutott a `done` jelzés előtt.

## 11. Review — a Claude tölti ki
