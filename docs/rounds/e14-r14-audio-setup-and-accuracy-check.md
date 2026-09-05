# E14-R14 — Automatikus Audio Setup és Accuracy Check

- **Státusz:** READY (pre-flight lefutott 2026-09-05, kód újraolvasva: `main @ 5f772a20`)
- **Típus:** Chapter 14, Kör 14 (a truthfulness hotfix blokk záró köre)
- **Kör-azonosító:** `E14-R14`
- **Branch:** `sonnet-impl/e14-r14-audio-setup-and-accuracy-check`
- **Előfeltétel:** `E14-R05` (signal quality analyzer) és `E14-R11` merge-elve.
- **Brief szerzője:** Claude (Opus 5)
- **Kiosztott ADR:** `0519` (a foglalótól, `tools/round-slots.py reserve-adr --round E14-R14`)
  — **a Claude írta meg a pre-flightban, a `docs/adr/` a TILOS zónában van.**
  Az előre beírt `0366` ELAVULT, lásd §0.0/R1.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/settings/providers/input_latency_provider.dart`-ot és a
> `lib/features/onboarding/onboarding_provider.dart`-ot — a profil ezek mellé
> kerül, nem helyettük. Eltérésnél §0.0 revízió.

**Kockázat = high, indoklás:** a kör mikrofon-felvételt vezérel és
eszköz-specifikus profilt tárol (`privacy` osztály a `.ai/router.toml`
high-risk listáján), ezért a security-review kötelező.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/onboarding/audio_setup/audio_setup_step.dart",
  "lib/features/onboarding/audio_setup/audio_setup_controller.dart",
  "lib/features/onboarding/audio_setup/audio_profile.dart",
  "lib/features/onboarding/audio_setup/audio_profile_store.dart",
  "lib/features/onboarding/public.dart",
  "test/features/onboarding/audio_setup_controller_test.dart",
  "test/features/onboarding/audio_profile_store_test.dart",
  "docs/rounds/e14-r14-audio-setup-and-accuracy-check.md",
]
gate_tests = [
  "test/features/onboarding/audio_setup_controller_test.dart",
  "test/features/onboarding/audio_profile_store_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Pre-flight brief-revízió (2026-09-05, `main @ 5f772a20`) — KÖTELEZŐ

A brief 2026-08-20-án készült; a `brief-lint` két `strict` leletet adott
(**S12**, **S15**). A pre-flight újraolvasta a hivatkozott fájlokat. Az alábbi
revíziók **kötik** az implementert; a teljes mérés az
[ADR 0519](../adr/0519-audio-setup-profile-as-input-not-calibration.md)
„Kontextus" szakaszában van.

**R1 (S15 → ADR-szám). Az előre kiosztott `0366` ELAVULT.** A foglaló
(`tools/round-slots.py reserve-adr --round E14-R14`) a **`0519`**-et adta; a fán
a legmagasabb szám `0517`. Az ADR megírva: `docs/adr/0519-audio-setup-profile-as-input-not-calibration.md`.
A brief §5 mostantól erre hivatkozik.

**R2 (S15 → mi maradt igaz a §2-ből).** A `main` a brief alapja óta elmozdult:
`lib/features/onboarding/onboarding_provider.dart` MÓDOSULT, és négy ÚJ fájl
landolt a feature-gyökér alatt (`first_win_engine.dart`,
`first_win_providers.dart`, `screens/first_win_stage_screen.dart`,
`screens/permission_primer_screen.dart`). Újramérve:

- **IGAZ marad:** `lib/features/onboarding/audio_setup/` **nem létezik**; a
  `settings` latency-providerek megvannak és a profil nem írja felül őket; a
  wizard az onboarding modulja lesz.
- **NEM IGAZ tovább:** `lib/features/onboarding/public.dart` **nem létezik** —
  a §4 „additív export" sora félrevezető: a fájlt a kör **létrehozza**. A
  generált-barrel őr (`tool/check_architecture.dart:804`) csak azokra a
  feature-ökre fut, amelyeknek van `lib/features/<f>/public/` fragmentum-
  könyvtára (mérve: ma egyedül a `practice_generator`), ezért a kézzel írt
  barrel szabályos.
- **NINCS időközben merge-elt szerződés ugyanerre a döntésre.** Mérve:
  `grep -rln "AudioProfile\|audio_profile\|micRoute\|audioRoute" lib/ test/` →
  az onboarding és a live fában nulla találat. A négy új fájl egyike sem
  deklarálja az `AudioSetupStep` / `AudioProfile` / `AudioProfileStore` /
  `AudioSetupController` típust → nincs S5 típusütközés. Az `OnboardingStep`
  (`welcome, permission, done`) egy MÁSIK, a
  `test/features/onboarding/onboarding_resume_test.dart` által kipinnelt enum,
  amelyhez ez a kör **nem nyúl**.
- **A kör EGYETLEN döntési helye** az új `lib/features/onboarding/audio_setup/`
  könyvtár. A meglévő `onboarding_provider.dart`-ot, a `screens/**`-ot és a
  `settings/**`-ot a kör NEM módosítja.

**R3 (új, kötelező — architektúra-kapu). A `SignalQualitySnapshot` KIZÁRÓLAG a
`lib/features/live/public.dart` barrelen át importálható.** Mérve:
`tool/check_architecture.dart:382-392` — a `crossFeatureImportsMustUsePublicApi`
szabály a mély importot (`.../live/domain/recognition/signal_quality_snapshot.dart`)
architektúra-sértésként jelenti, és a kapu a `tools/round-gate.sh` `architecture`
lépése. Az allowlist a kör TILOS zónájában lévő `tool/check_architecture.dart`-ban
él → bővítése **H3**. Az export MÁR LÉTEZIK (`lib/features/live/public.dart:29`),
tehát a legális út ma is járható. Ugyanez a kikötés az ADR 0519 D6.

**R4 (új, kötelező — tárolókulcs). Az `AudioProfileStore` feature-lokális
`static const String storageKey`-t használ, NEM vesz fel `StorageKeys`
bejegyzést** — `lib/core/storage/` a tilos zónában van. Ez a merge-elt
precedens folytatása: `OnboardingStepController.storageKey = 'ss.onboarding.step'`
(`lib/features/onboarding/onboarding_provider.dart:64`), a doc-commentbe írt
indoklással együtt. Javasolt érték: `ss.onboarding.audio_profile`. Az elérhető
tároló-API: `KeyValueStore.readString/writeString/remove/contains`
(`lib/core/storage/key_value_store.dart`), szinkron olvasással.

**R5 (S12 → a §7 gate-parancs).** A §7 parancsa nem tükrözte a `gate_tests`
listát; javítva — a §7 mostantól mindkét gate-tesztet külön útvonalként
sorolja fel.

## 0.1 Kötött scope-szűkítés a SDD-hez képest (drift, KÖTELEZŐ így)

A SDD Kör 14 a wizard **képernyőjét** is kéri. Ez a kör a **lépés-gépet, a
profilt és a tárolót** építi, képernyő nélkül — ugyanaz a mért ok, mint az
`E14-R06`-nál: a képernyők helye a Chapter 13 sáv (`E13-R16` onboarding), és
két sáv ugyanarra a felületre írva fájl-ütközést adna. A UI-bekötés külön kör
(`E14-R14b`); a jelen kör acceptance-e nem hivatkozhat rá.

## 1. Cél

A felhasználó **ne vakon kezdjen**: egy 30–60 másodperces lépéssor felmérje a
csendet, a hangerőt, a latencyt és néhány ismert akkordot/pengetést, majd adjon
konkrét telefonelhelyezési tanácsot, és mentsen **eszköz+audio-route
specifikus** profilt. A modellt tilos a mérésre „ráhangolni" — a profil csak
input gain / latency / minőségi elvárás és személyes confidence-profil.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §9/4–5:** tilos thresholdot egyetlen játékosra hangolni, és
  tilos shipping DSP/ML konstanst mért A/B nélkül mozgatni. A profil ezért
  BEMENET a döntési rétegnek, nem konstans-felülírás.
- **E14-R05:** a `SignalQualitySnapshot` a wizard mérőeszköze — a kör nem ír
  új jelminőség-számítást.
- **[L305](../LESSONS.md#l305) (pre-flight visszakeresés, `--corpus lessons,halts,adr`):**
  egy wizard folytatási pontját NEM szabad az adat JELENLÉTÉBŐL következtetni —
  az E07-R20 `PlanSetupController._resumeStep`-je így nem tudta megkülönböztetni
  az explicit „nem tudom" választ a meg sem nyitott lépéstől. Ide fordítva: az
  `AudioSetupController` állapotát EXPLICIT lépés-állapot hordozza, nem az
  „ennek a mezőnek már van értéke" következtetés — ez a D4 (megszakítás →
  nincs részleges profil) másik oldala.
- **[L70](../LESSONS.md#l70) (`--corpus lessons,halts`):** a hiányzó mezők
  visszaolvasáskor valódi adatvesztésnek minősülnek, nem elfogadható migrációs
  normalizációnak — az 5. acceptance-pont migrációs cellája ezért mezőnkénti
  egyezést mér, nem csak „nem dobott hibát".

## 2. Jelenlegi állapot — mért tények

- `lib/features/settings/providers/input_latency_provider.dart` és
  `visual_latency_provider.dart` — MEGLÉVŐ latency-beállítások; a profil ezeket
  nem írja felül, hanem javaslatot ad hozzájuk.
- `lib/features/onboarding/onboarding_provider.dart` + `screens/onboarding_screen.dart`
  — a MEGLÉVŐ onboarding; a wizard ennek a modulja lesz.
- `lib/features/onboarding/audio_setup/` — **nem létezik**; ez a kör hozza létre.

## 3. Scope

**Benne:** lépés-gép (megszakítható, újraindítható), profil-modell, tároló
(mentés/olvasás/migráció/törlés), elavulás mic-route vagy mintavétel változásra,
javaslat-szöveg kiszámítása.

**Nincs benne:** képernyő (§0.1), modellhangolás, DSP-konstans, hálózat,
felvétel-export (az az `E14-R06` consent-kapuja mögött él).

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/onboarding/audio_setup/audio_setup_step.dart` | a lépések típusos leírása |
| `lib/features/onboarding/audio_setup/audio_setup_controller.dart` | a lépés-gép |
| `lib/features/onboarding/audio_setup/audio_profile.dart` | profil-modell + verzió |
| `lib/features/onboarding/audio_setup/audio_profile_store.dart` | tárolás, migráció, törlés |
| `lib/features/onboarding/public.dart` | additív export |
| `test/features/onboarding/audio_setup_controller_test.dart` | lépés-gép mátrix |
| `test/features/onboarding/audio_profile_store_test.dart` | migráció, elavulás, törlés |
| `docs/rounds/e14-r14-audio-setup-and-accuracy-check.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/features/live/engine/**`,
`lib/features/settings/**`, `lib/features/onboarding/screens/**`, `assets/**`,
`ml/**`, `docs/adr/**`, `docs/rag/chunks/**`, `.github/workflows/**`,
`tools/round-gate.sh`.

## 5. Kötött architekturális döntések ([ADR 0519](../adr/0519-audio-setup-profile-as-input-not-calibration.md))

### 5.1 A profil bemenet, nem felülírás

A profil a döntési réteg BEMENETE; egyetlen DSP/ML konstanst sem ír felül.
**NEM elfogadható**: „a profil beállítja a küszöböt a classifierben".

### 5.2 Rossz jelminőség nem ad sikerállapotot

Ha a mérés `tooQuiet`/`clipping`/`tooNoisy` állapotban zárul, a wizard
`needsAttention` eredményt ad konkrét tanáccsal — soha nem `success`-t.

### 5.3 A profil elavul, ha a route változik

Mic-route vagy mintavételi frekvencia érdemi változásakor a profil
`stale`; a stale profil nem használható fel csendben.

### 5.4 Megszakítható és újraindítható

Bármely lépésen megszakítható; a félbehagyott futás nem hagy részleges
profilt (atomikus mentés).

### 5.5 Verziózott tárolás, tesztelt migráció

`schemaVersion` kötelező; ismeretlen verzió típusos hiba, a migráció külön
tesztelt út (ADR 0054 mintája).

## 6. Acceptance criteria

1. A lépés-gép a SDD lépéseit tartalmazza (csendmérés, egy erős down, egy up,
   E/Am/G/C ellenőrzés, pozíció-javaslat), és a teljes futás hossza a
   **30–60 másodperc** tartományban van: a hármas cella a felső határra — a
   határ **alatt** (59 s) → elfogadott, pontosan **rajta** (60 s) → elfogadott
   (inkluzív), a határ **fölött** (61 s) → a teszt hibát jelez.
2. `tooQuiet` fixture-ön az eredmény `needsAttention`, és a tanács szövege nem
   üres.
3. Megszakítás után nincs elmentett részleges profil (a store üres marad).
4. Mic-route változás után a profil `stale`, és a getter nem adja vissza
   érvényesként.
5. Ismeretlen `schemaVersion` típusos hibát ad; a támogatott régi verzió
   migrálódik, és a migrált profil mezői egyeznek a várttal.
6. Törlés után a profil nem olvasható vissza.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A wizard rossz jelnél is `success`-t ad | 2. pont |
| Lépésenkénti (nem atomikus) mentés | 3. pont |
| A route-változás nem érvényteleníti a profilt | 4. pont |
| Ismeretlen verzió → default profil | 5. pont |
| A törlés csak flaget állít | 6. pont |
| A hossz-ellenőrzés exkluzív felső határral | 1. pont „pontosan rajta" cellája |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/onboarding/audio_setup_controller_test.dart test/features/onboarding/audio_profile_store_test.dart
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: az atomikus mentés ideiglenes lépésenkéntire cserélésével
a 3. pont **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. `AudioSetupStep` + lépéslista, teszttel.
2. `AudioProfile` + verzió + migráció.
3. `AudioProfileStore` (atomikus mentés, elavulás, törlés).
4. `AudioSetupController` (megszakítás, eredmény-osztályozás).

## 9. Kockázatok

- **Mikrofon a tesztben:** a controller-teszt fake jelminőség-forrást kapjon;
  valódi mikrofon a CI-n nincs.
- **Scope-csúszás a UI felé:** a §0.1 tiltja.
- **Profil-alapú „kalibrálás" kísértése:** az 5.1 tiltja; igény esetén `stopped`.

## 10. Implementation handoff — az implementer tölti ki

**Motor:** `sonnet-impl` (Claude Sonnet 5, `--effort medium`). Az ADR 0519-et
nem módosítottam, csak követtem.

### Fájlonként mit építettem

- **`lib/features/onboarding/audio_setup/audio_setup_step.dart`** — az
  `AudioSetupStepKind` enum (silence, strongDownStrum, upStrum, chordCheck,
  positionSuggestion), az `AudioSetupStep` típus (`kind` + `expectedDuration`
  + opcionális `expectedChord`), a rögzített `AudioSetupStep.sequence` (8
  lépés: csend → erős down → up → E/Am/G/C → pozíció-javaslat, egyenként
  5s-os tervezett résszel, összesen 40s), és a hossz-elfogadási ablak
  önálló, tiszta függvénye: `isAudioSetupDurationAccepted(Duration)` a
  `kAudioSetupMinDuration`/`kAudioSetupMaxDuration` (30s/60s, mindkettő
  inkluzív) konstansokkal. A mérce-mátrix 1. pontjának cellái ide kerültek,
  mert ez a lépés-gép **statikus alakja**, nem a controller futásideje —
  a teszt egész literálból (`Duration(seconds: 59/60/61)`) hívja a
  függvényt, nem összegzett/számolt értékből.
- **`lib/features/onboarding/audio_setup/audio_profile.dart`** — az
  `AudioProfile` immutable modell (`schemaVersion`, `micRouteId`,
  `sampleRateHz`, `suggestedInputGainDb`, `inputLatencyMsAtCapture`,
  `visualLatencyMsAtCapture`, `qualityExpectation` [`SignalQualityState`,
  a `live/public.dart` barrelen át importálva, D6], `confidenceProfile`,
  `recordedAt`), `toJson`/`AudioProfile.decode` (fail-closed: hiányzó mező
  vagy ismeretlen `schemaVersion` → típusos `ArgumentError`, sosem default
  vagy `null` — a `SignalQualitySnapshot.fromJson` mintáját követve), és a
  `isStaleFor({currentMicRouteId, currentSampleRateHz})` predikátum (D3). A
  migráció egy feltételezett, a kör előtti prototípus-alakú `schemaVersion:
  0`-t old fel a jelenlegi (`1`) alakra — mezőnkénti átnevezéssel (`route` →
  `micRouteId`, `gainDb` → `suggestedInputGainDb`, `recordedAtEpochMs`
  epoch-ms → `recordedAt` ISO-8601, stb.), egyetlen mező elvesztése nélkül
  (L70).
- **`lib/features/onboarding/audio_setup/audio_profile_store.dart`** — az
  `AudioProfileStore` a `KeyValueStore`-ra épül, feature-lokális
  `storageKey = 'ss.onboarding.audio_profile'` konstanssal (R4/D7,
  `OnboardingStepController.storageKey` precedens). API: `read()` (fail-
  closed decode), `readValid({currentMicRouteId, currentSampleRateHz})`
  (elavulás-szűrt getter, D3), `save(AudioProfile)` (EGYETLEN atomikus
  `writeString` hívás — nincs lépésenkénti write API a store-on, D4), és
  `clear()` (valódi `remove`, nem flag).
- **`lib/features/onboarding/audio_setup/audio_setup_controller.dart`** —
  az `AudioSetupController` explicit `AudioSetupRunStatus` állapotgéppel
  (`notStarted, inProgress, completed, aborted` — sosem az „van-e már adat"
  következtetéséből, L305). `start()` / `recordStep(SignalQualitySnapshot)`
  / `abort()`. A `recordStep` az UTOLSÓ lépésnél hívja az egyetlen
  `_finish()`-t, ami az EGYETLEN helyen menti a store-ba (D4). Az
  eredmény-osztályozás (D2): bármely nem-`good` állapot a futás bármely
  lépésén `needsAttention`-t ad nem üres tanáccsal, és NEM ment profilt;
  csak egy végig `good` futás termel `success`-t és profilt. A
  `suggestedInputGainDb` egyszerű heurisztika a strum/akkord lépések
  `peakDbfs` átlagából (a csend-lépés kizárva), a `confidenceProfile` a
  `good` lépések aránya — egyik sem ír felül semmilyen DSP/ML konstanst
  (D1), tisztán az `audio_setup` réteg saját, tájékoztató mezője.
- **`lib/features/onboarding/public.dart`** — új, kézzel írt barrel (a
  feature első publikus felülete), a négy `audio_setup/*.dart` fájlt
  exportálja. Nincs `lib/features/onboarding/public/` fragmentum-könyvtár,
  tehát a generált-barrel frissesség-őr (`tool/check_architecture.dart:804`)
  nem fut rá — mérve az `architecture` gate-lépés zöld kimenetén.

### §7.1 Falszifikációs próba — MÉRT kimenet

Ideiglenesen (nem commitolva) a `recordStep`-be egy lépésenkénti
`store.save(...)` hívást szúrtam be minden rögzített lépés után (a
`_finish()` előtti ág elé), majd lefuttattam:

```
flutter test test/features/onboarding/audio_setup_controller_test.dart
```

**PIROS** — 2 teszt bukott:

```
acceptance #2 — ... a tooQuiet fixture ... [E]
  Expected: null
    Actual: <Instance of 'AudioProfile'>
acceptance #3 — ... abort() after a few recorded steps leaves the store empty [E]
  Expected: null
    Actual: <Instance of 'AudioProfile'>
```

(A #2 is bukott, mert a lépésenkénti mentés a `tooQuiet` felismerése előtt
már beírt egy jó-minőségű profilt — ez a D2 másik oldala: a lépésenkénti
mentés nemcsak a megszakítást, hanem a rossz-jelminőségű zárást is elrontja.)

Ezután a beszúrt kódot szó szerint visszaállítottam az eredeti
`_stepIndex`-increment + `_finish()` alakra (`git diff` a visszaállítás után
üres volt a controller fájlra), és újra lefuttatva: **ZÖLD**, mind a 8 teszt
(lásd a gate lenti kimenete).

### Gate — tényleges eredmény

```
tools/round-gate.sh test/features/onboarding/audio_setup_controller_test.dart test/features/onboarding/audio_profile_store_test.dart
```

`format` → ZÖLD, `analyze` → ZÖLD (0 lelet), `test
audio_setup_controller_test.dart` → ZÖLD (8/8), `test
audio_profile_store_test.dart` → ZÖLD (9/9), `architecture` → ZÖLD (12
allowlistelt deviáció, változatlan), `secrets` → ZÖLD, `l10n` → ZÖLD.

### Döntések, amiket a brief nem írt elő explicit

- A `qualityExpectation`/`confidenceProfile`/`suggestedInputGainDb` konkrét
  formuláit a brief nem specifikálta számszerűen (csak azt, hogy a profil
  ezeket „hordozza", D1) — az implementáció egyszerű, kizárólag az
  `audio_setup` rétegben élő heurisztikákat használ (lásd fent), amelyeket
  egyetlen acceptance-pont sem mér számértékben; a mátrix csak a
  `needsAttention`/`success` osztályozást és a mentett/nem-mentett profil
  jelenlétét méri.
- Az `inputLatencyMsAtCapture`/`visualLatencyMsAtCapture` mezőket a
  controller konstruktor-paraméterként kapja (alapérték 0), NEM olvassa be
  közvetlenül a `settings` provider-eiből — a `lib/features/settings/**` a
  kör tilos zónájában van, és egy jövőbeli UI-kör (E14-R14b) fogja ezeket a
  meglévő `inputLatencyProvider`/`visualLatencyProvider` értékeivel
  meghívni a controllert.
- A schemaVersion 0 „legacy" alak feltételezett (ez egy vadonatúj feature,
  nincs valós régi mentés) — a migrációs útvonal a brief 5. acceptance-
  pontjának demonstrálására készült, ugyanazzal a mintával, mint a
  `PracticePlanMigrator` (ADR 0054).

## 11. Review — a Claude tölti ki

**VÉGSŐ DÖNTÉS: APPROVED** — nyitott BLOCKER: 0, MAJOR: 0. A teljes jelentés:
[`docs/reviews/e14-r14-review.md`](../reviews/e14-r14-review.md).

- **Scope-audit:** `ok` (8 fájl, mind az `allowed_paths` listáján; új
  allowlist-bejegyzés nincs — az `architecture` deviáció-szám változatlanul 12).
- **Gate függetlenül újrafuttatva** izolált klónban, `HEAD = 6d34fa65`:
  `format`/`analyze`/`architecture`/`secrets`/`l10n` zöld, `8/8` + `9/9` teszt,
  `GATE_EXIT=0`.
- **Valódi-sértés próbák (eldobható mutációk):** a §7.1 falszifikáció
  REPRODUKÁLVA (lépésenkénti mentés → a 2. és 3. acceptance PIROS); a mély
  import → `crossFeatureImportsMustUsePublicApi` sértés (a §0.0/R3 kapu
  valódi); az inkluzív felső határ `<`-re rontva → az 1. pont „pontosan
  rajta" cellája PIROS. A D2 osztályozás a TELJES `SignalQualityState` enumon
  mérve (mind a hét nem-`good` érték → `needsAttention`, nem üres tanács,
  nincs mentett profil — az `unknown` is).
- **Biztonsági review (`risk = high`, `privacy`): nincs lelet.** A diff nem
  nyit hálózatot, nem naplóz, nem nyúl platform-csatornához, engedélyhez vagy
  felvételhez; a tárolt mezők között nincs hangminta vagy azonosító; a
  `clear()` valódi `remove` (a backing store `contains`-e is mérve).
- **Nyitva hagyva (nem merge-blokkoló):** MINOR-1 — a `toJson()` a
  `currentSchemaVersion` konstanst írja ki a példány `schemaVersion` mezője
  helyett, így egy nem-current verzióval épített profil mentés után csendben
  `1`-esként jön vissza (ma egyetlen producer sem tud ilyet előállítani).
  NOTE-1 sérült blob → `FormatException` (továbbra is fail-closed);
  NOTE-2 a `confidenceProfile` ma mindig `1.0`; NOTE-3 a `schemaVersion: 0`
  legacy alak feltételezett (a §10 ezt kimondja). Mindhárom a `E14-R14b`
  bemenete.

