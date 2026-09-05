# E14-R19 — Adataugmentáció és kiegyensúlyozott training recept

- **Státusz:** READY (pre-flight elvégezve 2026-09-05, kód újraolvasva: `main @ 9632a96d`)
- **Típus:** Chapter 14, Kör 19 (strum recovery blokk) — **kutatási kör**
- **Kör-azonosító:** `E14-R19`
- **Branch:** `sonnet-impl/e14-r19-augmentation-and-balanced-recipe`
- **Előfeltétel:** `E14-R08` (grouped harness) és `E14-R15` (hard-negative
  taxonómia) merge-elve. ✅ mérve: `59372c9c8`, `c14b89730`.
- **Brief szerzője:** Claude (Opus 5) · **§0.0 revízió:** Claude (Opus 5), 2026-09-05
- **ADR:** [`0525`](../adr/0525-seeded-manifested-augmentation-and-honest-ablation.md)
  — a pre-flightban MEGÍRVA (a `docs/adr/` a TILOS zónában van, az implementer
  nem nyúl hozzá).

---

## 0.0 Pre-flight revízió (2026-09-05, `main @ 9632a96d`)

Az eredeti brief **2026-08-20-án, `main @ 6371aa3`-on** készült; azóta **448
commit** landolt. A `brief-lint` **S12** fokot jelzett; a pre-flight mérés
ennél többet talált. Az alábbi tíz pont a kör érvényes szerződése — ahol
eltér az eredeti szövegtől, **ez a szakasz az erősebb**.

### R1 — Az ADR-szám `0371` → **`0525`**

`docs/adr/0371-*.md` nem létezik. A foglaló
(`tools/round-slots.py reserve-adr --round E14-R19`) a **`0525`**-öt adta; az
`O_CREAT|O_EXCL` marker miatt ez az érvényes szám. Az ADR MEGÍRVA a
pre-flightban. (Ugyanez mérve: E14-R08 `0360`→`0509`, E14-R15 `0367`→`0521`,
E14-R16 `0368`→`0524`.)

### R2 — S12: a §7 gate-parancs a `gate_tests` listát tükrözi

A §7 parancsa mostantól **szó szerint** a `gate_tests` egyetlen elemét
futtatja (`test/tooling/augmentation_manifest_test.dart`), nem a tágabb
`test/tooling` könyvtárat — a brief nem ígérhet olyan mércét, amit nem
futtat.

### R3 — S15: mi maradt igaz a §2 „mért tényekből"

| Eredeti állítás | Ma mérve (`main @ 9632a96d`) |
|---|---|
| `ml/augment.py` létezik, pure-NumPy, PCM-szintű | ✅ igaz, 151 sor, változatlan |
| nincs mellette manifest | ✅ igaz |
| nincs ablation-report | ⚠️ **RÉSZBEN HAMIS** — lásd R4 |
| `ml/synth.py`, `prepare_dataset.py`, `negatives.py` a kör nem írja át | ✅ igaz, változatlan |
| `ml/test_pipeline.py` a Python belépési pont | ✅ igaz (24 cella az `ml/` gyökérben, 115 az egész fán) |

### R4 — A szállított augmentáció **nem javított** egyetlen unseen-player spliten sem

`ml/honest_results.json` (r173) MÁR tartalmaz leave-one-guitarist-out
(= unseen-player) számokat tiszta és augmentált kezelésre is:

| Split (LOGO, unseen player) | tiszta `logo` | `logo_aug` | különbség |
|---|---|---|---|
| `batch` | **0.7066** ± 0.0165 | 0.6985 ± 0.0093 | **−0.0081** |
| `live70` | **0.6061** ± 0.0548 | 0.5289 ± 0.0952 | **−0.0772** |

A §5.3 elfogadási feltétele („legalább egy split javul") tehát a MAI
összetett recepttel **nem teljesül**. A `logo_aug` kezelés ráadásul
regularizációt is bekapcsol (`AUG_REG`: dropout 0.25 / rec_dropout 0.15 /
l2 1e-4), ezért **konfundált**: a különbség két hatás összege, és egyetlen
EGYEDI transzformáció elfogadására vagy elvetésére sem használható. Mindkét
tényt a riportnak ki kell mondania (ADR 0525 D7).

### R5 — A per-transzformációs ablation MÉRTEN nem fut le ebben a körben

`ml/honest_results.json::_timing` → `logo_aug`: **10 769,7 s ≈ 3,0 óra**
EGYETLEN kezelés-párra. Az implementer-burkoló abszolút időkorlátja **3600 s**
(`docs/execution/engine-registry.tsv`, `sonnet-impl` sor). Egy hét
transzformációra kiterjedő leave-one-transform-out ablation nagyságrendileg
20+ óra → **nem futtatható**.

**Feloldás (nem lazítás):** a 6. acceptance-pont a riport SZERKEZETÉT és
becsületességét méri, nem a tréning meglétét. Minden transzformáció-sor vagy
MÉRT split-eredményt hordoz, vagy a literális `"nem mért"` értéket a
reprodukáló paranccsal és a mért költséggel — numerikus `0` tilos —, és a
`"nem mért"` sor **soha nem** kaphat `accepted` státuszt (ADR 0525 D6). A
recept VÉGLEGESÍTÉSE az `E14-R20` dolga.

### R6 — A címke-transzponálás EGÉSZ félhangot kíván → ÚJ, additív belépési pont

`ml/augment.py::augment_pcm` ma `rng.uniform(-semitone_range, semitone_range)`
hívással **folytonos** félhangot húz, a fejléc pedig kimondja: „Direction
labels are INVARIANT to all of these". Akkord-címkét csak **egész** félhanggal
lehet transzponálni. A §5.1 tehát ÚJ, egész-félhangos utat kíván; a meglévő
`augment_pcm` viselkedése **bitre változatlan** marad (§9 regressziós
követelmény, ADR 0525 D1).

### R7 — A Python-cellát egyetlen CI-workflow sem futtatja

`.github/workflows/ml-train.yml` → `python -m pytest test_pipeline.py -q`;
`router-ci.yml` → `pytest tools/tests`. A `ml/test_augmentation_labels.py`
tehát **nincs** CI-ban, és a `.github/**` a TILOS zóna → a bővítés **H3**
volna, ezért NEM része ennek a körnek. A CI-oldali mérce a **Dart-őr**
(`gate_tests`); a Python-cella lokálisan és a review-ban reprodukálva mér. A
§10 handoffban ezt ki kell mondani.

### R8 — A Dart-őr a tesztfájlban él (dokumentált, korlátos kivétel)

Sem `lib/`, sem `tool/` nincs az `allowed_paths`-on, tehát a
manifest-validátor nem importálható könyvtárból. Precedens és minta:
`test/tooling/joint_io_schema_test.dart` (E14-R18, ADR 0517 D8) — ott a
validátor teljes egészében a tesztfájlban él, kimondott, korlátos kivételként
az L631 „a cella a szállított belépési pontot mérje" szabálya alól. Ugyanez
érvényes itt. **Ez nem ad felmentést a Python oldalon:** a Python-cellák a
SZÁLLÍTOTT generáló/validátor függvényeket hívják, nem kézzel épített dictet
(L631).

### R9 — Minden új cella legyen PIROS a saját javítása nélkül (L563)

A §10-ben cellánként dokumentáld: a javítás ideiglenes visszavételével a cella
PIROS, visszaállítva ZÖLD. A „belefér a régi ablakba" degenerált fixture nem
mérce.

### R10 — A kör új fájljai a listán KÍVÜL semmit nem visznek pirosra (mérve)

Sem `ml/**`, sem `docs/eval/**`, sem `evaluation/recognition/fixtures/**`
alatt nincs könyvtár-bejáró (`listSync`-es) őr a fán; a hivatkozások
mind NÉVSZERINTIEK. A `tools/tests/test_pipeline_throughput.py` útvonal-listái
szintetikus fixture-ök, nem valós-fa enumeráció. (L164 osztálya mérve
kizárva.) Ha az implementer mégis a listán kívüli fájlt találna pirosnak:
**`stopped` jelzés + jelentés**, nem lista-tágítás.

### R11 — A címke-transzponálás osztály-matematikája MÁR MERGE-ELVE VAN — újraírni tilos

A pre-flight grepje megtalálta a kör legfontosabb előzményét, amit az eredeti
brief nem ismert:

- `ml/chords/labels.py::transpose_class` + `ml/chords/augment.py::_transpose_labels`
  / `transpose_window` — **egész-félhangos, címke-transzponáló** augmentáció a
  25-osztályos majmin térben (`0 = N.C.` invariáns; dúr/moll csoport mod 12
  gördül). Pure NumPy, seedelhető.
- Ez a szerződés **CI-fedett**: `.github/workflows/chord-train.yml` futtatja a
  `chords/test_augment.py`-t (a `chords/test_labels.py`-vel együtt).
- A chord-track a **CQT-tengelyen** transzponál (`BINS_PER_SEMITONE = 2`,
  zero-fill, nem `np.roll`), és `max_semi=5`-öt használ (a biztonságos
  zero-fill tartomány). Ez **más közeg, más korlát**, mint ennek a körnek a
  PCM/varispeed útja a ±6-os ISMIR-optimummal — a kettő nem mond ellent
  egymásnak, de a manifestnek meg kell mondania, MELYIK korlát MELYIK útra
  vonatkozik.

**Kötelező következmény:** a címke-transzponálás osztály-matematikáját
**importálni és újrahasználni** kell (`ml/chords/labels.py::transpose_class`),
**nem újraírni**. Az `ml/chords/**` a TILOS zóna marad: read-only függőség,
egyetlen fájlját sem módosítod. Egy második, párhuzamos akkord-osztály-logika
a fában **MAJOR lelet** (ugyanaz a hibaosztály, mint [L164](../LESSONS.md#l164)
és az „egy második metrika-fájl mellette" E14-R15 halt).

**Az akkord-címke tényleg létezik a strum-adat-úton is:**
`ml/klangio.py::parse_strums` a `.strums` fájl HARMADIK oszlopát akkord-címkeként
olvassa (`time_s \t D|U \t chord-label`), a `windows_for_recording` viszont
eldobja (`for t, direction, _chord in events`). A `klangio.py` TILOS zóna, tehát
ezt a kör NEM köti be — de a §5.1 emiatt nem elméleti: a manifest egy
adatkészletet ír le, amelyben az akkord-címke JELEN VAN.

### R12 — Az `ml/honest_results.json` **gitignore-olt**, tehát a szám doboz-lokális

`ml/.gitignore:14` → `honest_results.json`. Az R4/R5 számai ezért a repóból
**nem ellenőrizhetők**. Az ablation-riport a számokat **doboz-lokális,
r173-as mérésként** idézze, a reprodukáló paranccsal együtt, és **ne** állítsa,
hogy a fájl a repóban van. Ugyanez vonatkozik a `_timing` 10 769,7 s-os
értékére.

> **A prompt §1 két kötelező mérése.** (1) *Elérhetetlen cél-státusz:* a kör
> egyetlen acceptance-cellája sem ír elő állapotgép-státuszt — nincs reducer
> vagy átmenettábla az útban, a mérés tárgytalan. (2) *Erőforrás-tulajdonlás:*
> a kör nem rendel lease-t, lockot, handle-t vagy subscriptiont réteghez —
> tárgytalan. Mindkettő kimondva, nem kihagyva.

---

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

Az augmentáció legyen **seedelt, manifestelt, kikapcsolható és becsületesen
riportált**: egész-félhangos, címke-transzponáló pitch shift, szoba-IR, gain,
EQ, kompresszió, eszköz-válasz, SNR, forgalom/nappali zaj, fret/pick/tap burst
— és a down/up/no-strum, illetve az akkord-osztályok kiegyensúlyozása. Egy
transzformáció csak MÉRT javulással lehet `accepted`; mérés hiányában
`candidate`, romlás esetén `rejected` (ADR 0525 D6). Romló subgroup esetén
NINCS automatikus elfogadás.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **`ml/augment.py` (r173):** a PCM-szintű augmentáció alapja megvan; a
  fejléc kimondja, miért PCM-en és nem spektrogramon történik.
- **`ml/negatives.py` (r174):** a no-strum osztály és a hard negatívok — a
  kiegyensúlyozás ezekre is vonatkozik.
- **`ml/honest_results.json` (r173):** a `logo` / `logo_aug` szakaszok és a
  `_timing` — a kör két legfontosabb mért bemenete (R4, R5).
- **[L631](../LESSONS.md#l631):** a determinizmus-cella a SZÁLLÍTOTT belépési
  pontot mérje, ne kézzel épített riportot.
- **[L563](../LESSONS.md#l563):** a cella csak akkor mérce, ha a saját
  javítása nélkül PIROS.
- **[L164](../LESSONS.md#l164):** az „additív manifest-bővítés" a kipinnelt
  assertionök grepeléséből induljon (R10-ben elvégezve).
- **[ADR 0517](../adr/0517-streaming-joint-onset-direction-prototype.md) D8:**
  tilos `lib/`+`tool/` mellett a validátor a tesztfájlban él (R8).
- **[ADR 0509](../adr/0509-grouped-recognition-evaluation-and-leakage-protection.md):**
  `null` ≠ `0` — a hiányzó mérés nem nulla.
- **Chapter 14 §9/4:** tilos egyetlen játékosra vagy ugyanarra a test setre
  hangolni.

## 2. Jelenlegi állapot — mért tények (`main @ 9632a96d`)

- `ml/augment.py` — 151 soros, pure-NumPy PCM-augmentáció
  (`pitch_shift`, `add_noise`, `gain`, `synth_rir`, `reverb`, `mic_sim`,
  `augment_pcm`); nincs mellette **manifest**, nincs `enabled`-kapcsoló, és a
  pitch shift folytonos félhangot húz (R6).
- `ml/honest_results.json` — MÁR van benne unseen-player ablation-jellegű
  mérés, és az **nem javulást** mutat (R4); a per-transzformációs bontás
  hiányzik, és mérten nem is fut le itt (R5).
- `ml/synth.py`, `ml/prepare_dataset.py`, `ml/negatives.py` — a tanító adat-út
  többi darabja; a kör ezeket NEM írja át.
- `ml/chords/augment.py` + `ml/chords/labels.py` — **MÁR MERGE-ELT**,
  CI-fedett (`chord-train.yml`), egész-félhangos **címke-transzponáló**
  augmentáció a 25-osztályos majmin térben. A kör ezt **újrahasználja**, nem
  írja újra (R11), és nem módosítja.
- `ml/klangio.py::parse_strums` — a `.strums` HARMADIK oszlopa akkord-címke,
  amit a `windows_for_recording` ma eldob (`_chord`). A `klangio.py` tilos
  zóna; a kör nem köti be, csak tudomásul veszi (R11).
- `ml/honest_results.json` — **gitignore-olt** (`ml/.gitignore:14`), tehát az
  R4/R5 számai doboz-lokálisak (R12).
- `ml/test_pipeline.py` — a meglévő Python-teszt belépési pont (24 cella),
  köztük `test_augment_pcm_is_stochastic_but_deterministic_per_seed` — ezek
  **változatlanul zöldek** kell maradjanak (§9 regresszió).

## 3. Scope

**Benne:** az `augment.py` **additív** bővítése (egész-félhangos,
címke-transzponáló út; a hiányzó transzformációk; `enabled`-kapcsolók;
seed-szerződés; manifest-generálás és -validálás; osztály-kiegyensúlyozás),
a Python-cellák, a Dart-oldali manifest-őr + CI-fixture, és a becsületes
ablation-riport.

**Nincs benne:** modelltanítás elfogadása (az az R20), `lib/**`, `assets/**`,
`tool/**`, `.github/**`, DSP-konstans, a szállított súlyok cseréje, a meglévő
`augment_pcm` viselkedésének megváltoztatása.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `ml/augment.py` | a meglévő augmentáció **additív** bővítése |
| `ml/augmentation_manifest.json` | mi futott, milyen seeddel, milyen aránnyal, milyen státusszal |
| `ml/test_augmentation_labels.py` | címke-eltolódás, tartomány-határ, seed-determinizmus, kapcsolók |
| `evaluation/recognition/fixtures/augmentation_manifest_sample.json` | CI-fixture a Dart-őrhöz |
| `test/tooling/augmentation_manifest_test.dart` | manifest-séma őr (a `gate_tests` egyetlen eleme) |
| `docs/eval/augmentation-ablation.md` | ablation-riport |
| `docs/rounds/e14-r19-augmentation-and-balanced-recipe.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `ml/chords/**` (R11: **importálni
igen, módosítani nem**), `ml/klangio.py`, `ml/honest_eval.py`,
`ml/honest_results.json`, `ml/test_pipeline.py`, `ml/export_*`, `assets/**`,
`lib/**`, `tool/**`, `docs/adr/**`, `docs/rag/chunks/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0525)

### 5.1 A pitch shift a CÍMKÉT is transzponálja — egész félhangon

Félhang-eltolásnál az akkord-címke együtt mozog. **NEM elfogadható**: „a
direction-fejnek úgyis mindegy" — a manifest egy adatkészletet ír le, nem egy
fejet. A címke-transzponáló út bemenete **egész** félhang; törtérték típusos
hiba, nem csendes kerekítés (ADR 0525 D1/D2).

Az osztály-matematikát **a MÁR MERGE-ELT `ml/chords/labels.py::transpose_class`
adja** — importálni és újrahasználni kell, nem újraírni (R11). Az
`ml/chords/**` read-only függőség; egy párhuzamos, második akkord-osztály-logika
a fában MAJOR lelet.

### 5.2 Minden augmentáció seedelt és kikapcsolható

Seed nélküli véletlen tilos; minden transzformációnak van `enabled`
kapcsolója, és a manifest rögzíti a ténylegesen futott halmazt. Minden
kapcsoló hamis → a kimenet **bitre azonos** a nyers bemenettel (ADR 0525 D4).

### 5.3 Az elfogadás MÉRÉSHEZ kötött — és a mérés hiánya nem elfogadás

Egy transzformáció csak akkor `accepted`, ha az ablation-riport szerint
legalább egy unseen-player VAGY unseen-device split javul, és egyik sem romlik
a jelentett hibahatáron túl. Mérés hiányában `candidate`; romlás esetén
`rejected`. `"nem mért"` sor mellett `accepted` státusz **típusos hiba**
(ADR 0525 D6).

### 5.4 Romló subgroup → nincs automatikus elfogadás

A riport romlást jelző sorát a döntés (ADR 0525 D7) tárgyalja; az implementer
nem fogadhat el csendben. A ma szállított összetett recept sora `rejected`, a
`logo` ↔ `logo_aug` különbséggel és a regularizációs konfund kimondásával
(R4).

### 5.5 A tanító-oldal határa

A kör az adat-utat érinti; a modell-architektúra és a szállított súlyok
változatlanok (ADR 0525 D9).

### 5.6 Az osztály-kiegyensúlyozás nem töröl valós adatot

Csak súlyoz vagy (újra)mintavételez. A manifest a kiinduló ÉS a
kiegyensúlyozott arányt is rögzíti (ADR 0525 D8).

## 6. Acceptance criteria

1. A `ml/test_augmentation_labels.py` bizonyítja, hogy ±N **egész** félhang
   pitch shift után a címke pontosan N félhanggal tolódik (a mátrix ±1, ±3,
   ±6 esetre fut), és hogy nem-egész bemenet **típusos hibát** ad (nem
   kerekítést). Az osztály-matematika a MERGE-ELT
   `ml/chords/labels.py::transpose_class`-ból jön (R11) — a cella azt is
   bizonyítja, hogy az `N.C.` osztály invariáns marad.
2. A pitch-shift tartomány határa **inkluzív**: a hármas cella a ±6-ra — a
   határ **alatt** (±5) elfogadott, pontosan **rajta** (±6) elfogadott (a
   határ ide tartozik), a határ **fölött** (±7) a validátor hibát ad.
3. Ugyanaz a seed bitre ugyanazt a kimenetet adja; eltérő seed eltérőt
   (mindkettő mérve, a SZÁLLÍTOTT belépési ponton keresztül — L631).
4. Minden transzformáció kikapcsolható, és **minden** kapcsoló kikapcsolt
   állapotában a kimenet bitre azonos a nyers bemenettel.
5. A manifest tartalmazza a seedet, a transzformáció-listát (`name`,
   `enabled`, paraméterek, `status`), az osztály-arányokat (kiinduló ÉS
   kiegyensúlyozott); hiányzó kötelező mező → típusos hiba a Python
   validátorban **és** a Dart-őrben.
6. Az ablation-riport minden transzformációhoz ad **vagy** egy mért
   unseen-player / unseen-device split-eredményt, **vagy** a literális
   `"nem mért"` értéket a reprodukáló paranccsal és a mért költséggel.
   Hiányzó mérés helyén numerikus `0` **tilos**, és `"nem mért"` sor mellett
   `accepted` státusz **tilos** (mindkettő gépi cellával mérve, Python ÉS
   Dart oldalon).
7. A ma szállított összetett recept sora `rejected`, és a riport idézi a
   `logo` ↔ `logo_aug` különbséget (batch −0.0081, live70 −0.0772) **és** a
   regularizációs konfundot (R4).
8. **Regresszió:** `python3 -m pytest ml -q` továbbra is teljesen zöld — a
   meglévő `ml/test_pipeline.py` egyetlen cellája sem változik és egyik sem
   bukik; a meglévő `augment_pcm` viselkedése bitre változatlan (kipinnelt
   cella egy rögzített seedre).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA | Hol mér |
|---|---|---|
| A pitch shift nem mozgatja a címkét | 1. pont címke-mátrixa (±1, ±3, ±6) | Python |
| Törtérték csendes kerekítése | 1. pont típusos-hiba cellája | Python |
| A tartomány exkluzív felső határral (`< 6`) | 2. pont „pontosan rajta" (±6) cellája | Python |
| A tartomány felső határ nélkül (±7 átmegy) | 2. pont „fölötte" (±7) cellája | Python |
| Seed nélküli véletlen | 3. pont determinizmus-cellája | Python |
| A kikapcsolt transzformáció mégis módosít | 4. pont bitazonossági cellája | Python |
| A manifestből hiányzik a seed / a `status` | 5. pont | Python **és** Dart |
| Hiányzó ablation-mérés `0`-ként | 6. pont `"nem mért"` cellája | Python **és** Dart |
| `"nem mért"` sor `accepted` státusszal | 6. pont státusz-cellája | Python **és** Dart |
| A romló összetett recept `accepted`/eltüntetve | 7. pont | Python **és** Dart |
| A bővítés megváltoztatja a meglévő `augment_pcm`-et | 8. pont kipinnelt regressziós cellája | Python |
| Újraírt, párhuzamos akkord-osztály-matematika | 1. pont — a cella a MERGE-ELT `transpose_class`-szal szemben mér (R11) | Python |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/augmentation_manifest_test.dart
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). A Python oldal külön, önálló parancsként:

```bash
python3 -m pytest ml -q
```

`&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld cellánként (L563): a javítás ideiglenes visszavételével
a cella **PIROS**, visszaállítva **ZÖLD**. Kötelezően legalább:
a címke-transzponálás (1. pont), a ±6 inkluzív határ (2. pont), a
bitazonos kikapcsolás (4. pont) és a `"nem mért"` + `accepted` tiltás
(6. pont) cellájára.

## 8. Implementációs sorrend

1. Manifest-séma + Dart-őr + fixture (RED-del kezdve).
2. Címke-transzponálás teszt (RED), majd az ÚJ, egész-félhangos út (R6).
3. A hiányzó transzformációk, seedelve és kapcsolhatóan; a meglévők
   viselkedése változatlan (regressziós cella).
4. Osztály-kiegyensúlyozás + ablation-riport a `"nem mért"` szerződéssel.

## 9. Kockázatok

- **Az `augment.py` átírásának kísértése:** a fájl a listán van, de a bővítés
  **additív**; a meglévő transzformációk viselkedése nem változhat
  (regressziós cella kötelező, 8. acceptance-pont).
- **Tanító-környezet:** a per-transzformációs ablation MÉRTEN nem fut le ebben
  a körben (R5) — ez NEM `blocked`, hanem a `"nem mért"` szerződés (R5, ADR
  0525 D6). A kör akkor `blocked`, ha a RIPORT SZERKEZETE nem építhető meg.
- **Osztály-arány torzítás:** a kiegyensúlyozás nem törölhet valós adatot,
  csak súlyoz/mintavételez — a manifest ezt rögzíti (5.6).
- **Lista-tágítás kísértése:** a `.github/**` (R7), a `tool/**` (R8) és az
  `ml/chords/**` (R11) a tilos zónában van; ha a kör ezekre szorulna, az
  `stopped` + jelentés, nem önkezű tágítás. Az `ml/chords/**` **importálása**
  viszont nem módosítás — az kifejezetten elvárt (R11).
- **Az akkord-osztály-logika újraírása:** MAJOR lelet; a merge-elt
  `transpose_class` az egyetlen forrás (R11).
- **Doboz-lokális szám repo-szintűnek állítása:** az `ml/honest_results.json`
  gitignore-olt (R12) — a riport ezt mondja ki, nem hallgatja el.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5). Minden acceptance-pont
zöld gépi cellával mérve; a §7 két kapuja külön, csővezeték nélkül futott.

### Fájlonként mit és miért

- **`ml/augment.py`** — additív bővítés, a meglévő `augment_pcm` és az
  általa hívott hat transzformáció (`pitch_shift`, `add_noise`, `gain`,
  `synth_rir`, `reverb`, `mic_sim`) **egyetlen sora sem változott** (lásd a
  8. pont regressziós bizonyítékát). Új tartalom:
  - `_validate_whole_semitone` + `transpose_pcm_and_chord_labels` +
    `random_label_transposing_shift` — az egész-félhangos,
    címke-transzponáló pitch-shift út (R6/D1/D2/D3). A címke-aritmetikát
    a MÁR MERGE-ELT `chords.labels.transpose_class`-ból importálja
    (`from chords.labels import NO_CHORD, transpose_class`) — nem írja
    újra (R11/D10). `ml/chords/**`-hoz egyetlen írás sem történt.
  - `DEVICE_PROFILES` + `device_response`, `compress`, `traffic_noise`,
    `transient_burst` — a brief §1-ben hiányzóként megnevezett
    transzformációk (eszköz-válasz, kompresszió, forgalom/nappali zaj,
    fret/pick/tap burst). Mind seedelt (rng-paraméterezett) és pure NumPy.
  - `DEFAULT_TRANSFORM_CONFIG` + `_merged_config` +
    `_apply_secondary_transforms` + `augment_pcm_configurable` +
    `augment_pcm_with_chord_labels` — a kapcsolható, manifestelt
    komponálás (D4). A két komponáló függvény UGYANAZT a
    `_apply_secondary_transforms`-t hívja, hogy a bitazonos-kikapcsolás
    garanciája ne tudjon szétcsúszni a két út között.
  - `balance_indices` + `class_ratios` — az osztály-kiegyensúlyozás: csak
    visszamintavételez (ismétléssel), soha nem dob el eredeti indexet
    (D8).
  - `PITCH_SHIFT_LIMITS`, `validate_manifest`, `build_manifest` — a
    manifest-szerződés (D5/D6/D8/D10) Python-oldali forrása és őre.
- **`ml/augmentation_manifest.json`** — a `build_manifest`-tel TÉNYLEGESEN
  generált (nem kézzel írt JSON-dict) manifest; a 11 transzformáció-sor
  közül 10 `candidate` (nem mért), a `composite_recipe_r173` `rejected`
  (mért, romló LOGO-delták). Egy Python-cella
  (`test_the_shipped_ml_augmentation_manifest_json_validates_cleanly`)
  betölti és validálja — a fájl NEM kerülhet ki szinkronból a
  validátortól.
- **`ml/test_augmentation_labels.py`** — 42 cella: címke-transzponálás
  mátrix + N.C.-invariancia + típusos hibák (1. pont), ±6 inkluzív határ
  (2. pont), seed-determinizmus a SZÁLLÍTOTT komponáló belépési pontokon
  keresztül (3. pont, L631), bitazonos kikapcsolás mindkét komponáló
  útra (4. pont), manifest-kontraktus + „nem mért"/`accepted` tiltás
  (5–6. pont), osztály-kiegyensúlyozás (5.6), és a kipinnelt
  `augment_pcm` regresszió (8. pont).
- **`evaluation/recognition/fixtures/augmentation_manifest_sample.json`**
  — az `ml/augmentation_manifest.json` másolata, a Dart-őr CI-fixture-je
  (R7/R8: CI-nak nincs Python/TF interpretere).
- **`test/tooling/augmentation_manifest_test.dart`** — 27 cella, a
  `joint_io_schema_test.dart` (E14-R18, ADR 0517 D8) mintáját követve: a
  validátor teljes egészében a tesztfájlban él (nincs `lib/`/`tool/` a
  listán). A Python `validate_manifest`-tel PÁRHUZAMOS, nem azt hívó,
  szabálykészletet valósít meg (kötelező mezők, státusz-enum, „nem mért"
  ≠ numerikus 0, „nem mért" + `accepted` tiltás, delta-visszaszámolás a
  mért splitekből, két KÜLÖNBÖZŐ félhang-korlát, `dropsRealData==false`).
- **`docs/eval/augmentation-ablation.md`** — a becsületes ablation-riport:
  soronként vagy „nem mért" (repro parancs + a mért 10 769,7 s/pár
  költség-alap), vagy a ma szállított recept TÉNYLEGES, romló LOGO-számai
  a regularizációs konfund kimondásával; explicit szakasz arról, hogy az
  `ml/honest_results.json` gitignore-olt (R12/D11) és miért nem futtatható
  ebben a körben egy teljes leave-one-transform-out ablation (R5).

### Acceptance-pontonként a MÉRT bizonyíték

1. **Címke-transzponálás mátrix + N.C.-invariancia + típusos hiba** —
   `ml/test_augmentation_labels.py::test_label_transpose_matrix_moves_class_by_exactly_n_semitones`
   (±1/±3/±6, parametrizált), `test_label_transpose_uses_the_merged_transpose_class_not_a_reimplementation`
   (A-moll −1 félhang → G#-moll, a MERGE-ELT `transpose_class`-szal
   szemben mérve), `test_nc_class_is_invariant_under_label_transpose`,
   `test_non_whole_semitone_raises_typeerror_not_silently_rounded`,
   `test_bool_semitone_is_rejected_as_a_typed_error`. Mind ZÖLD.
2. **±6 inkluzív határ** —
   `test_below_the_boundary_is_accepted` (±5),
   `test_exactly_on_the_boundary_is_accepted_inclusive` (±6),
   `test_above_the_boundary_is_a_typed_error` (±7 → `ValueError`). ZÖLD.
3. **Seed-determinizmus a szállított belépési ponton** —
   `test_random_label_transposing_shift_is_deterministic_per_seed`,
   `test_augment_pcm_with_chord_labels_is_deterministic_per_seed`,
   `test_augment_pcm_configurable_is_deterministic_per_seed` — mindhárom
   ugyanazzal a seeddel bitazonos, más seeddel eltérő kimenetet mér a
   TÉNYLEGES komponáló függvényen (nem kézzel épített dicten, L631).
4. **Bitazonos kikapcsolás** —
   `test_configurable_augmentor_all_disabled_is_bit_identical_to_input`,
   `test_label_aware_augmentor_all_disabled_is_bit_identical_to_input`
   (mindkét komponáló út, minden kapcsoló hamis → `np.array_equal`),
   `test_only_pitch_shift_enabled_still_moves_the_signal` (ellenőrző
   pozitív eset: egy kapcsoló visszakapcsolva MÉGIS változtat).
5. **Manifest kötelező mezők** — 6 cella
   (`test_missing_seed_is_a_typed_error`,
   `test_missing_transforms_is_a_typed_error`,
   `test_transform_missing_status_is_a_typed_error`,
   `test_missing_class_ratios_group_is_a_typed_error`,
   `test_missing_balanced_phase_is_a_typed_error`,
   `test_a_well_formed_manifest_validates_cleanly`) Python oldalon;
   Dart oldalon az A2/A3/A6 csoport (11 cella).
6. **„nem mért" ≠ 0, „nem mért" soha `accepted`** —
   `test_numeric_zero_for_a_missing_measurement_is_rejected`,
   `test_not_measured_row_with_accepted_status_is_rejected`,
   `test_not_measured_row_with_candidate_or_rejected_status_is_fine`
   Python oldalon; Dart A4 csoport (5 cella, ebből egy a kör kötelező
   falszifikációs cellája, lásd lent).
7. **A ma szállított recept `rejected` + idézett LOGO-delták** —
   `test_the_shipped_ml_augmentation_manifest_json_validates_cleanly`
   (Python, betölti a valós fájlt és leellenőrzi a `composite_recipe_r173`
   sor `status`-át), Dart A1/A5 csoport (a valós fixture-ön mér, és a
   `-0.0081`/`-0.0772` delták jelenlétét is ellenőrzi).
8. **Regresszió: `augment_pcm` bitre változatlan** —
   `test_existing_augment_pcm_is_byte_identical_for_a_pinned_seed`
   (SHA-256 digest egy rögzített szintetikus bemenetre + seed=1234-re);
   `python3 -m pytest ml -q` **157/157 ZÖLD** (115 meglévő + 42 új,
   egyetlen meglévő cella sem módosult vagy bukott).

### A §7.1 falszifikációs cellák (L563) — mind a négy kötelező

Mindegyiknél: a javítást ideiglenesen visszavettem → cella PIROS →
`git checkout -- <fájl>` → cella ZÖLD. Egyik mutáció sem maradt a
munkafában (`git status --porcelain` üres a kör alatt és most is).

| # | Cella | Mutáció | PIROS (idézet) | ZÖLD visszaállítás után |
|---|---|---|---|---|
| 1 | Címke-transzponálás | `transposed = classes` (elfelejtett transzponálás) `transpose_pcm_and_chord_labels`-ben | 7 teszt bukott: `assert False … array([1, 1]) == 7`, `assert 'Am' == 'G#m'` | `python3 -m pytest ml/test_augmentation_labels.py -k "label_transpose_matrix or uses_the_merged" -q` → 7 passed |
| 2 | ±6 inkluzív határ | `_validate_whole_semitone`: `>` → `>=` | `ValueError: semitones=6 exceeds the inclusive range [-6, 6]` (±6-nál is elszáll) | `-k boundary` → 6 passed |
| 3 | Bitazonos kikapcsolás | `_apply_secondary_transforms`: `if cfg["gain"]["enabled"]:` → `if True:` | mindkét komponáló-út cellája bukott: `assert np.array_equal(out, pcm)` → `False` | `-k all_disabled_is_bit_identical` → 2 passed |
| 4a | „nem mért" + `accepted` tiltás (Python) | `validate_manifest`: az `if status == "accepted": raise …` ág `pass`-re cserélve | `Failed: DID NOT RAISE <class 'ValueError'>` | `-k not_measured_row_with_accepted` → 1 passed |
| 4b | „nem mért" + `accepted` tiltás (Dart) | a Dart-guard ugyanezen ága komment-re cserélve | `flutter test … --plain-name "falsification cell"` → `Expected: false / Actual: <true>` (1 failed) | ugyanaz a parancs → `+1: All tests passed!` |

### A két kapu tényleges kimenete

```
tools/round-gate.sh test/tooling/augmentation_manifest_test.dart
→ format zöld · analyze zöld · test (27/27) zöld · architecture zöld ·
  secrets zöld · l10n zöld — MINDEN GATE ZÖLD
```

```
python3 -m pytest ml -q
→ 157 passed in 21.22s
```

Mindkettő külön, csővezeték nélküli parancsként futott (L05/L09).

### Amit nem futtattam, és miért

- **Per-transzformációs leave-one-transform-out ablation** — mérten nem
  fér a körbe (R5: 1 kezelés-pár = 10 769,7 s ≈ 3,0 óra, hét
  transzformációra 20+ óra a 3600 s-os burkoló-korláttal szemben). A
  `docs/eval/augmentation-ablation.md` minden ilyen sort „nem mért"-ként
  jelöl a reprodukáló paranccsal.
- **CI-workflow bővítés** a `ml/test_augmentation_labels.py`
  lefuttatására — `.github/**` a tilos zóna (R7); a Python-cella lokálisan
  és ebben a handoffban reprodukálva mér, a CI-oldali mérce a Dart-őr.
- **`gh workflow run` / PR / merge** — nem az implementer dolga (§7).

### Nyitott kockázatok

- A `docs/eval/augmentation-ablation.md`-ben idézett `10 769,7 s` és a
  LOGO-delták az `ml/honest_results.json` r173 futásából származnak, ami
  gitignore-olt (`ml/.gitignore:14`) — egy jövőbeli reviewer ezeket a
  számokat csak akkor tudja saját maga reprodukálni, ha van hozzáférése
  egy TensorFlow-interpreteres dobozhoz + a Klangio GST-MM korpuszhoz.
- A `DEVICE_PROFILES` táblázat (`phone_a`/`phone_b`/`tablet_a`) és a
  `compress`/`traffic_noise`/`transient_burst` paraméter-tartományai
  ÉSZSZERŰ, de nem irodalomból idézett alapértékek (a `pitch_shift`
  ±6-tal szemben, ami az ISMIR-2025 Murgul et al. mért optimuma) — ezek
  finomhangolása a recept-végleges ítő E14-R20 dolga lehet.
- A `balance_indices` felső korlát nélkül mintavételez vissza (a
  legkisebb és legnagyobb osztály aránya tetszőlegesen nagy lehet); ha egy
  jövőbeli adatkészletben ez a torzítás extrém, egy felső korlát (pl.
  max 5×-ös felszorzás) hozzáadása E14-R20 döntése.

## 11. Review — a Claude tölti ki
