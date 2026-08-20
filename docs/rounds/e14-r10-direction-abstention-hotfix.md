# E14-R10 — Azonnali direction abstention hotfix

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 88e08e65`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 10 — az
  „azonnali truthfulness és UX hotfix" blokk (SDD §8: R10–R14) nyitó köre
- **Kör-azonosító:** `E14-R10`
- **Branch:** `<motor>/e14-r10-direction-abstention-hotfix`
- **Előfeltétel:** `E14-R04` merge-elve (a `RecognitionDecision` állapotok) és
  `E14-R08` merge-elve (a küszöb-választás mérőeszköze). **Enélkül a kör nem
  indítható** — a küszöböt tilos kézzel kitalálni.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0362` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/live/engine/dsp/strum_direction_classifier.dart` confidence-létráját
> (ma: `0.8 + 0.05*gap` clamp `0.95` / `0.55` / `0.5` / `0.3`, a 154–163. sorok
> környékén) és a `lib/features/settings/providers/confidence_threshold_provider.dart`-t.
> A §2 ezekre mutat. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/engine/dsp/strum_direction_gate.dart",
  "lib/features/live/engine/dsp/live_pipeline.dart",
  "lib/features/live/model/live_frame.dart",
  "lib/features/practice/data/live_practice_observation_gateway.dart",
  "lib/features/live/public.dart",
  "test/features/live/strum_direction_gate_test.dart",
  "test/features/practice/live_practice_uncertain_event_test.dart",
  "docs/eval/recognition-direction-abstention.md",
  "docs/rounds/e14-r10-direction-abstention-hotfix.md",
]
gate_tests = [
  "test/features/live/strum_direction_gate_test.dart",
  "test/features/practice/live_practice_uncertain_event_test.dart",
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

A felhasználó **ne kapjon magabiztos nyilat bizonytalan pengetésre**. A döntési
réteg (nem a DSP!) kapjon minimum irány-margót és minimum kalibrált
confidence-küszöböt; ezek alatt az esemény `uncertain`, és a UI semleges
pulzust mutat, nem ↓/↑ nyilat. A gyakorlás-pontozás a bizonytalan eseményt
**nem** számolja hibás iránynak.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **E14-R01 release guard:** `UNKNOWN > CONFIDENTLY WRONG` — ez a kör ennek az
  első futásidejű érvényesítése a strum-oldalon.
- **AGENTS.md §9 (DSP-tilalom):** shipping DSP/ML konstans NEM hangolható mért
  A/B és ADR nélkül — ezért a kör **nem** nyúl a
  `strum_direction_classifier.dart` létrájához, hanem FÖLÉ tesz egy kaput.
- **ADR 0271 / Chapter 14 §7.2 (Strum Alpha kapu):** a küszöb a
  coverage/accuracy célból származik, nem érzésből.

## 2. Jelenlegi állapot — mért tények

- `lib/features/live/engine/dsp/strum_direction_classifier.dart` — a
  confidence egy **rögzített létra** (`0.8 + 0.05*gap` … `0.3`), nem kalibrált
  valószínűség. A kör ezt NEM írja át.
- `lib/features/live/model/live_frame.dart` — `double get confidence =>
  latestStrum?.confidence ?? 0;` — egyetlen érték, és az a STRUM-é.
- `lib/features/settings/providers/confidence_threshold_provider.dart` —
  MEGLÉVŐ felhasználói küszöb-beállítás. A SDD kimondja: ez nem írhatja felül a
  biztonsági minimumot.
- `lib/features/practice/data/live_practice_observation_gateway.dart` — a
  gyakorlás innen kapja a strum-eseményeket; ma nincs `uncertain` fogalma.

## 3. Scope

**Benne:** döntési kapu (margó + kalibrált confidence), `uncertain` út a
frame-ben, a felhasználói küszöb alsó korlátja, a gyakorlás-pontozás
semlegesítése, a küszöb származtatásának dokumentálása.

**Nincs benne:** DSP/ML konstans hangolása, modellcsere, új modell-asset,
UI-redesign (az a R13), chord-oldal (az a R11), `ml/**`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/engine/dsp/strum_direction_gate.dart` | új döntési kapu (a DSP FÖLÖTT) |
| `lib/features/live/engine/dsp/live_pipeline.dart` | a kapu bekötése |
| `lib/features/live/model/live_frame.dart` | `uncertain` út a frame-ben |
| `lib/features/practice/data/live_practice_observation_gateway.dart` | bizonytalan ≠ hibás irány |
| `lib/features/live/public.dart` | additív export |
| `test/features/live/strum_direction_gate_test.dart` | küszöb-mátrix |
| `test/features/practice/live_practice_uncertain_event_test.dart` | pontozás-semlegesség |
| `docs/eval/recognition-direction-abstention.md` | a küszöb származtatása |
| `docs/rounds/e14-r10-direction-abstention-hotfix.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten
`lib/features/live/engine/dsp/strum_direction_classifier.dart`,
`lib/features/live/engine/dsp/dsp_config.dart`, `lib/features/live/engine/ml/**`,
`assets/**`, `ml/**`, `docs/rag/chunks/**`, `docs/adr/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0362)

### 5.1 A kapu a DSP FÖLÖTT él

A `StrumDirectionGate` a classifier kimenetét fogadja és döntést ad; a
classifier egyetlen konstansa sem változik. **NEM elfogadható** gyengítés:
„egyszerűbb a létrát átírni".

### 5.2 A küszöb MÉRT, nem választott

A margó- és confidence-küszöb a held-out kalibrációs halmazon optimalizált
érték, a `docs/eval/recognition-direction-abstention.md`-ben a **futtatott
paranccsal és a kapott coverage/accuracy párral** együtt. **NEM elfogadható**:
kerek szám indoklás nélkül.

### 5.3 A user-beállítás nem mehet a biztonsági minimum alá

A `confidenceThresholdProvider` értéke csak SZIGORÍTHAT. A gate a
`max(userThreshold, safetyMinimum)` értékkel dolgozik.

### 5.4 Egy eseményre egy végleges irány

Ha egy eseményre már `confirmed` irány született, ugyanaz az esemény nem
válthat a másik irányra. Az `uncertain` nem „később majd eldől" — a UI
szempontjából végleges semleges állapot.

### 5.5 A bizonytalan esemény nem hibás esemény

A gyakorlás-pontozásban az `uncertain` sem találatnak, sem hibának nem számít;
külön számlálóba megy.

## 6. Acceptance criteria

1. A gate hármas küszöb-cellája a margóra (a `0.150` határ **inkluzív**):
   **0,149 → `uncertain`**, **0,150 → elfogadott**, **0,151 → elfogadott**.
2. A kalibrált confidence hármas cellája ugyanígy, a `docs/eval/…` fájlban
   rögzített értékkel; a teszt ezt az értéket olvassa, nem duplikálja.
3. `uncertain` esetén a frame nem tartalmaz ↓/↑ irányt (a mező null/semleges).
4. `userThreshold < safetyMinimum` esetén a gate a `safetyMinimum`-ot használja
   (teszt: alatta / rajta / fölötte).
5. Egy `confirmed` irány után ugyanarra az eseményre érkező ellentétes javaslat
   nem írja felül (immutábilis esemény).
6. A gyakorlás-gateway `uncertain` eseményre sem `hit`-et, sem `miss`-t nem
   könyvel; a külön számláló nő.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A margó-határ exkluzív (`>`) | 1. pont **0,150** cellája |
| A user-küszöb felülírja a minimumot | 4. pont „alatta" cellája |
| `uncertain` mellett is beírja a legutóbbi irányt | 3. pont |
| A `confirmed` esemény felülírható | 5. pont |
| Az `uncertain` `miss`-ként könyvelődik | 6. pont |
| A küszöb a kódba égetve, a doksi nélkül | 2. pont (a teszt nem találja a forrást) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live test/features/practice
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a `max(userThreshold, safetyMinimum)` ideiglenes
`userThreshold`-ra cserélésével a 4. pont „alatta" cellája **PIROS**,
visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. `StrumDirectionGate` + küszöb-mátrix teszt.
2. A küszöb származtatása és rögzítése a `docs/eval/…`-ban.
3. Bekötés a `live_pipeline.dart`-ba, `uncertain` út a frame-ben.
4. A gyakorlás-gateway semlegesítése + teszt.

## 9. Kockázatok

- **Coverage-esés:** a kapu csökkenti a megjelenített események számát; ez
  SZÁNDÉKOS, de a §10-ben számszerűen jelenteni kell.
- **A DSP átírásának kísértése:** tilos zóna; igény esetén `stopped`.
- **Kettős küszöb-forrás:** a doksi és a kód nem térhet el — a teszt a doksiból
  olvasson.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
