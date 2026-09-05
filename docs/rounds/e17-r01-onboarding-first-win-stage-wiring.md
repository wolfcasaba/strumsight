# E17-R01 — Onboarding First-Win állomás bekötése

- **Státusz:** PREPARED · **REVIDEÁLVA** (ADR 0112 önjavító kör, 2026-09-05 — lásd §0.0; kód újramérve: `main @ 0b2feb43`)
- **Típus:** Chapter 17 (Teljes bekötés), Kör 1
- **Kör-azonosító:** `E17-R01`
- **Branch:** `<motor>/e17-r01-onboarding-first-win-stage-wiring`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0534` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt). *(Az eredeti `0520` MEGÍRT, más körhöz tartozó ADR — `docs/adr/0520-live-uncertainty-reason-from-the-merged-recognition-vocabulary.md`; a queue 0520–0533 sávját az E17 sáv többi köre foglalja, ezért a szabad `0534` jött ide.)*
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "onboarding first-win állomás bekötése"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/onboarding/screens/onboarding_screen.dart",
  "lib/features/onboarding/screens/first_win_stage_screen.dart",
  "lib/features/onboarding/first_win_engine.dart",
  "lib/features/onboarding/first_win_providers.dart",
  "lib/features/onboarding/public.dart",
  "test/features/onboarding/first_win_stage_wiring_test.dart",
  "test/features/onboarding/first_win_production_engine_test.dart",
  "docs/rounds/e17-r01-onboarding-first-win-stage-wiring.md",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/app/routing/shell_entry_location_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/e2e/full_app_walkthrough_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/onboarding_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/app/navigation/",
]
native_gate = false
gate_tests = [
  "test/features/onboarding/",
  "test/features/onboarding/first_win_production_engine_test.dart",
  "test/e2e/full_app_walkthrough_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/app/routing/shell_entry_location_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/onboarding_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/app/navigation/",
]
```

## 0.0 Revízió — ADR 0112 önjavító kör (2026-09-05, H3 / 1. kísérlet)

**Miért.** A kör a saját pre-flightján `H3`-mal állt meg (`.pipeline/HALTED`,
`halted_at=2026-09-05T19:05:09+00:00`; dispatch NEM történt, kör-ág nincs). A
teljes mérés: [`.pipeline/halt-E17-R01-preflight.md`](../../.pipeline/halt-E17-R01-preflight.md).
A halt MÉRTEN indokolt volt, és az önjavító kör függetlenül reprodukálta
(`main @ 0b2feb43`): a §2 eredeti állítása („a képernyő adatforrása MÁR
LÉTEZIK") a bekötés szempontjából félrevezető — a provider létezik, de a
**szállított default gyára a `FakeOnboardingFirstWinEngine`**, ami a
produkcióban soha nem emittál. A bekötés így egy örökké „Listening…"
képernyőt tett volna a MÁR MŰKÖDŐ first-win út elé, miközben az A1/A4 cella
zölden ment volna át — ez az [L606](../LESSONS.md#l606) hibaosztálya (*az üres
forrás és a zöld kapu megkülönböztethetetlen*).

**Mi változott.**

1. `allowed_paths` + `gate_tests` **TÁGÍTVA** a hiányzó FORRÁSSAL:
   `first_win_engine.dart`, `first_win_providers.dart`,
   `screens/first_win_stage_screen.dart`, és az új
   `test/features/onboarding/first_win_production_engine_test.dart`.
2. A §3 tiltása **PONTOSÍTVA**, nem törölve: a forrás átkötése ettől a körtől a
   kör CÉLJA, de a siker-küszöb őszinteség-szerződése
   (`kFirstWinConfidenceThreshold`, `isFirstWinSuccess`, ADR 0281 §2)
   TOVÁBBRA IS érinthetetlen, és a `lib/core/audio/**` (lease-szerződés, új
   `AudioOwner` variáns) TOVÁBBRA IS kívül van.
3. Új acceptance-cellák: **A8** (a szállított gyár nem `FakeOnboardingFirstWinEngine`),
   **A9** (a Stage elhagyása elengedi a motort, és az utána következő mini-lecke
   továbbra is detektál), **A10** (a forrás hibája — megtagadott engedély,
   foglalt mikrofon — kimondva jelenik meg, nem néma „Listening…").
   Az A1–A7 cella VÁLTOZATLAN.
4. ADR-szám `0520` → `0534` (a `0520` megírt, más körhöz tartozó ADR; a queue
   sora is javítva).

**Regressziós őr:** `tools/tests/test_e17_r01_first_win_source_scope.py` — a
revízió ELŐTTI briefen piros, utána zöld.

## 0.0.1 Pre-flight újramérés — a kör indulása (`main @ 5fbb4937`, 2026-09-05)

Az orchestrátor a §2 MINDEN mért állítását újramérte a kör indulási HEAD-jén
(`5fbb4937`, az önjavító kör merge-e). **Eredmény: a §2 teljes egészében áll, brief-revízió
nem kellett** — az alábbi mérésekkel:

| Állítás | Mérés | Eredmény |
|---|---|---|
| A Stage-et se route, se imperatív hívás nem éri el | `grep -rn "FirstWinStageScreen" lib/ test/ tool/` | csak a saját deklarációja + 2 TESZT-hivatkozás (`first_win_test.dart:156`, `e13_r16_screens_golden_test.dart:132`) — `lib/`-ből NULLA fogyasztó |
| A szállított gyár fake | `first_win_providers.dart:20-23` | `(_) => FakeOnboardingFirstWinEngine.new` — változatlan |
| A fake sosem emittál produkcióban | `grep -rn "\.emit(" lib/features/onboarding/` | 0 találat; `FakeOnboardingFirstWinEngine.start()` = `_started = true` (`first_win_engine.dart:32`) |
| Nincs produkciós override | `grep -rn "onboardingFirstWinEngineFactoryProvider.overrideWith" lib/` | 0 találat |
| A `strumEngineProvider` a `live/public.dart` felületén elérhető | `lib/features/live/public.dart:41` → `export 'providers/live_providers.dart'` | ÁLL (a symbol nem külön exportsor, a **fájl** exportált); a kereszt-feature szabályt a `tool/check_architecture.dart:382-392` a `public.dart`-végződésre méri → az onboarding `../../live/public.dart` importja legális |
| Precedens ugyanerre | `practice_observation_gateway_provider.dart:31` | `ref.watch(strumEngineProvider)` a `../../live/public.dart` importon át |
| `LiveFrame.confidence` | `live_frame.dart:83` | `double get confidence => latestStrum?.confidence ?? 0` |
| Küszöb-hármas mérhető (A5/A6/A7) | `first_win_providers.dart:10-14` | `kFirstWinConfidenceThreshold = 0.60`, `isFirstWinSuccess` = `>=` (INKLUZÍV) → alatta `0.59`, rajta `0.60`, fölötte `0.61` |
| **Erőforrás-tulajdonlás a TÉNYLEGES hívási láncon** (prompt §1/2. szabály) | `grep -rn "\.acquire(" lib/` + `grep -rn "createMicCapture" lib/` | a mikrofon-lease-t a `mic_capture.dart:82` `_coordinator.acquire(...)` szerzi, a `strumEngineProvider` `createMicCapture(ref, AudioOwner.live)` hívásából (`live_providers.dart:13`) — **az `AudioOwner` enumnak ma öt variánsa van** (`audio_session_lease.dart:5-11`), onboarding NINCS köztük, és a §5.3 szerint nem is kell |
| **Cél-állapot elérhetősége** (prompt §1/1. szabály) | a Stage állapotai nem enumból jönnek, hanem az `AsyncValue` ágaiból (`first_win_stage_screen.dart:28-30`) | mindhárom ág elérhető: `.value == null` → Listening, `hasAttempt && !success` → Retry, `success` → Continue; a **hiba-ág ma NEM létezik** — ezt a kör építi (A10) |
| A D5 hiba-ág l10n kulcsai megvannak | `lib/l10n/base/app_en.arb:6-7` + `app_localizations_hu.dart:4061,4064` | `micPermissionBody` és `micPermissionAction` MINDKÉT locale-ban él, produkciós használattal (`analyze_screen.dart:181-182`) → **új l10n kulcs nem kell, az [L646](../LESSONS.md#l646) csapdája elkerülve** |
| `entryLocationFor` egy-forrás | `adaptive_shell_routes.dart:28`, `onboarding_screen.dart:108,132` | ÁLL |
| Az `OnboardingStep` switch teljes | `onboarding_screen.dart:176-186` | `welcome` / `permission` / `done` — a `build` egy kimerítő `switch`; **új enum-érték tilos** (§3), tehát a Stage a folyamaton BELÜL renderelt/pusholt képernyő |

**ADR-szám.** A foglaló (`tools/round-slots.py reserve-adr --round E17-R01`) `0527`-et adott,
mert a lemezen/ágakon a legmagasabb ADR a `0526`. A kör mégis a **`0534`**-et használja: a
merge-elt őr (`tools/tests/test_e17_r01_first_win_source_scope.py::AdrNumberIsFreeTest`) a
brief fejlécének és a `docs/execution/pipeline-queue.tsv` ADR-oszlopának EGYEZÉSÉT méri, a
queue pedig `0534`-et tartalmaz és a driver tulajdona (ADR 0087 §4 — az orchestrátor nem
írja). A `0527` a foglalóban kiégetve marad, a `0534`-re pedig az orchestrátor külön markert
írt, tehát párhuzamos kör egyiket sem kaphatja meg. A `test_adr_numbering.py` csak
EGYEDISÉGET mér (nem folytonosságot), ezért a hézag szabályos.

**Visszakeresés (ADR 0312, KÖTELEZŐ).** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr`
(szűkítve, majd teljes korpuszon):
[L606](../LESSONS.md#l606) (*az üres forrás és a zöld kapu megkülönböztethetetlen* — ez a
halt osztálya), [L498](../LESSONS.md#l498) (*a „gyártott mérés": szintetikus bemenet a
VALÓDI motoron át hitelesnek látszik* — az A8 pontosan ezt zárja ki),
[L644](../LESSONS.md#l644) (*a saját scope-on belüli kivételt semmi nem pinneli; az
implementer becsületes jelzése nem mérce* — az A9/A10 cellák ezért gépi őrök, nem §10-es
mondatok), [L612](../LESSONS.md#l612) (*az őr ne a kör munkájának HIÁNYÁT pinnelje*),
[adr/0281](../adr/0281-permission-primer-and-honest-first-win.md) §2 (a tiltott
feltétel-nélküli siker-képernyő), valamint a saját halt-jelzése
(`halts/E17-R01 H3`). Új, a §2-t cáfoló előzmény NINCS.

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása: állítsd meg a kört (`stopped`), és írd le, melyik §-t kell módosítani.

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A `FirstWinStageScreen` a szállított kompozícióból elérhető: az onboarding folyamat a first-win kísérlet után erre az állomásra lép, valós konfidencia-forrásból.

## 2. Jelenlegi állapot — mért tények (`main @ 0b2feb43`, önjavító kör újramérése)

- A `FirstWinStageScreen` a fában él (`lib/features/onboarding/screens/first_win_stage_screen.dart`), de a `check_screen_reachability` mérése szerint SEM route, SEM imperatív hívás nem éri el (`reachable: false`, csak teszt- és golden-hivatkozás).
- A provider-váz létezik — `onboardingFirstWinConfidenceProvider` (`first_win_providers.dart:39`, `StreamProvider.autoDispose<double>`), küszöb az `isFirstWinSuccess(confidence)` predikátumban —, **de a szállított forrás FAKE**:
  - `first_win_providers.dart:20-23` — a default gyár `(_) => FakeOnboardingFirstWinEngine.new`;
  - `grep -rn "\.emit(" lib/features/onboarding/ --include=*.dart` → **0 találat**: a fake kizárólag teszt/preview hookból emittál (`first_win_engine.dart:45-49`), a `start()` csak egy boolt állít;
  - `grep -rn "onboardingFirstWinEngineFactoryProvider.overrideWith" lib/` → **0 találat**: nincs produkciós felülírás a kompozícióban.
  - Következmény: bekötve a képernyő VÉGIG az `onboardFirstWinListening` ágon állna (`first_win_stage_screen.dart:41-52`) — se Continue, se Retry, csak a „Not now". **Ez a kör tehát a FORRÁST is szállítja** (§5.3).
- Van produkciós hangforrás, amit a Stage a `public.dart` felületén elér: `strumEngineProvider` (`lib/features/live/providers/live_providers.dart:12-16`, `RealStrumEngine(mic: createMicCapture(ref, AudioOwner.live))`), exportálva a `lib/features/live/public.dart:41`-ben. Keresztfeature-precedens ugyanerre: `lib/features/practice/data/practice_observation_gateway_provider.dart:31`. A `LiveFrame` már hordoz strum-konfidenciát: `live_frame.dart:83` (`double get confidence => latestStrum?.confidence ?? 0`).
- Az `OnboardingScreen` routolt és működik; a `PermissionPrimerScreen`-t MÁR imperatívan hívja (`onboarding_screen.dart:181`) — ez a bekötés MÉRT mintája. A first-win ág ma az engedély-primer után a valós, pontozott `LearnScreen(lesson: Lessons.firstWin)`-re pushol (`onboarding_screen.dart:127-151`) — **ez a működő út, amit a Stage nem ronthat el** (a Stage elé kerül, nem helyette).

## 3. Scope

**Benne van:** A First-Win állomás belépési pontja az onboarding folyamatból · a képernyő `onContinue` / `onSkip` visszahívásainak valós navigációhoz kötése · a folyamat kimenete az `entryLocationFor(...)` EGYETLEN forráson át (ADR 0508 D1) · **a produkciós konfidencia-forrás** (`OnboardingFirstWinEngine` implementáció a `strumEngineProvider` fölött + a default gyár átkötése) · **a forrás-hiba őszinte ága** a Stage-en (§5.3, A8–A10 — az önjavító kör revíziója).

**NINCS benne (tilos):**

- Az `OnboardingScreen` lépés-gépének átírása; új `OnboardingStep` enum-érték (az enum ordinálisa a lemezen perzisztált checkpoint, `onboarding_provider.dart:59`, pinneli `test/features/onboarding/onboarding_resume_test.dart`).
- Új képernyő létrehozása.
- A first-win **siker-szemantikájának** módosítása: a `kFirstWinConfidenceThreshold` értéke és az `isFirstWinSuccess` inkluzív predikátuma VÁLTOZATLAN (ADR 0281 §2 őszinteség-szerződés). A forrás (a gyár mögötti motor) átkötése ezzel szemben a kör CÉLJA — ezt a különbséget az önjavító kör revíziója rögzítette.
- A `lib/core/audio/**` bármely fájlja: új `AudioOwner` variáns, lease-szerződés vagy `createMicCapture` módosítás. A produkciós motor a MEGLÉVŐ `strumEngineProvider`-t használja a `lib/features/live/public.dart` felületén át.
- Új l10n kulcs: a forrás-hiba ága a MEGLÉVŐ `micPermissionBody` / `micPermissionAction` kulcsokból él (a generált ARB-aggregátum és a forrás-szegmens együtt-mozgatása külön kör, [L646](../LESSONS.md#l646)).

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.


## 5. Kötött architekturális döntések (ADR 0534)

### 5.1 A belépés az onboarding folyamatból megy, nem új top-level route-ból

A First-Win állomás a folyamat egy LÉPÉSE. Külön `/first-win` route két belépési pontot adna ugyanahhoz az állapothoz, és a `entryLocationFor(...)` egy-forrás szabályát (ADR 0508 D1) sértené.

### 5.2 A `onContinue` / `onSkip` SOSEM navigál közvetlenül literál útvonalra

Mindkettő az `entryLocationFor(adaptiveShellEnabled)` eredményét használja — ugyanaz a forrás, amit az `onboarding_screen.dart` Skip/finish ága már ma is (E16-R06 mérése).

### 5.3 A produkciós konfidencia a MEGLÉVŐ live motorból jön, nem új mikrofon-tulajdonosból *(önjavító kör, 2026-09-05)*

A `FakeOnboardingFirstWinEngine` teszt-infrastruktúra marad (override-ból élő, `emit`-tel vezérelt), de a **default gyár produkciós motort ad**: egy `OnboardingFirstWinEngine` implementációt, amely a `strumEngineProvider` frame-folyamából (`LiveFrame.confidence`, `live_frame.dart:83`) állítja elő a kísérletenkénti konfidenciát, és a `liveFrameProvider` életciklus-precedensét követi (`start()` a mountra, `stop()` a `ref.onDispose`-ra, idempotens).

Miért NEM új `AudioOwner.onboarding`: a lease-szerződés (`lib/core/audio/**`) bővítése a kör mérete fölött van, és nem is szükséges — az onboarding a Stage alatt az egyetlen mikrofon-fogyasztó, a rá következő mini-lecke (`LearnScreen`) pedig UGYANEZT a `strumEngineProvider`-t használja (`learn_screen.dart:125,241`). Egy tulajdonos, egy lease, nulla arbitrációs kockázat. Ha a mérés mégis külön tulajdonost kíván, az a kör BLOKKOLÓ lelete (`stopped`), nem csendes scope-tágítás.

### 5.4 A forrás hibája kimondva jelenik meg *(önjavító kör, 2026-09-05)*

A konfidencia-stream hibája (megtagadott mikrofon-engedély — az engedély-primer `onSkipped` ága a szállított út! —, foglalt mikrofon, motor-hiba) a Stage-en NEM olvadhat bele a „Listening…" állapotba: a képernyő a `AsyncValue` hibaágát kimondja (meglévő `micPermissionBody` / `micPermissionAction` kulcsokkal), és a „Not now" mellett a folyamat továbbvitele mindig elérhető marad. Ez ugyanannak az őszinteség-szerződésnek a folytatása, amit az ADR 0281 §2 a gyenge jelre már kimond.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `check_screen_reachability` a `FirstWinStageScreen`-t `reachable: true`-ként méri | `dart run tool/check_screen_reachability.dart --format json` |
| A2 | Az onboarding folyamat a first-win kísérlet után a First-Win állomásra lép | widget-teszt valós `ProviderContainer`-rel |
| A3 | A `onContinue` és a `onSkip` egyaránt az `entryLocationFor(...)` által adott célra navigál — literál útvonal EGYIK ágban sincs | widget-teszt + `grep` a diffre |
| A4 | A képernyő a VALÓS `onboardingFirstWinConfidenceProvider`-t olvassa, nem tesztkonstansot | a szállított kompozíció tesztje |
| A5 | A siker-küszöb **alatt** lévő konfidencia a „még nem sikerült" ágra visz | widget-teszt a küszöb alatti értékkel |
| A6 | A küszöbön **rajta** álló konfidencia a siker-ágra visz (a predikátum inkluzív határa mérve) | widget-teszt pontosan a küszöb-értékkel |
| A7 | A küszöb **fölött** lévő konfidencia ugyanarra a siker-ágra visz — a határ fölött nincs harmadik viselkedés | widget-teszt a küszöb fölötti értékkel |
| A8 | A SZÁLLÍTOTT kompozícióban a `onboardingFirstWinEngineFactoryProvider` default gyára NEM `FakeOnboardingFirstWinEngine`-t ad, hanem a produkciós motort, és az a `strumEngineProvider` frame-folyamából kap konfidenciát (override nélküli `ProviderContainer`) | `test/features/onboarding/first_win_production_engine_test.dart` — a default gyár típusa + fake `StrumEngine` override-dal adott frame → a Stage siker-ága |
| A9 | A Stage elhagyása elengedi a motort (`stop()` a `ref.onDispose`-on), és az utána következő mini-lecke UGYANAZON a `strumEngineProvider`-en továbbra is kap frame-et — nincs holt motor | widget/provider-teszt fake `StrumEngine`-nel: `start`/`stop` számláló + a lecke-út újraindulása |
| A10 | A konfidencia-forrás HIBÁJA (megtagadott engedély / foglalt mikrofon) kimondva jelenik meg a Stage-en, és a továbblépés elérhető marad — a hiba SOHA nem néma `onboardFirstWinListening` | widget-teszt hibát emittáló fake motorral: a hiba-szöveg és a skip-akció jelen van |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Cseréld a `onSkip` ágat literál `'/live'` útvonalra, futtasd a gate-et → az A3 cellának PIROSNAK kell lennie → állítsd vissza. Második próba a küszöb-hármasra: fordítsd a határt exkluzívra, futtasd → az A6 cellának PIROSNAK kell lennie (az A5 és A7 zöld marad, tehát a hármas tényleg a HATÁRT méri) → állítsd vissza.

**Harmadik próba (a halt hibamódja, KÖTELEZŐ):** állítsd vissza a default gyárat `FakeOnboardingFirstWinEngine.new`-ra, futtasd a gate-et → az **A8**-nak PIROSNAK kell lennie (és vele a Stage siker-ága a produkciós konfidenciából), az A5–A7 (override-os) cellák közben ZÖLDEK maradnak — ez bizonyítja, hogy a hármas tényleg a SZÁLLÍTOTT forrást méri, nem a tesztbeli felülírást → állítsd vissza. Ugyanígy: némítsd el a hiba-ágat (a hibát „Listening…"-ként kezelve) → az **A10**-nek pirosnak kell lennie.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/onboarding/ test/features/onboarding/first_win_production_engine_test.dart test/e2e/full_app_walkthrough_test.dart test/app/routing/app_router_test.dart test/app/routing/onboarding_first_win_test.dart test/app/routing/shell_entry_location_test.dart test/core/screen_size_guard_test.dart test/features/onboarding/first_win_test.dart test/features/onboarding/onboarding_resume_test.dart test/features/onboarding/onboarding_test.dart test/features/onboarding/permission_primer_test.dart test/ui/goldens/e13_r16_screens_golden_test.dart test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/ui/ui_baseline_screenshot_test.dart test/app/navigation/
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture` lépéseket KÜLÖN processzként futtatja (a box mért OOM-csapdája miatt a `flutter analyze && flutter test` lánc tilos).

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE a kör indulásakor (a brief alapja elmozdulhatott).
2. A §5 döntéseinek rögzítése az ADR-ben.
3. Az implementáció a §4 engedélyezett fájljain belül.
4. A §6 acceptance-cellák tesztjei.
5. A §6.1 valódi-sértés próba lefuttatása és a §10-be dokumentálása.
6. A §7 gate futtatása csonkítatlan kimenettel.

## 9. Kockázatok

- **A kettős belépési pont.** Egy külön route ugyanahhoz az állapothoz az ADR 0508 D1 egy-forrás szabályát sérti (5.1).
- **A literál útvonal.** Az E16-R06 pont ezt a hibaosztályt mérte és távolította el a gerincről (5.2).
- **A folyamat megszakadása.** Ha az állomás a konfidencia-stream első értéke előtt navigál, a felhasználó üres állapotot lát (A4).
- **A néma forrás (a halt gyökéroka).** Fake vagy soha nem emittáló motorral a Stage örökké „Listening…" — és a kapu ZÖLD marad, mert a képernyő tényleg a valós providert olvassa. Ezt kizárólag az A8 méri (§6.1 harmadik próba).
- **Az osztott motor életciklusa.** A Stage és a rá következő `LearnScreen` UGYANAZT a `strumEngineProvider`-t használja; a Stage `stop()`-ja aszinkron. Ha a lecke a leállás közben indul, „detektál, de nem hall" állapot áll elő — az A9 pontosan ezt a sorrendet méri.
- **Az engedély nélküli út.** Az engedély-primer `onSkipped` ága a szállított folyamat része: a Stage ilyenkor hibát kap a forrástól, nem adatot (A10).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** `sonnet-impl` (Claude Sonnet 5). **Kiindulás:** `main @ 5fbb4937`.

### 10.1 Mit szállít a kör

1. **Produkciós konfidencia-forrás** (D3/A4/A8) — `lib/features/onboarding/first_win_engine.dart`:
   új `LiveFirstWinEngine implements OnboardingFirstWinEngine`, ami a
   `StrumEngine.frames` (`lib/features/live/public.dart` felületén elért
   `strumEngineProvider`) folyamát `.map((frame) => frame.confidence)`-szel
   alakítja konfidencia-stream-mé — a hibaesemények a `Stream.map`
   szemantikája miatt VÁLTOZATLANUL átfutnak (D5 előfeltétele). `start()`/
   `stop()` a becsomagolt `StrumEngine`-re delegál, sosem `dispose()`-olja
   (osztott példány, A9). `lib/features/onboarding/first_win_providers.dart`:
   `onboardingFirstWinEngineFactoryProvider` default gyára mostantól
   `(ref) => () => LiveFirstWinEngine(ref.watch(strumEngineProvider))` —
   NEM `FakeOnboardingFirstWinEngine.new`.
2. **A Stage bekötése** (D1/D2/A2/A3) —
   `lib/features/onboarding/screens/onboarding_screen.dart`:
   `_completeFirstWin`-ben a `router.go(entryLocation)` utáni
   `addPostFrameCallback` mostantól `FirstWinStageScreen`-t pusholja (a
   korábbi közvetlen `LearnScreen`-push helyett). A Stage `onContinue`-ja
   `router.go(entryLocation)` + `LearnScreen(lesson: Lessons.firstWin)`
   push-ot végez (pontosan a RÉGI `_completeFirstWin` viselkedése), az
   `onSkip` csak `router.go(entryLocation)`-t hív — mindkettő ugyanazt az
   előre kiszámolt `entryLocation` (`entryLocationFor(...)`) változót
   olvassa, literál útvonal egyikben sincs. A `widget.onFirstWin` override
   (tesztek) útja VÁLTOZATLAN — a Stage csak a default navigációs ágban jelenik meg.
3. **Az őszinte hiba-ág** (D5/A10) —
   `lib/features/onboarding/screens/first_win_stage_screen.dart`: a widget
   mostantól a TELJES `AsyncValue`-t figyeli (`.hasError`), és hiba esetén a
   MEGLÉVŐ `micPermissionBody`/`micPermissionAction` kulcsokból épülő
   külön ágat mutat (`onboard-first-win-open-settings` gomb,
   `openAppSettings` — pontosan az `analyze_screen.dart:181-183` precedens),
   a "Not now" gomb VÁLTOZATLANUL, feltétel nélkül renderelt marad.
4. **Új gate-tesztfájl** —
   `test/features/onboarding/first_win_production_engine_test.dart`: A8
   (a default gyár típusa + a konfidencia valós forrásból jön), A5-A7 (a
   pontos 0.59/0.60/0.61 határ, EXPLICIT `FakeOnboardingFirstWinEngine`
   override-dal — szándékosan függetlenül a default gyártól, lásd §10.2/3.
   próba), A9 (stop a dispose-on + a megosztott motor újraindul a
   következő figyelőnek), A10 (stream-hiba `AsyncValue` hibaként jelenik
   meg + a Stage kimondja és a skip elérhető marad).
5. **Pin-őrök típus-átírása** (§4 pin-guard):
   - `test/app/routing/onboarding_first_win_test.dart` — a delayed-persist
     teszt a CTA megnyomása után mostantól a `FirstWinStageScreen`-t várja
     (nem közvetlenül a `LearnScreen`-t), egy erős `LiveFrame`-et emittál a
     MÁR meglévő `strumEngineProvider`/`FakeStrumEngine` override-on át, és
     a Continue gombbal jut el a `LearnScreen`-ig.
   - `test/app/routing/shell_entry_location_test.dart` — a `pumpOnboarding`
     helper mostantól `(GoRouter, FakeStrumEngine)` rekordot ad vissza; az
     "A2" 2×2 mátrix mindkét first-win cellája új `passThroughFirstWinStage`
     helperrel megy át a Stage-en; ÚJ cella: "shell BE × first-win Stage
     'Not now' ALSO settles on /today" — ez az A3 tényleges widget-teszt
     bizonyítéka (lásd §10.2/1. próba).
   - `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` — új
     `'first_win_stage'` `_ScreenFixture` bejegyzés (build +
     `FakeOnboardingFirstWinEngine` override, az e13_r16 golden fixture
     mintáját követve) — az A1-completeness cella ELVÁRJA, hogy minden
     MÉRTEN elérhető screen szerepeljen a mátrixban vagy a kizárási
     listán; lásd §10.3 a maradék piros két cellához.

### 10.2 Falszifikációs próbák (§6.1, mind a NÉGY, ténylegesen lefuttatva és visszaállítva)

**1. próba — literál `/live` az `onSkip` ágban.**
`onboarding_screen.dart`: `onSkip: () => router.go('/live')`.
`flutter test test/app/routing/shell_entry_location_test.dart --plain-name "Not now"`
→ **PIROS**: `Expected: <'/today'> Actual: <'/live'>` az új A3-cellán
("shell BE × first-win Stage \"Not now\" ALSO settles on /today").
Visszaállítva `onSkip: () => router.go(entryLocation)`-ra → **ZÖLD**
(újramérve: `+1: ... All tests passed!`).

**2. próba — exkluzív küszöb.**
`first_win_providers.dart`: `isFirstWinSuccess` `>=` → `>`.
`flutter test test/features/onboarding/first_win_production_engine_test.dart --plain-name "A5-A7"`
→ **A6 (0.60) PIROS** (`onboard-first-win-continue` nem található,
`onboard-first-win-retry` igen), **A5 (0.59) és A7 (0.61) ZÖLD**
maradt — a hármas ténylegesen a HATÁRT méri. Visszaállítva `>=`-ra →
mindhárom ZÖLD.

**3. próba — a default gyár vissza `FakeOnboardingFirstWinEngine.new`-ra.**
`first_win_providers.dart`:
`onboardingFirstWinEngineFactoryProvider = Provider(( _) =>
FakeOnboardingFirstWinEngine.new)`.
`flutter test test/features/onboarding/first_win_production_engine_test.dart`
→ **A8 mindkét cellája PIROS** (a `LiveFirstWinEngine` típus-ellenőrzés és a
`strumEngineProvider`-ből jövő konfidencia egyaránt elbukik — a fake
default sosem emittál a `FakeStrumEngine.emit(...)`-re), **az A5-A7 hármas
(explicit `FakeOnboardingFirstWinEngine` override-dal, a default gyártól
FÜGGETLENÜL) mindhárom cellája ZÖLD maradt** — pontosan ez bizonyítja, hogy
a hármas a SZÁLLÍTOTT forrást méri (A8), nem a tesztbeli felülírást.
(Mellékhatásként az A9/A10 is pirosra vált, mert azok is a default
gyáron/`strumEngineProvider`-en át mérnek — ez helyes, nem tiltott
mellékhatás.) Visszaállítva a produkciós gyárra → mind a 8 teszt ZÖLD.

**4. próba — a hiba-ág elnémítása.**
`first_win_stage_screen.dart`: `final hasError = false; //
asyncConfidence.hasError;`.
`flutter test test/features/onboarding/first_win_production_engine_test.dart --plain-name "A10"`
→ **A10 widget-cellája PIROS** ("the Stage states the error and keeps
\"Not now\" reachable" — a `micPermissionBody` szöveg nem jelenik meg,
helyette a "Listening…" cím marad), a stream-szintű A10-teszt továbbra is
ZÖLD (az `AsyncValue.hasError` maga nem hamisítható a widget szintjén).
Visszaállítva `final hasError = asyncConfidence.hasError;`-re → mindkét
A10-cella ZÖLD.

### 10.3 A §7 gate — csonkítatlan futtatás, MEGTALÁLT lelet

A pontos §7 parancs (mind a 15 tesztútvonal egy hívásban) **PIROS**-sal állt
meg a 15. lépésnél (`test/ui/goldens/e15_r13_full_variant_matrix_test.dart`,
kilépési kód 1), a format/analyze és mind a 14 megelőző tesztlépés ZÖLD
volt. A gate script (`round-gate.sh`) az ELSŐ piros lépésnél megáll, ezért a
záró `architecture`/`secrets`/`l10n` lépések ebben az EGY hívásban nem
futottak le — emiatt külön futtattam ugyanazt a `round-gate.sh`-t a
maradék két útvonallal (`test/ui/ui_baseline_screenshot_test.dart`,
`test/app/navigation/`), ami a `architecture`/`secrets`/`l10n` lépésekkel
együtt **MINDET ZÖLDRE** hozta (`MINDEN GATE ZÖLD`, kilépési kód 0).

**A talált lelet, MÉRT gyökérokkal (pin-guard, brief §4: "ha egy cella a
típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella
hibája"):** a `FirstWinStageScreen` A1 miatt MOST vált elérhetővé
(`check_screen_reachability` → `reachable: true`, lásd alább) — a fájl saját
"A1 — completeness" cellája ezért MEGKÖVETELI, hogy a screen szerepeljen a
`_screens` mátrixban vagy a kizárási listán (§10.1/5. pont: felvettem a
mátrixba, `FakeOnboardingFirstWinEngine` override-dal). Ez viszont a
`_screens.length`/`totalCells` LIVE értékét eggyel/16-tal megemeli, és az
"A5 — completion-report guard" csoport KÉT cellája
(`cites the matrix screen/cell counts…`, `cites the grand total test
count…`) ezt az élő számot szó szerint keresi `docs/ui/chapter-15-completion-report.md`
szövegében — az a fájl NINCS ezen kör `allowed_paths`-án, tehát nem
frissíthető. Ez PONTOSAN a fájl saját, korábbi review-ból (MAJOR-1) örökölt,
és a fájl saját kommentjében (L613/ADR 0112, az E16-R02 precedens) MÁR
dokumentált hibaosztály: *"it goes red for a round that cannot fix it (the
report is outside that round's allowed paths)"*. Ellenpróbát is futtattam:
ha a mátrix-bejegyzést NEM veszem fel, az "A1 — completeness" cella vált
pirosra helyette (kevesebb piros cella összesen, de valódi lefedettségi
hiányt hagyna nyitva) — a mátrixba-vétel a helyesebb mérnöki döntés (valódi
regressziós lefedettség > egy elavult szöveg-egyeztetés), ezért ezt
tartottam meg. **A `docs/ui/chapter-15-completion-report.md` frissítése egy
követő HEAL/kör dolga** (a §4 allowed_paths bővítésével).

Mért kimenet:

```
$ dart run tool/check_screen_reachability.dart --format json
...
{
  "screenPath": "lib/features/onboarding/screens/first_win_stage_screen.dart",
  "className": "FirstWinStageScreen",
  "declaredAt": {...},
  "reachable": true,
  ...
}
```

```
$ tools/round-gate.sh <mind a 15 útvonal egy hívásban>
[1] format: ZÖLD
[2] analyze: ZÖLD
[3]  test test/features/onboarding/: ZÖLD
[4]  test test/features/onboarding/first_win_production_engine_test.dart: ZÖLD
[5]  test test/e2e/full_app_walkthrough_test.dart: ZÖLD
[6]  test test/app/routing/app_router_test.dart: ZÖLD
[7]  test test/app/routing/onboarding_first_win_test.dart: ZÖLD
[8]  test test/app/routing/shell_entry_location_test.dart: ZÖLD
[9]  test test/core/screen_size_guard_test.dart: ZÖLD
[10] test test/features/onboarding/first_win_test.dart: ZÖLD
[11] test test/features/onboarding/onboarding_resume_test.dart: ZÖLD
[12] test test/features/onboarding/onboarding_test.dart: ZÖLD
[13] test test/features/onboarding/permission_primer_test.dart: ZÖLD
[14] test test/ui/goldens/e13_r16_screens_golden_test.dart: ZÖLD
[15] test test/ui/goldens/e15_r13_full_variant_matrix_test.dart: PIROS (kilépési kód 1)
  Failing tests:
    ...A5 — completion-report guard... cites the grand total test count...
    ...A5 — completion-report guard... cites the matrix screen/cell counts...
exit 10
```

```
$ tools/round-gate.sh test/ui/ui_baseline_screenshot_test.dart test/app/navigation/
[1] format: ZÖLD
[2] analyze: ZÖLD
[3] test test/ui/ui_baseline_screenshot_test.dart: ZÖLD
[4] test test/app/navigation/: ZÖLD
[5] architecture: ZÖLD
[6] secrets: ZÖLD
[7] l10n: ZÖLD
MINDEN GATE ZÖLD.
exit 0
```

### 10.4 Érintetlen szerződések (ellenőrizve)

`kFirstWinConfidenceThreshold` (0.60) és az `isFirstWinSuccess` inkluzív
predikátuma VÁLTOZATLAN (csak a 2. falszifikációs próba idejére, majd
azonnal visszaállítva). Nincs új `AudioOwner` variáns, nincs
`lib/core/audio/**` módosítás, nincs új l10n kulcs, nincs új
`OnboardingStep` érték, nincs új top-level route.

### 10.5 Javító kör #1 — BLOCKER-1 / MAJOR-1 feloldása (`sonnet-impl`, 2026-09-05)

**A lelet gyökéroka (mérve, `.pipeline/E17-R01-review-findings.md`).**
`_completeFirstWin` a Stage-et pageless `MaterialPageRoute`-ként pusholta a
CÉL-oldal (`entryLocation`) fölé. Az `onSkip` ág ezután `router.go
(entryLocation)`-t hívott — UGYANARRA a location-re, amin a router már állt —,
ezért a pushed route-ot semmi nem zárta be (BLOCKER-1: a felhasználó a "Not
now" után is a Stage-en ragadt). Az `onContinue` ág a `LearnScreen`-t a Stage
FÖLÉ pusholta a Stage bezárása nélkül, ezért a lecke poppolása egy elavult
"siker" Stage-re esett vissza, nem a shellre (MAJOR-1).

**A javítás.** `lib/features/onboarding/screens/onboarding_screen.dart`:
mindkét ág immár a Stage-et pusholó UGYANAZT a `navigator` referenciát
használja a route imperatív bezárására, nem a router-t:
- `onSkip: () => navigator.pop()` — bezárja a Stage saját pushed route-ját,
  felfedve az `entryLocation`-t, amin a router már áll.
- `onContinue: () => navigator.pushReplacement(MaterialPageRoute(builder:
  (_) => LearnScreen(lesson: Lessons.firstWin)))` — LECSERÉLI a Stage
  route-ját a leckére (nem fölé pusholja), így a lecke az `entryLocation`-ra
  van horgonyozva, és a vissza-gesztus a shellre visz.

Literál útvonal egyik ágban sem jelent meg (ADR 0534 D2 változatlan).

**Gépi őrök (`test/app/routing/shell_entry_location_test.dart`).**
1. A MEGLÉVŐ "Not now" A3-cella bővült:
   `expect(find.byType(FirstWinStageScreen), findsNothing)`.
2. ÚJ cella: *"shell BE × first-win Stage Continue: popping the scored
   mini-lesson does not fall back to the Stage — review MAJOR-1"* — Continue
   → `LearnScreen`, a leckét a root-navigatoron poppolva → `FirstWinStageScreen`
   `findsNothing`, `LearnScreen` `findsNothing`, és a settled router-URI
   `entryLocationFor(true)`.

**Falszifikáció (tényleges kimenet, nem parafrázis).**

*Próba 1 — `onSkip` visszaállítva `router.go(entryLocation)`-ra
(a bezárás nélkül):*

```
$ flutter test test/app/routing/shell_entry_location_test.dart --plain-name "Not now"
Expected: no matching candidates
  Actual: _TypeWidgetFinder:<Found 1 widget with type "FirstWinStageScreen": [...]>
   Which: means one was found but none were expected
review BLOCKER-1: "Not now" must actually dismiss the Stage, not just settle
the router on a location it was already on
00:02 +0 -1: Some tests failed.
```

→ **PIROS**, a többi cella nem futott ebben a szűkített hívásban (a
`--plain-name` csak az érintett cellát futtatta). Visszaállítva
`onSkip: () => navigator.pop()`-ra.

*Próba 2 — `onContinue` visszaállítva `navigator.push(...)`-ra (a Stage
bezárása/lecserélése nélkül, a lecke a Stage FÖLÉ kerül):*

```
$ flutter test test/app/routing/shell_entry_location_test.dart --plain-name "MAJOR-1"
Expected: no matching candidates
  Actual: _TypeWidgetFinder:<Found 1 widget with type "FirstWinStageScreen": [...]>
   Which: means one was found but none were expected
the back gesture after the scored lesson must land on the shell, not
re-enter a stale "success" Stage
00:02 +2 -1: Some tests failed.
```

→ **PIROS** az új MAJOR-1 cellán. Visszaállítva
`onContinue: () => navigator.pushReplacement(...)`-ra — a visszaállítás után
a fájl teljes 8 cellája ZÖLD (`00:03 +8: All tests passed!`).

**A §7 gate — csonkítatlan, mind a 17 tesztútvonal + format/analyze/
architecture/secrets/l10n EGY hívásban:**

```
[1] format: ZÖLD
[2] analyze: ZÖLD
[3]  test test/features/onboarding/: ZÖLD
[4]  test test/features/onboarding/first_win_production_engine_test.dart: ZÖLD
[5]  test test/e2e/full_app_walkthrough_test.dart: ZÖLD
[6]  test test/app/routing/app_router_test.dart: ZÖLD
[7]  test test/app/routing/onboarding_first_win_test.dart: ZÖLD
[8]  test test/app/routing/shell_entry_location_test.dart: ZÖLD
[9]  test test/core/screen_size_guard_test.dart: ZÖLD
[10] test test/features/onboarding/first_win_test.dart: ZÖLD
[11] test test/features/onboarding/onboarding_resume_test.dart: ZÖLD
[12] test test/features/onboarding/onboarding_test.dart: ZÖLD
[13] test test/features/onboarding/permission_primer_test.dart: ZÖLD
[14] test test/ui/goldens/e13_r16_screens_golden_test.dart: ZÖLD
[15] test test/ui/goldens/e15_r13_full_variant_matrix_test.dart: ZÖLD
[16] test test/ui/ui_baseline_screenshot_test.dart: ZÖLD
[17] test test/app/navigation/: ZÖLD
[18] architecture: ZÖLD
[19] secrets: ZÖLD
[20] l10n: ZÖLD
MINDEN GATE ZÖLD.
```

A korábbi H3 halt gyökéroka (`e15_r13_full_variant_matrix_test.dart` A5
completion-report guard) a `origin/main @ b1abed91` heal beolvasztása után
(l. `b148f7dc`) ezen a fán is ZÖLD — a javító kör ezt nem érintette.

## 11. Review — a Claude tölti ki

> **VÉGSŐ VERDIKT (2026-09-05, 2. review a javító kör után): APPROVED.**
> A 11.1–11.4 az ELSŐ review (H3 halt) történeti feljegyzése; a halt gyökérokát
> az ADR 0112 önjavító kör a `main`-en feloldotta (`b1abed91`), a kör a
> §11.5–11.7 szerint folytatódott. Nyitott BLOCKER/MAJOR/MINOR: **nincs**.

**Verdikt (1. review, SUPERSEDED): HALT — H3 (a feloldás az `allowed_paths` TÁGÍTÁSÁT kívánja).** A kör
implementációja MÉRTEN kész és jó (A1–A10 zöld, 4/4 falszifikációs próba
dokumentálva), a §7 gate mégsem hozható zöldre a kör engedélyezett fájllistáján
belül. A halt tehát NEM az implementáció hibája — a scope-audit is `ok`
(`scope_audit_base=24c21e25`, `scope_audit_changed=9`, minden fájl a listán).

### 11.1 A lelet — az orchestrátor FÜGGETLEN mérése (nem az implementer bemondása)

```
$ cd /home/ubuntu/ss-sonnet-impl-e17-r01
$ flutter test test/ui/goldens/e15_r13_full_variant_matrix_test.dart
00:58 +1177 -2: Some tests failed.

Failing tests:
  …e15_r13_full_variant_matrix_test.dart: A5 — completion-report guard …
      cites the grand total test count this file itself produces …
  …e15_r13_full_variant_matrix_test.dart: A5 — completion-report guard …
      cites the matrix screen/cell counts derived from THIS file, not hand-typed
```

**Gyökérok.** A két cella a MÁTRIX ÉLŐ számait keresi szó szerint a
`docs/ui/chapter-15-completion-report.md` szövegében
(`e15_r13_full_variant_matrix_test.dart:3862-3911`):

| Mit vár a cella | A report ma | A kör után |
|---|---|---|
| `_screens.length` | `72 screens` (report:22) | **73** |
| `_screens.length * 16` | `1152 cells` (report:24) | **1168** |
| `totalCells + 5 (A1) + 6 (A5)` | `1163 tests total` (report:27,89,92) | **1179** |

A `docs/ui/chapter-15-completion-report.md` **NINCS a kör `allowed_paths`-án**
(és a kör-brief §4 pin-őr bekezdése kifejezetten csak a *lecserélt képernyő
típusának* átírására jogosít a pin-cellákban).

### 11.2 Miért nincs a listán belüli feloldás — mind a HÁROM ág mérve

1. **Mátrixba vétel** (amit az implementer választott): a fenti két cella piros.
2. **A kizárási listára tétel:** a
   `test('names WrappedPreviewScreen as the sole coverage exclusion')` cella
   `expect(_exclusions, hasLength(1))`-et ír elő
   (`e15_r13_full_variant_matrix_test.dart:3937-3944`), és a report is a
   `WrappedPreviewScreen`-t nevezi meg EGYETLEN kizárásként → két új piros, és a
   feloldásukhoz megint a report kell.
3. **Lefedetlenül hagyás:** az „A1 — completeness" cella
   (`:3735-3754`, *measured reachable set ⊆ matrix ∪ exclusion list*) vált
   pirosra — és ez a kör A1 acceptance-kritériumának a párja, tehát a
   lefedetlenség a kör SIKERÉNEK a tagadása lenne.

Cella törlése/`skip`-je/gyengítése a brief §4 szerint TILOS, tehát nem opció.

### 11.3 Ez a kör SIKERE váltja pirosra a kaput — L612/L613 hibaosztály, 14 körön át ismétlődne

A guard-fájl SAJÁT fejléce már kimondja ezt a hibaosztályt
(`e15_r13_full_variant_matrix_test.dart:3217-3233`, L613 / ADR 0112 önjavító kör):

> „A guard that re-measures the LIVE tree and demands the report cite THOSE
> numbers therefore goes red the moment any later round legitimately changes
> reachability, and **it goes red for a round that cannot fix it (the report is
> outside that round's allowed paths)**."

Az E16-R02-re szánt önjavítás a *migration + reachability* cellát átvitte egy
rögzített baseline-snapshotra (`_baselinePath`), a **mátrix-darabszám** celláit
viszont ÉLŐ mérésen hagyta. Az E17 sáv MINDEN köre (14 kör) épp a
reachability növelése, tehát ez a fal körönként újra elő fog jönni.

### 11.4 Javasolt feloldás az önjavító körnek (két alak, sorrendben)

1. **Szerkezeti (ajánlott):** a `_screens.length` / `totalCells` / grand-total
   celláit is a rögzített baseline-hoz mérni (a `_baselinePath` snapshot
   mintájára, `e15_r13_full_variant_matrix_test.dart:3227-3233` indoklása
   szerint) — a report DÁTUMOZOTT történeti feljegyzés, nem élő mérce. Az élő
   fát az A1-completeness csoport őrzi tovább, tehát a mérce NEM gyengül.
   Ez egyszer old fel 14 kört.
2. **Pontszerű:** az E17-R01 `allowed_paths` + `gate_tests` bővítése a
   `docs/ui/chapter-15-completion-report.md`-vel, és a 72/1152/1163 →
   73/1168/1179 átírása a kör diffjében.

A kör implementációs commitjai (`74288e86`, `e1631db3`) a
`sonnet-impl/e17-r01-onboarding-first-win-stage-wiring` ágon állnak, az
originra pusholva — az önjavítás után a kör a review + CI + merge lépésnél
folytatható, nem kell újraimplementálni.

### 11.5 A halt feloldása és az upstream-szinkron (2026-09-05, folytatás)

Az önjavító kör a `main`-en a **szerkezeti** feloldást választotta (a §11.4/1.
javaslat): `b1abed91` — „A dátumozott jelentés darabszám-celláit is a RÖGZÍTETT
pillanatkép őrzi" (L653; a `test/fixtures/ui/e15_r13_completion_report_baseline.json`
`matrix` blokkja + a két A5-cella a snapshotból veszi a várt értéket). A kör-ág
ezért NEM indult újra: az orchestrátor a §0.3 szerint mérte és építette be az
upstreamet.

```
$ git -C /home/ubuntu/ss-sonnet-impl-e17-r01 merge-base --is-ancestor origin/main HEAD
ANCESTOR: NEEDS MERGE
$ git merge --no-ff origin/main
Auto-merging test/ui/goldens/e15_r13_full_variant_matrix_test.dart
Merge made by the 'ort' strategy.   (b148f7dc — konfliktus nélkül)
```

A `b148f7dc` fán a §7 gate ÚJRA lefutott, csonkítatlanul:

```
$ tools/round-gate.sh <a §7 mind a 15 tesztútvonala>
    test test/ui/goldens/e15_r13_full_variant_matrix_test.dart zöld
    architecture / secrets / l10n                              zöld
MINDEN GATE ZÖLD
```

— azaz a H3-at okozó két cella a heal után zöld, a kör mércéje NEM gyengült.

### 11.6 2. review — két lelet a zöld kapu MÖGÖTT (eldobható próbatesztek)

A gate zöldje nem review: a `b148f7dc` fáról készült izolált klónban
(`/tmp/review-e17-r01`) két ELDOBHATÓ próba mérte a szállított felhasználói
utat. Mindkettő PIROS lett — a kör celláival zölden.

| Lelet | Mit mértem | Gyökérok |
|---|---|---|
| **BLOCKER-1** | „Not now" után `FirstWinStageScreen` `findsOneWidget` (a router közben `/today`-en) | a Stage pageless route-ját a `router.go(entryLocation)` NEM zárja be, mert a router már azon a location-ön áll → a felhasználó a Stage-en ragad |
| **MAJOR-1** | a pontozott mini-lecke poppolása után `FirstWinStageScreen` `findsOneWidget` | az `onContinue` a leckét a Stage FÖLÉ pusholta → a vissza-gesztus egy elavult „siker" Stage-re esik vissza (a kör ELŐTT a shellre vitt) |

A leletlista: [`.pipeline/E17-R01-review-findings.md`](../../.pipeline/E17-R01-review-findings.md).
A javító kört ugyanaz a motor (`sonnet-impl`) vitte, a leletlistával — a
javítás és a falszifikáció a §10.5-ben, tényleges kimenettel.

### 11.7 A javító kör ellenőrzése leletenként — VÉGSŐ DÖNTÉS: APPROVED

- **BLOCKER-1 → ZÁRVA.** `onSkip: () => navigator.pop()` (ugyanaz a
  `navigator` referencia, amelyik a Stage-et pusholta). Az őr a MEGLÉVŐ A3
  cellába került (`shell_entry_location_test.dart`), és pontosan azt az
  állítást használja, amellyel a próbám pirosat mért.
- **MAJOR-1 → ZÁRVA.** `onContinue: () => navigator.pushReplacement(...)` — a
  lecke az `entryLocation`-ra horgonyzódik. Új cella méri, hogy a lecke
  poppolása után sem a Stage, sem a lecke nincs a fán, és a settled URI
  `entryLocationFor(true)`.
- **ADR 0534 D2 érintetlen:** literál útvonal EGYIK ágban sem szerepel, és a
  landolási hely továbbra is az `entryLocationFor(...)` EGYETLEN forrása — az
  új ágak nem navigálnak külön location-re, hanem az imperatív route-ot
  bontják le, ami alatt már az a location áll. Az A3 cella ezt SETTLED
  router-URI-ként állítja, nem a hívás alakjából következteti.
- **Független ellenőrzés (orchestrátor, nem implementer-bemondás):**

```
$ flutter test test/app/routing/shell_entry_location_test.dart
00:03 +8: All tests passed!
```

- **Scope:** a javító kör 3 fájlt írt (`onboarding_screen.dart`,
  `shell_entry_location_test.dart`, ez a brief) — mind az `allowed_paths`-on;
  cella nem lett törölve, `skip`-elve vagy gyengítve.

Nyitott BLOCKER/MAJOR/MINOR nincs. A kör a CI-kapun (`full-gate.yml` +
`router-ci.yml`, exact-SHA) mehet merge-re.
