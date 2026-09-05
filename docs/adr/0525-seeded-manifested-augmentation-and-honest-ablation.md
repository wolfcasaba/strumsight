# ADR 0525 — Seedelt, manifestelt, kikapcsolható augmentáció: a címke-transzponálás EGÉSZ félhangot kíván, és a „nem mért" ablation-sor SOSEM lesz elfogadás

- **Státusz:** Elfogadva
- **Kör:** `E14-R19` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 19)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`) · az ADR-t az orchesztrátor (Claude Opus 5) írta a pre-flightban
- **Kapcsolódó:**
  [ADR 0517](0517-streaming-joint-onset-direction-prototype.md) (D8: ha a
  `lib/` és a `tool/` is tilos zóna, a validátor a tesztfájlban él — ez a kör
  UGYANEZT a kivételt használja),
  [ADR 0509](0509-grouped-recognition-evaluation-and-leakage-protection.md)
  (`null` ≠ `0`: a hiányzó mérés nem nulla — ez a kör ezt a szabályt viszi át
  az ablation-riportra),
  [ADR 0511](0511-recognition-release-gate-and-single-source-report.md)
  (fail-closed: az el nem fogadott dolog nem csúszhat át hallgatással),
  [ADR 0524](0524-onset-detector-variant-seam-and-ab-measurement.md) (ugyanez
  az S15-mintázat: az előre megírt brief mért alapja elmozdult),
  [ADR 0249](0249-analysis-evaluation-dataset-governance.md) (nyers audio nem
  kerül a repóba),
  [L631](../LESSONS.md#l631) (a determinizmus-cella a SZÁLLÍTOTT belépési
  pontot mérje), [L563](../LESSONS.md#l563) (a cella csak akkor mérce, ha a
  saját javítása nélkül PIROS), [L164](../LESSONS.md#l164) („additív
  manifest-bővítés" csak a kipinnelt assertionök grepeléséből indulhat),
  [L636](../LESSONS.md#l636), [L646](../LESSONS.md#l646)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ 9632a96d`)

Az `E14-R19` briefje **2026-08-20-án, `main @ 6371aa3`-on** készült; azóta
**448 commit** landolt. A `brief-lint` **S12** fokot jelzett, a mérés pedig
ennél többet talált. A hét döntő tény:

### 1. Az előre kiosztott `0371` szám elavult

`docs/adr/0371-*.md` **nem létezik**; az E14 sáv valós ADR-jei az `0509` /
`0511` / `0517` / `0520` / `0521` / `0524` tartományban járnak. A foglaló
(`tools/round-slots.py reserve-adr --round E14-R19`) a **`0525`** számot adta;
az `O_CREAT|O_EXCL` marker miatt ez az érvényes szám. Ugyanez mérve az
E14-R08-nál (`0360` → `0509`), az E14-R15-nél (`0367` → `0521`) és az
E14-R16-nál (`0368` → `0524`).

### 2. A szállított augmentáció NEM javított egyetlen unseen-player spliten sem

`ml/honest_results.json` (r173, 2026-07-13) mindkét leave-one-guitarist-out
konfigurációra tartalmazza a tiszta és az augmentált+regularizált kezelést:

| Split (unseen player, LOGO) | tiszta `logo` | `logo_aug` (r173 recept) | különbség |
|---|---|---|---|
| `batch` | **0.7066** ± 0.0165 | 0.6985 ± 0.0093 | **−0.0081** |
| `live70` | **0.6061** ± 0.0548 | 0.5289 ± 0.0952 | **−0.0772** |

A brief §5.3 elfogadási feltétele („legalább egy unseen-player VAGY
unseen-device split javul") tehát a MA szállított, összetett recepttel **nem
teljesül** — a két mért irány lefelé mutat. Ez a kör legfontosabb bemenete: a
manifest nem kanonizálhatja elfogadottként azt, amit a meglévő mérés cáfol.

**Fontos pontosság:** a `logo_aug` szakasz nem tiszta augmentációs ablation —
a kezelés az augmentáció MELLETT regularizációt is bekapcsol
(`dropout 0.25`, `rec_dropout 0.15`, `l2 1e-4`,
`ml/honest_eval.py::AUG_REG`), ezért a fenti különbség két hatás összege. Ez
nem gyengíti a következtetést (nincs javulás), de kizárja, hogy bármelyik
EGYEDI transzformációt a szám alapján fogadjuk el vagy vessük el.

### 3. A per-transzformációs ablation futásideje MÉRT, és nem fér a körbe

`ml/honest_results.json::_timing`: a `logo_aug` szakasz **10 769,7 s ≈ 3,0
óra** egyetlen kezelés-párra (2 konfiguráció × 3 fold). Egy leave-one-transform-out
ablation hét transzformációra ennek a többszöröse (nagyságrendileg 20+ óra),
miközben az implementer-burkoló abszolút időkorlátja **3600 s**
(`docs/execution/engine-registry.tsv`, `sonnet-impl` sor). A mérés tehát nem
azért marad el, mert kimarad, hanem mert **bizonyítottan nem futtatható**
ebben a körben.

### 4. A címke-transzponálás EGÉSZ félhangot kíván; a szállított út folytonos

`ml/augment.py::augment_pcm` a `rng.uniform(-semitone_range, semitone_range)`
hívással **folytonos** félhang-értéket húz, a fejléce pedig kimondja: „Direction
labels are INVARIANT to all of these". Egy akkord-címke viszont csak **egész**
félhanggal transzponálható — 4,37 félhanggal eltolt `C`-dúrnak nincs neve. A
brief §5.1 („a pitch shift a CÍMKÉT is transzponálja") ezért nem a meglévő
belépési pont megváltoztatását jelenti, hanem egy ÚJ, egész-félhangos utat.

### 5. A `ml/test_augmentation_labels.py`-t EGYETLEN CI-workflow sem futtatja

`.github/workflows/ml-train.yml` csak a `test_pipeline.py`-t futtatja
(`python -m pytest test_pipeline.py -q`), a `router-ci.yml` a `tools/tests`-et.
A `.github/**` a kör TILOS zónája, tehát a workflow bővítése **H3** volna. A
Python-oldali cella mércéje ezért lokális + review-ban reprodukált; a
**CI-oldali** mérce a Dart-őr.

### 6. A Dart-őrnek a tesztfájlban kell élnie

A kör `allowed_paths`-a sem `lib/`-et, sem `tool/`-t nem tartalmaz, ezért a
manifest-validátor nem importálható könyvtárból. Ugyanez a helyzet mérve és
elfogadva az E14-R18-ban ([ADR 0517](0517-streaming-joint-onset-direction-prototype.md)
D8, `test/tooling/joint_io_schema_test.dart`).

### 7. Egyetlen fán kívüli őr sem sorolja fel a kör új fájljait

Mérve: `evaluation/recognition/fixtures/**`-ra és `docs/eval/**`-ra csak
NÉVSZERINTI hivatkozások vannak (`joint_io_schema_test.dart`,
`recognition_baseline_manifest_test.dart`,
`reference_model_licence_guard_test.dart`); `ml/` alatti `.json`-t egyetlen
könyvtár-bejáró őr sem enumerál (`check_assets_test.dart`,
`repository_policy_test.dart`, `production_readiness_test.dart` — egyik sem
listázza a valós fát ezeken az útvonalakon). A
`tools/tests/test_pipeline_throughput.py` útvonal-listái szintetikus
fixture-ök, nem valós-fa enumeráció. A kör új fájljai tehát a listán KÍVÜL
semmit nem visznek pirosra (L164 osztálya kizárva).

### 8. A címke-transzponálás osztály-matematikája MÁR MERGE-ELVE VAN

`ml/chords/labels.py::transpose_class` és `ml/chords/augment.py::_transpose_labels`
/ `transpose_window` egész-félhangos, címke-transzponáló augmentációt szállít a
25-osztályos majmin térben (`0 = N.C.` invariáns, dúr/moll csoport mod 12
gördül), és a `.github/workflows/chord-train.yml` a `chords/test_augment.py`-vel
CI-ban futtatja. A chord-track a CQT-tengelyen transzponál
(`BINS_PER_SEMITONE = 2`, zero-fill, nem `np.roll`) `max_semi=5`-tel — más
közeg, más korlát, mint ennek a körnek a PCM/varispeed útja.

Az akkord-címke a strum-adat-úton is JELEN VAN:
`ml/klangio.py::parse_strums` a `.strums` harmadik oszlopát akkord-címkeként
olvassa, a `windows_for_recording` viszont eldobja (`_chord`). A `klangio.py`
tilos zóna, tehát a bekötés nem ennek a körnek a dolga — de a §5.1 emiatt nem
elméleti.

### 9. Az `ml/honest_results.json` gitignore-olt

`ml/.gitignore:14`. A 2. és 3. pont számai tehát **doboz-lokálisak**, a repóból
nem ellenőrizhetők.

## Döntés

### D1 — A címke-transzponáló pitch shift EGÉSZ félhangos, és külön belépési pont

A címkét mozgató augmentáció bemenete **egész** félhang (`int`), és a kimenete
a transzponált címkével együtt utazik. A meglévő, folytonos
`augment.py::augment_pcm` viselkedése **bitre változatlan** marad (a brief §9
regressziós követelménye) — az új út additív. Nem elfogadható a „a
direction-fejnek úgyis mindegy" érvelés: a manifest egy ADATKÉSZLETET ír le,
nem egy fejet.

### D2 — Nem-egész félhang a címke-transzponáló úton típusos hiba

Törtérték nem kerekítődik csendben. A kerekítés hazugsággá tenné a manifestet
(„±3 félhang", miközben az audio 3,4-gyel tolódott).

### D3 — A ±6 félhangos tartomány határa INKLUZÍV

`|semitones| <= 6` elfogadott, `|semitones| >= 7` típusos hiba. A ±6 a Murgul
et al. (ISMIR-2025, arXiv:2508.07973) ablation-optimuma, amit az
`ml/augment.py` fejléce már idéz — a határ ide TARTOZIK, nem kizáró.

### D4 — Minden transzformáció seedelt és kikapcsolható; kikapcsolva bitazonos

Seed nélküli véletlen tilos. Minden transzformációnak van `enabled`
kapcsolója, és ha MINDEN kapcsoló hamis, a kimenet **bitre azonos** a nyers
bemenettel (nem „közel azonos", nem toleranciás) — ez a különbség a
kikapcsolható és a kikapcsolhatónak MONDOTT recept között.

### D5 — A manifest a TÉNYLEGESEN futott halmazt írja le, a determinizmus a szállított úton mérve

A manifest kötelező mezői: `seed`, a transzformációk listája
(`name` + `enabled` + paraméterek), és az osztály-arányok
(down / up / no-strum, illetve akkord-osztályok). Hiányzó kötelező mező →
típusos hiba a Python validátorban **és** a Dart-őrben. A determinizmus-cellák
a SZÁLLÍTOTT generáló belépési ponton keresztül mérnek, nem kézzel összerakott
dict-en (L631).

### D6 — „nem mért" ≠ 0, és „nem mért" SOHA nem elfogadás

Az ablation-riport minden transzformáció-sora vagy egy MÉRT unseen-player /
unseen-device split-eredményt hordoz, vagy a literális `"nem mért"` értéket a
reprodukáló paranccsal és a mért költséggel együtt. Numerikus `0` hiányzó
mérés helyén tilos ([ADR 0509](0509-grouped-recognition-evaluation-and-leakage-protection.md)
`null` ≠ `0` szabályának átvitele).

Ebből következik a manifest `status` mezője, három megengedett értékkel:

| `status` | Mikor |
|---|---|
| `accepted` | van MÉRT sor, és legalább egy unseen-player VAGY unseen-device split JAVUL, és egyik sem romlik a jelentett hibahatáron túl |
| `candidate` | a sor `"nem mért"` — a transzformáció a receptben SZEREPELHET, de elfogadottnak NEM nyilvánítható |
| `rejected` | van MÉRT sor, és az nem javul (vagy romlik) |

Az `accepted` státusz `"nem mért"` sor mellett **típusos hiba** — ezt a
Dart-őr és a Python validátor is méri. Ez a kör anti-reward-hacking őre: a
zöld gate nem tehet elfogadottá egy le nem mért transzformációt.

### D7 — A ma szállított összetett recept `rejected`, mert a MÉRÉS ezt mondja

A fenti 2. pont két LOGO-száma alapján az r173 összetett kezelés (`pitch±6
varispeed + reverb + mic-sim + gain/noise`, `n_aug=2`, `AUG_REG`) sora
`rejected`, a `logo` ↔ `logo_aug` különbséggel és a regularizációs konfund
kimondásával együtt. A romló subgroup nem tűnhet el a riportból, és nem
kaphat automatikus elfogadást (a brief §5.4).

### D8 — Az osztály-kiegyensúlyozás nem töröl valós adatot

A kiegyensúlyozás kizárólag súlyoz vagy (újra)mintavételez; valós felvétel
eldobása tilos. A manifest a kiinduló ÉS a kiegyensúlyozott arányt is rögzíti,
hogy a torzítás mértéke látható legyen.

### D9 — A kör a tanító adat-utat érinti, a modellt és a súlyokat nem

A modell-architektúra, a szállított `assets/ml/**` súlyok és a DSP-konstansok
változatlanok. A recept VÉGLEGESÍTÉSE (mely transzformáció marad benne) a
mért ablationnel együtt az `E14-R20` dolga; ez a kör a szerződést, a
mérőeszközt és az őröket szállítja.

### D10 — Az osztály-matematika a merge-elt forrásból jön, nem újraírásból

A címke-transzponálás osztály-logikája **kizárólag** a merge-elt
`ml/chords/labels.py::transpose_class`-ból származhat: importált, read-only
függőség. Egy második, párhuzamos akkord-osztály-logika a fában a
[L164](../LESSONS.md#l164) és az E14-R15 „második metrika-fájl mellette"
hibaosztálya — MAJOR lelet. Az `ml/chords/**` fájljait a kör nem módosítja.

A két út félhang-korlátja szándékosan KÜLÖNBÖZIK, és a manifestnek meg kell
mondania, melyik melyikre vonatkozik: CQT/chord-track `max_semi = 5`
(biztonságos zero-fill), PCM/varispeed-track `|semitones| <= 6` (ISMIR-optimum,
D3).

### D11 — Doboz-lokális szám nem állítható repo-szintűnek

Az `ml/honest_results.json` gitignore-olt, ezért a riport a belőle idézett
számokat mérés-forrással és reprodukáló paranccsal, **doboz-lokálisként**
jelöli. Egy „lásd `ml/honest_results.json`" hivatkozás önmagában, a
gitignore-oltság kimondása nélkül, félrevezető.

## Következmények

- **Pozitív:** az augmentáció innentől auditálható artefaktum (seed +
  manifest + kapcsolók), a hiányzó mérés láthatóan hiányzik, és a mai,
  MÉRHETŐEN nem javító recept nem tud csendben „bevált gyakorlatként"
  továbbélni.
- **Ár:** a per-transzformációs ablation számai ebben a körben `"nem mért"`
  maradnak; a receptet nem ez a kör zárja le.
- **Kockázat:** az `augment.py` átírásának kísértése. A meglévő
  transzformációk viselkedése nem változhat — regressziós cella kötelező
  (brief §9).

## Elutasított alternatívák

- **A címke-transzponálás elhagyása („a direction-fejnek mindegy"):** a
  manifest adatkészletet ír le; egy akkord-fej ugyanezt az adatot fogyasztja.
- **Törtérték kerekítése egész félhangra:** a manifest állítása és az audio
  szétcsúszna.
- **Exkluzív felső határ (`< 6`):** kizárná a hivatkozott ISMIR-optimumot.
- **Hiányzó ablation-mérés `0`-ként jelentése:** a `0` mért rosszat állít, a
  hiány nem az ([ADR 0509](0509-grouped-recognition-evaluation-and-leakage-protection.md)).
- **A per-transzformációs tréning erőltetése ebben a körben:** mérve 3,0 óra
  KEZELÉSENKÉNT a 3600 s-os burkoló-korláttal szemben — halt lenne, nem mérés.
- **A `logo_aug` romlásának elhallgatása vagy „kevesebb epoch" magyarázata:**
  a szám mérve van; a riport tartozik vele.
- **A `transpose_class` újraírása a PCM-oldalon:** két, egymástól függetlenül
  romolható akkord-osztály-logika ugyanabban a fában (L164, E14-R15).
- **A chord-track `max_semi=5` korlátjának ráerőltetése a PCM-útra (vagy
  fordítva):** a zero-fill CQT-korlát és a varispeed ISMIR-optimum két
  különböző közeg két különböző korlátja; az összemosás mérés nélküli
  szigorítás vagy lazítás lenne.
