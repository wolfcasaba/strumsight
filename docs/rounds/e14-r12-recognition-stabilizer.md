# E14-R12 — Provisional → confirmed stabilizátor állapotgép

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 88e08e65`)
- **Típus:** Chapter 14, Kör 12 (truthfulness hotfix blokk)
- **Kör-azonosító:** `E14-R12`
- **Branch:** `<motor>/e14-r12-recognition-stabilizer`
- **Előfeltétel:** `E14-R04` merge-elve (döntési állapotok). Az `E14-R08`
  ajánlott a flip-rate méréshez, de nem blokkoló: a kör fixture-ön is mér.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0364` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/live/providers/chord_timeline_provider.dart`
> `ChordTimelineController`-ét — ez hajtja ma a timeline-kártyákat. Eltérésnél
> §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/engine/recognition_stabilizer.dart",
  "lib/features/live/providers/chord_timeline_provider.dart",
  "lib/features/live/providers/live_providers.dart",
  "lib/features/live/public.dart",
  "test/features/live/recognition_stabilizer_test.dart",
  "test/features/live/chord_timeline_churn_test.dart",
  "docs/rounds/e14-r12-recognition-stabilizer.md",
]
gate_tests = [
  "test/features/live/recognition_stabilizer_test.dart",
  "test/features/live/chord_timeline_churn_test.dart",
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

## 1. Cél

A felületen **csak stabil, megerősített változás** jelenjen meg: a jelölt
(`provisional`) akkord csak N frame vagy onset-igazolt evidencia után válik
`confirmed`-dé, a megerősített állapotból pedig csak erős átmenet-evidencia
mozdít ki. A strum-esemény immutábilis. A kör méri a megerősítési késleltetést
és a flip-rate-et.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §4.1–4.2 (mért audit):** a jelenlegi UI minden labelváltást
  kártyává emel — a felismerési zajból „timeline churn" lesz.
- **E14-R10:** ugyanaz az elv a strum-oldalon (egy eseményre egy végleges
  irány); ez a kör az akkord-oldali párja.

## 2. Jelenlegi állapot — mért tények

- `lib/features/live/providers/chord_timeline_provider.dart` — a
  `ChordTimelineController` a `liveFrameProvider`-ből hajtogatja a
  történetet („newest last, capped ring buffer"); nincs stabilizáló réteg.
- `lib/features/live/engine/` — nincs `recognition_stabilizer.dart`; ez a kör
  hozza létre.
- A Free és Guided mód külön profilja ma sehol nem létezik.

## 3. Scope

**Benne:** `RecognitionStabilizer` (Free/Guided profil), akkord provisional →
confirmed logika, strum candidate → accepted/rejected/uncertain, immutábilis
esemény, latency/flip-rate mérőszám, a timeline bekötése.

**Nincs benne:** UI-layout (R13), DSP/ML konstans, új modell, hálózat.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/engine/recognition_stabilizer.dart` | az állapotgép |
| `lib/features/live/providers/chord_timeline_provider.dart` | a stabilizált forrás használata |
| `lib/features/live/providers/live_providers.dart` | a stabilizátor bekötése |
| `lib/features/live/public.dart` | additív export |
| `test/features/live/recognition_stabilizer_test.dart` | állapotgép-mátrix |
| `test/features/live/chord_timeline_churn_test.dart` | churn-mérés |
| `docs/rounds/e14-r12-recognition-stabilizer.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/features/live/engine/dsp/**`,
`lib/features/live/engine/ml/**`, `lib/features/live/screens/**`, `assets/**`,
`ml/**`, `docs/adr/**`, `docs/rag/chunks/**`, `.github/workflows/**`,
`tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0364)

### 5.1 Az esemény immutábilis

Egy `confirmed` strum-esemény iránya soha nem változik. **NEM elfogadható**:
„utólagos korrekció jobb élményt ad".

### 5.2 A megerősítés evidencia-alapú, nem időzítő

A `confirmed` átmenet feltétele N egybehangzó frame VAGY onset-igazolt
evidencia — nem puszta `Future.delayed`.

### 5.3 A profil paraméter, nem elágazás

A Free és Guided profil ugyanazt az állapotgépet paraméterezi (küszöbök,
N), nem két külön kódág.

### 5.4 Tartott akkord nem generál új kártyát

Változatlan `confirmed` akkord ismételt megjelenése nem hoz létre új
timeline-elemet.

### 5.5 A mérőszám a kimenet része

A stabilizátor kiadja a `confirmationLatency` és `flipRate` értékeket, hogy a
release gate (R09) mérhesse — nem csak logsor.

## 6. Acceptance criteria

1. Megerősítési küszöb hármas cellája (`N = 3`, a határ **inkluzív**): a
   küszöb **alatt** (2 egybehangzó frame) → `provisional`, pontosan **rajta**
   (3 frame) → `confirmed` (a határ ide tartozik), a küszöb **fölött**
   (4 frame) → `confirmed`.
2. `confirmed` állapotból gyenge ellenevidencia nem vált ki átmenetet; erős
   igen (a teszt mindkét irányt méri).
3. 10 frame-en át tartott azonos akkord **pontosan egy** timeline-kártyát ad.
4. Egy `confirmed` strum-eseményre érkező ellentétes javaslat nem írja felül.
5. A Free és Guided profil ugyanazon a bemeneten mérhetően eltérő
   latency/flip-rate párt ad, és mindkettő a kimenet része.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A küszöb exkluzív (`> N`) | 1. pont **3 → confirmed** cellája |
| Időzítő-alapú megerősítés | 2. pont erős/gyenge evidencia cellája |
| A timeline minden frame-re kártyát ad | 3. pont |
| Az esemény felülírható | 4. pont |
| A profil nem paraméter, hanem másolt kódág | 5. pont (a két profil azonos értéket ad) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: az „N egybehangzó frame" feltétel ideiglenes 1-re
állításával a 3. pont **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Állapotgép + mátrix-teszt (profilok paraméterként).
2. Mérőszámok kivezetése.
3. Timeline bekötése + churn-teszt.

## 9. Kockázatok

- **Késleltetés-növekedés:** a megerősítés természetéből adódik; a §10-ben
  számszerűen jelenteni kell (a release gate küszöbe a R09-é).
- **Kettős igazság:** a timeline nem olvashat a stabilizátor MELLETT nyers
  frame-et — egyetlen forrás.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
