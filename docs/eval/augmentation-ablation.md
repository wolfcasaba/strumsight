# Augmentáció ablation-riport — becsületes „nem mért" szerződés (E14-R19, ADR 0525)

## Amit ez a kör szállít

Ez a dokumentum **nem** egy teljes leave-one-transform-out ablation eredménye
— egy ilyen mérés ebben a körben **bizonyítottan nem futtatható** (lásd
alább, „Miért nem mérünk most"). Amit szállít: a `ml/augmentation_manifest.json`
(és a CI-fixture, `evaluation/recognition/fixtures/
augmentation_manifest_sample.json` — a két fájlt gépi cella pinneli egymáshoz
mindkét oldalon, review E14-R19 MAJOR-1) minden egyes transzformáció-sorára
kimondja, hogy **MÉRT** javulás/romlás áll mögötte, vagy a literális
**„nem mért"** érték a reprodukáló paranccsal és egy **költség-alappal**
együtt (ADR 0525 D6) — numerikus `0` egyik esetben sem szerepelhet, és „nem
mért" sor **soha** nem kaphat `accepted` státuszt, és **soha** nem lehet
`enabled: true` egy `rejected` sorral párosítva (review E14-R19 MAJOR-2).
Mindkét szabályt gépi cella méri, Python (`ml/augment.py::validate_manifest`)
**és** Dart (`test/tooling/augmentation_manifest_test.dart`) oldalon is.

A manifest emellett egy **`provenance`** blokkot is hordoz
(`generatedFrom`/`datasetSource`/`classRatiosSource`, kötelező mindkét
validátorban) — kimondja, MELYIK konfigurációt írja le (a szállított
`ml.augment.DEFAULT_TRANSFORM_CONFIG` alapot: `pitch_shift`/`reverb`/
`mic_sim`/`gain`/`add_noise` bekapcsolva, `device_response`/`compression`/
`traffic_noise`/`transient_burst` kikapcsolva), és — mert az alábbi
`classRatios` táblázat számai **nem mértek** — a `classRatiosSource` mezőben
kimondottan `"illustrative — not measured"`-ként jelöli őket (review E14-R19
MAJOR-2). Ugyanezért a `composite_recipe_r173` sor `enabled` mezője is
`false`: egy mérten romló (`rejected`) sor nem lehet a „ténylegesen futó"
halmaz tagja — ezt mindkét validátor gépi cellával kényszeríti ki.

**Költség-mező elnevezés (review E14-R19 MINOR-1).** A `measuredCostSeconds`
mezőnév egy per-transzformációs MÉRT költséget sugallna; mivel a 10 „nem
mért" sor mindegyike ugyanazt az EGYETLEN mért adatpontot (10 769,7 s) idézi
reprezentatív alapként, ezek a sorok most a `costBasisSeconds` +
`costBasisSource` mezőpárt hordozzák (nem `measuredCostSeconds`-t) — a
`measuredCostSeconds` mezőnév ezután KIZÁRÓLAG a ténylegesen mért
`composite_recipe_r173` soron szerepel, ahol ez a szám a TÉNYLEGES, ehhez a
pontos futáshoz mért költség.

## Miért nem mérünk most egyetlen ÚJ transzformációt sem

`ml/honest_results.json::_timing` (r173, doboz-lokális — **gitignore-olt**,
`ml/.gitignore:14`, tehát a repóból nem ellenőrizhető, csak ebben a
dokumentumban idézett szám) szerint az EGYETLEN mért összetett kezelés-pár
(`logo` vs. `logo_aug`, 2 konfiguráció × 3 fold) **10 769,7 másodpercet
(≈ 3,0 óra)** vett igénybe. Egy hét transzformációra kiterjedő
leave-one-transform-out ablation ennek nagyságrendileg **20+ órás**
többszöröse volna, miközben az implementer-burkoló abszolút időkorlátja
**3600 s** (`docs/execution/engine-registry.tsv`, `sonnet-impl` sor). A mérés
tehát nem hanyagságból marad el — **bizonyítottan nem fér bele** ebbe a
körbe. A recept VÉGLEGESÍTÉSE (melyik transzformáció marad benne) a mért
ablationnel együtt az `E14-R20` dolga (ADR 0525 D9).

## Transzformáció-soronkénti státusz

Minden alábbi sor a `ml/augmentation_manifest.json`-ban ténylegesen szereplő
bejegyzés tükre. Az `Enabled` oszlop a manifest `provenance.generatedFrom`
által megnevezett alapkonfigurációt (`ml.augment.DEFAULT_TRANSFORM_CONFIG`)
tükrözi — nem egy tetszőleges összes-bekapcsolva receptet (review E14-R19
MAJOR-2); a `composite_recipe_r173` sor `enabled: false`, mert a státusza
`rejected` (egy mérten romló sor nem lehet a „ténylegesen futó" halmaz
tagja). A `reproCommand` oszlop az a parancs, ami — ha lefutna — mérné az
adott transzformáció ÖNMAGÁBAN vett hatását (leave-one-transform-out,
`ml/honest_eval.py` egy ma még NEM létező, egy-transzformációs szekciójával);
a `költség-alap` minden „nem mért" sorra a fenti, EGYETLEN mért adatpontot
(10 769,7 s/kezelés-pár) idézi mint reprezentatív alapot (`costBasisSeconds`
+ `costBasisSource`, review E14-R19 MINOR-1), mert ez az egyetlen valós
mérés, ami a nagyságrendet megalapozza — ez NEM ugyanaz, mint a
`composite_recipe_r173` sor `measuredCostSeconds` mezője, ami a TÉNYLEGES,
ehhez a pontos futáshoz mért költség.

| Transzformáció | Domén | Enabled | Státusz | Mérés | Repro parancs | Költség-alap |
|---|---|---|---|---|---|---|
| `pitch_shift_continuous` | PCM/varispeed, irány-only (meglévő, változatlan) | igaz | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_pitch_shift_continuous_only` — a per-transzformációs szekció még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `pitch_shift_label_transpose` | PCM/varispeed, akkord-címke-tudatos (ÚJ, E14-R19) | igaz | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_pitch_shift_label_transpose_only` — még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `room_ir_reverb` | szoba-IR konvolúció (meglévő, most kapcsolható) | igaz | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_room_ir_reverb_only` — még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `gain` | globális erősítés (meglévő, most kapcsolható) | igaz | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_gain_only` — még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `device_response` | névvel ellátott eszköz-frekvenciaválasz (ÚJ, E14-R19, a `mic_sim` szűrőjét használja fel) | **hamis** (`DEFAULT_TRANSFORM_CONFIG` kikapcsolva szállítja) | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_device_response_only` — még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `mic_sim` | folytonos véletlen EQ-tilt + sávhatárolás (meglévő, most kapcsolható) | igaz | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_mic_sim_only` — még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `compression` | RMS-burkológörbés dinamika-kompresszor (ÚJ, E14-R19) | **hamis** (`DEFAULT_TRANSFORM_CONFIG` kikapcsolva szállítja) | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_compression_only` — még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `additive_snr_noise` | fehérzaj célzott SNR-en (meglévő, most kapcsolható) | igaz | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_additive_snr_noise_only` — még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `traffic_ambient_noise` | 1/f-szerű, forgalom/nappali-zaj-jellegű zaj célzott SNR-en (ÚJ, E14-R19) | **hamis** (`DEFAULT_TRANSFORM_CONFIG` kikapcsolva szállítja) | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_traffic_ambient_noise_only` — még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `transient_burst` | fret-zaj/pengetés-kattanás/koppintás-jellegű tranziens zajburst (ÚJ, E14-R19) | **hamis** (`DEFAULT_TRANSFORM_CONFIG` kikapcsolva szállítja) | `candidate` | „nem mért" | `python3 ml/honest_eval.py logo logo_transient_burst_only` — még NEM létezik | 10 769,7 s/kezelés-pár (r173, doboz-lokális) |
| `composite_recipe_r173` | a MA szállított, összetett recept (pitch ±6 varispeed + reverb + mic-sim + gain/zaj, `n_aug=2`, `AUG_REG`) | **hamis** (a `rejected` státusz miatt, ADR 0525 D6/D9) | **`rejected`** | **MÉRT** (lásd lent) | `python3 ml/honest_eval.py logo logo_aug` | 10 769,7 s — ez a `measuredCostSeconds` mezőben a TÉNYLEGES, ehhez a pontos futáshoz mért érték (nem költség-alap) |

## A ma szállított összetett recept — MÉRT, és `rejected`

`ml/honest_results.json` (r173, doboz-lokális, **gitignore-olt** —
`ml/.gitignore:14`, tehát a repóból nem ellenőrizhető, a számok itt
idézve reprodukálhatók) mindkét leave-one-guitarist-out (unseen-player)
spliten tartalmazza a tiszta és az augmentált+regularizált kezelést:

| Split (unseen player, LOGO) | tiszta `logo` | `logo_aug` (r173 recept) | különbség |
|---|---|---|---|
| `batch` | **0,7066** ± 0,0165 | 0,6985 ± 0,0093 | **−0,0081** |
| `live70` | **0,6061** ± 0,0548 | 0,5289 ± 0,0952 | **−0,0772** |

Mindkét irány **lefelé** mutat — a brief §5.3 elfogadási feltétele
(„legalább egy unseen-player VAGY unseen-device split javul") a MA szállított
recepttel **nem teljesül**. A manifest ezt a sort `rejected` státusszal
rögzíti (`ml/augment.py::validate_manifest` és a Dart-őr mindkettő megköveteli,
hogy egy MÉRT, romló sor ne maradhasson `accepted`).

**Regularizációs konfund (ADR 0525 D7).** A `logo_aug` kezelés az
augmentáció MELLETT regularizációt is bekapcsol
(`ml/honest_eval.py::AUG_REG`: `dropout=0.25`, `rec_dropout=0.15`, `l2=1e-4`).
A fenti két szám tehát **két hatás összege** — az augmentáció ÉS a
regularizáció együttes különbsége a tiszta baseline-tól —, és emiatt **nem
használható fel** egyetlen EGYEDI transzformáció (pl. csak a pitch-shift, vagy
csak a reverb) elfogadására vagy elvetésére. Ez a kör mérési korlátja, nem egy
elhallgatott hiba: a manifest `composite_recipe_r173.measured.confound` mezője
ugyanezt a mondatot rögzíti gépileg olvasható formában.

## Doboz-lokális szám, nem repo-szintű (ADR 0525 D11)

Minden e dokumentumban idézett szám (`0,7066`, `0,6985`, `0,6061`, `0,5289`,
`10 769,7 s`) az `ml/honest_results.json` r173 futásából származik. Ez a fájl
**gitignore-olt** (`ml/.gitignore:14`) — a repóból **nem** tölthető vissza és
nem ellenőrizhető közvetlenül; a fenti táblázatok **r173-as, doboz-lokális
mérésként** idézik, a reprodukáló paranccsal együtt, ahogy az ADR 0525 D11
előírja. Aki reprodukálni akarja: `python3 ml/honest_eval.py logo logo_aug`
egy olyan dobozon, ahol a Klangio GST-MM korpusz és egy TensorFlow interpreter
elérhető (`.github/workflows/ml-train.yml` az x86 CI-futó megfelelője).

## Osztály-kiegyensúlyozás — nem törli a valós adatot (ADR 0525 D8)

A `ml/augment.py::balance_indices` kizárólag a KISEBBSÉGI osztályokat
mintavételezi vissza (véletlenszerű, ismétléses húzással) a TÖBBSÉGI osztály
méretére — minden eredeti index legalább egyszer megmarad a kimenetben (soha
nem törlődik valós felvétel). A manifest `classRatios` blokkja mindkét fázist
rögzíti (kiinduló ÉS kiegyensúlyozott), irány- (down/up/noStrum) és
akkord-csoport (N.C./major/minor) szinten egyaránt; a `balancing.dropsRealData`
mező mindig `false` — ezt mindkét oldali validátor (Python és Dart) gépi
cellával kényszeríti ki.

**A `classRatios` számai illusztratívak, NEM mértek (review E14-R19
MAJOR-2).** A `down 0.42/up 0.40/noStrum 0.18` és az `N.C. 0.35/major
0.44/minor 0.21` kerek, kézzel választott számok — nincs mögöttük repo-lokális
osztály-számlálási futás. A kör szállít egy `ml.augment.class_ratios()`
függvényt, ami egy VALÓS címke-tömbből tényleges arányt számol, de ez a
manifest generálásakor nem futott adatkészleten. A manifest
`provenance.classRatiosSource` mezője ezt kimondottan `"illustrative — not
measured"`-ként rögzíti, és mindkét validátor (Python és Dart) megköveteli
ennek a mezőnek a jelenlétét — a `classRatios` blokk tehát a KÍVÁNT, kerek
kiegyensúlyozott célt szemlélteti (`0.3333`/`0.3334` egyenlő harmadok), nem
egy mért kiinduló/kiegyensúlyozott állapotpárt.

## Két KÜLÖNBÖZŐ félhang-korlát — nem ugyanaz a szám (R11)

A manifest `pitchShiftLimits` blokkja explicit módon két, egymástól FÜGGETLEN
korlátot rögzít, hogy a kettő soha ne mosódjon össze:

| Korlát | Érték | Közeg | Forrás |
|---|---|---|---|
| `pcmVarispeedMaxSemitones` | **6** | PCM/varispeed (ez a kör, direction + label-transpose út egyaránt) | ISMIR-2025 Murgul et al. ablation-optimum (arXiv:2508.07973) |
| `cqtChordTrackMaxSemitones` | **5** | CQT/akkord-track (MÁR MERGE-ELT, `ml/chords/augment.py::augment_windows`) | a 144-sávos CQT frekvencia-tengely biztonságos zero-fill tartománya |

Mindkét oldali validátor (Python és Dart) LITERÁLISAN ellenőrzi mindkét
értéket, és elutasítja, ha a kettő összemosódna (pl. mindkettő 6-ra állítva).

## Az akkord-címke-transzponálás — MERGE-ELT osztály-matematika, ÚJ PCM-út

A `ml/augment.py::transpose_pcm_and_chord_labels` a MÁR MERGE-ELT
`ml/chords/labels.py::transpose_class`-t hívja a címke-aritmetikára — ez a
kör NEM ír újra akkord-osztály-logikát (R11, ADR 0525 D10). A pitch-shift
bemenete **egész** félhang; törtérték `TypeError`, a tartomány határa
(`|semitones| <= 6`) **inkluzív** — mindkettőt a `ml/test_augmentation_labels.py`
méri (lásd a kör §10 handoffját a falszifikációs cellákért).
