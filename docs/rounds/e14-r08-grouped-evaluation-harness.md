# E14-R08 — Csoportosított evaluation harness és leakage-védelem

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ b0979855`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 8
- **Kör-azonosító:** `E14-R08`
- **Branch:** `<motor>/e14-r08-grouped-evaluation-harness`
- **Előfeltétel:** `E14-R02` (baseline manifest) és `E14-R07` (annotációs
  szerződés) merge-elve — a harness ezek formátumát olvassa.
- **Brief szerzője:** Claude (Opus 5)
- **Kiosztott ADR:** `0509` — **a Claude írta meg a pre-flightban** (`docs/adr/0509-grouped-recognition-evaluation-and-leakage-protection.md`); a `docs/adr/` az implementer TILOS zónája.
- **Visszakeresett előzmény (ADR 0312):** `lessons/L269`, `lessons/L173`,
  `lessons/L549`, `lessons/L577`, `adr/0249`, `adr/0359` — lásd §0.0 és §1.1.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az `E14-R07`
> annotációs sémáját és a `ml/honest_eval.py` fejlécét. Utóbbi a TANÍTÓ oldal
> saját mérése (leave-one-guitarist-out, bootstrap, kalibráció) — ez a kör a
> SZÁLLÍTOTT felismerési útra épít Dart-oldali harness-t, és NEM írja át a
> Python-oldalt. Eltérésnél §0.0 revízió.

## 0.0 Pre-flight revízió (orchestrátor, 2026-09-04, `main @ 62e0dce6`)

A brief 2026-08-20-án készült; az alábbi pontokat a pre-flight MÉRÉSE
javította. A revízió az orchestrátor saját hatásköre (ADR 0087 §2) — a
lista-tágítás nem: az `allowed_paths` változatlan.

**R1 — Az ADR-szám `0360` → `0509`.** MÉRVE: `docs/adr/0360-*.md` nem létezik
(`ls docs/adr | grep ^0360` → 0 találat), a fán a legmagasabb `0505`, és a
foglaló (`tools/round-slots.py reserve-adr --round E14-R08`) a `0509`-et adta.
A §5 döntései ezért az **ADR 0509**-re hivatkoznak. Az ADR már meg van írva és
commitolva — az implementer NEM nyúl a `docs/adr/`-hoz.

**R2 — S12 (brief-lint, strict): a §7 gate-parancs nem tükrözte a
`gate_tests` listát.** A `gate_tests` két konkrét fájlt sorol, a §7 viszont
csak a könyvtárat adta át. A §7 parancsa javítva: mindkét útvonal külön
argumentumként szerepel. Indok: a metaadatot a scope-audit és a CI-terv
olvassa, a kaput viszont a PARANCSSOR futtatja — a kettő szétcsúszása néma.

**R3 — Acceptance 4. pont: „a briefben rögzített szám" teljesíthetetlen volt.**
A brief semmilyen számot nem rögzít, és nem is rögzíthet: a fixture ebben a
körben keletkezik (§8/1.). Ezért az elvárás átfogalmazva — a bizonyíték a
**kézi számítás**, nem egy brief-beli literál. Részletek a javított 4. pontban.

**R4 — L269: a párosítás maximális kardinalitású (ADR 0509 D5).** A repó két
meglévő párosítója (`evaluation_runner.dart:227`,
`recognition_annotation.dart:284`) Kuhn-féle maximális párosítást futtat, mert
a mohó „legközelebbi szabad pár" mérten NEM maximalizál (L269, E06-R29
BLOCKER: várt `50, 90` / detektált `0, 55`, 50 ms → mohó 1 TP, maximális 2 TP).
Új acceptance-cella (8. pont) méri.

**R5 — L173: az ECE/Brier/latencia/false-event hiba-metrika (ADR 0509 D4).**
Egy „magasabb = jobb" sablonból konkretizált összehasonlítás ezeken csendben
megfordítja a döntést. Az irány a report-ban típusban van. Új acceptance-cella
(9. pont) méri.

**R6 — S5-előzés: típusnév-ütközés.** MÉRVE: `OnsetMetrics` **FOGLALT**
(`tool/benchmarks/real_audio_dsp_baseline.dart:30`), tehát nem használható. A
`RecognitionSplit*`, `SplitStrategy`, `LeakageDetector`, `LeakageViolation`,
`RecognitionMetrics*`, `GroupKey`, `RecognitionCase` nevekre nulla találat a
`lib/`, `tool/`, `test/` fában — ezek szabadok.

**R7 — Nincs kereszt-feature import (ADR 0509 D8).** A
`tool/check_architecture.dart:774` szerint kereszt-feature import csak
`public.dart` barrelt célozhat, és az `audio_analysis` barrel NINCS az
`allowed_paths`-on. Az `audio_analysis` evaluation kódját tehát **importálni
tilos** — a minta másolható (ADR 0359 D6 precedens), a függés nem. A
`lib/features/live/public.dart` sem módosul (nem generált barrel, és ezek a
típusok nem publikus szerződés; az E14-R07 merge-elt fájllistája ugyanezt
mutatja).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/domain/evaluation/recognition_split.dart",
  "lib/features/live/domain/evaluation/recognition_metrics.dart",
  "lib/features/live/data/evaluation/recognition_evaluation_runner.dart",
  "tool/recognition_evaluate.dart",
  "evaluation/recognition/fixtures/ci_manifest.json",
  "test/features/live/evaluation/recognition_split_test.dart",
  "test/features/live/evaluation/recognition_metrics_test.dart",
  "docs/rounds/e14-r08-grouped-evaluation-harness.md",
]
gate_tests = [
  "test/features/live/evaluation/recognition_split_test.dart",
  "test/features/live/evaluation/recognition_metrics_test.dart",
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

A felismerési mérés ne egyetlen accuracy-szám legyen, és ne szivárogjon:
ugyanaz a játékos, telefon vagy gitár ne szerepelhessen egyszerre a tanító és a
kiértékelő oldalon. A kör csoportosított split-stratégiákat, leakage-detektort
és a Chapter 14 §7 által kért metrika-készletet ad, kézzel ellenőrzött
fixture-értékekkel.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **ADR 0249 / E06-R29:** a CI kis, szintetikus fixture-ön fut, a valós korpusz
  külső, kézi futtatás — ez a kör ugyanezt a kettősséget örökli.
- **GOV-06b / E99-R05 (`docs/eval/real-audio-dsp-baseline.md`):** a visszavont
  BPM-mérce mért tanulsága, hogy a metrika definíciója maga is bizonyítandó —
  ezért itt minden metrikához fixture-en kézzel ellenőrzött érték tartozik.

## 2. Jelenlegi állapot — mért tények

- `ml/honest_eval.py` — a TANÍTÓ oldal mérése: three-way split, LOGO CV,
  cluster-bootstrap, kalibráció/ECE. Dart-oldali megfelelője **nincs**.
- `tool/audio_analysis_evaluate.dart` + `evaluation/analysis/` — a repó
  bevált harness-alakja (fixture-default, `--manifest`, determinisztikus JSON).
- `lib/features/live/domain/evaluation/` — az `E14-R07` hozza létre; ez a kör
  bővíti.
- Felismerési oldali split/leakage kód a repóban **nincs**.

## 3. Scope

**Benne:** `leave-one-player-out`, `leave-one-device-out`,
`leave-one-guitar-out`, `room-holdout` split; leakage-detektor; onset P/R/F1
25/50/100 ms; irány-osztály F1; any-strum F1; accepted accuracy + coverage;
false visible event/min; latencia p50/p95; ECE; Brier; akkord-metrikák
(weighted accuracy, macro-F1, no-chord F1, unknown false-accept); CLI; fixture.

**Nincs benne:** modellcsere, küszöbhangolás, `ml/**` módosítás, valós korpusz
a repóban, dashboard/HTML (az `E14-R09` köre), UI.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/domain/evaluation/recognition_split.dart` | split-stratégiák + leakage-detektor |
| `lib/features/live/domain/evaluation/recognition_metrics.dart` | metrika-készlet, Flutter-független |
| `lib/features/live/data/evaluation/recognition_evaluation_runner.dart` | manifest → report futtató |
| `tool/recognition_evaluate.dart` | CLI a meglévő harness alakja szerint |
| `evaluation/recognition/fixtures/ci_manifest.json` | kicsi, szintetikus CI-fixture |
| `test/features/live/evaluation/recognition_split_test.dart` | split + leakage mátrix |
| `test/features/live/evaluation/recognition_metrics_test.dart` | kézzel ellenőrzött metrika-értékek |
| `docs/rounds/e14-r08-grouped-evaluation-harness.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `ml/**`, `lib/features/live/engine/**`,
`assets/**`, `docs/adr/**`, `docs/rag/chunks/**`, `.github/workflows/**`,
`tools/round-gate.sh`, és minden shipping DSP/ML konstans (AGENTS.md §9).

## 5. Kötött architekturális döntések (ADR 0509)

### 5.1 A leakage-detektor fail-closed

Ha ugyanaz a csoportkulcs (player/device/guitar/room) két splitben előfordul, a
futtató **hibát ad és megáll** — nem figyelmeztet, nem javít. **NEM elfogadható**
gyengítés: „warning + folytatás", vagy a duplikált csoport csendes eldobása.

### 5.2 Hiányzó csoportkulcs = hiba

Ha egy felvételhez nincs player/device/guitar/room mező, az adott split
stratégia típusos hibát ad. Az `unknown` nem csoportkulcs.

### 5.3 A metrika definíciója a reportban utazik

Minden metrika mellé kerül a definíciója (tolerancia, párosítási szabály,
számláló/nevező), hogy a szám később is olvasható legyen — a visszavont
BPM-mérce (GOV-06b) tanulsága.

### 5.4 Determinisztikus report

Ugyanaz a manifest bitre ugyanazt a JSON-t adja; a splitek sorrendje a
csoportkulcs szerint rendezett, nem hash-sorrend.

### 5.5 A CI fixture kicsi és szintetikus

A CI-fixture nem tartalmaz valós felvételt; a valós korpusz külső manifesttel,
kézi futtatással mérhető (`--manifest`).

### 5.6 A párosítás maximális kardinalitású, nem mohó (ADR 0509 D5)

Az onset- és akkord-párosítás Kuhn-féle **maximális kardinalitású**,
egy-az-egyhez párosítás, determinisztikus élsorrenddel (legkisebb eltérés
először, index-döntetlennel). A lokálisan legközelebbi mohó párosítás **NEM
elfogadható**: mérten alulbecsli a TP-t (L269). A minta a fában két helyen él
(`evaluation_runner.dart:227`, `recognition_annotation.dart:284`) — másold, ne
importáld (§5.8).

### 5.7 Az irány a metrika része: `higherIsBetter` (ADR 0509 D4)

Minden metrika kimondja a report-ban, melyik irány a jobb. **Magasabb = jobb:**
onset/irány/any-strum/akkord F1, accepted accuracy, coverage. **Alacsonyabb =
jobb:** ECE, Brier, false visible event/min, latencia p50/p95. Egy „magasabb =
jobb" alapfeltevés a hiba-metrikákon csendben megfordítja a döntést (L173).

### 5.8 Nincs kereszt-feature import, és a típusnevek saját nevek (ADR 0509 D8)

Az `audio_analysis` evaluation kódját **importálni tilos**
(`tool/check_architecture.dart:774`: kereszt-feature import csak `public.dart`
barrelt célozhat, és az nincs az `allowed_paths`-on). Az `OnsetMetrics` név
FOGLALT (`tool/benchmarks/real_audio_dsp_baseline.dart:30`) — használj
`Recognition…` előtagú, ütközésmentes neveket. A `lib/features/live/public.dart`
nem módosul.

### 5.9 Az ECE binjei egyenlő SZÉLESSÉGŰEK (ADR 0509 D7)

`binCount` darab, `[i/binCount, (i+1)/binCount)` félig nyitott bin, az utolsó
zárt — a repó meglévő mintája (`calibration_fitter.dart:132-141`). Egyenlő
darabszámú (kvantilis) binelés **NEM** elfogadható: ugyanarra az adatra más
ECE-t ad.

## 6. Acceptance criteria

1. Mind a négy split-stratégia előállítja a maga foldjait a fixture-ön, és a
   foldok uniója a teljes felvételhalmaz (nincs elveszett elem).
2. A leakage-detektor a szándékosan elrontott fixture-változaton hibát dob, és
   a hibaüzenet megnevezi az ütköző csoportkulcsot.
3. Az onset-tolerancia (50 ms) határa **inkluzív**, mindhárom cellával mérve: a
   küszöb **alatt** (49 ms) → találat; **rajta** (pontosan 50 ms) → találat, a
   határ az elfogadó oldalhoz tartozik; **fölött** (51 ms) → hiányzó találat.
4. **(R3 szerint javítva)** A fixture-re kézzel kiszámolt értékek egyeznek:
   onset P/R/F1 (25/50/100 ms), irány-F1, any-strum F1, accepted accuracy +
   coverage, false visible event/min, latencia p50/p95, ECE, Brier. A
   bizonyíték HÁROM része kötelező, mert a fixture ebben a körben keletkezik,
   így brief-beli literál nem létezhet:
   - a teszt a **literál várt értéket** állítja (pl. `expect(m.onsetF1, 0.8)`),
     NEM az implementációt hívja újra referenciaként;
   - a §10-ben ott a **kézi levezetés** minden számhoz (`TP=…, FP=…, FN=…` →
     `P=…, R=…, F1=…`), hogy a szám a kód nélkül is ellenőrizhető legyen;
   - a levezetés `python3 -c`-vel kiszámolva, a parancs és a kimenete a
     §10-ben idézve.
5. A report tartalmazza minden metrika definícióját (tolerancia, párosítási
   szabály, számláló és nevező megnevezése) — ADR 0509 D3.
6. Kétszeri futtatás bájtra azonos JSON-t ad.
7. Hiányzó csoportkulcsnál típusos hiba, nem `unknown` fold.
8. **(R4)** A párosítás maximális kardinalitású: az L269 ellenpéldáján
   (várt `50, 90`; detektált `0, 55`; tolerancia 50 ms) a harness **2 TP**-t
   mér, nem 1-et.
9. **(R5)** Minden metrika hordozza az irányát: az onset/irány/any-strum/akkord
   F1, az accepted accuracy és a coverage `higherIsBetter = true`; az ECE, a
   Brier, a false visible event/min és a latencia p50/p95
   `higherIsBetter = false`. A cella mind a négy hiba-metrikát tételesen méri.
10. **(R7)** A `lib/features/live/**` új fájljai nem importálnak
    `package:strumsight/features/audio_analysis/…`-t; a `tools/round-gate.sh`
    `architecture` lépése zöld.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A leakage-detektor csak logol | 2. pont hibadobás-cellája |
| A párosítás exkluzív határ (`<`) | 3. pont **rajta (50 ms)** cellája |
| A coverage a teljes halmazra oszt, nem az elfogadottakra | 4. pont accepted/coverage cellája |
| A foldok hash-sorrendben állnak elő | 6. pont bájtra-azonos cellája |
| Hiányzó csoportkulcs → `unknown` fold | 7. pont típusos-hiba cellája |
| Az ECE binjei egyenlő darabszámúak egyenlő szélesség helyett | 4. pont ECE-cellája |
| A párosítás mohó („legközelebbi szabad pár"), nem maximális | 8. pont L269-ellenpélda cellája |
| Az ECE/Brier/latencia `higherIsBetter = true`-t kap | 9. pont irány-cellája |
| A harness importálja az `audio_analysis` evaluation kódját | 10. pont — a gate `architecture` lépése |
| A metrika-teszt az implementációt hívja referenciaként, nem literált állít | 4. pont — a review méri: a mutált implementáció is zöld maradna |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/evaluation/recognition_split_test.dart test/features/live/evaluation/recognition_metrics_test.dart
```

A parancs a `gate_tests` mindkét elemét tételesen átadja (R2/S12) — a kaput a
PARANCSSOR futtatja, nem a metaadat.

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a leakage-detektor ideiglenes kikapcsolásával a 2. pont
cellája **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Fixture (a leakage-változattal együtt).
2. Split-stratégiák + detektor, teszttel.
3. Metrikák, kézzel ellenőrzött értékekkel.
4. Runner + CLI.

## 9. Kockázatok

- **A metrikák túl sokan vannak egy körre:** ha a kör mérete futás közben
  aránytalannak bizonyul, a chord-metrikák leválaszthatók egy `E14-R08b`
  körre — ez `stopped` jelzéssel és brief-revízióval történik, nem csendben.
- **Python-oldali duplikáció:** a `ml/honest_eval.py` NEM módosul; ha a két
  oldal eltérő definíciót adna, az a review dolga, nem a kódé.
- **Fixture-túlillesztés:** a fixture-nek tartalmaznia kell nem párosított
  eseményt és elutasított (abstained) eseményt is.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
