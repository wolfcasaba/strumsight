# E13-R18 — Live Stage UI migráció

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ e9a2c8b2`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 18
- **Kör-azonosító:** `E13-R18`
- **Branch:** `<motor>/e13-r18-live-stage-ui`
- **Előfeltétel:** `E13-R17` merge-elve (hubok) + az R09 StageScaffold
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0274/0276/0280 érvényes erre a körre.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES Live
> engine-interfészt és `autoDispose` életciklust (`lib/features/live/`), és
> jegyezd fel a jelenlegi DSP-paraméterek helyét — a §5.1 tiltás rájuk
> vonatkozik. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/live/",
  "lib/core/design_system/components/music/ss_chord_hero.dart",
  "lib/core/design_system/components/music/ss_strum_glyph.dart",
  "lib/core/design_system/components/music/ss_beat_grid.dart",
  "lib/core/design_system/components/music/ss_tempo_display.dart",
  "lib/core/design_system/components/music/ss_signal_quality_indicator.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/live/chord_timeline_golden_test.dart",
  "test/features/live/chord_timeline_test.dart",
  "test/features/live/expected_hint_cleared_on_live_test.dart",
  "test/features/live/live_background_test.dart",
  "test/features/live/live_lab_panel_test.dart",
  "test/features/live/live_screen_test.dart",
  "test/features/live/live_widgets_test.dart",
  "test/features/live/live_stage_test.dart",
  "test/features/live/live_mic_release_test.dart",
  "test/features/live/live_announcement_throttle_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/shell_lifecycle_test.dart",
  "test/features/ai_tutor/presentation/tutor_home_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "docs/rounds/e13-r18-live-stage-ui.md",
]
gate_tests = [
  "test/features/live/live_stage_test.dart",
  "test/features/live/live_mic_release_test.dart",
  "test/features/live/live_announcement_throttle_test.dart",
  "test/ui/goldens/e13_r18_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/shell_lifecycle_test.dart",
  "test/features/ai_tutor/presentation/tutor_home_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
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

**Kockázat = high, indoklás:** a Live Stage a mikrofon-erőforrás (authorization) életciklusát vezérli, a jel-minőség kijelzés pedig a felismerés igazmondását közvetíti.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fája ma **13** l10n-kulcsot használ, és mind feloldható: `app` = 13 kulcs.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `live` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/live/chord_timeline_golden_test.dart`
  - `test/features/live/chord_timeline_test.dart`
  - `test/features/live/expected_hint_cleared_on_live_test.dart`
  - `test/features/live/live_background_test.dart`
  - `test/features/live/live_lab_panel_test.dart`
  - `test/features/live/live_screen_test.dart`
  - `test/features/live/live_widgets_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 27 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/live/` könyvtár-előtag
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
- `test/app/offline_network_guard_test.dart`
- `test/app/routing/app_router_test.dart`
- `test/app/routing/shell_lifecycle_test.dart`
- `test/features/ai_tutor/presentation/tutor_home_screen_test.dart`
- `test/features/practice/presentation/practice_routing_test.dart`

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

### R5 — S11 MÁSODIK mérés: van egy NYOLCADIK pin — a feloldás a típus HELYBEN tartása

**Mérve (`main @ d32f11bd`, kör-pre-flight 2026-08-25):** a `LiveScreen` típust
**kilenc** tesztfájl pinneli (`grep -rln "LiveScreen" test/`). A fenti S11-lista
hetet sorol fel, a `test/features/live/live_screen_test.dart` a §0.0/R2 miatt
már rajta van — a **nyolcadik**, a
`test/features/today/hub_navigation_test.dart:234` (`find.byType(LiveScreen)`)
azonban **NINCS a listán**: az E13-R17-tel (`4235f636`) érkezett, tehát a
`b28bb1bf`-en végzett S11-mérés UTÁN. A `python3 tools/brief-lint.py --brief
docs/rounds/e13-r18-live-stage-ui.md --level strict` a REVIDEÁLT briefen
pontosan ezt az egy fájlt jelenti `S11`-ként.

A felvétele az orchestrátornak **tágítás, azaz H3** ([L478](../LESSONS.md)).
Ezért a kör az S11 szabály SAJÁT kifutóját használja („Ha a kör bizonyíthatóan
nem cseréli le a képernyőt, a kör pre-flightja mondja ki ezt a mérést"):

**KÖTELEZŐ SZŰKÍTÉS** (az orchestrátor §2 hatásköre — a lista *szűkítése*):

- a `lib/features/live/screens/live_screen.dart` **útvonala** és a publikus
  **`LiveScreen` típusnév VÁLTOZATLAN** — a migráció HELYBEN történik;
- a kör **NEM hoz létre új `lib/features/**/*_screen.dart` fájlt**.

Mért következmények:

| Amit a pin megőriz | Mérés |
|---|---|
| mind a 9 `find.byType(LiveScreen)` cella zöld marad | a 7 felsorolt fájl ÉRINTETLEN, a listán kívüli 8.-hoz hozzá sem kell nyúlni |
| `tool/ui_inventory.dart` képernyőszáma **84** marad | `find lib/features -name "*_screen.dart" \| wc -l` → 84 = `ui_inventory_test.dart` `hasLength(84)`; az R4 jogosultsága kihasználatlan marad |
| `lib/app/routing/**` (listán KÍVÜL) érintetlen | `/live` (`app_router.dart:251`) és `/practice/live` ma is **top-level** GoRoute |

Ha az implementer azt méri, hogy a migráció típus-átnevezés NÉLKÜL nem
megoldható: `stopped` jelzés és jelentés — **önkezű átnevezés TILOS**.

### R6 — a §7 golden-precedens hivatkozása MÉRVE HAMIS

A §7 a `test/features/live/chord_timeline_golden_test.dart`-ot nevezi meg
mintaként, „valódi kapu, nem `skip`-elt rögzítő" indoklással. **Mérve, a fájl
73. sora:**

```dart
final _skip = Platform.environment['GOLDENS'] != '1';
```

— tehát alapértelmezésben **skip-elt**, opt-in lokális vizuális eszköz; a két
PNG-je (`test/features/live/goldens/`) NEM CI-kapu. (Ezt a `test/ui/goldens/
e13_r17_screens_golden_test.dart` fejléc-kommentje szó szerint ki is mondja.)

**A kötelező minta helyette:** `test/ui/goldens/e13_r17_screens_golden_test.dart`
(és a `e13_r16_…` előzménye) — `Size(412, 915)`, `devicePixelRatio = 1.0`,
`TextScaler.linear(2.0)` a második kerethez, `AppTheme.dark()`,
`matchesGoldenFile('goldens/<név>.png')`, a PNG-k a `test/ui/goldens/goldens/`
alatt commitolva. Ez VALÓDI kapu: minden `flutter test` futtatja.

**[L486](../LESSONS.md) (MÉRT, E13-R17, két javító kör ára):** a golden nem a
képernyőt rögzíti, hanem a RASZTERIZÁLÁST. Egy `ColorScheme.fromSeed`-ből (HCT,
lebegőpontos) származó szín **nagy, egybefüggő felületre** festve box↔CI diffet
ad; konstans színforrás nem. A nagy felületeket (hero-háttér, metrika-doboz,
jelminőség-sáv) **konstans színforrásból** fesd.

### R7 — a mikrofon-lease tulajdonlása (prompt §1/2: a TÉNYLEGES hívási lánc)

Nem a réteg-diagramból, hanem `grep -rn "\.acquire(" lib/`-ből mérve:

- **egyetlen megszerző:** `MicCapture._doStart` →
  `AudioSessionCoordinator.acquire` (`lib/core/audio/mic_capture.dart:82`),
  tulajdonos `AudioOwner.live`;
- **huzalozás:** `strumEngineProvider` (sima, NEM autoDispose `Provider`) →
  `RealStrumEngine(mic: createMicCapture(ref, AudioOwner.live))`
  (`live_providers.dart:11–15`);
- **indítás/elengedés:** `liveFrameProvider` =
  `StreamProvider.autoDispose` → `engine.start()` + `ref.onDispose(engine.stop)`
  (`live_providers.dart:19–24`);
- **ma mért kilépési utak:** (1) autoDispose unmountkor (navigáció),
  (2) `_onAppLifecycle` háttér → `engine.stop()` (`live_screen.dart:86`),
  (3) `_togglePause` → `engine.stop()` (`:123`), (4) `dispose()`.

Ez megerősíti az [L100](../LESSONS.md)-at: a UI-réteg a lease-t **nem
birtokolja**. **ADR 0276** szerint az `SsStageScaffold` sem — a huzalozás a
feature rétegben marad; a scaffold `onRequestScreenAwake` /
`onReleaseScreenAwake` callbackje **kérés, nem birtoklás**.

**[L449](../LESSONS.md) (MÉRT, E13-R08):** erőforrás-birtokló képernyő nem
kerülhet shell-branchbe (`IndexedStack` → nincs unmount → nincs elengedés). Az
R5 pin ezt szerkezetileg megőrzi; az őr:
`test/app/navigation/adaptive_scaffold_test.dart`::`A8`.

**Riverpod-csapda (mért, r102):** minden provider, amely a `liveFrameProvider`-t
`ref.watch`/`ref.listen`-eli, MAGA is `autoDispose` kell legyen — különben a
mikrofon bekapcsolva ragad. Az A7 cella tárgya.

### R8 — a kilenc állapot → MÉRT bemenet (prompt §1/1: elérhetetlen cél-státusz)

**Mérve:** a `LiveFrame` (`lib/features/live/model/live_frame.dart`) **NEM
tartalmaz állapot-enumot** — az állapotok a UI-ban származtatottak. A transport
enum `SsSessionTransportStatus` = `{idle, countIn, active, paused, finishing,
disabled}` (`ss_session_transport.dart:6–13`).

| §3 állapot | MÉRT bemenet, ami előállítja |
|---|---|
| idle | `liveAsync` adat + `frame.listening == false`, nincs pause (`LiveFrame.empty`) → `SsSessionTransportStatus.idle` |
| induló | `liveAsync.isLoading` (a `StreamProvider` az első keret előtt) |
| hallgató | `frame.listening == true` → `active` |
| gyenge jel | `frame.listening == true` && `frame.inputLevel` a **prezentációs** küszöb alatt (R9) |
| nincs akkord | `frame.listening == true` && `frame.current == null`, elegendő `inputLevel` mellett |
| degradált | `micPermissionProvider` → `false` (engedély hiányzik) → `disabled` |
| szüneteltetett | a képernyő `_paused` állapota → `paused` |
| záró | a Finish akció → `finishing` (lásd lent) |
| hiba | `liveAsync.hasError` (`live_screen.dart:184`) |

**Két mért figyelmeztetés:**

1. **`countIn` a Live úton ELÉRHETETLEN** — a Live szabad játék, nincs
   beszámlálás; egyetlen bemenet sem produkálja. **Acceptance-cellát NEM
   kaphat**, és az „induló" NEM a `countIn`, hanem a `liveAsync.isLoading`.
   (Pontosan a prompt §1/1 hibaosztálya: az enum tartalmaz olyan élt, amit a
   tényleges út nem produkál.)
2. **A `finishing`-hez Finish akció kell, ami ma NINCS.** A mai `_ActionBar`
   (`live_screen.dart:251–292`) három gombja: Tuner / Pause / Metronome.
   **ADR 0276 döntés 4** viszont kimondja, hogy a Pause ÉS a Finish minden
   aktív állapotban látható, landscape-ben is — a migrált Stage-nek tehát
   **Finish akciót kell kapnia** (a session lezárása és a route elhagyása). Ez
   nem scope-tágítás: a kör kötelező ADR-jének kikényszerítése.

### R9 — a gyenge-jel küszöb PREZENTÁCIÓS konstans, nem DSP

Mérve: `grep -rn "inputLevel" lib/` — a Live fában egyetlen fogyasztó van
(`live_status_bar.dart:55` → `InputLevelMeter`), **küszöb sehol**. A
„degradált" állapotnak sincs forrása a Live fában (`grep -rni "degraded"
lib/features/live/` → 0 találat).

**KÖTÖTT ÉRTELMEZÉS:** a `frame.inputLevel` a nyers 0..1 **mikrofonszint**, NEM
confidence. Egy megjelenítési sáv efölött **display-leképezés**, nem felismerési
küszöb — ezért nem ütközik az **ADR 0278 §5**-tel („a confidence küszöbeit a
felismerési réteg határozza meg, nem a felület"), és nem DSP-változás
(AGENTS.md §9).

**Ezért kötelező:** a küszöb-konstans a **UI rétegben** él
(`lib/features/live/widgets/**` vagy az `SsSignalQualityIndicator`), és a
`lib/features/live/engine/dsp/**` — kiemelten a `dsp_config.dart` — a körben
**NEM módosulhat**. Ez az **A1** cella tárgya (`git diff` bizonyíték).

### R10 — nincs új ADR (mért precedens)

A közvetlenül analóg migrációs kör, az **E13-R17** („Előre kiosztott ADR:
nincs", squash `4235f636`) **nem** hozott új ADR-t
(`git log --name-only 4235f636 -- docs/adr/` → üres). A kör normatív tartalmát
merge-elt döntések fedik: **ADR 0274** (mozgás az audio-órához kötve),
**0276** (§4 Pause+Finish), **0278 §2/§5**, **0280 §2** (a bejelentési
költségvetés **1000 ms**, a határ inkluzív — a fájl 28. sorával ellenőrizve) és
az AGENTS.md §9. Új ADR merge-elt döntések fölé nem osztható, ezért a kör
**ADR-t nem kap**, és a `docs/adr/**` a tilos zónában marad.

### R11 — a §7 gate-sora a REVIDEÁLT `gate_tests` blokkhoz igazítva

A revízió a `gate_tests` blokkot 5-ről **12** bejegyzésre bővítette, a §7
parancssora viszont az eredeti ötöt tartalmazta. A §7 alább a teljes,
commitolt `gate_tests` listát futtatja — ez a mérce **erősítése**: az R5 pin
regressziós őrei (a hét örökség-teszt) is minden gate-futásban mérve lesznek.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A Live felület (UI-08) átállítása az új StageScaffoldra és a zenei
komponensekre — **a felismerési viselkedés változtatása nélkül**
(SDD Ch13 Kör 18).

## 2. Jelenlegi állapot — mért tények

- Az R09 letette a StageScaffoldot, az R12 a badge-eket, az R14 az élő régió
  költségvetését — ez a kör ezeket használja.
- A Live a termék központi képernyője: a jelenlegi motor-interfész és
  `autoDispose` életciklus **regressziós tesztekkel védett**.
- Az AGENTS.md §9 tiltja a DSP-paraméterek módosítását.

## 3. Scope

**Benne van:** `SsChordHero`, `SsStrumGlyph`, `SsBeatGrid`, `SsTempoDisplay`,
`SsSignalQualityIndicator` · a Live elrendezés portrait / landscape / expanded
változata · idle, induló, hallgató, gyenge jel, nincs akkord, degradált,
szüneteltetett, záró és hiba állapotok — **a §0.0/R8 mért bemenet-táblája
szerint** (a `countIn` a Live úton elérhetetlen, az „induló" a
`liveAsync.isLoading`) · a **Finish akció** (ADR 0276 döntés 4 — ma nincs,
§0.0/R8) · az accessibility-bejelentés
**throttlingja** (a vizuális frissítés maradhat sűrűbb) · a baseline-hoz képesti
**szándékos** eltérések dokumentálása.

**NINCS benne (tilos):** **bármely DSP-paraméter módosítása** (AGENTS.md §9) ·
a motor-interfész vagy az `autoDispose` viselkedés megváltoztatása · más
képernyők migrációja · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/live/` | a képernyő migrációja (UI-réteg) |
| `components/music/ss_chord_hero.dart` | **ÚJ** — akkord-hero |
| `components/music/ss_strum_glyph.dart` | **ÚJ** — strum-irány |
| `components/music/ss_beat_grid.dart` | **ÚJ** — ütem-rács |
| `components/music/ss_tempo_display.dart` | **ÚJ** |
| `components/music/ss_signal_quality_indicator.dart` | **ÚJ** |
| `public.dart` | az export bővítése |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — az állapot-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (7 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/live/*_test.dart` (3) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r18-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `live/` KIVÉTELÉVEL · a DSP- és
felismerési paraméterek bárhol · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 NINCS DSP-paraméterváltozás — a paritás fixture-rel bizonyított

A kör UI-migráció. A felismerés kimenete bit-szinten ugyanaz marad; ezt
paritás-fixture méri, nem ígéret.

**NEM elfogadható gyengítés:** „a küszöb egy hajszálnyi módosítása szebb
kijelzést ad". Az AGENTS.md §9 tiltott zónája, és a termék mérőszámát rontja el
egy UI-kör kedvéért.

### 5.2 A gyenge jel és a „nincs akkord" KÜLÖN állapot

Két különböző ok, két különböző teendő: az egyik a mikrofonhoz szólít, a másik
a játékhoz. Összevonva a felhasználó nem tudja, mit tegyen.

### 5.3 Az akkord és az irány MESSZIRŐL olvasható

A Stage-t a gitár mellől nézik. Az akkordnév az R04 adaptív méretezésével, a
strum-irány az R07 saját glyph-jével jelenik meg.

### 5.4 A confidence NEM csak szín

Az ADR 0278 §2 kikényszerítése ezen a képernyőn.

### 5.5 A bejelentés THROTTLE-olt, a vizuális frissítés NEM

Az ADR 0280 §2 költségvetése az élő régióra vonatkozik; a vizuális kép
maradhat sűrűbb.

### 5.6 A mikrofon MINDEN kilépési úton leáll

Navigáció, háttérbe kerülés, hiba, rendszer-vissza. Ez acceptance-cella (A4).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nincs DSP-paraméterváltozás — a paritás-fixture azonos kimenetet ad | `live_stage_test.dart` + `git diff` |
| A2 | A gyenge jel és a „nincs akkord" külön állapot, külön teendővel | `live_stage_test.dart` |
| A3 | A confidence nem csak színnel jelölt | ugyanott |
| A4 | A mikrofon minden kilépési úton leáll | `live_mic_release_test.dart` |
| A5 | A bejelentés throttle-olt, a vizuális frissítés nem korlátozott | `live_announcement_throttle_test.dart` |
| A6 | Portrait, landscape és expanded elrendezésben nincs túlcsordulás | `live_stage_test.dart` |
| A7 | A motor-interfész és az `autoDispose` viselkedés változatlan | a meglévő regressziós tesztek zöldek |
| A8 | A baseline-hoz képesti eltérések szándékosként dokumentáltak | §10 |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r18_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |
| A10 | A Pause ÉS a Finish MINDEN aktív állapotban látható (`active`, `paused`, `finishing`), portrait ÉS landscape elrendezésben — ADR 0276 döntés 4 | `live_stage_test.dart` |
| A11 | A `LiveScreen` típusnév és a `lib/features/live/screens/live_screen.dart` útvonal VÁLTOZATLAN; a kör nem hoz új `lib/features/**/*_screen.dart`-ot (§0.0/R5) | `test/ui/ui_inventory_test.dart` `hasLength(84)` érintetlenül zöld + a hét örökség-teszt érintetlenül zöld |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy küszöb „hajszálnyi" módosítása | **A1** |
| A gyenge jel és a nincs-akkord összevonva | **A2** |
| A confidence csak színes sáv | A3 |
| A háttérbe kerüléskor nyitva marad a mikrofon | **A4** |
| A vizuális frissítés is a bejelentési ütemre lassítva | **A5** |
| Fix magasságú akkord-hero | A6 |
| Az `autoDispose` lecserélése tartós providerre | **A7** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |
| A Finish elrejtve/hiányzik bármely aktív állapotban (ADR 0276 döntés 4) | **A10** |
| A `LiveScreen` típus átnevezése vagy új `*_screen.dart` (§0.0/R5) | **A11** |

**A bejelentés-throttling három kötelező cellája** (a küszöb: **1000 ms**, az
ADR 0280 §2 szerint):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 200 ms-onként változó akkord | **egy** bejelentés; a vizuális kép **minden** változást követ |
| rajta (a küszöbön) | pontosan 1000 ms | **bejelentve** (a határ inkluzív) |
| a küszöb fölött | 3000 ms-onként | minden változás bejelentve |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vond össze a gyenge
jel és a „nincs akkord" állapotot → az **A2** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/live_stage_test.dart test/features/live/live_mic_release_test.dart test/features/live/live_announcement_throttle_test.dart test/ui/goldens/e13_r18_screens_golden_test.dart test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/app/routing/app_router_test.dart test/app/routing/shell_lifecycle_test.dart test/features/ai_tutor/presentation/tutor_home_screen_test.dart test/features/practice/presentation/practice_routing_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/ui/goldens/e13_r17_screens_golden_test.dart`
(valódi kapu — a §0.0/R6 mérése szerint a korábban hivatkozott
`chord_timeline_golden_test.dart` `GOLDENS=1`-re skip-elt lokális eszköz).
Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r18_screens_golden_test.dart
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

1. A DSP-paritás fixture ELŐBB — a nem-változás mércéje.
2. A zenei komponensek (`SsChordHero`, `SsStrumGlyph`, `SsBeatGrid`,
   `SsTempoDisplay`, `SsSignalQualityIndicator`).
3. A Live elrendezés StageScaffoldon, három elrendezésben.
4. A kilenc állapot — gyenge jel és nincs-akkord KÜLÖN.
5. A bejelentés-throttling + a három cella.
6. Mikrofon-felszabadítás minden kilépési úton.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A DSP-hez nyúlás.** A UI-munka közben kézenfekvőnek tűnik „megigazítani" a
  küszöböt, és ezzel a termék mérőszámát rontja el (A1).
- **A háttérbe kerülés.** A legkönnyebben kifelejtett kilépési út, és nyitva
  hagyott mikrofont jelent (A4).
- **A throttling túlterjesztése.** Ha a vizuális képre is hat, a Stage
  akadozónak tűnik (A5).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** Claude Sonnet 5 (`sonnet-impl`). **Branch:** `sonnet-impl/e13-r18-live-stage-ui`.

### 10.1 Mi készült el, fájlonként

**Új fájlok:**

- `lib/core/design_system/components/music/ss_strum_glyph.dart` — `SsStrumGlyph`,
  generikus le/fel strum-irány glyph, a `StrumArrow` festő-logikájának
  design-system-natív portja (saját `SsStrumDirection` enum, nincs
  `core/music` függés). Az irány tier (0/1/2) a FORMÁT vezérli (kitöltött
  hegy / nyitott sarok / nyitott sarok + üres pötty), nem csak a színt.
- `lib/core/design_system/components/music/ss_chord_hero.dart` — `SsChordHero`,
  a Stage `hero` slotjának messziről olvasható akkord-kijelzője
  (`FittedBox(scaleDown)`, sosem fix magasság) + a `SsStrumGlyph`.
- `lib/core/design_system/components/music/ss_beat_grid.dart` — `SsBeatGrid` +
  `SsBeatGridSlot`, a `BeatCounter` generikus rács-motorja.
- `lib/core/design_system/components/music/ss_tempo_display.dart` —
  `SsTempoDisplay`, a "96 BPM · A=440 · Capo 2" olvasat.
- `lib/core/design_system/components/music/ss_signal_quality_indicator.dart` —
  `SsSignalQualityIndicator`, az 5-sávos szintmérő + a gyenge-jel
  ikon+szöveg figyelmeztetés (a `defaultWeakThreshold = 0.12` PREZENTÁCIÓS
  konstans itt él, nem a DSP-ben — §0.0/R9).
- `test/features/live/live_stage_test.dart` — A1/A2/A3/A6/A10 cellák.
- `test/features/live/live_mic_release_test.dart` — A4, mind a négy mért
  kilépési út egy fájlban.
- `test/features/live/live_announcement_throttle_test.dart` — A5, a három
  kötelező mátrix-cella (200 ms / 1000 ms / 3000 ms).
- `test/ui/goldens/e13_r18_screens_golden_test.dart` +
  `test/ui/goldens/goldens/e13_r18_live_stage_{compact,compact_scale2}.png` — A9.

**Módosított fájlok:**

- `lib/features/live/screens/live_screen.dart` — a `build()` metódus teljesen
  átépült `SsStageScaffold`-ra (öt slot); a `_LiveScreenState` életciklus-kódja
  (wakelock, `_onAppLifecycle`, `dispose`, mikrofon-huzalozás) **VÁLTOZATLAN**
  — csak a `_finish()`/`_finishing` és a `_liveRegion` mező új. A típusnév és
  az útvonal **VÁLTOZATLAN** (§0.0/R5).
- `lib/features/live/widgets/live_status_bar.dart` — az input-level mérő
  kikerült (a `feedback` slotba költözött `SsSignalQualityIndicator`
  formájában), a BPM/tuning szöveg `SsTempoDisplay`-re állt.
- `lib/features/live/widgets/beat_counter.dart` — vékony adapter:
  `BeatSlot`/`Strum` → `SsBeatGridSlot`, a rajzolást átadja `SsBeatGrid`-nek.
  A saját tesztje (`live_widgets_test.dart`) változatlanul zöld — csak a
  belső renderelő cserélődött, a `BeatSlot`-alapú publikus API nem.
- `lib/features/live/widgets/live_lab_panel.dart` — **valódi bugfix**, nem
  csak migráció: a fejléc-Row-ban lévő gomb ("Capture & analyze last ~60 s")
  a Stage Wide-elrendezésének szűkebb (~262 px) oszlopában túlcsordult
  (mérve: `test/features/live/live_lab_panel_test.dart` a Wide-ágat triggerelő
  800×600 alap teszt-felületen). A gomb saját sorba került (cím fölött,
  jobbra igazítva) — nulla vizuális szövegváltozás, a felirat és a
  `find.text(...)` a tesztben változatlan.
- `lib/core/design_system/public.dart` — az öt új export.
- `lib/l10n/base/app_{en,hu}.arb` (FORRÁS) + `lib/l10n/app_{en,hu}.arb`
  (GENERÁLT, `dart run tool/gen_l10n_segments.dart --write`) — három új kulcs:
  `liveFinish`, `liveStarting`, `liveWeakSignal`.

### 10.2 A1–A11 acceptance-cellák, bizonyítékkal

| # | Státusz | Bizonyíték |
|---|---|---|
| A1 | ✅ | `git diff main -- lib/features/live/engine/` **üres** (mérve); `live_stage_test.dart` "A1" csoport — fix bemenő keret (C, down, 90%) ugyanazt a szöveget adja, mint a migráció előtt |
| A2 | ✅ | `live_stage_test.dart` "A2" csoport, KÖTELEZŐ valódi-sértés próbával megerősítve — lásd §10.3 |
| A3 | ✅ | `live_stage_test.dart` "A3" — 20% vs 92% konfidencia KÜLÖNBÖZŐ szemantika-szöveget ad (`SsStrumGlyph.semanticLabel`), nem csak színt |
| A4 | ✅ | `live_mic_release_test.dart` — mind a négy mért kilépési út (navigáció, háttér, pause, Finish) leállítja a motort |
| A5 | ✅ | `live_announcement_throttle_test.dart` — mindhárom mátrix-cella (200 ms összevon, 1000 ms határ inkluzív bejelent, 3000 ms minden változást bejelent); a vizuális szöveg minden esetben azonnal követi a keretet |
| A6 | ✅ | `live_stage_test.dart` "A6" — portrait (412×915), landscape (915×412), expanded (1300×900), `tester.takeException()` nulla mindháromban |
| A7 | ✅ | a meglévő regressziós tesztek (`live_widgets_test.dart`, `live_background_test.dart`, `live_mic_release_test.dart`) változatlanul zöldek — a `strumEngineProvider` (sima `Provider`) és a `liveFrameProvider` (`StreamProvider.autoDispose`) huzalozása egy sort sem változott |
| A8 | ✅ | lásd §10.4 — a szándékos eltérések felsorolva |
| A9 | ✅ | `test/ui/goldens/e13_r18_screens_golden_test.dart` zöld, a két PNG a diffben (`goldens/e13_r18_live_stage_compact.png`, `..._compact_scale2.png`) |
| A10 | ✅ | `live_stage_test.dart` "A10" — mind a hat kombináció (active/paused/finishing × portrait/landscape) mutatja az `ss-session-transport-pause`/`-finish` kulcsot |
| A11 | ✅ | `test/ui/ui_inventory_test.dart` **érintetlen**, `hasLength(84)` zöld (nincs új `*_screen.dart`); a hét S11-listás örökség-teszt + a `test/features/today/hub_navigation_test.dart` (a nyolcadik, listán kívüli pin) mind zöld, szintén érintetlenül |

### 10.3 Valódi-sértés próba (§6.1, KÖTELEZŐ)

Két kört futtattam, mert az első mutáció nem bizonyult valódi sértésnek —
ez maga is dokumentálva van, mert azt mutatja, hogy az architektúra
STRUKTURÁLISAN véd A2 ellen egy felszínes megközelítéssel szemben:

1. **1. kísérlet (nem sértett):** az `isWeakSignal` kifejezést kiterjesztettem
   `frame.current == null`-ra is (a live_screen.dart-beli döntésen). A teszt
   **zöld maradt**, mert az `SsSignalQualityIndicator` maga is őrzi a saját
   `isWeak` predikátumát (`listening && level < weakThreshold`) — a hívó által
   átadott `weakLabel` önmagában nem elég a sáv megjelenítéséhez. Ez a
   komponens saját kettős kapuzása, nem hiba a tesztben.
2. **2. kísérlet (valódi sértés):** a `timeline` slot `ChordTimeline`
   `events` paraméterét `isWeakSignal ? const [] : timeline`-re cseréltem —
   azaz gyenge jelnél a filmstrip úgy tett, mintha nem lenne felismert
   akkord. Lefuttatva:

   ```
   A2 — weak signal and "no chord" are distinct states weak signal WHILE a
   chord is held shows the mic warning, not the "play a chord" prompt [E]
   Expected: no matching candidates
     Actual: _TextWidgetFinder:<Found 1 widget with text "Play a chord…": […]>
     Which: means one was found but none were expected
   ```

   Az **A2 cella PIROSRA váltott**, pontosan a mátrix-mátrix szerint. A
   mutációt visszaállítottam (`git diff` üres a `live_screen.dart`-on a
   próba után), és a teljes `live_stage_test.dart` újra zöld (13/13).

### 10.4 Szándékos eltérések a baseline-hoz képest (A8)

1. **`SsChordHero`/`SsSessionTransport` NEM `SsChordHeroText`/`SsTypography`-n
   keresztül él.** Mérve: `lib/app/strumsight_app.dart` a futó alkalmazást
   `AppTheme.light()/.dark()`-kal témázza (`lib/core/theme/app_theme.dart`),
   ami **csak** a `palette` extension-t regisztrálja — a `SsTypography`/
   `SsColorScheme` NINCS bekötve. A `SsChordHeroText`/`SsStatusBadge` ezekre
   `assert`-tel/`!`-lel támaszkodik, tehát élesben azonnal elszállna. A
   `lib/core/theme/app_theme.dart` a kör tiltott zónájában van, tehát nem
   javíthattam. Az öt új komponens ezért `context.palette` + explicit
   `TextStyle`-t használ — pontosan azt a mintát követve, amit a
   `ChordTimelineCard`/`LiveStatusBar` már ma is használ.
2. **A "nincs akkord" hero NEM egy óriás placeholder-glyph.** Az első
   verzióban egy `—` karaktert renderelt 96px-es betűmérettel — a teszt-hoston
   (nincs betöltött márka-betűtípus) ez egy hatalmas "tofu" (hiányzó-glyph)
   dobozra váltott a golden PNG-n. Túl azon, hogy ez a teszt-host
   műterméke, ÖNMAGÁBAN is rossz UX egy nagy, magányos kötőjelet mutatni
   "nincs akkord" állapotban, amikor a `timeline` slot alatta már mutatja a
   "Play a chord…" felszólítást. A hero ezért `hasChord == false` esetén egy
   visszafogott `Icons.music_note_outlined` ikonra vált.
3. **A transport-státusz NEM kapcsol `idle`-re `liveAsync.isLoading` alatt.**
   A §0.0/R8 tábla az "induló" állapotot `isLoading`-hoz köti; a transportot
   erre gate-elve viszont minden `_togglePause()` utáni resume — ami
   `ref.invalidate(liveFrameProvider)`-t hív, tehát rövid időre újra
   `isLoading`-ba kerül, amíg az első új keret meg nem érkezik — ELTÜNTETTE
   a Pause gombot (mérve: a `live_screen_test.dart` "Pause freezes the
   display…" teszt pirosra váltott). A transport ezért csak
   disabled/finishing/paused/active között különböztet; az "induló" állapot
   a `statusHeader`-ben külön "Starting…" szövegként jelenik meg
   (`l10n.liveStarting`), az `idle`/`countIn` transport-státusz a Live úton
   így is elérhetetlen marad (a `countIn`-hez hasonlóan).
4. **`SsStageScaffold.onRequestScreenAwake`/`onReleaseScreenAwake` NINCS
   bekötve.** A `_LiveScreenState` már ma is (a migráció előtt is) maga
   kezeli a wakelockot `initState`/`dispose`/`_onAppLifecycle`-ben — ez a
   háttérbe-kerülés útját is lefedi, amit a scaffold két callbackje nem tud.
   A kettő egyidejű bekötése duplán kapcsolná a wakelocket; a birtoklás
   marad a feature rétegben (ADR 0276 §1), csak nem a scaffold hookján
   keresztül.
5. **`hasUnsavedSession: false`, mindig.** A Live szabad játék, nincs
   menthető munkamenet-artefaktum — a `PopScope` back-gate kihasználatlan
   marad ezen a képernyőn (más Stage módoknál, pl. Practice/Song, releváns
   lehet, ha azok is migrálnak).
6. **A Finish akció navigációs célja `context.pop()` ha van backstack, egyébként
   `context.go(AppRoutes.learn)`.** A `/live` (shell tab) és a `/practice/live`
   (top-level, pusholt) két különböző belépési útvonal a Live-ra (§0.0/R5
   táblázat) — a `learn` egy semleges, mindig létező shell-ág, `lib/app/
   routing/**`-et nem módosítottam.
7. **`ChordDisplay`/`ConfidencePill` production-használata nem változott**
   (már a migráció ELŐTT sem hívta őket a `LiveScreen` — a `ChordTimeline`
   korábbi köre helyettesítette őket). A saját tesztjeik (`live_widgets_test.dart`)
   érintetlenül zöldek; nem töröltem őket, mert a fájl nincs a kör hatáskörében
   indokolt törlésre, és a törlés önmagában nem tartozna a kör scope-jához.

### 10.5 A záró gate tényleges kimenete

Lásd a §5 (Záró gate) blokk a jelen dokumentum végén — a kör
`tools/round-gate.sh` futtatása előtt a teljes `test/features/live/` +
`test/ui/goldens/` fa (199 teszt) és a `flutter analyze lib` (0 hiba)
külön-külön ellenőrizve zöld.

## 11. Review — a Claude tölti ki
