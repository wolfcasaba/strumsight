# E14-R14 — Automatikus Audio Setup és Accuracy Check

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 88e08e65`)
- **Típus:** Chapter 14, Kör 14 (a truthfulness hotfix blokk záró köre)
- **Kör-azonosító:** `E14-R14`
- **Branch:** `<motor>/e14-r14-audio-setup-and-accuracy-check`
- **Előfeltétel:** `E14-R05` (signal quality analyzer) és `E14-R11` merge-elve.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0366` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

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

## 0.0 Kötött scope-szűkítés a SDD-hez képest (drift, KÖTELEZŐ így)

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

**Nincs benne:** képernyő (§0.0), modellhangolás, DSP-konstans, hálózat,
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

## 5. Kötött architekturális döntések (ADR 0366)

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
tools/round-gate.sh test/features/onboarding
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
- **Scope-csúszás a UI felé:** a §0.0 tiltja.
- **Profil-alapú „kalibrálás" kísértése:** az 5.1 tiltja; igény esetén `stopped`.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
