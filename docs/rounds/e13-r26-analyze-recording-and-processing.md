# E13-R26 — Analyze Home, Recording és Processing UI

- **Státusz:** IN PROGRESS (pre-flight 2026-08-26, kód MÉRVE: `main @ 22ef4b1e`;
  eredetileg előre megírva 2026-08-15 `main @ c732ec75` ellen — a §0.0/B revízió
  hat mért eltérést old fel)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 26
- **Kör-azonosító:** `E13-R26`
- **Branch:** `<motor>/e13-r26-analyze-recording-and-processing`
- **Előfeltétel:** `E13-R25` merge-elve (dal-tréner)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0285`](../adr/0285-recording-transparency-and-honest-progress.md)
  — **MÁR MERGE-ELT** (`6e7877de`, 2026-08-15), státusza *elfogadva*. A kör
  ADR-t **NEM ír**, csak hivatkozza: egy merge-elt ADR újraírása H1 (§0.0/B0).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el az elemzési feladat
> TÉNYLEGES életciklusát (szakaszok, ellenőrzőpont, megszakítás), mert a §5.2
> „nincs hamis százalék" cella a mért szakaszokra épül. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  # §0.0/B1 — az eredeti HÁROM könyvtár-előtag (`lib/features/analyze/home/`,
  # `recording/`, `processing/`) a verziókövetett fán NEM létezik (S13 lint,
  # L497 hibaosztály). A `lib/features/analyze/` a LEGACY V1 fa (egyetlen
  # `analyze_screen.dart`, `AnalyzePhase`, EGY `compute()` hop, NULLA szakasz);
  # a brief §2 által leírt szakaszos, megszakítható életciklus MÉRHETŐEN a V2
  # `lib/features/audio_analysis/` fában él. A csere ezért a V2 presentation
  # rétegre megy, és szigorúan KEVESEBB, mint a szomszéd, user-jóváhagyott
  # E13-R22 lista (ott `presentation/widgets/` ÉS `presentation/providers/`
  # ÉS `public.dart` is szerepelt): itt EGY, e kör által létrehozott alkönyvtár
  # + EGY nevesített meglévő fájl.
  #
  # A `capture/` előtag a lint S13 ESCAPE-ágán marad bent („vagy a §0.0 mondja
  # ki, hogy a könyvtárat EZ a kör hozza létre") — §0.0/B1 kimondja. A
  # kézenfekvő alternatíva, a MEGLÉVŐ `presentation/widgets/` felvétele (ez az
  # E13-R22 alakja) TÁGÍTÁS lenne: abban a könyvtárban a Kör 27 eredmény-
  # widgetjei élnek, amiket a §3 kizár. A szűkebb, gépileg tiszta scope-ot
  # választjuk a strict-szintű lint-lelet árán (a CI-kapu `--level base`).
  "lib/features/audio_analysis/presentation/capture/",
  "lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart",
  "lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart",
  "lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart",
  "lib/features/audio_analysis/presentation/analysis_progress_view.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/analyze/recording_state_test.dart",
  "test/features/analyze/processing_progress_test.dart",
  "test/features/analyze/analyze_cleanup_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r26-analyze-recording-and-processing.md",
]
gate_tests = [
  "test/features/analyze/recording_state_test.dart",
  "test/features/analyze/processing_progress_test.dart",
  "test/features/analyze/analyze_cleanup_test.dart",
  # §0.0/B4 — a V2 életciklusra MA is mérő, listán KÍVÜLI pinek: futtatni
  # KELL, szerkeszteni TILOS. Az első kettő a kör által szerkeszthető
  # `analysis_progress_view.dart`-ot és a megszakítás-utat pinneli.
  "test/features/audio_analysis/presentation/analysis_progress_view_test.dart",
  "test/features/audio_analysis/application/analysis_controller_test.dart",
  "test/features/audio_analysis/application/analysis_cancellation_test.dart",
  "test/features/audio_analysis/data/analysis_recorder_test.dart",
  "test/features/audio_analysis/data/analysis_recorder_lifecycle_test.dart",
  # §0.0/B5 (ADR 0426 §3) — a golden-útvonal NEM kerül a lokális ARM-gate-re;
  # a lokális mérés egyetlen érvényes alakja:
  # `tools/golden-x86.sh check test/ui/goldens/e13_r26_screens_golden_test.dart`
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

**Kockázat = high, indoklás:** a felvétel mikrofon-engedélyt (authorization) kér, és nyers hangadatot tárol a feldolgozásig.

## 0.0/B BRIEF-REVÍZIÓ — 2026-08-26, E13-R26 pre-flight (`main @ 22ef4b1e`)

**Visszakeresett előzmény (ADR 0312 §4.9):** [L497](../LESSONS.md) (nem létező
könyvtár-előtag az `allowed_paths`-on — most NEGYEDSZER), [L478](../LESSONS.md)
(a pre-flight csak SZŰKÍTHET, a tágítás H3), [L397](../LESSONS.md#l397) +
[L401](../LESSONS.md#l401) (ÚJ `*_screen.dart` → a `ui_inventory` bázisvonal
CI-only lelet), [L97](../LESSONS.md#l97) + [L409](../LESSONS.md#l409) (új
route-hoz a katalógus-owner is kell — lásd B3), [ADR 0217](../adr/0217-analysis-raw-audio-retention.md)
(nyers audio retention), [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
(golden az x86 kapu-architektúrán), [ADR 0285](../adr/0285-recording-transparency-and-honest-progress.md).

### B0 — a kiosztott ADR `0285` MÁR MERGE-ELT → a kör ADR-t NEM ír

A pipeline-prompt szerint az ADR-t a pre-flight írná meg, de a mérés mást ad:
`docs/adr/0285-recording-transparency-and-honest-progress.md` a fán van,
**merge-elve** (`6e7877de`, „docs(ch13): E13-R26..R29 briefek + ADR 0285-0287",
2026-08-15), státusza *elfogadva*, és a §5 mind a hét kötött döntése szó
szerint benne áll. Egy merge-elt ADR újraírása **H1** (ADR 0087 §2). A kör
tehát **ADR-t nem ír**, csak hivatkozza — ez a sávon a **kilencedik** ADR
nélküli kör egymás után (E13-R17…R26), azonos indokkal.

### B1 — a három `lib/features/analyze/*` előtag NEM LÉTEZIK, és rossz fát céloz

Mérve:

```
$ find lib/features/analyze -type d
lib/features/analyze/{application,engine,model,providers,screens,widgets}
```

`home/`, `recording/`, `processing/` **nincs** — a lista nulla fájlt fedett
(S13 lint). A javítás azonban NEM a `lib/features/analyze/` alatti könyvtárak
létrehozása, mert **két** analyze-fa van, és a brief a MÁSIKAT írja le:

| | `lib/features/analyze/` (V1, legacy) | `lib/features/audio_analysis/` (V2, SDD Ch7) |
|---|---|---|
| szakaszok | **nincs** — `_analyze()` EGY `compute()` hop | `AnalysisProgressPhase` — **9 szakasz** (`preparing`…`finalizing`) |
| haladás-egységek | nincs | `AnalysisPhaseProgressEvent.completedUnits/totalUnits`, **opcionális PÁR** (`ArgumentError`, ha csak az egyik) |
| megszakítás | csak `cancelRecording()` (felvétel), az elemzés NEM szakítható meg | `AnalysisRunHandle.cancel()` + `CancelAnalysisUseCase` + `AnalysisCancelled` |
| degradált mód | nincs | `AnalysisDegradedCompleted`, `CapabilityStatus.degraded`, `CapabilityUnavailableReason` (13 érték) |

A brief §2 állítása („az elemzési feladat szakaszokból áll, ellenőrzőponttal és
megszakítási ponttal") tehát **a V2 fára igaz, a V1-re nem** — pontosan ezt
kérte kimérni a fejléc pre-flight figyelmeztetése („eltérésnél §0.0 revízió").
A kör célfája ezért **`lib/features/audio_analysis/presentation/`**.

**A csere alakja:** egy ÚJ, kizárólag e kör által létrehozott alkönyvtár
(`presentation/capture/`) a három felületnek és privát widgetjeiknek, plusz az
EGY meglévő fájl, amit a feldolgozás-felület befogad
(`analysis_progress_view.dart`). A `presentation/` többi fájlja **Kör 27** öt
eredmény-képernyője (`analysis_overview|timeline|compare|metric_detail|export_screen.dart`)
és azok widgetjei — a listára NEM kerülnek, a §3 „az eredmény-felületek
(Kör 27)" kizárása gépileg is érvényes marad.

### B2 — az `AnalysisProgressView` MA árva: `lib/`-ben SENKI nem hostolja

```
$ grep -rn "AnalysisProgressView" lib/ test/ | grep -v analysis_progress_view.dart:
test/features/audio_analysis/presentation/analysis_progress_view_test.dart:17,42
```

A fájl a §5.2-t **már helyesen valósítja meg** (`progress = unitsAvailable ?
completedUnits!/totalUnits! : null`, majd `LinearProgressIndicator(value:
progress)` → hiányzó egységeknél HATÁROZATLAN sáv, kitalált szám nélkül), de
egyetlen production képernyő sem jeleníti meg. A kör dolga tehát nem az
újraírása, hanem a **befogadása** a feldolgozás-felületbe — és az `A3` három
cellája ezen a MÉRT szerződésen mér.

### B3 — a három ÚJ képernyő ROUTE NÉLKÜL épül (nem hiányosság, hanem a bevett út)

A `lib/app/routing/**` **nincs** az `allowed_paths`-on, és felvenni **tágítás
= H3** ([L478](../LESSONS.md)) — az orchestrátor a pre-flightban nem oldhatja
fel. Ez nem blokkoló: a sáv merge-elt precedense pontosan ez. Az E13-R22 két ÚJ
képernyőt hozott (`practice_history_screen.dart`, `speed_builder_screen.dart`),
a listáján `lib/app/routing/` NEM szerepelt, és

```
$ grep -rn "practice_history_screen\|speed_builder_screen" lib/app/routing/
(nincs találat)
```

— a kör mégis APPROVED review-val és zöld kapuval merge-elt. A route-élesítés
külön kör dolga ([L409](../LESSONS.md#l409): „29 korábbi kör mindegyike
szándékosan" így járt el). **Következmény, amit be KELL tartani:** a kör
GoRouter route-string-literált nem vezet be — a `test/tooling/route_literal_guard_test.dart`
a `gate_tests`-ben fut, és a katalógus-owner nélküli literál pirosra váltaná
([L97](../LESSONS.md#l97)).

### B4 — `ui_inventory` bázisvonal: 86 → 89 (L397/L401)

Mérve: `test/ui/ui_inventory_test.dart:14` → `hasLength(86)`, és
`find lib/features -name '*_screen.dart' | wc -l` → **86** (egyezik). A kör
három ÚJ `*_screen.dart`-ot hoz, tehát a bázisvonal **89**-re mozdul. A
jogosultság PONTOSAN a szám emelése (§0.0/R4) — más állítás nem érinthető.
Ha a kör a háromtól eltérő számú képernyőt hoz, a tényleges mért számot írd be.

### B5 — a golden NEM fut a lokális ARM-kapun (ADR 0426 §3)

Az eredeti `gate_tests` felsorolta a
`test/ui/goldens/e13_r26_screens_golden_test.dart`-ot; ez ezen a boxon (ARM)
architektúra-eltérés miatt pirosra váltana. A merge-elt E13-R22/R25 precedens
szerint a golden kikerül a lokális gate-sorból, és a mérése:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r26_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r26_screens_golden_test.dart
```

A PNG-ket commitolni kell (A9), és a CI-oldali Full Gate futtatja a goldent
élesben.

### B6 — A2 / A5 / A6 / A8 a MÉRT modellre horgonyozva

A négy cella közül háromnak a brief szövege olyan platform-jelet feltételez,
ami a fán **nincs** — a feloldás a mért modellre horgonyzás, NEM új plugin (az
`pubspec`/natív réteg a tilos zónában van, felvétele H3):

| Cella | Mit mértem | A cella MÉRT horgonya |
|---|---|---|
| **A2** (megőrzés látható) | [ADR 0217](../adr/0217-analysis-raw-audio-retention.md) §1–2 + `domain/audio_retention_policy.dart`: `keepOriginal = false` az ALAPÉRTELMEZÉS, „the repository NEVER writes audio bytes"; kivétel KIZÁRÓLAG a consentelt Lab capture | a felvételi felület a **hatályos** `AudioRetentionPolicy`-t mondja ki (alapeset: „csak a származtatott elemzés marad meg"); tilos megőrzés-kapcsolót KITALÁLNI, ami a domainben nincs |
| **A5** (nincs árva mikrofon / temp fájl) | a V2 felvétel **memóriában** gyűlik (`AnalysisRecorder._samples`, `List<double>`) — a felvételi úton temp fájl NEM keletkezik; a mikrofont a `MicCapture` lease birtokolja | minden hibaágon (`AnalysisPermissionDenied`, `AnalysisInputError`, `AnalysisError`) elengedett lease + eldobott minta-puffer; a „temp fájl" ága az ADR 0217 §4 szerint az IMPORT úté |
| **A6** (kevés tárhely ELŐRE jelzett) | `grep -rn "freeSpace\|diskSpace\|getTemporaryDirectory" lib/` → **NULLA** találat: szabad-tárhely lekérdezés a fán nincs | a felvétel ELŐTT ismert, MÉRT korlát a horgony: `InputLimits.maxDuration` (**10 perc**) és fájl-bemenetnél `InputLimits.maxFileBytes` (**64 MiB**) — a felület ezt indulás előtt kimondja, és a 64 MiB fölötti fájlt feldolgozás előtt utasítja el |
| **A8** (degradált mód kimondja az okát) | hő-/akkumulátor-API a fán **nincs**; ami VAN: `AnalysisCompletionStatus.degraded` → `AnalysisDegradedCompleted`, és per-képesség `CapabilityStatus.degraded` + `CapabilityUnavailableReason` (13 érték) | a felület a **mért** degradáltság-okot nevezi meg a `CapabilityReport.reason`-ből; kitalált „hő/akku" indok kiírása a mérés meghamisítása lenne |

Az A7 változatlanul teljesíthető a mért `RecordingLevel { peakDbfs, rmsDbfs,
isClipping }` + `AnalysisRecorder.clippingOnDbfs/-OffDbfs` (Schmitt) párosból:
a **torzítás** az `isClipping`, a **csend** a `rmsDbfs` alsó tartománya — két
KÜLÖN, cselekvésre hívó állapot.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör három képernyőjét (`presentation/capture/`) **ez a kör hozza létre**,
tehát MINDEN szövege új. Mérve: az `audio_analysis` feature-nek **nincs** saját
l10n fragmentuma (`ls lib/l10n/features/` → community, design_system,
gamification, onboarding, tuner), és a MEGLÉVŐ `analysisProgress*` kulcsok
(21 db) a `lib/l10n/base/app_{en,hu}.arb` szegmensben élnek — a kör új kulcsai
tehát ugyanoda mennek.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `analyze` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

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
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z)
`lib/features/audio_analysis/presentation/capture/` könyvtár-előtag (§0.0/B1)
alá képernyőt hoz, tehát a szám **elmozdul** (mérve: 86 → 89, §0.0/B4), és az
exact-SHA Full Gate pirosra vált.

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

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-34–UI-36 megvalósítása **egyértelmű nyers-hang megőrzéssel**, valós
haladásjelzéssel és megszakítható elemzéssel (SDD Ch13 Kör 26).

## 2. Jelenlegi állapot — mért tények

- Az elemzési feladat **szakaszokból** áll, ellenőrzőponttal és megszakítási
  ponttal — a felület ezekre képez. **MÉRVE (§0.0/B1): ez a V2 fára
  (`lib/features/audio_analysis/`) igaz** — `AnalysisProgressPhase` 9 szakasz,
  `AnalysisPhaseProgressEvent` opcionális egység-PÁRRAL, `AnalysisRunHandle.cancel()`.
  A legacy V1 fa (`lib/features/analyze/`) EGY `compute()` hop, szakaszok és
  megszakítható elemzés nélkül — a kör NEM azt célozza.
- Az ADR 0276 kimondta: a Stage layout nem birtokol erőforrást; a felvétel
  indítása felhasználói szándék.
- A nyers hangfelvétel a legérzékenyebb adat, amit a termék kezel. **MÉRVE
  (§0.0/B6): az [ADR 0217](../adr/0217-analysis-raw-audio-retention.md) szerint
  `keepOriginal = false` az alapértelmezés és a repository soha nem ír
  audio-bájtot; kivétel kizárólag a consentelt Lab capture.**
- **MÉRVE (§0.0/B2):** az `AnalysisProgressView` a §5.2-t már helyesen
  valósítja meg, de `lib/`-ben SENKI nem hostolja — a kör befogadja, nem
  újraírja.

## 3. Scope

**Benne van:** az Analyze kezdőképernyő bemeneti módjai és a legutóbbi elemzések
előnézete · a felvételi Stage jelminőség, torzítás, csend, tárhely és
**megőrzés-jelzéssel** · a feldolgozás szakasz-haladása és hő/akkumulátor
degradált állapota · megszakítás / ellenőrzőpont / újraindítás · kapcsolódás az
engedély-átjáróhoz és az audio-session koordinátorhoz · fájl-bemenet, nem
támogatott formátum és kevés tárhely állapotok.

**NINCS benne (tilos):** DSP vagy elemzési paraméter (AGENTS.md §9) · a
feladat-életciklus módosítása · az eredmény-felületek (Kör 27) · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `audio_analysis/presentation/capture/` | **ÚJ könyvtár, ezt a kör hozza létre** (§0.0/B1) — a kezdőképernyő, a felvételi Stage, a feldolgozás és a PRIVÁT widgetjeik |
| `audio_analysis/presentation/analysis_progress_view.dart` | a MEGLÉVŐ, ma árva haladás-felület, amit a feldolgozás befogad (§0.0/B2) |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a felvételi és haladás-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/analyze/*_test.dart` (3) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r26-…md` | a §10 handoff |

**Tilos zóna:** a Kör 27 öt eredmény-képernyője és widgetjeik
(`audio_analysis/presentation/analysis_{overview,timeline,compare,metric_detail,export}_screen.dart`,
`presentation/widgets/`, `presentation/controllers/`) · a V2 `domain/`,
`application/`, `data/`, `engine/` rétege (a feladat-életciklus NEM módosul) ·
a legacy `lib/features/analyze/**` · `lib/features/**` a listán kívül ·
`lib/app/routing/**` (§0.0/B3 — a kör route-ot NEM vezet be) ·
`lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**` · `pubspec.*` és a natív réteg (§0.0/B6).

## 5. Kötött architekturális döntések (ADR 0285)

### 5.1 A felvétel-jelzés ÁLLANDÓ, és a megőrzés végig LÁTHATÓ

Amíg a mikrofon aktív, a felületen folyamatosan látszik. A felhasználó
mindvégig tudja, **megmarad-e** a nyers hangfelvétel, vagy csak a származtatott
elemzés.

**NEM elfogadható gyengítés:** a megőrzés-jelzés kizárólag a beállításokban. A
felvétel pillanatában kell tudni, mi történik a hanggal.

### 5.2 NINCS hamis százalék

A haladás a **tényleges** szakaszokból származik. Ha egy szakasz nem ad
haladás-információt, a felület határozatlan jelzést mutat — nem kitalált
számot, és nem lassan kúszó álhaladást.

**NEM elfogadható gyengítés:** időzítőből animált százalék, „hogy történjen
valami a képernyőn". Ez magabiztos hazugság a felhasználó felé.

### 5.3 A megszakítás IDEMPOTENS

Kétszer megnyomva sem keletkezik két megszakítás, és a folyamat mindig
konzisztens állapotban áll meg.

### 5.4 Hiba után NINCS árva mikrofon vagy ideiglenes fájl

Minden hibaútvonalon felszabadul a mikrofon, és eltűnnek az ideiglenes fájlok
(az ADR 0284 §2 elve a felvételi oldalon).

### 5.5 A kevés tárhely ELŐRE jelzett

Nem a felvétel közepén derül ki. A felület indulás előtt figyelmeztet.

### 5.6 A degradált mód KIMONDJA az okát

Hő- vagy akkumulátor-korlát esetén a felhasználó megtudja, miért lassabb a
feldolgozás — nem néma teljesítményesés.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A felvétel-jelzés végig látható, amíg a mikrofon aktív | `recording_state_test.dart` |
| A2 | A nyers-hang megőrzés állapota a felvétel közben látható — a **hatályos** `AudioRetentionPolicy`-ból, nem kitalált kapcsolóból (§0.0/B6) | ugyanott |
| A3 | Nincs hamis százalék — a haladás a tényleges szakaszokból jön | `processing_progress_test.dart` |
| A4 | A megszakítás idempotens | ugyanott |
| A5 | Hiba után nincs árva mikrofon vagy ideiglenes fájl | `analyze_cleanup_test.dart` |
| A6 | A kapacitás-korlát a felvétel ELŐTT jelzett — a MÉRT `InputLimits.maxDuration` (10 perc) és `maxFileBytes` (64 MiB) alapján (§0.0/B6) | `recording_state_test.dart` |
| A7 | A torzítás és a csend külön, cselekvésre hívó állapot | ugyanott |
| A8 | A degradált mód kimondja a **mért** okát (`CapabilityUnavailableReason` / `AnalysisDegradedCompleted`), nem kitalált hő/akku indokot (§0.0/B6) | `processing_progress_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r26_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A megőrzés-jelzés csak a beállításokban | **A2** |
| Időzítőből animált haladás | **A3** |
| A második megszakítás új leállítást indít | **A4** |
| Hibaágon nyitva marad a mikrofon | **A5** |
| A kapacitás-korlát csak a felvétel közben derül ki | A6 |
| A torzítás és a csend egy „hiba" állapot | A7 |
| Kitalált megőrzés-kapcsoló a `AudioRetentionPolicy` helyett | **A2** |
| Kitalált „hő/akku" indok a mért `CapabilityUnavailableReason` helyett | **A8** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A haladásjelzés három kötelező cellája** (a küszöb: ad-e a szakasz mérhető
haladást):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a szakasz nem ad haladást | **határozatlan** jelzés — nincs szám |
| rajta (a küszöbön) | a szakasz szakasz-szintű haladást ad | szakasz-szintű jelzés (pl. „3/5 szakasz") |
| a küszöb fölött | a szakasz százalékot ad | a **tényleges** százalék |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** animálj időzítőből
százalékot a határozatlan szakaszra → az **A3** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/analyze/recording_state_test.dart test/features/analyze/processing_progress_test.dart test/features/analyze/analyze_cleanup_test.dart test/features/audio_analysis/presentation/analysis_progress_view_test.dart test/features/audio_analysis/application/analysis_controller_test.dart test/features/audio_analysis/application/analysis_cancellation_test.dart test/features/audio_analysis/data/analysis_recorder_test.dart test/features/audio_analysis/data/analysis_recorder_lifecycle_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden NEM ebben a sorban fut (§0.0/B5, ADR 0426 §3)** — a lokális box ARM,
a merge-kapu x86_64. A golden egyetlen érvényes lokális mérése:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r26_screens_golden_test.dart
tools/golden-x86.sh check test/ui/goldens/e13_r26_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r26_screens_golden_test.dart
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

1. Az Analyze kezdőképernyő bemeneti módokkal és előnézettel.
2. A felvételi Stage — állandó jelzés + megőrzés-állapot.
3. Jelminőség: torzítás és csend KÜLÖN, cselekvésre hívón.
4. A tárhely-előrejelzés.
5. A feldolgozás szakasz-haladása + a három cella.
6. Megszakítás idempotensen, ellenőrzőponttal; takarítás minden hibaágon.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az álhaladás.** A legelterjedtebb UI-hazugság, és pont a leghosszabb
  műveletnél rombolja a bizalmat (A3).
- **A rejtett megőrzés.** A nyers hang a legérzékenyebb adat; ha a felhasználó
  csak a beállításokban tudja meg a sorsát, az nem informált beleegyezés (A2).
- **A hibaágon nyitva maradó mikrofon.** A boldog út takarít, a hibaág nem —
  ez a klasszikus kihagyás (A5).

## 10. Implementation handoff — az implementer tölti ki

### Mit épített a kör

Három ÚJ képernyő a `lib/features/audio_analysis/presentation/capture/`
alatt (§0.0/B1 szerint, a V2 fára horgonyozva):

- **`AnalysisHomeScreen`** — két bemeneti mód (felvétel / fájl-import)
  kártyaként, a fájl-import kártya a MÉRT `InputLimits.maxFileBytes`-ból
  számolt MB-limitet mondja ki; legutóbbi elemzések előnézete
  (`List<AnalysisSummary>`, üres-állapot felirattal).
- **`AnalysisRecordingScreen`** — StatefulWidget, amely egy a hoszttól kapott
  `AnalysisRecorder`-t birtokol. Öt belső állapot: idle/starting (kész,
  még nem indult), recording (állandó jelzés), permissionDenied, error.
  A `dispose()` MINDEN kilépési útvonalon meghívja `recorder.dispose()`-t
  (idempotens, biztonságos duplán is).
- **`AnalysisProcessingScreen`** — a MEGLÉVŐ, addig árva
  `AnalysisProgressView`-t fogadja be (nem írta újra); ráépít egy
  determinisztikus fázis-lépés jelzőt (`AnalysisProgressPhase.values.indexOf`)
  a köztes granularitáshoz. `AnalysisState`-et fogyaszt (application réteg,
  csak import, nem módosítás).

A `AnalysisProgressView` (`presentation/analysis_progress_view.dart`) fájlt
a kör NEM módosította — a `analysis_progress_view_test.dart` pinelt teszt
változatlanul zöld, mert a fájl bájtra egyezik a merge-elt állapottal.

### Acceptance-mátrix → hol teljesül

| # | Kritérium | Hol | Teszt |
|---|---|---|---|
| A1 | Felvétel-jelzés végig látható, amíg a mikrofon aktív | `AnalysisRecordingScreen._RecordingBody` — `Key('analysis-recording-live-indicator')`, `Semantics(liveRegion: true)` | `recording_state_test.dart` „A1" csoport |
| A2 | Megőrzés-állapot látható, a MÉRT `AudioRetentionPolicy`-ból | `_RetentionNotice` — `retentionPolicy.keepOriginal` ágaztatja a két lokalizált szöveget, idle ÉS recording állapotban is megjelenik | `recording_state_test.dart` „A2" csoport (default + `keepOriginal: true`) |
| A3 | Nincs hamis százalék, tényleges szakaszokból jön | `AnalysisProcessingScreen` — indeterminate (nincs fázis) → `LinearProgressIndicator(value: null)`; fázis van, egység nincs → `_PhaseStepIndicator` szöveg + indeterminate sáv; egység van → `AnalysisProgressView` valódi hányadosa | `processing_progress_test.dart` „A3" csoport, mindhárom küszöb-cella |
| A4 | Megszakítás idempotens | `_AnalysisProcessingScreenState._handleCancel` — `_cancelledForRunId` per-run őr, második koppintás no-op, ÚJ `runId` újra engedélyezi | `processing_progress_test.dart` „A4" csoport |
| A5 | Hiba után nincs árva mikrofon/ideiglenes fájl | `AnalysisRecordingScreen.dispose()` MINDEN úton `recorder.dispose()`-t hív; a V2 felvétel memóriában gyűlik, temp fájl nincs (§0.0/B6) | `analyze_cleanup_test.dart`, öt eset: engedély megtagadva, motorhiba indításkor, megszakítás felvétel közben, képernyő elhagyása koppintás nélkül, max-hossz auto-stop |
| A6 | Kapacitás-korlát a felvétel ELŐTT jelzett | `_ReadyBody` — `InputLimits.maxDuration` (10 perc) az idle állapotban, MIELŐTT a `Start` gomb megnyomásra kerül | `recording_state_test.dart` „A6" csoport |
| A7 | Torzítás és csend külön, cselekvésre hívó állapot | `_RecordingBody._isClipping` / `_isQuiet` — kölcsönösen kizáró, két külön `Key`-jel jelölt banner | `recording_state_test.dart` „A7" csoport |
| A8 | Degradált mód a MÉRT okot mondja ki | `_DegradedBody` — `document.capabilities` `unavailable` + `reason != null` elemeiből, az `AppLocalizationsOverviewLabels.unavailableReason` (MEGLÉVŐ adapter) újrafelhasználásával | `processing_progress_test.dart` „A8" csoport |
| A9 | Golden minden képernyőről, két keretben | `test/ui/goldens/e13_r26_screens_golden_test.dart`, x86-on rögzítve | 6 PNG a `test/ui/goldens/goldens/`-ben |

### A gate TÉNYLEGES kimenete

```
tools/round-gate.sh test/features/analyze/recording_state_test.dart test/features/analyze/processing_progress_test.dart test/features/analyze/analyze_cleanup_test.dart test/features/audio_analysis/presentation/analysis_progress_view_test.dart test/features/audio_analysis/application/analysis_controller_test.dart test/features/audio_analysis/application/analysis_cancellation_test.dart test/features/audio_analysis/data/analysis_recorder_test.dart test/features/audio_analysis/data/analysis_recorder_lifecycle_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**MINDEN GATE ZÖLD** (18/18 lépés): format, analyze, mind a 13 megnevezett
teszt-útvonal külön processzben, architecture, secrets, l10n. Az
`ui_inventory` `hasLength(89)`-re mozdult (86 → 89, pontosan a három új
képernyő, §0.0/B4 mérés szerint). Első futáskor az `analyze` lépés 11
lint-leletet adott (nem használt import, `unnecessary_underscores`
`(_, __)` mintára) a saját teszt-fájljaimban — javítva, második futás
tisztán zöld.

A golden lokálisan (ARM-on) NEM fut ebben a sorban (ADR 0426 §3); mérése:

```
tools/golden-x86.sh record test/ui/goldens/e13_r26_screens_golden_test.dart  → 6/6 „All tests passed!" (37s, docker/amd64)
tools/golden-x86.sh check  test/ui/goldens/e13_r26_screens_golden_test.dart  → 6/6 „All tests passed!" (stabil raszterizáció)
```

A hat PNG (3 képernyő × 412×915 compact portrait / textScale 2.0) commitolva.

### A valódi-sértés próba (§6.1, KÖTELEZŐ)

`AnalysisProcessingScreen._IndeterminateBody`-t átmenetileg `StatefulWidget`-re
cseréltem egy `Timer.periodic(200ms)`-cel animált `_fakePercent` állapottal,
és a `LinearProgressIndicator.value`-t erre kötöttem, plusz egy
`Text('$_fakePercent%')` sort hozzáadtam — pontosan az ADR 0285 §5.2 által
tiltott „időzítőből animált százalék" minta.

Futtatás: `flutter test test/features/analyze/processing_progress_test.dart`.
**MÉRT kimenet — az A3 „alatta" cellája PIROSRA váltott:**

```
AnalysisProcessingScreen — A3 no fake percent below the threshold: an indeterminate signal, no number [E]
Expected: no matching candidates
  Actual: _TextContainingWidgetFinder:<Found 1 widget with text containing %: [
            Text("0%", ...),
          ]>
   Which: means one was found but none were expected
```

A másik két A3-cella (rajta/fölötte) és az A4/A8 cellák változatlanul
zöldek maradtak — a próba PONTOSAN azt a cellát fogta meg, amit a sértés
érintett. Ezután a `_IndeterminateBody`-t visszaállítottam az eredeti
`StatelessWidget`-re (`git diff` a fájlra üres a visszaállítás után), és a
teszt újra 6/6 zöld.

### Amit NEM csináltam meg, és miért

- **Route-ot nem vezettem be** (§0.0/B3) — a három képernyő route nélkül áll,
  a `route_literal_guard_test.dart` zöld.
- **Az `AnalysisHomeScreen`/`AnalysisRecordingScreen`/`AnalysisProcessingScreen`
  nincs egymáshoz vagy a Kör 27 eredmény-képernyőkhöz drótozva** — a
  screenek kizárólag callback-eket és már validált állapotot kapnak
  konstruktorban (a `SongResultScreen`/`TrainerSetupScreen` E13-R22..R25
  precedens mintája), a tényleges huzalozás (providerek, navigáció) egy
  KÉSŐBBI, route-ot bevezető kör dolga.
- **Fájl-import maga (file picker, dekódolás) nincs a képernyőn belül** — a
  Home képernyő `onImportFile` callbacket exponál, a tényleges fájlkezelés
  a hoszté; ez konzisztens azzal, hogy a `data/input/` réteg NINCS az
  `allowed_paths`-on.
- **Csend-küszöb (`silenceThresholdDbfs = -45.0`)** egy PREZENTÁCIÓS
  konstans, nem mért/kalibrált érték — dokumentálva a doc-commentben, hogy
  ne legyen összetévesztve DSP-döntéssel (AGENTS.md §9 tiltja a DSP-paraméter
  módosítást; ez tisztán UI-küszöb, a felismerést nem érinti).
- **Megőrzés-kapcsoló, szabad-tárhely lekérdezés, hő/akku indok** — a
  §0.0/B6 kifejezetten tiltja a kitalálásukat; egyik sem került a kódba.

## 11. Review — a Claude tölti ki
