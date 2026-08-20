# E14-R07 — Annotációs szerződés, validator és annotátor-egyetértés

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ b0979855`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 7
- **Kör-azonosító:** `E14-R07`
- **Branch:** `<motor>/e14-r07-annotation-contract-and-agreement`
- **Előfeltétel:** `E14-R06` merge-elve (a csomagformátum, amit annotálunk).
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0359` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `evaluation/analysis/manifest_schema.json`-t és a
> `lib/features/audio_analysis/data/evaluation/evaluation_manifest_parser.dart`-t
> — ez a kör UGYANAZT a mintát viszi tovább a felismerési oldalra, nem újat
> talál ki. Ellenőrizd az `E14-R06` `LabCapturePackage` mezőneveit is.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "evaluation/recognition/annotation_schema.json",
  "evaluation/recognition/fixtures/annotation_pair.json",
  "lib/features/live/domain/evaluation/recognition_annotation.dart",
  "lib/features/live/data/evaluation/recognition_annotation_parser.dart",
  "tool/recognition_annotate.dart",
  "test/features/live/evaluation/recognition_annotation_test.dart",
  "docs/eval/recognition-annotation.md",
  "docs/rounds/e14-r07-annotation-contract-and-agreement.md",
]
gate_tests = [
  "test/features/live/evaluation/recognition_annotation_test.dart",
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

A SDD Kör 07 grafikus annotátort ír (waveform, spectrogram, húzható onset,
undo/redo). Ez a kör a **szerződést, a validatort és az egyetértés-mérést**
építi meg CLI-ként; a grafikus szerkesztő NINCS benne. Mért ok: a repónak
nincs desktop/web futtatási célja, és a gate egy GUI-t nem tud vezetni —
a bizonyítható rész (séma, átfedés-validáció, provenance, két-annotátoros
riport) viszont közvetlenül mérhető. A szerkesztő külön kör (`E14-R07b`),
és a jelen kör acceptance-e nem hivatkozhat rá.

## 1. Cél

Az annotáció legyen **verziózott, validált és visszakövethető**: egy onset-,
irány- és akkord-annotációs séma, hozzá parser és `tool/`-CLI, amely elutasítja
az érvénytelen/átfedő eseményeket, és két annotátor eltéréséről gépi riportot ad.
Automatikus címke önmagában NEM ground truth — a séma ezt a provenance mezővel
teszi mérhetővé.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **ADR 0249 / E06-R29:** `EvaluationManifestParser` + `manifest_schema.json` —
  típusos hibák (`InvalidSchemaVersion`), CI-fixture, külső valós korpusz. Ez a
  kör ugyanezt a hármast építi a felismerési annotációra.
- **E14-R01 release guard:** a „nem validált állítás visszavonva" szabály — az
  annotációnál ez a `provenance: auto|human|reviewed` mező.

## 2. Jelenlegi állapot — mért tények

- `evaluation/recognition/` — az `E14-R02` hozza létre (baseline manifest); az
  annotációs séma ide kerül, mellé.
- `lib/features/live/domain/`, `lib/features/live/data/` — **nem léteznek**; ez
  a kör hozza létre őket, az `audio_analysis` mintájára.
- `tool/audio_analysis_evaluate.dart` — a CLI-forma mintája (fixture-default,
  `--manifest` kapcsoló, determinisztikus JSON a stdout-ra).

## 3. Scope

**Benne:** annotációs séma (JSON Schema), Flutter-független modell + parser,
átfedés/érvényesség validáció, provenance, két-annotátoros egyetértés-riport,
CLI, CI-fixture, rövid doksi.

**Nincs benne:** GUI, hangfájl-írás/módosítás, modellhívás, DSP, `ml/**`,
korpusz-adat a repóban.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `evaluation/recognition/annotation_schema.json` | a séma maga |
| `evaluation/recognition/fixtures/annotation_pair.json` | két annotátoros CI-fixture |
| `lib/features/live/domain/evaluation/recognition_annotation.dart` | Flutter-független modell |
| `lib/features/live/data/evaluation/recognition_annotation_parser.dart` | típusos parser + validáció |
| `tool/recognition_annotate.dart` | validate + agreement CLI |
| `test/features/live/evaluation/recognition_annotation_test.dart` | séma, validáció, egyetértés |
| `docs/eval/recognition-annotation.md` | használat, provenance-szabály |
| `docs/rounds/e14-r07-annotation-contract-and-agreement.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/features/live/engine/**`,
`evaluation/analysis/**`, `assets/**`, `ml/**`, `docs/adr/**`,
`docs/rag/chunks/**`, `.github/workflows/**`, `tools/round-gate.sh`. Új
kereszt-feature import felvétele a `tool/check_architecture.dart` listájába
TILOS — ha kellene, `stopped`.

## 5. Kötött architekturális döntések (ADR 0359)

### 5.1 A nyers hang érintetlen

A CLI és a parser CSAK annotációt olvas/ír; WAV-ot soha nem módosít, nem is
nyit írásra. **NEM elfogadható**: „normalizáljuk a WAV-ot a konzisztenciáért".

### 5.2 Provenance kötelező, és nem default `human`

Minden esemény `provenance` mezője kötelező, felvehető értékei
`auto | human | reviewed`; hiányzó mező **típusos hiba**. Az automatikus címke
sosem lép elő `human`-ná parser-oldalon.

### 5.3 Átfedés és érvénytelenség: hiba, nem javítás

Két, ugyanarra a sávra eső, átfedő esemény esetén a parser hibát ad, **nem**
old fel csendben (nem vág, nem összevon). A hiba tartalmazza a két esemény
indexét.

### 5.4 Egyetértés: mért szám, nem becslés

A riport párosított eseményekre onset-toleranciával számol egyetértést, és
külön adja az irány- és akkord-címke egyezését. A tolerancia paraméter, nem
beégetett konstans.

### 5.5 Determinisztikus kimenet

Ugyanaz a bemenet bitre ugyanazt a riportot adja (kanonikus kulcsrend, nincs
`DateTime.now()` a riport belsejében).

## 6. Acceptance criteria

1. A séma-verzió eltérése típusos hibát ad (nem `null`, nem default).
2. Átfedő eseménypár elutasítva, a hibaüzenet mindkét indexet tartalmazza.
3. Hiányzó `provenance` → típusos hiba; `auto` érték nem konvertálódik.
4. A CLI a fixture-ön determinisztikus JSON riportot ad: kétszeri futás bájtra
   azonos.
5. Az egyetértés-riport a fixture-re kézzel ellenőrzött értéket ad: a két
   annotátor 10 eseményéből 8 párosítható 50 ms-on belül, ebből 7 egyezik
   irányban → `directionAgreement = 0.875`.
6. Az onset-tolerancia (50 ms) határa **inkluzív**, és mind a három cellát
   mérni kell: a küszöb **alatt** (49 ms eltérés) → párosít; **rajta**
   (pontosan 50 ms) → párosít, mert a határ az elfogadó oldalhoz tartozik;
   **fölött** (51 ms) → nem párosít.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A parser az átfedést csendben összevonja | 2. pont index-cellája |
| Hiányzó provenance → `human` default | 3. pont típusos-hiba cellája |
| A riportba bekerül a futás időbélyege | 4. pont bájtra-azonos cellája |
| A párosítás exkluzív határt használ (`<`) | 6. pont **50 ms** cellája |
| Az egyetértés az összes eseményre oszt, nem a párosítottakra | 5. pont `0.875` cellája |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/evaluation
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a párosítás határának `<=` → `<` cserével a 6. pont
**50 ms** cellája **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Séma + fixture.
2. Modell + parser (séma-verzió, provenance, átfedés).
3. Egyetértés-számítás.
4. CLI a meglévő `tool/audio_analysis_evaluate.dart` alakja szerint.
5. Doksi.

## 9. Kockázatok

- **A GUI-igény visszaszivárgása:** a §0.0 tiltja; felület-kérés → `stopped`.
- **Fixture-túlillesztés:** a fixture-nek tartalmaznia kell nem párosítható
  eseményt is, különben a párosító hibás implementációja is zöld marad.
- **Kereszt-feature import:** az `audio_analysis` evaluation kódját NEM
  importáljuk; a minta másolható, a függés nem.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
