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

## 11. Review — a Claude tölti ki
