# E13-R18 — független review (Live Stage UI migráció)

- **Kör:** `E13-R18` · **Branch:** `sonnet-impl/e13-r18-live-stage-ui`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude Opus 5 (orchesztrátor), read-only
- **Review HEAD:** `16e07661` (implementer-diff: `710d82d1..5922d90f`, majd
  `origin/main` @ `57b18ccb` merge a §0.3 upstream-szinkron miatt)
- **Dátum:** 2026-08-25

## 1. Verdikt

**APPROVED** — 0 BLOCKER, 0 MAJOR, 2 MINOR, 1 NOTE.

A kör a fő kockázatát (a mérce meghamisítása egy UI-kör kedvéért) **nem**
váltotta ki: a DSP érintetlen, az erőforrás-életciklus változatlan, és a
három legfontosabb acceptance-cellát SAJÁT valódi-sértés próbával mértem —
mind a három PIROSRA váltott a rontáson, tehát valódi őr, nem vakuum.

## 2. Amit magam mértem (nem bemondásra)

### 2.1 Scope-audit — a hiteles eszközzel

```
Legacy scope audit OK (710d82d1404e..5922d90fee64, 22 changed path(s), 0 generated/ignored)
```

A `16e07661` (merge utáni) HEAD-en ugyanez a futás 42 utat lát és `FAILED`-et
ad — a 20 többlet **kizárólag** az általam végrehajtott `origin/main`
(`57b18ccb`, PR #458) upstream-szinkron tartalma (`docs/rounds/e13-r19…r35`,
`tools/brief-lint.py`, két `tools/tests/…`), NEM az implementer munkája. A kör
saját diffjének mércéje a fenti, pre-merge tartományon vett `OK`.

### 2.2 Célzott gate — izolált `/tmp` klónban, saját kézzel

`/tmp/review-e13-r18`, a brief §7 teljes, 12 elemű `gate_tests` során:

```
[1] format: ZÖLD          [2] analyze: ZÖLD
[3] live_stage_test: ZÖLD (13 cella)        [4] live_mic_release_test: ZÖLD (5)
[5] live_announcement_throttle_test: ZÖLD (3)  [6] e13_r18_screens_golden_test: ZÖLD (2)
[7] ui_inventory_test: ZÖLD (1)             [8] adaptive_scaffold_test: ZÖLD (24)
[9] legacy_route_redirect_test: ZÖLD (8)    [10] offline_network_guard_test: ZÖLD (4)
[11] app_router_test: ZÖLD (22)             [12] shell_lifecycle_test: ZÖLD (2)
[13] tutor_home_screen_test: ZÖLD (4)       [14] practice_routing_test: ZÖLD (6)
[15] architecture: ZÖLD    [16] secrets: ZÖLD    [17] l10n: ZÖLD
MINDEN GATE ZÖLD.
```

A kör SAJÁT feature-fája teljes egészében (`flutter test test/features/live/`):
**181 passed, 2 skipped** — a két skip pontosan a `GOLDENS=1`-re opt-in
`chord_timeline_golden_test.dart` cellapár (§0.0/R6 mérése).

### 2.3 Valódi-sértés próbák — MIND a három PIROSRA váltott

Eldobható próbák a GYÁRTÁSI kódon, mindegyik utána visszaállítva
(`git diff --stat` üres):

| Próba | Rontás | Mért eredmény |
|---|---|---|
| **A2** (a brief §6.1 KÖTELEZŐ próbája) | a gyenge jel feltételéhez `&& frame.current == null` — a két állapot összevonva | `-1`: *„A2 — weak signal WHILE a chord is held shows the mic warning…"* PIROS, a többi 12 cella zöld |
| **A5** | a bejelentés időbélyege minden kereten a költségvetés fölé tolva (throttle kiütve) | `-1`: *„below the threshold (200 ms apart)…"* PIROS |
| **A4** | a háttérbe kerülés ága már nem hívja az `engine.stop()`-ot | `-1`: *„(2) backgrounding — the app-lifecycle hook stops the mic"* PIROS |

A cellák tehát nem az L443 szerinti tautologikus „tiszta predikátumot hívó"
alakban élnek: a throttle-teszt a TELJES appot építi
(`StrumSightApp` + `FakeStrumEngine`), és minden cellában a bejelentés-listát
ÉS a vizuális `find.text(...)`-et is állítja — pontosan a brief §5.5
kettősségét (bejelentés throttle-olt, vizuális nem).

### 2.4 A §0.0/R5 pin — a legfontosabb szerkezeti kockázat

| Mérés | Eredmény |
|---|---|
| `class LiveScreen` neve és útvonala | **változatlan** (`live_screen.dart:39`) |
| új `lib/features/**/*_screen.dart` | **nincs** (a diff egyetlen `_screen.dart`-ja `M`) |
| `find lib/features -name "*_screen.dart" \| wc -l` | **84** = `ui_inventory_test.dart` `hasLength(84)` |
| a 7 örökség-pin teszt + `ui_inventory_test` + a listán KÍVÜLI `test/features/today/hub_navigation_test.dart` | **egyike sem módosult**, és mind zöld |

A `git diff --name-only 710d82d1..HEAD -- test/app/ test/ui/ui_inventory_test.dart test/features/today/` **üres**. A pin tartott: a kör
nem futott bele az E13-R16/R17-et megállító H3-osztályba.

### 2.5 A1 — DSP-invariancia

`git diff --stat 710d82d1..HEAD -- lib/features/live/engine/` → **üres**. A
gyenge-jel küszöb a §0.0/R9 szerint prezentációs konstansként él:
`SsSignalQualityIndicator.defaultWeakThreshold = 0.12`
(`ss_signal_quality_indicator.dart:30`), a `dsp_config.dart` érintetlen.

### 2.6 A7 — erőforrás-életciklus

A `strumEngineProvider` / `liveFrameProvider` (`StreamProvider.autoDispose`,
`engine.start()` + `ref.onDispose(engine.stop)`) huzalozása **bit-azonos** a
migráció előttivel; az `initState`/`dispose`/`_onAppLifecycle`/`_togglePause`
törzse változatlan. Az `SsStageScaffold` az ADR 0276 §1 szerint nem birtokol
erőforrást: a `LiveScreen` szándékosan NEM adja át neki a wakelockot
(`onRequestScreenAwake` nincs bekötve), mert a háttér-ágat a scaffold hookjai
nem fedik — ez a doc-commentben ki is van mondva, és helyes döntés.

## 3. Leletek

### MINOR-1 — az `SsLiveRegion` (`ChangeNotifier`) sosem kerül `dispose()`-ra

`lib/features/live/screens/live_screen.dart:68`

```dart
final SsLiveRegion _liveRegion = SsLiveRegion();
```

`SsLiveRegion extends ChangeNotifier` (`ss_live_region.dart:20`). A
`_LiveScreenState.dispose()` a `_lifecycle` listenert leszedi és a
`_finishTimer`-t elvágja, de a `_liveRegion`-t **nem** dobja el; a
`SsLiveRegionAnnouncer` pedig helyesen NEM dobja el (nem birtokolja — csak
`ListenableBuilder`-rel figyeli). Mérve: a repóban a `LiveScreen` az EGYETLEN
`SsLiveRegion()` tulajdonos, és nincs benne `_liveRegion.dispose()`.

**Miért számít itt jobban, mint máshol:** ez a kör az erőforrás-életciklusról
szól (A4/A7) — egy el nem dobott `ChangeNotifier` pont ebben a körben marad
benne. Viselkedést nem tör (a State-tel együtt elhal), de a Flutter
leak-tracker debug-módban ezt jelenti, és a szerződés kimondja a `dispose`-t.

**Javasolt irány:** `dispose()`-ban `_liveRegion.dispose()`, a `_finishTimer`
elvágása mellett. Őrcella: a `LiveScreen` unmountja után a notifier ne fogadjon
listenert.

### MINOR-2 — a Finish tartalék-célja (`/learn`) önkényes és semmilyen teszt nem pinneli

`lib/features/live/screens/live_screen.dart:166–170`

```dart
if (context.canPop()) { context.pop(); } else { context.go(AppRoutes.learn); }
```

**Mérve:** az adaptív shell flag **defaultból KI** (E13-R17), és ekkor
`entryLocation = AppRoutes.live` (`app_router.dart:212`). A `/live` tehát a
belépési útvonal, ahol `canPop()` **hamis** — vagyis a mai alapbeállításban a
Finish **mindig** a Learn képernyőre visz, nem ritka éldeset. Ezt egyetlen
teszt sem rögzíti (`grep -rn "AppRoutes.learn\|/learn" test/features/live/`
→ üres), és sem a brief, sem az ADR 0276 nem nevez meg célt.

**Javasolt irány:** a tartalék legyen az alkalmazás belépési útvonala
(`adaptiveShellEnabled ? today : live`-szemantika), vagy — ha a Learn a
szándék — kapjon cellát és egy mondat indoklást a §10-ben. A lényeg, hogy a
default út ne implicit döntés legyen.

### NOTE-1 — az `idle` és a `countIn` transport-állapot a Live úton nem áll elő

A `transportStatus` csak `disabled`/`finishing`/`paused`/`active` értéket vesz
fel; a `countIn` elérhetetlenségét a §0.0/R8 előre kimérte, az `idle`-t pedig a
kód doc-commentje indokolja (a session mountkor autostartol, és az `isLoading`-ra
kapcsolás minden resume-nál elvillantaná a Pause-t). Ez **helyes és
dokumentált** — nem lelet, csak rögzítendő, hogy a §3 kilenc állapota közül
ezt a kettőt a hero/feedback/timeline slot különbözteti meg, nem a transport.

## 4. Merge-feltételek

| Feltétel | Állapot |
|---|---|
| scope-audit (kör-diff) | ✅ OK, 22 út |
| célzott gate izolált klónban | ✅ 17/17 ZÖLD |
| valódi-sértés próbák | ✅ A2, A4, A5 mind PIROSRA váltott |
| Router CI a merge SHA-n | ✅ `32899640698` success @ `16e07661` |
| Full Gate a merge SHA-n | a merge előtt ellenőrizve |
| BLOCKER/MAJOR | ✅ nincs |

A két MINOR nem blokkolja a merge-öt; javításuk egy rövid javító körben
történik (ugyanaz a motor, ez a leletlista), utána a CI a friss SHA-n újra fut.

## 5. Javító kör — `daa5a369` (ugyanaz a motor, ez a leletlista)

**VÉGSŐ DÖNTÉS: APPROVED — 0 nyitott lelet.**

A javító kör 4 fájlt érintett (`+127 −2`), scope-audit
`OK (16e07661bd65..daa5a3699765, 5 changed path(s), 1 generated/ignored)`.

### 5.1 MINOR-1 — LEZÁRVA

`live_screen.dart:112` — `_liveRegion.dispose()` bekerült a `dispose()`-ba, a
`_finishTimer?.cancel()` után, a `super.dispose()` maradt utolsó.

**Zárás-ellenőrzés (saját próba):** a `dispose()` sor ismételt eltávolítása
után az új cella PIROSRA vált —
`(5) dispose — unmounting Live disposes its SsLiveRegion, not just its listeners (review MINOR-1)`.
A cella tehát valódi őr, nem utólagos díszlet.

### 5.2 MINOR-2 — LEZÁRVA

`live_screen.dart:169–194` — a tartalék-cél már a router SAJÁT szemantikáját
tükrözi (`adaptiveShellEnabled ? today : live`, a publikus `appConfigProvider`-ből
olvasva, a `lib/app/routing/**` érintése NÉLKÜL). Ha a belépési útvonal maga a
`/live` — a mai, shell-flag-KI default —, a Finish **nem navigál sehová**: a
session helyben ér véget (mikrofon + wakelock leáll, a kép `paused`-ra vált).

**Zárás-ellenőrzés (saját próba):** az önkényes `context.go(AppRoutes.learn)`
visszaállítása után az új cella PIROSRA vált —
`Finish fallback target is the app entry route, not a fixed screen (review MINOR-2) … /live IS the entry route — Finish ends the session in place instead of hopping to Learn`.

### 5.3 A javító kör utáni teljes újramérés (friss `/tmp` klón)

`/tmp/review-e13-r18-fix` @ `daa5a369`: a 12 elemű `gate_tests` teljes során
**17/17 ZÖLD** (format, analyze, 12 teszt-út, architecture, secrets, l10n).
Az A4 mikrofon-cellák száma 4-ről 5-re nőtt, az A2/A5 cellák változatlanok —
a mérce nem gyengült, csak bővült.

**Minden próba visszaállítva**, mindkét klónban `git diff --stat` üres.
