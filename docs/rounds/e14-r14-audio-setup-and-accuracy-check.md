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

## 11. Review — a Claude tölti ki
