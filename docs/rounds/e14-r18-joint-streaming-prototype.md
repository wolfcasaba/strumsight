# E14-R18 — Streaming joint onset + direction prototípus

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 6371aa3`)
- **Típus:** Chapter 14, Kör 18 (strum recovery blokk) — **kutatási kör**
- **Kör-azonosító:** `E14-R18`
- **Branch:** `<motor>/e14-r18-joint-streaming-prototype`
- **Előfeltétel:** `E14-R08` (grouped harness) és `E14-R17` (referencia-audit,
  hogy tudjuk, mi vehető át és mi nem) merge-elve.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0370` — **a Claude írja meg (go/no-go), a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az `ml/honest_eval.py`
> fejlécét (három-utas split, LOGO CV, cluster-bootstrap, kalibráció) — a
> prototípus mérése ezt a szigort örökli. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "ml/joint_prototype/README.md",
  "ml/joint_prototype/train_prototype.py",
  "ml/joint_prototype/evaluate_prototype.py",
  "evaluation/recognition/joint_io_schema.json",
  "evaluation/recognition/fixtures/joint_io_sample.json",
  "test/tooling/joint_io_schema_test.dart",
  "docs/eval/joint-strum-prototype.md",
  "docs/rounds/e14-r18-joint-streaming-prototype.md",
]
gate_tests = [
  "test/tooling/joint_io_schema_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`. Hiányzó
tanító-környezet → `blocked`.

## 1. Cél

Offline prototípus arról, hogy egy **joint** fej (külön down- és up-onset
regresszió + no-event confidence) jobb-e a mai kétlépcsős (onset → irány)
útnál, ahol az onset-hiba továbbterjed. A prototípus **nem kerül a termékbe**
ebben a körben; a kimenete mért összehasonlítás és verziózott IO-séma.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §4.4/§5.1:** a kétlépcsős lánc hibaterjedése MÉRT; a joint
  modell természetesen támogatja az abstentiont.
- **`ml/honest_eval.py`:** a repó saját mérési szigora (három-utas split, LOGO,
  bootstrap CI) — a prototípus ugyanezt használja, nem lazábbat.

## 2. Jelenlegi állapot — mért tények

- `lib/features/live/engine/dsp/superflux_onset_detector.dart` →
  `strum_direction_classifier.dart` — a mai lánc KÉT lépcső.
- `ml/` — a jelenlegi CRNN tanító- és export-eszközei megvannak
  (`klangio.py`, `export_live_weights.py`), joint fej nincs.
- `evaluation/recognition/` — az `E14-R02` hozza létre; az IO-séma ide kerül.

## 3. Scope

**Benne:** offline prototípus (16 kHz log-mel frontend), down/up onset
regresszió + no-event fej, causal vagy kontrollált lookahead, összehasonlítás a
legacy lánccal, verziózott IO-séma + Dart-oldali séma-őr, report.

**Nincs benne:** mobil bekötés, `lib/**` módosítás, súly-export a termékbe,
DSP-konstans, production flag.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `ml/joint_prototype/README.md` | környezet és futtatás |
| `ml/joint_prototype/train_prototype.py` | prototípus tanítás |
| `ml/joint_prototype/evaluate_prototype.py` | mérés a grouped splittel |
| `evaluation/recognition/joint_io_schema.json` | verziózott IO-szerződés |
| `evaluation/recognition/fixtures/joint_io_sample.json` | CI-fixture |
| `test/tooling/joint_io_schema_test.dart` | séma-őr |
| `docs/eval/joint-strum-prototype.md` | report + go/no-go javaslat |
| `docs/rounds/e14-r18-joint-streaming-prototype.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/**`, `assets/**`, `ml/` a
`joint_prototype/` alkönyvtáron kívül, `docs/adr/**`, `docs/rag/chunks/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0370)

### 5.1 Csak causal vagy kontrollált lookahead

Mobil jelöltként kizárólag olyan architektúra értékelhető, amelynek a
lookahead-je számszerűen korlátozott és a reportban szerepel. **NEM
elfogadható**: „offline jobb, majd a mobilon lesz valami".

### 5.2 Nincs player-leakage

A train/eval split játékos szerint csoportosított; a leakage-detektor
(E14-R08) futása a report kötelező része.

### 5.3 Az IO-séma verziózott

A modell be- és kimenete sémában rögzített, `schemaVersion`-nel; ismeretlen
verzió típusos hiba a Dart-oldali őrben is.

### 5.4 A go/no-go az Alpha kapuhoz kötött

A javaslat csak akkor „go", ha a mért érték eléri a Chapter 14 §7.2 Strum
Alpha kapuját a grouped spliten. **NEM elfogadható**: „majdnem elérte".

### 5.5 A prototípus nem szállítható artefaktum

Súly nem kerül `assets/`-be ebben a körben.

## 6. Acceptance criteria

1. A prototípus futtatható egyetlen paranccsal, és a splitet a manifestből
   veszi (nem beégetve).
2. A report tartalmazza az end-to-end down/up F1-et és a latency-t, a legacy
   kétlépcsős lánccal EGY táblában, azonos korpusz-hash-sel.
3. A lookahead értéke számszerűen szerepel a reportban és a sémában.
4. A Dart-oldali séma-őr ismeretlen `schemaVersion`-re típusos hibát ad
   (fixture-rel mérve).
5. A go/no-go a Chapter 14 §7.2 Alpha küszöbhöz méri magát: a hármas cella a
   küszöb **alatt** → no-go, pontosan **rajta** → go (a határ inkluzív), a
   küszöb **fölött** → go.
6. Player-leakage esetén a futás hibával áll meg, nem ad reportot.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A split beégetve | 1. pont |
| A legacy összehasonlítás külön korpuszon | 2. pont hash-cellája |
| A lookahead nincs jelentve | 3. pont |
| Ismeretlen séma-verzió → default | 4. pont |
| A küszöb exkluzív („majdnem elérte" → go) | 5. pont „pontosan rajta" cellája |
| A leakage csak figyelmeztetés | 6. pont |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). A Python oldal külön, önálló parancsként:

```bash
python3 -m pytest ml -q
```

`&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a séma-verzió ellenőrzésének ideiglenes kivételével a
4. pont **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. IO-séma + fixture + Dart-őr (RED-del kezdve).
2. Prototípus tanítás/mérés script.
3. Összehasonlító report a legacy lánccal.
4. Go/no-go javaslat (a döntés ADR-je a Claude-é).

## 9. Kockázatok

- **Tanító-környezet hiánya:** `blocked` a helyes jelzés.
- **Túlillesztés a fixture-re:** a mérés grouped spliten megy, különben
  értelmetlen.
- **Scope-csúszás a termék felé:** az 5.5 és a tilos zóna védi.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
