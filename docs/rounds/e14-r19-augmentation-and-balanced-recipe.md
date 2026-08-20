# E14-R19 — Adataugmentáció és kiegyensúlyozott training recept

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 6371aa3`)
- **Típus:** Chapter 14, Kör 19 (strum recovery blokk) — **kutatási kör**
- **Kör-azonosító:** `E14-R19`
- **Branch:** `<motor>/e14-r19-augmentation-and-balanced-recipe`
- **Előfeltétel:** `E14-R08` (grouped harness) és `E14-R15` (hard-negative
  taxonómia) merge-elve.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0371` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az `ml/augment.py`
> fejlécét — a PCM-szintű augmentáció (r173, RAG chunk 018) MÁR LÉTEZIK, pure
> NumPy. Ez a kör BŐVÍT és ablationnel bizonyít, nem újraír. Nézd meg az
> `ml/synth.py` és `ml/prepare_dataset.py` szerepét is. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "ml/augment.py",
  "ml/augmentation_manifest.json",
  "ml/test_augmentation_labels.py",
  "evaluation/recognition/fixtures/augmentation_manifest_sample.json",
  "test/tooling/augmentation_manifest_test.dart",
  "docs/eval/augmentation-ablation.md",
  "docs/rounds/e14-r19-augmentation-and-balanced-recipe.md",
]
gate_tests = [
  "test/tooling/augmentation_manifest_test.dart",
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

Az augmentáció legyen **seedelt, manifestelt, kikapcsolható és ablationnel
bizonyított**: pitch shift címke-transzponálással, szoba-IR, gain, EQ,
kompresszió, eszköz-válasz, SNR, forgalom/nappali zaj, fret/pick/tap burst —
és a down/up/no-strum, illetve az akkord-osztályok kiegyensúlyozása. Az
elfogadás feltétele, hogy legalább egy **unseen-player** vagy
**unseen-device** split javuljon, és romló subgroup esetén NINCS automatikus
elfogadás.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **`ml/augment.py` (r173):** a PCM-szintű augmentáció alapja megvan; a
  fejléc kimondja, miért PCM-en és nem spektrogramon történik.
- **`ml/negatives.py` (r174):** a no-strum osztály és a hard negatívok — a
  kiegyensúlyozás ezekre is vonatkozik.
- **Chapter 14 §9/4:** tilos egyetlen játékosra vagy ugyanarra a test setre
  hangolni.

## 2. Jelenlegi állapot — mért tények

- `ml/augment.py` — létező, pure-NumPy PCM-augmentáció; nincs mellette
  **manifest** (mi futott, milyen seeddel), és nincs **ablation-report**.
- `ml/synth.py`, `ml/prepare_dataset.py`, `ml/negatives.py` — a tanító adat-út
  többi darabja; a kör ezeket NEM írja át.
- `ml/test_pipeline.py` — a meglévő Python-teszt belépési pont.

## 3. Scope

**Benne:** az `augment.py` bővítése a hiányzó transzformációkkal, seed- és
manifest-szerződés, kikapcsolhatóság, címke-transzponálás helyessége
(pitch shift), osztály-kiegyensúlyozás, ablation-report, Dart-oldali
manifest-őr.

**Nincs benne:** modelltanítás elfogadása (az az R20), `lib/**`, `assets/**`,
DSP-konstans, a szállított súlyok cseréje.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `ml/augment.py` | a meglévő augmentáció bővítése |
| `ml/augmentation_manifest.json` | mi futott, milyen seeddel, milyen aránnyal |
| `ml/test_augmentation_labels.py` | címke-eltolódás és seed-determinizmus |
| `evaluation/recognition/fixtures/augmentation_manifest_sample.json` | CI-fixture |
| `test/tooling/augmentation_manifest_test.dart` | manifest-séma őr |
| `docs/eval/augmentation-ablation.md` | ablation-report |
| `docs/rounds/e14-r19-augmentation-and-balanced-recipe.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `ml/klangio.py`, `ml/honest_eval.py`,
`ml/export_*`, `assets/**`, `lib/**`, `docs/adr/**`, `docs/rag/chunks/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0371)

### 5.1 A pitch shift a CÍMKÉT is transzponálja

Félhang-eltolásnál az akkord-címke együtt mozog. **NEM elfogadható**: „a
direction-fejnek úgyis mindegy" — a manifest egy adatkészletet ír le, nem egy
fejet.

### 5.2 Minden augmentáció seedelt és kikapcsolható

Seed nélküli véletlen tilos; minden transzformációnak van `enabled` kapcsolója,
és a manifest rögzíti a ténylegesen futott halmazt.

### 5.3 Az ablation kötelező

Egy transzformáció csak akkor marad a receptben, ha az ablation-report szerint
legalább egy unseen-player VAGY unseen-device split javul, és egyik sem romlik
a jelentett hibahatáron túl.

### 5.4 Romló subgroup → nincs automatikus elfogadás

A report romlást jelző sorát a döntés (ADR) tárgyalja; az implementer nem
fogadhat el csendben.

### 5.5 A tanító-oldal határa

A kör az adat-utat érinti; a modell-architektúra és a szállított súlyok
változatlanok.

## 6. Acceptance criteria

1. A `ml/test_augmentation_labels.py` bizonyítja, hogy ±N félhang pitch shift
   után a címke pontosan N félhanggal tolódik (a mátrix ±1, ±3, ±6 esetre fut).
2. A pitch-shift tartomány határa **inkluzív**: a hármas cella a ±6-ra — a
   határ **alatt** (±5) elfogadott, pontosan **rajta** (±6) elfogadott (a
   határ ide tartozik), a határ **fölött** (±7) a validátor hibát ad.
3. Ugyanaz a seed bitre ugyanazt a kimenetet adja; eltérő seed eltérőt
   (mindkettő mérve).
4. Minden transzformáció kikapcsolható, és kikapcsolt állapotban a kimenet
   bitre azonos a nyers bemenettel.
5. A manifest tartalmazza a seedet, a transzformáció-listát és az
   osztály-arányokat; hiányzó mező → típusos hiba a Dart-őrben is.
6. Az ablation-report minden transzformációhoz ad legalább egy unseen-player
   VAGY unseen-device split-eredményt; hiányzó mérés → „nem mért", nem 0.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A pitch shift nem mozgatja a címkét | 1. pont |
| A tartomány exkluzív felső határral | 2. pont „pontosan rajta" cellája |
| Seed nélküli véletlen | 3. pont determinizmus-cellája |
| A kikapcsolt transzformáció mégis módosít | 4. pont |
| A manifestből hiányzik a seed | 5. pont |
| Hiányzó ablation-mérés → 0 | 6. pont |

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

A §10-ben dokumentáld: a címke-transzponálás ideiglenes kivételével az
1. pont **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Manifest-séma + Dart-őr + fixture (RED-del kezdve).
2. Címke-transzponálás teszt (RED), majd a javítás/bővítés.
3. A hiányzó transzformációk, seedelve és kapcsolhatóan.
4. Osztály-kiegyensúlyozás + ablation-report.

## 9. Kockázatok

- **Az `augment.py` átírásának kísértése:** a fájl a listán van, de a bővítés
  additív; a meglévő transzformációk viselkedése nem változhat (regressziós
  teszt kötelező).
- **Tanító-környezet hiánya:** ablation nélkül a kör `blocked`, nem „részleges".
- **Osztály-arány torzítás:** a kiegyensúlyozás nem törölhet valós adatot,
  csak súlyoz/mintavételez — a manifest ezt rögzíti.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
