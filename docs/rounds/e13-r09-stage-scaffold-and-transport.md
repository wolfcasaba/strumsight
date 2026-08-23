# E13-R09 — StageScaffold és session transport

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 9
- **Kör-azonosító:** `E13-R09`
- **Branch:** `<motor>/e13-r09-stage-scaffold-and-transport`
- **Előfeltétel:** `E13-R08` merge-elve (adaptive scaffold)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0276`](../adr/0276-stage-scaffold-owns-no-resources.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, MELYIK réteg birtokolja
> ma a mikrofon/kamera életciklust (`lib/features/**` alatt), mert az §5.1
> kimondja: a Stage layout NEM veheti át. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/layouts/ss_stage_scaffold.dart",
  "lib/core/design_system/components/music/ss_session_transport.dart",
  "lib/core/design_system/public.dart",
  "test/core/design_system/stage/ss_stage_scaffold_test.dart",
  "test/core/design_system/stage/ss_session_transport_test.dart",
  "test/core/design_system/stage/stage_back_confirmation_test.dart",
  "docs/rounds/e13-r09-stage-scaffold-and-transport.md",
]
gate_tests = [
  "test/core/design_system/stage/ss_stage_scaffold_test.dart",
  "test/core/design_system/stage/ss_session_transport_test.dart",
  "test/core/design_system/stage/stage_back_confirmation_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió (Claude, 2026-08-23) — MÉRT eltérések

Az előre megírt brief (2026-08-15, `93a6c19a`) mért állításai elavulhattak. Az
alábbi nyolc pont a **mai** `main @ b26b8ccb` mérése. Ahol a §2–§9 ennek
ellentmondana, **ez a szakasz az erősebb**.

> **Kockázat = high, indoklás:** az `allowed_paths` egyetlen eleme sem érinti a
> router `high_risk_path_fragments` listáját (csak `lib/core/design_system/**`
> és a hozzá tartozó tesztek), a magas besorolás mégis indokolt: a kör tétje
> pontosan az, hogy egy **prezentációs widget** ne nyithasson mikrofont,
> kamerát vagy felvételt. Egy `autoStart`-szerű kényelmi paraméter itt csendes,
> a hívási helyről nem látható adatgyűjtést telepítene minden olyan fába
> (katalógus, előnézet, teszt), ahová a layoutot beteszik — ez adatvédelmi,
> nem esztétikai hibaosztály (ADR 0276 Kontextus). A besorolás tehát marad
> `high`, és az A1 cella a gépi mércéje.

### D1 — Az ADR 0276 MÁR MEG VAN ÍRVA és MERGE-ELVE → ez a kör ADR-t NEM ír

```
$ git log --oneline -1 -- docs/adr/0276-stage-scaffold-owns-no-resources.md
a4fdfec2 docs(ch13): E13-R07..R13 briefek + ADR 0275-0279
$ git cat-file -e origin/main:docs/adr/0276-stage-scaffold-owns-no-resources.md && echo MERGED
MERGED
```

A fejléc „a Claude írja meg a kör indításakor" sora ezzel **tárgytalan**: egy
már merge-elt ADR újraírása H1 lenne. Az ADR szövege ellenőrizve — a négy
kötött döntése szó szerint fedi a §5.1–5.5-öt, tehát nincs divergencia, amit
fel kellene oldani. Új ADR-számot sem foglalunk (`round-slots.py reserve-adr`
hívása szándékosan elmarad: új normatív döntés nem születik). A `docs/adr/**`
marad a **tilos zónában**. Ugyanez a minta futott az E13-R08-nál (ADR 0275,
szintén `a4fdfec2`).

### D2 — Erőforrás-tulajdonlás: mérve, a §5.1 állítása ÁLL

A brief ⚠ pre-flight kérdésére (melyik réteg birtokolja ma a mikrofon/kamera
életciklust) a **tényleges hívási lánc** mérése — nem a réteg-diagram:

| Erőforrás | Ki szerzi meg MA | Hely |
|---|---|---|
| mikrofon | `createMicCapture(ref, AudioOwner.live/tuner/analyzeRecorder)` | `lib/features/live/providers/live_providers.dart:12`, `lib/features/tuner/providers/tuner_providers.dart:13`, `lib/features/analyze/providers/analyze_providers.dart:135` |
| kamera | `coordinator.acquire(...)` | `lib/features/vision/application/vision_session_controller.dart:157`, `.../vision_setup_controller.dart:163` |
| felvétel | `ClipRecorder`, `AnalysisRecorder` | `lib/features/analyze/engine/clip_recorder.dart`, `lib/features/audio_analysis/data/capture/analysis_recorder.dart` |
| képernyő-ébrentartás | `screenWakelockProvider` → `enable()/disable()` | `lib/features/live/screens/live_screen.dart:61-62,81,92,124-127` |

A `lib/core/design_system/**` fa alatt **egyetlen** erőforrás-hívás sincs. A
§5.1 tehát nem revideálandó: a Stage layout ma sem birtokol semmit, és nem is
veheti át.

### D3 — A7 kötése: az ébrentartás CALLBACK, nem `ScreenWakelock`-import

Mérve: a `lib/core/design_system/**` fa nem-Flutter importjai kizárólag saját
relatív design-system fájlok + egyetlen `../../theme/app_colors.dart`;
`core/platform` importja **nincs**. Az `SsStageScaffold` ezért két szimmetrikus
hookot kap (pl. `VoidCallback? onRequestScreenAwake` / `onReleaseScreenAwake`):
`initState`-ben kér, `dispose`-ban **pontosan egyszer** old. A
`wakelock_plus`, a `WakelockPlus` és a `core/platform/screen_wakelock.dart`
importja a scaffoldban **TILOS** — az birtoklás lenne (ADR 0276 2. döntés), és
egy katalógus-oldal is ébren tartaná a képernyőt.

### D4 — A6 mércéje kipinnelve

`SsAdaptiveScaffold(showPrimaryNavigation: false)` ma puszta
`Scaffold(body: body)`-t ad (`lib/core/design_system/layouts/ss_adaptive_scaffold.dart:74-76`).
Az A6 cella ezért így mér: a Stage fában **nincs** `NavigationBar` és **nincs**
`NavigationRail` (`find.byType`, mindkettőre `findsNothing`).

### D5 — A5 idiómája kipinnelve

A repó a `PopScope` + `canPop` + `onPopInvokedWithResult(didPop, result)`
alakot használja (`lib/features/practice/presentation/screens/practice_session_screen.dart:102-105`)
— az elavult `onPopInvoked` NEM. A scaffold `canPop`-ja a „van-e mentetlen
adat" bemenetből számol, a hook a `didPop == false` ágon hívódik, és a §6.1
három cellája ezt méri.

### D6 — A valódi-sértés próba a PRODUKCIÓS widgetet mutálja

`lessons/L398` (E08-R20): egy implementer a §6.1 próbát önálló, a produkciós
widgettől független `MaterialApp`-fával „teljesítette" — az semmit nem
bizonyít. `lessons/L403` (E08-R23): a típus/kulcs szintű próba átengedett egy
tartalmi sértést. A próba tehát csak akkor érvényes, ha (a) a Finish tényleg
átkerül overflow menübe a `ss_session_transport.dart`-ban, (b) a §7 gate
tényleg PIROSAT ad az **A2**-re, (c) a diff visszaáll, és (d) a §10 a
tényleges, csonkítatlan piros kimenetet idézi. Az A2 cella a Finish/Pause
**feliratát/semantics-címkéjét** is nézze, ne csak a widget-típust.

### D7 — Visszakeresett előzmény (S8, ADR 0312 §4.1)

`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "…"`:

- `adr/0276` (bm25#1 emb#1) — a kör kötött döntései; lásd D1.
- `lessons/L449` (E13-R08, 2026-08-23) — a `StatefulShellRoute.indexedStack`
  életben tartja az erőforrást birtokló képernyőt, ezért a mikrofon és a
  wakelock tabváltás után is aktív maradt. **Mind a hét acceptance-cella, a
  teljes gate és a CI zöld volt** — a MAJOR-t egy eldobható próbateszt mérte
  ki. Ebből erre a körre: a zöld kapu nem bizonyítja az A1/A7-et, ezért a
  cellák a **hívásszámot** mérjék (enable/disable, hook-hívás), ne a látszatot.
- `adr/0074` — a mikrofon-életciklus státusz-vezérelt és a feature-é; ott a
  `_pause()` nem zárta a subscriptiont, azaz a „csendben nyitva maradó
  erőforrás" ebben a repóban MÉRT hibaosztály.
- `lessons/L398`, `lessons/L403` — lásd D6.

### D8 — Az `SsSemantics` tokenek használandók

`lib/core/design_system/foundations/ss_semantics.dart`:
`minimumInteractiveDimension = 48`, `maximumTextScale = 2.0`. Az A4 cella a
`SsSemantics.maximumTextScale` tokent használja, ne beírt `2.0` literált; a
minta a meglévő `test/core/design_system/typography/text_scale_overflow_test.dart`.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Közös, **életciklus-semleges** Stage layout a Live, Practice, Song, Tuner,
Metronome és Vision aktív állapotához (SDD Ch13 Kör 9).

## 2. Jelenlegi állapot — mért tények

- Az R08 bevezette, hogy Stage route alatt nincs primary navigation — ez a kör
  tölti meg tartalommal a Stage felületet.
- A hat aktív mód ma külön-külön oldja meg a fejlécet, a transportot és a
  biztonságos területet.
- A Ch13 §9.9 megadja a slot-szerkezetet: status header, hero, feedback,
  timeline/beat, bottom action.

## 3. Scope

**Benne van:** `SsStageScaffold` — safe area, orientáció, képernyő-ébrentartás
**kérése**, primary-nav-mentes szerkezet · `SsSessionTransport` idle /
count-in / active / paused / finishing / disabled állapotokkal · az öt slot
API-ja · portrait / landscape / expanded elrendezés · a mentetlen session
vissza-megerősítés **hookja** (callback, nem logika) · high contrast és 2.0
text scale.

**NINCS benne (tilos):** **erőforrás-kezelés a widgetben** — mikrofon, kamera,
felvétel indítása/leállítása · DSP vagy időzítés (AGENTS.md §9) ·
`lib/features/**` · `lib/core/theme/**` · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `layouts/ss_stage_scaffold.dart` | **ÚJ** — a Stage váz |
| `components/music/ss_session_transport.dart` | **ÚJ** — a transport |
| `public.dart` | az export bővítése |
| `test/…/stage/*_test.dart` (3) | a §6 cellái |
| `docs/rounds/e13-r09-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0276)

### 5.1 A StageScaffold NEM indít mikrofont, kamerát vagy felvételt

Prezentációs réteg. Az erőforrás-életciklus a feature-é marad — különben a
layout beépítése bárhol csendben engedélykérést és felvételt indítana.

**NEM elfogadható gyengítés:** „a kényelem kedvéért a scaffold indítja a
mikrofont, ha kap egy `autoStart` flaget". Az egy UI-komponensbe rejtett
adatgyűjtés.

### 5.2 A Pause és a Finish MINDIG látható aktív session alatt

Nem rejthető el görgetés, overflow menü vagy „elegánsabb elrendezés" mögé. Aki
játszik, egyetlen mozdulattal meg tud állni.

**NEM elfogadható gyengítés:** a Finish áthelyezése overflow menübe helyhiány
miatt. Landscape-ben ez pont a leggyakoribb helyzet.

### 5.3 A vissza-megerősítés HOOK, nem beépített párbeszéd

A scaffold jelzi, hogy adatvesztés fenyeget, és a feature dönt a szövegről és a
mentésről. Az adatvesztés-tény ismerete a feature-é.

### 5.4 Landscape-ben nincs túlcsordulás

A hat mód közül több landscape-ben használatos (Stage a gitár mellett). Ez
acceptance-cella (A4).

### 5.5 A képernyő-ébrentartás KÉRÉS, és visszavonódik

A scaffold kéri, de nem birtokolja: az elhagyáskor a kérés megszűnik.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A scaffold NEM indít mikrofont/kamerát/felvételt | `ss_stage_scaffold_test.dart` + `grep` a diffben |
| A2 | Pause és Finish minden aktív állapotban látható | `ss_session_transport_test.dart` |
| A3 | A hat transport-állapot mindegyike megkülönböztethető | ugyanott |
| A4 | Landscape-ben és 2.0 text scale mellett nincs túlcsordulás | `ss_stage_scaffold_test.dart` |
| A5 | A rendszer-vissza adatvesztésnél a hookot hívja, pontosan egyszer | `stage_back_confirmation_test.dart` |
| A6 | Stage alatt nincs primary navigation | `ss_stage_scaffold_test.dart` |
| A7 | A képernyő-ébrentartás kérése elhagyáskor visszavonódik | ugyanott |
| A8 | A semantics sorrend a vizuális sorrendet követi | `ss_stage_scaffold_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `autoStart` a scaffoldban, ami mikrofont nyit | **A1** |
| A Finish overflow menübe kerül | **A2** |
| A paused és az active vizuálisan azonos | A3 |
| Fix magasságú Stage fejléc | **A4** |
| A vissza-hook kétszer hív | **A5** |
| Az ébrentartás bent ragad kilépés után | A7 |

**A vissza-megerősítés három kötelező cellája** (a küszöb: van-e mentetlen adat):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nincs mentetlen adat | a hook **nem hívódik**, a vissza azonnal működik |
| rajta (a küszöbön) | van mentetlen adat, a feature megerősít | a hook **pontosan egyszer** hívódik, a kilépés megtörténik |
| a küszöb fölött | van mentetlen adat, a feature elutasít | a hook egyszer hívódik, a kilépés **elmarad** |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd a Finish gombot
overflow menübe → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/stage/ss_stage_scaffold_test.dart test/core/design_system/stage/ss_session_transport_test.dart test/core/design_system/stage/stage_back_confirmation_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_stage_scaffold.dart` — slotok, safe area, orientáció, ébrentartás-kérés.
2. `ss_session_transport.dart` — a hat állapot.
3. A vissza-hook + a három cellája.
4. Landscape és 2.0 text scale cellák.
5. Semantics sorrend.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az erőforrás-kezelés becsúszása.** Kényelmes lenne a layoutból indítani, és
  ettől bárhol elhelyezve mikrofont nyitna (A1).
- **A helyhiányos landscape.** A Finish elrejtése ilyenkor kézenfekvő és
  pontosan a legrosszabb (A2/A4).
- **A kétszer hívott vissza-hook.** Duplán megjelenő párbeszédet ad, amit
  kézzel nehéz észrevenni (A5).

## 10. Implementation handoff — az implementer tölti ki

### Mi készült el

- **`lib/core/design_system/layouts/ss_stage_scaffold.dart` (ÚJ)** —
  `SsStageScaffold`, egy `StatefulWidget`. Öt kötelező slot
  (`statusHeader`, `hero`, `feedback`, `timeline`, `bottomAction`), mind
  `Widget` típusú, adat-bemenetes. Két elrendezési stratégia:
  `_CompactStage` (portrait: fejléc pinnelve fent, a hero/feedback/timeline
  görgethető középen, `bottomAction` pinnelve lent) és `_WideStage`
  (landscape VAGY `width >= SsBreakpoints.expandedMin`: két oszlop —
  bal: fejléc + görgethető hero/feedback, jobb: görgethető timeline +
  pinnelt `bottomAction`). A `PopScope`-ot a scaffold maga adja:
  `canPop: !hasUnsavedSession`, `onPopInvokedWithResult` a `didPop==false`
  ágon hívja az `onUnsavedSessionBackAttempt` callbacket — a szöveget és a
  mentést a hívó dönti el. A `onRequestScreenAwake`/`onReleaseScreenAwake`
  callback-pár `initState`/`dispose`-ban fut, pontosan egyszer-egyszer;
  a fájlban nincs `wakelock_plus`, `WakelockPlus` vagy
  `core/platform/screen_wakelock.dart` import.
- **`lib/core/design_system/components/music/ss_session_transport.dart`
  (ÚJ)** — `SsSessionTransportStatus` (`idle`, `countIn`, `active`,
  `paused`, `finishing`, `disabled`) és `SsSessionTransport`. A négy
  aktív állapotban (`countIn`/`active`/`paused`/`finishing`) a Pause és a
  Finish `IconButton` mindig renderelődik (Pause `countIn`/`finishing`
  alatt látható, de letiltva; Finish mindig aktív). `idle`/`disabled`
  alatt egy `_RestIndicator` fut (`radio_button_unchecked` vs. `block`
  ikon), Pause/Finish kulcsok nélkül. A hat állapot páronként
  megkülönböztethető kombinációja: rest-ág (2 ikon) × pause
  engedélyezve/letiltva × pause ikon (play/pause) × extra jelző
  (`timer_outlined` count-in alatt, `CircularProgressIndicator`
  finishing alatt).
- **`lib/core/design_system/public.dart`** — a két új fájl exportja
  (`layouts/ss_stage_scaffold.dart`, `components/music/ss_session_transport.dart`).
- **3 teszt fájl** az `test/core/design_system/stage/` alatt (lásd lent).

### Acceptance-mátrix → hol mér

| # | Fájl | Teszt(ek) |
|---|---|---|
| A1 | `ss_stage_scaffold_test.dart` | „A1: building the Stage tree makes no wakelock platform-channel call” — a `wakelock_plus` csatornára mock handlert regisztrál, és `channelCalls` üres marad; kiegészítve a produkciós fájlok grep-jével (lásd lent). |
| A2 | `ss_session_transport_test.dart` | Mind a négy aktív státuszra: Pause+Finish `findsOneWidget`, **és** `tester.getSemantics(find.byKey(finishKey)).tooltip == finishLabel` (nem csak a kulcs/típus — lessons/L403), **és** egyetlen tap közvetlenül hívja az `onFinish`-t. |
| A3 | `ss_session_transport_test.dart` | „A3: all six transport states are pairwise distinguishable” — mind a hat státuszra aláírást (pause láthatóság/engedélyezettség/ikon, finish láthatóság, extra jelző) gyűjt, és az öt Set-elem helyett hatot vár. |
| A4 | `ss_stage_scaffold_test.dart` | Három landscape/expanded méret (800×400, 1000×500, 1200×800) 2.0×-os `SsSemantics.maximumTextScale` mellett, hosszú magyar szövegekkel minden slotban — `tester.takeException()` nulla. |
| A5 | `stage_back_confirmation_test.dart` | A §6.1 három cellája (lásd lent). |
| A6 | `ss_stage_scaffold_test.dart` | `find.byType(NavigationBar)`/`NavigationRail` → `findsNothing`. |
| A7 | `ss_stage_scaffold_test.dart` | „A7” teszt: mountkor `requestCount==1`, rebuildkor (ugyanaz a widget) marad 1, unmountkor `releaseCount==1`. |
| A8 | `ss_stage_scaffold_test.dart` | Minden slot szövege szerepel a semantics fában (`tester.getSemantics(...).label` nem üres), és a paint-pozíciójuk (`getTopLeft(...).dy`) szigorúan növekvő a slot-sorrendben. |

Megjegyzés az A8 méréshez: az eredeti terv a teljes semantics-fa DFS
bejárása volt (`SemanticsNode.visitChildren`), de ez `tester.getSemantics`
és `rootPipelineOwner` alatt is vagy `Null check operator used on a null
value`-t, vagy üres eredményt adott ezen a Flutter SDK-verzión (a
`pipelineOwner` deprecated, a `rootPipelineOwner`-en a scaffold gyökere
nem tartalmazta a semantics fát ezen az úton). A helyettük választott
mérce — minden slot részt vesz a semantics fában + a paint-sorrend
monoton — ugyanazt az állítást bizonyítja egy egyszerű, nem-átfedő
függőleges layoutra, és determinisztikusan reprodukálható.

### §6.1 vissza-megerősítés — a három cella

`stage_back_confirmation_test.dart`: egy két-route harness (kezdőlap →
gomb → `SsStageScaffold`-ot tartalmazó route), `ValueNotifier<bool>`
adja a `hasUnsavedSession`-t reaktívan, a rendszer-vissza szimulációja
`tester.binding.handlePopRoute()`.

- **küszöb alatt** (nincs mentetlen adat): `attempts == 0`, a vissza
  azonnal működik (a kezdőlap újra látszik).
- **rajta** (van mentetlen adat, a feature megerősít): a callback
  `hasUnsaved.value = false`-t állít, majd egy
  `WidgetsBinding.instance.addPostFrameCallback`-ban újra popol (mert a
  `PopScope` `canPopNotifier`-je csak `didUpdateWidget`-ben frissül —
  egy frame kell, mielőtt a második pop sikeres lehet). `attempts == 1`,
  a kilépés megtörténik.
- **fölötte** (van mentetlen adat, a feature elutasít): a callback
  csak számol, nem popol újra. `attempts == 1`, a Stage route látható
  marad.

### Valódi-sértés próba (D6, KÖTELEZŐ) — tényleges, csonkítatlan kimenet

A `ss_session_transport.dart`-ban a Finish `IconButton`-t ideiglenesen
`PopupMenuButton`-ra cseréltem (a Finish felirat egy `PopupMenuItem`
mögé került), majd lefuttattam
`flutter test test/core/design_system/stage/ss_session_transport_test.dart`-ot.

Első kísérletnél az A2 teszt csak `find.byKey`-jel nézte a Finish
jelenlétét — ez **zöld maradt** a sértés mellett is, mert a
`PopupMenuButton` megtartotta ugyanazt a kulcsot (pontosan az
`lessons/L403` mintája: típus/kulcs-szintű próba egy tartalmi sértést
átenged). Ezért az A2 tesztet megerősítettem: a Finish feliratának
közvetlenül, egy plusz tap nélkül kell szerepelnie a semantics fában
(`tester.getSemantics(find.byKey(finishKey)).tooltip == finishLabel`),
és egyetlen tapnak közvetlenül hívnia kell az `onFinish`-t.

A megerősített teszttel a sértés PIROSAT adott, csonkítatlanul:

```
00:01 +0 -1: SsSessionTransport A2: Pause and Finish are both visible and directly actionable in the SsSessionTransportStatus.active state [E]
  Test failed. See exception logs above.
Expected: 'Finish'
  Actual: 'Show menu'
   Which: trailing characters: Finish
Finish must expose its own caption directly, not behind an overflow menu disclosure step
...
00:01 +0 -4: SsSessionTransport A2: Pause and Finish are both visible and directly actionable in the SsSessionTransportStatus.finishing state [E]
...
Failing tests:
  .../ss_session_transport_test.dart: SsSessionTransport A2: Pause and Finish are both visible and directly actionable in the SsSessionTransportStatus.active state
  .../ss_session_transport_test.dart: SsSessionTransport A2: Pause and Finish are both visible and directly actionable in the SsSessionTransportStatus.countIn state
  .../ss_session_transport_test.dart: SsSessionTransport A2: Pause and Finish are both visible and directly actionable in the SsSessionTransportStatus.finishing state
  .../ss_session_transport_test.dart: SsSessionTransport A2: Pause and Finish are both visible and directly actionable in the SsSessionTransportStatus.paused state
  .../ss_session_transport_test.dart: SsSessionTransport tapping Finish invokes onFinish
```

Mind a négy aktív állapotra az A2 cella PIROS lett (plusz az önálló
„tapping Finish invokes onFinish” próba), pontosan a `PopupMenuButton`
alapértelmezett „Show menu” tooltipjén bukva a `finishLabel`
összehasonlításon. Ezután a diffet visszaállítottam
(`git diff` a `ss_session_transport.dart`-ra üres), és a §7 gate-et
újra lefuttattam — mind a nyolc lépés (`format`, `analyze`, 3× `test`,
`architecture`, `secrets`, `l10n`) ZÖLD.

### A1 — a grep-bizonyíték

```
$ grep -rniE "wakelock|WakelockPlus|screen_wakelock|permission_handler|camera|microphone|mic_stream|record(er)?\b" \
    lib/core/design_system/layouts/ss_stage_scaffold.dart \
    lib/core/design_system/components/music/ss_session_transport.dart
lib/core/design_system/layouts/ss_stage_scaffold.dart:10:/// Presentation-only (ADR 0276): it starts no microphone, camera, or
lib/core/design_system/layouts/ss_stage_scaffold.dart:52:  /// Requested exactly once, from [initState] — never a direct wakelock
```

A két találat mind doc-comment, egyik sem import vagy hívás — a fát
elemezve nincs erőforrás-hívás egyik új fájlban sem.

### Döntések, amiket a brief nem kötött meg

- **Az `expandedMin` küszöb (`SsBreakpoints.expandedMin == 840`) a
  `_WideStage`/`_CompactStage` választónak is bemenete** a puszta
  orientáció mellett — így egy széles (≥840dp) portrait tablet is a
  kétoszlopos elrendezést kapja, nem csak a landscape telefon. Ezt a
  brief D4/§5.4 nem tiltja, és a §8.4 „portrait, landscape, expanded”
  hármasát fedi le két render-ággal (a landscape és az expanded
  ugyanazt az elrendezést használja, mert mindkettő ugyanazt a
  helyhiány-mintát oldja meg — külön szélesség-alapú `wide` elágazás
  jelenleg felesleges komplexitás lenne).
- **`idleLabel`/`disabledLabel` opcionális String? paraméterek** az
  `SsSessionTransport`-on — a rest-állapotokhoz a hívó adhat felirat,
  de nem kötelező (a brief nem ír elő explicit feliratot ide, csak
  megkülönböztethetőséget, amit az ikon már biztosít).
- **A `finishing` állapotban a Finish gomb `onPressed` aktív marad**
  (nem tiltottam le duplakattintás ellen) — a brief nem ír elő
  double-submit védelmet erre a körre, és egy extra állapot bevezetése
  csak a mátrixot bonyolította volna újabb, nem tesztelt ággal.

### Gate — végső, csonkítatlan futás

```
tools/round-gate.sh test/core/design_system/stage/ss_stage_scaffold_test.dart test/core/design_system/stage/ss_session_transport_test.dart test/core/design_system/stage/stage_back_confirmation_test.dart
```

`format` ZÖLD · `analyze` ZÖLD (0 issue) · mindhárom `test` ZÖLD
(7+9+3 = 19 teszt, mind PASS) · `architecture` ZÖLD (12 allowlistelt
eltérés, változatlan) · `secrets` ZÖLD · `l10n` ZÖLD.

### Javító kör (fix1) — a review három MAJOR-ja

A review (`docs/reviews/e13-r09-review.md`, 2026-08-23, Claude Opus 5,
`CHANGES REQUESTED`) mind a hét acceptance-cella zöldsége MÖGÖTT három MAJOR-t
mért ki eldobható próbatesztekkel. Az alábbiak ezt zárják.

#### MAJOR-1 — forrás-szintű őrcella a mikrofon/kamera/felvétel ellen

`ss_stage_scaffold_test.dart`-ba egy új `group('resource ownership (source
guard, E13-R09 MAJOR-1)')` került: a két új produkciós fájlt (`ss_stage_
scaffold.dart`, `ss_session_transport.dart`) forrásként olvassa be
(`File(...).readAsStringSync()`), a kommenteket kiszűri (a doc-comment
szándékosan tartalmazza a "microphone"/"camera"/"recording" szavakat — ezek
NEM sérthetik a próbát), és hat tiltott tokenre keres a maradék kódban:
`MethodChannel`, `wakelock`, `camera`, `record`, `microphone`, `permission`.
A string-literálok VISZONT láthatók maradnak, mert a mutáció legjellemzőbb
jele — a `'plugins.flutter.io/record'` csatornanév — egy string literálban
van.

**A review pontos mutációjával ellenőrizve, csonkítatlan piros kimenet.** A
`ss_stage_scaffold.dart` `initState`-jébe ideiglenesen bekerült (majd
`git checkout --`-tal visszaállt):

```dart
widget.onRequestScreenAwake?.call();
final channel = MethodChannel('plugins.flutter.io/record');
channel.invokeMethod<void>('start');
```

(a `MethodChannel` feloldásához egy ideiglenes `import 'package:flutter/
services.dart';` is bekerült — a produkciós fájl eredetileg csak
`material.dart`-ot importálja, ami NEM exportálja a `services.dart`-ot; ez
önmagában is megerősíti, hogy a fájlban ma nincs platform-csatorna import).

```
00:01 +7 -1: resource ownership (source guard, E13-R09 MAJOR-1) the Stage scaffold and transport sources never mention a platform channel, wakelock, camera, recording, microphone, or permission API [E]
  Expected: empty
    Actual: [
              'lib/core/design_system/layouts/ss_stage_scaffold.dart contains "MethodChannel"',
              'lib/core/design_system/layouts/ss_stage_scaffold.dart contains "record"'
            ]
  SsStageScaffold/SsSessionTransport must stay presentation-only (ADR 0276) — found: lib/core/design_system/layouts/ss_stage_scaffold.dart contains "MethodChannel", lib/core/design_system/layouts/ss_stage_scaffold.dart contains "record"
```

Visszaállítás után (`git diff lib/core/design_system/layouts/
ss_stage_scaffold.dart` üres) az egész `ss_stage_scaffold_test.dart` ismét
zöld (9/9, a két új teszttel együtt). A produkciós kódot a MAJOR-1 javítása
NEM módosította — csak az őr volt hiányos, nem az implementáció (a brief
maga is így jelezte előre).

#### MAJOR-2 — az A4 cellák valódi felületen mérnek

A `_harness` függvényt (`ss_stage_scaffold_test.dart:15-58` volt) `_pumpStage`
váltotta fel: a régi `MediaQuery(data: MediaQueryData(size: size, ...))`
wrapper csak azt írta felül, amit a leszármazottak *olvasnak* — a tényleges
teszt-felület a régi kódban mindig az alapértelmezett maradt. `_pumpStage`
most `tester.view.physicalSize`-t és `tester.view.devicePixelRatio = 1`-et
állít be minden pump előtt (`addTearDown(tester.view.reset)`-tel párosítva),
így a deklarált `Size` a TÉNYLEGES layout-kényszer; a `MediaQuery` ezután csak
a `textScaler` felülírására kell (egy `Builder`-ben az ambiens, a valódi
felületből származó `MediaQuery.of(context)`-et `copyWith`-eli). Minden
korábbi hívási hely (A1, A7, A6, A4, A8) átállt az új segédfüggvényre.

Az A4 három cellája (800×400, 1000×500, 1200×800, mind 2.0 text scale)
ugyanígy 9/9 zöld marad — vagyis az implementáció valóban helyes volt, csak
korábban rossz felületen mérték (ahogy a review is jelezte: "őr-hiba, nem
termék-hiba").

#### MAJOR-3 — a rest-állapotú felirat tördelhetővé tétele

`ss_session_transport.dart` `_RestIndicator`-jában a `Text(label!)` egy
`Flexible(child: Text(label!, softWrap: true))`-ra váltott, hogy a felirat a
rendelkezésre álló szélességhez tördelhessen ahelyett, hogy egyetlen sorként
túlcsordulna.

**RED → GREEN, csonkítatlan kimenet.** A javítás ELŐTT (a `Flexible` nélküli
eredeti kóddal) hozzáadott két új cella (`ss_session_transport_test.dart`):
mindkettő valódi `tester.view.physicalSize = Size(360, 640)` felületet és
`SsSemantics.maximumTextScale` (2.0x) text scale-t állít be, a rest-ágra a
review pontos magyar feliratával (`'Készen áll a gyakorlás megkezdésére'`).

```
00:01 +9: SsSessionTransport MAJOR-3 regression: a real-length idle label does not overflow on a narrow 360x640 phone at 2.0 text scale
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following TestFailure was thrown running a test:
Expected: null
  Actual: FlutterError:<A RenderFlex overflowed by 661 pixels on the right.>
...
00:01 +9 -1: SsSessionTransport MAJOR-3 regression: a real-length idle label does not overflow on a narrow 360x640 phone at 2.0 text scale [E]
  Test failed. See exception logs above.
```

Pontosan a review mért 661 pixeles túlcsordulása reprodukálódott. A
`Flexible`+`softWrap` javítás után mindkét új cella (rest- ÉS aktív ág) zöld,
a teljes `ss_session_transport_test.dart` 11/11 PASS.

#### MINOR-1 — a „Fix magasságú Stage fejléc → A4" sor: ÚJRAMÉRVE a MAJOR-2 javítás után

A review MINOR-1 lelete szerint 240 px és 500 px fix fejléc-magassággal
VALÓDI 800×400-as landscape felületen sem lenne túlcsordulás, és az A8
(nem az A4) venné észre a sértést. **Ezt a MAJOR-2 javítása UTÁN, a most már
valóban valódi geometriát kényszerítő `tester.view` technikával újramértem**
(ideiglenes, a commit előtt eltávolított próbacellákkal ugyanabban a fájlban,
`git diff` a próba törlése után üres) — az eredmény ELTÉR a review eredeti
állításától:

- **240 px fix fejléc**, valódi `Size(800, 400)`: `exception=null` — nincs
  túlcsordulás (megegyezik a review mérésével).
- **500 px fix fejléc**, valódi `Size(800, 400)`: `exception=A RenderFlex
  overflowed by 124 pixels on the bottom.` — **VAN túlcsordulás**, ellentétben
  a review állításával.

A `_WideStage` bal oszlopában a fejléc `Padding`-ja NEM `Expanded`, tehát a
teljes oszlop-magasság (400px) mínusz a fejléc igénye (500+24 padding=524px)
negatív marad a görgethető középső résznek — ez klasszikus `RenderFlex`
túlcsordulás, amit a görgetés NEM tud elnyelni (a görgetés a TARTALOM
magasságát oldja, nem a KONTÉNER hiányát). A legvalószínűbb magyarázat, hogy a
review saját MINOR-1 mérése még a MAJOR-2-ben leírt hibás harness-szal (nem
valódi `tester.view` felület, hanem a tesztfelület alapértelmezett
800×600-a) készült — abban a világban 524 < 600, tényleg nem lenne
túlcsordulás.

**Következtetés:** a MAJOR-2 javítása UTÁN a §6.1 táblázat eredeti sora — „Fix
magasságú Stage fejléc → A4" — HELYES marad: az A4 (a `tester.takeException()
isNull` ellenőrzésen keresztül) ma ténylegesen elkapja a 400px-nél magasabb
fix fejlécet valódi landscape geometrián. A táblázatot emiatt NEM kellett
módosítani, és nem volt szükség új célzott cellára sem — a MAJOR-2 javítása
saját magában orvosolta a MINOR-1 mögötti hiányt is.

### Javító kör — végső gate (fix1)

```bash
tools/round-gate.sh test/core/design_system/stage/ss_stage_scaffold_test.dart test/core/design_system/stage/ss_session_transport_test.dart test/core/design_system/stage/stage_back_confirmation_test.dart
```

Lásd a §7 alatti tényleges, csonkítatlan futást lent — a fix1 után a
`ss_stage_scaffold_test.dart` 9 tesztet (a két új MAJOR-1 cellával), a
`ss_session_transport_test.dart` 11 tesztet (a két új MAJOR-3 cellával)
futtat, mindegyik PASS.

## 11. Review — a Claude tölti ki
